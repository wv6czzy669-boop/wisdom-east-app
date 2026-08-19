/// Build 26 Phase 5 (slice 3): the required focused test suite for
/// [LocalDeletionFinalizer] -- points 1-25 of the Slice 3 33-point matrix
/// (points 26-33, concerning runtime/relaunch wiring, live in
/// `test/sync_runtime/cloud_kit_sync_runtime_coordinator_test.dart`
/// instead).
///
/// Uses `InMemorySyncPersistenceStore`/`InMemoryLocalSyncIntentStore`
/// (test/sync_integration/in_memory_sync_test_doubles.dart) directly -- the
/// real, already-reviewed CAS/idempotency semantics, no file I/O -- plus two
/// small, self-contained crash-injecting decorators for the four required
/// crash-recovery points (19-22).
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/sync/cloud_kept_wisdom_projection.dart';
import 'package:wisdom_app/sync/data_epoch.dart';
import 'package:wisdom_app/sync/sync_change.dart';
import 'package:wisdom_app/sync_deletion/local_deletion_finalizer.dart';
import 'package:wisdom_app/sync_integration/local_sync_intent.dart';
import 'package:wisdom_app/sync_integration/local_sync_intent_store.dart';
import 'package:wisdom_app/sync_persistence/account_sync_state.dart';
import 'package:wisdom_app/sync_persistence/associated_account_fingerprint_commit.dart';
import 'package:wisdom_app/sync_persistence/deletion_transaction_result.dart';
import 'package:wisdom_app/sync_persistence/incoming_batch_checkpoint.dart';
import 'package:wisdom_app/sync_persistence/outbox_mutation_retirement.dart';
import 'package:wisdom_app/sync_persistence/pending_deletion_transaction.dart';
import 'package:wisdom_app/sync_persistence/persisted_outbox_mutation.dart';
import 'package:wisdom_app/sync_persistence/sync_persistence_store.dart';

import '../sync_integration/in_memory_sync_test_doubles.dart';

/// Deterministic, valid-shape opaque account fingerprint fixture, mirroring
/// every other Phase 5 test file's own `_fingerprint(int)` helper.
String _fingerprint(int n) => n.toRadixString(16).padLeft(64, '0');

const _revealIdA = 'aaaaaaaa-1111-4111-8111-111111111111';
const _intentId1 = '11111111-1111-4111-8111-111111111111';
const _mutationId1 = '44444444-4444-4444-8444-444444444444';

LocalSyncIntent _keepIntent({String intentId = _intentId1}) {
  return LocalSyncIntent(
    intentId: intentId,
    kind: LocalSyncIntentKind.create,
    payload: LocalSyncIntentPayload.active(
      revealId: _revealIdA,
      operation: LocalSyncIntentOperation.keep,
      wisdomText: 'Synthetic wisdom text for testing only.',
      revealedAtMs: 1000,
      keptAtMs: 2000,
      updatedAtMs: 3000,
      mutationId: _mutationId1,
    ),
    stage: LocalSyncIntentStage.pendingLocalApplication,
    enqueuedAt: DateTime.utc(2026, 8, 1),
  );
}

/// A durable transaction fixture at [stage], targeting [fingerprint].
/// Constructed directly (never through `beginDeletionTransaction`) since
/// these are unit tests of the finalizer alone -- the deletion runner's own
/// Slice 2 suite already exhaustively proves how a transaction legitimately
/// reaches each stage.
PendingDeletionTransaction _transaction({
  String fingerprint = '',
  required DeletionTransactionStage stage,
}) {
  return PendingDeletionTransaction(
    accountFingerprint: fingerprint.isEmpty ? _fingerprint(1) : fingerprint,
    originalDataEpoch: null,
    replacementDataEpoch: DataEpoch.generate(),
    stage: stage,
  );
}

/// A thin forwarding decorator that throws once from exactly one named
/// operation, then resets to normal delegation -- simulating "the process
/// died immediately after this step durably completed, but before the next
/// step's own call even started." Mirrors this codebase's established
/// `_ThrowingLoadSyncPersistenceStore` precedent
/// (`test/sync_deletion/cloud_kit_remote_deletion_runner_test.dart`), but
/// generalized to any one of the three write operations
/// [LocalDeletionFinalizer.finalize] itself calls in sequence.
class _CrashInjectingSyncPersistenceStore implements SyncPersistenceStore {
  _CrashInjectingSyncPersistenceStore(this._delegate);

  final SyncPersistenceStore _delegate;

  bool throwOnClearAccountState = false;
  bool throwOnClearAssociatedMarker = false;
  bool throwOnClearDeletionTransaction = false;
  bool throwOnVerificationRead = false;

  @override
  Future<AccountSyncState?> loadAccountState(String accountFingerprint) {
    if (throwOnVerificationRead) {
      throwOnVerificationRead = false;
      throw const SyncPersistenceStoreException(
        'test-injected-crash',
        'Simulated crash inside the post-cleanup verification read, '
            'immediately before the final clearDeletionTransaction call.',
      );
    }
    return _delegate.loadAccountState(accountFingerprint);
  }

  @override
  Future<void> clearAccountState(String accountFingerprint) {
    if (throwOnClearAccountState) {
      throwOnClearAccountState = false;
      throw const SyncPersistenceStoreException(
        'test-injected-crash',
        'Simulated crash inside clearAccountState.',
      );
    }
    return _delegate.clearAccountState(accountFingerprint);
  }

  @override
  Future<ClearAssociatedAccountFingerprintResult>
      clearAssociatedAccountFingerprintIfCurrent({
    required String expectedCurrent,
  }) {
    if (throwOnClearAssociatedMarker) {
      throwOnClearAssociatedMarker = false;
      throw const SyncPersistenceStoreException(
        'test-injected-crash',
        'Simulated crash inside clearAssociatedAccountFingerprintIfCurrent.',
      );
    }
    return _delegate.clearAssociatedAccountFingerprintIfCurrent(
      expectedCurrent: expectedCurrent,
    );
  }

  @override
  Future<void> clearDeletionTransaction({
    required String accountFingerprint,
  }) {
    if (throwOnClearDeletionTransaction) {
      throwOnClearDeletionTransaction = false;
      throw const SyncPersistenceStoreException(
        'test-injected-crash',
        'Simulated crash inside clearDeletionTransaction.',
      );
    }
    return _delegate.clearDeletionTransaction(
      accountFingerprint: accountFingerprint,
    );
  }

  // Every other method passes straight through, unmodified.
  @override
  Future<void> replaceAccountState(
          String accountFingerprint, AccountSyncState state) =>
      _delegate.replaceAccountState(accountFingerprint, state);
  @override
  Future<void> enqueueMutation(String accountFingerprint, SyncChange change) =>
      _delegate.enqueueMutation(accountFingerprint, change);
  @override
  Future<void> applyMutationOutcomes(
    String accountFingerprint, {
    Set<String> acknowledgedMutationIds = const {},
    Map<String, PersistedOutboxMutationStatus> updatedStatusByMutationId =
        const {},
  }) =>
      _delegate.applyMutationOutcomes(
        accountFingerprint,
        acknowledgedMutationIds: acknowledgedMutationIds,
        updatedStatusByMutationId: updatedStatusByMutationId,
      );
  @override
  Future<List<PersistedOutboxMutation>> readPendingMutations(
          String accountFingerprint) =>
      _delegate.readPendingMutations(accountFingerprint);
  @override
  Future<void> replaceRecordSystemFields(
          String accountFingerprint, String recordName, String systemFields) =>
      _delegate.replaceRecordSystemFields(
          accountFingerprint, recordName, systemFields);
  @override
  Future<void> storeServerChangeToken(
          String accountFingerprint, String serverToken) =>
      _delegate.storeServerChangeToken(accountFingerprint, serverToken);
  @override
  Future<void> clearServerChangeToken(String accountFingerprint) =>
      _delegate.clearServerChangeToken(accountFingerprint);
  @override
  Future<void> quarantineAccountState(String accountFingerprint) =>
      _delegate.quarantineAccountState(accountFingerprint);
  @override
  Future<CommitIncomingBatchCheckpointResult> commitIncomingBatchCheckpoint(
    CommitIncomingBatchCheckpointRequest request,
  ) =>
      _delegate.commitIncomingBatchCheckpoint(request);
  @override
  Future<RetireOutboxMutationResult> retireOutboxMutationIfCurrent(
    RetireOutboxMutationRequest request,
  ) =>
      _delegate.retireOutboxMutationIfCurrent(request);
  @override
  Future<String?> loadAssociatedAccountFingerprint() =>
      _delegate.loadAssociatedAccountFingerprint();
  @override
  Future<CommitAssociatedAccountFingerprintResult>
      commitAssociatedAccountFingerprint({
    required String fingerprint,
    required String? expectedCurrent,
  }) =>
          _delegate.commitAssociatedAccountFingerprint(
            fingerprint: fingerprint,
            expectedCurrent: expectedCurrent,
          );
  @override
  Future<List<String>> loadMeaningfulAccountFingerprints() =>
      _delegate.loadMeaningfulAccountFingerprints();
  @override
  Future<PendingDeletionTransaction?> loadPendingDeletionTransaction() =>
      _delegate.loadPendingDeletionTransaction();
  @override
  Future<BeginDeletionTransactionResult> beginDeletionTransaction({
    required String accountFingerprint,
  }) =>
      _delegate.beginDeletionTransaction(
          accountFingerprint: accountFingerprint);
  @override
  Future<AdvanceDeletionTransactionResult> advanceDeletionTransactionStage({
    required String accountFingerprint,
    required DeletionTransactionStage expectedCurrentStage,
    required DeletionTransactionStage nextStage,
  }) =>
      _delegate.advanceDeletionTransactionStage(
        accountFingerprint: accountFingerprint,
        expectedCurrentStage: expectedCurrentStage,
        nextStage: nextStage,
      );
}

