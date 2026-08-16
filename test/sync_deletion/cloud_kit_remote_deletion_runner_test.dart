// Build 26 Phase 5 (slice 2): the required focused test suite for
// `CloudKitRemoteDeletionRunner` -- the 32-point matrix specified for this
// slice. Points 1-31 live here; point 32 ("stale old-epoch device continues
// to hit existing remote-epoch-change fail-closed behavior") is added to
// `test/sync_integration/kept_sync_bootstrap_coordinator_test.dart` instead,
// per the instruction's own placement of that guarantee.
//
// Uses `InMemorySyncPersistenceStore`
// (test/sync_integration/in_memory_sync_test_doubles.dart) directly for the
// persistence side -- the real, already-reviewed CAS/idempotency semantics,
// no file I/O, no second hand-rolled persistence model -- and a small,
// self-contained fake `CloudKitPlatformBridge` (mirroring
// test/sync_orchestration/sync_orchestrator_test.dart's own
// `_FakeCloudKitPlatformBridge`) for the transport side. No real
// MethodChannel or CloudKit container anywhere in this file.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/sync/cloud_east_sync_state_projection.dart';
import 'package:wisdom_app/sync/data_epoch.dart';
import 'package:wisdom_app/sync/sync_change.dart';
import 'package:wisdom_app/sync/sync_error_classification.dart';
import 'package:wisdom_app/sync_deletion/cloud_kit_remote_deletion_runner.dart';
import 'package:wisdom_app/sync_deletion/remote_deletion_run_result.dart';
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
import 'package:wisdom_app/sync_platform/cloud_kit_platform_error.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_sync_state_epoch_contract.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_zone_changes_contract.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_zone_configuration_result.dart';

import '../sync_integration/in_memory_sync_test_doubles.dart';

/// Deterministic, valid-shaped account fingerprints -- `^[0-9a-f]{64}$`,
/// mirroring `test/sync_e2e/cloudkit_sync_e2e_test.dart`'s own
/// `fingerprint(int)` helper exactly.
String fingerprint(int n) => n.toRadixString(16).padLeft(64, '0');

CloudKitAccountSnapshot _available(String fp) => CloudKitAccountSnapshot(
      availability: CloudKitAccountAvailability.available,
      isPrivateDatabaseUsable: true,
      accountFingerprint: fp,
      fingerprintResolved: true,
      bridgeVersion: 1,
    );

const CloudKitAccountSnapshot _unavailable = CloudKitAccountSnapshot(
  availability: CloudKitAccountAvailability.noAccount,
  isPrivateDatabaseUsable: false,
  accountFingerprint: null,
  fingerprintResolved: false,
  bridgeVersion: 1,
);

const CloudKitZoneConfigurationResult _zoneSuccess =
    CloudKitZoneConfigurationResult(
  success: true,
  zoneCreated: false,
  zoneAlreadyExisted: true,
  accountAvailability: CloudKitAccountAvailability.available,
);

PendingDeletionTransaction _tx({
  required String accountFingerprint,
  DataEpoch? originalDataEpoch,
  required DataEpoch replacementDataEpoch,
  required DeletionTransactionStage stage,
}) =>
    PendingDeletionTransaction(
      accountFingerprint: accountFingerprint,
      originalDataEpoch: originalDataEpoch,
      replacementDataEpoch: replacementDataEpoch,
      stage: stage,
    );

/// Fake [CloudKitPlatformBridge] -- no real MethodChannel or CloudKit
/// container anywhere in this file. Every hook defaults to a benign,
/// "nothing to do" response; individual tests override exactly the hooks
/// they need.
class _FakeCloudKitPlatformBridge implements CloudKitPlatformBridge {
  CloudKitAccountSnapshot Function() accountSnapshotProvider =
      () => _available(fingerprint(1));
  CloudKitZoneConfigurationResult Function() zoneConfigurationProvider =
      () => _zoneSuccess;
  CloudKitSyncStateEpochResult Function() fetchSyncStateEpochProvider =
      () => CloudKitSyncStateEpochResult.notFound();
  CloudKitKeptWisdomRecordNamesResult Function()
      listKeptWisdomRecordNamesProvider =
      () => CloudKitKeptWisdomRecordNamesResult.success(const []);
  CloudKitDeleteKeptWisdomRecordsResult Function(
    CloudKitDeleteKeptWisdomRecordsRequest,
  ) deleteKeptWisdomRecordsProvider =
      (request) => CloudKitDeleteKeptWisdomRecordsResult.allSucceeded([
            for (final name in request.recordNames)
              CloudKitRecordDeleteOutcome.success(recordName: name),
          ]);
  CloudKitModifyRecordsResult Function(CloudKitModifyRecordsRequest)
      modifyPrivateRecordsProvider =
      (request) => CloudKitModifyRecordsResult.allSucceeded([
            CloudKitRecordModifyOutcome.success(
              recordName: CloudEastSyncStateProjection.recordName,
              systemFields: 'fake-system-fields',
            ),
          ]);

  int getAccountSnapshotCallCount = 0;
  int configurePrivateZoneCallCount = 0;
  int fetchSyncStateEpochCallCount = 0;
  int listKeptWisdomRecordNamesCallCount = 0;
  int deleteKeptWisdomRecordsCallCount = 0;
  int modifyPrivateRecordsCallCount = 0;
  final List<String> callOrder = [];
  final List<CloudKitDeleteKeptWisdomRecordsRequest> deleteRequests = [];
  final List<CloudKitModifyRecordsRequest> modifyRequests = [];

  @override
  Future<CloudKitAccountSnapshot> getAccountSnapshot() async {
    getAccountSnapshotCallCount += 1;
    callOrder.add('getAccountSnapshot');
    return accountSnapshotProvider();
  }

  @override
  Future<CloudKitZoneConfigurationResult> configurePrivateZone() async {
    configurePrivateZoneCallCount += 1;
    callOrder.add('configurePrivateZone');
    return zoneConfigurationProvider();
  }

