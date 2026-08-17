// Build 26: Sync Diagnostics / Safe Recovery core -- SyncHealthEvaluator.
// Synthetic content only. Exercises the evaluator's own deterministic
// precedence over an in-memory SyncPersistenceStore
// (test/sync_integration/in_memory_sync_test_doubles.dart, already used by
// several other sync-layer test suites) and a small, local fake
// CloudKitPlatformBridge -- never real CloudKit, never real file I/O.
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/sync/cloud_kept_wisdom_projection.dart';
import 'package:wisdom_app/sync/data_epoch.dart';
import 'package:wisdom_app/sync/sync_change.dart';
import 'package:wisdom_app/sync/sync_tombstone.dart';
import 'package:wisdom_app/sync_diagnostics/sync_health_evaluator.dart';
import 'package:wisdom_app/sync_diagnostics/sync_health_snapshot.dart';
import 'package:wisdom_app/sync_persistence/account_sync_state.dart';
import 'package:wisdom_app/sync_persistence/associated_account_fingerprint_commit.dart';
import 'package:wisdom_app/sync_persistence/deletion_transaction_result.dart';
import 'package:wisdom_app/sync_persistence/incoming_batch_checkpoint.dart';
import 'package:wisdom_app/sync_persistence/outbox_mutation_retirement.dart';
import 'package:wisdom_app/sync_persistence/pending_deletion_transaction.dart';
import 'package:wisdom_app/sync_persistence/persisted_outbox_mutation.dart';
import 'package:wisdom_app/sync_persistence/sync_persistence_store.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_account_change_event.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_account_snapshot.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_bridge_info.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_delete_records_contract.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_kept_wisdom_record_names_contract.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_modify_records_contract.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_platform_bridge.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_sync_state_epoch_contract.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_zone_changes_contract.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_zone_configuration_result.dart';
import 'package:wisdom_app/sync_runtime/cloud_kit_sync_runtime_coordinator.dart';

import '../sync_integration/in_memory_sync_test_doubles.dart';

const _fingerprintA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _fingerprintB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

final _epoch = DataEpoch.parse('bbbbbbbb-2222-4222-8222-222222222222');

const _emptyRuntimeStatus = CloudKitSyncRuntimeStatus(
  isRunning: false,
  followUpRequested: false,
  retryScheduled: false,
  retryAttempt: 0,
);

CloudKeptWisdomProjection _projection(
  String revealId, {
  DataEpoch? dataEpoch,
  String? mutationId,
}) {
  return CloudKeptWisdomProjection.tryParseRemote({
    'recordName': 'east-kept-$revealId',
    'isTombstone': false,
    'revealId': revealId,
    'wisdomText': 'Synthetic wisdom text.',
    'revealedAtMs': 1000,
    'keptAtMs': 2000,
    'updatedAtMs': 3000,
    'mutationId': mutationId ?? 'cccccccc-3333-4333-8333-333333333333',
    'dataEpoch': (dataEpoch ?? _epoch).value,
    'schemaVersion': 3,
  })!;
}

CloudKeptWisdomProjection _tombstoneProjection(
  String revealId, {
  DataEpoch? dataEpoch,
  String? mutationId,
}) {
  final now = DateTime.utc(2026, 8, 1);
  return CloudKeptWisdomProjection.tombstone(
    SyncTombstone(
      revealId: revealId,
      dataEpoch: dataEpoch ?? _epoch,
      updatedAt: now,
      deletedAt: now,
      mutationId: mutationId ?? 'cccccccc-3333-4333-8333-333333333333',
    ),
  );
}

PersistedOutboxMutation _mutation(
  String revealId, {
  PersistedOutboxMutationStatus status = PersistedOutboxMutationStatus.pending,
  SyncChangeKind kind = SyncChangeKind.create,
  String? mutationId,
}) {
  return PersistedOutboxMutation(
    change: SyncChange(
      kind: kind,
      projection: kind == SyncChangeKind.delete
          ? _tombstoneProjection(revealId, mutationId: mutationId)
          : _projection(revealId, mutationId: mutationId),
      enqueuedAt: DateTime.utc(2026, 8, 1),
    ),
    status: status,
  );
}