/// A thin forwarding [LocalSyncIntentStore] decorator that throws once from
/// [loadIntents] -- simulating "the process died while enumerating pending
/// intents, before any intent was actually removed."
class _CrashInjectingLocalSyncIntentStore implements LocalSyncIntentStore {
  _CrashInjectingLocalSyncIntentStore(this._delegate);

  final LocalSyncIntentStore _delegate;
  bool throwOnLoadIntents = false;

  @override
  Future<List<LocalSyncIntent>> loadIntents() {
    if (throwOnLoadIntents) {
      throwOnLoadIntents = false;
      throw const LocalSyncIntentStoreException(
        'test-injected-crash',
        'Simulated crash inside loadIntents.',
      );
    }
    return _delegate.loadIntents();
  }

  @override
  Future<void> enqueueIntent(LocalSyncIntent intent) =>
      _delegate.enqueueIntent(intent);
  @override
  Future<void> advanceIntentStage({
    required String intentId,
    required LocalSyncIntentStage expectedStage,
    required LocalSyncIntentStage nextStage,
  }) =>
      _delegate.advanceIntentStage(
        intentId: intentId,
        expectedStage: expectedStage,
        nextStage: nextStage,
      );
  @override
  Future<void> removeIntent(String intentId) =>
      _delegate.removeIntent(intentId);
}

/// A [SyncPersistenceStore] decorator that fails the test outright if ANY
/// mutating method is ever invoked -- [clearAccountState],
/// [clearAssociatedAccountFingerprintIfCurrent], or
/// [clearDeletionTransaction]. Used only to prove REPAIR 1's pre-flight
/// account-mismatch check runs, and returns, strictly before any cleanup
/// mutation is even attempted -- not merely that mutations happen to net
/// out to a no-op.
class _MutationForbiddenSyncPersistenceStore implements SyncPersistenceStore {
  _MutationForbiddenSyncPersistenceStore(this._delegate);

  final SyncPersistenceStore _delegate;

  @override
  Future<void> clearAccountState(String accountFingerprint) {
    fail('clearAccountState must never be called before the account-mismatch '
        'pre-flight check has completed.');
  }

  @override
  Future<ClearAssociatedAccountFingerprintResult>
      clearAssociatedAccountFingerprintIfCurrent({
    required String expectedCurrent,
  }) {
    fail('clearAssociatedAccountFingerprintIfCurrent must never be called '
        'before the account-mismatch pre-flight check has completed.');
  }

  @override
  Future<void> clearDeletionTransaction({
    required String accountFingerprint,
  }) {
    fail('clearDeletionTransaction must never be called before the '
        'account-mismatch pre-flight check has completed.');
  }

  // Every read-only method passes straight through, unmodified.
  @override
  Future<AccountSyncState?> loadAccountState(String accountFingerprint) =>
      _delegate.loadAccountState(accountFingerprint);
  @override
  Future<void> replaceAccountState(
          String accountFingerprint, AccountSyncState state) =>
      _delegate.replaceAccountState(accountFingerprint, state);
  @override
  Future<void> enqueueMutation(String accountFingerprint, SyncChange change) =>
      _delegate.enqueueMutation(accountFingerprint, change);
  @override
  Future<void> applyMutationOutcomes(
    String accountFingerprint, {
    Set<String> acknowledgedMutationIds = const {},
    Map<String, PersistedOutboxMutationStatus> updatedStatusByMutationId =
        const {},
  }) =>
      _delegate.applyMutationOutcomes(
        accountFingerprint,
        acknowledgedMutationIds: acknowledgedMutationIds,
        updatedStatusByMutationId: updatedStatusByMutationId,
      );
  @override
  Future<List<PersistedOutboxMutation>> readPendingMutations(
          String accountFingerprint) =>
      _delegate.readPendingMutations(accountFingerprint);
  @override
  Future<void> replaceRecordSystemFields(
          String accountFingerprint, String recordName, String systemFields) =>
      _delegate.replaceRecordSystemFields(
          accountFingerprint, recordName, systemFields);
  @override
  Future<void> storeServerChangeToken(
          String accountFingerprint, String serverToken) =>
      _delegate.storeServerChangeToken(accountFingerprint, serverToken);
  @override
  Future<void> clearServerChangeToken(String accountFingerprint) =>
      _delegate.clearServerChangeToken(accountFingerprint);
  @override
  Future<void> quarantineAccountState(String accountFingerprint) =>
      _delegate.quarantineAccountState(accountFingerprint);
  @override
  Future<CommitIncomingBatchCheckpointResult> commitIncomingBatchCheckpoint(
    CommitIncomingBatchCheckpointRequest request,
  ) =>
      _delegate.commitIncomingBatchCheckpoint(request);
  @override
  Future<RetireOutboxMutationResult> retireOutboxMutationIfCurrent(
    RetireOutboxMutationRequest request,
  ) =>
      _delegate.retireOutboxMutationIfCurrent(request);
  @override
  Future<String?> loadAssociatedAccountFingerprint() =>
      _delegate.loadAssociatedAccountFingerprint();
  @override
  Future<CommitAssociatedAccountFingerprintResult>
      commitAssociatedAccountFingerprint({
    required String fingerprint,
    required String? expectedCurrent,
  }) =>
          _delegate.commitAssociatedAccountFingerprint(
            fingerprint: fingerprint,
            expectedCurrent: expectedCurrent,
          );
  @override
  Future<List<String>> loadMeaningfulAccountFingerprints() =>
      _delegate.loadMeaningfulAccountFingerprints();
  @override
  Future<PendingDeletionTransaction?> loadPendingDeletionTransaction() =>
      _delegate.loadPendingDeletionTransaction();
  @override
  Future<BeginDeletionTransactionResult> beginDeletionTransaction({
    required String accountFingerprint,
  }) =>
      _delegate.beginDeletionTransaction(
          accountFingerprint: accountFingerprint);
  @override
  Future<AdvanceDeletionTransactionResult> advanceDeletionTransactionStage({
    required String accountFingerprint,
    required DeletionTransactionStage expectedCurrentStage,
    required DeletionTransactionStage nextStage,
  }) =>
      _delegate.advanceDeletionTransactionStage(
        accountFingerprint: accountFingerprint,
        expectedCurrentStage: expectedCurrentStage,
        nextStage: nextStage,
      );
}

/// A [LocalSyncIntentStore] decorator that fails the test outright if
/// [removeIntent] is ever invoked -- the device-wide-intent counterpart to
/// [_MutationForbiddenSyncPersistenceStore], used in the same pre-flight
/// ordering proof.
class _MutationForbiddenLocalSyncIntentStore implements LocalSyncIntentStore {
  _MutationForbiddenLocalSyncIntentStore(this._delegate);

  final LocalSyncIntentStore _delegate;

  @override
  Future<void> removeIntent(String intentId) {
    fail('removeIntent must never be called before the account-mismatch '
        'pre-flight check has completed -- LocalSyncIntentStore is '
        'device-wide, not fingerprint-scoped, so clearing it before that '
        'check could destroy intents belonging to a different, correctly '
        'associated account.');
  }

  @override
  Future<List<LocalSyncIntent>> loadIntents() => _delegate.loadIntents();
  @override
  Future<void> enqueueIntent(LocalSyncIntent intent) =>
      _delegate.enqueueIntent(intent);
  @override
  Future<void> advanceIntentStage({
    required String intentId,
    required LocalSyncIntentStage expectedStage,
    required LocalSyncIntentStage nextStage,
  }) =>
      _delegate.advanceIntentStage(
        intentId: intentId,
        expectedStage: expectedStage,
        nextStage: nextStage,
      );
}

/// A [SyncPersistenceStore] decorator whose [clearAccountState] call
/// succeeds (returns normally, exactly as a real success would look to the
/// caller) without actually removing the underlying bucket -- simulating a
/// persistence-layer defect where a clear call reports success but the
/// write never durably lands. Used only to prove the hard runtime
/// verification gate (REPAIR 2, point 5) independently re-reads durable
/// state with its own fresh calls, rather than trusting any earlier call's
/// own reported outcome.
class _IneffectiveAccountStateClearStore implements SyncPersistenceStore {
  _IneffectiveAccountStateClearStore(this._delegate);

