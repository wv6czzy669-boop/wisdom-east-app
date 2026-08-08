import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../persistence/file_protection_bridge.dart';
import '../persistence/persistence_operation_coordinator.dart';
import '../sync/sync_change.dart';
import '../utils/kept_diagnostics.dart';
import 'account_sync_state.dart';
import 'incoming_batch_checkpoint.dart';
import 'outbox_mutation_retirement.dart';
import 'persisted_outbox_mutation.dart';
import 'sync_persistence_envelope.dart';
import 'sync_persistence_store.dart';

/// Build 26 Phase 4D-1: protected, atomic, file-backed
/// [SyncPersistenceStore] implementation.
///
/// Stores the complete [SyncPersistenceEnvelope] as one JSON file,
/// `east_sync_state_v1.json`, inside its own `east_sync_state` directory
/// beneath the platform's Application Support directory -- **deliberately
/// separate from** `east_kept_state`'s directory and file
/// (`ProtectedFileKeptStateStore`). This phase's own instruction is explicit
/// that sync-state must never live inside the existing authoritative Kept
/// envelope and must never alter its format; see
/// `sync_persistence_envelope.dart`'s doc comment for the fuller note on why
/// this is a deliberate, disclosed refinement of ADR-007's original sketch.
///
/// The atomic-write algorithm below (temp file, protect+verify, backup the
/// existing final, atomic rename, protect+verify the final, restore the
/// backup on any post-rename failure) intentionally mirrors
/// `ProtectedFileKeptStateStore`'s own -- the *tested primitives*
/// ([FileProtectionBridge], [PersistenceOperationCoordinator]) are reused
/// unmodified, but the control flow itself is necessarily re-implemented
/// here for [SyncPersistenceEnvelope] rather than extracted into a shared
/// generic base class, since factoring one out would require modifying
/// `ProtectedFileKeptStateStore` -- out of scope for this phase, and against
/// the standing instruction not to refactor unrelated Kept-storage code
/// broadly. This is a disclosed trade-off, not an oversight.
///
/// **Fingerprint privacy:** the file path this store reads and writes never
/// contains an account fingerprint -- fingerprint-scoping happens entirely
/// inside the JSON content (`SyncPersistenceEnvelope.accounts`), never in a
/// path. Every diagnostic message this store logs (via `keptDiagnostic`,
/// gated on `kDebugMode` exactly like the existing Kept store) names only
/// the stage and, at most, a fingerprint-free path or an aggregate count --
/// never a fingerprint, a server token, a record name, a mutation id, or any
/// raw JSON.
///
/// All operations on one instance are serialized through
/// [PersistenceOperationCoordinator] under one resource key ([resourceKey]),
/// distinct from [ProtectedFileKeptStateStore.resourceKey] -- the two stores
/// share the coordinator type but never a resource key, a directory, or a
/// file.
final class ProtectedSyncPersistenceStore implements SyncPersistenceStore {
  ProtectedSyncPersistenceStore({
    Future<Directory> Function()? rootDirectoryProvider,
    FileProtectionBridge? fileProtectionBridge,
    String Function()? tokenFactory,
    DateTime Function()? clock,
    PersistenceOperationCoordinator? operationCoordinator,
  })  : _rootDirectoryProvider =
            rootDirectoryProvider ?? getApplicationSupportDirectory,
        _fileProtectionBridge =
            fileProtectionBridge ?? const MethodChannelFileProtectionBridge(),
        _tokenFactory = tokenFactory ?? (() => const Uuid().v4()),
        _clock = clock ?? DateTime.now,
        _coordinator =
            operationCoordinator ?? PersistenceOperationCoordinator();

  static const String resourceKey = 'protected_sync_state_file';
  static const String _directoryName = 'east_sync_state';
  static const String _baseName = 'east_sync_state_v1';

  final Future<Directory> Function() _rootDirectoryProvider;
  final FileProtectionBridge _fileProtectionBridge;
  final String Function() _tokenFactory;
  final DateTime Function() _clock;
  final PersistenceOperationCoordinator _coordinator;

  // -----------------------------------------------------------------------
  // Public SyncPersistenceStore API -- every method runs fully inside the
  // coordinator's exclusive slot for [resourceKey], so a load can never
  // observe a half-completed replace and two mutations can never interleave.
  // -----------------------------------------------------------------------

  @override
  Future<AccountSyncState?> loadAccountState(String accountFingerprint) {
    return _coordinator.runExclusive<AccountSyncState?>(
      resourceKey: resourceKey,
      operation: () async {
        final envelope = await _loadEnvelope();
        return envelope.accounts[accountFingerprint];
      },
    );
  }

  @override
  Future<void> replaceAccountState(
    String accountFingerprint,
    AccountSyncState state,
  ) {
    return _coordinator.runExclusive<void>(
      resourceKey: resourceKey,
      operation: () async {
        final envelope = await _loadEnvelope();
        await _replaceEnvelope(
          envelope.withAccount(accountFingerprint, state),
        );
      },
    );
  }

