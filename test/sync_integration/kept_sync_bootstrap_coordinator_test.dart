// Build 26 Phase 4E-4: KeptSyncBootstrapCoordinator -- existing-user
// remote-first bootstrap, explicit account association, and legacy local
// backfill. Synthetic content only.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/models/kept_bootstrap_result.dart';
import 'package:wisdom_app/models/kept_record.dart';
import 'package:wisdom_app/persistence/file_protection_bridge.dart';
import 'package:wisdom_app/persistence/persistence_operation_coordinator.dart';
import 'package:wisdom_app/repositories/kept_repository.dart';
import 'package:wisdom_app/sync/cloud_east_sync_state_projection.dart';
import 'package:wisdom_app/sync/cloud_kept_wisdom_projection.dart';
import 'package:wisdom_app/sync/data_epoch.dart';
import 'package:wisdom_app/sync/sync_record_identity.dart';
import 'package:wisdom_app/sync/sync_tombstone.dart';
import 'package:wisdom_app/sync_integration/incoming_kept_sync_coordinator.dart';
import 'package:wisdom_app/sync_integration/kept_sync_bootstrap_coordinator.dart';
import 'package:wisdom_app/sync_integration/kept_sync_integration_coordinator.dart';
import 'package:wisdom_app/sync_integration/local_sync_intent.dart';
import 'package:wisdom_app/sync_integration/local_sync_intent_store.dart';
import 'package:wisdom_app/sync_integration/protected_local_sync_intent_store.dart';
import 'package:wisdom_app/sync_persistence/account_sync_state.dart';
import 'package:wisdom_app/sync_persistence/associated_account_fingerprint_commit.dart';
import 'package:wisdom_app/sync_persistence/persisted_outbox_mutation.dart';
import 'package:wisdom_app/sync_persistence/protected_sync_persistence_store.dart';
import 'package:wisdom_app/sync_platform/cloud_east_sync_state_wire_envelope.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_account_snapshot.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_bridge_info.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_account_change_event.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_delete_records_contract.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_kept_wisdom_record_names_contract.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_modify_records_contract.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_platform_bridge.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_platform_error.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_sync_state_epoch_contract.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_zone_changes_contract.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_zone_configuration_result.dart';
import 'package:wisdom_app/utils/kept_timestamp_canonicalizer.dart';
import 'package:wisdom_app/utils/remote_kept_identity.dart';

import '../persistence_test_helpers.dart';
import 'in_memory_sync_test_doubles.dart';

/// A controllable [CloudKitPlatformBridge] fake -- mirrors
/// `sync_orchestrator_test.dart`'s own `_FakeCloudKitPlatformBridge`
/// precedent (never a real MethodChannel/CloudKit container).
class _FakeCloudKitPlatformBridge implements CloudKitPlatformBridge {
  List<CloudKitAccountSnapshot>? accountSnapshotSequence;
  int _snapshotIndex = 0;
  CloudKitZoneConfigurationResult Function()? zoneConfigurationProvider;
  CloudKitModifyRecordsResult Function(CloudKitModifyRecordsRequest)?
      modifyProvider;
  CloudKitZoneChangesResult Function(CloudKitZoneChangesRequest)? fetchProvider;
  CloudKitSyncStateEpochResult Function()? syncStateEpochProvider;

  /// When set, `fetchPrivateZoneChanges` awaits this completer before
  /// resolving -- used to hold a fetch open so a test can prove other work
  /// proceeds concurrently (i.e. the integration lock is not held across the
  /// fetch).
  Completer<void>? holdFetchUntil;

  /// When set, `modifyPrivateRecords` awaits this completer before
  /// resolving -- used to hold the one-time empty-remote control-record
  /// upload open so a test can prove other work proceeds concurrently (i.e.
  /// the integration lock is not held across that upload either).
  Completer<void>? holdModifyUntil;

  final List<String> callOrder = [];
  int getAccountSnapshotCallCount = 0;
  int configurePrivateZoneCallCount = 0;
  int modifyPrivateRecordsCallCount = 0;
  int fetchPrivateZoneChangesCallCount = 0;
  int fetchSyncStateEpochCallCount = 0;
  final List<CloudKitModifyRecordsRequest> modifyRequests = [];
  final List<CloudKitZoneChangesRequest> fetchRequests = [];

  @override
  Future<CloudKitAccountSnapshot> getAccountSnapshot() async {
    getAccountSnapshotCallCount += 1;
    callOrder.add('getAccountSnapshot');
    final sequence = accountSnapshotSequence!;
    final index =
        _snapshotIndex < sequence.length ? _snapshotIndex : sequence.length - 1;
    _snapshotIndex += 1;
    return sequence[index];
  }

  @override
  Future<CloudKitZoneConfigurationResult> configurePrivateZone() async {
    configurePrivateZoneCallCount += 1;
    callOrder.add('configurePrivateZone');
    return zoneConfigurationProvider!.call();
  }

  @override
  Future<CloudKitBridgeInfo> getBridgeInfo() =>
      throw UnimplementedError('Not used by KeptSyncBootstrapCoordinator.');

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
    final hold = holdModifyUntil;
    if (hold != null) {
      await hold.future;
    }
    return modifyProvider!.call(request);
  }

  @override
  Future<CloudKitZoneChangesResult> fetchPrivateZoneChanges(
    CloudKitZoneChangesRequest request,
  ) async {
    fetchPrivateZoneChangesCallCount += 1;
    fetchRequests.add(request);
    callOrder.add('fetchPrivateZoneChanges');
    final hold = holdFetchUntil;
    if (hold != null) {
      await hold.future;
    }
    return fetchProvider!.call(request);
  }

  @override
  Future<CloudKitSyncStateEpochResult> fetchSyncStateEpoch() async {
    fetchSyncStateEpochCallCount += 1;
    callOrder.add('fetchSyncStateEpoch');
    return syncStateEpochProvider!.call();
  }

  @override
  Future<CloudKitKeptWisdomRecordNamesResult> listKeptWisdomRecordNames() =>
      throw UnimplementedError('Not used by KeptSyncBootstrapCoordinator.');

  @override
  Future<CloudKitDeleteKeptWisdomRecordsResult> deleteKeptWisdomRecords(
    CloudKitDeleteKeptWisdomRecordsRequest request,
  ) =>
      throw UnimplementedError('Not used by KeptSyncBootstrapCoordinator.');
}