  final SyncPersistenceStore _delegate;

  @override
  Future<void> clearAccountState(String accountFingerprint) async {
    // Deliberately a no-op: reports success without touching the delegate.
  }

  @override
  Future<AccountSyncState?> loadAccountState(String accountFingerprint) =>
      _delegate.loadAccountState(accountFingerprint);
  @override
  Future<void> replaceAccountState(
          String accountFingerprint, AccountSyncState state) =>
      _delegate.replaceAccountState(accountFingerprint, state);
  @override
  Future<void> enqueueMutation(String accountFingerprint, SyncChange change) =>
      _delegate.enqueueMutation(accountFingerprint, change);
  @override
  Future<void> applyMutationOutcomes(
    String accountFingerprint, {
    Set<String> acknowledgedMutationIds = const {},
    Map<String, PersistedOutboxMutationStatus> updatedStatusByMutationId =
        const {},
  }) =>
      _delegate.applyMutationOutcomes(
        accountFingerprint,
        acknowledgedMutationIds: acknowledgedMutationIds,
        updatedStatusByMutationId: updatedStatusByMutationId,
      );
  @override
  Future<List<PersistedOutboxMutation>> readPendingMutations(
          String accountFingerprint) =>
      _delegate.readPendingMutations(accountFingerprint);
  @override
  Future<void> replaceRecordSystemFields(
          String accountFingerprint, String recordName, String systemFields) =>
      _delegate.replaceRecordSystemFields(
          accountFingerprint, recordName, systemFields);
  @override
  Future<void> storeServerChangeToken(
          String accountFingerprint, String serverToken) =>
      _delegate.storeServerChangeToken(accountFingerprint, serverToken);
  @override
  Future<void> clearServerChangeToken(String accountFingerprint) =>
      _delegate.clearServerChangeToken(accountFingerprint);
  @override
  Future<void> quarantineAccountState(String accountFingerprint) =>
      _delegate.quarantineAccountState(accountFingerprint);
  @override
  Future<CommitIncomingBatchCheckpointResult> commitIncomingBatchCheckpoint(
    CommitIncomingBatchCheckpointRequest request,
  ) =>
      _delegate.commitIncomingBatchCheckpoint(request);
  @override
  Future<RetireOutboxMutationResult> retireOutboxMutationIfCurrent(
    RetireOutboxMutationRequest request,
  ) =>
      _delegate.retireOutboxMutationIfCurrent(request);
  @override
  Future<String?> loadAssociatedAccountFingerprint() =>
      _delegate.loadAssociatedAccountFingerprint();
  @override
  Future<ClearAssociatedAccountFingerprintResult>
      clearAssociatedAccountFingerprintIfCurrent({
    required String expectedCurrent,
  }) =>
          _delegate.clearAssociatedAccountFingerprintIfCurrent(
            expectedCurrent: expectedCurrent,
          );
  @override
  Future<CommitAssociatedAccountFingerprintResult>
      commitAssociatedAccountFingerprint({
    required String fingerprint,
    required String? expectedCurrent,
  }) =>
          _delegate.commitAssociatedAccountFingerprint(
            fingerprint: fingerprint,
            expectedCurrent: expectedCurrent,
          );
  @override
  Future<List<String>> loadMeaningfulAccountFingerprints() =>
      _delegate.loadMeaningfulAccountFingerprints();
  @override
  Future<PendingDeletionTransaction?> loadPendingDeletionTransaction() =>
      _delegate.loadPendingDeletionTransaction();
  @override
  Future<BeginDeletionTransactionResult> beginDeletionTransaction({
    required String accountFingerprint,
  }) =>
      _delegate.beginDeletionTransaction(
          accountFingerprint: accountFingerprint);
  @override
  Future<AdvanceDeletionTransactionResult> advanceDeletionTransactionStage({
    required String accountFingerprint,
    required DeletionTransactionStage expectedCurrentStage,
    required DeletionTransactionStage nextStage,
  }) =>
      _delegate.advanceDeletionTransactionStage(
        accountFingerprint: accountFingerprint,
        expectedCurrentStage: expectedCurrentStage,
        nextStage: nextStage,
      );
  @override
  Future<void> clearDeletionTransaction({
    required String accountFingerprint,
  }) =>
      _delegate.clearDeletionTransaction(
          accountFingerprint: accountFingerprint);
}

/// A [SyncPersistenceStore] decorator whose
/// [clearAssociatedAccountFingerprintIfCurrent] call reports `cleared`
/// (exactly as a real success would look to the caller) without actually
/// clearing the underlying marker -- the marker counterpart to
/// [_IneffectiveAccountStateClearStore], used to prove REPAIR 2 point 6.
class _IneffectiveMarkerClearStore implements SyncPersistenceStore {
  _IneffectiveMarkerClearStore(this._delegate);

  final SyncPersistenceStore _delegate;

  @override
  Future<ClearAssociatedAccountFingerprintResult>
      clearAssociatedAccountFingerprintIfCurrent({
    required String expectedCurrent,
  }) async {
    // Deliberately a no-op: reports `cleared` without touching the
    // delegate's own durable marker.
    return const ClearAssociatedAccountFingerprintResult(
      AssociatedAccountFingerprintClearStatus.cleared,
    );
  }

  @override
  Future<void> clearAccountState(String accountFingerprint) =>
      _delegate.clearAccountState(accountFingerprint);
  @override
  Future<AccountSyncState?> loadAccountState(String accountFingerprint) =>
      _delegate.loadAccountState(accountFingerprint);
  @override
  Future<void> replaceAccountState(
          String accountFingerprint, AccountSyncState state) =>
      _delegate.replaceAccountState(accountFingerprint, state);
  @override
  Future<void> enqueueMutation(String accountFingerprint, SyncChange change) =>
      _delegate.enqueueMutation(accountFingerprint, change);
  @override
  Future<void> applyMutationOutcomes(
    String accountFingerprint, {
    Set<String> acknowledgedMutationIds = const {},
    Map<String, PersistedOutboxMutationStatus> updatedStatusByMutationId =
        const {},
  }) =>
      _delegate.applyMutationOutcomes(
        accountFingerprint,
        acknowledgedMutationIds: acknowledgedMutationIds,
        updatedStatusByMutationId: updatedStatusByMutationId,
      );
  @override
  Future<List<PersistedOutboxMutation>> readPendingMutations(
          String accountFingerprint) =>
      _delegate.readPendingMutations(accountFingerprint);
  @override
  Future<void> replaceRecordSystemFields(
          String accountFingerprint, String recordName, String systemFields) =>
      _delegate.replaceRecordSystemFields(
          accountFingerprint, recordName, systemFields);
  @override
  Future<void> storeServerChangeToken(
          String accountFingerprint, String serverToken) =>
      _delegate.storeServerChangeToken(accountFingerprint, serverToken);
  @override
  Future<void> clearServerChangeToken(String accountFingerprint) =>
      _delegate.clearServerChangeToken(accountFingerprint);
  @override
  Future<void> quarantineAccountState(String accountFingerprint) =>
      _delegate.quarantineAccountState(accountFingerprint);
  @override
  Future<CommitIncomingBatchCheckpointResult> commitIncomingBatchCheckpoint(
    CommitIncomingBatchCheckpointRequest request,
  ) =>
      _delegate.commitIncomingBatchCheckpoint(request);
  @override
  Future<RetireOutboxMutationResult> retireOutboxMutationIfCurrent(
    RetireOutboxMutationRequest request,
  ) =>
      _delegate.retireOutboxMutationIfCurrent(request);
  @override
  Future<String?> loadAssociatedAccountFingerprint() =>
      _delegate.loadAssociatedAccountFingerprint();
  @override
  Future<CommitAssociatedAccountFingerprintResult>
      commitAssociatedAccountFingerprint({
    required String fingerprint,
    required String? expectedCurrent,
  }) =>
          _delegate.commitAssociatedAccountFingerprint(
            fingerprint: fingerprint,
            expectedCurrent: expectedCurrent,
          );
  @override
  Future<List<String>> loadMeaningfulAccountFingerprints() =>
      _delegate.loadMeaningfulAccountFingerprints();
  @override
  Future<PendingDeletionTransaction?> loadPendingDeletionTransaction() =>
      _delegate.loadPendingDeletionTransaction();
  @override
  Future<BeginDeletionTransactionResult> beginDeletionTransaction({
    required String accountFingerprint,
  }) =>
      _delegate.beginDeletionTransaction(
          accountFingerprint: accountFingerprint);
  @override
  Future<AdvanceDeletionTransactionResult> advanceDeletionTransactionStage({
    required String accountFingerprint,
    required DeletionTransactionStage expectedCurrentStage,
    required DeletionTransactionStage nextStage,
  }) =>
      _delegate.advanceDeletionTransactionStage(
        accountFingerprint: accountFingerprint,
        expectedCurrentStage: expectedCurrentStage,
        nextStage: nextStage,
      );
  @override
  Future<void> clearDeletionTransaction({
    required String accountFingerprint,
  }) =>
      _delegate.clearDeletionTransaction(
          accountFingerprint: accountFingerprint);
}

