// Build 26 Phase 4D-2: SyncOrchestrator -- the isolated CloudKit sync
// orchestrator connecting the Phase 4A sync domain, Phase 4C transport, and
// Phase 4D-1 persistence, entirely through injected abstractions. Synthetic
// content only.
//
// The persistence side uses the real `ProtectedSyncPersistenceStore` (with
// a fake `FileProtectionBridge` and a temp directory) rather than a
// hand-rolled parallel in-memory model, so this suite exercises the exact,
// already-reviewed supersession/epoch/acknowledgment rules Phase 4D-1
// implements -- never a second, competing persistence model. The transport
// side uses a small fake `CloudKitPlatformBridge` -- no real MethodChannel
// or CloudKit container is used anywhere in this file.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/persistence/file_protection_bridge.dart';
import 'package:wisdom_app/sync/cloud_kept_wisdom_projection.dart';
import 'package:wisdom_app/sync/data_epoch.dart';
import 'package:wisdom_app/sync/sync_change.dart';
import 'package:wisdom_app/sync/sync_error_classification.dart';
import 'package:wisdom_app/sync/sync_tombstone.dart';
import 'package:wisdom_app/sync_orchestration/pending_incoming_sync_batch.dart';
import 'package:wisdom_app/sync_orchestration/sync_orchestrator.dart';
import 'package:wisdom_app/sync_orchestration/sync_pass_result.dart';
import 'package:wisdom_app/sync_persistence/account_sync_state.dart';
import 'package:wisdom_app/sync_persistence/associated_account_fingerprint_commit.dart';
import 'package:wisdom_app/sync_persistence/incoming_batch_checkpoint.dart';
import 'package:wisdom_app/sync_persistence/outbox_mutation_retirement.dart';
import 'package:wisdom_app/sync_persistence/persisted_outbox_mutation.dart';
import 'package:wisdom_app/sync_persistence/protected_sync_persistence_store.dart';
import 'package:wisdom_app/sync_persistence/sync_persistence_store.dart';
import 'package:wisdom_app/sync_platform/cloud_kept_wisdom_wire_envelope.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_account_snapshot.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_bridge_info.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_account_change_event.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_modify_records_contract.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_platform_bridge.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_zone_changes_contract.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_zone_configuration_result.dart';

/// Fake [FileProtectionBridge] -- identical in shape/intent to the one
/// already used throughout `test/sync_persistence/protected_sync_persistence_store_test.dart`.
class _FakeFileProtectionBridge implements FileProtectionBridge {
  final List<String> protectedPaths = [];
  final Map<String, int> _remainingFailures = {};

  void failNextTimeFor(String path, {int times = 1}) {
    _remainingFailures[path] = (_remainingFailures[path] ?? 0) + times;
  }

  @override
  Future<void> protectAndVerifyComplete(String path) async {
    protectedPaths.add(path);
    final remaining = _remainingFailures[path];
    if (remaining != null && remaining > 0) {
      _remainingFailures[path] = remaining - 1;
      throw const FileProtectionException('Simulated protection failure.');
    }
  }
}

/// Fake [CloudKitPlatformBridge] -- no real MethodChannel or CloudKit
/// container anywhere in this file. Records call order and concurrency so
/// tests can assert on both.
class _FakeCloudKitPlatformBridge implements CloudKitPlatformBridge {
  List<CloudKitAccountSnapshot>? accountSnapshotSequence;
  int _snapshotIndex = 0;
  CloudKitZoneConfigurationResult Function()? zoneConfigurationProvider;
  CloudKitModifyRecordsResult Function(CloudKitModifyRecordsRequest)?
      modifyProvider;
  CloudKitZoneChangesResult Function(CloudKitZoneChangesRequest)? fetchProvider;
  Future<void> Function(CloudKitModifyRecordsRequest)? onModify;

  final List<String> callOrder = [];
  int getAccountSnapshotCallCount = 0;
  int configurePrivateZoneCallCount = 0;
  int modifyPrivateRecordsCallCount = 0;
  int fetchPrivateZoneChangesCallCount = 0;
  final List<CloudKitModifyRecordsRequest> modifyRequests = [];
  final List<CloudKitZoneChangesRequest> fetchRequests = [];

  int _activeTransportCalls = 0;
  int maxConcurrentTransportCalls = 0;

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
      throw UnimplementedError('Not used by SyncOrchestrator.');

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
    _activeTransportCalls += 1;
    if (_activeTransportCalls > maxConcurrentTransportCalls) {
      maxConcurrentTransportCalls = _activeTransportCalls;
    }
    if (onModify != null) {
      await onModify!.call(request);
    }
    await Future<void>.delayed(Duration.zero);
    _activeTransportCalls -= 1;
    return modifyProvider!.call(request);
  }

  @override
  Future<CloudKitZoneChangesResult> fetchPrivateZoneChanges(
    CloudKitZoneChangesRequest request,
  ) async {
    fetchPrivateZoneChangesCallCount += 1;
    fetchRequests.add(request);
    callOrder.add('fetchPrivateZoneChanges');
    _activeTransportCalls += 1;
    if (_activeTransportCalls > maxConcurrentTransportCalls) {
      maxConcurrentTransportCalls = _activeTransportCalls;
    }
    await Future<void>.delayed(Duration.zero);
    _activeTransportCalls -= 1;
    return fetchProvider!.call(request);
  }
}

/// Wraps a real [SyncPersistenceStore] (typically a real
/// `ProtectedSyncPersistenceStore`) to record exact per-method call counts
/// and call order, and to optionally inject a synthetic failure into one
/// specific method -- without reimplementing any persistence semantics of
/// its own. Used to prove call-order and failure-injection requirements
/// (system fields persisted before acknowledgment; a failure at either step
/// stops the pass before any fetch) precisely, rather than only inferring
/// them from a file-protection-bridge failure whose exact internal timing
/// this test suite does not otherwise assert on.
class _RecordingSyncPersistenceStore implements SyncPersistenceStore {
  _RecordingSyncPersistenceStore(this._delegate);

  final SyncPersistenceStore _delegate;
  final List<String> callOrder = [];

  int loadAccountStateCallCount = 0;
  int replaceAccountStateCallCount = 0;
  int enqueueMutationCallCount = 0;
  int applyMutationOutcomesCallCount = 0;
  int readPendingMutationsCallCount = 0;
  int replaceRecordSystemFieldsCallCount = 0;
  int storeServerChangeTokenCallCount = 0;
  int clearServerChangeTokenCallCount = 0;
  int clearAccountStateCallCount = 0;
  int quarantineAccountStateCallCount = 0;

  /// Build 26 Phase 4E-4: the new associated-account-marker persistence
  /// surface is owned by `KeptSyncBootstrapCoordinator` alone --
  /// `SyncOrchestrator` (Phase 4D-2) never calls it and never legitimately
  /// could. Mirrors the existing `commitIncomingBatchCheckpoint`/
  /// `retireOutboxMutationIfCurrent` fail-loud precedent immediately above:
  /// any call here is itself the test failure.
  int loadAssociatedAccountFingerprintCallCount = 0;
  int commitAssociatedAccountFingerprintCallCount = 0;
  int loadMeaningfulAccountFingerprintsCallCount = 0;

  /// Build 26 Phase 4E-1: `SyncOrchestrator` is Phase 4D-2 -- it must never
  /// call the Phase 4E incoming-checkpoint API (that is Phase 4E-3's own,
  /// separate responsibility once it exists). This fake therefore never
  /// forwards to a real implementation: any call is itself the test
  /// failure, so it records the call and then fails immediately with a
  /// static, content-safe `StateError` rather than fabricating a
  /// successful checkpoint result.
  int commitIncomingBatchCheckpointCallCount = 0;

  /// Build 26 Phase 4E-3b: `retireOutboxMutationIfCurrent` is the incoming-
  /// apply loser-cleanup API `IncomingKeptSyncCoordinator` alone owns --
  /// exactly like `commitIncomingBatchCheckpoint` immediately above,
  /// `SyncOrchestrator` (Phase 4D-2) never calls it and never legitimately
  /// could (production confirms no `lib/sync_orchestration/` file references
  /// it). This fake mirrors that same fail-loud precedent rather than
  /// forwarding to `_delegate`: any call here is itself the test failure,
  /// so it records the call and then fails immediately with a static,
  /// content-safe `StateError` rather than fabricating a successful
  /// retirement result.
  int retireOutboxMutationIfCurrentCallCount = 0;

  /// When non-null, the *next* call to `replaceRecordSystemFields` throws
  /// this and is not forwarded to the delegate.
  Object? throwOnNextReplaceRecordSystemFields;

  /// When non-null, the *next* call to `applyMutationOutcomes` throws this
  /// and is not forwarded to the delegate.
  Object? throwOnNextApplyMutationOutcomes;

  @override
  Future<AccountSyncState?> loadAccountState(String accountFingerprint) {
    loadAccountStateCallCount += 1;
    callOrder.add('loadAccountState');
    return _delegate.loadAccountState(accountFingerprint);
  }

  @override
  Future<void> replaceAccountState(
    String accountFingerprint,
    AccountSyncState state,
  ) {
    replaceAccountStateCallCount += 1;
    callOrder.add('replaceAccountState');
    return _delegate.replaceAccountState(accountFingerprint, state);
  }

  @override
  Future<void> enqueueMutation(String accountFingerprint, SyncChange change) {
    enqueueMutationCallCount += 1;
    callOrder.add('enqueueMutation');
    return _delegate.enqueueMutation(accountFingerprint, change);
  }

  @override
  Future<void> applyMutationOutcomes(
    String accountFingerprint, {
    Set<String> acknowledgedMutationIds = const {},
    Map<String, PersistedOutboxMutationStatus> updatedStatusByMutationId =
        const {},
  }) async {
    applyMutationOutcomesCallCount += 1;
    callOrder.add('applyMutationOutcomes');
    final failure = throwOnNextApplyMutationOutcomes;
    if (failure != null) {
      throwOnNextApplyMutationOutcomes = null;
      throw failure;
    }
    return _delegate.applyMutationOutcomes(
      accountFingerprint,
      acknowledgedMutationIds: acknowledgedMutationIds,
      updatedStatusByMutationId: updatedStatusByMutationId,
    );
  }

  @override
  Future<List<PersistedOutboxMutation>> readPendingMutations(
    String accountFingerprint,
  ) {
    readPendingMutationsCallCount += 1;
    callOrder.add('readPendingMutations');
    return _delegate.readPendingMutations(accountFingerprint);
  }

  @override
  Future<void> replaceRecordSystemFields(
    String accountFingerprint,
    String recordName,
    String systemFields,
  ) async {
    replaceRecordSystemFieldsCallCount += 1;
    callOrder.add('replaceRecordSystemFields');
    final failure = throwOnNextReplaceRecordSystemFields;
    if (failure != null) {
      throwOnNextReplaceRecordSystemFields = null;
      throw failure;
    }
    return _delegate.replaceRecordSystemFields(
      accountFingerprint,
      recordName,
      systemFields,
    );
  }

  @override
  Future<void> storeServerChangeToken(
    String accountFingerprint,
    String serverToken,
  ) {
    storeServerChangeTokenCallCount += 1;
    callOrder.add('storeServerChangeToken');
    return _delegate.storeServerChangeToken(accountFingerprint, serverToken);
  }

  @override
  Future<void> clearServerChangeToken(String accountFingerprint) {
    clearServerChangeTokenCallCount += 1;
    callOrder.add('clearServerChangeToken');
    return _delegate.clearServerChangeToken(accountFingerprint);
  }

