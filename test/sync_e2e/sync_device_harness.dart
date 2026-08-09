/// Build 26 Phase 4E-5: the per-device CloudKit bridge adapter (Section C)
/// and the [SyncDeviceHarness] that composes REAL production coordinators
/// (Section D/E) into one independent simulated device.
///
/// Every non-CloudKit-bridge collaborator a [SyncDeviceHarness] owns is a
/// completely independent instance per device -- its own [KeptRepository],
/// its own Kept state store, its own [LocalSyncIntentStore],
/// its own [SyncPersistenceStore], its own account/bootstrap bucket state,
/// and its own integration [PersistenceOperationCoordinator] -- so Device
/// A's integration lock is never shared with Device B's. Within one device,
/// the SAME `PersistenceOperationCoordinator` instance is injected into
/// [KeptSyncIntegrationCoordinator], [IncomingKeptSyncCoordinator], and
/// [KeptSyncBootstrapCoordinator], matching production's own composition in
/// `lib/services/app_services.dart` exactly (all three share the
/// `kept_sync_integration_v1` resource key).
///
/// Every sync-capable operation this harness exposes is a thin, direct
/// pass-through to a REAL production coordinator method -- never a
/// reimplementation of any sync rule, and never a shortcut around
/// `SyncOrchestrator`/`IncomingKeptSyncCoordinator`/
/// `KeptSyncBootstrapCoordinator`. Because Phase 4F's automatic sync
/// triggering does not exist yet, [runOutgoingAndIncomingSync] performs the
/// explicit multi-step composition a future automatic trigger will
/// eventually perform on its own: promote any pending local intents into
/// the durable outbox
/// (`KeptSyncIntegrationCoordinator.reconcileForAssociatedAccount` --
/// necessary because that coordinator's own `record*` methods only ever
/// advance an intent to `localCommittedOutboxPending`, never enqueue it
/// themselves), run one real `SyncOrchestrator.runSyncPass()`, then, only if
/// that pass returned a pending incoming batch, apply it through one real
/// `IncomingKeptSyncCoordinator.applyIncomingBatch(...)` call.
library;

import 'dart:async';

import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/models/kept_bootstrap_result.dart';
import 'package:wisdom_app/models/kept_record.dart';
import 'package:wisdom_app/models/kept_state_envelope.dart';
import 'package:wisdom_app/persistence/persistence_operation_coordinator.dart';
import 'package:wisdom_app/repositories/kept_repository.dart';
import 'package:wisdom_app/sync_integration/incoming_kept_sync_coordinator.dart';
import 'package:wisdom_app/sync_integration/kept_sync_bootstrap_coordinator.dart';
import 'package:wisdom_app/sync_integration/kept_sync_integration_coordinator.dart';
import 'package:wisdom_app/sync_orchestration/sync_pass_result.dart';
import 'package:wisdom_app/sync_orchestration/sync_orchestrator.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_account_change_event.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_account_snapshot.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_bridge_info.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_modify_records_contract.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_platform_bridge.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_zone_changes_contract.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_zone_configuration_result.dart';

import '../persistence_test_helpers.dart';
import '../sync_integration/in_memory_sync_test_doubles.dart';
import 'synthetic_cloudkit_server.dart';

/// Section C: one simulated device's own [CloudKitPlatformBridge] adapter,
/// pointing at a SHARED [SyntheticCloudKitServer] instance. The server is
/// shared across every device signed into the same synthetic account; every
/// field on this class (current account fingerprint, hold-completers, call
/// counters) is per-device, never shared.
class E2ECloudKitPlatformBridge implements CloudKitPlatformBridge {
  E2ECloudKitPlatformBridge({required this.server});

  final SyntheticCloudKitServer server;

  /// `null` means "no iCloud account signed in on this simulated device."
  /// Deliberately mutable so a test can simulate an account switch
  /// (scenario 17) by changing it directly.
  String? currentFingerprint;