  @override
  Future<CloudKitBridgeInfo> getBridgeInfo() =>
      throw UnimplementedError('Not used by CloudKitRemoteDeletionRunner.');

  @override
  Stream<CloudKitAccountChangeEvent> get accountChangeEvents =>
      const Stream.empty();

  @override
  Future<CloudKitModifyRecordsResult> modifyPrivateRecords(
    CloudKitModifyRecordsRequest request,
  ) async {
    modifyPrivateRecordsCallCount += 1;
    modifyRequests.add(request);
    callOrder.add('modifyPrivateRecords');
    return modifyPrivateRecordsProvider(request);
  }

  @override
  Future<CloudKitZoneChangesResult> fetchPrivateZoneChanges(
    CloudKitZoneChangesRequest request,
  ) =>
      throw UnimplementedError('Not used by CloudKitRemoteDeletionRunner.');

  @override
  Future<CloudKitSyncStateEpochResult> fetchSyncStateEpoch() async {
    fetchSyncStateEpochCallCount += 1;
    callOrder.add('fetchSyncStateEpoch');
    return fetchSyncStateEpochProvider();
  }

  @override
  Future<CloudKitKeptWisdomRecordNamesResult>
      listKeptWisdomRecordNames() async {
    listKeptWisdomRecordNamesCallCount += 1;
    callOrder.add('listKeptWisdomRecordNames');
    return listKeptWisdomRecordNamesProvider();
  }

  @override
  Future<CloudKitDeleteKeptWisdomRecordsResult> deleteKeptWisdomRecords(
    CloudKitDeleteKeptWisdomRecordsRequest request,
  ) async {
    deleteKeptWisdomRecordsCallCount += 1;
    deleteRequests.add(request);
    callOrder.add('deleteKeptWisdomRecords');
    return deleteKeptWisdomRecordsProvider(request);
  }

  /// Zero calls of every kind -- used by "no destructive work at all"
  /// assertions.
  void expectNoCalls() {
    expect(getAccountSnapshotCallCount, 0);
    expect(configurePrivateZoneCallCount, 0);
    expect(fetchSyncStateEpochCallCount, 0);
    expect(listKeptWisdomRecordNamesCallCount, 0);
    expect(deleteKeptWisdomRecordsCallCount, 0);
    expect(modifyPrivateRecordsCallCount, 0);
  }

  /// Zero content-affecting calls -- used by account-safety tests where
  /// exactly one account-snapshot read is expected but nothing further.
  void expectNoDestructiveCalls() {
    expect(configurePrivateZoneCallCount, 0);
    expect(fetchSyncStateEpochCallCount, 0);
    expect(listKeptWisdomRecordNamesCallCount, 0);
    expect(deleteKeptWisdomRecordsCallCount, 0);
    expect(modifyPrivateRecordsCallCount, 0);
  }
}

/// Wraps a real [SyncPersistenceStore], throwing on
/// [SyncPersistenceStore.loadPendingDeletionTransaction] only -- mirrors
/// `test/sync_runtime/cloud_kit_sync_runtime_coordinator_test.dart`'s own
/// `_DeletionStateCorruptedSyncPersistenceStore` pattern exactly, so a
/// malformed/corrupt durable deletion-transaction record can be simulated
/// without a second, hand-rolled persistence model.
class _ThrowingLoadSyncPersistenceStore implements SyncPersistenceStore {
  _ThrowingLoadSyncPersistenceStore(this._delegate);

  final SyncPersistenceStore _delegate;

  @override
  Future<PendingDeletionTransaction?> loadPendingDeletionTransaction() async {
    throw const SyncPersistenceStoreException(
      'load-decode',
      'Simulated: the durable deletion-transaction record is corrupt.',
    );
  }

  @override
  Future<String?> loadAssociatedAccountFingerprint() =>
      _delegate.loadAssociatedAccountFingerprint();

  @override
  Future<AccountSyncState?> loadAccountState(String accountFingerprint) =>
      _delegate.loadAccountState(accountFingerprint);

  @override
  Future<void> replaceAccountState(
    String accountFingerprint,
    AccountSyncState state,
  ) =>
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
    String accountFingerprint,
  ) =>
      _delegate.readPendingMutations(accountFingerprint);

  @override
  Future<void> replaceRecordSystemFields(
    String accountFingerprint,
    String recordName,
    String systemFields,
  ) =>
      _delegate.replaceRecordSystemFields(
        accountFingerprint,
        recordName,
        systemFields,
      );

  @override
  Future<void> storeServerChangeToken(
    String accountFingerprint,
    String serverToken,
  ) =>
      _delegate.storeServerChangeToken(accountFingerprint, serverToken);

  @override
  Future<void> clearServerChangeToken(String accountFingerprint) =>
      _delegate.clearServerChangeToken(accountFingerprint);

  @override
  Future<void> clearAccountState(String accountFingerprint) =>
      _delegate.clearAccountState(accountFingerprint);

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
  Future<ClearAssociatedAccountFingerprintResult>
      clearAssociatedAccountFingerprintIfCurrent({
    required String expectedCurrent,
  }) =>
          _delegate.clearAssociatedAccountFingerprintIfCurrent(
            expectedCurrent: expectedCurrent,
          );

  @override
  Future<List<String>> loadMeaningfulAccountFingerprints() =>
      _delegate.loadMeaningfulAccountFingerprints();

  @override
  Future<BeginDeletionTransactionResult> beginDeletionTransaction({
    required String accountFingerprint,
  }) =>
      _delegate.beginDeletionTransaction(
        accountFingerprint: accountFingerprint,
      );

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
        accountFingerprint: accountFingerprint,
      );
}