  @override
  Future<void> enqueueMutation(String accountFingerprint, SyncChange change) {
    return _coordinator.runExclusive<void>(
      resourceKey: resourceKey,
      operation: () async {
        final envelope = await _loadEnvelope();
        final current = envelope.accounts[accountFingerprint];

        if (current == null) {
          // No bucket yet: this enqueue is the explicit, non-fabricated
          // source of this account's dataEpoch -- never a default.
          final freshState = AccountSyncState(
            dataEpoch: change.projection.dataEpoch,
            outbox: [PersistedOutboxMutation(change: change)],
          );
          keptDiagnostic('sync-persistence-store: enqueue-creates-bucket');
          await _replaceEnvelope(
            envelope.withAccount(accountFingerprint, freshState),
          );
          return;
        }

        if (change.projection.dataEpoch != current.dataEpoch) {
          throw const MutationEpochMismatchException();
        }

        final mutationId = change.projection.mutationId;
        final recordName = change.projection.recordName;

        for (final entry in current.outbox) {
          if (entry.mutationId == mutationId) {
            if (entry.change.kind == change.kind &&
                entry.change.projection == change.projection) {
              // Exact repeat of an already-queued mutation -- idempotent
              // no-op.
              keptDiagnostic(
                'sync-persistence-store: enqueue-idempotent-noop',
              );
              return;
            }
            throw const ConflictingMutationIdentityException();
          }
        }

        // A different mutationId for the same deterministic record name
        // atomically supersedes the existing not-yet-sent entry, in place,
        // preserving that record's original queue position -- never
        // removed-then-appended, which would let a repeatedly-edited record
        // perpetually push itself to the back of the queue.
        final existingIndex = current.outbox.indexWhere(
          (entry) => entry.recordName == recordName,
        );

        final nextOutbox = List<PersistedOutboxMutation>.of(current.outbox);
        if (existingIndex == -1) {
          nextOutbox.add(PersistedOutboxMutation(change: change));
        } else {
          keptDiagnostic(
            'sync-persistence-store: enqueue-supersedes-pending-mutation',
          );
          nextOutbox[existingIndex] = PersistedOutboxMutation(change: change);
        }

        final nextState = current.copyWith(outbox: nextOutbox);
        await _replaceEnvelope(
          envelope.withAccount(accountFingerprint, nextState),
        );
      },
    );
  }

  @override
  Future<void> applyMutationOutcomes(
    String accountFingerprint, {
    Set<String> acknowledgedMutationIds = const {},
    Map<String, PersistedOutboxMutationStatus> updatedStatusByMutationId =
        const {},
  }) {
    return _coordinator.runExclusive<void>(
      resourceKey: resourceKey,
      operation: () async {
        final envelope = await _loadEnvelope();
        final current = envelope.accounts[accountFingerprint];
        if (current == null) return;

        final nextOutbox = <PersistedOutboxMutation>[];
        for (final entry in current.outbox) {
          if (acknowledgedMutationIds.contains(entry.mutationId)) continue;
          final newStatus = updatedStatusByMutationId[entry.mutationId];
          nextOutbox.add(newStatus == null
              ? entry
              : entry.copyWith(
                  status: newStatus,
                ));
        }

        final nextState = current.copyWith(outbox: nextOutbox);
        await _replaceEnvelope(
          envelope.withAccount(accountFingerprint, nextState),
        );
      },
    );
  }

  @override
  Future<List<PersistedOutboxMutation>> readPendingMutations(
    String accountFingerprint,
  ) {
    return _coordinator.runExclusive<List<PersistedOutboxMutation>>(
      resourceKey: resourceKey,
      operation: () async {
        final envelope = await _loadEnvelope();
        final current = envelope.accounts[accountFingerprint];
        if (current == null) return const <PersistedOutboxMutation>[];

        // The stored outbox list order *is* the deterministic order: a new
        // mutation is appended at the end (enqueueMutation), and a
        // supersession overwrites its predecessor's exact slot rather than
        // moving to the end -- so no re-sort happens here. Re-sorting by
        // `enqueuedAt` would silently defeat queue-position preservation,
        // since a superseding mutation's own `enqueuedAt` is newer than the
        // slot it occupies.
        return List.unmodifiable(current.outbox);
      },
    );
  }

  @override
  Future<void> replaceRecordSystemFields(
    String accountFingerprint,
    String recordName,
    String systemFields,
  ) {
    return _coordinator.runExclusive<void>(
      resourceKey: resourceKey,
      operation: () async {
        final envelope = await _loadEnvelope();
        final current = envelope.accounts[accountFingerprint];
        if (current == null) {
          throw const SyncPersistenceStoreException(
            'system-fields-no-account-state',
            'No sync state exists yet for this account; its dataEpoch must '
                'be established via enqueueMutation or replaceAccountState '
                'first -- this method never fabricates one.',
          );
        }
        final nextFields = Map<String, String>.from(current.recordSystemFields)
          ..[recordName] = systemFields;
        final nextState = current.copyWith(recordSystemFields: nextFields);
        await _replaceEnvelope(
          envelope.withAccount(accountFingerprint, nextState),
        );
      },
    );
  }

  @override
  Future<void> storeServerChangeToken(
    String accountFingerprint,
    String serverToken,
  ) {
    return _coordinator.runExclusive<void>(
      resourceKey: resourceKey,
      operation: () async {
        final envelope = await _loadEnvelope();
        final current = envelope.accounts[accountFingerprint];
        if (current == null) {
          throw const SyncPersistenceStoreException(
            'store-token-no-account-state',
            'No sync state exists yet for this account; its dataEpoch must '
                'be established via enqueueMutation or replaceAccountState '
                'first -- this method never fabricates one.',
          );
        }
        final nextState = current.copyWith(serverChangeToken: serverToken);
        await _replaceEnvelope(
          envelope.withAccount(accountFingerprint, nextState),
        );
      },
    );
  }