/// A [LocalSyncIntentStore] decorator whose [removeIntent] call succeeds
/// (returns normally) without actually removing the underlying intent --
/// the intent counterpart to [_IneffectiveAccountStateClearStore], used to
/// prove REPAIR 2 point 7.
class _IneffectiveIntentRemovalStore implements LocalSyncIntentStore {
  _IneffectiveIntentRemovalStore(this._delegate);

  final LocalSyncIntentStore _delegate;

  @override
  Future<void> removeIntent(String intentId) async {
    // Deliberately a no-op: reports success without touching the delegate.
  }

  @override
  Future<List<LocalSyncIntent>> loadIntents() => _delegate.loadIntents();
  @override
  Future<void> enqueueIntent(LocalSyncIntent intent) =>
      _delegate.enqueueIntent(intent);
  @override
  Future<void> advanceIntentStage({
    required String intentId,
    required LocalSyncIntentStage expectedStage,
    required LocalSyncIntentStage nextStage,
  }) =>
      _delegate.advanceIntentStage(
        intentId: intentId,
        expectedStage: expectedStage,
        nextStage: nextStage,
      );
}

/// A [SyncPersistenceStore] decorator that, at the exact moment
/// [clearDeletionTransaction] is invoked, independently re-reads the
/// transaction's own presence plus the target bucket/marker/intents'
/// already-clean state directly from the delegate/intent store -- proving
/// (REPAIR 2, point 9) that a successful finalize() only calls
/// [clearDeletionTransaction] LAST, after everything else already reads as
/// fully clean.
class _ClearDeletionTransactionObservingStore implements SyncPersistenceStore {
  _ClearDeletionTransactionObservingStore(this._delegate, this._intentStore);

  final SyncPersistenceStore _delegate;
  final LocalSyncIntentStore _intentStore;

  bool clearDeletionTransactionWasCalled = false;
  bool transactionPresentAtCallTime = false;
  bool bucketAlreadyGoneAtCallTime = false;
  bool markerAlreadyGoneAtCallTime = false;
  bool intentsAlreadyGoneAtCallTime = false;

  @override
  Future<void> clearDeletionTransaction({
    required String accountFingerprint,
  }) async {
    clearDeletionTransactionWasCalled = true;
    transactionPresentAtCallTime =
        await _delegate.loadPendingDeletionTransaction() != null;
    bucketAlreadyGoneAtCallTime =
        await _delegate.loadAccountState(accountFingerprint) == null;
    markerAlreadyGoneAtCallTime =
        await _delegate.loadAssociatedAccountFingerprint() !=
            accountFingerprint;
    intentsAlreadyGoneAtCallTime = (await _intentStore.loadIntents()).isEmpty;
    return _delegate.clearDeletionTransaction(
      accountFingerprint: accountFingerprint,
    );
  }

  @override
  Future<void> clearAccountState(String accountFingerprint) =>
      _delegate.clearAccountState(accountFingerprint);
  @override
  Future<AccountSyncState?> loadAccountState(String accountFingerprint) =>
      _delegate.loadAccountState(accountFingerprint);
  @override
  Future<void> replaceAccountState(
          String accountFingerprint, AccountSyncState state) =>
      _delegate.replaceAccountState(accountFingerprint, state);
  @override
  Future<void> enqueueMutation(String accountFingerprint, SyncChange change) =>
      _delegate.enqueueMutation(accountFingerprint, change);
  @override
  Future<void> applyMutationOutcomes(
    String accountFingerprint, {
    Set<String> acknowledgedMutationIds = const {},
    Map<String, PersistedOutboxMutationStatus> updatedStatusByMutationId =
        const {},
  }) =>
      _delegate.applyMutationOutcomes(
        accountFingerprint,
        acknowledgedMutationIds: acknowledgedMutationIds,
        updatedStatusByMutationId: updatedStatusByMutationId,
      );
  @override
  Future<List<PersistedOutboxMutation>> readPendingMutations(
          String accountFingerprint) =>
      _delegate.readPendingMutations(accountFingerprint);
  @override
  Future<void> replaceRecordSystemFields(
          String accountFingerprint, String recordName, String systemFields) =>
      _delegate.replaceRecordSystemFields(
          accountFingerprint, recordName, systemFields);
  @override
  Future<void> storeServerChangeToken(
          String accountFingerprint, String serverToken) =>
      _delegate.storeServerChangeToken(accountFingerprint, serverToken);
  @override
  Future<void> clearServerChangeToken(String accountFingerprint) =>
      _delegate.clearServerChangeToken(accountFingerprint);
  @override
  Future<void> quarantineAccountState(String accountFingerprint) =>
      _delegate.quarantineAccountState(accountFingerprint);
  @override
  Future<CommitIncomingBatchCheckpointResult> commitIncomingBatchCheckpoint(
    CommitIncomingBatchCheckpointRequest request,
  ) =>
      _delegate.commitIncomingBatchCheckpoint(request);
  @override
  Future<RetireOutboxMutationResult> retireOutboxMutationIfCurrent(
    RetireOutboxMutationRequest request,
  ) =>
      _delegate.retireOutboxMutationIfCurrent(request);
  @override
  Future<String?> loadAssociatedAccountFingerprint() =>
      _delegate.loadAssociatedAccountFingerprint();
  @override
  Future<ClearAssociatedAccountFingerprintResult>
      clearAssociatedAccountFingerprintIfCurrent({
    required String expectedCurrent,
  }) =>
          _delegate.clearAssociatedAccountFingerprintIfCurrent(
            expectedCurrent: expectedCurrent,
          );
  @override
  Future<CommitAssociatedAccountFingerprintResult>
      commitAssociatedAccountFingerprint({
    required String fingerprint,
    required String? expectedCurrent,
  }) =>
          _delegate.commitAssociatedAccountFingerprint(
            fingerprint: fingerprint,
            expectedCurrent: expectedCurrent,
          );
  @override
  Future<List<String>> loadMeaningfulAccountFingerprints() =>
      _delegate.loadMeaningfulAccountFingerprints();
  @override
  Future<PendingDeletionTransaction?> loadPendingDeletionTransaction() =>
      _delegate.loadPendingDeletionTransaction();
  @override
  Future<BeginDeletionTransactionResult> beginDeletionTransaction({
    required String accountFingerprint,
  }) =>
      _delegate.beginDeletionTransaction(
          accountFingerprint: accountFingerprint);
  @override
  Future<AdvanceDeletionTransactionResult> advanceDeletionTransactionStage({
    required String accountFingerprint,
    required DeletionTransactionStage expectedCurrentStage,
    required DeletionTransactionStage nextStage,
  }) =>
      _delegate.advanceDeletionTransactionStage(
        accountFingerprint: accountFingerprint,
        expectedCurrentStage: expectedCurrentStage,
        nextStage: nextStage,
      );
}