/// Minimal local fake -- only [getAccountSnapshot] is ever exercised by
/// [SyncHealthEvaluator] (see its own doc comment's "observational only"
/// section); every other member throws if ever called, which would itself
/// be a test failure signal that the evaluator started doing real CloudKit
/// work.
class _FakeBridge implements CloudKitPlatformBridge {
  CloudKitAccountSnapshot snapshot = const CloudKitAccountSnapshot(
    availability: CloudKitAccountAvailability.available,
    isPrivateDatabaseUsable: true,
    accountFingerprint: _fingerprintA,
    fingerprintResolved: true,
    bridgeVersion: 1,
  );

  int getAccountSnapshotCallCount = 0;

  @override
  Future<CloudKitAccountSnapshot> getAccountSnapshot() async {
    getAccountSnapshotCallCount += 1;
    return snapshot;
  }

  @override
  Stream<CloudKitAccountChangeEvent> get accountChangeEvents =>
      const Stream.empty();

  @override
  Future<CloudKitZoneConfigurationResult> configurePrivateZone() =>
      _unused<CloudKitZoneConfigurationResult>();

  @override
  Future<CloudKitBridgeInfo> getBridgeInfo() => _unused<CloudKitBridgeInfo>();

  @override
  Future<CloudKitModifyRecordsResult> modifyPrivateRecords(
    CloudKitModifyRecordsRequest request,
  ) =>
      _unused<CloudKitModifyRecordsResult>();

  @override
  Future<CloudKitZoneChangesResult> fetchPrivateZoneChanges(
    CloudKitZoneChangesRequest request,
  ) =>
      _unused<CloudKitZoneChangesResult>();

  @override
  Future<CloudKitSyncStateEpochResult> fetchSyncStateEpoch() =>
      _unused<CloudKitSyncStateEpochResult>();

  @override
  Future<CloudKitKeptWisdomRecordNamesResult> listKeptWisdomRecordNames() =>
      _unused<CloudKitKeptWisdomRecordNamesResult>();

  @override
  Future<CloudKitDeleteKeptWisdomRecordsResult> deleteKeptWisdomRecords(
    CloudKitDeleteKeptWisdomRecordsRequest request,
  ) =>
      _unused<CloudKitDeleteKeptWisdomRecordsResult>();

  Future<T> _unused<T>() async {
    throw StateError(
      'SyncHealthEvaluator must never call this CloudKitPlatformBridge '
      'method -- it is observational only.',
    );
  }
}

/// Wraps [InMemorySyncPersistenceStore] with one-shot fault injection on the
/// two reads [SyncHealthEvaluator] treats as fail-closed-on-throw
/// (`loadPendingDeletionTransaction`, `loadAccountState`) -- the base double
/// has no such seam of its own.
class _FaultInjectingStore implements SyncPersistenceStore {
  _FaultInjectingStore(this._inner);

  final InMemorySyncPersistenceStore _inner;
  bool failNextLoadPendingDeletionTransaction = false;
  bool failNextLoadAccountState = false;

  @override
  Future<PendingDeletionTransaction?> loadPendingDeletionTransaction() {
    if (failNextLoadPendingDeletionTransaction) {
      failNextLoadPendingDeletionTransaction = false;
      throw const SyncPersistenceStoreException(
        'test-fault', 'synthetic corrupted read',
      );
    }
    return _inner.loadPendingDeletionTransaction();
  }

  @override
  Future<AccountSyncState?> loadAccountState(String accountFingerprint) {
    if (failNextLoadAccountState) {
      failNextLoadAccountState = false;
      throw const SyncPersistenceStoreException(
        'test-fault', 'synthetic corrupted read',
      );
    }
    return _inner.loadAccountState(accountFingerprint);
  }

  @override
  Future<void> replaceAccountState(
          String accountFingerprint, AccountSyncState state) =>
      _inner.replaceAccountState(accountFingerprint, state);

  @override
  Future<void> enqueueMutation(String accountFingerprint, SyncChange change) =>
      _inner.enqueueMutation(accountFingerprint, change);