  @override
  Future<void> clearServerChangeToken(String accountFingerprint) {
    return _coordinator.runExclusive<void>(
      resourceKey: resourceKey,
      operation: () async {
        final envelope = await _loadEnvelope();
        final current = envelope.accounts[accountFingerprint];
        if (current == null) return;
        final nextState = current.copyWith(serverChangeToken: null);
        await _replaceEnvelope(
          envelope.withAccount(accountFingerprint, nextState),
        );
      },
    );
  }

  @override
  Future<void> clearAccountState(String accountFingerprint) {
    return _coordinator.runExclusive<void>(
      resourceKey: resourceKey,
      operation: () async {
        final envelope = await _loadEnvelope();
        await _replaceEnvelope(envelope.withAccountCleared(accountFingerprint));
      },
    );
  }

  @override
  Future<void> quarantineAccountState(String accountFingerprint) {
    return _coordinator.runExclusive<void>(
      resourceKey: resourceKey,
      operation: () async {
        final envelope = await _loadEnvelope();
        await _replaceEnvelope(
          envelope.withAccountQuarantined(accountFingerprint),
        );
      },
    );
  }

  // -----------------------------------------------------------------------
  // Build 26 Phase 4E-1: one atomic incoming-batch checkpoint. Every
  // business-rule failure is returned as a typed, non-`committed` result --
  // never thrown -- computed inside exactly one coordinator-serialized
  // read-modify-replace operation, so this never issues two separate
  // envelope writes (one for system fields, one for the token) the way
  // calling `replaceRecordSystemFields` then `storeServerChangeToken`
  // separately would.
  // -----------------------------------------------------------------------

  @override
  Future<CommitIncomingBatchCheckpointResult> commitIncomingBatchCheckpoint(
    CommitIncomingBatchCheckpointRequest request,
  ) async {
    final structuralFailure = _validateCheckpointRequestShape(request);
    if (structuralFailure != null) {
      return CommitIncomingBatchCheckpointResult(status: structuralFailure);
    }

    return _coordinator.runExclusive<CommitIncomingBatchCheckpointResult>(
      resourceKey: resourceKey,
      operation: () async {
        final envelope = await _loadEnvelope();
        final current = envelope.accounts[request.accountFingerprint];

        if (request.mode == IncomingCheckpointMode.bootstrapCreate) {
          return _commitBootstrapCreate(envelope, current, request);
        }
        return _commitExistingBucket(envelope, current, request);
      },
    );
  }

  Future<CommitIncomingBatchCheckpointResult> _commitBootstrapCreate(
    SyncPersistenceEnvelope envelope,
    AccountSyncState? current,
    CommitIncomingBatchCheckpointRequest request,
  ) async {
    if (current != null) {
      return const CommitIncomingBatchCheckpointResult(
        status: IncomingCheckpointStatus.bucketAlreadyExists,
      );
    }

    final expected =
        request.expectedBootstrapState ?? AccountBootstrapState.notStarted;
    if (expected != AccountBootstrapState.notStarted) {
      return const CommitIncomingBatchCheckpointResult(
        status: IncomingCheckpointStatus.bootstrapStateMismatch,
      );
    }
    final nextBootstrapState =
        request.nextBootstrapState ?? AccountBootstrapState.notStarted;
    if (!isValidBootstrapTransition(
      AccountBootstrapState.notStarted,
      nextBootstrapState,
    )) {
      return const CommitIncomingBatchCheckpointResult(
        status: IncomingCheckpointStatus.invalidBootstrapTransition,
      );
    }

    final mergedFields = _mergeSystemFields(
      const {},
      request.recordSystemFieldsUpdates,
    );

    final newState = AccountSyncState(
      dataEpoch: request.bootstrapTargetDataEpoch!,
      serverChangeToken: request.pendingServerChangeToken,
      recordSystemFields: mergedFields,
      bootstrapState: nextBootstrapState,
    );
    await _replaceEnvelope(
      envelope.withAccount(request.accountFingerprint, newState),
    );
    keptDiagnostic(
      'sync-persistence-store: incoming-checkpoint-bootstrap-create-ok '
      'systemFieldCount=${request.recordSystemFieldsUpdates.length}',
    );

    return CommitIncomingBatchCheckpointResult(
      status: IncomingCheckpointStatus.committed,
      systemFieldCount: request.recordSystemFieldsUpdates.length,
      bootstrapStateChanged:
          nextBootstrapState != AccountBootstrapState.notStarted,
      tokenChanged: true,
    );
  }