void main() {
  group('point 1-2: gating (no transaction / wrong stage)', () {
    test('1. no transaction -> no finalize mutation of any kind', () async {
      final store = InMemorySyncPersistenceStore();
      final intentStore = InMemoryLocalSyncIntentStore();
      await intentStore.enqueueIntent(_keepIntent());
      store.seedAccount(
          _fingerprint(1),
          AccountSyncState.empty(
            DataEpoch.generate(),
          ));
      store.seedAssociatedAccountFingerprint(_fingerprint(1));
      final finalizer = LocalDeletionFinalizer(
        syncPersistenceStore: store,
        localSyncIntentStore: intentStore,
      );

      final result = await finalizer.finalize();

      expect(result.outcome, LocalDeletionFinalizeOutcome.noPendingTransaction);
      expect(result.clearedIntentCount, 0);
      expect(result.markerCleared, isFalse);
      expect(await intentStore.loadIntents(), hasLength(1),
          reason: 'Nothing was cleared -- no transaction ever existed.');
      expect(await store.loadAccountState(_fingerprint(1)), isNotNull);
      expect(await store.loadAssociatedAccountFingerprint(), _fingerprint(1));
    });

    test(
        '2. a transaction exists but its stage is before '
        'localFinalizePending -> no local finalize', () async {
      for (final stage in [
        DeletionTransactionStage.prepared,
        DeletionTransactionStage.epochBarrierPending,
        DeletionTransactionStage.cloudPurgePending,
        DeletionTransactionStage.verificationPending,
      ]) {
        final store = InMemorySyncPersistenceStore();
        final intentStore = InMemoryLocalSyncIntentStore();
        await intentStore.enqueueIntent(_keepIntent());
        store.seedAccount(
          _fingerprint(1),
          AccountSyncState.empty(DataEpoch.generate()),
        );
        store.seedAssociatedAccountFingerprint(_fingerprint(1));
        store.seedPendingDeletionTransaction(
          _transaction(fingerprint: _fingerprint(1), stage: stage),
        );
        final finalizer = LocalDeletionFinalizer(
          syncPersistenceStore: store,
          localSyncIntentStore: intentStore,
        );

        final result = await finalizer.finalize();

        expect(
          result.outcome,
          LocalDeletionFinalizeOutcome.notYetAtLocalFinalizeStage,
          reason: 'Stage $stage must not trigger local finalize.',
        );
        expect(await intentStore.loadIntents(), hasLength(1));
        expect(await store.loadAccountState(_fingerprint(1)), isNotNull);
        expect(await store.loadAssociatedAccountFingerprint(), _fingerprint(1));
        expect(await store.loadPendingDeletionTransaction(), isNotNull);
      }
    });
  });

  group('point 3, 9-15: localFinalizePending begins full cleanup', () {
    test(
        '3, 9-15. localFinalizePending begins cleanup: intents cleared, '
        'AccountSyncState bucket (outbox/token/system fields/bootstrap '
        'state) removed, association marker removed', () async {
      final store = InMemorySyncPersistenceStore();
      final intentStore = InMemoryLocalSyncIntentStore();
      await intentStore.enqueueIntent(_keepIntent());
      final bucketEpoch = DataEpoch.generate();
      store.seedAccount(
        _fingerprint(1),
        AccountSyncState(
          dataEpoch: bucketEpoch,
          serverChangeToken: 'b3B0b2tlbg==',
          recordSystemFields: const {
            'east-kept-$_revealIdA': 'c3lzdGVtRmllbGRz',
          },
          outbox: [
            PersistedOutboxMutation(
              change: _syncChangeFixture(bucketEpoch),
            ),
          ],
          bootstrapState: AccountBootstrapState.complete,
        ),
      );
      store.seedAssociatedAccountFingerprint(_fingerprint(1));
      store.seedPendingDeletionTransaction(
        _transaction(
          fingerprint: _fingerprint(1),
          stage: DeletionTransactionStage.localFinalizePending,
        ),
      );
      final finalizer = LocalDeletionFinalizer(
        syncPersistenceStore: store,
        localSyncIntentStore: intentStore,
      );

      final result = await finalizer.finalize();

      expect(result.outcome, LocalDeletionFinalizeOutcome.finalized);
      expect(result.clearedIntentCount, 1);
      expect(result.markerCleared, isTrue);
      expect(await intentStore.loadIntents(), isEmpty, reason: 'point 9');
      final residualState = await store.loadAccountState(_fingerprint(1));
      expect(residualState, isNull,
          reason: 'point 10/11/12/13/14: the whole bucket -- outbox, '
              'server token, system fields, and bootstrap state alike -- '
              'is gone in one atomic clearAccountState call.');
      expect(await store.loadAssociatedAccountFingerprint(), isNull,
          reason: 'point 15');
      expect(await store.loadPendingDeletionTransaction(), isNull);
    });
  });

  group(
      'REPAIR 1 (points 1-4): account mismatch is a pre-flight, '
      'zero-mutation check', () {
    test(
        '1-4. a durable marker naming a DIFFERENT account causes '
        'accountMismatch with ZERO local cleanup mutation of any kind: '
        'LocalSyncIntents are left intact (point 2), the transaction\'s own '
        'target AccountSyncState is left untouched (point 3), the '
        'transaction itself is left intact (point 4), and the different '
        'account\'s own bucket/marker are never retargeted (point 1)',
        () async {
      final store = InMemorySyncPersistenceStore();
      final intentStore = InMemoryLocalSyncIntentStore();
      await intentStore.enqueueIntent(_keepIntent());
      final target = _fingerprint(1);
      final otherAccount = _fingerprint(2);
      store.seedAccount(
        otherAccount,
        AccountSyncState.empty(DataEpoch.generate()),
      );
      // The durable marker currently names a DIFFERENT account than the
      // transaction's own target -- e.g. the user signed into a different
      // iCloud account on this device after Slice 2's own remote
      // verification completed.
      store.seedAssociatedAccountFingerprint(otherAccount);
      final transaction = _transaction(
        fingerprint: target,
        stage: DeletionTransactionStage.localFinalizePending,
      );
      store.seedPendingDeletionTransaction(transaction);
      final finalizer = LocalDeletionFinalizer(
        syncPersistenceStore: store,
        localSyncIntentStore: intentStore,
      );

      final result = await finalizer.finalize();

      expect(result.outcome, LocalDeletionFinalizeOutcome.accountMismatch);
      expect(result.clearedIntentCount, 0);
      expect(result.markerCleared, isFalse);
      expect(await intentStore.loadIntents(), hasLength(1),
          reason: 'point 2: a mismatched marker must leave device-wide '
              'LocalSyncIntents completely untouched -- detected before '
              'the intent-clearing loop ever runs, not merely skipped '
              'partway through it.');
      expect(await store.loadAccountState(target), isNull,
          reason: 'point 3: the transaction\'s own target never had a '
              'bucket, and none was created or touched.');
      expect(await store.loadAccountState(otherAccount), isNotNull,
          reason: 'point 1: the different (currently-associated) '
              'account\'s own bucket is never touched, retargeted, or '
              'cleared just because an unrelated transaction named a '
              'different fingerprint.');
      expect(await store.loadAssociatedAccountFingerprint(), otherAccount,
          reason: 'a marker naming a different account is never cleared, '
              'overwritten, or retargeted.');
      expect(await store.loadPendingDeletionTransaction(), transaction,
          reason: 'point 4: the deletion transaction itself is left '
              'completely intact -- still durable, still at '
              'localFinalizePending, so a future account switch back can '
              'resume finalize correctly.');
    });

    test(
        'account mismatch is detected strictly BEFORE any mutating call -- '
        'proven by a store/intent-store pair that fails the test outright '
        'if any mutation is even attempted', () async {
      final store = InMemorySyncPersistenceStore();
      final intentStore = InMemoryLocalSyncIntentStore();
      await intentStore.enqueueIntent(_keepIntent());
      final target = _fingerprint(1);
      final otherAccount = _fingerprint(2);
      store.seedAccount(
        otherAccount,
        AccountSyncState.empty(DataEpoch.generate()),
      );
      store.seedAssociatedAccountFingerprint(otherAccount);
      store.seedPendingDeletionTransaction(
        _transaction(
          fingerprint: target,
          stage: DeletionTransactionStage.localFinalizePending,
        ),
      );
      final mutationForbiddenStore = _MutationForbiddenSyncPersistenceStore(
        store,
      );
      final mutationForbiddenIntentStore =
          _MutationForbiddenLocalSyncIntentStore(intentStore);
      final finalizer = LocalDeletionFinalizer(
        syncPersistenceStore: mutationForbiddenStore,
        localSyncIntentStore: mutationForbiddenIntentStore,
      );

      final result = await finalizer.finalize();

      expect(result.outcome, LocalDeletionFinalizeOutcome.accountMismatch);
      // Reaching this line at all (rather than a thrown
      // "mutation attempted" failure from the decorators below) is itself
      // the proof: the pre-flight check ran, and returned, before any
      // mutating method was ever invoked.
    });
  });

  group('point 18: transaction cleared only after cleanup verification', () {
    test(
        '18. the deletion transaction is still present at the moment '
        'clearAccountState/clearAssociatedAccountFingerprintIfCurrent are '
        'called, and only removed afterward', () async {
      final store = InMemorySyncPersistenceStore();
      final intentStore = InMemoryLocalSyncIntentStore();
      store.seedAccount(
        _fingerprint(1),
        AccountSyncState.empty(DataEpoch.generate()),
      );
      store.seedAssociatedAccountFingerprint(_fingerprint(1));
      store.seedPendingDeletionTransaction(
        _transaction(
          fingerprint: _fingerprint(1),
          stage: DeletionTransactionStage.localFinalizePending,
        ),
      );
      final observed = <bool>[];
      final observingStore = _TransactionPresenceObservingStore(
        store,
        onClearAccountState: () async =>
            observed.add(await store.loadPendingDeletionTransaction() != null),
        onClearMarker: () async =>
            observed.add(await store.loadPendingDeletionTransaction() != null),
      );
      final finalizer = LocalDeletionFinalizer(
        syncPersistenceStore: observingStore,
        localSyncIntentStore: intentStore,
      );

      await finalizer.finalize();

      expect(observed, [true, true],
          reason: 'The transaction must still exist at the moment of both '
              'the account-bucket clear and the marker clear -- it is only '
              'removed last, after both are durably confirmed.');
      expect(await store.loadPendingDeletionTransaction(), isNull);
    });
  });

  group('point 19-22: crash-safety -- every step is independently resumable',
      () {
    test(
        'crash before any cleanup begins (during the very first '
        'loadIntents read) resumes cleanly on retry -- the "crash before '
        'any cleanup" case the instruction\'s own atomicity section '
        'requires alongside points 19-22', () async {
      final store = InMemorySyncPersistenceStore();
      final intentStore = InMemoryLocalSyncIntentStore();
      await intentStore.enqueueIntent(_keepIntent());
      store.seedAccount(
        _fingerprint(1),
        AccountSyncState.empty(DataEpoch.generate()),
      );
      store.seedAssociatedAccountFingerprint(_fingerprint(1));
      store.seedPendingDeletionTransaction(
        _transaction(
          fingerprint: _fingerprint(1),
          stage: DeletionTransactionStage.localFinalizePending,
        ),
      );
      final crashingIntentStore =
          _CrashInjectingLocalSyncIntentStore(intentStore)
            ..throwOnLoadIntents = true;
      final finalizer = LocalDeletionFinalizer(
        syncPersistenceStore: store,
        localSyncIntentStore: crashingIntentStore,
      );

      await expectLater(finalizer.finalize(), throwsA(anything));
      // Absolutely nothing was touched yet.
      expect(await intentStore.loadIntents(), hasLength(1));
      expect(await store.loadAccountState(_fingerprint(1)), isNotNull);
      expect(await store.loadAssociatedAccountFingerprint(), _fingerprint(1));
      expect(await store.loadPendingDeletionTransaction(), isNotNull);

      final result = await finalizer.finalize();
      expect(result.outcome, LocalDeletionFinalizeOutcome.finalized);
      expect(await intentStore.loadIntents(), isEmpty);
      expect(await store.loadAccountState(_fingerprint(1)), isNull);
      expect(await store.loadAssociatedAccountFingerprint(), isNull);
      expect(await store.loadPendingDeletionTransaction(), isNull);
    });

    test('19. crash after intent cleanup resumes cleanly on retry', () async {
      final store = InMemorySyncPersistenceStore();
      final intentStore = InMemoryLocalSyncIntentStore();
      await intentStore.enqueueIntent(_keepIntent());
      store.seedAccount(
        _fingerprint(1),
        AccountSyncState.empty(DataEpoch.generate()),
      );
      store.seedAssociatedAccountFingerprint(_fingerprint(1));
      store.seedPendingDeletionTransaction(
        _transaction(
          fingerprint: _fingerprint(1),
          stage: DeletionTransactionStage.localFinalizePending,
        ),
      );
      final crashingStore = _CrashInjectingSyncPersistenceStore(store)
        ..throwOnClearAccountState = true;
      final finalizer = LocalDeletionFinalizer(
        syncPersistenceStore: crashingStore,
        localSyncIntentStore: intentStore,
      );

      await expectLater(finalizer.finalize(), throwsA(anything));
      // Intent cleanup itself already durably completed before the crash.
      expect(await intentStore.loadIntents(), isEmpty);
      expect(await store.loadPendingDeletionTransaction(), isNotNull,
          reason: 'Transaction must still exist -- crash happened before '
              'cleanup was verified complete.');

      // Retry converges.
      final result = await finalizer.finalize();
      expect(result.outcome, LocalDeletionFinalizeOutcome.finalized);
      expect(await store.loadAccountState(_fingerprint(1)), isNull);
      expect(await store.loadAssociatedAccountFingerprint(), isNull);
      expect(await store.loadPendingDeletionTransaction(), isNull);
    });

    test('20. crash after bucket cleanup resumes cleanly on retry', () async {
      final store = InMemorySyncPersistenceStore();
      final intentStore = InMemoryLocalSyncIntentStore();
      store.seedAccount(
        _fingerprint(1),
        AccountSyncState.empty(DataEpoch.generate()),
      );
      store.seedAssociatedAccountFingerprint(_fingerprint(1));
      store.seedPendingDeletionTransaction(
        _transaction(
          fingerprint: _fingerprint(1),
          stage: DeletionTransactionStage.localFinalizePending,
        ),
      );
      final crashingStore = _CrashInjectingSyncPersistenceStore(store)
        ..throwOnClearAssociatedMarker = true;
      final finalizer = LocalDeletionFinalizer(
        syncPersistenceStore: crashingStore,
        localSyncIntentStore: intentStore,
      );

      await expectLater(finalizer.finalize(), throwsA(anything));
      expect(await store.loadAccountState(_fingerprint(1)), isNull,
          reason: 'Bucket cleanup already durably completed before the '
              'crash.');
      expect(await store.loadPendingDeletionTransaction(), isNotNull);

      final result = await finalizer.finalize();
      expect(result.outcome, LocalDeletionFinalizeOutcome.finalized);
      expect(await store.loadAssociatedAccountFingerprint(), isNull);
      expect(await store.loadPendingDeletionTransaction(), isNull);
    });

    test('21. crash after association cleanup resumes cleanly on retry',
        () async {
      final store = InMemorySyncPersistenceStore();
      final intentStore = InMemoryLocalSyncIntentStore();
      store.seedAccount(
        _fingerprint(1),
        AccountSyncState.empty(DataEpoch.generate()),
      );
      store.seedAssociatedAccountFingerprint(_fingerprint(1));
      store.seedPendingDeletionTransaction(
        _transaction(
          fingerprint: _fingerprint(1),
          stage: DeletionTransactionStage.localFinalizePending,
        ),
      );
      final crashingStore = _CrashInjectingSyncPersistenceStore(store)
        ..throwOnClearDeletionTransaction = true;
      final finalizer = LocalDeletionFinalizer(
        syncPersistenceStore: crashingStore,
        localSyncIntentStore: intentStore,
      );

      await expectLater(finalizer.finalize(), throwsA(anything));
      expect(await store.loadAccountState(_fingerprint(1)), isNull);
      expect(await store.loadAssociatedAccountFingerprint(), isNull,
          reason: 'Marker cleanup already durably completed before the '
              'crash.');
      expect(await store.loadPendingDeletionTransaction(), isNotNull,
          reason: 'Only the final transaction-clear step failed.');

      final result = await finalizer.finalize();
      expect(result.outcome, LocalDeletionFinalizeOutcome.finalized);
      expect(await store.loadPendingDeletionTransaction(), isNull);
    });

    test(
        '22. an exception thrown during the post-cleanup verification read '
        '-- after both the bucket and the marker are already durably gone '
        '-- is caught internally (REPAIR 2: never allowed to escape as an '
        'ambient uncaught exception) and reported as verificationFailed, '
        'leaving the transaction durable; a subsequent retry then resumes '
        'and finalizes cleanly', () async {
      final store = InMemorySyncPersistenceStore();
      final intentStore = InMemoryLocalSyncIntentStore();
      store.seedAccount(
        _fingerprint(1),
        AccountSyncState.empty(DataEpoch.generate()),
      );
      store.seedAssociatedAccountFingerprint(_fingerprint(1));
      store.seedPendingDeletionTransaction(
        _transaction(
          fingerprint: _fingerprint(1),
          stage: DeletionTransactionStage.localFinalizePending,
        ),
      );
      final crashingStore = _CrashInjectingSyncPersistenceStore(store)
        ..throwOnVerificationRead = true;
      final finalizer = LocalDeletionFinalizer(
        syncPersistenceStore: crashingStore,
        localSyncIntentStore: intentStore,
      );

      final firstResult = await finalizer.finalize();

      expect(
          firstResult.outcome, LocalDeletionFinalizeOutcome.verificationFailed,
          reason: 'REPAIR 2: a verification-read exception must be caught '
              'and converted into a typed, fail-closed result -- never left '
              'to propagate as an ambient uncaught exception with unclear '
              'transaction state.');
      expect(await store.loadAccountState(_fingerprint(1)), isNull,
          reason: 'Both cleanup steps already durably completed before the '
              'exception -- only the verification read (and therefore the '
              'final transaction clear gated behind it) failed.');
      expect(await store.loadAssociatedAccountFingerprint(), isNull);
      expect(await store.loadPendingDeletionTransaction(), isNotNull,
          reason: 'The transaction must remain fully durable -- verification '
              'never completed, so clearDeletionTransaction must never run.');

      final result = await finalizer.finalize();
      expect(result.outcome, LocalDeletionFinalizeOutcome.finalized);
      expect(await store.loadPendingDeletionTransaction(), isNull);
    });
  });

  group(
      'REPAIR 2 (points 5-9): the hard runtime verification gate is real '
      'control flow, not assert()', () {
    test(
        '5. runtime verification detects a surviving target AccountSyncState '
        '(e.g. the underlying clearAccountState call silently failed to '
        'take effect) and does NOT clear the transaction', () async {
      final store = InMemorySyncPersistenceStore();
      final intentStore = InMemoryLocalSyncIntentStore();
      store.seedAccount(
        _fingerprint(1),
        AccountSyncState.empty(DataEpoch.generate()),
      );
      store.seedAssociatedAccountFingerprint(_fingerprint(1));
      store.seedPendingDeletionTransaction(
        _transaction(
          fingerprint: _fingerprint(1),
          stage: DeletionTransactionStage.localFinalizePending,
        ),
      );
      final ineffectiveStore = _IneffectiveAccountStateClearStore(store);
      final finalizer = LocalDeletionFinalizer(
        syncPersistenceStore: ineffectiveStore,
        localSyncIntentStore: intentStore,
      );

      final result = await finalizer.finalize();

      expect(result.outcome, LocalDeletionFinalizeOutcome.verificationFailed);
      expect(await store.loadAccountState(_fingerprint(1)), isNotNull,
          reason: 'sanity: the bucket genuinely still exists -- the clear '
              'call reported success but never actually took effect.');
      expect(await store.loadPendingDeletionTransaction(), isNotNull,
          reason: 'A surviving target AccountSyncState bucket must block '
              'the transaction clear, independent of what the earlier '
              'clearAccountState call itself reported.');
    });

    test(
        '6. runtime verification detects a surviving association marker '
        '(e.g. the underlying clear call silently failed to take effect) '
        'and does NOT clear the transaction', () async {
      final store = InMemorySyncPersistenceStore();
      final intentStore = InMemoryLocalSyncIntentStore();
      store.seedAccount(
        _fingerprint(1),
        AccountSyncState.empty(DataEpoch.generate()),
      );
      store.seedAssociatedAccountFingerprint(_fingerprint(1));
      store.seedPendingDeletionTransaction(
        _transaction(
          fingerprint: _fingerprint(1),
          stage: DeletionTransactionStage.localFinalizePending,
        ),
      );
      final ineffectiveStore = _IneffectiveMarkerClearStore(store);
      final finalizer = LocalDeletionFinalizer(
        syncPersistenceStore: ineffectiveStore,
        localSyncIntentStore: intentStore,
      );

      final result = await finalizer.finalize();

      expect(result.outcome, LocalDeletionFinalizeOutcome.verificationFailed);
      expect(await store.loadAssociatedAccountFingerprint(), _fingerprint(1),
          reason: 'sanity: the marker genuinely still names the target -- '
              'the clear call reported success but never actually took '
              'effect.');
      expect(await store.loadPendingDeletionTransaction(), isNotNull,
          reason: 'A surviving association marker must block the '
              'transaction clear, independent of what the earlier clear '
              'call itself reported.');
    });

    test(
        '7. runtime verification detects surviving LocalSyncIntents (e.g. '
        'the underlying removeIntent call silently failed to take effect) '
        'and does NOT clear the transaction', () async {
      final store = InMemorySyncPersistenceStore();
      final intentStore = InMemoryLocalSyncIntentStore();
      await intentStore.enqueueIntent(_keepIntent());
      store.seedAccount(
        _fingerprint(1),
        AccountSyncState.empty(DataEpoch.generate()),
      );
      store.seedAssociatedAccountFingerprint(_fingerprint(1));
      store.seedPendingDeletionTransaction(
        _transaction(
          fingerprint: _fingerprint(1),
          stage: DeletionTransactionStage.localFinalizePending,
        ),
      );
      final ineffectiveIntentStore =
          _IneffectiveIntentRemovalStore(intentStore);
      final finalizer = LocalDeletionFinalizer(
        syncPersistenceStore: store,
        localSyncIntentStore: ineffectiveIntentStore,
      );

      final result = await finalizer.finalize();

      expect(result.outcome, LocalDeletionFinalizeOutcome.verificationFailed);
      expect(await intentStore.loadIntents(), hasLength(1),
          reason: 'sanity: the intent genuinely still exists -- the removal '
              'call reported success but never actually took effect.');
      expect(await store.loadPendingDeletionTransaction(), isNotNull,
          reason: 'Surviving LocalSyncIntents must block the transaction '
              'clear, independent of what the earlier removal calls '
              'themselves reported.');
    });

    test(
        '9. a successful runtime verification clears the transaction LAST -- '
        'only after the bucket, marker, and intents already read as fully '
        'clean at the moment clearDeletionTransaction is invoked', () async {
      final store = InMemorySyncPersistenceStore();
      final intentStore = InMemoryLocalSyncIntentStore();
      await intentStore.enqueueIntent(_keepIntent());
      store.seedAccount(
        _fingerprint(1),
        AccountSyncState.empty(DataEpoch.generate()),
      );
      store.seedAssociatedAccountFingerprint(_fingerprint(1));
      store.seedPendingDeletionTransaction(
        _transaction(
          fingerprint: _fingerprint(1),
          stage: DeletionTransactionStage.localFinalizePending,
        ),
      );
      final observingStore =
          _ClearDeletionTransactionObservingStore(store, intentStore);
      final finalizer = LocalDeletionFinalizer(
        syncPersistenceStore: observingStore,
        localSyncIntentStore: intentStore,
      );

      final result = await finalizer.finalize();

      expect(result.outcome, LocalDeletionFinalizeOutcome.finalized);
      expect(observingStore.clearDeletionTransactionWasCalled, isTrue);
      expect(observingStore.transactionPresentAtCallTime, isTrue,
          reason: 'the transaction must still exist at the moment '
              'clearDeletionTransaction is invoked -- it is that very call '
              'which removes it, never a call made after it was already '
              'gone.');
      expect(observingStore.bucketAlreadyGoneAtCallTime, isTrue,
          reason: 'the target bucket must already read as gone by the time '
              'the transaction is cleared.');
      expect(observingStore.markerAlreadyGoneAtCallTime, isTrue,
          reason: 'the association marker must already read as gone by the '
              'time the transaction is cleared.');
      expect(observingStore.intentsAlreadyGoneAtCallTime, isTrue,
          reason: 'LocalSyncIntents must already read as empty by the time '
              'the transaction is cleared.');
      expect(await store.loadPendingDeletionTransaction(), isNull);
    });
  });

  group(
      'REPAIR 1 crash-resume (point 10): a null marker at call start is '
      'never treated as a mismatch', () {
    test(
        '10. a null (already-clear) association marker at the very start '
        'of finalize() -- simulating resumption after a prior attempt '
        'crashed after clearing the marker but before clearing the '
        'transaction -- still finalizes successfully', () async {
      final store = InMemorySyncPersistenceStore();
      final intentStore = InMemoryLocalSyncIntentStore();
      await intentStore.enqueueIntent(_keepIntent());
      store.seedAccount(
        _fingerprint(1),
        AccountSyncState.empty(DataEpoch.generate()),
      );
      // Deliberately no `seedAssociatedAccountFingerprint` call -- the
      // marker is durably null before this finalize() call ever starts.
      store.seedPendingDeletionTransaction(
        _transaction(
          fingerprint: _fingerprint(1),
          stage: DeletionTransactionStage.localFinalizePending,
        ),
      );
      final finalizer = LocalDeletionFinalizer(
        syncPersistenceStore: store,
        localSyncIntentStore: intentStore,
      );

      final result = await finalizer.finalize();

      expect(result.outcome, LocalDeletionFinalizeOutcome.finalized,
          reason: 'REPAIR 1: a null marker must never be treated as a '
              'mismatch -- it is exactly the safe crash-resume case a '
              'prior, partially-completed attempt leaves behind.');
      expect(result.markerCleared, isFalse,
          reason: 'the marker was already clear before this call started, '
              'so this call\'s own clear attempt is an alreadyClear no-op, '
              'not a fresh "cleared" transition.');
      expect(await store.loadAccountState(_fingerprint(1)), isNull);
      expect(await intentStore.loadIntents(), isEmpty);
      expect(await store.loadPendingDeletionTransaction(), isNull);
    });
  });

  group(
      'REPAIR 2 (point 11): the production correctness path has zero '
      'dependency on assert()', () {
    test(
        '11. local_deletion_finalizer.dart never uses assert() -- the hard '
        'runtime verification gate before clearDeletionTransaction is '
        'ordinary, always-executed control flow (if/try-catch), so it '
        'behaves identically in debug and release/profile builds', () {
      final file = File('lib/sync_deletion/local_deletion_finalizer.dart');
      expect(file.existsSync(), isTrue);
      final source = file.readAsStringSync();
      expect(
        source.contains('assert('),
        isFalse,
        reason: 'assert() is stripped entirely in release/profile builds -- '
            'the correctness gate deciding whether clearDeletionTransaction '
            'may run must never depend on it. This file must use ordinary '
            'if/try-catch control flow for that gate instead, which is what '
            'this test proves by confirming the literal construct is '
            'entirely absent from the file.',
      );
    });
  });

  group('point 23-24: idempotency of the successful final state', () {
    test('23. repeated finalizer call after success is idempotent', () async {
      final store = InMemorySyncPersistenceStore();
      final intentStore = InMemoryLocalSyncIntentStore();
      await intentStore.enqueueIntent(_keepIntent());
      store.seedAccount(
        _fingerprint(1),
        AccountSyncState.empty(DataEpoch.generate()),
      );
      store.seedAssociatedAccountFingerprint(_fingerprint(1));
      store.seedPendingDeletionTransaction(
        _transaction(
          fingerprint: _fingerprint(1),
          stage: DeletionTransactionStage.localFinalizePending,
        ),
      );
      final finalizer = LocalDeletionFinalizer(
        syncPersistenceStore: store,
        localSyncIntentStore: intentStore,
      );

      final first = await finalizer.finalize();
      expect(first.outcome, LocalDeletionFinalizeOutcome.finalized);

      final second = await finalizer.finalize();
      expect(second.outcome, LocalDeletionFinalizeOutcome.noPendingTransaction,
          reason: 'The transaction is gone -- a repeat call is a safe, '
              'content-free no-op, never a re-finalize of a fingerprint the '
              'caller no longer has.');
    });

    test(
        '24. the successful final state contains no old-account sync '
        'metadata of any kind', () async {
      final store = InMemorySyncPersistenceStore();
      final intentStore = InMemoryLocalSyncIntentStore();
      await intentStore.enqueueIntent(_keepIntent());
      store.seedAccount(
        _fingerprint(1),
        AccountSyncState(
          dataEpoch: DataEpoch.generate(),
          serverChangeToken: 'b3B0b2tlbg==',
          recordSystemFields: const {
            'east-kept-$_revealIdA': 'c3lzdGVtRmllbGRz',
          },
          bootstrapState: AccountBootstrapState.complete,
        ),
      );
      store.seedAssociatedAccountFingerprint(_fingerprint(1));
      store.seedPendingDeletionTransaction(
        _transaction(
          fingerprint: _fingerprint(1),
          stage: DeletionTransactionStage.localFinalizePending,
        ),
      );
      final finalizer = LocalDeletionFinalizer(
        syncPersistenceStore: store,
        localSyncIntentStore: intentStore,
      );

      await finalizer.finalize();

      expect(await store.loadAccountState(_fingerprint(1)), isNull);
      expect(await store.loadAssociatedAccountFingerprint(), isNull);
      expect(await store.loadMeaningfulAccountFingerprints(), isEmpty);
      expect(await intentStore.loadIntents(), isEmpty);
      expect(await store.loadPendingDeletionTransaction(), isNull);
    });
  });

  group('points 4-8, 25: never touches user content or unrelated state', () {
    test(
        '4-8, 25: LocalDeletionFinalizer has zero dependency on any '
        'Kept/Reflection/daily-access/Keeper-entitlement type -- structural '
        'proof by source inspection, mirroring this codebase\'s established '
        'layering-test convention', () {
      final file = File('lib/sync_deletion/local_deletion_finalizer.dart');
      expect(file.existsSync(), isTrue);
      final source = file.readAsStringSync();
      const forbiddenImportFragments = [
        'kept_repository',
        'saved_reflections_service',
        'daily_access_repository',
        'daily_wisdom_access_service',
        'purchase_service',
        'kept_state_store',
        'kept_state_envelope',
      ];
      for (final fragment in forbiddenImportFragments) {
        expect(
          source.contains(fragment),
          isFalse,
          reason: 'local_deletion_finalizer.dart must never import or '
              'reference "$fragment" -- it never reads or mutates Kept '
              'content, Reflection content, revealId occurrence identity, '
              'daily wisdom access state, or Keeper entitlement. Only '
              'SyncPersistenceStore (sync metadata) and LocalSyncIntentStore '
              '(sync intent metadata) are ever touched.',
        );
      }
      // The finalizer's own constructor signature is the second half of
      // this structural proof: it is physically incapable of touching Kept/
      // Reflection storage because it is never given a reference to it.
      expect(
        source.contains(
          'required SyncPersistenceStore syncPersistenceStore,\n'
          '    required LocalSyncIntentStore localSyncIntentStore,',
        ),
        isTrue,
        reason: 'The constructor must accept exactly these two '
            'dependencies -- never a KeptRepository or '
            'SavedReflectionsService.',
      );
    });
  });
}