void main() {
  const fingerprintA =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const fingerprintB =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const fingerprintC =
      'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
  final epoch = DataEpoch.parse('11111111-1111-4111-8111-111111111111');
  final otherEpoch = DataEpoch.parse('99999999-9999-4999-8999-999999999999');
  const revealIdA = 'aaaaaaaa-1111-4111-8111-111111111111';
  const revealIdB = 'bbbbbbbb-2222-4222-8222-222222222222';
  final t0 = DateTime.utc(2026, 8, 1, 10);

  String mutationIdFor(String seed) => 'eeeeeeee${seed.substring(8)}';
  String systemFieldsFor(String recordName) => 'c3lzdGVtRmllbGRz';

  CloudKitAccountSnapshot availableSnapshot({
    String fingerprint = fingerprintA,
  }) =>
      CloudKitAccountSnapshot(
        availability: CloudKitAccountAvailability.available,
        isPrivateDatabaseUsable: true,
        accountFingerprint: fingerprint,
        fingerprintResolved: true,
        bridgeVersion: 1,
      );

  const unavailableSnapshot = CloudKitAccountSnapshot(
    availability: CloudKitAccountAvailability.noAccount,
    isPrivateDatabaseUsable: false,
    accountFingerprint: null,
    fingerprintResolved: false,
    bridgeVersion: 1,
  );

  const unresolvedFingerprintSnapshot = CloudKitAccountSnapshot(
    availability: CloudKitAccountAvailability.available,
    isPrivateDatabaseUsable: true,
    accountFingerprint: null,
    fingerprintResolved: false,
    bridgeVersion: 1,
  );

  KeptRecord buildRecord({
    required String id,
    required String revealId,
    String wisdomText = 'Be still and know.',
    DateTime? revealedAt,
    DateTime? keptAt,
    DateTime? updatedAt,
    String? reflectionText,
    DateTime? reflectedAt,
    String? mutationId,
  }) {
    return KeptRecord(
      id: id,
      revealId: revealId,
      wisdomText: wisdomText,
      revealedAt: revealedAt ?? t0,
      keptAt: keptAt ?? t0.add(const Duration(minutes: 5)),
      updatedAt: updatedAt ?? keptAt ?? t0.add(const Duration(minutes: 5)),
      reflectionText: reflectionText,
      reflectedAt: reflectedAt,
      mutationId: mutationId ?? mutationIdFor(revealId),
    );
  }

  CloudKeptWisdomProjection activeProjection({
    required String revealId,
    String wisdomText = 'Be still and know.',
    DateTime? revealedAt,
    DateTime? keptAt,
    DateTime? updatedAt,
    String? reflectionText,
    DateTime? reflectedAt,
    String? mutationId,
    DataEpoch? dataEpoch,
  }) {
    return CloudKeptWisdomProjection.active(
      buildRecord(
        id: 'conversion-vehicle-only',
        revealId: revealId,
        wisdomText: wisdomText,
        revealedAt: revealedAt,
        keptAt: keptAt,
        updatedAt: updatedAt,
        reflectionText: reflectionText,
        reflectedAt: reflectedAt,
        mutationId: mutationId,
      ),
      dataEpoch: dataEpoch ?? epoch,
    );
  }

  CloudKeptWisdomProjection tombstoneProjection({
    required String revealId,
    DateTime? updatedAt,
    DateTime? deletedAt,
    String? mutationId,
    DataEpoch? dataEpoch,
  }) {
    return CloudKeptWisdomProjection.tombstone(
      SyncTombstone(
        revealId: revealId,
        dataEpoch: dataEpoch ?? epoch,
        updatedAt: updatedAt ?? t0,
        deletedAt: deletedAt ?? t0,
        mutationId: mutationId ?? mutationIdFor(revealId),
      ),
    );
  }

  CloudKitZoneChangesResult successResult({
    List<CloudKeptWisdomProjection> records = const [],
    List<CloudEastSyncStateProjection> syncState = const [],
    String serverToken = 'bmV3dG9rZW4=',
    Map<String, String>? systemFields,
  }) {
    return CloudKitZoneChangesResult.success(
      changedKeptWisdomRecords: records,
      changedSyncStateRecords: syncState,
      serverToken: serverToken,
      keptWisdomRecordSystemFields: systemFields ??
          {
            for (final r in records) r.recordName: systemFieldsFor(r.recordName)
          },
    );
  }

  late InMemoryKeptStateStore keptStore;
  late KeptRepository keptRepository;
  late InMemoryLocalSyncIntentStore intentStore;
  late InMemorySyncPersistenceStore syncStore;
  late PersistenceOperationCoordinator sharedCoordinator;
  late _FakeCloudKitPlatformBridge bridge;
  late KeptSyncBootstrapCoordinator bootstrapCoordinator;

  setUp(() {
    keptStore = InMemoryKeptStateStore();
    keptRepository = KeptRepository(
      store: keptStore,
      bootstrap: const KeptBootstrapResult.ready(),
      operationCoordinator: PersistenceOperationCoordinator(),
    );
    intentStore = InMemoryLocalSyncIntentStore();
    syncStore = InMemorySyncPersistenceStore();
    sharedCoordinator = PersistenceOperationCoordinator();
    bridge = _FakeCloudKitPlatformBridge()
      ..accountSnapshotSequence = [availableSnapshot()]
      ..zoneConfigurationProvider = () => const CloudKitZoneConfigurationResult(
            success: true,
            zoneCreated: false,
            zoneAlreadyExisted: true,
            accountAvailability: CloudKitAccountAvailability.available,
          );
    // Explicit separate assignments (not cascaded off the constructor call
    // above) -- `..fetchProvider`/`..modifyProvider` chained directly after
    // the `CloudKitZoneConfigurationResult(...)` call's closing paren would
    // bind to *that* result object, not to `bridge` itself.
    bridge.fetchProvider = (_) => successResult();
    bridge.syncStateEpochProvider = () => CloudKitSyncStateEpochResult.found(
          dataEpoch: epoch,
          systemFields: systemFieldsFor(
            CloudEastSyncStateProjection.recordName,
          ),
        );
    bridge.modifyProvider =
        (request) => CloudKitModifyRecordsResult.allSucceeded([
              for (final _ in request.records)
                CloudKitRecordModifyOutcome.success(
                  recordName: CloudEastSyncStateProjection.recordName,
                  systemFields:
                      systemFieldsFor(CloudEastSyncStateProjection.recordName),
                ),
            ]);
    bootstrapCoordinator = KeptSyncBootstrapCoordinator(
      bridge: bridge,
      keptRepository: keptRepository,
      intentStore: intentStore,
      syncPersistenceStore: syncStore,
      integrationCoordinator: sharedCoordinator,
      idFactory: _sequentialIdFactory(),
      clock: () => t0,
    );
  });

  Future<void> seedLocalRecord(KeptRecord record) async {
    final all = await keptRepository.loadAllRecords();
    await keptRepository.replaceAllRecords([...all, record]);
  }

  void seedBucket(
    AccountBootstrapState bootstrapState, {
    String fingerprint = fingerprintA,
    DataEpoch? dataEpoch,
    String? serverChangeToken,
    List<PersistedOutboxMutation> outbox = const [],
    Map<String, String> recordSystemFields = const {},
  }) {
    syncStore.seedAccount(
      fingerprint,
      AccountSyncState(
        dataEpoch: dataEpoch ?? epoch,
        serverChangeToken: serverChangeToken,
        outbox: outbox,
        recordSystemFields: recordSystemFields,
        bootstrapState: bootstrapState,
      ),
    );
  }

  group('shared lock key', () {
    test(
        'KeptSyncBootstrapCoordinator.resourceKey equals '
        'KeptSyncIntegrationCoordinator.resourceKey and '
        'IncomingKeptSyncCoordinator.resourceKey exactly', () {
      expect(
        KeptSyncBootstrapCoordinator.resourceKey,
        KeptSyncIntegrationCoordinator.resourceKey,
      );
      expect(
        KeptSyncBootstrapCoordinator.resourceKey,
        IncomingKeptSyncCoordinator.resourceKey,
      );
    });
  });

  group('1-15. association evaluation / authorization / legacy repair', () {
    test('1. no marker + no local history -> autoAssociable', () async {
      final result = await bootstrapCoordinator.evaluateAssociation();
      expect(result.status, AssociationEvaluationStatus.autoAssociable);
    });

    test('2. no marker + local history -> associationRequired', () async {
      await seedLocalRecord(buildRecord(id: 'k1', revealId: revealIdA));
      final result = await bootstrapCoordinator.evaluateAssociation();
      expect(result.status, AssociationEvaluationStatus.associationRequired);
    });

    test('3. marker == current -> resumeAssociation', () async {
      syncStore.seedAssociatedAccountFingerprint(fingerprintA);
      final result = await bootstrapCoordinator.evaluateAssociation();
      expect(result.status, AssociationEvaluationStatus.resumeAssociation);
    });

    test('4. marker != current -> associationRequired', () async {
      syncStore.seedAssociatedAccountFingerprint(fingerprintB);
      final result = await bootstrapCoordinator.evaluateAssociation();
      expect(result.status, AssociationEvaluationStatus.associationRequired);
    });

    test('5. account unavailable', () async {
      bridge.accountSnapshotSequence = [unavailableSnapshot];
      final result = await bootstrapCoordinator.evaluateAssociation();
      expect(result.status, AssociationEvaluationStatus.accountUnavailable);
    });

    test('6. fingerprint unresolved', () async {
      bridge.accountSnapshotSequence = [unresolvedFingerprintSnapshot];
      final result = await bootstrapCoordinator.evaluateAssociation();
      expect(result.status, AssociationEvaluationStatus.fingerprintUnresolved);
    });

    test('7. evaluateAssociation performs zero writes', () async {
      await seedLocalRecord(buildRecord(id: 'k1', revealId: revealIdA));
      await bootstrapCoordinator.evaluateAssociation();
      expect(await syncStore.loadAssociatedAccountFingerprint(), isNull);
      expect(await syncStore.loadAccountState(fingerprintA), isNull);
      expect(await syncStore.loadMeaningfulAccountFingerprints(), isEmpty);
    });

    test('8. zero legacy meaningful buckets -> ordinary A/B', () async {
      final result = await bootstrapCoordinator.evaluateAssociation();
      expect(result.status, AssociationEvaluationStatus.autoAssociable);
    });

    test(
        '9. exactly one legacy meaningful bucket -> unresolvedLegacyAssociation',
        () async {
      seedBucket(
        AccountBootstrapState.remoteBaselinePending,
        fingerprint: fingerprintB,
      );
      final result = await bootstrapCoordinator.evaluateAssociation();
      expect(
        result.status,
        AssociationEvaluationStatus.unresolvedLegacyAssociation,
      );
    });

    test('10. multiple meaningful legacy buckets -> ambiguousLegacyState',
        () async {
      seedBucket(
        AccountBootstrapState.remoteBaselinePending,
        fingerprint: fingerprintB,
      );
      seedBucket(
        AccountBootstrapState.complete,
        fingerprint: fingerprintC,
      );
      final result = await bootstrapCoordinator.evaluateAssociation();
      expect(result.status, AssociationEvaluationStatus.ambiguousLegacyState);
    });

    test(
        'notStarted-only bucket is never treated as a meaningful legacy '
        'candidate', () async {
      seedBucket(AccountBootstrapState.notStarted, fingerprint: fingerprintB);
      final result = await bootstrapCoordinator.evaluateAssociation();
      expect(result.status, AssociationEvaluationStatus.autoAssociable);
    });

    test(
        '11a. legacy repair succeeds when current fingerprint == sole '
        'candidate', () async {
      seedBucket(
        AccountBootstrapState.remoteBaselinePending,
        fingerprint: fingerprintA,
      );
      final result = await bootstrapCoordinator.repairLegacyAssociationMarker(
        expectedCandidateFingerprint: fingerprintA,
      );
      expect(result.status, LegacyAssociationRepairStatus.repaired);
      expect(
        await syncStore.loadAssociatedAccountFingerprint(),
        fingerprintA,
      );
    });

    test(
        '11b. legacy repair fails closed when candidate != current '
        'fingerprint', () async {
      seedBucket(
        AccountBootstrapState.remoteBaselinePending,
        fingerprint: fingerprintB,
      );
      final result = await bootstrapCoordinator.repairLegacyAssociationMarker(
        expectedCandidateFingerprint: fingerprintB,
      );
      expect(result.status, LegacyAssociationRepairStatus.accountChanged);
      expect(await syncStore.loadAssociatedAccountFingerprint(), isNull);
    });

    test('12. legacy repair re-derives candidates fresh, fails on ambiguity',
        () async {
      seedBucket(
        AccountBootstrapState.remoteBaselinePending,
        fingerprint: fingerprintA,
      );
      seedBucket(
        AccountBootstrapState.complete,
        fingerprint: fingerprintB,
      );
      final result = await bootstrapCoordinator.repairLegacyAssociationMarker(
        expectedCandidateFingerprint: fingerprintA,
      );
      expect(result.status, LegacyAssociationRepairStatus.ambiguousCandidates);
      expect(await syncStore.loadAssociatedAccountFingerprint(), isNull);
    });

    test('13. marker CAS cannot overwrite a different marker', () async {
      syncStore.seedAssociatedAccountFingerprint(fingerprintA);
      final result = await syncStore.commitAssociatedAccountFingerprint(
        fingerprint: fingerprintB,
        expectedCurrent: null,
      );
      expect(
        result.status,
        AssociatedAccountFingerprintCommitStatus.expectedCurrentMismatch,
      );
      expect(
        await syncStore.loadAssociatedAccountFingerprint(),
        fingerprintA,
      );
    });

    test('14. authorizeAssociation cannot silently replace a different marker',
        () async {
      syncStore.seedAssociatedAccountFingerprint(fingerprintB);
      final result = await bootstrapCoordinator.authorizeAssociation(
        fingerprint: fingerprintA,
      );
      expect(
        result.status,
        AssociationAuthorizationStatus.differentAssociationExists,
      );
      expect(
        await syncStore.loadAssociatedAccountFingerprint(),
        fingerprintB,
      );
    });

    test('authorizeAssociation is idempotent on an already-matching marker',
        () async {
      syncStore.seedAssociatedAccountFingerprint(fingerprintA);
      final result = await bootstrapCoordinator.authorizeAssociation(
        fingerprint: fingerprintA,
      );
      expect(result.status, AssociationAuthorizationStatus.alreadyAuthorized);
    });

    test('authorizeAssociation refuses a fingerprint the account no longer has',
        () async {
      bridge.accountSnapshotSequence = [
        availableSnapshot(fingerprint: fingerprintB)
      ];
      final result = await bootstrapCoordinator.authorizeAssociation(
        fingerprint: fingerprintA,
      );
      expect(result.status, AssociationAuthorizationStatus.accountMismatch);
      expect(await syncStore.loadAssociatedAccountFingerprint(), isNull);
    });
  });

  group('16-23. remote-first fetch', () {
    test('16. associationRequired performs no network fetch', () async {
      await seedLocalRecord(buildRecord(id: 'k1', revealId: revealIdA));
      final result = await bootstrapCoordinator.runBootstrap();
      expect(result.status, BootstrapRunStatus.associationRequired);
      expect(bridge.fetchPrivateZoneChangesCallCount, 0);
      expect(bridge.modifyPrivateRecordsCallCount, 0);
      expect(bridge.configurePrivateZoneCallCount, 0);
    });

    test('17. first clean device fetches with previousServerToken null',
        () async {
      bridge.fetchProvider = (_) => successResult(
            syncState: [
              CloudEastSyncStateProjection.current(
                dataEpoch: epoch,
                mutationId: mutationIdFor(revealIdA),
              ),
            ],
          );
      final result = await bootstrapCoordinator.runBootstrap();
      expect(result.status, BootstrapRunStatus.completed);
      expect(bridge.fetchRequests.single.previousServerToken, isNull);
    });

    test('18. remote baseline adopted before any content upload', () async {
      bridge.fetchProvider = (_) => successResult(
            records: [activeProjection(revealId: revealIdA)],
            syncState: [
              CloudEastSyncStateProjection.current(
                dataEpoch: epoch,
                mutationId: mutationIdFor(revealIdA),
              ),
            ],
          );
      final result = await bootstrapCoordinator.runBootstrap();
      expect(result.status, BootstrapRunStatus.completed);
      // No KeptWisdom record upload ever happens from this coordinator.
      for (final request in bridge.modifyRequests) {
        for (final record in request.records) {
          expect(record.recordType, isNot('CKKeptWisdom'));
        }
      }
    });

    test(
        '19. empty remote creates CKEastSyncState with a fresh epoch, '
        'verifies it via a mandatory post-upload re-fetch (never trusting '
        'the generated epoch on its own), and commits using the verified '
        'epoch/token', () async {
      var fetchCallCount = 0;
      bridge.fetchProvider = (request) {
        fetchCallCount += 1;
        if (fetchCallCount == 1) {
          // Initial baseline fetch: genuinely empty remote.
          expect(request.previousServerToken, isNull);
          return successResult();
        }
        // Mandatory post-upload verification re-fetch -- must happen after
        // the upload, using the pre-upload token.
        expect(bridge.modifyPrivateRecordsCallCount, 1);
        expect(request.previousServerToken, 'bmV3dG9rZW4=');
        final uploaded = CloudEastSyncStateWireEnvelope.tryDecode(
          bridge.modifyRequests.single.records.single.fields,
        )!;
        return successResult(
          syncState: [uploaded],
          serverToken: 'cG9zdHVwbG9hZA==',
        );
      };

      final result = await bootstrapCoordinator.runBootstrap();
      expect(result.status, BootstrapRunStatus.completed);
      expect(bridge.modifyPrivateRecordsCallCount, 1);
      expect(bridge.fetchPrivateZoneChangesCallCount, 2);
      expect(bridge.modifyRequests.single.records.single.recordType,
          'CKEastSyncState');
      final bucket = await syncStore.loadAccountState(fingerprintA);
      expect(bucket, isNotNull);
      expect(bucket!.bootstrapState, AccountBootstrapState.complete);
      // The committed epoch/token are whichever the *verification* re-fetch
      // reported -- proving the generated epoch was never trusted on its
      // own, and the stale pre-upload token was never committed either.
      final verified = CloudEastSyncStateWireEnvelope.tryDecode(
        bridge.modifyRequests.single.records.single.fields,
      )!;
      expect(bucket.dataEpoch, verified.dataEpoch);
      expect(bucket.serverChangeToken, 'cG9zdHVwbG9hZA==');
    });

    test(
        '19b. an upload that succeeds but whose verification re-fetch comes '
        'back empty fails closed -- never assumes the generated epoch is '
        'authoritative', () async {
      var fetchCallCount = 0;
      bridge.fetchProvider = (request) {
        fetchCallCount += 1;
        // Every fetch (initial and verification) reports an empty remote --
        // an ambiguous read-after-write gap.
        return successResult();
      };
      final result = await bootstrapCoordinator.runBootstrap();
      expect(result.status, BootstrapRunStatus.controlRecordCreationUnverified);
      expect(await syncStore.loadAccountState(fingerprintA), isNull);
      expect(fetchCallCount, 2);
    });

    test(
        '19c. a verification re-fetch reporting more than one control '
        'record fails closed as controlRecordInvalid', () async {
      var fetchCallCount = 0;
      bridge.fetchProvider = (request) {
        fetchCallCount += 1;
        if (fetchCallCount == 1) return successResult();
        return successResult(
          syncState: [
            CloudEastSyncStateProjection.current(
              dataEpoch: epoch,
              mutationId: mutationIdFor(revealIdA),
            ),
            CloudEastSyncStateProjection.current(
              dataEpoch: otherEpoch,
              mutationId: mutationIdFor(revealIdB),
            ),
          ],
        );
      };
      final result = await bootstrapCoordinator.runBootstrap();
      expect(result.status, BootstrapRunStatus.controlRecordInvalid);
      expect(await syncStore.loadAccountState(fingerprintA), isNull);
    });

    test(
        '20. existing CKEastSyncState epoch adopted exactly -- also the '
        'crash-retry case: if a prior attempt already uploaded a control '
        'record (e.g. the process crashed after that upload but before its '
        'own local checkpoint), this attempt\'s *initial* fetch now '
        'observes it directly and must adopt it rather than generating (or '
        'uploading) a second, competing epoch', () async {
      bridge.fetchProvider = (_) => successResult(
            syncState: [
              CloudEastSyncStateProjection.current(
                dataEpoch: otherEpoch,
                mutationId: mutationIdFor(revealIdA),
              ),
            ],
          );
      final result = await bootstrapCoordinator.runBootstrap();
      expect(result.status, BootstrapRunStatus.completed);
      // Zero uploads -- the already-existing remote control record is
      // adopted as-is, never re-created or overwritten.
      expect(bridge.modifyPrivateRecordsCallCount, 0);
      // Exactly one fetch -- no verification re-fetch is needed (or
      // performed) when the control record already exists on the very
      // first read.
      expect(bridge.fetchPrivateZoneChangesCallCount, 1);
      final bucket = await syncStore.loadAccountState(fingerprintA);
      expect(bucket!.dataEpoch, otherEpoch);
    });

    test('21. multiple control records fail closed', () async {
      bridge.fetchProvider = (_) => successResult(
            syncState: [
              CloudEastSyncStateProjection.current(
                dataEpoch: epoch,
                mutationId: mutationIdFor(revealIdA),
              ),
              CloudEastSyncStateProjection.current(
                dataEpoch: otherEpoch,
                mutationId: mutationIdFor(revealIdB),
              ),
            ],
          );
      final result = await bootstrapCoordinator.runBootstrap();
      expect(result.status, BootstrapRunStatus.controlRecordInvalid);
      expect(await syncStore.loadAccountState(fingerprintA), isNull);
    });

    test(
        '19d. a concurrent device wins the empty-remote creation race -- the '
        'verification re-fetch reports a DIFFERENT epoch than the one this '
        'device generated, and that (foreign) epoch is adopted exactly, '
        'never the locally-generated one', () async {
      var fetchCallCount = 0;
      bridge.fetchProvider = (request) {
        fetchCallCount += 1;
        if (fetchCallCount == 1) return successResult();
        // The verification re-fetch reports a control record whose epoch
        // does NOT match whatever this device just generated and uploaded
        // -- a concurrent device's write won the race at the server. The
        // uploaded fields are deliberately never consulted here.
        return successResult(
          syncState: [
            CloudEastSyncStateProjection.current(
              dataEpoch: otherEpoch,
              mutationId: mutationIdFor(revealIdB),
            ),
          ],
          serverToken: 'Y29uY3VycmVudA==',
        );
      };
      final result = await bootstrapCoordinator.runBootstrap();
      expect(result.status, BootstrapRunStatus.completed);
      expect(bridge.modifyPrivateRecordsCallCount, 1);
      final bucket = await syncStore.loadAccountState(fingerprintA);
      expect(bucket, isNotNull);
      // The committed epoch is the concurrent device's (`otherEpoch`) --
      // never whatever this device's own upload happened to generate.
      expect(bucket!.dataEpoch, otherEpoch);
      expect(bucket.serverChangeToken, 'Y29uY3VycmVudA==');
    });

    test(
        '23b. account changes between the empty-remote control-record '
        'upload and the local checkpoint -> fail closed, zero local '
        'bootstrap mutation, and the uploaded control record (already on '
        'the server) is simply left for a future attempt to discover',
        () async {
      syncStore.seedAssociatedAccountFingerprint(fingerprintA);
      // Four snapshot checks precede the lock on this empty-remote path:
      // evaluateAssociation, `_fetchAndMergeBaseline`'s own initial check,
      // the pre-creation check immediately before `modifyPrivateRecords`
      // (Build 26 Phase 4E-4 correction -- must still see `fingerprintA` so
      // creation is allowed to proceed, since this test targets a *later*
      // account change), and the final pre-lock check (mismatched, as
      // intended).
      bridge.accountSnapshotSequence = [
        availableSnapshot(fingerprint: fingerprintA), // evaluateAssociation
        availableSnapshot(fingerprint: fingerprintA), // initial fetch check
        availableSnapshot(fingerprint: fingerprintA), // pre-creation check
        availableSnapshot(fingerprint: fingerprintB), // final pre-lock check
      ];
      var fetchCallCount = 0;
      bridge.fetchProvider = (request) {
        fetchCallCount += 1;
        if (fetchCallCount == 1) return successResult();
        final uploaded = CloudEastSyncStateWireEnvelope.tryDecode(
          bridge.modifyRequests.single.records.single.fields,
        )!;
        return successResult(syncState: [uploaded]);
      };
      final result = await bootstrapCoordinator.runBootstrap();
      expect(result.status, BootstrapRunStatus.accountChangedDuringFetch);
      // The control record was genuinely uploaded (and verified) before the
      // account-change was detected -- this phase never retracts a
      // completed CloudKit write -- but zero *local* bootstrap state was
      // ever created or mutated as a result.
      expect(bridge.modifyPrivateRecordsCallCount, 1);
      expect(await syncStore.loadAccountState(fingerprintA), isNull);
      expect(await syncStore.loadAssociatedAccountFingerprint(), fingerprintA);
    });

    test(
        '22. the integration lock is released during the network fetch '
        '(a concurrent lock-scoped call for the same account completes '
        'while the fetch is still pending)', () async {
      // A non-empty remote (an existing CKEastSyncState already present) is
      // used here so this test stays scoped purely to proving the lock is
      // released across the *fetch* -- the separate empty-remote
      // create-and-verify sequence has its own dedicated concurrency proof
      // (test "22b" below).
      bridge.fetchProvider = (_) => successResult(
            syncState: [
              CloudEastSyncStateProjection.current(
                dataEpoch: epoch,
                mutationId: mutationIdFor(revealIdA),
              ),
            ],
          );
      final holdFetch = Completer<void>();
      bridge.holdFetchUntil = holdFetch;
      final bootstrapFuture = bootstrapCoordinator.runBootstrap();

      // Give the bootstrap call a chance to reach the (held-open) fetch.
      await Future<void>.delayed(Duration.zero);
      expect(bridge.fetchPrivateZoneChangesCallCount, 1);

      // The concurrent call must use `fingerprintA` -- the same fingerprint
      // the mocked account snapshot reports -- since `repairLegacyAssociation
      // Marker`'s own account check now runs *before* it ever acquires the
      // lock (Build 26 Phase 4E-4 lock correction); a mismatched fingerprint
      // would return `accountChanged` without ever touching the lock at
      // all, which would prove nothing about lock concurrency.
      //
      // If the integration lock were (incorrectly) held across the fetch,
      // this call -- which acquires the exact same resourceKey -- would not
      // be able to complete until the fetch above finishes. It must
      // complete now, before the fetch is released.
      var concurrentCallCompleted = false;
      unawaited(
        bootstrapCoordinator
            .repairLegacyAssociationMarker(
              expectedCandidateFingerprint: fingerprintA,
            )
            .then((_) => concurrentCallCompleted = true),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        concurrentCallCompleted,
        isTrue,
        reason: 'A second lock-scoped call must complete while the network '
            'fetch is still pending -- the integration lock must not be '
            'held across the CloudKit fetch.',
      );

      holdFetch.complete();
      final result = await bootstrapFuture;
      expect(result.status, BootstrapRunStatus.completed);
    });

    test(
        '23. account changes after the initial baseline fetch but before '
        'empty-remote control-record creation -> fail closed, zero '
        'modifyPrivateRecords call, zero local bootstrap mutation', () async {
      // Marker pre-seeded so `evaluateAssociation` resolves directly to
      // `resumeAssociation`, isolating the snapshot sequence to exactly the
      // checks `_fetchAndMergeBaseline` itself performs. The default
      // (empty-syncState) fetch provider means this attempt takes the
      // empty-remote branch, so the THIRD snapshot below is consumed by the
      // Build 26 Phase 4E-4 pre-creation check (immediately before any
      // `modifyPrivateRecords` call) -- not by the later final pre-lock
      // check, which this scenario never reaches.
      syncStore.seedAssociatedAccountFingerprint(fingerprintA);
      bridge.accountSnapshotSequence = [
        availableSnapshot(fingerprint: fingerprintA), // evaluateAssociation
        availableSnapshot(fingerprint: fingerprintA), // initial fetch check
        availableSnapshot(fingerprint: fingerprintB), // pre-creation check
      ];
      final result = await bootstrapCoordinator.runBootstrap();
      expect(result.status, BootstrapRunStatus.accountChangedDuringFetch);
      expect(await syncStore.loadAccountState(fingerprintA), isNull);
      // Zero network mutation: the account-changed detection happens after
      // the baseline fetch has already completed, but strictly before any
      // control-record upload -- confirm no control record was ever
      // uploaded.
      expect(bridge.modifyPrivateRecordsCallCount, 0);
    });

    test(
        "22b. the integration lock is released during the empty-remote "
        'control-record creation/verification round trip (a concurrent '
        'lock-scoped call for the same account completes while the upload '
        'is still pending)', () async {
      var fetchCallCount = 0;
      bridge.fetchProvider = (request) {
        fetchCallCount += 1;
        if (fetchCallCount == 1) return successResult();
        final uploaded = CloudEastSyncStateWireEnvelope.tryDecode(
          bridge.modifyRequests.single.records.single.fields,
        )!;
        return successResult(syncState: [uploaded]);
      };
      final holdModify = Completer<void>();
      bridge.holdModifyUntil = holdModify;
      final bootstrapFuture = bootstrapCoordinator.runBootstrap();

      // Give the call a chance to reach the initial (empty-remote) fetch,
      // complete it, and reach the (held-open) control-record upload.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(bridge.modifyPrivateRecordsCallCount, 1);

      // Same rationale as test "22": the concurrent call must use
      // `fingerprintA` so its own outside-lock account check passes and it
      // actually reaches the lock -- otherwise it would prove nothing.
      var concurrentCallCompleted = false;
      unawaited(
        bootstrapCoordinator
            .repairLegacyAssociationMarker(
              expectedCandidateFingerprint: fingerprintA,
            )
            .then((_) => concurrentCallCompleted = true),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        concurrentCallCompleted,
        isTrue,
        reason: 'A second lock-scoped call must complete while the '
            'control-record upload is still pending -- the integration '
            'lock must not be held across any CloudKit bridge call, '
            'including modifyPrivateRecords.',
      );

      holdModify.complete();
      final result = await bootstrapFuture;
      expect(result.status, BootstrapRunStatus.completed);
    });
  });

  group('24-32. baseline merge', () {
    // Every physical local candidate is, by construction, always tagged
    // with whatever epoch this bootstrap run actually adopts (see
    // `_resolveOneRecord`'s `CloudKeptWisdomProjection.active(record,
    // dataEpoch: epoch)` -- the *authoritative* epoch, never the record's
    // own). For these merge tests to genuinely exercise
    // `resolveKeptWisdomConflict`'s `updatedAt`/tombstone precedence
    // (rather than trivially resolving on an epoch mismatch every time),
    // every fetch below adopts a `CKEastSyncState` whose `dataEpoch` equals
    // the same fixed `epoch` this file's `activeProjection`/
    // `tombstoneProjection` helpers already tag every remote projection
    // with -- so both sides genuinely belong to the same authoritative
    // epoch and the fold falls through to the real precedence rules.
    final matchingSyncState = [
      CloudEastSyncStateProjection.current(
        dataEpoch: epoch,
        mutationId: mutationIdFor(revealIdA),
      ),
    ];

    setUp(() {
      // These scenarios exercise the merge fold against existing local
      // history -- that requires an already-authorized association
      // (marker set) so evaluateAssociation resolves to resumeAssociation
      // even though local Kept history exists (H is only consulted when the
      // marker is absent).
      syncStore.seedAssociatedAccountFingerprint(fingerprintA);
    });

    test('24. remote active restore', () async {
      bridge.fetchProvider = (_) => successResult(
            records: [activeProjection(revealId: revealIdA)],
            syncState: matchingSyncState,
          );
      final result = await bootstrapCoordinator.runBootstrap();
      expect(result.status, BootstrapRunStatus.completed);
      final records = await keptRepository.loadAllRecords();
      expect(records, hasLength(1));
      expect(records.single.revealId, revealIdA);
      expect(records.single.id, deriveIncomingKeptLocalId(revealIdA));
    });

    test('25. remote Reflection restore', () async {
      bridge.fetchProvider = (_) => successResult(
            records: [
              activeProjection(
                revealId: revealIdA,
                reflectionText: 'A quiet thought.',
                reflectedAt: t0.add(const Duration(minutes: 10)),
              ),
            ],
            syncState: matchingSyncState,
          );
      await bootstrapCoordinator.runBootstrap();
      final records = await keptRepository.loadAllRecords();
      expect(records.single.reflectionText, 'A quiet thought.');
    });

    test(
        '26. duplicate wisdom text under different revealIds stays independent',
        () async {
      bridge.fetchProvider = (_) => successResult(
            records: [
              activeProjection(revealId: revealIdA, wisdomText: 'Same text.'),
              activeProjection(revealId: revealIdB, wisdomText: 'Same text.'),
            ],
            syncState: matchingSyncState,
          );
      await bootstrapCoordinator.runBootstrap();
      final records = await keptRepository.loadAllRecords();
      expect(records, hasLength(2));
      expect(records.map((r) => r.revealId).toSet(), {revealIdA, revealIdB});
    });

    test('27a. overlapping revealId -- newer local physical record wins',
        () async {
      await seedLocalRecord(
        buildRecord(
          id: 'local-1',
          revealId: revealIdA,
          wisdomText: 'Local text.',
          updatedAt: t0.add(const Duration(days: 1)),
        ),
      );
      bridge.fetchProvider = (_) => successResult(
            records: [
              activeProjection(
                revealId: revealIdA,
                wisdomText: 'Local text.',
                // `keptAt` pinned to the same instant as `updatedAt` (both
                // `t0`, still strictly older than the local record's `t0 +
                // 1 day`) -- `buildRecord`'s own default `keptAt` (`t0 + 5
                // minutes`) would otherwise be later than this `updatedAt`,
                // which `KeptRecord` rejects
                // (`updatedAt cannot be before keptAt`). Only `updatedAt`
                // participates in conflict-resolution ordering, so the
                // intended "remote is the older record" relationship is
                // unchanged.
                keptAt: t0,
                updatedAt: t0,
              ),
            ],
            syncState: matchingSyncState,
          );
      await bootstrapCoordinator.runBootstrap();
      final records = await keptRepository.loadAllRecords();
      expect(records.single.id, 'local-1');
      expect(records.single.updatedAt, t0.add(const Duration(days: 1)));
    });

    test(
        '27b. overlapping revealId -- newer remote record wins, physical '
        'localId preserved', () async {
      await seedLocalRecord(
        buildRecord(
          id: 'local-1',
          revealId: revealIdA,
          wisdomText: 'Same identity fields.',
          // `keptAt` pinned to `t0` (same instant as `updatedAt`) --
          // `buildRecord`'s default `keptAt` (`t0 + 5 minutes`) would
          // otherwise postdate this `updatedAt`, which `KeptRecord` rejects.
          // Only `updatedAt` drives conflict-resolution ordering, so this
          // local record remains the strictly-older side of the conflict.
          keptAt: t0,
          updatedAt: t0,
        ),
      );
      bridge.fetchProvider = (_) => successResult(
            records: [
              activeProjection(
                revealId: revealIdA,
                wisdomText: 'Same identity fields.',
                // `keptAt` pinned to the same instant as the local record's
                // `keptAt` above -- `resolveKeptWisdomConflict` requires
                // both sides of a genuine conflict to agree on every
                // immutable identity field (revealId/wisdomText/
                // revealedAtMs/keptAtMs); leaving this at
                // `activeProjection`'s (via `buildRecord`'s) default
                // `t0 + 5 minutes` would disagree with the local record's
                // `keptAt: t0` and make the resolver correctly reject the
                // pair as an `immutableFieldMismatch`, aborting the whole
                // baseline apply rather than exercising the intended
                // newer-remote-wins path.
                keptAt: t0,
                reflectionText: 'Newer remote reflection.',
                updatedAt: t0.add(const Duration(days: 1)),
              ),
            ],
            syncState: matchingSyncState,
          );
      await bootstrapCoordinator.runBootstrap();
      final records = await keptRepository.loadAllRecords();
      expect(records.single.id, 'local-1');
      expect(records.single.reflectionText, 'Newer remote reflection.');
    });

    test('28. remote tombstone removes a stale local record', () async {
      await seedLocalRecord(
        // `keptAt: t0` pinned alongside `updatedAt: t0` -- see test 27b's
        // identical rationale for why `buildRecord`'s default `keptAt`
        // cannot be used here.
        buildRecord(
          id: 'local-1',
          revealId: revealIdA,
          keptAt: t0,
          updatedAt: t0,
        ),
      );
      bridge.fetchProvider = (_) => successResult(
            records: [
              tombstoneProjection(
                revealId: revealIdA,
                updatedAt: t0.add(const Duration(days: 1)),
              ),
            ],
            syncState: matchingSyncState,
          );
      await bootstrapCoordinator.runBootstrap();
      final records = await keptRepository.loadAllRecords();
      expect(records, isEmpty);
    });

    test('29. newer local re-Keep beats a stale remote tombstone', () async {
      await seedLocalRecord(
        buildRecord(
          id: 'local-1',
          revealId: revealIdA,
          updatedAt: t0.add(const Duration(days: 1)),
        ),
      );
      bridge.fetchProvider = (_) => successResult(
            records: [
              tombstoneProjection(revealId: revealIdA, updatedAt: t0),
            ],
            syncState: matchingSyncState,
          );
      await bootstrapCoordinator.runBootstrap();
      final records = await keptRepository.loadAllRecords();
      expect(records, hasLength(1));
      expect(records.single.id, 'local-1');
    });

    test('30. no field-level Reflection merge -- winner is whole', () async {
      await seedLocalRecord(
        // `keptAt: t0` pinned alongside `updatedAt: t0` -- see test 27b's
        // identical rationale.
        buildRecord(
          id: 'local-1',
          revealId: revealIdA,
          reflectionText: 'Local reflection.',
          keptAt: t0,
          updatedAt: t0,
        ),
      );
      bridge.fetchProvider = (_) => successResult(
            records: [
              activeProjection(
                revealId: revealIdA,
                // `keptAt` pinned to the same instant as the local record's
                // `keptAt` above -- see the identical rationale on test
                // 27b's remote fixture: without this, `activeProjection`'s
                // default `keptAt` (`t0 + 5 minutes`) would disagree with
                // the local record's `keptAt: t0`, and
                // `resolveKeptWisdomConflict` would correctly reject the
                // pair as an `immutableFieldMismatch` (rather than
                // resolving on `updatedAt` as this test intends), aborting
                // the whole baseline apply and leaving the local record's
                // original `reflectionText` untouched.
                keptAt: t0,
                reflectionText: 'Remote reflection.',
                updatedAt: t0.add(const Duration(days: 1)),
              ),
            ],
            syncState: matchingSyncState,
          );
      await bootstrapCoordinator.runBootstrap();
      final records = await keptRepository.loadAllRecords();
      expect(records.single.reflectionText, 'Remote reflection.');
    });

    test('31. more than three remote Kept records are all preserved', () async {
      final revealIds = List.generate(
        5,
        (i) => 'aaaaaaa$i-1111-4111-8111-11111111111$i',
      );
      bridge.fetchProvider = (_) => successResult(
            records: [
              for (final id in revealIds) activeProjection(revealId: id),
            ],
            syncState: matchingSyncState,
          );
      await bootstrapCoordinator.runBootstrap();
      final records = await keptRepository.loadAllRecords();
      expect(records, hasLength(5));
    });

    test('32. more than three remote Reflections are all preserved', () async {
      final revealIds = List.generate(
        5,
        (i) => 'bbbbbbb$i-2222-4222-8222-22222222222$i',
      );
      bridge.fetchProvider = (_) => successResult(
            records: [
              for (final id in revealIds)
                activeProjection(
                    revealId: id, reflectionText: 'Reflection $id'),
            ],
            syncState: matchingSyncState,
          );
      await bootstrapCoordinator.runBootstrap();
      final records = await keptRepository.loadAllRecords();
      expect(records.every((r) => r.reflectionText != null), isTrue);
      expect(records, hasLength(5));
    });
  });

  group('33-41. legacy local backfill', () {
    setUp(() {
      // Backfill only runs once the account is already authorized -- seed
      // the marker so evaluateAssociation resolves to resumeAssociation
      // even though these tests deliberately pre-populate local Kept
      // history (H) before bootstrap ever runs.
      syncStore.seedAssociatedAccountFingerprint(fingerprintA);
    });

    test(
        '33/38/39. genuinely local-only physical record is backfilled, '
        'promoted, and its exact historical fields are preserved', () async {
      final record = buildRecord(
        id: 'legacy-1',
        revealId: revealIdA,
        wisdomText: 'A legacy kept wisdom.',
        reflectionText: 'A legacy reflection.',
        reflectedAt: t0.add(const Duration(minutes: 20)),
      );
      await seedLocalRecord(record);
      // `serverChangeToken` explicitly seeded -- a real
      // `remoteBaselinePending -> localReconciliationPending` transition
      // always carries a non-null token forward (`commitIncomingBatch
      // Checkpoint`'s `pendingServerChangeToken` is non-nullable); a bucket
      // fixture with no token cannot legitimately reach this state and
      // would (correctly) fail closed as `corruptedBucketState` instead of
      // exercising the promotion behavior this test targets.
      seedBucket(
        AccountBootstrapState.localReconciliationPending,
        serverChangeToken: 'dG9rZW4=',
      );

      final result = await bootstrapCoordinator.runBootstrap();
      expect(result.status, BootstrapRunStatus.completed);
      expect(result.backfilledIntentCount, 1);
      expect(result.promotedIntentCount, 1);

      // The intent must have been promoted, not left parked.
      expect(await intentStore.loadIntents(), isEmpty);

      final bucket = await syncStore.loadAccountState(fingerprintA);
      final mutation = bucket!.outbox.singleWhere(
        (m) => m.change.projection.revealId == revealIdA,
      );
      final projection = mutation.change.projection;
      expect(projection.wisdomText, record.wisdomText);
      expect(projection.revealedAtMs, record.revealedAt.millisecondsSinceEpoch);
      expect(projection.keptAtMs, record.keptAt.millisecondsSinceEpoch);
      expect(projection.reflectionText, record.reflectionText);
      expect(projection.mutationId, record.mutationId);
    });

    test(
        'a localReconciliationPending bucket with no serverChangeToken -- a '
        'shape this coordinator\'s own transitions can never produce -- '
        'fails closed as corruptedBucketState instead of crashing, with '
        'zero backfill, zero promotion, and zero checkpoint write', () async {
      final record = buildRecord(id: 'legacy-1', revealId: revealIdA);
      await seedLocalRecord(record);
      await intentStore.enqueueIntent(
        LocalSyncIntent(
          intentId: '00000000-0000-4000-8000-0000000000fe',
          kind: LocalSyncIntentKind.create,
          payload: LocalSyncIntentPayload.active(
            revealId: revealIdB,
            operation: LocalSyncIntentOperation.keep,
            wisdomText: 'Pending promotion.',
            revealedAtMs: t0.millisecondsSinceEpoch,
            keptAtMs: t0.millisecondsSinceEpoch,
            updatedAtMs: t0.millisecondsSinceEpoch,
            mutationId: mutationIdFor(revealIdB),
          ),
          stage: LocalSyncIntentStage.localCommittedOutboxPending,
          enqueuedAt: t0,
        ),
      );
      // Deliberately no `serverChangeToken` -- an impossible-in-practice
      // bucket a real `remoteBaselinePending -> localReconciliationPending`
      // transition could never produce, simulating externally-corrupted or
      // hand-edited persisted state.
      seedBucket(AccountBootstrapState.localReconciliationPending);

      final result = await bootstrapCoordinator.runBootstrap();
      expect(result.status, BootstrapRunStatus.corruptedBucketState);

      // Zero mutation of any kind: no backfill intent created, the
      // pre-existing pending intent left untouched (never promoted), and
      // the bucket's own bootstrapState/outbox unchanged.
      final intents = await intentStore.loadIntents();
      expect(intents, hasLength(1));
      expect(intents.single.recordName, deriveKeptWisdomRecordName(revealIdB));
      expect(
        intents.single.stage,
        LocalSyncIntentStage.localCommittedOutboxPending,
      );
      final bucket = await syncStore.loadAccountState(fingerprintA);
      expect(
        bucket!.bootstrapState,
        AccountBootstrapState.localReconciliationPending,
      );
      expect(bucket.outbox, isEmpty);
    });

    test(
        '34. a record already tracked by an existing intent is not backfilled '
        'a second time', () async {
      final record = buildRecord(id: 'legacy-1', revealId: revealIdA);
      await seedLocalRecord(record);
      await intentStore.enqueueIntent(
        LocalSyncIntent(
          intentId: '00000000-0000-4000-8000-000000000001',
          kind: LocalSyncIntentKind.create,
          payload: LocalSyncIntentPayload.active(
            revealId: revealIdA,
            operation: LocalSyncIntentOperation.keep,
            wisdomText: record.wisdomText,
            revealedAtMs: record.revealedAt.millisecondsSinceEpoch,
            keptAtMs: record.keptAt.millisecondsSinceEpoch,
            updatedAtMs: record.updatedAt.millisecondsSinceEpoch,
            mutationId: record.mutationId,
            localId: record.id,
          ),
          stage: LocalSyncIntentStage.pendingLocalApplication,
          enqueuedAt: t0,
        ),
      );
      // `serverChangeToken` explicitly seeded -- a real
      // `remoteBaselinePending -> localReconciliationPending` transition
      // always carries a non-null token forward (`commitIncomingBatch
      // Checkpoint`'s `pendingServerChangeToken` is non-nullable); a bucket
      // fixture with no token cannot legitimately reach this state and
      // would (correctly) fail closed as `corruptedBucketState` instead of
      // exercising the promotion behavior this test targets.
      seedBucket(
        AccountBootstrapState.localReconciliationPending,
        serverChangeToken: 'dG9rZW4=',
      );

      final result = await bootstrapCoordinator.runBootstrap();
      expect(result.status, BootstrapRunStatus.completed);
      expect(result.backfilledIntentCount, 0);
      // The pre-existing intent (never at localCommittedOutboxPending) is
      // left completely untouched -- never duplicated, never promoted.
      final remaining = await intentStore.loadIntents();
      expect(remaining, hasLength(1));
      expect(
          remaining.single.stage, LocalSyncIntentStage.pendingLocalApplication);
    });

    test(
        '35. a record already represented in recordSystemFields is not '
        'backfilled', () async {
      final record = buildRecord(id: 'legacy-1', revealId: revealIdA);
      await seedLocalRecord(record);
      seedBucket(
        AccountBootstrapState.localReconciliationPending,
        serverChangeToken: 'dG9rZW4=',
        recordSystemFields: {
          deriveKeptWisdomRecordName(revealIdA): systemFieldsFor(revealIdA),
        },
      );

      final result = await bootstrapCoordinator.runBootstrap();
      expect(result.status, BootstrapRunStatus.completed);
      expect(result.backfilledIntentCount, 0);
      expect(result.promotedIntentCount, 0);
    });

    test('36. both an existing intent and recordSystemFields -> skipped',
        () async {
      final record = buildRecord(id: 'legacy-1', revealId: revealIdA);
      await seedLocalRecord(record);
      await intentStore.enqueueIntent(
        LocalSyncIntent(
          intentId: '00000000-0000-4000-8000-000000000002',
          kind: LocalSyncIntentKind.create,
          payload: LocalSyncIntentPayload.active(
            revealId: revealIdA,
            operation: LocalSyncIntentOperation.keep,
            wisdomText: record.wisdomText,
            revealedAtMs: record.revealedAt.millisecondsSinceEpoch,
            keptAtMs: record.keptAt.millisecondsSinceEpoch,
            updatedAtMs: record.updatedAt.millisecondsSinceEpoch,
            mutationId: record.mutationId,
          ),
          stage: LocalSyncIntentStage.pendingLocalApplication,
          enqueuedAt: t0,
        ),
      );
      seedBucket(
        AccountBootstrapState.localReconciliationPending,
        serverChangeToken: 'dG9rZW4=',
        recordSystemFields: {
          deriveKeptWisdomRecordName(revealIdA): systemFieldsFor(revealIdA),
        },
      );
      final result = await bootstrapCoordinator.runBootstrap();
      expect(result.backfilledIntentCount, 0);
    });

    test(
        '37. a record just adopted from remote in this same run is never '
        'also backfilled', () async {
      syncStore.seedAssociatedAccountFingerprint(fingerprintA);
      bridge.fetchProvider = (_) => successResult(
            records: [activeProjection(revealId: revealIdA)],
            syncState: [
              CloudEastSyncStateProjection.current(
                dataEpoch: epoch,
                mutationId: mutationIdFor(revealIdA),
              ),
            ],
          );
      final result = await bootstrapCoordinator.runBootstrap();
      expect(result.status, BootstrapRunStatus.completed);
      final bucket = await syncStore.loadAccountState(fingerprintA);
      // Exactly the one adopted-from-remote record's revealId appears in the
      // outbox at most zero times (it was already applied directly to Kept,
      // never re-queued as a legacy backfill).
      expect(
        bucket!.outbox.where((m) => m.change.projection.revealId == revealIdA),
        isEmpty,
      );
    });

    test(
        'a remoteBaselinePending bucket with no serverChangeToken also '
        'fails closed as corruptedBucketState, symmetrically with the '
        'localReconciliationPending case', () async {
      seedBucket(AccountBootstrapState.remoteBaselinePending);
      final result = await bootstrapCoordinator.runBootstrap();
      expect(result.status, BootstrapRunStatus.corruptedBucketState);
      final bucket = await syncStore.loadAccountState(fingerprintA);
      expect(
          bucket!.bootstrapState, AccountBootstrapState.remoteBaselinePending);
      expect(bucket.outbox, isEmpty);
    });
  });

  group('42-49. local reconciliation promotion', () {
    setUp(() {
      syncStore.seedAssociatedAccountFingerprint(fingerprintA);
    });

    test(
        '42/46/48. every localCommittedOutboxPending intent is enqueued '
        'before complete is written', () async {
      final record = buildRecord(id: 'legacy-1', revealId: revealIdA);
      await seedLocalRecord(record);
      // `serverChangeToken` explicitly seeded -- a real
      // `remoteBaselinePending -> localReconciliationPending` transition
      // always carries a non-null token forward (`commitIncomingBatch
      // Checkpoint`'s `pendingServerChangeToken` is non-nullable); a bucket
      // fixture with no token cannot legitimately reach this state and
      // would (correctly) fail closed as `corruptedBucketState` instead of
      // exercising the promotion behavior this test targets.
      seedBucket(
        AccountBootstrapState.localReconciliationPending,
        serverChangeToken: 'dG9rZW4=',
      );

      final result = await bootstrapCoordinator.runBootstrap();
      expect(result.status, BootstrapRunStatus.completed);
      expect(await intentStore.loadIntents(), isEmpty);
      final bucket = await syncStore.loadAccountState(fingerprintA);
      expect(bucket!.bootstrapState, AccountBootstrapState.complete);
      expect(bucket.outbox, isNotEmpty);
    });

    test(
        '49. an ordinary user mutation that lands during the network fetch '
        'is incorporated into promotion', () async {
      syncStore.seedAssociatedAccountFingerprint(fingerprintA);
      // A non-empty remote (an existing CKEastSyncState already present) is
      // used here so this test stays scoped purely to the user-mutation-
      // during-fetch invariant -- the separate empty-remote create-and-
      // verify sequence has its own dedicated tests (19, 19b-19d, 22b) and
      // is unrelated behavior this test should not also exercise.
      bridge.fetchProvider = (_) => successResult(
            syncState: [
              CloudEastSyncStateProjection.current(
                dataEpoch: epoch,
                mutationId: mutationIdFor(revealIdA),
              ),
            ],
          );
      final holdFetch = Completer<void>();
      bridge.holdFetchUntil = holdFetch;

      final outgoingCoordinator = KeptSyncIntegrationCoordinator(
        keptRepository: keptRepository,
        intentStore: intentStore,
        syncPersistenceStore: syncStore,
        integrationCoordinator: sharedCoordinator,
      );

      final bootstrapFuture = bootstrapCoordinator.runBootstrap();
      await Future<void>.delayed(Duration.zero);
      expect(bridge.fetchPrivateZoneChangesCallCount, 1);

      // A real user mutation happens while the fetch is still in flight --
      // the integration lock must be free for this to complete.
      await outgoingCoordinator.recordKeep(
        revealId: revealIdB,
        wisdomText: 'Kept during the fetch window.',
        revealedAt: t0,
        isKeeper: false,
      );

      holdFetch.complete();
      final result = await bootstrapFuture;
      expect(result.status, BootstrapRunStatus.completed);

      final bucket = await syncStore.loadAccountState(fingerprintA);
      expect(
        bucket!.outbox.any((m) => m.change.projection.revealId == revealIdB),
        isTrue,
        reason: 'The mutation that landed during the fetch window must be '
            'promoted into the outbox before bootstrap completes.',
      );
      expect(await intentStore.loadIntents(), isEmpty);
    });
  });

  group('50-53. remote epoch fail-closed on an already-complete association',
      () {
    test('50. matching remote epoch -> alreadyComplete, no mutation', () async {
      seedBucket(AccountBootstrapState.complete, serverChangeToken: 'dG9rZW4=');
      syncStore.seedAssociatedAccountFingerprint(fingerprintA);
      final result = await bootstrapCoordinator.runBootstrap();
      expect(result.status, BootstrapRunStatus.alreadyComplete);
      expect(bridge.modifyPrivateRecordsCallCount, 0);
      expect(bridge.fetchSyncStateEpochCallCount, 1);
      expect(bridge.fetchPrivateZoneChangesCallCount, 0);
    });

    test(
        '51/52/53. different remote epoch -> remoteEpochChangedRecovery'
        'Required, zero mutation, no bootstrap transition', () async {
      seedBucket(AccountBootstrapState.complete, serverChangeToken: 'dG9rZW4=');
      syncStore.seedAssociatedAccountFingerprint(fingerprintA);
      bridge.syncStateEpochProvider = () => CloudKitSyncStateEpochResult.found(
            dataEpoch: otherEpoch,
            systemFields: systemFieldsFor(
              CloudEastSyncStateProjection.recordName,
            ),
          );
      final before = await syncStore.loadAccountState(fingerprintA);
      final result = await bootstrapCoordinator.runBootstrap();
      expect(
        result.status,
        BootstrapRunStatus.remoteEpochChangedRecoveryRequired,
      );
      final after = await syncStore.loadAccountState(fingerprintA);
      expect(after, before);
      expect(after!.bootstrapState, AccountBootstrapState.complete);
      expect(bridge.modifyPrivateRecordsCallCount, 0);
      expect(await keptRepository.loadAllRecords(), isEmpty);
    });

    test(
        'a missing remote control record fails closed as epoch recovery '
        'required without changing local Kept or checkpoint state', () async {
      seedBucket(AccountBootstrapState.complete, serverChangeToken: 'dG9rZW4=');
      syncStore.seedAssociatedAccountFingerprint(fingerprintA);
      bridge.syncStateEpochProvider = CloudKitSyncStateEpochResult.notFound;
      final before = await syncStore.loadAccountState(fingerprintA);

      final result = await bootstrapCoordinator.runBootstrap();

      expect(
        result.status,
        BootstrapRunStatus.remoteEpochChangedRecoveryRequired,
      );
      expect(await syncStore.loadAccountState(fingerprintA), before);
      expect(bridge.fetchPrivateZoneChangesCallCount, 0);
    });

    test('a malformed direct epoch result fails closed as fetchFailed',
        () async {
      seedBucket(AccountBootstrapState.complete, serverChangeToken: 'dG9rZW4=');
      syncStore.seedAssociatedAccountFingerprint(fingerprintA);
      bridge.syncStateEpochProvider = () =>
          CloudKitSyncStateEpochResult.tryParse(const {'outcome': 'future'});

      final result = await bootstrapCoordinator.runBootstrap();

      expect(result.status, BootstrapRunStatus.fetchFailed);
      expect(bridge.fetchPrivateZoneChangesCallCount, 0);
    });
  });

  group(
      '32. Build 26 Phase 5 (slice 2) compatibility: a stale device that '
      'already completed bootstrap under the old epoch continues to hit '
      'this existing remote-epoch-change fail-closed barrier once a Phase '
      '5 remote deletion runner has rotated CKEastSyncState.dataEpoch, '
      'rather than ever uploading its own stale local content. The Phase 5 '
      'deletion runner (lib/sync_deletion/cloud_kit_remote_deletion_runner'
      '.dart) establishes its replacement epoch via a plain '
      'modifyPrivateRecords save of CKEastSyncState -- wire-identical to '
      'any other sync-state save this coordinator already handles -- so '
      'this test asserts the existing check requires zero modification for '
      'Phase 5 to be safe: it is a pure `remoteEpoch != '
      'completeBucket.dataEpoch` comparison '
      '(_checkAlreadyCompleteForEpochChange), unrelated to how or why the '
      'remote epoch changed.', () {
    test(
        '32. remote epoch rotated by a Phase 5 deletion runner -> '
        'remoteEpochChangedRecoveryRequired, zero mutation, no local Kept '
        'upload -- this device never silently repopulates iCloud', () async {
      // This device (a stale "Device B") completed bootstrap under `epoch`
      // and has its own local Kept content. Its own AccountSyncState bucket
      // still records `epoch` as the last epoch it observed.
      seedBucket(AccountBootstrapState.complete, serverChangeToken: 'dG9rZW4=');
      syncStore.seedAssociatedAccountFingerprint(fingerprintA);
      await seedLocalRecord(buildRecord(id: 'k1', revealId: revealIdA));

      // Simulates "Device A" having already driven a Phase 5 remote
      // deletion transaction through CloudKitRemoteDeletionRunner's
      // epochBarrierPending stage: a fresh replacement epoch is now the
      // authoritative CKEastSyncState.dataEpoch remotely, generated exactly
      // once via the same DataEpoch.generate() factory the runner itself
      // uses -- this device (Device B) has not observed that rotation yet.
      final replacementEpochFromDeletionRunner = DataEpoch.generate();
      bridge.syncStateEpochProvider = () => CloudKitSyncStateEpochResult.found(
            dataEpoch: replacementEpochFromDeletionRunner,
            systemFields: systemFieldsFor(
              CloudEastSyncStateProjection.recordName,
            ),
          );

      final before = await syncStore.loadAccountState(fingerprintA);
      final result = await bootstrapCoordinator.runBootstrap();

      expect(
        result.status,
        BootstrapRunStatus.remoteEpochChangedRecoveryRequired,
        reason: 'the rotated epoch a Phase 5 deletion runner establishes is '
            'indistinguishable, to this existing check, from any other '
            'remote epoch change -- it must fail closed exactly the same '
            'way, never proceed as if nothing happened.',
      );
      final after = await syncStore.loadAccountState(fingerprintA);
      expect(after, before,
          reason: 'this device\'s own bucket/epoch/token must be completely '
              'untouched by discovering the rotation.');
      expect(after!.bootstrapState, AccountBootstrapState.complete);
      expect(bridge.modifyPrivateRecordsCallCount, 0,
          reason: 'zero mutation -- in particular, this stale device must '
              'never upload its own local Kept content under the old '
              'epoch, which is exactly what would silently repopulate the '
              'CKKeptWisdom records Phase 5 is in the middle of purging.');
    });
  });

  group(
      '55-57. Build 26 Phase 4H real-device regression: the resume-path '
      'direct epoch read (_checkAlreadyCompleteForEpochChange) fails '
      'closed to fetchFailed on a genuine transport failure -- never a '
      'crash, never a local mutation, never a bucket/token change. This is '
      'the exact call path a physical-device localMutation-triggered sync '
      'pass takes once bootstrap has ever reached AccountBootstrapState'
      '.complete: `resumeAssociation` -> this direct epoch check -> either '
      '`alreadyComplete`/`remoteEpochChangedRecoveryRequired` (both already '
      'covered above) or `fetchFailed` (previously uncovered by this suite '
      'entirely).', () {
    test(
        '55. the bridge throwing CloudKitPlatformException during the '
        'direct epoch read -> fetchFailed, zero mutation, bucket/token '
        'unchanged', () async {
      seedBucket(AccountBootstrapState.complete, serverChangeToken: 'dG9rZW4=');
      syncStore.seedAssociatedAccountFingerprint(fingerprintA);
      final before = await syncStore.loadAccountState(fingerprintA);
      bridge.syncStateEpochProvider =
          () => throw const CloudKitPlatformException('networkFailure');

      final result = await bootstrapCoordinator.runBootstrap();

      expect(result.status, BootstrapRunStatus.fetchFailed);
      expect(bridge.modifyPrivateRecordsCallCount, 0);
      final after = await syncStore.loadAccountState(fingerprintA);
      expect(after, before);
      expect(after!.bootstrapState, AccountBootstrapState.complete);
      expect(after.serverChangeToken, 'dG9rZW4=');
      expect(await keptRepository.loadAllRecords(), isEmpty);
    });

    test(
        '56. the bridge returning a non-throwing '
        'CloudKitSyncStateEpochOutcome.failure result during the direct '
        'epoch read -> fetchFailed, zero mutation, bucket/token unchanged -- '
        'proving this is not merely a thrown-exception-only path', () async {
      seedBucket(AccountBootstrapState.complete, serverChangeToken: 'dG9rZW4=');
      syncStore.seedAssociatedAccountFingerprint(fingerprintA);
      final before = await syncStore.loadAccountState(fingerprintA);
      bridge.syncStateEpochProvider =
          () => CloudKitSyncStateEpochResult.failure('zoneBusy');

      final result = await bootstrapCoordinator.runBootstrap();

      expect(result.status, BootstrapRunStatus.fetchFailed);
      expect(bridge.modifyPrivateRecordsCallCount, 0);
      final after = await syncStore.loadAccountState(fingerprintA);
      expect(after, before);
      expect(after!.bootstrapState, AccountBootstrapState.complete);
      expect(after.serverChangeToken, 'dG9rZW4=');
      expect(await keptRepository.loadAllRecords(), isEmpty);
    });

    test(
        '57. a retry after fetchFailed with a now-succeeding fetch resolves '
        'normally (alreadyComplete) -- the earlier failure left no durable '
        'state a subsequent success needs to work around', () async {
      seedBucket(AccountBootstrapState.complete, serverChangeToken: 'dG9rZW4=');
      syncStore.seedAssociatedAccountFingerprint(fingerprintA);
      bridge.syncStateEpochProvider =
          () => throw const CloudKitPlatformException('networkFailure');
      final firstAttempt = await bootstrapCoordinator.runBootstrap();
      expect(firstAttempt.status, BootstrapRunStatus.fetchFailed);

      bridge.syncStateEpochProvider = () => CloudKitSyncStateEpochResult.found(
            dataEpoch: epoch,
            systemFields: systemFieldsFor(
              CloudEastSyncStateProjection.recordName,
            ),
          );
      final retry = await bootstrapCoordinator.runBootstrap();

      expect(retry.status, BootstrapRunStatus.alreadyComplete);
      expect(bridge.modifyPrivateRecordsCallCount, 0);
    });
  });

  group('54. concurrency -- single-flight', () {
    test('two runBootstrap calls return the exact same in-flight Future',
        () async {
      final future1 = bootstrapCoordinator.runBootstrap();
      final future2 = bootstrapCoordinator.runBootstrap();
      expect(identical(future1, future2), isTrue);
      await future1;
    });
  });

  group('60-65. boundaries and privacy', () {
    test(
        '62. no AssociationEvaluation/BootstrapRunResult toLogSafeSummary '
        'ever contains a fingerprint-shaped value', () async {
      syncStore.seedAssociatedAccountFingerprint(fingerprintA);
      final evaluation = await bootstrapCoordinator.evaluateAssociation();
      final summary = evaluation.toLogSafeSummary().toString();
      expect(summary.contains(fingerprintA), isFalse);

      final runResult = await bootstrapCoordinator.runBootstrap();
      final runSummary = runResult.toLogSafeSummary().toString();
      expect(runSummary.contains(fingerprintA), isFalse);
    });

    test(
        '64. AssociationAuthorizationResult/LegacyAssociationRepairResult '
        'never render a fingerprint', () async {
      final authResult = await bootstrapCoordinator.authorizeAssociation(
        fingerprint: fingerprintA,
      );
      expect(authResult.toString().contains(fingerprintA), isFalse);

      seedBucket(
        AccountBootstrapState.remoteBaselinePending,
        fingerprint: fingerprintB,
      );
      final repairResult =
          await bootstrapCoordinator.repairLegacyAssociationMarker(
        expectedCandidateFingerprint: fingerprintB,
      );
      expect(repairResult.toString().contains(fingerprintB), isFalse);
    });
  });

  // -------------------------------------------------------------------
  // Phase 4G real-device timestamp-canonicalization regression: the
  // independent mirror `_toSyncChangeIndependentMirror` (used only by
  // `_promotePendingIntents`, itself only reachable from the real
  // `runBootstrap()` pipeline) constructed every persisted `SyncChange`
  // with a raw `enqueuedAt: _clock()` -- never canonicalized -- even
  // though the sibling `KeptSyncIntegrationCoordinator._toSyncChange` was
  // already fixed. On a real device, `_clock()` (`DateTime.now()`)
  // routinely carries a non-zero microsecond remainder;
  // `PersistedOutboxMutation.encode()`/`tryDecode` round-trip only
  // millisecond precision, while `PersistedOutboxMutation.operator==`
  // compares `enqueuedAt` with `DateTime.isAtSameMomentAs` (exact to the
  // microsecond) -- exactly the bug class already proven and fixed for
  // `LocalSyncIntent.enqueuedAt` and for the other `SyncChange`
  // construction sites in `kept_sync_integration_coordinator.dart`. This
  // silently starved every real-device bootstrap-time outbox promotion,
  // which is why CloudKit never observed an uploaded `CKKeptWisdom`
  // record despite a successful local Keep. These tests exercise the
  // REAL `ProtectedSyncPersistenceStore` (only the native
  // `FileProtectionBridge` is faked) through the real, unmodified
  // `KeptSyncBootstrapCoordinator.runBootstrap()` call graph -- never a
  // copied/reimplemented helper.
  // -------------------------------------------------------------------
  group('Phase 4G bootstrap timestamp canonicalization (real-device fix)', () {
    late Directory tempRoot;
    late ProtectedSyncPersistenceStore realSyncStore;
    late ProtectedLocalSyncIntentStore realIntentStore;

    setUp(() {
      tempRoot = Directory.systemTemp
          .createTempSync('kept_sync_bootstrap_real_store_test_');
      realSyncStore = ProtectedSyncPersistenceStore(
        rootDirectoryProvider: () async => tempRoot,
        fileProtectionBridge: const _AlwaysSucceedsFileProtectionBridge(),
      );
      realIntentStore = ProtectedLocalSyncIntentStore(
        rootDirectoryProvider: () async => tempRoot,
        fileProtectionBridge: const _AlwaysSucceedsFileProtectionBridge(),
      );
    });

    tearDown(() {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    });

    /// Builds a coordinator wired to the REAL [realSyncStore] (never the
    /// outer `setUp`'s in-memory `syncStore`), the outer `keptRepository`/
    /// `intentStore`/`bridge`, and [clock] as the coordinator's own
    /// injected clock -- the exact value `_toSyncChangeIndependentMirror`'s
    /// `enqueuedAt: canonicalizeKeptTimestamp(_clock())` now reads from.
    KeptSyncBootstrapCoordinator buildRealStoreCoordinator({
      required DateTime Function() clock,
    }) {
      return KeptSyncBootstrapCoordinator(
        bridge: bridge,
        keptRepository: keptRepository,
        intentStore: intentStore,
        syncPersistenceStore: realSyncStore,
        integrationCoordinator: sharedCoordinator,
        idFactory: _sequentialIdFactory(),
        clock: clock,
      );
    }

    /// Builds a coordinator wired to BOTH real stores -- [realSyncStore]
    /// AND a real [ProtectedLocalSyncIntentStore] wrapped in
    /// [_RecordingLocalSyncIntentStore] so the test can inspect exactly what
    /// `_backfillLegacyLocalOnlyRecords` handed to `enqueueIntent` (a real
    /// delegate call: if the real store's own strict post-write
    /// verification ever threw, this call -- and therefore the whole
    /// `runBootstrap()` pipeline -- would throw too).
    KeptSyncBootstrapCoordinator buildFullyRealStoresCoordinator({
      required DateTime Function() clock,
      required _RecordingLocalSyncIntentStore recordingIntentStore,
    }) {
      return KeptSyncBootstrapCoordinator(
        bridge: bridge,
        keptRepository: keptRepository,
        intentStore: recordingIntentStore,
        syncPersistenceStore: realSyncStore,
        integrationCoordinator: sharedCoordinator,
        idFactory: _sequentialIdFactory(),
        clock: clock,
      );
    }

    /// Configures [bridge] for the exact "genuinely empty remote, first
    /// association" branch: the initial baseline fetch reports zero
    /// records of any kind, the one-time `CKEastSyncState` upload
    /// succeeds, and the mandatory post-upload verification re-fetch
    /// reports back exactly the uploaded control record -- mirroring
    /// test 19's own established pattern above.
    void configureEmptyRemoteFirstAssociation() {
      var fetchCallCount = 0;
      bridge.fetchProvider = (request) {
        fetchCallCount += 1;
        if (fetchCallCount == 1) return successResult();
        final uploaded = CloudEastSyncStateWireEnvelope.tryDecode(
          bridge.modifyRequests.single.records.single.fields,
        )!;
        return successResult(
          syncState: [uploaded],
          serverToken: 'cG9zdHVwbG9hZA==',
        );
      };
    }

    final microsecondClock = DateTime.utc(2026, 8, 9, 12, 0, 0, 123, 456);
    final expectedCanonicalEnqueuedAt =
        canonicalizeKeptTimestamp(microsecondClock);

    test(
        'A. a microsecond-precision injected clock is canonicalized before '
        'the independent mirror constructs the persisted SyncChange during '
        '_promotePendingIntents', () async {
      configureEmptyRemoteFirstAssociation();
      await seedLocalRecord(
        KeptRecord(
          id: 'local-only-1',
          revealId: revealIdA,
          wisdomText: 'Be still.',
          revealedAt: t0,
          keptAt: t0,
          updatedAt: t0,
          mutationId: mutationIdFor(revealIdA),
        ),
      );
      final coordinator =
          buildRealStoreCoordinator(clock: () => microsecondClock);

      // Existing non-empty local Kept history means `evaluateAssociation()`
      // returns `associationRequired`, never `autoAssociable` -- an explicit
      // authorization is required before `runBootstrap()` will proceed at
      // all, exactly like a real user-driven "associate my existing local
      // history with this iCloud account" decision.
      final authorization =
          await coordinator.authorizeAssociation(fingerprint: fingerprintA);
      expect(authorization.isAuthorized, isTrue);

      final result = await coordinator.runBootstrap();

      expect(result.status, BootstrapRunStatus.completed);
      expect(result.backfilledIntentCount, 1);
      expect(result.promotedIntentCount, 1);
      final bucket = await realSyncStore.loadAccountState(fingerprintA);
      final enqueuedAt = bucket!.outbox.single.change.enqueuedAt;
      expect(enqueuedAt.microsecond, 0);
      expect(enqueuedAt, expectedCanonicalEnqueuedAt);
    });

    test(
        'B. the promoted mutation survives the REAL '
        'ProtectedSyncPersistenceStore encode -> write -> protect -> '
        'verify -> rename -> protect -> verify round trip without a '
        'replace-verify-temp/replace-verify-final mismatch, and a fresh '
        'independent reload still reports the millisecond-canonical '
        'instant', () async {
      configureEmptyRemoteFirstAssociation();
      await seedLocalRecord(
        KeptRecord(
          id: 'local-only-1',
          revealId: revealIdA,
          wisdomText: 'Be still.',
          revealedAt: t0,
          keptAt: t0,
          updatedAt: t0,
          mutationId: mutationIdFor(revealIdA),
        ),
      );
      final coordinator =
          buildRealStoreCoordinator(clock: () => microsecondClock);
      final authorization =
          await coordinator.authorizeAssociation(fingerprint: fingerprintA);
      expect(authorization.isAuthorized, isTrue);

      // Must not throw: before this fix, this call's real-device shape
      // (`_promotePendingIntents` -> `enqueueMutation` -> `_replaceEnvelope`)
      // threw `SyncPersistenceStoreException('replace-verify-temp', ...)`.
      final result = await coordinator.runBootstrap();
      expect(result.status, BootstrapRunStatus.completed);

      // A second, fully independent load (a fresh read-back of the
      // already-committed final file) reports the exact same
      // millisecond-canonical instant -- not a one-shot artifact of the
      // write path.
      final reloaded = await realSyncStore.loadAccountState(fingerprintA);
      expect(
        reloaded!.outbox.single.change.enqueuedAt,
        DateTime.utc(2026, 8, 9, 12, 0, 0, 123),
      );
      expect(reloaded.outbox.single.change.enqueuedAt.microsecond, 0);
    });

    test(
        'C. existing non-empty local Kept + first CloudKit association + '
        'empty remote baseline -> local Kept remains present, and the '
        'record is successfully promoted into the outbox instead of being '
        'silently parked forever', () async {
      configureEmptyRemoteFirstAssociation();
      final localRecord = KeptRecord(
        id: 'local-only-1',
        revealId: revealIdA,
        wisdomText: 'Be still.',
        revealedAt: t0,
        keptAt: t0,
        updatedAt: t0,
        mutationId: mutationIdFor(revealIdA),
      );
      await seedLocalRecord(localRecord);
      final coordinator =
          buildRealStoreCoordinator(clock: () => microsecondClock);
      final authorization =
          await coordinator.authorizeAssociation(fingerprint: fingerprintA);
      expect(authorization.isAuthorized, isTrue);

      final result = await coordinator.runBootstrap();

      expect(result.status, BootstrapRunStatus.completed);

      // Local Kept content remains present -- never erased by the empty
      // remote baseline.
      final localAfter = await keptRepository.loadAllRecords();
      expect(localAfter, hasLength(1));
      expect(localAfter.single.revealId, revealIdA);
      expect(localAfter.single.wisdomText, 'Be still.');

      // No LocalSyncIntent is left permanently parked -- the backfilled
      // intent was successfully promoted and retired, not silently
      // stranded at localCommittedOutboxPending forever (this is exactly
      // the pre-fix real-device symptom: a swallowed
      // SyncPersistenceStoreException left the intent parked every single
      // bootstrap attempt, forever).
      expect(await intentStore.loadIntents(), isEmpty);

      // The record was genuinely promoted into the durable outbox --
      // never silently dropped -- ready for a future SyncOrchestrator
      // pass to actually upload it.
      final bucket = await realSyncStore.loadAccountState(fingerprintA);
      expect(bucket!.outbox, hasLength(1));
      expect(bucket.outbox.single.change.projection.revealId, revealIdA);
      expect(bucket.bootstrapState, AccountBootstrapState.complete);
    });

    // ---------------------------------------------------------------------
    // Third confirmed defect: `_backfillLegacyLocalOnlyRecords` (the only
    // other persisted-timestamp construction site in this file) also
    // constructed its `LocalSyncIntent` with a raw, uncanonicalized
    // `enqueuedAt: _clock()`. This is reachable in the exact same
    // real-device bootstrap pipeline as A/B/C above, whenever a genuinely
    // local-only Kept record needs backfilling into a fresh intent. These
    // four tests exercise the REAL `ProtectedLocalSyncIntentStore` (only its
    // native `FileProtectionBridge` is faked) through the unmodified
    // `runBootstrap()` call graph -- never a copied/reimplemented helper.
    // ---------------------------------------------------------------------
    test(
        '1-2. _backfillLegacyLocalOnlyRecords receives the microsecond-'
        'bearing injected clock and the LocalSyncIntent it durably enqueues '
        'is millisecond-canonical', () async {
      configureEmptyRemoteFirstAssociation();
      await seedLocalRecord(
        KeptRecord(
          id: 'local-only-1',
          revealId: revealIdA,
          wisdomText: 'Be still.',
          revealedAt: t0,
          keptAt: t0,
          updatedAt: t0,
          mutationId: mutationIdFor(revealIdA),
        ),
      );
      final recordingIntentStore =
          _RecordingLocalSyncIntentStore(realIntentStore);
      final coordinator = buildFullyRealStoresCoordinator(
        clock: () => microsecondClock,
        recordingIntentStore: recordingIntentStore,
      );
      final authorization =
          await coordinator.authorizeAssociation(fingerprint: fingerprintA);
      expect(authorization.isAuthorized, isTrue);

      final result = await coordinator.runBootstrap();

      expect(result.status, BootstrapRunStatus.completed);
      expect(result.backfilledIntentCount, 1);
      // Exactly one LocalSyncIntent was ever durably enqueued this run --
      // the one backfilled from the local-only record. Its `enqueuedAt` is
      // the real clock value the coordinator's own `_clock()` produced,
      // canonicalized before construction.
      expect(recordingIntentStore.enqueuedIntents, hasLength(1));
      final backfilled = recordingIntentStore.enqueuedIntents.single;
      expect(backfilled.payload.revealId, revealIdA);
      expect(backfilled.enqueuedAt.microsecond, 0);
      expect(backfilled.enqueuedAt, expectedCanonicalEnqueuedAt);
    });

    test(
        '3. the backfilled LocalSyncIntent survives the REAL '
        'ProtectedLocalSyncIntentStore encode -> write -> protect -> '
        'verify -> rename -> protect -> verify round trip without a '
        'replace-verify-temp/replace-verify-final mismatch', () async {
      configureEmptyRemoteFirstAssociation();
      await seedLocalRecord(
        KeptRecord(
          id: 'local-only-1',
          revealId: revealIdA,
          wisdomText: 'Be still.',
          revealedAt: t0,
          keptAt: t0,
          updatedAt: t0,
          mutationId: mutationIdFor(revealIdA),
        ),
      );
      final recordingIntentStore =
          _RecordingLocalSyncIntentStore(realIntentStore);
      final coordinator = buildFullyRealStoresCoordinator(
        clock: () => microsecondClock,
        recordingIntentStore: recordingIntentStore,
      );
      final authorization =
          await coordinator.authorizeAssociation(fingerprint: fingerprintA);
      expect(authorization.isAuthorized, isTrue);

      // Must not throw: before this fix, the real store's own
      // `_promotePendingIntents`-preceding backfill write would have hit
      // `LocalSyncIntentStoreException('replace-verify-temp', ...)` on a
      // real device (microsecond-bearing `_clock()` value, millisecond-only
      // wire format, exact-to-the-microsecond `operator==`).
      final result = await coordinator.runBootstrap();
      expect(result.status, BootstrapRunStatus.completed);

      // A second, fully independent load directly against the real store
      // (never through the recording wrapper) confirms the durable file
      // itself, not merely an in-memory artifact of the write path, is
      // consistent -- by this point the intent has already been promoted
      // and retired, so the authoritative state is "no pending intents".
      expect(await realIntentStore.loadIntents(), isEmpty);
    });

    test(
        '4. existing local-only Kept + empty remote baseline: the Kept '
        'record is preserved, the intent is backfilled and promoted into '
        'the durable outbox, and it is never left permanently parked',
        () async {
      configureEmptyRemoteFirstAssociation();
      final localRecord = KeptRecord(
        id: 'local-only-1',
        revealId: revealIdA,
        wisdomText: 'Be still.',
        revealedAt: t0,
        keptAt: t0,
        updatedAt: t0,
        mutationId: mutationIdFor(revealIdA),
      );
      await seedLocalRecord(localRecord);
      final recordingIntentStore =
          _RecordingLocalSyncIntentStore(realIntentStore);
      final coordinator = buildFullyRealStoresCoordinator(
        clock: () => microsecondClock,
        recordingIntentStore: recordingIntentStore,
      );
      final authorization =
          await coordinator.authorizeAssociation(fingerprint: fingerprintA);
      expect(authorization.isAuthorized, isTrue);

      final result = await coordinator.runBootstrap();

      expect(result.status, BootstrapRunStatus.completed);
      expect(result.backfilledIntentCount, 1);
      expect(result.promotedIntentCount, 1);

      // Preserves the Kept record.
      final localAfter = await keptRepository.loadAllRecords();
      expect(localAfter, hasLength(1));
      expect(localAfter.single.revealId, revealIdA);

      // Backfills the intent then promotes it -- never left permanently
      // parked at localCommittedOutboxPending (the pre-fix real-device
      // symptom: a swallowed exception during backfill's own enqueue left
      // the record un-backfilled and un-promoted, silently, forever).
      expect(await realIntentStore.loadIntents(), isEmpty);

      // Promotes it to the durable outbox.
      final bucket = await realSyncStore.loadAccountState(fingerprintA);
      expect(bucket!.outbox, hasLength(1));
      expect(bucket.outbox.single.change.projection.revealId, revealIdA);
      expect(bucket.bootstrapState, AccountBootstrapState.complete);
    });
  });
}

