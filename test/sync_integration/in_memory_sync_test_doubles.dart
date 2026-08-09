/// Build 26 Phase 4E-2: minimal, correct, purely in-memory test doubles for
/// [LocalSyncIntentStore] and [SyncPersistenceStore] -- reused by
/// `KeptSyncIntegrationCoordinator` tests and by
/// `test/persistence_test_helpers.dart`'s `KeptRepositoryTestGraph` (which
/// widget tests depend on transitively via `SavedReflectionsService`).
///
/// Deliberately not the "Protected*" file-backed implementations: those are
/// already exhaustively tested elsewhere (crash-safe atomic file writes).
/// These doubles exist only to reproduce the *documented interface
/// contracts* (idempotent-by-identity, supersession-by-record, mismatch
/// exceptions) synchronously and in-memory, so coordinator-level tests can
/// exercise real concurrency (via `Future`s and manual scheduling) without
/// any real file I/O.
library;

import 'package:wisdom_app/sync/sync_change.dart';
import 'package:wisdom_app/sync_integration/local_sync_intent.dart';
import 'package:wisdom_app/sync_integration/local_sync_intent_store.dart';
import 'package:wisdom_app/sync_persistence/account_sync_state.dart';
import 'package:wisdom_app/sync_persistence/associated_account_fingerprint_commit.dart';
import 'package:wisdom_app/sync_persistence/incoming_batch_checkpoint.dart';
import 'package:wisdom_app/sync_persistence/outbox_mutation_retirement.dart';
import 'package:wisdom_app/sync_persistence/persisted_outbox_mutation.dart';
import 'package:wisdom_app/sync_persistence/sync_persistence_store.dart';

/// In-memory [LocalSyncIntentStore] reproducing [LocalSyncIntentStore
/// .enqueueIntent]'s exact documented identity/supersession policy.
class InMemoryLocalSyncIntentStore implements LocalSyncIntentStore {
  final List<LocalSyncIntent> _intents = [];

  /// Test-only one-shot fault injection: when non-null, the *next*
  /// [enqueueIntent] call throws this instead of persisting -- resets to
  /// `null` immediately after firing, mirroring
  /// `InMemoryKeptStateStore.failReplace`'s own contract.
  Object? failNextEnqueueIntent;

  @override
  Future<List<LocalSyncIntent>> loadIntents() async {
    return List.unmodifiable(_intents);
  }

  @override
  Future<void> enqueueIntent(LocalSyncIntent intent) async {
    final failure = failNextEnqueueIntent;
    if (failure != null) {
      failNextEnqueueIntent = null;
      throw failure;
    }

    final byId = _intents.indexWhere((i) => i.intentId == intent.intentId);
    if (byId >= 0) {
      final existing = _intents[byId];
      if (existing.kind == intent.kind && existing.payload == intent.payload) {
        return;
      }
      throw const ConflictingLocalSyncIntentIdentityException();
    }

    final byRecord =
        _intents.indexWhere((i) => i.recordName == intent.recordName);
    if (byRecord >= 0) {
      _intents[byRecord] = intent;
    } else {
      _intents.add(intent);
    }
  }

  @override
  Future<void> advanceIntentStage({
    required String intentId,
    required LocalSyncIntentStage expectedStage,
    required LocalSyncIntentStage nextStage,
  }) async {
    final index = _intents.indexWhere((i) => i.intentId == intentId);
    if (index < 0) return;
    final current = _intents[index];
    if (current.stage != expectedStage) {
      throw const LocalSyncIntentStageMismatchException();
    }
    _intents[index] = current.copyWith(stage: nextStage);
  }

  @override
  Future<void> removeIntent(String intentId) async {
    _intents.removeWhere((i) => i.intentId == intentId);
  }
}