  /// Deterministic, Completer-controlled holds -- only where a concurrency
  /// scenario needs them (scenario 16). `null` (the default) means "resolve
  /// immediately," matching every other scenario's ordinary, un-held path.
  Completer<void>? holdFetchUntil;
  Completer<void>? holdModifyUntil;

  int getAccountSnapshotCallCount = 0;
  int configurePrivateZoneCallCount = 0;
  int modifyPrivateRecordsCallCount = 0;
  int fetchPrivateZoneChangesCallCount = 0;

  @override
  Future<CloudKitAccountSnapshot> getAccountSnapshot() async {
    getAccountSnapshotCallCount += 1;
    final fingerprint = currentFingerprint;
    if (fingerprint == null) {
      return const CloudKitAccountSnapshot(
        availability: CloudKitAccountAvailability.noAccount,
        isPrivateDatabaseUsable: false,
        accountFingerprint: null,
        fingerprintResolved: false,
        bridgeVersion: 1,
      );
    }
    return CloudKitAccountSnapshot(
      availability: CloudKitAccountAvailability.available,
      isPrivateDatabaseUsable: true,
      accountFingerprint: fingerprint,
      fingerprintResolved: true,
      bridgeVersion: 1,
    );
  }

  @override
  Future<CloudKitZoneConfigurationResult> configurePrivateZone() async {
    configurePrivateZoneCallCount += 1;
    return const CloudKitZoneConfigurationResult(
      success: true,
      zoneCreated: false,
      zoneAlreadyExisted: true,
      accountAvailability: CloudKitAccountAvailability.available,
    );
  }

  @override
  Future<CloudKitBridgeInfo> getBridgeInfo() =>
      throw UnimplementedError('Not used by the Phase 4E-5 E2E harness.');

  @override
  Stream<CloudKitAccountChangeEvent> get accountChangeEvents =>
      const Stream.empty();

  @override
  Future<CloudKitModifyRecordsResult> modifyPrivateRecords(
    CloudKitModifyRecordsRequest request,
  ) async {
    modifyPrivateRecordsCallCount += 1;
    final hold = holdModifyUntil;
    if (hold != null) await hold.future;
    return server.modify(request);
  }

  @override
  Future<CloudKitZoneChangesResult> fetchPrivateZoneChanges(
    CloudKitZoneChangesRequest request,
  ) async {
    fetchPrivateZoneChangesCallCount += 1;
    final hold = holdFetchUntil;
    if (hold != null) await hold.future;
    return server.fetch(request);
  }
}

/// The combined, content-safe result of [SyncDeviceHarness
/// .runOutgoingAndIncomingSync] -- both real production results, exactly as
/// they were returned, with no reinterpretation.
class SyncCycleResult {
  const SyncCycleResult({required this.syncPassResult, this.applyResult});

  final SyncPassResult syncPassResult;
  final IncomingApplyResult? applyResult;
}