  @override
  Future<void> clearAccountState(String accountFingerprint) {
    clearAccountStateCallCount += 1;
    callOrder.add('clearAccountState');
    return _delegate.clearAccountState(accountFingerprint);
  }

  @override
  Future<void> quarantineAccountState(String accountFingerprint) {
    quarantineAccountStateCallCount += 1;
    callOrder.add('quarantineAccountState');
    return _delegate.quarantineAccountState(accountFingerprint);
  }

  @override
  Future<CommitIncomingBatchCheckpointResult> commitIncomingBatchCheckpoint(
    CommitIncomingBatchCheckpointRequest request,
  ) async {
    commitIncomingBatchCheckpointCallCount += 1;
    callOrder.add('commitIncomingBatchCheckpoint');
    throw StateError(
      'Incoming checkpoint must not be called by SyncOrchestrator.',
    );
  }

  @override
  Future<RetireOutboxMutationResult> retireOutboxMutationIfCurrent(
    RetireOutboxMutationRequest request,
  ) async {
    retireOutboxMutationIfCurrentCallCount += 1;
    callOrder.add('retireOutboxMutationIfCurrent');
    throw StateError(
      'Outbox mutation retirement must not be called by SyncOrchestrator.',
    );
  }

  @override
  Future<String?> loadAssociatedAccountFingerprint() async {
    loadAssociatedAccountFingerprintCallCount += 1;
    callOrder.add('loadAssociatedAccountFingerprint');
    throw StateError(
      'Associated-account-fingerprint read must not be called by '
      'SyncOrchestrator.',
    );
  }

  @override
  Future<CommitAssociatedAccountFingerprintResult>
      commitAssociatedAccountFingerprint({
    required String fingerprint,
    required String? expectedCurrent,
  }) async {
    commitAssociatedAccountFingerprintCallCount += 1;
    callOrder.add('commitAssociatedAccountFingerprint');
    throw StateError(
      'Associated-account-fingerprint commit must not be called by '
      'SyncOrchestrator.',
    );
  }

  @override
  Future<List<String>> loadMeaningfulAccountFingerprints() async {
    loadMeaningfulAccountFingerprintsCallCount += 1;
    callOrder.add('loadMeaningfulAccountFingerprints');
    throw StateError(
      'Meaningful-legacy-fingerprint enumeration must not be called by '
      'SyncOrchestrator.',
    );
  }
}