/// In-memory [SyncPersistenceStore] reproducing [SyncPersistenceStore
/// .enqueueMutation]'s exact documented identity/supersession/epoch policy.
/// [commitIncomingBatchCheckpoint] is intentionally unimplemented -- no
/// Phase 4E-2 test exercises incoming-batch application.
class InMemorySyncPersistenceStore implements SyncPersistenceStore {
  final Map<String, AccountSyncState> _accounts = {};
  final Set<String> _quarantined = {};

  /// Build 26 Phase 4E-4: the durable top-level associated-account marker --
  /// deliberately a plain field here (never a per-account bucket value),
  /// mirroring `SyncPersistenceEnvelope.associatedAccountFingerprint`'s own
  /// top-level, bucket-independent placement exactly.
  String? _associatedAccountFingerprint;

  @override
  Future<String?> loadAssociatedAccountFingerprint() async {
    return _associatedAccountFingerprint;
  }

  @override
  Future<CommitAssociatedAccountFingerprintResult>
      commitAssociatedAccountFingerprint({
    required String fingerprint,
    required String? expectedCurrent,
  }) async {
    if (_associatedAccountFingerprint == fingerprint) {
      return const CommitAssociatedAccountFingerprintResult(
        AssociatedAccountFingerprintCommitStatus.alreadyCommitted,
      );
    }
    if (_associatedAccountFingerprint != expectedCurrent) {
      return const CommitAssociatedAccountFingerprintResult(
        AssociatedAccountFingerprintCommitStatus.expectedCurrentMismatch,
      );
    }
    _associatedAccountFingerprint = fingerprint;
    return const CommitAssociatedAccountFingerprintResult(
      AssociatedAccountFingerprintCommitStatus.committed,
    );
  }

  @override
  Future<List<String>> loadMeaningfulAccountFingerprints() async {
    return [
      for (final entry in _accounts.entries)
        if (entry.value.bootstrapState != AccountBootstrapState.notStarted)
          entry.key,
    ];
  }

  /// Test-only convenience: directly seeds the associated-account marker
  /// without going through [commitAssociatedAccountFingerprint]'s own CAS
  /// semantics, mirroring [seedAccount]'s own precedent.
  void seedAssociatedAccountFingerprint(String? fingerprint) {
    _associatedAccountFingerprint = fingerprint;
  }

  @override
  Future<AccountSyncState?> loadAccountState(String accountFingerprint) async {
    return _accounts[accountFingerprint];
  }

  @override
  Future<void> replaceAccountState(
    String accountFingerprint,
    AccountSyncState state,
  ) async {
    _accounts[accountFingerprint] = state;
  }

  @override
  Future<void> enqueueMutation(
    String accountFingerprint,
    SyncChange change,
  ) async {
    final current = _accounts[accountFingerprint];
    if (current == null) {
      _accounts[accountFingerprint] = AccountSyncState(
        dataEpoch: change.projection.dataEpoch,
        outbox: [PersistedOutboxMutation(change: change)],
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
          return;
        }
        throw const ConflictingMutationIdentityException();
      }
    }