  Future<CommitIncomingBatchCheckpointResult> _commitExistingBucket(
    SyncPersistenceEnvelope envelope,
    AccountSyncState? current,
    CommitIncomingBatchCheckpointRequest request,
  ) async {
    if (current == null) {
      return const CommitIncomingBatchCheckpointResult(
        status: IncomingCheckpointStatus.bucketMissing,
      );
    }
    if (current.dataEpoch != request.expectedCurrentDataEpoch) {
      return const CommitIncomingBatchCheckpointResult(
        status: IncomingCheckpointStatus.dataEpochMismatch,
      );
    }

    // Idempotent-retry shortcut: a caller that crashed or dropped a
    // response after a checkpoint durably committed cannot always tell
    // whether its prior identical request already succeeded. If the bucket
    // already reflects exactly the state this request would produce (same
    // token, same bootstrap state, every requested system-fields entry
    // already holding the exact requested value), this call is a genuine
    // no-op repeat -- report it as committed without a second envelope
    // write, rather than failing it on `expectedPreviousServerToken`, which
    // necessarily no longer matches once the first attempt already
    // advanced the token. This mirrors `enqueueMutation`'s own
    // same-content idempotent-repeat rule.
    if (_alreadyMatchesCheckpointTarget(current, request)) {
      return const CommitIncomingBatchCheckpointResult(
        status: IncomingCheckpointStatus.committed,
        systemFieldCount: 0,
        bootstrapStateChanged: false,
        tokenChanged: false,
      );
    }

    if (current.serverChangeToken != request.expectedPreviousServerToken) {
      return const CommitIncomingBatchCheckpointResult(
        status: IncomingCheckpointStatus.previousTokenMismatch,
      );
    }
    if (request.expectedBootstrapState != null &&
        current.bootstrapState != request.expectedBootstrapState) {
      return const CommitIncomingBatchCheckpointResult(
        status: IncomingCheckpointStatus.bootstrapStateMismatch,
      );
    }
    final nextBootstrapState =
        request.nextBootstrapState ?? current.bootstrapState;
    if (!isValidBootstrapTransition(
        current.bootstrapState, nextBootstrapState)) {
      return const CommitIncomingBatchCheckpointResult(
        status: IncomingCheckpointStatus.invalidBootstrapTransition,
      );
    }

    final mergedFields = _mergeSystemFields(
      current.recordSystemFields,
      request.recordSystemFieldsUpdates,
    );

    final tokenChanged =
        current.serverChangeToken != request.pendingServerChangeToken;
    final bootstrapStateChanged = nextBootstrapState != current.bootstrapState;

    final newState = current.copyWith(
      serverChangeToken: request.pendingServerChangeToken,
      recordSystemFields: mergedFields,
      bootstrapState: nextBootstrapState,
    );
    await _replaceEnvelope(
      envelope.withAccount(request.accountFingerprint, newState),
    );
    keptDiagnostic(
      'sync-persistence-store: incoming-checkpoint-existing-bucket-ok '
      'systemFieldCount=${request.recordSystemFieldsUpdates.length}',
    );

    return CommitIncomingBatchCheckpointResult(
      status: IncomingCheckpointStatus.committed,
      systemFieldCount: request.recordSystemFieldsUpdates.length,
      bootstrapStateChanged: bootstrapStateChanged,
      tokenChanged: tokenChanged,
    );
  }

  /// Pure, bucket-independent request-shape validation -- runs before the
  /// envelope is ever loaded. Returns `null` when the request shape itself
  /// is valid (bucket-dependent checks still follow inside the coordinator
  /// block); otherwise returns the exact [IncomingCheckpointStatus] failure
  /// this malformed request represents.
  IncomingCheckpointStatus? _validateCheckpointRequestShape(
    CommitIncomingBatchCheckpointRequest request,
  ) {
    if (!looksLikeOpaqueBase64(request.pendingServerChangeToken)) {
      return IncomingCheckpointStatus.invalidRequest;
    }

    switch (request.mode) {
      case IncomingCheckpointMode.existingBucket:
        if (request.expectedCurrentDataEpoch == null) {
          return IncomingCheckpointStatus.invalidRequest;
        }
        if (request.bootstrapTargetDataEpoch != null) {
          return IncomingCheckpointStatus.invalidRequest;
        }
      case IncomingCheckpointMode.bootstrapCreate:
        if (request.expectedCurrentDataEpoch != null ||
            request.expectedPreviousServerToken != null) {
          return IncomingCheckpointStatus.invalidRequest;
        }
        if (request.bootstrapTargetDataEpoch == null) {
          return IncomingCheckpointStatus.invalidRequest;
        }
    }

    if (request.nextBootstrapState != null &&
        request.expectedBootstrapState == null) {
      return IncomingCheckpointStatus.invalidRequest;
    }

    final seenRecordNames = <String>{};
    for (final update in request.recordSystemFieldsUpdates) {
      if (!seenRecordNames.add(update.recordName)) {
        return IncomingCheckpointStatus.duplicateRecordName;
      }
      if (!looksLikeKeptWisdomRecordName(update.recordName) ||
          !looksLikeOpaqueBase64(update.systemFields)) {
        return IncomingCheckpointStatus.invalidRecordSystemFields;
      }
    }

    return null;
  }

  /// Whether [current] already exactly equals the post-state [request]
  /// would produce, i.e. this call would be a genuine no-op repeat of an
  /// already-durable checkpoint. See the call site's doc comment.
  bool _alreadyMatchesCheckpointTarget(
    AccountSyncState current,
    CommitIncomingBatchCheckpointRequest request,
  ) {
    if (current.serverChangeToken != request.pendingServerChangeToken) {
      return false;
    }
    final targetBootstrapState =
        request.nextBootstrapState ?? current.bootstrapState;
    if (current.bootstrapState != targetBootstrapState) return false;
    for (final update in request.recordSystemFieldsUpdates) {
      if (current.recordSystemFields[update.recordName] !=
          update.systemFields) {
        return false;
      }
    }
    return true;
  }