void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('sync_orchestrator_test_');
  });

  tearDown(() {
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  ProtectedSyncPersistenceStore buildStore({FileProtectionBridge? bridge}) {
    var counter = 0;
    return ProtectedSyncPersistenceStore(
      rootDirectoryProvider: () async => tempRoot,
      fileProtectionBridge: bridge ?? _FakeFileProtectionBridge(),
      tokenFactory: () => 'token-${counter++}',
      clock: () => DateTime.utc(2026, 8, 1, 12, 0),
    );
  }

  const fingerprintA =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const fingerprintB =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  final epoch = DataEpoch.parse('12121212-1212-4212-8212-121212121212');

  CloudKitAccountSnapshot availableSnapshot(
          {String fingerprint = fingerprintA}) =>
      CloudKitAccountSnapshot(
        availability: CloudKitAccountAvailability.available,
        isPrivateDatabaseUsable: true,
        accountFingerprint: fingerprint,
        fingerprintResolved: true,
        bridgeVersion: 1,
      );

  const successZoneResult = CloudKitZoneConfigurationResult(
    success: true,
    zoneCreated: false,
    zoneAlreadyExisted: true,
    accountAvailability: CloudKitAccountAvailability.available,
  );

  CloudKeptWisdomProjection activeProjection({
    required String revealId,
    String wisdomText = 'Synthetic wisdom text for testing only.',
    int updatedAtMs = 3000,
    String? mutationId,
    DataEpoch? dataEpoch,
    bool hasReflection = false,
  }) {
    return CloudKeptWisdomProjection.tryParseRemote({
      'recordName': 'east-kept-$revealId',
      'isTombstone': false,
      'revealId': revealId,
      'wisdomText': wisdomText,
      'revealedAtMs': 1000,
      'keptAtMs': 2000,
      if (hasReflection) 'reflectionText': 'A synthetic reflection.',
      if (hasReflection) 'reflectedAtMs': updatedAtMs,
      'updatedAtMs': updatedAtMs,
      'mutationId': mutationId ?? _mutationIdFor(revealId),
      'dataEpoch': (dataEpoch ?? epoch).value,
      'schemaVersion': 3,
    })!;
  }

  SyncChange createChangeFor(
    String revealId, {
    String wisdomText = 'Synthetic wisdom text for testing only.',
    String? mutationId,
    DataEpoch? dataEpoch,
    bool hasReflection = false,
    int updatedAtMs = 3000,
    DateTime? enqueuedAt,
  }) {
    return SyncChange(
      kind: SyncChangeKind.create,
      projection: activeProjection(
        revealId: revealId,
        wisdomText: wisdomText,
        mutationId: mutationId,
        dataEpoch: dataEpoch,
        hasReflection: hasReflection,
        updatedAtMs: updatedAtMs,
      ),
      enqueuedAt: enqueuedAt ?? DateTime.utc(2026, 8, 1, 10),
    );
  }

  SyncChange createTombstoneFor(
    String revealId, {
    String? mutationId,
    DataEpoch? dataEpoch,
  }) {
    return SyncChange(
      kind: SyncChangeKind.delete,
      projection: CloudKeptWisdomProjection.tombstone(
        SyncTombstone(
          revealId: revealId,
          dataEpoch: dataEpoch ?? epoch,
          updatedAt: DateTime.utc(2026, 8, 1, 11),
          deletedAt: DateTime.utc(2026, 8, 1, 11),
          mutationId: mutationId ?? _mutationIdFor(revealId),
        ),
      ),
      enqueuedAt: DateTime.utc(2026, 8, 1, 11),
    );
  }

  // ---------------------------------------------------------------------
  // 1. no-account state performs zero persistence mutation and zero
  //    transport operation.
  // ---------------------------------------------------------------------
  test(
      'no-account: zero persistence mutation, zero transport call beyond '
      'the account snapshot', () async {
    final fileBridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: fileBridge);
    final bridge = _FakeCloudKitPlatformBridge();
    bridge.accountSnapshotSequence = [
      const CloudKitAccountSnapshot(
        availability: CloudKitAccountAvailability.noAccount,
        isPrivateDatabaseUsable: false,
        accountFingerprint: null,
        fingerprintResolved: false,
        bridgeVersion: 1,
      ),
    ];
    final orchestrator =
        SyncOrchestrator(bridge: bridge, persistenceStore: store);

    final result = await orchestrator.runSyncPass();

    expect(result.status, SyncPassStatus.noAccount);
    expect(bridge.configurePrivateZoneCallCount, 0);
    expect(bridge.modifyPrivateRecordsCallCount, 0);
    expect(bridge.fetchPrivateZoneChangesCallCount, 0);
    expect(fileBridge.protectedPaths, isEmpty);
    expect(await store.loadAccountState(fingerprintA), isNull);
  });

  // ---------------------------------------------------------------------
  // 2. restricted/unavailable states fail closed.
  // ---------------------------------------------------------------------
  test('restricted account fails closed with zero further transport calls',
      () async {
    final store = buildStore();
    final bridge = _FakeCloudKitPlatformBridge();
    bridge.accountSnapshotSequence = [
      const CloudKitAccountSnapshot(
        availability: CloudKitAccountAvailability.restricted,
        isPrivateDatabaseUsable: false,
        accountFingerprint: null,
        fingerprintResolved: false,
        bridgeVersion: 1,
      ),
    ];
    final orchestrator =
        SyncOrchestrator(bridge: bridge, persistenceStore: store);

    final result = await orchestrator.runSyncPass();

    expect(result.status, SyncPassStatus.restricted);
    expect(bridge.configurePrivateZoneCallCount, 0);
  });

  for (final entry in <String, CloudKitAccountSnapshot>{
    'couldNotDetermine': const CloudKitAccountSnapshot(
      availability: CloudKitAccountAvailability.couldNotDetermine,
      isPrivateDatabaseUsable: false,
      accountFingerprint: null,
      fingerprintResolved: false,
      bridgeVersion: 1,
    ),
    'temporarilyUnavailable': const CloudKitAccountSnapshot(
      availability: CloudKitAccountAvailability.temporarilyUnavailable,
      isPrivateDatabaseUsable: false,
      accountFingerprint: null,
      fingerprintResolved: false,
      bridgeVersion: 1,
    ),
    'unknown': const CloudKitAccountSnapshot(
      availability: CloudKitAccountAvailability.unknown,
      isPrivateDatabaseUsable: false,
      accountFingerprint: null,
      fingerprintResolved: false,
      bridgeVersion: 1,
    ),
    'unresolvedFingerprintOnAvailableAccount': const CloudKitAccountSnapshot(
      availability: CloudKitAccountAvailability.available,
      isPrivateDatabaseUsable: true,
      accountFingerprint: null,
      fingerprintResolved: false,
      bridgeVersion: 1,
    ),
    'privateDatabaseNotUsable': CloudKitAccountSnapshot(
      availability: CloudKitAccountAvailability.available,
      isPrivateDatabaseUsable: false,
      accountFingerprint: fingerprintA,
      fingerprintResolved: true,
      bridgeVersion: 1,
    ),
  }.entries) {
    test('unavailable case "${entry.key}" fails closed as unavailable',
        () async {
      final store = buildStore();
      final bridge = _FakeCloudKitPlatformBridge();
      bridge.accountSnapshotSequence = [entry.value];
      final orchestrator =
          SyncOrchestrator(bridge: bridge, persistenceStore: store);

      final result = await orchestrator.runSyncPass();

      expect(result.status, SyncPassStatus.unavailable);
      expect(bridge.configurePrivateZoneCallCount, 0);
    });
  }

  // ---------------------------------------------------------------------
  // 3. zone configuration occurs before upload.
  // ---------------------------------------------------------------------
  test('zone configuration occurs before outbox upload', () async {
    final store = buildStore();
    await store.enqueueMutation(
      fingerprintA,
      createChangeFor('aaaaaaaa-1111-4111-8111-111111111111'),
    );
    final bridge = _FakeCloudKitPlatformBridge();
    bridge.accountSnapshotSequence = [availableSnapshot()];
    bridge.zoneConfigurationProvider = () => successZoneResult;
    bridge.modifyProvider =
        (request) => CloudKitModifyRecordsResult.allSucceeded(
              request.records
                  .map((r) => CloudKitRecordModifyOutcome.success(
                        recordName:
                            (r.fields['recordName'] as String?) ?? 'unknown',
                        systemFields: 'c3lzdGVtZmllbGRz',
                      ))
                  .toList(),
            );
    bridge.fetchProvider = (request) => CloudKitZoneChangesResult.success(
          changedKeptWisdomRecords: const [],
          changedSyncStateRecords: const [],
          serverToken: 'bmV3dG9rZW4=',
        );
    final orchestrator =
        SyncOrchestrator(bridge: bridge, persistenceStore: store);

    await orchestrator.runSyncPass();

    final configureIndex = bridge.callOrder.indexOf('configurePrivateZone');
    final modifyIndex = bridge.callOrder.indexOf('modifyPrivateRecords');
    expect(configureIndex, greaterThanOrEqualTo(0));
    expect(modifyIndex, greaterThan(configureIndex));
  });

  // ---------------------------------------------------------------------
  // 4. persisted outbox order becomes upload order.
  // ---------------------------------------------------------------------
  test('persisted outbox order becomes upload order', () async {
    final store = buildStore();
    const revealIds = [
      'aaaaaaaa-1111-4111-8111-111111111111',
      'bbbbbbbb-2222-4222-8222-222222222222',
      'cccccccc-3333-4333-8333-333333333333',
    ];
    for (final revealId in revealIds) {
      await store.enqueueMutation(fingerprintA, createChangeFor(revealId));
    }

    CloudKitModifyRecordsRequest? capturedRequest;
    final bridge = _FakeCloudKitPlatformBridge();
    bridge.accountSnapshotSequence = [availableSnapshot()];
    bridge.zoneConfigurationProvider = () => successZoneResult;
    bridge.onModify = (request) async => capturedRequest = request;
    bridge.modifyProvider =
        (request) => CloudKitModifyRecordsResult.allSucceeded(
              const [],
            );
    bridge.fetchProvider = (request) => CloudKitZoneChangesResult.success(
          changedKeptWisdomRecords: const [],
          changedSyncStateRecords: const [],
          serverToken: 'bmV3dG9rZW4=',
        );
    final orchestrator =
        SyncOrchestrator(bridge: bridge, persistenceStore: store);

    await orchestrator.runSyncPass();

    final expectedOrder =
        revealIds.map((id) => 'east-kept-$id').toList(growable: false);
    final actualOrder = capturedRequest!.records
        .map((r) => r.fields['recordName'] as String)
        .toList(growable: false);
    expect(actualOrder, expectedOrder);
  });

  // ---------------------------------------------------------------------
  // 5/6/7/8: translation correctness (active, tombstone, reflection,
  // duplicate wisdom text under distinct revealIds).
  // ---------------------------------------------------------------------
  test('active mutation is translated correctly', () async {
    final store = buildStore();
    const revealId = 'aaaaaaaa-1111-4111-8111-111111111111';
    await store.enqueueMutation(fingerprintA, createChangeFor(revealId));

    CloudKitModifyRecordsRequest? capturedRequest;
    final bridge = _FakeCloudKitPlatformBridge();
    bridge.accountSnapshotSequence = [availableSnapshot()];
    bridge.zoneConfigurationProvider = () => successZoneResult;
    bridge.onModify = (request) async => capturedRequest = request;
    bridge.modifyProvider =
        (_) => CloudKitModifyRecordsResult.allSucceeded(const []);
    bridge.fetchProvider = (_) => CloudKitZoneChangesResult.success(
          changedKeptWisdomRecords: const [],
          changedSyncStateRecords: const [],
          serverToken: 'bmV3dG9rZW4=',
        );
    final orchestrator =
        SyncOrchestrator(bridge: bridge, persistenceStore: store);

    await orchestrator.runSyncPass();

    expect(capturedRequest!.records, hasLength(1));
    final record = capturedRequest!.records.single;
    expect(record.recordType, CloudKeptWisdomWireEnvelope.recordType);
    final decoded = CloudKeptWisdomWireEnvelope.tryDecode(record.fields);
    expect(decoded, isNotNull);
    expect(decoded!.revealId, revealId);
    expect(decoded.isTombstone, isFalse);
  });

  test('tombstone mutation is translated correctly', () async {
    final store = buildStore();
    const revealId = 'aaaaaaaa-1111-4111-8111-111111111111';
    // A tombstone-only bucket still needs a dataEpoch source; enqueue the
    // tombstone directly (a fresh bucket adopts its dataEpoch).
    await store.enqueueMutation(fingerprintA, createTombstoneFor(revealId));

    CloudKitModifyRecordsRequest? capturedRequest;
    final bridge = _FakeCloudKitPlatformBridge();
    bridge.accountSnapshotSequence = [availableSnapshot()];
    bridge.zoneConfigurationProvider = () => successZoneResult;
    bridge.onModify = (request) async => capturedRequest = request;
    bridge.modifyProvider =
        (_) => CloudKitModifyRecordsResult.allSucceeded(const []);
    bridge.fetchProvider = (_) => CloudKitZoneChangesResult.success(
          changedKeptWisdomRecords: const [],
          changedSyncStateRecords: const [],
          serverToken: 'bmV3dG9rZW4=',
        );
    final orchestrator =
        SyncOrchestrator(bridge: bridge, persistenceStore: store);

    await orchestrator.runSyncPass();

    final record = capturedRequest!.records.single;
    final decoded = CloudKeptWisdomWireEnvelope.tryDecode(record.fields);
    expect(decoded, isNotNull);
    expect(decoded!.isTombstone, isTrue);
    expect(decoded.recordName, 'east-kept-$revealId');
  });

  test('Reflection projection is preserved through translation', () async {
    final store = buildStore();
    const revealId = 'aaaaaaaa-1111-4111-8111-111111111111';
    await store.enqueueMutation(
      fingerprintA,
      createChangeFor(revealId, hasReflection: true),
    );

    CloudKitModifyRecordsRequest? capturedRequest;
    final bridge = _FakeCloudKitPlatformBridge();
    bridge.accountSnapshotSequence = [availableSnapshot()];
    bridge.zoneConfigurationProvider = () => successZoneResult;
    bridge.onModify = (request) async => capturedRequest = request;
    bridge.modifyProvider =
        (_) => CloudKitModifyRecordsResult.allSucceeded(const []);
    bridge.fetchProvider = (_) => CloudKitZoneChangesResult.success(
          changedKeptWisdomRecords: const [],
          changedSyncStateRecords: const [],
          serverToken: 'bmV3dG9rZW4=',
        );
    final orchestrator =
        SyncOrchestrator(bridge: bridge, persistenceStore: store);

    await orchestrator.runSyncPass();

    final decoded = CloudKeptWisdomWireEnvelope.tryDecode(
        capturedRequest!.records.single.fields);
    expect(decoded!.reflectionText, 'A synthetic reflection.');
    expect(decoded.reflectedAtMs, isNotNull);
  });

  test(
      'exact duplicate wisdom text under different revealIds remains '
      'independent in the upload batch', () async {
    final store = buildStore();
    const revealId1 = 'aaaaaaaa-1111-4111-8111-111111111111';
    const revealId2 = 'bbbbbbbb-2222-4222-8222-222222222222';
    const sharedText = 'Byte-identical wisdom text for both occurrences.';
    await store.enqueueMutation(
      fingerprintA,
      createChangeFor(revealId1, wisdomText: sharedText),
    );
    await store.enqueueMutation(
      fingerprintA,
      createChangeFor(revealId2, wisdomText: sharedText),
    );

    CloudKitModifyRecordsRequest? capturedRequest;
    final bridge = _FakeCloudKitPlatformBridge();
    bridge.accountSnapshotSequence = [availableSnapshot()];
    bridge.zoneConfigurationProvider = () => successZoneResult;
    bridge.onModify = (request) async => capturedRequest = request;
    bridge.modifyProvider =
        (_) => CloudKitModifyRecordsResult.allSucceeded(const []);
    bridge.fetchProvider = (_) => CloudKitZoneChangesResult.success(
          changedKeptWisdomRecords: const [],
          changedSyncStateRecords: const [],
          serverToken: 'bmV3dG9rZW4=',
        );
    final orchestrator =
        SyncOrchestrator(bridge: bridge, persistenceStore: store);

    await orchestrator.runSyncPass();

    expect(capturedRequest!.records, hasLength(2));
    final recordNames =
        capturedRequest!.records.map((r) => r.fields['recordName']).toSet();
    expect(recordNames, {'east-kept-$revealId1', 'east-kept-$revealId2'});
  });

  // ---------------------------------------------------------------------
  // 9/10/11/12/13: upload outcome application.
  // ---------------------------------------------------------------------
  test('upload success acknowledges only the exact mutationId', () async {
    final store = buildStore();
    const revealId = 'aaaaaaaa-1111-4111-8111-111111111111';
    await store.enqueueMutation(fingerprintA, createChangeFor(revealId));

    final bridge = _FakeCloudKitPlatformBridge();
    bridge.accountSnapshotSequence = [availableSnapshot()];
    bridge.zoneConfigurationProvider = () => successZoneResult;
    bridge.modifyProvider =
        (request) => CloudKitModifyRecordsResult.allSucceeded([
              CloudKitRecordModifyOutcome.success(
                recordName: 'east-kept-$revealId',
                systemFields: 'c3lzdGVtZmllbGRz',
              ),
            ]);
    bridge.fetchProvider = (_) => CloudKitZoneChangesResult.success(
          changedKeptWisdomRecords: const [],
          changedSyncStateRecords: const [],
          serverToken: 'bmV3dG9rZW4=',
        );
    final orchestrator =
        SyncOrchestrator(bridge: bridge, persistenceStore: store);

    final result = await orchestrator.runSyncPass();

    expect(result.status, SyncPassStatus.completed);
    expect(result.acknowledgedMutationCount, 1);
    final pending = await store.readPendingMutations(fingerprintA);
    expect(pending, isEmpty);
    final bucket = await store.loadAccountState(fingerprintA);
    expect(
        bucket!.recordSystemFields['east-kept-$revealId'], 'c3lzdGVtZmllbGRz');
  });

  test('partial success removes only confirmed mutations', () async {
    final store = buildStore();
    const revealId1 = 'aaaaaaaa-1111-4111-8111-111111111111';
    const revealId2 = 'bbbbbbbb-2222-4222-8222-222222222222';
    await store.enqueueMutation(fingerprintA, createChangeFor(revealId1));
    await store.enqueueMutation(fingerprintA, createChangeFor(revealId2));

    final bridge = _FakeCloudKitPlatformBridge();
    bridge.accountSnapshotSequence = [availableSnapshot()];
    bridge.zoneConfigurationProvider = () => successZoneResult;
    bridge.modifyProvider = (_) => CloudKitModifyRecordsResult.partialFailure([
          CloudKitRecordModifyOutcome.success(
            recordName: 'east-kept-$revealId1',
            systemFields: 'c3lzdGVtZmllbGRz',
          ),
          CloudKitRecordModifyOutcome.failure(
            recordName: 'east-kept-$revealId2',
            errorCode: syncErrorCodeInvalidArguments,
          ),
        ]);
    bridge.fetchProvider = (_) => CloudKitZoneChangesResult.success(
          changedKeptWisdomRecords: const [],
          changedSyncStateRecords: const [],
          serverToken: 'bmV3dG9rZW4=',
        );
    final orchestrator =
        SyncOrchestrator(bridge: bridge, persistenceStore: store);

    final result = await orchestrator.runSyncPass();

    expect(result.status, SyncPassStatus.completed);
    expect(result.acknowledgedMutationCount, 1);
    expect(result.permanentlyFailedMutationCount, 1);
    final pending = await store.readPendingMutations(fingerprintA);
    expect(pending, hasLength(1));
    expect(pending.single.recordName, 'east-kept-$revealId2');
    expect(pending.single.status, PersistedOutboxMutationStatus.failed);
  });

  test('retryable per-record failure leaves the queue unchanged', () async {
    final store = buildStore();
    const revealId = 'aaaaaaaa-1111-4111-8111-111111111111';
    await store.enqueueMutation(fingerprintA, createChangeFor(revealId));

    final bridge = _FakeCloudKitPlatformBridge();
    bridge.accountSnapshotSequence = [availableSnapshot()];
    bridge.zoneConfigurationProvider = () => successZoneResult;
    bridge.modifyProvider = (_) => CloudKitModifyRecordsResult.partialFailure([
          CloudKitRecordModifyOutcome.failure(
            recordName: 'east-kept-$revealId',
            errorCode: syncErrorCodeNetworkFailure,
          ),
        ]);
    bridge.fetchProvider = (_) => CloudKitZoneChangesResult.success(
          changedKeptWisdomRecords: const [],
          changedSyncStateRecords: const [],
          serverToken: 'bmV3dG9rZW4=',
        );
    final orchestrator =
        SyncOrchestrator(bridge: bridge, persistenceStore: store);

    final result = await orchestrator.runSyncPass();

    expect(result.status, SyncPassStatus.completed);
    expect(result.acknowledgedMutationCount, 0);
    expect(result.permanentlyFailedMutationCount, 0);
    expect(result.conflictedMutationCount, 0);
    final pending = await store.readPendingMutations(fingerprintA);
    expect(pending, hasLength(1));
    expect(pending.single.status, PersistedOutboxMutationStatus.pending);
  });

  test('permanent per-record failure remains queued and marked', () async {
    final store = buildStore();
    const revealId = 'aaaaaaaa-1111-4111-8111-111111111111';
    await store.enqueueMutation(fingerprintA, createChangeFor(revealId));

    final bridge = _FakeCloudKitPlatformBridge();
    bridge.accountSnapshotSequence = [availableSnapshot()];
    bridge.zoneConfigurationProvider = () => successZoneResult;
    bridge.modifyProvider = (_) => CloudKitModifyRecordsResult.partialFailure([
          CloudKitRecordModifyOutcome.failure(
            recordName: 'east-kept-$revealId',
            errorCode: syncErrorCodeInvalidArguments,
          ),
        ]);
    bridge.fetchProvider = (_) => CloudKitZoneChangesResult.success(
          changedKeptWisdomRecords: const [],
          changedSyncStateRecords: const [],
          serverToken: 'bmV3dG9rZW4=',
        );
    final orchestrator =
        SyncOrchestrator(bridge: bridge, persistenceStore: store);

    final result = await orchestrator.runSyncPass();

    expect(result.permanentlyFailedMutationCount, 1);
    final pending = await store.readPendingMutations(fingerprintA);
    expect(pending, hasLength(1));
    expect(pending.single.status, PersistedOutboxMutationStatus.failed);
  });

  test('conflict (serverRecordChanged) remains queued and marked conflicted',
      () async {
    final store = buildStore();
    const revealId = 'aaaaaaaa-1111-4111-8111-111111111111';
    await store.enqueueMutation(fingerprintA, createChangeFor(revealId));

    final bridge = _FakeCloudKitPlatformBridge();
    bridge.accountSnapshotSequence = [availableSnapshot()];
    bridge.zoneConfigurationProvider = () => successZoneResult;
    bridge.modifyProvider = (_) => CloudKitModifyRecordsResult.partialFailure([
          CloudKitRecordModifyOutcome.failure(
            recordName: 'east-kept-$revealId',
            errorCode: syncErrorCodeServerRecordChanged,
          ),
        ]);
    bridge.fetchProvider = (_) => CloudKitZoneChangesResult.success(
          changedKeptWisdomRecords: const [],
          changedSyncStateRecords: const [],
          serverToken: 'bmV3dG9rZW4=',
        );
    final orchestrator =
        SyncOrchestrator(bridge: bridge, persistenceStore: store);

    final result = await orchestrator.runSyncPass();

    expect(result.conflictedMutationCount, 1);
    final pending = await store.readPendingMutations(fingerprintA);
    expect(pending, hasLength(1));
    expect(pending.single.status, PersistedOutboxMutationStatus.conflicted);
  });

  // ---------------------------------------------------------------------
  // 14. stale superseded mutation response cannot remove the current
  //     mutation.
  // ---------------------------------------------------------------------
  test(
      'a success response naming a superseded mutationId never removes the '
      'current replacement mutation', () async {
    final store = buildStore();
    const revealId = 'aaaaaaaa-1111-4111-8111-111111111111';
    await store.enqueueMutation(
      fingerprintA,
      createChangeFor(
        revealId,
        mutationId: 'cccccccc-0000-4000-8000-000000000001',
      ),
    );

    final bridge = _FakeCloudKitPlatformBridge();
    bridge.accountSnapshotSequence = [availableSnapshot()];
    bridge.zoneConfigurationProvider = () => successZoneResult;
    bridge.onModify = (_) async {
      // Simulate a newer local edit superseding the outbox entry while
      // the "network call" for the old mutationId is still in flight.
      await store.enqueueMutation(
        fingerprintA,
        createChangeFor(
          revealId,
          mutationId: 'cccccccc-0000-4000-8000-000000000002',
          updatedAtMs: 9000,
        ),
      );
    };
    bridge.modifyProvider = (_) => CloudKitModifyRecordsResult.allSucceeded([
          CloudKitRecordModifyOutcome.success(
            recordName: 'east-kept-$revealId',
            systemFields: 'c3lzdGVtZmllbGRz',
          ),
        ]);
    bridge.fetchProvider = (_) => CloudKitZoneChangesResult.success(
          changedKeptWisdomRecords: const [],
          changedSyncStateRecords: const [],
          serverToken: 'bmV3dG9rZW4=',
        );
    final orchestrator =
        SyncOrchestrator(bridge: bridge, persistenceStore: store);

    await orchestrator.runSyncPass();

    final pending = await store.readPendingMutations(fingerprintA);
    expect(pending, hasLength(1));
    expect(pending.single.mutationId, 'cccccccc-0000-4000-8000-000000000002');
  });

  // ---------------------------------------------------------------------
  // 15. upload persistence failure prevents fetch.
  //
  // The injected failure fires on the very next protected-file operation
  // the store performs during this pass. Depending on
  // ProtectedSyncPersistenceStore's own internal call ordering, that may be
  // the state load or the durable application of upload outcomes -- either
  // way, this proves the required observable behavior: a persistence-layer
  // failure occurring anywhere before the fetch step yields
  // `persistenceFailure` and the fetch step is never reached.
  // ---------------------------------------------------------------------
  test(
      'a persistence-layer failure during upload/state handling stops the '
      'pass before any fetch', () async {
    final fileBridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: fileBridge);
    const revealId = 'aaaaaaaa-1111-4111-8111-111111111111';
    await store.enqueueMutation(fingerprintA, createChangeFor(revealId));

    final finalPath =
        '${tempRoot.path}/east_sync_state/east_sync_state_v1.json';
    fileBridge.failNextTimeFor(finalPath, times: 10);

    final bridge = _FakeCloudKitPlatformBridge();
    bridge.accountSnapshotSequence = [availableSnapshot()];
    bridge.zoneConfigurationProvider = () => successZoneResult;
    bridge.modifyProvider = (_) => CloudKitModifyRecordsResult.allSucceeded([
          CloudKitRecordModifyOutcome.success(
            recordName: 'east-kept-$revealId',
            systemFields: 'c3lzdGVtZmllbGRz',
          ),
        ]);
    bridge.fetchProvider = (_) => CloudKitZoneChangesResult.success(
          changedKeptWisdomRecords: const [],
          changedSyncStateRecords: const [],
          serverToken: 'bmV3dG9rZW4=',
        );
    final orchestrator =
        SyncOrchestrator(bridge: bridge, persistenceStore: store);

    final result = await orchestrator.runSyncPass();

    expect(result.status, SyncPassStatus.persistenceFailure);
    expect(bridge.fetchPrivateZoneChangesCallCount, 0);
  });

  // ---------------------------------------------------------------------
  // 16/17/18. fetch uses the persisted token; single aggregated
  //           "multi-page" call; token persisted only after success.
  // ---------------------------------------------------------------------
  test('fetch uses the persisted opaque server change token', () async {
    final store = buildStore();
    // Phase 4D-2 itself never commits a successful-fetch token (see the
    // crash-consistency correction) -- a previously *committed* token can
    // only come from a prior cycle's Phase 4E commit, simulated here via a
    // direct store call, exactly as Phase 4E would eventually perform it.
    await store.enqueueMutation(
      fingerprintA,
      createChangeFor('aaaaaaaa-1111-4111-8111-111111111111'),
    );
    await store.storeServerChangeToken(fingerprintA, 'cHJldmlvdXN0b2tlbg==');

    final bridge = _FakeCloudKitPlatformBridge();
    bridge.accountSnapshotSequence = [availableSnapshot()];
    bridge.zoneConfigurationProvider = () => successZoneResult;
    bridge.modifyProvider =
        (_) => CloudKitModifyRecordsResult.allSucceeded(const []);
    bridge.fetchProvider = (_) => CloudKitZoneChangesResult.success(
          changedKeptWisdomRecords: const [],
          changedSyncStateRecords: const [],
          serverToken: 'Zmlyc3R0b2tlbg==',
        );
    final orchestrator =
        SyncOrchestrator(bridge: bridge, persistenceStore: store);

    final result = await orchestrator.runSyncPass();

    expect(result.status, SyncPassStatus.completed);
    expect(
      bridge.fetchRequests.single.previousServerToken,
      'cHJldmlvdXN0b2tlbg==',
    );
  });

  test(
      'a single fetchPrivateZoneChanges call carries the fully-aggregated '
      'multi-record result deterministically (no orchestrator-level '
      'pagination loop -- none exists in the transport contract)', () async {
    final store = buildStore();
    final projections = [
      activeProjection(revealId: 'aaaaaaaa-1111-4111-8111-111111111111'),
      activeProjection(revealId: 'bbbbbbbb-2222-4222-8222-222222222222'),
      activeProjection(revealId: 'cccccccc-3333-4333-8333-333333333333'),
    ];
    final bridge = _FakeCloudKitPlatformBridge();
    bridge.accountSnapshotSequence = [availableSnapshot()];
    bridge.zoneConfigurationProvider = () => successZoneResult;
    bridge.modifyProvider =
        (_) => CloudKitModifyRecordsResult.allSucceeded(const []);
    bridge.fetchProvider = (_) => CloudKitZoneChangesResult.success(
          changedKeptWisdomRecords: projections,
          changedSyncStateRecords: const [],
          serverToken: 'bmV3dG9rZW4=',
        );
    final orchestrator =
        SyncOrchestrator(bridge: bridge, persistenceStore: store);

    final result = await orchestrator.runSyncPass();

    expect(bridge.fetchPrivateZoneChangesCallCount, 1);
    expect(
      result.pendingIncomingBatch!.incomingKeptWisdomProjections,
      hasLength(3),
    );
    expect(result.hasMoreWorkRemaining, isFalse);
    expect(
        result.pendingIncomingBatch!.pendingServerChangeToken, 'bmV3dG9rZW4=');
  });

  // ---------------------------------------------------------------------
  // Crash-consistency correction, required tests 1-3, 5, 6, 10:
  // a successful fetch never commits its token; it is only ever returned
  // as a *proposed* checkpoint, and repeated/no-bucket passes remain safe.
  // ---------------------------------------------------------------------

  test(
      '1. a successful fetch returns one typed pending incoming batch '
      'carrying the proposed server change token and the opaque account '
      'fingerprint', () async {
    final store = buildStore();
    final bridge = _FakeCloudKitPlatformBridge();
    bridge.accountSnapshotSequence = [availableSnapshot()];
    bridge.zoneConfigurationProvider = () => successZoneResult;
    bridge.modifyProvider =
        (_) => CloudKitModifyRecordsResult.allSucceeded(const []);
    bridge.fetchProvider = (_) => CloudKitZoneChangesResult.success(
          changedKeptWisdomRecords: const [],
          changedSyncStateRecords: const [],
          serverToken: 'cHJvcG9zZWR0b2tlbg==',
        );
    final orchestrator =
        SyncOrchestrator(bridge: bridge, persistenceStore: store);

    final result = await orchestrator.runSyncPass();

    expect(result.status, SyncPassStatus.completed);
    // 1. exactly one typed pending batch, not loose result fields.
    expect(result.pendingIncomingBatch, isA<PendingIncomingSyncBatch>());
    final batch = result.pendingIncomingBatch!;
    expect(batch.pendingServerChangeToken, 'cHJvcG9zZWR0b2tlbg==');
    // 2. the batch carries the opaque account fingerprint internally.
    expect(batch.accountFingerprint, fingerprintA);
  });

  test(
      '2. a successful fetch never calls storeServerChangeToken, and never '
      'calls the Phase 4E-1 incoming-checkpoint API (Phase 4D-2\'s own '
      'SyncOrchestrator does not call it; that remains Phase 4E-3\'s '
      'separate responsibility once it exists)', () async {
    final recordingStore = _RecordingSyncPersistenceStore(buildStore());
    final bridge = _FakeCloudKitPlatformBridge();
    bridge.accountSnapshotSequence = [availableSnapshot()];
    bridge.zoneConfigurationProvider = () => successZoneResult;
    bridge.modifyProvider =
        (_) => CloudKitModifyRecordsResult.allSucceeded(const []);
    bridge.fetchProvider = (_) => CloudKitZoneChangesResult.success(
          changedKeptWisdomRecords: const [],
          changedSyncStateRecords: const [],
          serverToken: 'cHJvcG9zZWR0b2tlbg==',
        );
    final orchestrator =
        SyncOrchestrator(bridge: bridge, persistenceStore: recordingStore);

    final result = await orchestrator.runSyncPass();

    expect(result.status, SyncPassStatus.completed);
    expect(recordingStore.storeServerChangeTokenCallCount, 0);
    expect(recordingStore.commitIncomingBatchCheckpointCallCount, 0);
  });

  test(
      '3. the previously committed token remains unchanged after a '
      'successful fetch', () async {
    final store = buildStore();
    await store.enqueueMutation(
      fingerprintA,
      createChangeFor('aaaaaaaa-1111-4111-8111-111111111111'),
    );
    await store.storeServerChangeToken(fingerprintA, 'b2xkdG9rZW4=');
    final bridge = _FakeCloudKitPlatformBridge();
    bridge.accountSnapshotSequence = [availableSnapshot()];
    bridge.zoneConfigurationProvider = () => successZoneResult;
    bridge.modifyProvider =
        (_) => CloudKitModifyRecordsResult.allSucceeded(const []);
    bridge.fetchProvider = (_) => CloudKitZoneChangesResult.success(
          changedKeptWisdomRecords: const [],
          changedSyncStateRecords: const [],
          serverToken: 'bmV3dG9rZW4=',
        );
    final orchestrator =
        SyncOrchestrator(bridge: bridge, persistenceStore: store);

    final result = await orchestrator.runSyncPass();

    expect(result.status, SyncPassStatus.completed);
    final batch = result.pendingIncomingBatch!;
    expect(batch.pendingServerChangeToken, 'bmV3dG9rZW4=');
    // 3. the batch carries the exact existing dataEpoch.
    expect(batch.baseDataEpoch, epoch);
    // 4. the batch carries the exact previous token used for the fetch.
    expect(batch.previousServerChangeToken, 'b2xkdG9rZW4=');
    final bucket = await store.loadAccountState(fingerprintA);
    expect(bucket!.serverChangeToken, 'b2xkdG9rZW4=');
  });

  test(
      '5. a no-bucket account fetches from a null token, returns incoming '
      'changes and the proposed token, and creates no bucket', () async {
    final store = buildStore();
    final incoming =
        activeProjection(revealId: 'aaaaaaaa-1111-4111-8111-111111111111');
    final bridge = _FakeCloudKitPlatformBridge();
    bridge.accountSnapshotSequence = [availableSnapshot()];
    bridge.zoneConfigurationProvider = () => successZoneResult;
    bridge.fetchProvider = (_) => CloudKitZoneChangesResult.success(
          changedKeptWisdomRecords: [incoming],
          changedSyncStateRecords: const [],
          serverToken: 'Ym9vdHN0cmFwdG9rZW4=',
        );
    final orchestrator =
        SyncOrchestrator(bridge: bridge, persistenceStore: store);

    final result = await orchestrator.runSyncPass();

    expect(result.status, SyncPassStatus.completed);
    expect(bridge.fetchRequests.single.previousServerToken, isNull);
    final batch = result.pendingIncomingBatch!;
    expect(batch.incomingKeptWisdomProjections, hasLength(1));
    expect(batch.pendingServerChangeToken, 'Ym9vdHN0cmFwdG9rZW4=');
    // 6. no-bucket fetch returns null baseDataEpoch and null previous
    //    token -- never fabricated.
    expect(batch.baseDataEpoch, isNull);
    expect(batch.previousServerChangeToken, isNull);
    expect(batch.accountFingerprint, fingerprintA);
    expect(bridge.modifyPrivateRecordsCallCount, 0);
    expect(await store.loadAccountState(fingerprintA), isNull);
  });

  test(
      '6. repeating the pass before a Phase 4E commit refetches from the '
      'same previously committed token', () async {
    final store = buildStore();
    await store.enqueueMutation(
      fingerprintA,
      createChangeFor('aaaaaaaa-1111-4111-8111-111111111111'),
    );
    await store.storeServerChangeToken(fingerprintA, 'c3RhYmxldG9rZW4=');
    final bridge = _FakeCloudKitPlatformBridge();
    bridge.accountSnapshotSequence = [availableSnapshot(), availableSnapshot()];
    bridge.zoneConfigurationProvider = () => successZoneResult;
    bridge.modifyProvider =
        (_) => CloudKitModifyRecordsResult.allSucceeded(const []);
    bridge.fetchProvider = (_) => CloudKitZoneChangesResult.success(
          changedKeptWisdomRecords: const [],
          changedSyncStateRecords: const [],
          serverToken: 'cHJvcG9zZWQx',
        );
    final orchestrator =
        SyncOrchestrator(bridge: bridge, persistenceStore: store);

    final firstResult = await orchestrator.runSyncPass();
    bridge.accountSnapshotSequence = [availableSnapshot(), availableSnapshot()];
    final secondResult = await orchestrator.runSyncPass();

    expect(bridge.fetchRequests, hasLength(2));
    expect(bridge.fetchRequests[0].previousServerToken, 'c3RhYmxldG9rZW4=');
    expect(bridge.fetchRequests[1].previousServerToken, 'c3RhYmxldG9rZW4=');
    // 8. repeated fetches from the same uncommitted previous token carry
    //    that same previous-token baseline on their own returned batches.
    expect(
      firstResult.pendingIncomingBatch!.previousServerChangeToken,
      'c3RhYmxldG9rZW4=',
    );
    expect(
      secondResult.pendingIncomingBatch!.previousServerChangeToken,
      'c3RhYmxldG9rZW4=',
    );
  });

  test('10. a fetch failure never changes the persisted server change token',
      () async {
    final store = buildStore();
    await store.enqueueMutation(
      fingerprintA,
      createChangeFor('aaaaaaaa-1111-4111-8111-111111111111'),
    );
    await store.storeServerChangeToken(fingerprintA, 'dW5jaGFuZ2Vk');
    final bridge = _FakeCloudKitPlatformBridge();
    bridge.accountSnapshotSequence = [availableSnapshot()];
    bridge.zoneConfigurationProvider = () => successZoneResult;
    bridge.modifyProvider =
        (_) => CloudKitModifyRecordsResult.allSucceeded(const []);
    bridge.fetchProvider = (_) => CloudKitZoneChangesResult.failure(
          syncErrorCodeNetworkFailure,
        );
    final orchestrator =
        SyncOrchestrator(bridge: bridge, persistenceStore: store);

    final result = await orchestrator.runSyncPass();

    final bucket = await store.loadAccountState(fingerprintA);
    expect(bucket!.serverChangeToken, 'dW5jaGFuZ2Vk');
    // 12. fetch failure returns no pending batch.
    expect(result.pendingIncomingBatch, isNull);
  });

  // ---------------------------------------------------------------------
  // 19/20. token expiration.
  // ---------------------------------------------------------------------
  test(
      'token expiration clears only the token, preserving epoch, outbox, '
      'and system fields', () async {
    final store = buildStore();
    const revealId1 = 'aaaaaaaa-1111-4111-8111-111111111111';
    const revealId2 = 'bbbbbbbb-2222-4222-8222-222222222222';
    await store.enqueueMutation(fingerprintA, createChangeFor(revealId1));

    // First pass acknowledges revealId1 and stores its system fields (this
    // part of upload behavior is unchanged by the crash-consistency
    // correction -- only the fetch-success token-commit changed). A
    // "previously committed" token is then seeded directly, exactly as a
    // future Phase 4E would perform it after durably applying an earlier
    // incoming batch -- this phase's own successful fetch never commits
    // one itself (see the tests above).
    final firstBridge = _FakeCloudKitPlatformBridge();
    firstBridge.accountSnapshotSequence = [availableSnapshot()];
    firstBridge.zoneConfigurationProvider = () => successZoneResult;
    firstBridge.modifyProvider =
        (_) => CloudKitModifyRecordsResult.allSucceeded([
              CloudKitRecordModifyOutcome.success(
                recordName: 'east-kept-$revealId1',
                systemFields: 'c3lzdGVtZmllbGRz',
              ),
            ]);
    firstBridge.fetchProvider = (_) => CloudKitZoneChangesResult.success(
          changedKeptWisdomRecords: const [],
          changedSyncStateRecords: const [],
          serverToken: 'cHJvcG9zZWRvbmx5',
        );
    await SyncOrchestrator(bridge: firstBridge, persistenceStore: store)
        .runSyncPass();
    await store.storeServerChangeToken(fingerprintA, 'b2xkdG9rZW4=');

    // Second: enqueue a fresh pending mutation for a different record, then
    // run a pass whose fetch reports tokenExpired.
    await store.enqueueMutation(fingerprintA, createChangeFor(revealId2));
    final beforeBucket = await store.loadAccountState(fingerprintA);
    expect(beforeBucket!.serverChangeToken, 'b2xkdG9rZW4=');

    final secondBridge = _FakeCloudKitPlatformBridge();
    secondBridge.accountSnapshotSequence = [availableSnapshot()];
    secondBridge.zoneConfigurationProvider = () => successZoneResult;
    secondBridge.modifyProvider =
        (_) => CloudKitModifyRecordsResult.partialFailure([
              CloudKitRecordModifyOutcome.failure(
                recordName: 'east-kept-$revealId2',
                errorCode: syncErrorCodeNetworkFailure,
              ),
            ]);
    secondBridge.fetchProvider =
        (_) => CloudKitZoneChangesResult.tokenExpired();
    final result =
        await SyncOrchestrator(bridge: secondBridge, persistenceStore: store)
            .runSyncPass();

    expect(result.status, SyncPassStatus.tokenExpiredNeedsRefetch);
    // 11. tokenExpired returns no pending batch.
    expect(result.pendingIncomingBatch, isNull);
    final afterBucket = await store.loadAccountState(fingerprintA);
    expect(afterBucket!.serverChangeToken, isNull);
    expect(afterBucket.dataEpoch, beforeBucket.dataEpoch);
    expect(afterBucket.recordSystemFields, beforeBucket.recordSystemFields);
    // revealId2's mutation was left retryable (network failure), so it
    // remains queued, exactly as it was before this pass.
    expect(afterBucket.outbox, hasLength(1));
    expect(afterBucket.outbox.single.recordName, 'east-kept-$revealId2');
  });

  // ---------------------------------------------------------------------
  // 21. incoming projections returned, not applied anywhere.
  // ---------------------------------------------------------------------
  test(
      'incoming active and tombstone projections are returned in the '
      'result but this pass never applies them to any repository', () async {
    final store = buildStore();
    final incomingActive =
        activeProjection(revealId: 'aaaaaaaa-1111-4111-8111-111111111111');
    final incomingTombstone = CloudKeptWisdomProjection.tombstone(
      SyncTombstone(
        revealId: 'bbbbbbbb-2222-4222-8222-222222222222',
        dataEpoch: epoch,
        updatedAt: DateTime.utc(2026, 8, 1),
        deletedAt: DateTime.utc(2026, 8, 1),
        mutationId: 'dddddddd-4444-4444-8444-444444444444',
      ),
    );
    final bridge = _FakeCloudKitPlatformBridge();
    bridge.accountSnapshotSequence = [availableSnapshot()];
    bridge.zoneConfigurationProvider = () => successZoneResult;
    bridge.modifyProvider =
        (_) => CloudKitModifyRecordsResult.allSucceeded(const []);
    bridge.fetchProvider = (_) => CloudKitZoneChangesResult.success(
          changedKeptWisdomRecords: [incomingActive, incomingTombstone],
          changedSyncStateRecords: const [],
          serverToken: 'bmV3dG9rZW4=',
        );
    final orchestrator =
        SyncOrchestrator(bridge: bridge, persistenceStore: store);

    final result = await orchestrator.runSyncPass();

    final batch = result.pendingIncomingBatch!;
    expect(batch.incomingKeptWisdomProjections, hasLength(2));
    expect(
      batch.incomingKeptWisdomProjections.where((p) => p.isTombstone),
      hasLength(1),
    );
    expect(
      batch.incomingKeptWisdomProjections.where((p) => !p.isTombstone),
      hasLength(1),
    );
    // 4. Returned alongside the proposed (not committed) token.
    expect(batch.pendingServerChangeToken, 'bmV3dG9rZW4=');
    // Structurally: this class has no field, method, or import capable of
    // reaching a repository at all -- see the layering test file.
  });

  // ---------------------------------------------------------------------
  // 22. malformed incoming payload fails closed.
  // ---------------------------------------------------------------------
  test('a malformed incoming fetch payload fails the pass closed', () async {
    final store = buildStore();
    final malformedResult = CloudKitZoneChangesResult.tryParse({
      'outcome': 'success',
      'changedKeptWisdomRecords': [
        {'recordType': 'CKKeptWisdom'}, // missing every required field
      ],
      'changedSyncStateRecords': <Object?>[],
      'serverToken': 'dG9rZW4=',
    });
    final bridge = _FakeCloudKitPlatformBridge();
    bridge.accountSnapshotSequence = [availableSnapshot()];
    bridge.zoneConfigurationProvider = () => successZoneResult;
    bridge.modifyProvider =
        (_) => CloudKitModifyRecordsResult.allSucceeded(const []);
    bridge.fetchProvider = (_) => malformedResult;
    final orchestrator =
        SyncOrchestrator(bridge: bridge, persistenceStore: store);

    final result = await orchestrator.runSyncPass();

    expect(result.status, SyncPassStatus.permanentFailure);
    final bucket = await store.loadAccountState(fingerprintA);
    expect(bucket, isNull);
  });

  // ---------------------------------------------------------------------
  // 23. account buckets never mix.
  // ---------------------------------------------------------------------
  test('account buckets for two different fingerprints never mix', () async {
    final store = buildStore();

    final bridgeA = _FakeCloudKitPlatformBridge();
    bridgeA.accountSnapshotSequence = [
      availableSnapshot(fingerprint: fingerprintA)
    ];
    bridgeA.zoneConfigurationProvider = () => successZoneResult;
    bridgeA.modifyProvider =
        (_) => CloudKitModifyRecordsResult.allSucceeded(const []);
    bridgeA.fetchProvider = (_) => CloudKitZoneChangesResult.success(
          changedKeptWisdomRecords: const [],
          changedSyncStateRecords: const [],
          serverToken: 'dG9rZW5B',
        );
    // Bucket A needs an outbox entry to exist at all (an empty account has
    // no bucket); enqueue directly against fingerprintA first. Also seed a
    // "previously committed" token for A only, simulating an earlier Phase
    // 4E commit cycle -- this phase's own successful fetch never commits
    // one itself (see the crash-consistency tests above), so persisted
    // token divergence between accounts must come from a prior commit, not
    // from this pass.
    await store.enqueueMutation(
      fingerprintA,
      createChangeFor('aaaaaaaa-1111-4111-8111-111111111111'),
    );
    await store.storeServerChangeToken(fingerprintA, 'cHJldmlvdXNBdG9rZW4=');
    final resultA =
        await SyncOrchestrator(bridge: bridgeA, persistenceStore: store)
            .runSyncPass();

    final bridgeB = _FakeCloudKitPlatformBridge();
    bridgeB.accountSnapshotSequence = [
      availableSnapshot(fingerprint: fingerprintB)
    ];
    bridgeB.zoneConfigurationProvider = () => successZoneResult;
    bridgeB.modifyProvider =
        (_) => CloudKitModifyRecordsResult.allSucceeded(const []);
    bridgeB.fetchProvider = (_) => CloudKitZoneChangesResult.success(
          changedKeptWisdomRecords: const [],
          changedSyncStateRecords: const [],
          serverToken: 'dG9rZW5C',
        );
    await store.enqueueMutation(
      fingerprintB,
      createChangeFor('cccccccc-3333-4333-8333-333333333333',
          dataEpoch: DataEpoch.parse('99999999-9999-4999-8999-999999999999')),
    );
    final resultB =
        await SyncOrchestrator(bridge: bridgeB, persistenceStore: store)
            .runSyncPass();

    // Each pass's own proposed token is distinct and never crosses over.
    final batchA = resultA.pendingIncomingBatch!;
    final batchB = resultB.pendingIncomingBatch!;
    expect(batchA.pendingServerChangeToken, 'dG9rZW5B');
    expect(batchB.pendingServerChangeToken, 'dG9rZW5C');

    // 7. account A and account B batches remain distinguishable
    //    internally -- distinct fingerprints and distinct base epochs.
    expect(batchA.accountFingerprint, fingerprintA);
    expect(batchB.accountFingerprint, fingerprintB);
    expect(batchA.accountFingerprint, isNot(batchB.accountFingerprint));
    expect(batchA.baseDataEpoch, isNot(batchB.baseDataEpoch));
    expect(batchA.previousServerChangeToken, 'cHJldmlvdXNBdG9rZW4=');
    expect(batchB.previousServerChangeToken, isNull);

    // Neither pass durably advanced its own token (crash-consistency
    // correction) -- A's persisted token is still its pre-seeded one, and B
    // (which never had one committed) still has none.
    final bucketA = await store.loadAccountState(fingerprintA);
    final bucketB = await store.loadAccountState(fingerprintB);
    expect(bucketA!.serverChangeToken, 'cHJldmlvdXNBdG9rZW4=');
    expect(bucketB!.serverChangeToken, isNull);
    expect(bucketA.dataEpoch, isNot(bucketB.dataEpoch));
  });

  // ---------------------------------------------------------------------
  // 24. account inconsistency mid-pass fails closed.
  // ---------------------------------------------------------------------
  test(
      'an account-identity change detected mid-pass fails closed without '
      'mutating any bucket', () async {
    final store = buildStore();
    await store.enqueueMutation(
      fingerprintA,
      createChangeFor('aaaaaaaa-1111-4111-8111-111111111111'),
    );
    final bridge = _FakeCloudKitPlatformBridge();
    bridge.accountSnapshotSequence = [
      availableSnapshot(fingerprint: fingerprintA),
      availableSnapshot(fingerprint: fingerprintB),
    ];
    bridge.zoneConfigurationProvider = () => successZoneResult;
    bridge.modifyProvider =
        (_) => CloudKitModifyRecordsResult.allSucceeded(const []);
    bridge.fetchProvider = (_) => CloudKitZoneChangesResult.success(
          changedKeptWisdomRecords: const [],
          changedSyncStateRecords: const [],
          serverToken: 'bmV3dG9rZW4=',
        );
    final orchestrator =
        SyncOrchestrator(bridge: bridge, persistenceStore: store);

    final result = await orchestrator.runSyncPass();

    expect(result.status, SyncPassStatus.permanentFailure);
    expect(bridge.modifyPrivateRecordsCallCount, 0);
    expect(bridge.fetchPrivateZoneChangesCallCount, 0);
    final bucketA = await store.loadAccountState(fingerprintA);
    expect(bucketA!.outbox, hasLength(1));
    expect(await store.loadAccountState(fingerprintB), isNull);
  });

  // ---------------------------------------------------------------------
  // 25. concurrency: shared in-flight future.
  // ---------------------------------------------------------------------
  test(
      'concurrent runSyncPass calls share the same in-flight future '
      'rather than starting a second transport sequence', () async {
    final store = buildStore();
    final bridge = _FakeCloudKitPlatformBridge();
    bridge.accountSnapshotSequence = [availableSnapshot()];
    bridge.zoneConfigurationProvider = () => successZoneResult;
    bridge.modifyProvider =
        (_) => CloudKitModifyRecordsResult.allSucceeded(const []);
    bridge.fetchProvider = (_) => CloudKitZoneChangesResult.success(
          changedKeptWisdomRecords: const [],
          changedSyncStateRecords: const [],
          serverToken: 'bmV3dG9rZW4=',
        );
    final orchestrator =
        SyncOrchestrator(bridge: bridge, persistenceStore: store);

    final future1 = orchestrator.runSyncPass();
    final future2 = orchestrator.runSyncPass();
    final results = await Future.wait([future1, future2]);

    expect(identical(results[0], results[1]), isTrue);
    // One actual pass runs `getAccountSnapshot` twice (account resolution,
    // then the account-isolation consistency re-check) -- the second,
    // concurrent `runSyncPass()` call must not add any further calls,
    // since it shares the exact in-flight Future rather than starting a
    // second pass.
    expect(bridge.getAccountSnapshotCallCount, 2);
    expect(bridge.maxConcurrentTransportCalls, lessThanOrEqualTo(1));

    // A later call, after the first pass has settled, starts a genuinely
    // new pass -- exactly one more pass's worth of calls (2 more).
    bridge.accountSnapshotSequence = [availableSnapshot()];
    await orchestrator.runSyncPass();
    expect(bridge.getAccountSnapshotCallCount, 4);
  });

  // ---------------------------------------------------------------------
  // 26. result/exception rendering is content-safe.
  // ---------------------------------------------------------------------
  test(
      'SyncPassResult rendering never includes sensitive content, even '
      'when cause carries it', () async {
    const sensitiveCause =
        'wisdomText=Secret wisdom revealId=aaaaaaaa-1111-4111-8111-111111111111 '
        'fingerprint=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa '
        'token=c2VjcmV0dG9rZW4= mutationId=cccccccc-0000-4000-8000-000000000001';
    final result = SyncPassResult.permanentFailure(cause: sensitiveCause);

    final rendered = result.toString();
    expect(rendered, isNot(contains('Secret wisdom')));
    expect(rendered, isNot(contains('aaaaaaaa-1111-4111-8111-111111111111')));
    expect(rendered, isNot(contains(fingerprintA)));
    expect(rendered, isNot(contains('c2VjcmV0dG9rZW4=')));
    expect(rendered, isNot(contains('cccccccc-0000-4000-8000-000000000001')));
    expect(rendered, contains('permanentFailure'));
    expect(result.cause, sensitiveCause);
  });

  // ---------------------------------------------------------------------
  // 8/9. the proposed (pending) server change token is never rendered.
  // ---------------------------------------------------------------------
  test(
      '8. the pending incoming batch\'s tokens never appear in '
      'SyncPassResult.toString() or log-safe output', () async {
    const proposedToken = 'cHJvcG9zZWRDaGVja3BvaW50VG9rZW4=';
    const previousToken = 'cHJldmlvdXNDaGVja3BvaW50VG9rZW4=';
    final batch = PendingIncomingSyncBatch(
      accountFingerprint: fingerprintA,
      baseDataEpoch: epoch,
      previousServerChangeToken: previousToken,
      pendingServerChangeToken: proposedToken,
      incomingKeptWisdomProjections: const [],
      incomingSyncStateProjections: const [],
    );
    final result = SyncPassResult.completed(pendingIncomingBatch: batch);

    expect(result.toString(), isNot(contains(proposedToken)));
    expect(result.toString(), isNot(contains(previousToken)));
    expect(
      result.toLogSafeSummary().values.map((v) => v.toString()),
      isNot(contains(proposedToken)),
    );
    expect(result.toLogSafeSummary()['hasPendingBatch'], isTrue);
    expect(result.toLogSafeSummary()['hasPendingCheckpoint'], isTrue);
    expect(result.toLogSafeSummary()['hasPreviousCheckpoint'], isTrue);
    expect(result.toLogSafeSummary()['hasBaseDataEpoch'], isTrue);
    // The values themselves remain available programmatically for a
    // future Phase 4E validation/commit -- just never rendered.
    expect(
        result.pendingIncomingBatch!.pendingServerChangeToken, proposedToken);
    expect(
      result.pendingIncomingBatch!.previousServerChangeToken,
      previousToken,
    );
  });

  test(
      '9. a synthetic token embedding fingerprint-like, record-name-like, '
      'and JSON-like text remains fully absent from rendered output', () async {
    final suspiciousToken = 'eyJmaW5nZXJwcmludCI6ImFhYWFhYWFhYWFhYWFhYWFh'
        'YWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFh'
        'YWFhYSIsInJlY29yZE5hbWUiOiJlYXN0LWtlcHQtYWFhYWFhYWEtMTExMS00MTEx'
        'LTgxMTEtMTExMTExMTExMTExIn0=';
    // The base64 payload above decodes to exactly:
    //   {"fingerprint":"aaaa...(64 a's, equal to fingerprintA)...aaaa",
    //    "recordName":"east-kept-aaaaaaaa-1111-4111-8111-111111111111"}
    // -- a fingerprint-like value, a record-name-like value embedding a
    // revealId-like fragment, and JSON key/value punctuation. None of that
    // decoded content may ever appear in rendered output even though it's
    // embedded inside an opaque token string this phase never decodes.
    final batch = PendingIncomingSyncBatch(
      accountFingerprint: fingerprintA,
      baseDataEpoch: epoch,
      previousServerChangeToken: suspiciousToken,
      pendingServerChangeToken: suspiciousToken,
      incomingKeptWisdomProjections: const [],
      incomingSyncStateProjections: const [],
    );
    final result = SyncPassResult.completed(pendingIncomingBatch: batch);

    final rendered = result.toString();
    // Value-specific: every sensitive value this fixture carries -- the
    // complete opaque token (used as both previous and pending checkpoint
    // here), the complete account fingerprint, the complete dataEpoch
    // UUID, and every fragment embedded inside the decoded JSON payload
    // (its JSON keys, its fingerprint-like value, its record-name-like
    // value, and the revealId-like fragment inside that record name) --
    // is absent from the rendered string. No raw incoming wisdom or
    // Reflection text is asserted here because this fixture's incoming
    // projection lists are empty.
    expect(rendered, isNot(contains(suspiciousToken)));
    expect(rendered, isNot(contains(fingerprintA)));
    expect(rendered, isNot(contains(epoch.value)));
    expect(rendered, isNot(contains('"fingerprint"')));
    expect(rendered, isNot(contains('"recordName"')));
    expect(rendered, isNot(contains('fingerprint')));
    expect(rendered, isNot(contains('east-kept-')));
    expect(rendered, isNot(contains('aaaaaaaa-1111-4111-8111-111111111111')));
    // Exact allowlisted safe output: proves the rendered string is
    // *precisely* the categorical/count/boolean summary
    // `toLogSafeSummary()` produces -- not merely "doesn't contain one
    // particular substring". The structural braces here are the safe
    // map-literal formatting this summary always produces and are not
    // evidence of the JSON-like payload leaking.
    expect(
      rendered,
      'SyncPassResult({status: completed, uploadedRecordCount: 0, '
      'acknowledgedMutationCount: 0, permanentlyFailedMutationCount: 0, '
      'conflictedMutationCount: 0, hasMoreWorkRemaining: false, '
      'hasPendingBatch: true, incomingKeptCount: 0, '
      'incomingSyncStateCount: 0, hasBaseDataEpoch: true, '
      'hasPreviousCheckpoint: true, hasPendingCheckpoint: true, '
      'hasCause: false})',
    );
  });

  test(
      '9b. PendingIncomingSyncBatch\'s own toString()/toLogSafeSummary() '
      'never render its account fingerprint, dataEpoch, or token values',
      () async {
    final suspiciousToken = 'eyJmaW5nZXJwcmludCI6ImFhYWFhYWFhYWFhYWFhYWFh'
        'YWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFh'
        'YWFhYSIsInJlY29yZE5hbWUiOiJlYXN0LWtlcHQtYWFhYWFhYWEtMTExMS00MTEx'
        'LTgxMTEtMTExMTExMTExMTExIn0=';
    final batch = PendingIncomingSyncBatch(
      accountFingerprint: fingerprintA,
      baseDataEpoch: epoch,
      previousServerChangeToken: suspiciousToken,
      pendingServerChangeToken: suspiciousToken,
      incomingKeptWisdomProjections: const [],
      incomingSyncStateProjections: const [],
    );

    final rendered = batch.toString();
    // Value-specific: every sensitive value this fixture carries is
    // absent from the rendered string, including every fragment embedded
    // inside the decoded JSON payload (see test 9's own comment for the
    // exact decoded content) -- not just the complete token as a whole.
    expect(rendered, isNot(contains(suspiciousToken)));
    expect(rendered, isNot(contains(fingerprintA)));
    // DataEpoch.toString() renders its raw UUID value -- never invoked by
    // PendingIncomingSyncBatch's own rendering, so its value must never
    // leak in either form.
    expect(rendered, isNot(contains(epoch.value)));
    expect(rendered, isNot(contains('"fingerprint"')));
    expect(rendered, isNot(contains('"recordName"')));
    expect(rendered, isNot(contains('fingerprint')));
    expect(rendered, isNot(contains('east-kept-')));
    expect(rendered, isNot(contains('aaaaaaaa-1111-4111-8111-111111111111')));
    // Exact allowlisted safe output: proves the rendered string is
    // *precisely* PendingIncomingSyncBatch's own categorical/count/boolean
    // summary -- the structural braces here are the safe map-literal
    // formatting this summary always produces, never evidence of the
    // JSON-like payload leaking.
    expect(
      rendered,
      'PendingIncomingSyncBatch({incomingKeptCount: 0, '
      'incomingSyncStateCount: 0, hasBaseDataEpoch: true, '
      'hasPreviousCheckpoint: true, hasPendingCheckpoint: true})',
    );
    expect(batch.toLogSafeSummary()['hasBaseDataEpoch'], isTrue);
    expect(batch.toLogSafeSummary()['hasPreviousCheckpoint'], isTrue);
    expect(batch.toLogSafeSummary()['hasPendingCheckpoint'], isTrue);
  });

  test(
      '9c. Build 26 Phase 4E-3a: incomingKeptWisdomRecordSystemFields '
      'defaults to empty, accepts a real value, and is unmodifiable', () {
    final defaultBatch = PendingIncomingSyncBatch(
      accountFingerprint: fingerprintA,
      baseDataEpoch: epoch,
      previousServerChangeToken: null,
      pendingServerChangeToken: 'dG9rZW4=',
      incomingKeptWisdomProjections: const [],
      incomingSyncStateProjections: const [],
    );
    expect(defaultBatch.incomingKeptWisdomRecordSystemFields, isEmpty);

    final populatedBatch = PendingIncomingSyncBatch(
      accountFingerprint: fingerprintA,
      baseDataEpoch: epoch,
      previousServerChangeToken: null,
      pendingServerChangeToken: 'dG9rZW4=',
      incomingKeptWisdomProjections: const [],
      incomingSyncStateProjections: const [],
      incomingKeptWisdomRecordSystemFields: const {
        'east-kept-aaaaaaaa-1111-4111-8111-111111111111': 'c3lzdGVtRmllbGRz',
      },
    );
    expect(
      populatedBatch.incomingKeptWisdomRecordSystemFields[
          'east-kept-aaaaaaaa-1111-4111-8111-111111111111'],
      'c3lzdGVtRmllbGRz',
    );
    expect(
      () => populatedBatch.incomingKeptWisdomRecordSystemFields['x'] = 'y',
      throwsUnsupportedError,
    );
  });

  // ---------------------------------------------------------------------
  // 13. constructing/returning the batch is a pure in-memory operation --
  //     no persistence mutation occurs merely because a batch with a full
  //     set of scope fields and incoming projections was built and
  //     returned.
  // ---------------------------------------------------------------------
  test(
      '13. no persistence mutation occurs merely from constructing and '
      'returning a fully-populated pending incoming batch', () async {
    final recordingStore = _RecordingSyncPersistenceStore(buildStore());
    final incoming =
        activeProjection(revealId: 'aaaaaaaa-1111-4111-8111-111111111111');
    final bridge = _FakeCloudKitPlatformBridge();
    bridge.accountSnapshotSequence = [availableSnapshot()];
    bridge.zoneConfigurationProvider = () => successZoneResult;
    bridge.fetchProvider = (_) => CloudKitZoneChangesResult.success(
          changedKeptWisdomRecords: [incoming],
          changedSyncStateRecords: const [],
          serverToken: 'bmV3dG9rZW4=',
        );
    final orchestrator =
        SyncOrchestrator(bridge: bridge, persistenceStore: recordingStore);

    final result = await orchestrator.runSyncPass();

    expect(result.status, SyncPassStatus.completed);
    expect(result.pendingIncomingBatch!.accountFingerprint, fingerprintA);
    expect(
      result.pendingIncomingBatch!.incomingKeptWisdomProjections,
      hasLength(1),
    );
    // No-bucket account: only the read-only loadAccountState call ever
    // happens; every persistence-*mutating* method remains uncalled.
    expect(recordingStore.replaceAccountStateCallCount, 0);
    expect(recordingStore.enqueueMutationCallCount, 0);
    expect(recordingStore.applyMutationOutcomesCallCount, 0);
    expect(recordingStore.replaceRecordSystemFieldsCallCount, 0);
    expect(recordingStore.storeServerChangeTokenCallCount, 0);
    expect(recordingStore.clearServerChangeTokenCallCount, 0);
    expect(recordingStore.clearAccountStateCallCount, 0);
    expect(recordingStore.quarantineAccountStateCallCount, 0);
  });

  // ---------------------------------------------------------------------
  // Upload-outcome durability audit: system fields are persisted before
  // acknowledgment is committed, and a failure at either step stops the
  // pass before any fetch.
  // ---------------------------------------------------------------------
  test(
      'a successful save persists its returned system fields before the '
      'mutationId is acknowledged', () async {
    final recordingStore = _RecordingSyncPersistenceStore(buildStore());
    const revealId = 'aaaaaaaa-1111-4111-8111-111111111111';
    await recordingStore.enqueueMutation(
      fingerprintA,
      createChangeFor(revealId),
    );
    recordingStore.callOrder.clear(); // ignore setup's own enqueue call.

    final bridge = _FakeCloudKitPlatformBridge();
    bridge.accountSnapshotSequence = [availableSnapshot()];
    bridge.zoneConfigurationProvider = () => successZoneResult;
    bridge.modifyProvider = (_) => CloudKitModifyRecordsResult.allSucceeded([
          CloudKitRecordModifyOutcome.success(
            recordName: 'east-kept-$revealId',
            systemFields: 'c3lzdGVtZmllbGRz',
          ),
        ]);
    bridge.fetchProvider = (_) => CloudKitZoneChangesResult.success(
          changedKeptWisdomRecords: const [],
          changedSyncStateRecords: const [],
          serverToken: 'bmV3dG9rZW4=',
        );
    final orchestrator =
        SyncOrchestrator(bridge: bridge, persistenceStore: recordingStore);

    await orchestrator.runSyncPass();

    final systemFieldsIndex =
        recordingStore.callOrder.indexOf('replaceRecordSystemFields');
    final ackIndex = recordingStore.callOrder.indexOf('applyMutationOutcomes');
    expect(systemFieldsIndex, greaterThanOrEqualTo(0));
    expect(ackIndex, greaterThan(systemFieldsIndex));
    expect(recordingStore.replaceRecordSystemFieldsCallCount, 1);
    expect(recordingStore.applyMutationOutcomesCallCount, 1);
  });

  test(
      'if persisting returned system fields fails, the mutation remains '
      'queued and the pass never reaches fetch', () async {
    final recordingStore = _RecordingSyncPersistenceStore(buildStore());
    const revealId = 'aaaaaaaa-1111-4111-8111-111111111111';
    await recordingStore.enqueueMutation(
      fingerprintA,
      createChangeFor(revealId),
    );
    recordingStore.throwOnNextReplaceRecordSystemFields =
        const SyncPersistenceStoreException(
      'test-injected',
      'Simulated system-fields persistence failure.',
    );

    final bridge = _FakeCloudKitPlatformBridge();
    bridge.accountSnapshotSequence = [availableSnapshot()];
    bridge.zoneConfigurationProvider = () => successZoneResult;
    bridge.modifyProvider = (_) => CloudKitModifyRecordsResult.allSucceeded([
          CloudKitRecordModifyOutcome.success(
            recordName: 'east-kept-$revealId',
            systemFields: 'c3lzdGVtZmllbGRz',
          ),
        ]);
    bridge.fetchProvider = (_) => CloudKitZoneChangesResult.success(
          changedKeptWisdomRecords: const [],
          changedSyncStateRecords: const [],
          serverToken: 'bmV3dG9rZW4=',
        );
    final orchestrator =
        SyncOrchestrator(bridge: bridge, persistenceStore: recordingStore);

    final result = await orchestrator.runSyncPass();

    expect(result.status, SyncPassStatus.persistenceFailure);
    expect(recordingStore.applyMutationOutcomesCallCount, 0);
    expect(bridge.fetchPrivateZoneChangesCallCount, 0);
    final pending = await recordingStore.readPendingMutations(fingerprintA);
    expect(pending, hasLength(1));
    expect(pending.single.status, PersistedOutboxMutationStatus.pending);
  });

  test(
      'if acknowledgment fails after system fields already persisted, the '
      'mutation remains queued with its new system fields, and the pass '
      'never reaches fetch', () async {
    final recordingStore = _RecordingSyncPersistenceStore(buildStore());
    const revealId = 'aaaaaaaa-1111-4111-8111-111111111111';
    await recordingStore.enqueueMutation(
      fingerprintA,
      createChangeFor(revealId),
    );
    recordingStore.throwOnNextApplyMutationOutcomes =
        const SyncPersistenceStoreException(
      'test-injected',
      'Simulated acknowledgment failure.',
    );

    final bridge = _FakeCloudKitPlatformBridge();
    bridge.accountSnapshotSequence = [availableSnapshot()];
    bridge.zoneConfigurationProvider = () => successZoneResult;
    bridge.modifyProvider = (_) => CloudKitModifyRecordsResult.allSucceeded([
          CloudKitRecordModifyOutcome.success(
            recordName: 'east-kept-$revealId',
            systemFields: 'c3lzdGVtZmllbGRz',
          ),
        ]);
    bridge.fetchProvider = (_) => CloudKitZoneChangesResult.success(
          changedKeptWisdomRecords: const [],
          changedSyncStateRecords: const [],
          serverToken: 'bmV3dG9rZW4=',
        );
    final orchestrator =
        SyncOrchestrator(bridge: bridge, persistenceStore: recordingStore);

    final result = await orchestrator.runSyncPass();

    expect(result.status, SyncPassStatus.persistenceFailure);
    expect(bridge.fetchPrivateZoneChangesCallCount, 0);
    // The mutation remains queued...
    final pending = await recordingStore.readPendingMutations(fingerprintA);
    expect(pending, hasLength(1));
    expect(pending.single.status, PersistedOutboxMutationStatus.pending);
    // ...but its system fields already landed durably, from the step that
    // ran before the (failed) acknowledgment attempt -- so a future
    // upload retry for this record is conflict-safe and idempotent.
    final bucket = await recordingStore.loadAccountState(fingerprintA);
    expect(
      bucket!.recordSystemFields['east-kept-$revealId'],
      'c3lzdGVtZmllbGRz',
    );
  });

  // ---------------------------------------------------------------------
  // Build 26 Phase 4E-3a: fetched system fields are plumbed straight
  // through into PendingIncomingSyncBatch, with no other behavior change.
  // ---------------------------------------------------------------------
  group('Build 26 Phase 4E-3a: fetched system fields transport plumbing', () {
    test(
        'a successful fetch carries the exact recordName-to-systemFields '
        'association into PendingIncomingSyncBatch, for active and '
        'soft-tombstone records alike', () async {
      final store = buildStore();
      final bridge = _FakeCloudKitPlatformBridge();
      bridge.accountSnapshotSequence = [availableSnapshot()];
      bridge.zoneConfigurationProvider = () => successZoneResult;
      bridge.modifyProvider =
          (_) => CloudKitModifyRecordsResult.allSucceeded(const []);

      const activeRevealId = 'aaaaaaaa-1111-4111-8111-111111111111';
      const tombstoneRevealId = 'bbbbbbbb-2222-4222-8222-222222222222';
      final activeRecordName = 'east-kept-$activeRevealId';
      final tombstoneRecordName = 'east-kept-$tombstoneRevealId';
      const activeSystemFields = 'YWN0aXZlU3lzdGVtRmllbGRz';
      const tombstoneSystemFields = 'dG9tYnN0b25lU3lzdGVtRmllbGRz';

      final active = activeProjection(revealId: activeRevealId);
      final tombstone = CloudKeptWisdomProjection.tombstone(
        SyncTombstone(
          revealId: tombstoneRevealId,
          dataEpoch: epoch,
          updatedAt: DateTime.utc(2026, 8, 1, 11),
          deletedAt: DateTime.utc(2026, 8, 1, 11),
          mutationId: _mutationIdFor(tombstoneRevealId),
        ),
      );

      bridge.fetchProvider = (_) => CloudKitZoneChangesResult.success(
            changedKeptWisdomRecords: [active, tombstone],
            changedSyncStateRecords: const [],
            serverToken: 'bmV3dG9rZW4=',
            keptWisdomRecordSystemFields: {
              activeRecordName: activeSystemFields,
              tombstoneRecordName: tombstoneSystemFields,
            },
          );
      final orchestrator =
          SyncOrchestrator(bridge: bridge, persistenceStore: store);

      final result = await orchestrator.runSyncPass();

      expect(result.status, SyncPassStatus.completed);
      final batch = result.pendingIncomingBatch;
      expect(batch, isNotNull);
      // Existing projections/account/epoch/token behavior is unaffected --
      // this phase adds a new field, it does not change any existing one.
      expect(batch!.incomingKeptWisdomProjections, hasLength(2));
      expect(batch.accountFingerprint, fingerprintA);
      expect(batch.baseDataEpoch, isNull);
      expect(batch.pendingServerChangeToken, 'bmV3dG9rZW4=');

      expect(
        batch.incomingKeptWisdomRecordSystemFields[activeRecordName],
        activeSystemFields,
      );
      expect(
        batch.incomingKeptWisdomRecordSystemFields[tombstoneRecordName],
        tombstoneSystemFields,
      );
      expect(batch.incomingKeptWisdomRecordSystemFields, hasLength(2));

      // Build 26 Phase 4E-3a is transport-only: no checkpoint is performed
      // and no persistence mutation results from merely carrying this new
      // metadata through -- the account bucket's own durable
      // recordSystemFields (a wholly separate, already-existing concept
      // populated only by a successful *upload*) remains untouched.
      final persistedBucket = await store.loadAccountState(fingerprintA);
      expect(persistedBucket, isNull);
    });

    test(
        'keptWisdomRecordSystemFields is never rendered by SyncPassResult or '
        'PendingIncomingSyncBatch diagnostics', () async {
      final store = buildStore();
      final bridge = _FakeCloudKitPlatformBridge();
      bridge.accountSnapshotSequence = [availableSnapshot()];
      bridge.zoneConfigurationProvider = () => successZoneResult;
      bridge.modifyProvider =
          (_) => CloudKitModifyRecordsResult.allSucceeded(const []);

      const revealIdHere = 'cccccccc-3333-4333-8333-333333333333';
      const secretSystemFields = 'dGhpc0lzQVNlY3JldFN5c3RlbUZpZWxkc1ZhbHVl';
      final recordName = 'east-kept-$revealIdHere';

      bridge.fetchProvider = (_) => CloudKitZoneChangesResult.success(
            changedKeptWisdomRecords: [
              activeProjection(revealId: revealIdHere),
            ],
            changedSyncStateRecords: const [],
            serverToken: 'bmV3dG9rZW4=',
            keptWisdomRecordSystemFields: {recordName: secretSystemFields},
          );
      final orchestrator =
          SyncOrchestrator(bridge: bridge, persistenceStore: store);

      final result = await orchestrator.runSyncPass();
      expect(result.status, SyncPassStatus.completed);

      expect(result.toString(), isNot(contains(secretSystemFields)));
      expect(
        result.toLogSafeSummary().values.map((v) => v.toString()),
        isNot(contains(secretSystemFields)),
      );
      final batch = result.pendingIncomingBatch!;
      expect(batch.toString(), isNot(contains(secretSystemFields)));
      expect(
        batch.toLogSafeSummary().values.map((v) => v.toString()),
        isNot(contains(secretSystemFields)),
      );
    });
  });
}

/// Derives a deterministic, always-canonical (v4-shaped) mutationId from
/// [revealId] for test fixtures only: keeps every group after the first
/// (which is exactly where the version/variant nibbles already live) and
/// only replaces the leading group with a fixed literal distinct from any
/// revealId literal this file uses -- guaranteed to remain a valid
/// `isCanonicalUuidV4OrV5` shape without re-deriving version/variant
/// nibbles by hand.
String _mutationIdFor(String revealId) => 'eeeeeeee${revealId.substring(8)}';