    final existingIndex =
        current.outbox.indexWhere((entry) => entry.recordName == recordName);
    final nextOutbox = List<PersistedOutboxMutation>.of(current.outbox);
    if (existingIndex == -1) {
      nextOutbox.add(PersistedOutboxMutation(change: change));
    } else {
      nextOutbox[existingIndex] = PersistedOutboxMutation(change: change);
    }
    _accounts[accountFingerprint] = current.copyWith(outbox: nextOutbox);
  }

  @override
  Future<void> applyMutationOutcomes(
    String accountFingerprint, {
    Set<String> acknowledgedMutationIds = const {},
    Map<String, PersistedOutboxMutationStatus> updatedStatusByMutationId =
        const {},
  }) async {
    final current = _accounts[accountFingerprint];
    if (current == null) return;

    final nextOutbox = <PersistedOutboxMutation>[];
    for (final entry in current.outbox) {
      if (acknowledgedMutationIds.contains(entry.mutationId)) continue;
      final newStatus = updatedStatusByMutationId[entry.mutationId];
      nextOutbox
          .add(newStatus == null ? entry : entry.copyWith(status: newStatus));
    }
    _accounts[accountFingerprint] = current.copyWith(outbox: nextOutbox);
  }

  @override
  Future<List<PersistedOutboxMutation>> readPendingMutations(
    String accountFingerprint,
  ) async {
    return List.unmodifiable(_accounts[accountFingerprint]?.outbox ?? const []);
  }

  @override
  Future<void> replaceRecordSystemFields(
    String accountFingerprint,
    String recordName,
    String systemFields,
  ) async {
    final current = _accounts[accountFingerprint];
    if (current == null) {
      throw const SyncPersistenceStoreException(
        'system-fields-no-account-state',
        'No sync state exists yet for this account.',
      );
    }
    final nextFields = Map<String, String>.from(current.recordSystemFields)
      ..[recordName] = systemFields;
    _accounts[accountFingerprint] =
        current.copyWith(recordSystemFields: nextFields);
  }

  @override
  Future<void> storeServerChangeToken(
    String accountFingerprint,
    String serverToken,
  ) async {
    final current = _accounts[accountFingerprint];
    if (current == null) {
      throw const SyncPersistenceStoreException(
        'store-token-no-account-state',
        'No sync state exists yet for this account.',
      );
    }
    _accounts[accountFingerprint] =
        current.copyWith(serverChangeToken: serverToken);
  }

  @override
  Future<void> clearServerChangeToken(String accountFingerprint) async {
    final current = _accounts[accountFingerprint];
    if (current == null) return;
    _accounts[accountFingerprint] = current.copyWith(serverChangeToken: null);
  }

  @override
  Future<void> clearAccountState(String accountFingerprint) async {
    _accounts.remove(accountFingerprint);
  }

  @override
  Future<void> quarantineAccountState(String accountFingerprint) async {
    final current = _accounts.remove(accountFingerprint);
    if (current != null) _quarantined.add(accountFingerprint);
  }

  /// Build 26 Phase 4E-3b: a faithful (if simplified -- no bootstrap-create
  /// mode support, since no test needs it) in-memory reproduction of
  /// [ProtectedSyncPersistenceStore]'s own
  /// `commitIncomingBatchCheckpoint` request-validation and existing-bucket
  /// commit logic, so incoming-apply-coordinator tests can exercise the real
  /// documented contract (epoch/token/duplicate-record validation, atomic
  /// system-fields-plus-token commit) without any file I/O.
  @override
  Future<CommitIncomingBatchCheckpointResult> commitIncomingBatchCheckpoint(
    CommitIncomingBatchCheckpointRequest request,
  ) async {
    if (!_looksLikeOpaqueBase64(request.pendingServerChangeToken)) {
      return const CommitIncomingBatchCheckpointResult(
        status: IncomingCheckpointStatus.invalidRequest,
      );
    }
    if (request.nextBootstrapState != null &&
        request.expectedBootstrapState == null) {
      return const CommitIncomingBatchCheckpointResult(
        status: IncomingCheckpointStatus.invalidRequest,
      );
    }

    final seenRecordNames = <String>{};
    for (final update in request.recordSystemFieldsUpdates) {
      if (!seenRecordNames.add(update.recordName)) {
        return const CommitIncomingBatchCheckpointResult(
          status: IncomingCheckpointStatus.duplicateRecordName,
        );
      }
      if (!looksLikeKeptWisdomRecordName(update.recordName) ||
          !_looksLikeOpaqueBase64(update.systemFields)) {
        return const CommitIncomingBatchCheckpointResult(
          status: IncomingCheckpointStatus.invalidRecordSystemFields,
        );
      }
    }

    // Build 26 Phase 4E-4: a faithful (if simplified) in-memory
    // reproduction of `ProtectedSyncPersistenceStore._commitBootstrapCreate`
    // -- needed now that `KeptSyncBootstrapCoordinator` genuinely exercises
    // this mode for a clean device's first bootstrap.
    if (request.mode == IncomingCheckpointMode.bootstrapCreate) {
      if (request.expectedCurrentDataEpoch != null ||
          request.expectedPreviousServerToken != null ||
          request.bootstrapTargetDataEpoch == null) {
        return const CommitIncomingBatchCheckpointResult(
          status: IncomingCheckpointStatus.invalidRequest,
        );
      }
      if (_accounts.containsKey(request.accountFingerprint)) {
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
      final fields = <String, String>{};
      for (final update in request.recordSystemFieldsUpdates) {
        fields[update.recordName] = update.systemFields;
      }
      _accounts[request.accountFingerprint] = AccountSyncState(
        dataEpoch: request.bootstrapTargetDataEpoch!,
        serverChangeToken: request.pendingServerChangeToken,
        recordSystemFields: fields,
        bootstrapState: nextBootstrapState,
      );
      return CommitIncomingBatchCheckpointResult(
        status: IncomingCheckpointStatus.committed,
        systemFieldCount: request.recordSystemFieldsUpdates.length,
        bootstrapStateChanged:
            nextBootstrapState != AccountBootstrapState.notStarted,
        tokenChanged: true,
      );
    }
    if (request.expectedCurrentDataEpoch == null ||
        request.bootstrapTargetDataEpoch != null) {
      return const CommitIncomingBatchCheckpointResult(
        status: IncomingCheckpointStatus.invalidRequest,
      );
    }

    final current = _accounts[request.accountFingerprint];
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

    // Idempotent-retry shortcut, mirroring the production store exactly.
    final alreadyMatches =
        current.serverChangeToken == request.pendingServerChangeToken &&
            (request.nextBootstrapState ?? current.bootstrapState) ==
                current.bootstrapState &&
            request.recordSystemFieldsUpdates.every(
              (update) =>
                  current.recordSystemFields[update.recordName] ==
                  update.systemFields,
            );
    if (alreadyMatches) {
      return const CommitIncomingBatchCheckpointResult(
        status: IncomingCheckpointStatus.committed,
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

    final mergedFields = Map<String, String>.from(current.recordSystemFields);
    for (final update in request.recordSystemFieldsUpdates) {
      mergedFields[update.recordName] = update.systemFields;
    }
    final tokenChanged =
        current.serverChangeToken != request.pendingServerChangeToken;
    final bootstrapStateChanged = nextBootstrapState != current.bootstrapState;

    _accounts[request.accountFingerprint] = current.copyWith(
      serverChangeToken: request.pendingServerChangeToken,
      recordSystemFields: mergedFields,
      bootstrapState: nextBootstrapState,
    );

    return CommitIncomingBatchCheckpointResult(
      status: IncomingCheckpointStatus.committed,
      systemFieldCount: request.recordSystemFieldsUpdates.length,
      bootstrapStateChanged: bootstrapStateChanged,
      tokenChanged: tokenChanged,
    );
  }

  /// Build 26 Phase 4E-3b: in-memory reproduction of
  /// [ProtectedSyncPersistenceStore.retireOutboxMutationIfCurrent]'s exact
  /// documented guard order.
  @override
  Future<RetireOutboxMutationResult> retireOutboxMutationIfCurrent(
    RetireOutboxMutationRequest request,
  ) async {
    final current = _accounts[request.accountFingerprint];
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
    _accounts[request.accountFingerprint] =
        current.copyWith(outbox: nextOutbox);
    return const RetireOutboxMutationResult(RetireOutboxMutationStatus.retired);
  }

  bool _looksLikeOpaqueBase64(String value) => looksLikeOpaqueBase64(value);

  /// Test-only convenience: directly seeds a bucket without going through
  /// [enqueueMutation]/[replaceAccountState]'s own semantics, for account-
  /// gating tests that need to start from an already-established bucket at
  /// a specific [AccountBootstrapState].
  void seedAccount(String accountFingerprint, AccountSyncState state) {
    _accounts[accountFingerprint] = state;
  }
}