  Map<String, String> _mergeSystemFields(
    Map<String, String> existing,
    List<IncomingRecordSystemFieldsUpdate> updates,
  ) {
    final merged = Map<String, String>.from(existing);
    for (final update in updates) {
      merged[update.recordName] = update.systemFields;
    }
    return merged;
  }

  // -----------------------------------------------------------------------
  // Build 26 Phase 4E-3b: one atomic, narrowly-guarded outbox-mutation
  // retirement -- never `applyMutationOutcomes` (see
  // `outbox_mutation_retirement.dart`'s own doc comment for why a remote
  // conflict loss is never represented as a CloudKit-acknowledged upload).
  // -----------------------------------------------------------------------

  @override
  Future<RetireOutboxMutationResult> retireOutboxMutationIfCurrent(
    RetireOutboxMutationRequest request,
  ) {
    return _coordinator.runExclusive<RetireOutboxMutationResult>(
      resourceKey: resourceKey,
      operation: () async {
        final envelope = await _loadEnvelope();
        final current = envelope.accounts[request.accountFingerprint];
        if (current == null) {
          return const RetireOutboxMutationResult(
            RetireOutboxMutationStatus.accountMissing,
          );
        }
        if (current.dataEpoch != request.expectedDataEpoch) {
          return const RetireOutboxMutationResult(
            RetireOutboxMutationStatus.dataEpochMismatch,
          );
        }

        final index = current.outbox.indexWhere(
          (entry) => entry.recordName == request.recordName,
        );
        if (index == -1) {
          return const RetireOutboxMutationResult(
            RetireOutboxMutationStatus.recordNotFound,
          );
        }
        if (current.outbox[index].mutationId != request.mutationId) {
          return const RetireOutboxMutationResult(
            RetireOutboxMutationStatus.mutationIdMismatch,
          );
        }

        final nextOutbox = List<PersistedOutboxMutation>.of(current.outbox)
          ..removeAt(index);
        final nextState = current.copyWith(outbox: nextOutbox);
        await _replaceEnvelope(
          envelope.withAccount(request.accountFingerprint, nextState),
        );
        keptDiagnostic(
          'sync-persistence-store: retire-outbox-mutation-if-current-ok',
        );
        return const RetireOutboxMutationResult(
          RetireOutboxMutationStatus.retired,
        );
      },
    );
  }

  // -----------------------------------------------------------------------
  // Load -- mirrors ProtectedFileKeptStateStore._load exactly in shape.
  // -----------------------------------------------------------------------

  Future<SyncPersistenceEnvelope> _loadEnvelope() async {
    final dirPath = await _resolveAndProtectDirectory();
    final finalPath = _finalPath(dirPath);
    final finalFile = File(finalPath);

    if (!await finalFile.exists()) {
      final recovered = await _recoverFromBackupIfFinalAbsent(dirPath);
      return recovered ?? SyncPersistenceEnvelope.empty();
    }

    final String raw;
    try {
      raw = await finalFile.readAsString();
    } catch (error) {
      throw SyncPersistenceStoreException(
        'load-read',
        'Could not read the authoritative sync-state file.',
        error,
      );
    }

    final SyncPersistenceEnvelope envelope;
    try {
      envelope = SyncPersistenceEnvelope.decodeString(raw);
    } catch (decodeError) {
      try {
        await _preserveCorrupt(dirPath, raw);
      } catch (preserveError) {
        throw SyncPersistenceStoreException(
          'load-decode',
          'The authoritative sync-state file is corrupt, and preserving it '
              'also failed.',
          preserveError,
        );
      }
      throw SyncPersistenceStoreException(
        'load-decode',
        'The authoritative sync-state file is corrupt; it has been '
            'preserved separately.',
        decodeError,
      );
    }

    try {
      await _fileProtectionBridge.protectAndVerifyComplete(finalPath);
    } catch (error) {
      // A raw FileProtectionException (or any other bridge/filesystem
      // exception) must never escape a public SyncPersistenceStore
      // operation. This is a pure load-time protection re-verify failure --
      // the file was already read and decoded successfully above -- so
      // nothing is deleted, reset, or rewritten here; the caller simply
      // never receives an envelope for this call.
      throw SyncPersistenceStoreException(
        'load-protect',
        'Could not verify protection of the authoritative sync-state file '
            'after reading it.',
        error,
      );
    }
    await _cleanupStaleTransactionFilesBestEffort(dirPath);

    return envelope;
  }