/// Wraps a real [LocalSyncIntentStore] (in every test above,
/// [ProtectedLocalSyncIntentStore]), delegating every call unchanged, while
/// also recording every [LocalSyncIntent] ever passed to [enqueueIntent] --
/// this is the only seam that lets a test observe the exact in-memory value
/// `_backfillLegacyLocalOnlyRecords` constructed, since a successfully
/// promoted intent is removed from the store before `runBootstrap()`
/// returns. Because every call is a real delegate call to the real store,
/// any real-store verification failure still throws exactly as it would
/// without this wrapper -- this class adds observation only, never changes
/// behavior.
class _RecordingLocalSyncIntentStore implements LocalSyncIntentStore {
  _RecordingLocalSyncIntentStore(this._delegate);

  final LocalSyncIntentStore _delegate;
  final List<LocalSyncIntent> enqueuedIntents = [];

  @override
  Future<List<LocalSyncIntent>> loadIntents() => _delegate.loadIntents();

  @override
  Future<void> enqueueIntent(LocalSyncIntent intent) async {
    await _delegate.enqueueIntent(intent);
    enqueuedIntents.add(intent);
  }

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

/// A [FileProtectionBridge] fake that always reports success -- used only by
/// the real-[ProtectedSyncPersistenceStore] regression group above, which is
/// not exercising file-protection failure/rollback behavior (already
/// thoroughly covered by `protected_sync_persistence_store_test.dart`) and
/// needs no failure-injection surface.
class _AlwaysSucceedsFileProtectionBridge implements FileProtectionBridge {
  const _AlwaysSucceedsFileProtectionBridge();

  @override
  Future<void> protectAndVerifyComplete(String path) async {}
}

/// Deterministic, collision-free id sequence for tests that need
/// [KeptSyncBootstrapCoordinator]'s injected `idFactory` to be predictable
/// (e.g. asserting an exact intentId), while still producing canonical UUID
/// v4-shaped strings (required by every constructor this factory feeds).
String Function() _sequentialIdFactory() {
  var counter = 0;
  return () {
    counter += 1;
    final suffix = counter.toRadixString(16).padLeft(12, '0');
    return '00000000-0000-4000-8000-$suffix';
  };
}