/// Section D: one independent simulated device. See the library doc comment
/// for the full composition/locking contract.
class SyncDeviceHarness {
  SyncDeviceHarness({
    required this.deviceLabel,
    required SyntheticCloudKitServer server,
    KeptBootstrapResult bootstrap = const KeptBootstrapResult.ready(),
    int freeKeptLimit = 3,
    int freeReflectionLimit = 3,
    String Function()? idFactory,
    DateTime Function()? clock,
  })  : keptStore = InMemoryKeptStateStore(),
        intentStore = InMemoryLocalSyncIntentStore(),
        syncPersistenceStore = InMemorySyncPersistenceStore(),
        bridge = E2ECloudKitPlatformBridge(server: server),
        _integrationCoordinator = PersistenceOperationCoordinator() {
    keptRepository = KeptRepository(
      store: keptStore,
      bootstrap: bootstrap,
      operationCoordinator: PersistenceOperationCoordinator(),
      idFactory: idFactory,
      clock: clock,
      freeKeptLimit: freeKeptLimit,
      freeReflectionLimit: freeReflectionLimit,
    );
    // Build 26 Phase 4E-5 (Section D): the same integration coordinator
    // instance is injected into all three -- matching
    // `lib/services/app_services.dart`'s own production wiring, never a
    // per-coordinator private lock.
    syncCoordinator = KeptSyncIntegrationCoordinator(
      keptRepository: keptRepository,
      intentStore: intentStore,
      syncPersistenceStore: syncPersistenceStore,
      integrationCoordinator: _integrationCoordinator,
      idFactory: idFactory,
      clock: clock,
    );
    incomingCoordinator = IncomingKeptSyncCoordinator(
      keptRepository: keptRepository,
      intentStore: intentStore,
      syncPersistenceStore: syncPersistenceStore,
      integrationCoordinator: _integrationCoordinator,
    );
    bootstrapCoordinator = KeptSyncBootstrapCoordinator(
      bridge: bridge,
      keptRepository: keptRepository,
      intentStore: intentStore,
      syncPersistenceStore: syncPersistenceStore,
      integrationCoordinator: _integrationCoordinator,
      idFactory: idFactory,
      clock: clock,
    );
    orchestrator = SyncOrchestrator(
      bridge: bridge,
      persistenceStore: syncPersistenceStore,
    );
  }

  /// A human-readable label for test failure messages only (e.g. `'A'`,
  /// `'B'`) -- never used as any kind of identity by production code.
  final String deviceLabel;

  final InMemoryKeptStateStore keptStore;
  final InMemoryLocalSyncIntentStore intentStore;
  final InMemorySyncPersistenceStore syncPersistenceStore;
  final E2ECloudKitPlatformBridge bridge;
  final PersistenceOperationCoordinator _integrationCoordinator;

  late final KeptRepository keptRepository;
  late final KeptSyncIntegrationCoordinator syncCoordinator;
  late final IncomingKeptSyncCoordinator incomingCoordinator;
  late final KeptSyncBootstrapCoordinator bootstrapCoordinator;
  late final SyncOrchestrator orchestrator;

  // -----------------------------------------------------------------------
  // Account / bootstrap.
  // -----------------------------------------------------------------------

  /// Sets (or clears, via `null`) this device's current synthetic iCloud
  /// account fingerprint -- the only way this harness ever changes account
  /// identity. Never touches any durable local state by itself.
  void setAccountFingerprint(String? fingerprint) {
    bridge.currentFingerprint = fingerprint;
  }

  String? get accountFingerprint => bridge.currentFingerprint;

  Future<AssociationEvaluation> evaluateAssociation() =>
      bootstrapCoordinator.evaluateAssociation();

  Future<AssociationAuthorizationResult> authorizeAssociation(
    String fingerprint,
  ) =>
      bootstrapCoordinator.authorizeAssociation(fingerprint: fingerprint);

  /// Runs (or resumes) this device's real bootstrap sequence -- the one and
  /// only path this harness ever uses to establish/advance association,
  /// fetch the remote baseline, and reconcile local history. Never
  /// shortcut; always the real `KeptSyncBootstrapCoordinator.runBootstrap`.
  Future<BootstrapRunResult> bootstrap() => bootstrapCoordinator.runBootstrap();

  // -----------------------------------------------------------------------
  // User mutations -- thin, direct pass-throughs to the real
  // KeptSyncIntegrationCoordinator. No business rule is duplicated here.
  // -----------------------------------------------------------------------

  Future<KeptRepositoryMutationResult> keep({
    required String revealId,
    required String wisdomText,
    required DateTime revealedAt,
    bool isKeeper = false,
  }) =>
      syncCoordinator.recordKeep(
        revealId: revealId,
        wisdomText: wisdomText,
        revealedAt: revealedAt,
        isKeeper: isKeeper,
      );