  Future<SyncPersistenceEnvelope?> _recoverFromBackupIfFinalAbsent(
    String dirPath,
  ) async {
    final List<File> backups;
    try {
      backups = await _listFilesWithPrefix(dirPath, '.$_baseName.backup-');
    } catch (error) {
      // A raw filesystem exception (e.g. the directory became unreadable
      // between _resolveAndProtectDirectory and here) must never escape a
      // public SyncPersistenceStore operation either. Nothing has been
      // read, moved, or written yet at this point, so there is nothing to
      // roll back -- the caller simply never receives an envelope for this
      // call.
      throw SyncPersistenceStoreException(
        'load-recover-list',
        'Could not list candidate backup files while recovering the '
            'authoritative sync-state file.',
        error,
      );
    }
    if (backups.isEmpty) return null;

    final withModifiedTime = <MapEntry<File, DateTime>>[];
    for (final file in backups) {
      try {
        final stat = await file.stat();
        withModifiedTime.add(MapEntry(file, stat.modified));
      } catch (_) {
        // Unreadable stat: treat as unusable, skip.
      }
    }
    withModifiedTime.sort((a, b) => b.value.compareTo(a.value));

    for (final entry in withModifiedTime) {
      final backupFile = entry.key;

      final String raw;
      try {
        raw = await backupFile.readAsString();
      } catch (_) {
        continue;
      }

      final SyncPersistenceEnvelope envelope;
      try {
        envelope = SyncPersistenceEnvelope.decodeString(raw);
      } catch (_) {
        continue;
      }

      // From here on, `backupFile` is a genuinely valid, selected
      // candidate. It must remain byte-for-byte untouched at its own
      // backup path until a restored authoritative final has been written,
      // protected, read back, and confirmed to decode to exactly this same
      // envelope. The backup is never renamed directly into the final
      // path -- a dedicated recovery-temporary file, inside this same
      // protected sync-state directory (never a system/cache temp
      // directory), is staged and verified first, and only *that* file is
      // ever renamed into place.
      final recoverToken = _tokenFactory();
      final recoveryTempPath = _recoveryTempPath(dirPath, recoverToken);
      final recoveryTempFile = File(recoveryTempPath);
      final finalPath = _finalPath(dirPath);
      final finalFile = File(finalPath);

      try {
        final raf = await recoveryTempFile.open(mode: FileMode.write);
        try {
          await raf.writeString(raw);
          await raf.flush();
        } finally {
          await raf.close();
        }
      } catch (error) {
        await _deleteBestEffort(recoveryTempFile);
        throw SyncPersistenceStoreException(
          'load-recover-write-temp',
          'Could not write the recovery temporary file while restoring '
              'from backup.',
          error,
        );
      }

      try {
        await _fileProtectionBridge.protectAndVerifyComplete(recoveryTempPath);
      } catch (error) {
        await _deleteBestEffort(recoveryTempFile);
        throw SyncPersistenceStoreException(
          'load-recover-protect-temp',
          'Could not protect the recovery temporary file while restoring '
              'from backup.',
          error,
        );
      }

      try {
        final rawRecoveryTemp = await recoveryTempFile.readAsString();
        final decodedRecoveryTemp =
            SyncPersistenceEnvelope.decodeString(rawRecoveryTemp);
        if (decodedRecoveryTemp != envelope) {
          throw const SyncPersistenceStoreException(
            'load-recover-verify-temp',
            'Recovery temporary file did not match the selected backup '
                'envelope.',
          );
        }
      } catch (error) {
        await _deleteBestEffort(recoveryTempFile);
        if (error is SyncPersistenceStoreException) rethrow;
        throw SyncPersistenceStoreException(
          'load-recover-verify-temp',
          'Could not verify the recovery temporary file while restoring '
              'from backup.',
          error,
        );
      }

      try {
        await recoveryTempFile.rename(finalPath);
      } catch (error) {
        // The rename itself never moved the *backup* -- only the separate
        // recovery-temp file -- so the backup remains exactly where it
        // was, untouched.
        await _deleteBestEffort(recoveryTempFile);
        throw SyncPersistenceStoreException(
          'load-recover-rename',
          'Could not restore a valid backup to the authoritative path.',
          error,
        );
      }

      // The post-rename final check is deliberately split into two
      // distinct, separately-staged steps -- protecting/verifying the file
      // itself (an infrastructure/bridge concern) versus reading it back,
      // decoding it, and confirming it matches the selected backup's own
      // envelope (a content/correctness concern) -- so a caller can tell
      // which kind of failure actually occurred, exactly as
      // `load-recover-protect-temp` and `load-recover-verify-temp` are
      // already kept distinct for the earlier recovery-temp file above.
      try {
        await _fileProtectionBridge.protectAndVerifyComplete(finalPath);
      } catch (error) {
        // The authoritative final produced by this attempt is not trusted
        // -- it is removed where safely possible so the next load retries
        // recovery from the still-untouched, still-valid backup file.
        // Deleting the final here never touches `backupFile`, which is
        // only ever deleted below, after full success.
        await _deleteBestEffort(finalFile);
        throw SyncPersistenceStoreException(
          'load-recover-protect-final',
          'Could not verify protection of the restored authoritative '
              'sync-state file after recovering it from backup.',
          error,
        );
      }

      try {
        final rawFinal = await finalFile.readAsString();
        final decodedFinal = SyncPersistenceEnvelope.decodeString(rawFinal);
        if (decodedFinal != envelope) {
          throw const SyncPersistenceStoreException(
            'load-recover-verify-final',
            'Restored authoritative sync-state file did not match the '
                'selected backup envelope.',
          );
        }
      } catch (error) {
        // Same reasoning as the protection-failure branch above: the
        // untrusted final is removed, never the still-valid backup.
        await _deleteBestEffort(finalFile);
        if (error is SyncPersistenceStoreException) rethrow;
        throw SyncPersistenceStoreException(
          'load-recover-verify-final',
          'Could not verify the restored authoritative sync-state file '
              'after recovering it from backup.',
          error,
        );
      }

      // Only now -- after the authoritative final has been written,
      // protected, read back, and confirmed to decode to exactly the
      // selected backup's envelope -- may the now-redundant backup be
      // removed.
      await _deleteBestEffort(backupFile);
      await _cleanupStaleTransactionFilesBestEffort(dirPath);

      return envelope;
    }

    return null;
  }