void main() {
  group('Runner foundation', () {
    test('1. no pending transaction -> no destructive work', () async {
      final store = InMemorySyncPersistenceStore();
      final bridge = _FakeCloudKitPlatformBridge();
      final runner = CloudKitRemoteDeletionRunner(
        bridge: bridge,
        persistenceStore: store,
      );

      final result = await runner.run();

      expect(result.outcome, RemoteDeletionRunOutcome.noPendingTransaction);
      expect(result.stage, isNull);
      bridge.expectNoCalls();
    });

    test('2. account unavailable -> zero destructive calls', () async {
      final fp = fingerprint(1);
      final store = InMemorySyncPersistenceStore();
      final epoch = DataEpoch.generate();
      store.seedPendingDeletionTransaction(_tx(
        accountFingerprint: fp,
        replacementDataEpoch: epoch,
        stage: DeletionTransactionStage.prepared,
      ));
      final bridge = _FakeCloudKitPlatformBridge()
        ..accountSnapshotProvider = () => _unavailable;
      final runner = CloudKitRemoteDeletionRunner(
        bridge: bridge,
        persistenceStore: store,
      );

      final result = await runner.run();

      expect(result.outcome, RemoteDeletionRunOutcome.waitingForAccount);
      expect(result.stage, DeletionTransactionStage.prepared);
      expect(bridge.getAccountSnapshotCallCount, 1);
      bridge.expectNoDestructiveCalls();
      final persisted = await store.loadPendingDeletionTransaction();
      expect(persisted!.stage, DeletionTransactionStage.prepared);
    });

    test('3. account mismatch -> zero destructive calls', () async {
      final fp = fingerprint(1);
      final otherFp = fingerprint(2);
      final store = InMemorySyncPersistenceStore();
      final epoch = DataEpoch.generate();
      store.seedPendingDeletionTransaction(_tx(
        accountFingerprint: fp,
        replacementDataEpoch: epoch,
        stage: DeletionTransactionStage.epochBarrierPending,
      ));
      final bridge = _FakeCloudKitPlatformBridge()
        ..accountSnapshotProvider = () => _available(otherFp);
      final runner = CloudKitRemoteDeletionRunner(
        bridge: bridge,
        persistenceStore: store,
      );

      final result = await runner.run();

      expect(result.outcome, RemoteDeletionRunOutcome.accountMismatch);
      expect(result.stage, DeletionTransactionStage.epochBarrierPending);
      expect(bridge.getAccountSnapshotCallCount, 1);
      bridge.expectNoDestructiveCalls();
      final persisted = await store.loadPendingDeletionTransaction();
      expect(persisted!.accountFingerprint, fp);
      expect(persisted.stage, DeletionTransactionStage.epochBarrierPending);
    });

    test('4. malformed persistence -> fail closed', () async {
      final delegate = InMemorySyncPersistenceStore();
      final store = _ThrowingLoadSyncPersistenceStore(delegate);
      final bridge = _FakeCloudKitPlatformBridge();
      final runner = CloudKitRemoteDeletionRunner(
        bridge: bridge,
        persistenceStore: store,
      );

      final result = await runner.run();

      expect(result.outcome, RemoteDeletionRunOutcome.deletionStateCorrupted);
      expect(result.stage, isNull);
      bridge.expectNoCalls();
    });
  });

  group('Epoch barrier', () {
    test('5. prepared advances durably before remote barrier work', () async {
      final fp = fingerprint(1);
      final store = InMemorySyncPersistenceStore();
      final epoch = DataEpoch.generate();
      store.seedPendingDeletionTransaction(_tx(
        accountFingerprint: fp,
        replacementDataEpoch: epoch,
        stage: DeletionTransactionStage.prepared,
      ));
      final bridge = _FakeCloudKitPlatformBridge()
        ..accountSnapshotProvider = () {
          return _available(fp);
        }
        ..fetchSyncStateEpochProvider = () {
          throw const CloudKitPlatformException(syncErrorCodeNetworkFailure);
        };
      final runner = CloudKitRemoteDeletionRunner(
        bridge: bridge,
        persistenceStore: store,
      );

      final result = await runner.run();

      expect(result.outcome, RemoteDeletionRunOutcome.retryableFailure);
      expect(result.stage, DeletionTransactionStage.epochBarrierPending);
      expect(bridge.fetchSyncStateEpochCallCount, 1);
      final persisted = await store.loadPendingDeletionTransaction();
      expect(
        persisted!.stage,
        DeletionTransactionStage.epochBarrierPending,
        reason: 'the prepared -> epochBarrierPending advance must be '
            'durable even though the immediately-following remote epoch '
            'read then failed.',
      );
    });

    test('6. replacement epoch used exactly, no regeneration', () async {
      final fp = fingerprint(1);
      final store = InMemorySyncPersistenceStore();
      final epoch = DataEpoch.generate();
      store.seedPendingDeletionTransaction(_tx(
        accountFingerprint: fp,
        replacementDataEpoch: epoch,
        stage: DeletionTransactionStage.epochBarrierPending,
      ));
      final bridge = _FakeCloudKitPlatformBridge()
        ..accountSnapshotProvider = () {
          return _available(fp);
        }
        ..fetchSyncStateEpochProvider = () {
          return CloudKitSyncStateEpochResult.notFound();
        };
      final runner = CloudKitRemoteDeletionRunner(
        bridge: bridge,
        persistenceStore: store,
      );

      await runner.run();

      expect(bridge.modifyPrivateRecordsCallCount, 1);
      final request = bridge.modifyRequests.single;
      expect(request.records.single.fields['dataEpoch'], epoch.value);
    });

    test('7. successful epoch write advances to cloudPurgePending', () async {
      final fp = fingerprint(1);
      final store = InMemorySyncPersistenceStore();
      final epoch = DataEpoch.generate();
      store.seedPendingDeletionTransaction(_tx(
        accountFingerprint: fp,
        replacementDataEpoch: epoch,
        stage: DeletionTransactionStage.epochBarrierPending,
      ));
      final bridge = _FakeCloudKitPlatformBridge()
        ..accountSnapshotProvider = () {
          return _available(fp);
        }
        ..fetchSyncStateEpochProvider = () {
          return CloudKitSyncStateEpochResult.notFound();
        }
        ..listKeptWisdomRecordNamesProvider = () {
          throw const CloudKitPlatformException(syncErrorCodeInvalidArguments);
        };
      final runner = CloudKitRemoteDeletionRunner(
        bridge: bridge,
        persistenceStore: store,
      );

      final result = await runner.run();

      expect(result.stage, DeletionTransactionStage.cloudPurgePending);
      final persisted = await store.loadPendingDeletionTransaction();
      expect(persisted!.stage, DeletionTransactionStage.cloudPurgePending);
    });

    test(
        '8. crash/retry with remote epoch already replacement -> idempotent '
        'success', () async {
      final fp = fingerprint(1);
      final store = InMemorySyncPersistenceStore();
      final originalEpoch = DataEpoch.generate();
      final replacementEpoch = DataEpoch.generate();
      store.seedPendingDeletionTransaction(_tx(
        accountFingerprint: fp,
        originalDataEpoch: originalEpoch,
        replacementDataEpoch: replacementEpoch,
        stage: DeletionTransactionStage.epochBarrierPending,
      ));
      final bridge = _FakeCloudKitPlatformBridge()
        ..accountSnapshotProvider = () {
          return _available(fp);
        }
        ..fetchSyncStateEpochProvider = () {
          return CloudKitSyncStateEpochResult.found(
            dataEpoch: replacementEpoch,
            systemFields: 'sf',
          );
        }
        ..listKeptWisdomRecordNamesProvider = () {
          throw const CloudKitPlatformException(syncErrorCodeInvalidArguments);
        };
      final runner = CloudKitRemoteDeletionRunner(
        bridge: bridge,
        persistenceStore: store,
      );

      final result = await runner.run();

      expect(
        bridge.modifyPrivateRecordsCallCount,
        0,
        reason: 'the remote epoch already matches the replacement epoch -- '
            'this must be treated as an idempotent success, never re-saved.',
      );
      expect(result.stage, DeletionTransactionStage.cloudPurgePending);
      final persisted = await store.loadPendingDeletionTransaction();
      expect(persisted!.stage, DeletionTransactionStage.cloudPurgePending);
    });

    test('9. unexpected remote epoch conflict -> fail closed', () async {
      final fp = fingerprint(1);
      final store = InMemorySyncPersistenceStore();
      final originalEpoch = DataEpoch.generate();
      final replacementEpoch = DataEpoch.generate();
      final conflictingEpoch = DataEpoch.generate();
      store.seedPendingDeletionTransaction(_tx(
        accountFingerprint: fp,
        originalDataEpoch: originalEpoch,
        replacementDataEpoch: replacementEpoch,
        stage: DeletionTransactionStage.epochBarrierPending,
      ));
      final bridge = _FakeCloudKitPlatformBridge()
        ..accountSnapshotProvider = () {
          return _available(fp);
        }
        ..fetchSyncStateEpochProvider = () {
          return CloudKitSyncStateEpochResult.found(
            dataEpoch: conflictingEpoch,
            systemFields: 'sf',
          );
        };
      final runner = CloudKitRemoteDeletionRunner(
        bridge: bridge,
        persistenceStore: store,
      );

      final result = await runner.run();

      expect(result.outcome, RemoteDeletionRunOutcome.epochConflict);
      expect(bridge.modifyPrivateRecordsCallCount, 0);
      final persisted = await store.loadPendingDeletionTransaction();
      expect(
        persisted!.stage,
        DeletionTransactionStage.epochBarrierPending,
        reason: 'a transaction that cannot prove it still owns the remote '
            'epoch must be left completely untouched.',
      );
    });

    test('10. CKEastSyncState is never deleted', () async {
      final fp = fingerprint(1);
      final store = InMemorySyncPersistenceStore();
      final epoch = DataEpoch.generate();
      store.seedPendingDeletionTransaction(_tx(
        accountFingerprint: fp,
        replacementDataEpoch: epoch,
        stage: DeletionTransactionStage.prepared,
      ));
      var listed = false;
      final bridge = _FakeCloudKitPlatformBridge()
        ..accountSnapshotProvider = () {
          return _available(fp);
        }
        ..fetchSyncStateEpochProvider = () {
          return CloudKitSyncStateEpochResult.notFound();
        }
        ..listKeptWisdomRecordNamesProvider = () {
          final result = listed
              ? CloudKitKeptWisdomRecordNamesResult.success(const [])
              : CloudKitKeptWisdomRecordNamesResult.success(
                  const ['east-kept-a', 'east-kept-b'],
                );
          listed = true;
          return result;
        };
      final runner = CloudKitRemoteDeletionRunner(
        bridge: bridge,
        persistenceStore: store,
      );

      final result = await runner.run();

      expect(
        result.outcome,
        RemoteDeletionRunOutcome.reachedLocalFinalizePending,
      );
      for (final request in bridge.deleteRequests) {
        expect(
          request.recordNames,
          isNot(contains(CloudEastSyncStateProjection.recordName)),
        );
      }
      // There is no bridge method capable of deleting CKEastSyncState at
      // all -- deleteKeptWisdomRecords is scoped to CKKeptWisdom identities
      // only, and every sync-state mutation this runner performs goes
      // exclusively through modifyPrivateRecords (a save, never a delete).
    });
  });

  group('Purge', () {
    test('11. purge does not run before barrier confirmation', () async {
      final fp = fingerprint(1);
      final store = InMemorySyncPersistenceStore();
      final epoch = DataEpoch.generate();
      store.seedPendingDeletionTransaction(_tx(
        accountFingerprint: fp,
        replacementDataEpoch: epoch,
        stage: DeletionTransactionStage.epochBarrierPending,
      ));
      final bridge = _FakeCloudKitPlatformBridge()
        ..accountSnapshotProvider = () {
          return _available(fp);
        }
        ..fetchSyncStateEpochProvider = () {
          throw const CloudKitPlatformException(syncErrorCodeNetworkFailure);
        };
      final runner = CloudKitRemoteDeletionRunner(
        bridge: bridge,
        persistenceStore: store,
      );

      await runner.run();

      expect(bridge.listKeptWisdomRecordNamesCallCount, 0);
      expect(bridge.deleteKeptWisdomRecordsCallCount, 0);
    });

    test('12. active CKKeptWisdom deleted', () async {
      final fp = fingerprint(1);
      final store = InMemorySyncPersistenceStore();
      final epoch = DataEpoch.generate();
      store.seedPendingDeletionTransaction(_tx(
        accountFingerprint: fp,
        replacementDataEpoch: epoch,
        stage: DeletionTransactionStage.cloudPurgePending,
      ));
      var listed = false;
      final bridge = _FakeCloudKitPlatformBridge()
        ..accountSnapshotProvider = () {
          return _available(fp);
        }
        ..listKeptWisdomRecordNamesProvider = () {
          final result = listed
              ? CloudKitKeptWisdomRecordNamesResult.success(const [])
              : CloudKitKeptWisdomRecordNamesResult.success(
                  const ['east-kept-active-1'],
                );
          listed = true;
          return result;
        };
      final runner = CloudKitRemoteDeletionRunner(
        bridge: bridge,
        persistenceStore: store,
      );

      final result = await runner.run();

      expect(bridge.deleteRequests.single.recordNames, ['east-kept-active-1']);
      expect(
        result.outcome,
        RemoteDeletionRunOutcome.reachedLocalFinalizePending,
      );
    });

    test('13. tombstone CKKeptWisdom deleted', () async {
      final fp = fingerprint(1);
      final store = InMemorySyncPersistenceStore();
      final epoch = DataEpoch.generate();
      store.seedPendingDeletionTransaction(_tx(
        accountFingerprint: fp,
        replacementDataEpoch: epoch,
        stage: DeletionTransactionStage.cloudPurgePending,
      ));
      var listed = false;
      final bridge = _FakeCloudKitPlatformBridge()
        ..accountSnapshotProvider = () {
          return _available(fp);
        }
        ..listKeptWisdomRecordNamesProvider = () {
          final result = listed
              ? CloudKitKeptWisdomRecordNamesResult.success(const [])
              : CloudKitKeptWisdomRecordNamesResult.success(
                  const ['east-kept-active-1', 'east-kept-tombstone-1'],
                );
          listed = true;
          return result;
        };
      final runner = CloudKitRemoteDeletionRunner(
        bridge: bridge,
        persistenceStore: store,
      );

      await runner.run();

      expect(
        bridge.deleteRequests.single.recordNames,
        containsAll(['east-kept-active-1', 'east-kept-tombstone-1']),
      );
    });

    test('14. all pages are processed', () async {
      final fp = fingerprint(1);
      final store = InMemorySyncPersistenceStore();
      final epoch = DataEpoch.generate();
      store.seedPendingDeletionTransaction(_tx(
        accountFingerprint: fp,
        replacementDataEpoch: epoch,
        stage: DeletionTransactionStage.cloudPurgePending,
      ));
      final fullList = List.generate(650, (i) => 'east-kept-$i');
      var listed = false;
      final bridge = _FakeCloudKitPlatformBridge()
        ..accountSnapshotProvider = () {
          return _available(fp);
        }
        ..listKeptWisdomRecordNamesProvider = () {
          final result = listed
              ? CloudKitKeptWisdomRecordNamesResult.success(const [])
              : CloudKitKeptWisdomRecordNamesResult.success(fullList);
          listed = true;
          return result;
        };
      final runner = CloudKitRemoteDeletionRunner(
        bridge: bridge,
        persistenceStore: store,
      );

      await runner.run();

      final deletedNames = bridge.deleteRequests
          .expand((request) => request.recordNames)
          .toSet();
      expect(
        deletedNames,
        fullList.toSet(),
        reason: 'every record name the single listKeptWisdomRecordNames '
            'call returned must be deleted, not merely the first batch.',
      );
    });

    test('15. more than one batch is processed', () async {
      final fp = fingerprint(1);
      final store = InMemorySyncPersistenceStore();
      final epoch = DataEpoch.generate();
      store.seedPendingDeletionTransaction(_tx(
        accountFingerprint: fp,
        replacementDataEpoch: epoch,
        stage: DeletionTransactionStage.cloudPurgePending,
      ));
      final fullList = List.generate(650, (i) => 'east-kept-$i');
      var listed = false;
      final bridge = _FakeCloudKitPlatformBridge()
        ..accountSnapshotProvider = () {
          return _available(fp);
        }
        ..listKeptWisdomRecordNamesProvider = () {
          final result = listed
              ? CloudKitKeptWisdomRecordNamesResult.success(const [])
              : CloudKitKeptWisdomRecordNamesResult.success(fullList);
          listed = true;
          return result;
        };
      final runner = CloudKitRemoteDeletionRunner(
        bridge: bridge,
        persistenceStore: store,
      );

      await runner.run();

      expect(
        bridge.deleteKeptWisdomRecordsCallCount,
        3,
        reason: '650 names at a 300-per-batch ceiling requires 3 calls '
            '(300 + 300 + 50).',
      );
      for (final request in bridge.deleteRequests) {
        expect(request.recordNames.length, lessThanOrEqualTo(300));
      }
    });

    test('16. partial failure leaves stage safely retryable', () async {
      final fp = fingerprint(1);
      final store = InMemorySyncPersistenceStore();
      final epoch = DataEpoch.generate();
      store.seedPendingDeletionTransaction(_tx(
        accountFingerprint: fp,
        replacementDataEpoch: epoch,
        stage: DeletionTransactionStage.cloudPurgePending,
      ));
      final bridge = _FakeCloudKitPlatformBridge()
        ..accountSnapshotProvider = () {
          return _available(fp);
        }
        ..listKeptWisdomRecordNamesProvider = () {
          return CloudKitKeptWisdomRecordNamesResult.success(
            const ['east-kept-a', 'east-kept-b', 'east-kept-c'],
          );
        }
        ..deleteKeptWisdomRecordsProvider = (request) {
          return CloudKitDeleteKeptWisdomRecordsResult.partialFailure([
            CloudKitRecordDeleteOutcome.success(recordName: 'east-kept-a'),
            CloudKitRecordDeleteOutcome.failure(
              recordName: 'east-kept-b',
              errorCode: syncErrorCodeNetworkFailure,
            ),
            CloudKitRecordDeleteOutcome.success(recordName: 'east-kept-c'),
          ]);
        };
      final runner = CloudKitRemoteDeletionRunner(
        bridge: bridge,
        persistenceStore: store,
      );

      final result = await runner.run();

      expect(result.outcome, RemoteDeletionRunOutcome.retryableFailure);
      expect(result.stage, DeletionTransactionStage.cloudPurgePending);
      final persisted = await store.loadPendingDeletionTransaction();
      expect(persisted!.stage, DeletionTransactionStage.cloudPurgePending);
    });

    test('17. retry after partial delete is idempotent', () async {
      final fp = fingerprint(1);
      final store = InMemorySyncPersistenceStore();
      final epoch = DataEpoch.generate();
      store.seedPendingDeletionTransaction(_tx(
        accountFingerprint: fp,
        replacementDataEpoch: epoch,
        stage: DeletionTransactionStage.cloudPurgePending,
      ));
      var remaining = <String>['east-kept-a', 'east-kept-b', 'east-kept-c'];
      var deleteAttempts = 0;
      final bridge = _FakeCloudKitPlatformBridge()
        ..accountSnapshotProvider = () {
          return _available(fp);
        }
        ..listKeptWisdomRecordNamesProvider = () {
          return CloudKitKeptWisdomRecordNamesResult.success(remaining);
        }
        ..deleteKeptWisdomRecordsProvider = (request) {
          deleteAttempts += 1;
          if (deleteAttempts == 1) {
            // Simulated transient transport failure -- nothing is actually
            // deleted remotely on this attempt.
            return CloudKitDeleteKeptWisdomRecordsResult.transportFailure(
              syncErrorCodeNetworkFailure,
            );
          }
          remaining = [];
          return CloudKitDeleteKeptWisdomRecordsResult.allSucceeded([
            for (final name in request.recordNames)
              CloudKitRecordDeleteOutcome.success(recordName: name),
          ]);
        };
      final runner = CloudKitRemoteDeletionRunner(
        bridge: bridge,
        persistenceStore: store,
      );

      final first = await runner.run();
      expect(first.outcome, RemoteDeletionRunOutcome.retryableFailure);
      expect(first.stage, DeletionTransactionStage.cloudPurgePending);

      final second = await runner.run();
      expect(
        second.outcome,
        RemoteDeletionRunOutcome.reachedLocalFinalizePending,
      );
      final persisted = await store.loadPendingDeletionTransaction();
      expect(persisted!.stage, DeletionTransactionStage.localFinalizePending);
    });

    test('18. local Kept untouched', () {
      final file =
          File('lib/sync_deletion/cloud_kit_remote_deletion_runner.dart');
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();
      expect(content, isNot(contains('kept_repository.dart')));
      expect(content, isNot(contains('KeptRepository')));
      expect(content, isNot(contains('kept_state_store.dart')));
    });

    test('19. local Reflections untouched', () {
      final file =
          File('lib/sync_deletion/cloud_kit_remote_deletion_runner.dart');
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();
      expect(content, isNot(contains('saved_reflections_service.dart')));
      expect(content, isNot(contains('SavedReflectionsService')));
      expect(content, isNot(contains('reflectionText')));
    });
  });

  group('Verification', () {
    test('20. zero records -> localFinalizePending', () async {
      final fp = fingerprint(1);
      final store = InMemorySyncPersistenceStore();
      final epoch = DataEpoch.generate();
      store.seedPendingDeletionTransaction(_tx(
        accountFingerprint: fp,
        replacementDataEpoch: epoch,
        stage: DeletionTransactionStage.verificationPending,
      ));
      final bridge = _FakeCloudKitPlatformBridge()
        ..accountSnapshotProvider = () {
          return _available(fp);
        }
        ..listKeptWisdomRecordNamesProvider = () {
          return CloudKitKeptWisdomRecordNamesResult.success(const []);
        };
      final runner = CloudKitRemoteDeletionRunner(
        bridge: bridge,
        persistenceStore: store,
      );

      final result = await runner.run();

      expect(
        result.outcome,
        RemoteDeletionRunOutcome.reachedLocalFinalizePending,
      );
      expect(result.stage, DeletionTransactionStage.localFinalizePending);
      final persisted = await store.loadPendingDeletionTransaction();
      expect(persisted!.stage, DeletionTransactionStage.localFinalizePending);
    });

    test('21. nonzero verification does NOT advance to localFinalizePending',
        () async {
      final fp = fingerprint(1);
      final store = InMemorySyncPersistenceStore();
      final epoch = DataEpoch.generate();
      store.seedPendingDeletionTransaction(_tx(
        accountFingerprint: fp,
        replacementDataEpoch: epoch,
        stage: DeletionTransactionStage.verificationPending,
      ));
      // Always finds one more record and successfully deletes it, but
      // never actually converges to zero within the bounded loop.
      var counter = 0;
      final bridge = _FakeCloudKitPlatformBridge()
        ..accountSnapshotProvider = () {
          return _available(fp);
        }
        ..listKeptWisdomRecordNamesProvider = () {
          counter += 1;
          return CloudKitKeptWisdomRecordNamesResult.success(
            ['east-kept-stale-$counter'],
          );
        };
      final runner = CloudKitRemoteDeletionRunner(
        bridge: bridge,
        persistenceStore: store,
      );

      final result = await runner.run();

      expect(
        result.outcome,
        isNot(RemoteDeletionRunOutcome.reachedLocalFinalizePending),
      );
      expect(result.stage, DeletionTransactionStage.verificationPending);
      final persisted = await store.loadPendingDeletionTransaction();
      expect(
        persisted!.stage,
        DeletionTransactionStage.verificationPending,
        reason: 'the durable stage must never regress and must never '
            'advance until an independent re-query proves zero remain.',
      );
    });

    test(
        '22. verification can purge newly appeared stale records and query '
        'again', () async {
      final fp = fingerprint(1);
      final store = InMemorySyncPersistenceStore();
      final epoch = DataEpoch.generate();
      store.seedPendingDeletionTransaction(_tx(
        accountFingerprint: fp,
        replacementDataEpoch: epoch,
        stage: DeletionTransactionStage.verificationPending,
      ));
      // First query: one stale record (a second device raced a new record
      // in after the first purge pass). Second query, after it is purged:
      // zero.
      var callCount = 0;
      final bridge = _FakeCloudKitPlatformBridge()
        ..accountSnapshotProvider = () {
          return _available(fp);
        }
        ..listKeptWisdomRecordNamesProvider = () {
          callCount += 1;
          return callCount == 1
              ? CloudKitKeptWisdomRecordNamesResult.success(
                  const ['east-kept-stale-1'],
                )
              : CloudKitKeptWisdomRecordNamesResult.success(const []);
        };
      final runner = CloudKitRemoteDeletionRunner(
        bridge: bridge,
        persistenceStore: store,
      );

      final result = await runner.run();

      expect(bridge.deleteRequests.single.recordNames, ['east-kept-stale-1']);
      expect(bridge.listKeptWisdomRecordNamesCallCount, 2);
      expect(
        result.outcome,
        RemoteDeletionRunOutcome.reachedLocalFinalizePending,
      );
    });

    test('23. bounded verification retry cannot infinite-loop', () async {
      final fp = fingerprint(1);
      final store = InMemorySyncPersistenceStore();
      final epoch = DataEpoch.generate();
      store.seedPendingDeletionTransaction(_tx(
        accountFingerprint: fp,
        replacementDataEpoch: epoch,
        stage: DeletionTransactionStage.verificationPending,
      ));
      var counter = 0;
      final bridge = _FakeCloudKitPlatformBridge()
        ..accountSnapshotProvider = () {
          return _available(fp);
        }
        ..listKeptWisdomRecordNamesProvider = () {
          counter += 1;
          return CloudKitKeptWisdomRecordNamesResult.success(
            ['east-kept-stale-$counter'],
          );
        };
      final runner = CloudKitRemoteDeletionRunner(
        bridge: bridge,
        persistenceStore: store,
      );

      final result = await runner.run();

      expect(result.outcome, RemoteDeletionRunOutcome.progressed);
      expect(
        bridge.listKeptWisdomRecordNamesCallCount,
        3,
        reason: 'exactly the bounded number of iterations (3), never more '
            '-- a single run() call must always return, never loop '
            'forever.',
      );
    });

    test('24. crash at verificationPending resumes safely', () async {
      final fp = fingerprint(1);
      final store = InMemorySyncPersistenceStore();
      final epoch = DataEpoch.generate();
      // Simulates a process that already durably reached
      // verificationPending (e.g. from a prior run() call/process that then
      // crashed) -- this test seeds the transaction directly at that stage,
      // exactly as a real relaunch would resume it, and confirms a fresh
      // runner instance completes safely from durable state alone.
      store.seedPendingDeletionTransaction(_tx(
        accountFingerprint: fp,
        replacementDataEpoch: epoch,
        stage: DeletionTransactionStage.verificationPending,
      ));
      final bridge = _FakeCloudKitPlatformBridge()
        ..accountSnapshotProvider = () {
          return _available(fp);
        }
        ..listKeptWisdomRecordNamesProvider = () {
          return CloudKitKeptWisdomRecordNamesResult.success(const []);
        };
      final runner = CloudKitRemoteDeletionRunner(
        bridge: bridge,
        persistenceStore: store,
      );

      final result = await runner.run();

      expect(
        result.outcome,
        RemoteDeletionRunOutcome.reachedLocalFinalizePending,
      );
    });

    test('25. final stage after this slice is localFinalizePending', () async {
      final fp = fingerprint(1);
      final store = InMemorySyncPersistenceStore();
      final epoch = DataEpoch.generate();
      store.seedPendingDeletionTransaction(_tx(
        accountFingerprint: fp,
        replacementDataEpoch: epoch,
        stage: DeletionTransactionStage.prepared,
      ));
      // Every default hook already succeeds and returns an empty
      // CKKeptWisdom listing, so a single run() call from `prepared` should
      // drive the whole transaction all the way through.
      final bridge = _FakeCloudKitPlatformBridge()
        ..accountSnapshotProvider = () => _available(fp);
      final runner = CloudKitRemoteDeletionRunner(
        bridge: bridge,
        persistenceStore: store,
      );

      final result = await runner.run();

      expect(
        result.outcome,
        RemoteDeletionRunOutcome.reachedLocalFinalizePending,
      );
      expect(result.stage, DeletionTransactionStage.localFinalizePending);
    });

    test('26. transaction is NOT cleared in this slice', () async {
      final fp = fingerprint(1);
      final store = InMemorySyncPersistenceStore();
      final epoch = DataEpoch.generate();
      store.seedPendingDeletionTransaction(_tx(
        accountFingerprint: fp,
        replacementDataEpoch: epoch,
        stage: DeletionTransactionStage.localFinalizePending,
      ));
      final bridge = _FakeCloudKitPlatformBridge();
      final runner = CloudKitRemoteDeletionRunner(
        bridge: bridge,
        persistenceStore: store,
      );

      final result = await runner.run();

      expect(
        result.outcome,
        RemoteDeletionRunOutcome.alreadyAtLocalFinalizePending,
      );
      bridge.expectNoCalls();
      final persisted = await store.loadPendingDeletionTransaction();
      expect(
        persisted,
        isNotNull,
        reason: 'clearing the transaction is a future slice\'s scope -- '
            'this slice\'s runner must leave it in place.',
      );
      expect(persisted!.stage, DeletionTransactionStage.localFinalizePending);
    });
  });

  group('Privacy', () {
    test('27. runner summaries do not leak account fingerprint', () async {
      final fp = fingerprint(1);
      final store = InMemorySyncPersistenceStore();
      final epoch = DataEpoch.generate();
      store.seedPendingDeletionTransaction(_tx(
        accountFingerprint: fp,
        replacementDataEpoch: epoch,
        stage: DeletionTransactionStage.prepared,
      ));
      final bridge = _FakeCloudKitPlatformBridge()
        ..accountSnapshotProvider = () => _available(fp);
      final runner = CloudKitRemoteDeletionRunner(
        bridge: bridge,
        persistenceStore: store,
      );

      final result = await runner.run();
      final summaryMap = result.toLogSafeSummary();
      final summary = summaryMap.toString();
      final rendered = result.toString();

      expect(summaryMap.containsKey('accountFingerprint'), isFalse);
      expect(summaryMap.containsKey('replacementDataEpoch'), isFalse);
      expect(summaryMap.containsKey('originalDataEpoch'), isFalse);
      expect(summaryMap.containsKey('epoch'), isFalse);
      expect(summary, isNot(contains(fp)));
      expect(rendered, isNot(contains(fp)));
      expect(summary, isNot(contains(epoch.value)));
      expect(rendered, isNot(contains(epoch.value)));
    });

    test('28. transport errors do not leak recordName', () async {
      final fp = fingerprint(1);
      final store = InMemorySyncPersistenceStore();
      final epoch = DataEpoch.generate();
      store.seedPendingDeletionTransaction(_tx(
        accountFingerprint: fp,
        replacementDataEpoch: epoch,
        stage: DeletionTransactionStage.cloudPurgePending,
      ));
      const secretRecordName = 'east-kept-should-never-be-logged';
      final bridge = _FakeCloudKitPlatformBridge()
        ..accountSnapshotProvider = () {
          return _available(fp);
        }
        ..listKeptWisdomRecordNamesProvider = () {
          return CloudKitKeptWisdomRecordNamesResult.success(
            const [secretRecordName],
          );
        }
        ..deleteKeptWisdomRecordsProvider = (_) {
          return CloudKitDeleteKeptWisdomRecordsResult.transportFailure(
            syncErrorCodeNetworkFailure,
          );
        };
      final runner = CloudKitRemoteDeletionRunner(
        bridge: bridge,
        persistenceStore: store,
      );

      final result = await runner.run();
      final rendered = result.toString();

      expect(rendered, isNot(contains(secretRecordName)));
    });

    test('29. no wisdom/reflection content appears in deletion diagnostics',
        () async {
      final fp = fingerprint(1);
      final store = InMemorySyncPersistenceStore();
      final epoch = DataEpoch.generate();
      store.seedPendingDeletionTransaction(_tx(
        accountFingerprint: fp,
        replacementDataEpoch: epoch,
        stage: DeletionTransactionStage.prepared,
      ));
      final bridge = _FakeCloudKitPlatformBridge()
        ..accountSnapshotProvider = () => _available(fp);
      final runner = CloudKitRemoteDeletionRunner(
        bridge: bridge,
        persistenceStore: store,
      );

      final result = await runner.run();
      final rendered = result.toString();

      // CloudKitRemoteDeletionRunner never reads wisdom/Reflection content
      // in the first place (listKeptWisdomRecordNames is content-free by
      // construction -- see
      // cloud_kit_kept_wisdom_record_names_contract.dart), so there is
      // nothing for this result to leak; this asserts the rendered summary
      // carries only outcome/stage tokens.
      expect(rendered, contains('outcome'));
      expect(rendered, isNot(contains('wisdomText')));
      expect(rendered, isNot(contains('reflectionText')));
    });
  });

  group('Daily-state non-regression', () {
    test(
        '30. no daily access file/service is modified or called by this '
        'slice', () {
      final file =
          File('lib/sync_deletion/cloud_kit_remote_deletion_runner.dart');
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();
      const forbidden = [
        'daily_wisdom_access_service.dart',
        'daily_access_repository.dart',
        'DailyWisdomAccessService',
        'DailyAccessRepository',
        'unlockAt',
        'daily_wisdom_access',
      ];
      for (final term in forbidden) {
        expect(content, isNot(contains(term)), reason: term);
      }
    });

    test('31. no extra wisdom is generated', () {
      final file =
          File('lib/sync_deletion/cloud_kit_remote_deletion_runner.dart');
      expect(file.existsSync(), isTrue);
      final violations = <String>[];
      for (final line in file.readAsLinesSync()) {
        final trimmed = line.trimLeft();
        if (!trimmed.startsWith('import ') && !trimmed.startsWith('export ')) {
          continue;
        }
        if (trimmed.contains('repositories/') ||
            trimmed.contains('services/')) {
          violations.add(trimmed);
        }
      }
      expect(
        violations,
        isEmpty,
        reason: 'the deletion runner must never import a repository or '
            'service file -- it has no way to read, generate, or reveal '
            'wisdom/Reflection content of any kind. Violations: '
            '${violations.join(', ')}',
      );
    });
  });
}
