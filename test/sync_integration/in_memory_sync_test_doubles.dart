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
import 'package:wisdom_app/sync_persistence/incoming_batch_checkpoint.dart';
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

  @override
  Future<CommitIncomingBatchCheckpointResult> commitIncomingBatchCheckpoint(
    CommitIncomingBatchCheckpointRequest request,
  ) {
    throw UnimplementedError(
      'InMemorySyncPersistenceStore does not implement incoming-batch '
      'checkpointing -- no Phase 4E-2 test exercises it.',
    );
  }

  /// Test-only convenience: directly seeds a bucket without going through
  /// [enqueueMutation]/[replaceAccountState]'s own semantics, for account-
  /// gating tests that need to start from an already-established bucket at
  /// a specific [AccountBootstrapState].
  void seedAccount(String accountFingerprint, AccountSyncState state) {
    _accounts[accountFingerprint] = state;
  }
}