  Future<void> _preserveCorrupt(String dirPath, String rawBytes) async {
    final token = _tokenFactory();
    final utcMs = _clock().toUtc().millisecondsSinceEpoch;
    final corruptPath = _corruptPath(dirPath, utcMs, token);

    final file = File(corruptPath);
    final raf = await file.open(mode: FileMode.write);
    try {
      await raf.writeString(rawBytes);
      await raf.flush();
    } finally {
      await raf.close();
    }

    await _fileProtectionBridge.protectAndVerifyComplete(corruptPath);
  }

  Future<void> _cleanupStaleTransactionFilesBestEffort(String dirPath) async {
    try {
      final tempFiles = await _listFilesWithPrefix(dirPath, '.$_baseName.tmp-');
      final recoveryTempFiles =
          await _listFilesWithPrefix(dirPath, '.$_baseName.recover-');
      final backupFiles =
          await _listFilesWithPrefix(dirPath, '.$_baseName.backup-');
      for (final file in [...tempFiles, ...recoveryTempFiles, ...backupFiles]) {
        await _deleteBestEffort(file);
      }
    } catch (_) {
      // Best-effort only -- never let cleanup failure fail an otherwise
      // successful load.
    }
  }

  // -----------------------------------------------------------------------
  // Replace -- mirrors ProtectedFileKeptStateStore._replace exactly in
  // shape (temp write -> protect+verify temp -> backup existing final ->
  // atomic rename -> protect+verify final -> rollback on any post-rename
  // failure).
  // -----------------------------------------------------------------------

  Future<void> _replaceEnvelope(SyncPersistenceEnvelope envelope) async {
    final dirPath = await _resolveAndProtectDirectory();
    final finalPath = _finalPath(dirPath);
    final finalFile = File(finalPath);

    final encoded = envelope.encodeString();
    final token = _tokenFactory();
    final tempPath = _tempPath(dirPath, token);
    final tempFile = File(tempPath);

    try {
      final raf = await tempFile.open(mode: FileMode.write);
      try {
        await raf.writeString(encoded);
        await raf.flush();
      } finally {
        await raf.close();
      }
    } catch (error) {
      keptDiagnostic(
        'sync-persistence-store: replace-write-temp-failed '
        'errorType=${error.runtimeType}',
      );
      await _deleteBestEffort(tempFile);
      throw SyncPersistenceStoreException(
        'replace-write-temp',
        'Could not write the temporary sync-state file.',
        error,
      );
    }

    try {
      await _fileProtectionBridge.protectAndVerifyComplete(tempPath);
    } catch (error) {
      keptDiagnostic(
        'sync-persistence-store: replace-protect-temp-failed '
        'errorType=${error.runtimeType}',
      );
      await _deleteBestEffort(tempFile);
      throw SyncPersistenceStoreException(
        'replace-protect-temp',
        'Could not protect the temporary sync-state file.',
        error,
      );
    }

    try {
      final rawTemp = await tempFile.readAsString();
      final decodedTemp = SyncPersistenceEnvelope.decodeString(rawTemp);
      if (decodedTemp != envelope) {
        throw const SyncPersistenceStoreException(
          'replace-verify-temp',
          'Temporary sync-state file did not match the intended envelope.',
        );
      }
    } catch (error) {
      keptDiagnostic(
        'sync-persistence-store: replace-verify-temp-failed '
        'errorType=${error.runtimeType}',
      );
      await _deleteBestEffort(tempFile);
      if (error is SyncPersistenceStoreException) rethrow;
      throw SyncPersistenceStoreException(
        'replace-verify-temp',
        'Could not verify the temporary sync-state file.',
        error,
      );
    }

    final hadExistingFinal = await finalFile.exists();
    String? backupPath;
    SyncPersistenceEnvelope? previousEnvelope;

    if (hadExistingFinal) {
      backupPath = _backupPath(dirPath, token);
      final backupFile = File(backupPath);
      try {
        final existingBytes = await finalFile.readAsString();
        final raf = await backupFile.open(mode: FileMode.write);
        try {
          await raf.writeString(existingBytes);
          await raf.flush();
        } finally {
          await raf.close();
        }
        await _fileProtectionBridge.protectAndVerifyComplete(backupPath);
        final rawBackup = await backupFile.readAsString();
        previousEnvelope = SyncPersistenceEnvelope.decodeString(rawBackup);
      } catch (error) {
        keptDiagnostic(
          'sync-persistence-store: replace-backup-failed '
          'errorType=${error.runtimeType}',
        );
        await _deleteBestEffort(tempFile);
        await _deleteBestEffort(File(backupPath));
        throw SyncPersistenceStoreException(
          'replace-backup',
          'Could not create a verified backup of the existing sync-state '
              'file.',
          error,
        );
      }
    }

    try {
      await tempFile.rename(finalPath);
    } catch (error) {
      keptDiagnostic(
        'sync-persistence-store: replace-rename-failed '
        'errorType=${error.runtimeType}',
      );
      await _deleteBestEffort(tempFile);
      if (backupPath != null) await _deleteBestEffort(File(backupPath));
      throw SyncPersistenceStoreException(
        'replace-rename',
        'Could not atomically replace the authoritative sync-state file.',
        error,
      );
    }

    try {
      await _fileProtectionBridge.protectAndVerifyComplete(finalPath);
      final rawFinal = await finalFile.readAsString();
      final decodedFinal = SyncPersistenceEnvelope.decodeString(rawFinal);
      if (decodedFinal != envelope) {
        throw const SyncPersistenceStoreException(
          'replace-verify-final',
          'Final sync-state file did not match the intended envelope after '
              'replacement.',
        );
      }
    } catch (error) {
      keptDiagnostic(
        'sync-persistence-store: replace-verify-final-failed '
        'errorType=${error.runtimeType}',
      );
      await _rollbackAfterRename(
        finalFile: finalFile,
        backupPath: backupPath,
        previousEnvelope: previousEnvelope,
        originalError: error,
      );
    }

    if (backupPath != null) {
      await _deleteBestEffort(File(backupPath));
    }
  }