  Future<KeptRepositoryMutationResult> saveReflection({
    required String itemId,
    required String reflection,
    bool isKeeper = false,
    DateTime? reflectedAt,
  }) =>
      syncCoordinator.recordReflectionSave(
        itemId: itemId,
        reflection: reflection,
        isKeeper: isKeeper,
        reflectedAt: reflectedAt,
      );

  Future<List<FavoriteItem>> deleteReflection({required String itemId}) =>
      syncCoordinator.recordReflectionDelete(itemId: itemId);

  Future<RemovedKeptOccurrence?> remove({required String itemId}) =>
      syncCoordinator.recordRemove(itemId: itemId);

  // -----------------------------------------------------------------------
  // Section E: sync-pass composition. Explicit, deterministic steps only --
  // Phase 4F's automatic triggering does not exist yet.
  // -----------------------------------------------------------------------

  /// Promotes every currently durable local intent one step closer to (and,
  /// for an account bucket already `complete`, all the way into) the
  /// durable outbox -- the real
  /// `KeptSyncIntegrationCoordinator.reconcileForAssociatedAccount`. A no-op
  /// if this device has no current account fingerprint.
  Future<void> reconcileOutbox() async {
    final fingerprint = bridge.currentFingerprint;
    if (fingerprint == null) return;
    await syncCoordinator.reconcileForAssociatedAccount(
      AssociatedSyncAccountContext(accountFingerprint: fingerprint),
    );
  }

  /// Runs exactly one real `SyncOrchestrator.runSyncPass()` -- uploads the
  /// current outbox, then fetches incoming changes. Never applies the
  /// returned batch itself.
  Future<SyncPassResult> runSyncPassOnly() => orchestrator.runSyncPass();

  /// Applies [result]'s pending incoming batch, if any, through the real
  /// `IncomingKeptSyncCoordinator.applyIncomingBatch`. Returns `null` when
  /// [result] carried no batch (every non-`completed` status, or a
  /// `completed` pass with nothing to fetch does still carry an -- possibly
  /// empty -- batch; only a failure/unavailable/etc. status carries `null`).
  Future<IncomingApplyResult?> applyBatchIfPresent(
    SyncPassResult result,
  ) async {
    final batch = result.pendingIncomingBatch;
    if (batch == null) return null;
    return incomingCoordinator.applyIncomingBatch(batch);
  }

  /// The full explicit outgoing-then-incoming sync composition a future
  /// Phase 4F automatic trigger will eventually perform on its own: 1.
  /// promote pending local intents into the outbox, 2. run one real sync
  /// pass, 3. apply its pending incoming batch (if any) through the real
  /// incoming coordinator. Every step is a real production API call; no
  /// step here duplicates any sync rule.
  Future<SyncCycleResult> runOutgoingAndIncomingSync() async {
    await reconcileOutbox();
    final syncResult = await runSyncPassOnly();
    final applyResult = await applyBatchIfPresent(syncResult);
    return SyncCycleResult(
        syncPassResult: syncResult, applyResult: applyResult);
  }

  // -----------------------------------------------------------------------
  // Read-only inspection helpers -- real production read APIs only.
  // -----------------------------------------------------------------------

  /// The complete, currently active protected-domain [KeptRecord]
  /// collection -- the real `KeptRepository.loadAllRecords`, used here only
  /// for test assertions, never to bypass any mutation path.
  Future<List<KeptRecord>> loadAllRecords() => keptRepository.loadAllRecords();

  /// Seeds this device's local Kept history directly -- for scenarios 13/14
  /// only, which require a device to already have local history BEFORE its
  /// first bootstrap/association ever runs (something no real mutation path
  /// can produce, since every real mutation requires an already-resolved
  /// account). Never used once a device has already bootstrapped.
  void seedLocalHistory(List<KeptRecord> records) {
    keptStore.envelope = KeptStateEnvelope(activeRecords: records);
  }
}