  @override
  Future<void> applyMutationOutcomes(String accountFingerprint,
          {Set<String> acknowledgedMutationIds = const {},
          Map<String, PersistedOutboxMutationStatus>
              updatedStatusByMutationId = const {}}) =>
      _inner.applyMutationOutcomes(accountFingerprint,
          acknowledgedMutationIds: acknowledgedMutationIds,
          updatedStatusByMutationId: updatedStatusByMutationId);

  @override
  Future<List<PersistedOutboxMutation>> readPendingMutations(
          String accountFingerprint) =>
      _inner.readPendingMutations(accountFingerprint);

  @override
  Future<void> replaceRecordSystemFields(String accountFingerprint,
          String recordName, String systemFields) =>
      _inner.replaceRecordSystemFields(
          accountFingerprint, recordName, systemFields);

  @override
  Future<void> storeServerChangeToken(
          String accountFingerprint, String serverToken) =>
      _inner.storeServerChangeToken(accountFingerprint, serverToken);

  @override
  Future<void> clearServerChangeToken(String accountFingerprint) =>
      _inner.clearServerChangeToken(accountFingerprint);

  @override
  Future<void> clearAccountState(String accountFingerprint) =>
      _inner.clearAccountState(accountFingerprint);

  @override
  Future<void> quarantineAccountState(String accountFingerprint) =>
      _inner.quarantineAccountState(accountFingerprint);

  @override
  Future<CommitIncomingBatchCheckpointResult> commitIncomingBatchCheckpoint(
          CommitIncomingBatchCheckpointRequest request) =>
      _inner.commitIncomingBatchCheckpoint(request);

  @override
  Future<RetireOutboxMutationResult> retireOutboxMutationIfCurrent(
          RetireOutboxMutationRequest request) =>
      _inner.retireOutboxMutationIfCurrent(request);

  @override
  Future<String?> loadAssociatedAccountFingerprint() =>
      _inner.loadAssociatedAccountFingerprint();

  @override
  Future<CommitAssociatedAccountFingerprintResult>
      commitAssociatedAccountFingerprint(
          {required String fingerprint, required String? expectedCurrent}) =>
      _inner.commitAssociatedAccountFingerprint(
          fingerprint: fingerprint, expectedCurrent: expectedCurrent);

  @override
  Future<ClearAssociatedAccountFingerprintResult>
      clearAssociatedAccountFingerprintIfCurrent(
          {required String expectedCurrent}) =>
      _inner.clearAssociatedAccountFingerprintIfCurrent(
          expectedCurrent: expectedCurrent);

  @override
  Future<List<String>> loadMeaningfulAccountFingerprints() =>
      _inner.loadMeaningfulAccountFingerprints();

  @override
  Future<BeginDeletionTransactionResult> beginDeletionTransaction(
          {required String accountFingerprint}) =>
      _inner.beginDeletionTransaction(accountFingerprint: accountFingerprint);

  @override
  Future<AdvanceDeletionTransactionResult> advanceDeletionTransactionStage(
          {required String accountFingerprint,
          required DeletionTransactionStage expectedCurrentStage,
          required DeletionTransactionStage nextStage}) =>
      _inner.advanceDeletionTransactionStage(
          accountFingerprint: accountFingerprint,
          expectedCurrentStage: expectedCurrentStage,
          nextStage: nextStage);

  @override
  Future<void> clearDeletionTransaction({required String accountFingerprint}) =>
      _inner.clearDeletionTransaction(accountFingerprint: accountFingerprint);
}