/// A minimal, valid [SyncChange] fixture -- content is never inspected by
/// [LocalDeletionFinalizer] (only the surrounding [AccountSyncState] bucket
/// as a whole is atomically removed), so any structurally-valid `keep`
/// change works. Built via [CloudKeptWisdomProjection.tryParseRemote] (a raw
/// map) rather than [CloudKeptWisdomProjection.active] so this file never
/// needs a `KeptRecord` fixture of its own.
SyncChange _syncChangeFixture(DataEpoch dataEpoch) {
  final projection = CloudKeptWisdomProjection.tryParseRemote({
    'recordName': 'east-kept-$_revealIdA',
    'isTombstone': false,
    'revealId': _revealIdA,
    'wisdomText': 'Synthetic wisdom text for testing only.',
    'revealedAtMs': 1000,
    'keptAtMs': 2000,
    'updatedAtMs': 3000,
    'mutationId': _mutationId1,
    'dataEpoch': dataEpoch.value,
    'schemaVersion': 3,
  })!;
  return SyncChange(
    kind: SyncChangeKind.create,
    projection: projection,
    enqueuedAt: DateTime.utc(2026, 8, 1),
  );
}

/// A thin forwarding [SyncPersistenceStore] decorator used only by test 18,
/// to observe whether the deletion transaction is still present at the
/// exact moment two specific cleanup calls happen.
class _TransactionPresenceObservingStore implements SyncPersistenceStore {
  _TransactionPresenceObservingStore(
    this._delegate, {
    required this.onClearAccountState,
    required this.onClearMarker,
  });