  Future<void> _rollbackAfterRename({
    required File finalFile,
    required String? backupPath,
    required SyncPersistenceEnvelope? previousEnvelope,
    required Object originalError,
  }) async {
    if (backupPath == null) {
      await _deleteBestEffort(finalFile);
      throw SyncPersistenceStoreException(
        'replace-post-rename',
        'Sync-state replacement failed after rename; no prior state '
            'existed to restore.',
        originalError,
      );
    }

    final backupFile = File(backupPath);
    try {
      await _deleteBestEffort(finalFile);
      await backupFile.rename(finalFile.path);
      await _fileProtectionBridge.protectAndVerifyComplete(finalFile.path);
      final rawRestored = await finalFile.readAsString();
      final restoredEnvelope = SyncPersistenceEnvelope.decodeString(
        rawRestored,
      );
      if (restoredEnvelope != previousEnvelope) {
        throw const SyncPersistenceStoreException(
          'replace-rollback-verify',
          'Restored sync-state file did not match the prior envelope.',
        );
      }
    } catch (rollbackError) {
      throw SyncPersistenceStoreException(
        'replace-rollback',
        'Sync-state replacement failed and rollback also failed; a backup '
            'may remain for later recovery.',
        _CombinedFailure(originalError, rollbackError),
      );
    }

    throw SyncPersistenceStoreException(
      'replace-post-rename',
      'Sync-state replacement failed after rename; the prior sync-state '
          'file was restored.',
      originalError,
    );
  }

  // -----------------------------------------------------------------------
  // Shared path/file helpers -- none of these touch the coordinator; only
  // the public API methods above do.
  // -----------------------------------------------------------------------

  Future<String> _resolveAndProtectDirectory() async {
    final Directory root;
    try {
      root = await _rootDirectoryProvider();
    } catch (error) {
      throw SyncPersistenceStoreException(
        'directory-resolve',
        'Could not resolve the application support directory.',
        error,
      );
    }

    final dirPath = '${root.path}/$_directoryName';
    final dir = Directory(dirPath);
    try {
      await dir.create(recursive: true);
    } catch (error) {
      throw SyncPersistenceStoreException(
        'directory-create',
        'Could not create the protected sync-state directory.',
        error,
      );
    }

    try {
      await _fileProtectionBridge.protectAndVerifyComplete(dirPath);
    } catch (error) {
      throw SyncPersistenceStoreException(
        'directory-protect',
        'Could not protect the sync-state directory.',
        error,
      );
    }

    return dirPath;
  }

  String _finalPath(String dirPath) => '$dirPath/$_baseName.json';

  String _tempPath(String dirPath, String token) =>
      '$dirPath/.$_baseName.tmp-$token.json';

  String _recoveryTempPath(String dirPath, String token) =>
      '$dirPath/.$_baseName.recover-$token.json';

  String _backupPath(String dirPath, String token) =>
      '$dirPath/.$_baseName.backup-$token.json';

  String _corruptPath(String dirPath, int utcMs, String token) =>
      '$dirPath/$_baseName.corrupt-$utcMs-$token.json';

  String _fileName(String path) => path.split('/').last;

  Future<List<File>> _listFilesWithPrefix(
    String dirPath,
    String prefix,
  ) async {
    final dir = Directory(dirPath);
    final entries = await dir.list().toList();
    return entries
        .whereType<File>()
        .where((file) => _fileName(file.path).startsWith(prefix))
        .toList();
  }

  Future<void> _deleteBestEffort(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort only.
    }
  }
}

/// Bundles an original failure with a subsequent rollback failure, for
/// diagnostic purposes only -- never inspected structurally by callers.
/// Mirrors `ProtectedFileKeptStateStore`'s private `_CombinedFailure`.
class _CombinedFailure {
  const _CombinedFailure(this.original, this.rollback);

  final Object original;
  final Object rollback;

  @override
  String toString() =>
      'original failure: $original; rollback failure: $rollback';
}