void main() {
  late InMemorySyncPersistenceStore innerStore;
  late _FaultInjectingStore store;
  late _FakeBridge bridge;
  late CloudKitSyncRuntimeStatus runtimeStatus;
  late SyncHealthEvaluator evaluator;

  setUp(() {
    innerStore = InMemorySyncPersistenceStore(epochFactory: () => _epoch);
    store = _FaultInjectingStore(innerStore);
    bridge = _FakeBridge();
    runtimeStatus = _emptyRuntimeStatus;
    evaluator = SyncHealthEvaluator(
      syncPersistenceStore: store,
      bridge: bridge,
      readRuntimeStatus: () => runtimeStatus,
    );
  });

  AccountSyncState completeBucket({
    List<PersistedOutboxMutation> outbox = const [],
  }) =>
      AccountSyncState(
        dataEpoch: _epoch,
        bootstrapState: AccountBootstrapState.complete,
        outbox: outbox,
      );

  test('1. sync disabled (no association marker) -> disabled, no CloudKit '
      'work initiated', () async {
    final snapshot = await evaluator.evaluate();
    expect(snapshot.state, SyncHealthState.disabled);
    expect(snapshot.syncEnabled, isFalse);
  });

  test('2. enabled + valid account + fully converged durable state -> '
      'healthy', () async {
    innerStore.seedAssociatedAccountFingerprint(_fingerprintA);
    innerStore.seedAccount(_fingerprintA, completeBucket());

    final snapshot = await evaluator.evaluate();
    expect(snapshot.state, SyncHealthState.healthy);
    expect(snapshot.outboxPendingCount, 0);
  });

  test('3. enabled + pending local mutation -> pending, not healthy',
      () async {
    innerStore.seedAssociatedAccountFingerprint(_fingerprintA);
    innerStore.seedAccount(
      _fingerprintA,
      completeBucket(outbox: [
        _mutation('aaaaaaaa-1111-4111-8111-111111111111'),
      ]),
    );

    final snapshot = await evaluator.evaluate();
    expect(snapshot.state, SyncHealthState.pending);
    expect(snapshot.outboxPendingCount, 1);
    expect(snapshot.hasUnresolvedOutboxEntries, isFalse);
  });

  test('4. pending tombstone (delete) with no failure -> pending, not '
      'healthy; a conflicted tombstone -> recoveryRequired, not healthy',
      () async {
    innerStore.seedAssociatedAccountFingerprint(_fingerprintA);
    innerStore.seedAccount(
      _fingerprintA,
      completeBucket(outbox: [
        _mutation(
          'aaaaaaaa-1111-4111-8111-111111111111',
          kind: SyncChangeKind.delete,
        ),
      ]),
    );
    expect((await evaluator.evaluate()).state, SyncHealthState.pending);

    innerStore.seedAccount(
      _fingerprintA,
      completeBucket(outbox: [
        _mutation(
          'aaaaaaaa-1111-4111-8111-111111111111',
          kind: SyncChangeKind.delete,
          status: PersistedOutboxMutationStatus.conflicted,
        ),
      ]),
    );
    final snapshot = await evaluator.evaluate();
    expect(snapshot.state, SyncHealthState.recoveryRequired);
    expect(snapshot.hasUnresolvedOutboxEntries, isTrue);
  });

  test('5. account unavailable -> iCloudUnavailable; local durable state '
      'untouched', () async {
    innerStore.seedAssociatedAccountFingerprint(_fingerprintA);
    innerStore.seedAccount(_fingerprintA, completeBucket());
    bridge.snapshot = const CloudKitAccountSnapshot(
      availability: CloudKitAccountAvailability.noAccount,
      isPrivateDatabaseUsable: false,
      accountFingerprint: null,
      fingerprintResolved: false,
      bridgeVersion: 1,
    );

    final before = await innerStore.loadAccountState(_fingerprintA);
    final snapshot = await evaluator.evaluate();
    final after = await innerStore.loadAccountState(_fingerprintA);

    expect(snapshot.state, SyncHealthState.iCloudUnavailable);
    expect(after, equals(before));
  });

  test('6. retryable CloudKit failure (retry scheduled) -> temporaryFailure',
      () async {
    innerStore.seedAssociatedAccountFingerprint(_fingerprintA);
    innerStore.seedAccount(_fingerprintA, completeBucket());
    runtimeStatus = const CloudKitSyncRuntimeStatus(
      isRunning: false,
      followUpRequested: false,
      retryScheduled: true,
      retryAttempt: 1,
      lastOutcome: SyncRuntimeOutcome.retryableFailure,
    );

    final snapshot = await evaluator.evaluate();
    expect(snapshot.state, SyncHealthState.temporaryFailure);
  });

  test('7. interrupted bootstrap -> pending (resumable safely), not '
      'healthy and not recoveryRequired', () async {
    innerStore.seedAssociatedAccountFingerprint(_fingerprintA);
    innerStore.seedAccount(
      _fingerprintA,
      AccountSyncState(
        dataEpoch: _epoch,
        bootstrapState: AccountBootstrapState.remoteBaselinePending,
      ),
    );

    final snapshot = await evaluator.evaluate();
    expect(snapshot.state, SyncHealthState.pending);
  });

  test('8. account-change/re-association required -> recoveryRequired, '
      'never falsely healthy', () async {
    innerStore.seedAssociatedAccountFingerprint(_fingerprintA);
    innerStore.seedAccount(_fingerprintA, completeBucket());
    // The live CloudKit account no longer matches the durable marker.
    bridge.snapshot = const CloudKitAccountSnapshot(
      availability: CloudKitAccountAvailability.available,
      isPrivateDatabaseUsable: true,
      accountFingerprint: _fingerprintB,
      fingerprintResolved: true,
      bridgeVersion: 1,
    );

    final snapshot = await evaluator.evaluate();
    expect(snapshot.state, SyncHealthState.recoveryRequired);
  });

  test('9. pending Remove-from-iCloud deletion wins over an otherwise '
      'healthy-looking bucket', () async {
    innerStore.seedAssociatedAccountFingerprint(_fingerprintA);
    innerStore.seedAccount(_fingerprintA, completeBucket());
    innerStore.seedPendingDeletionTransaction(
      PendingDeletionTransaction(
        accountFingerprint: _fingerprintA,
        originalDataEpoch: _epoch,
        replacementDataEpoch:
            DataEpoch.parse('dddddddd-4444-4444-8444-444444444444'),
        stage: DeletionTransactionStage.cloudPurgePending,
      ),
    );

    final snapshot = await evaluator.evaluate();
    expect(snapshot.state, SyncHealthState.recovering);
    expect(snapshot.deletionRecoveryPending, isTrue);
    expect(snapshot.deletionRecoveryStage,
        DeletionTransactionStage.cloudPurgePending);
  });

  test('10. localFinalizePending deletion stage still resolves through the '
      'recovery path, not normal sync', () async {
    innerStore.seedAssociatedAccountFingerprint(_fingerprintA);
    innerStore.seedPendingDeletionTransaction(
      PendingDeletionTransaction(
        accountFingerprint: _fingerprintA,
        originalDataEpoch: _epoch,
        replacementDataEpoch:
            DataEpoch.parse('dddddddd-4444-4444-8444-444444444444'),
        stage: DeletionTransactionStage.localFinalizePending,
      ),
    );

    final snapshot = await evaluator.evaluate();
    expect(snapshot.state, SyncHealthState.recovering);
    expect(snapshot.deletionRecoveryStage,
        DeletionTransactionStage.localFinalizePending);
  });

  test('a deletion transaction whose most recent runtime pass reported a '
      'terminal failure (e.g. account mismatch/epoch conflict) -> '
      'recoveryRequired, not recovering', () async {
    innerStore.seedAssociatedAccountFingerprint(_fingerprintA);
    innerStore.seedPendingDeletionTransaction(
      PendingDeletionTransaction(
        accountFingerprint: _fingerprintA,
        originalDataEpoch: _epoch,
        replacementDataEpoch:
            DataEpoch.parse('dddddddd-4444-4444-8444-444444444444'),
        stage: DeletionTransactionStage.epochBarrierPending,
      ),
    );
    runtimeStatus = const CloudKitSyncRuntimeStatus(
      isRunning: false,
      followUpRequested: false,
      retryScheduled: false,
      retryAttempt: 0,
      lastOutcome: SyncRuntimeOutcome.terminalFailure,
    );

    final snapshot = await evaluator.evaluate();
    expect(snapshot.state, SyncHealthState.recoveryRequired);
  });

  test('a deletion-state read that throws (corrupted record) -> '
      'recoveryRequired, before any other read is trusted', () async {
    store.failNextLoadPendingDeletionTransaction = true;
    innerStore.seedAssociatedAccountFingerprint(_fingerprintA);
    innerStore.seedAccount(_fingerprintA, completeBucket());

    final snapshot = await evaluator.evaluate();
    expect(snapshot.state, SyncHealthState.recoveryRequired);
  });

  test('an unreadable account bucket -> recoveryRequired, not a blind '
      'retry-eligible state', () async {
    innerStore.seedAssociatedAccountFingerprint(_fingerprintA);
    store.failNextLoadAccountState = true;

    final snapshot = await evaluator.evaluate();
    expect(snapshot.state, SyncHealthState.recoveryRequired);
  });

  test('11/14. evaluate() always reflects the current durable state fresh '
      '-- never caches a stale prior read, exactly as a fresh process would '
      'observe after a kill/relaunch', () async {
    innerStore.seedAssociatedAccountFingerprint(_fingerprintA);
    innerStore.seedAccount(_fingerprintA, completeBucket());
    expect((await evaluator.evaluate()).state, SyncHealthState.healthy);

    innerStore.seedAccount(
      _fingerprintA,
      completeBucket(outbox: [
        _mutation('aaaaaaaa-1111-4111-8111-111111111111'),
      ]),
    );
    expect((await evaluator.evaluate()).state, SyncHealthState.pending);

    // A brand-new evaluator instance, reading the exact same durable store
    // and a freshly-defaulted runtime status -- exactly what a fresh app
    // process after a kill/relaunch would construct -- observes the same
    // durable state.
    final relaunchedEvaluator = SyncHealthEvaluator(
      syncPersistenceStore: store,
      bridge: bridge,
      readRuntimeStatus: () => _emptyRuntimeStatus,
    );
    expect((await relaunchedEvaluator.evaluate()).state, SyncHealthState.pending);
  });

  test('19. a terminal runtime failure always overrides an otherwise clean '
      'durable baseline -- healthy is never reported while a critical '
      'recovery condition is live', () async {
    innerStore.seedAssociatedAccountFingerprint(_fingerprintA);
    innerStore.seedAccount(_fingerprintA, completeBucket());
    runtimeStatus = const CloudKitSyncRuntimeStatus(
      isRunning: false,
      followUpRequested: false,
      retryScheduled: false,
      retryAttempt: 0,
      lastOutcome: SyncRuntimeOutcome.terminalFailure,
    );

    final snapshot = await evaluator.evaluate();
    expect(snapshot.state, isNot(SyncHealthState.healthy));
    expect(snapshot.state, SyncHealthState.recoveryRequired);
  });

  test('an actively-running pass never reports healthy mid-flight', () async {
    innerStore.seedAssociatedAccountFingerprint(_fingerprintA);
    innerStore.seedAccount(_fingerprintA, completeBucket());
    runtimeStatus = const CloudKitSyncRuntimeStatus(
      isRunning: true,
      followUpRequested: false,
      retryScheduled: false,
      retryAttempt: 0,
    );

    final snapshot = await evaluator.evaluate();
    expect(snapshot.state, isNot(SyncHealthState.healthy));
    expect(snapshot.state, SyncHealthState.pending);
  });

  test('17/18. toLogSafeSummary/toString expose only content-free fields',
      () async {
    innerStore.seedAssociatedAccountFingerprint(_fingerprintA);
    innerStore.seedAccount(
      _fingerprintA,
      completeBucket(outbox: [
        _mutation('aaaaaaaa-1111-4111-8111-111111111111'),
      ]),
    );

    final snapshot = await evaluator.evaluate();
    final summary = snapshot.toLogSafeSummary();

    expect(
      summary.keys,
      containsAll(<String>[
        'state',
        'syncEnabled',
        'accountAvailability',
        'outboxPendingCount',
        'hasUnresolvedOutboxEntries',
        'deletionRecoveryPending',
        'deletionRecoveryStage',
        'runtimeStatus',
      ]),
    );

    const forbidden = [
      'fingerprint',
      'wisdom',
      'reflection',
      'revealId',
      'mutationId',
      'recordName',
      'serverToken',
      _fingerprintA,
    ];
    final rendered = '${summary.toString()} ${snapshot.toString()}'
        .toLowerCase();
    for (final term in forbidden) {
      expect(rendered.contains(term.toLowerCase()), isFalse,
          reason: 'toLogSafeSummary/toString leaked "$term"');
    }
  });
}