  final SyncPersistenceStore _delegate;
  final Future<void> Function() onClearAccountState;
  final Future<void> Function() onClearMarker;

  @override
  Future<void> clearAccountState(String accountFingerprint) async {
    await onClearAccountState();
    return _delegate.clearAccountState(accountFingerprint);
  }

  @override
  Future<ClearAssociatedAccountFingerprintResult>
      clearAssociatedAccountFingerprintIfCurrent({
    required String expectedCurrent,
  }) async {
    await onClearMarker();
    return _delegate.clearAssociatedAccountFingerprintIfCurrent(
      expectedCurrent: expectedCurrent,
    );
  }

  @override
  Future<void> clearDeletionTransaction({
    required String accountFingerprint,
  }) =>
      _delegate.clearDeletionTransaction(
          accountFingerprint: accountFingerprint);
  @override
  Future<AccountSyncState?> loadAccountState(String accountFingerprint) =>
      _delegate.loadAccountState(accountFingerprint);
  @override
  Future<void> replaceAccountState(
          String accountFingerprint, AccountSyncState state) =>
      _delegate.replaceAccountState(accountFingerprint, state);
  @override
  Future<void> enqueueMutation(String accountFingerprint, SyncChange change) =>
      _delegate.enqueueMutation(accountFingerprint, change);
  @override
  Future<void> applyMutationOutcomes(
    String accountFingerprint, {
    Set<String> acknowledgedMutationIds = const {},
    Map<String, PersistedOutboxMutationStatus> updatedStatusByMutationId =
        const {},
  }) =>
      _delegate.applyMutationOutcomes(
        accountFingerprint,
        acknowledgedMutationIds: acknowledgedMutationIds,
        updatedStatusByMutationId: updatedStatusByMutationId,
      );
  @override
  Future<List<PersistedOutboxMutation>> readPendingMutations(
          String accountFingerprint) =>
      _delegate.readPendingMutations(accountFingerprint);
  @override
  Future<void> replaceRecordSystemFields(
          String accountFingerprint, String recordName, String systemFields) =>
      _delegate.replaceRecordSystemFields(
          accountFingerprint, recordName, systemFields);
  @override
  Future<void> storeServerChangeToken(
          String accountFingerprint, String serverToken) =>
      _delegate.storeServerChangeToken(accountFingerprint, serverToken);
  @override
  Future<void> clearServerChangeToken(String accountFingerprint) =>
      _delegate.clearServerChangeToken(accountFingerprint);
  @override
  Future<void> quarantineAccountState(String accountFingerprint) =>
      _delegate.quarantineAccountState(accountFingerprint);
  @override
  Future<CommitIncomingBatchCheckpointResult> commitIncomingBatchCheckpoint(
    CommitIncomingBatchCheckpointRequest request,
  ) =>
      _delegate.commitIncomingBatchCheckpoint(request);
  @override
  Future<RetireOutboxMutationResult> retireOutboxMutationIfCurrent(
    RetireOutboxMutationRequest request,
  ) =>
      _delegate.retireOutboxMutationIfCurrent(request);
  @override
  Future<String?> loadAssociatedAccountFingerprint() =>
      _delegate.loadAssociatedAccountFingerprint();
  @override
  Future<CommitAssociatedAccountFingerprintResult>
      commitAssociatedAccountFingerprint({
    required String fingerprint,
    required String? expectedCurrent,
  }) =>
          _delegate.commitAssociatedAccountFingerprint(
            fingerprint: fingerprint,
            expectedCurrent: expectedCurrent,
          );
  @override
  Future<List<String>> loadMeaningfulAccountFingerprints() =>
      _delegate.loadMeaningfulAccountFingerprints();
  @override
  Future<PendingDeletionTransaction?> loadPendingDeletionTransaction() =>
      _delegate.loadPendingDeletionTransaction();
  @override
  Future<BeginDeletionTransactionResult> beginDeletionTransaction({
    required String accountFingerprint,
  }) =>
      _delegate.beginDeletionTransaction(
          accountFingerprint: accountFingerprint);
  @override
  Future<AdvanceDeletionTransactionResult> advanceDeletionTransactionStage({
    required String accountFingerprint,
    required DeletionTransactionStage expectedCurrentStage,
    required DeletionTransactionStage nextStage,
  }) =>
      _delegate.advanceDeletionTransactionStage(
        accountFingerprint: accountFingerprint,
        expectedCurrentStage: expectedCurrentStage,
        nextStage: nextStage,
      );
}
