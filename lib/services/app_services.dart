import '../controllers/ritual_sound_preference_controller.dart';
import 'dart:async';

import '../controllers/icloud_removal_controller.dart';
import '../controllers/sync_association_controller.dart';
import '../persistence/persistence_operation_coordinator.dart';
import '../persistence/protected_file_kept_state_store.dart';
import '../persistence/protected_kept_migration_artifact_store.dart';
import '../persistence/kept_migration_journal_store.dart';
import '../persistence/legacy_favorites_store.dart';
import '../persistence/storage_preferences_adapter.dart';
import '../repositories/daily_access_repository.dart';
import '../repositories/kept_repository.dart';
import '../sync_diagnostics/sync_health_evaluator.dart';
import '../sync_diagnostics/sync_recovery_coordinator.dart';
import '../sync_integration/incoming_kept_sync_coordinator.dart';
import '../sync_integration/kept_sync_bootstrap_coordinator.dart';
import '../sync_integration/kept_sync_integration_coordinator.dart';
import '../sync_integration/protected_local_sync_intent_store.dart';
import '../sync_orchestration/sync_orchestrator.dart';
import '../sync_persistence/protected_sync_persistence_store.dart';
import '../sync_platform/method_channel_cloud_kit_platform_bridge.dart';
import '../sync_runtime/cloud_kit_sync_runtime_coordinator.dart';
import 'analytics_service.dart';
import 'daily_wisdom_access_service.dart';
import 'daily_ritual_authority.dart';
import 'data_export_service.dart';
import 'journal_owner_service.dart';
import 'keeper_ritual_widget_service.dart';
import 'kept_discovery_hint_service.dart';
import 'kept_migration_coordinator.dart';
import 'kept_state_revision_notifier.dart';
import 'kept_storage_bootstrap.dart';
import 'purchase_service.dart';
import 'production_diagnostics_service.dart';
import 'rating_request_service.dart';
import 'saved_reflections_service.dart';
import 'widget_snapshot_service.dart';
import 'wisdom_notification_service.dart';
import 'wisdom_share_service.dart';

final ritualSoundPreferenceController = RitualSoundPreferenceController();

final AnalyticsService analyticsService = AnalyticsService();
final PurchaseService purchaseService = PurchaseService(
  analyticsService: analyticsService,
);
final WisdomShareHandler wisdomShareService = WisdomShareService();
final WisdomNotificationService wisdomNotificationService =
    WisdomNotificationService();
final RatingRequestService ratingRequestService = RatingRequestService();
final WidgetSnapshotService widgetSnapshotService = WidgetSnapshotService();
final KeeperRitualWidgetService keeperRitualWidgetService =
    KeeperRitualWidgetService();
final JournalOwnerService journalOwnerService = JournalOwnerService();
final ProductionDiagnosticsService productionDiagnosticsService =
    ProductionDiagnosticsService();

/// Free-for-everyone user data export. `savedReflectionsServiceProvider` is
/// a closure over the `late final savedReflectionsService` global declared
/// further below -- this line runs before that field is ever assigned
/// (bootstrap happens later, in `initializeKeptStorage()`), so the closure
/// must not be *invoked* here, only captured. By the time
/// `dataExportService.exportAndShare()` actually calls it, bootstrap has
/// long since completed -- exactly the same pattern already used for this
/// file's own `onMutationCommitted` callbacks below.
final DataExportService dataExportService = DataExportService(
  savedReflectionsServiceProvider: () => savedReflectionsService,
  journalOwnerService: journalOwnerService,
);
final KeptDiscoveryHintService keptDiscoveryHintService =
    KeptDiscoveryHintService();

/// Build 26 Phase 4H-6: the one production [KeptStateRevisionNotifier]
/// instance. Constructed eagerly (mirrors [purchaseService]/
/// [wisdomNotificationService] above -- no I/O, no dependency on Kept
/// storage bootstrap), so a screen may safely add/remove a listener from
/// its own `initState`/`dispose` even before [initializeKeptStorage]
/// completes. Wired below, inside `buildService`, as
/// [IncomingKeptSyncCoordinator]'s `onIncomingStateChanged` callback --
/// never referenced by name from `lib/sync_integration/` itself (see that
/// class's own field doc comment).
final KeptStateRevisionNotifier keptStateRevisionNotifier =
    KeptStateRevisionNotifier();

final StoragePreferencesAdapter dailyAccessPreferencesAdapter =
    StoragePreferencesAdapter();
final PersistenceOperationCoordinator dailyAccessOperationCoordinator =
    PersistenceOperationCoordinator();
final DailyAccessRepository dailyAccessRepository = DailyAccessRepository(
  preferencesAdapter: dailyAccessPreferencesAdapter,
  operationCoordinator: dailyAccessOperationCoordinator,
);

DailyWisdomAccessService createDailyWisdomAccessService({
  WisdomClock? clock,
  Duration statusTimeout = DailyWisdomAccessService.defaultStatusTimeout,
}) {
  return DailyWisdomAccessService(
    repository: dailyAccessRepository,
    clock: clock,
    statusTimeout: statusTimeout,
    authority: const MethodChannelDailyRitualAuthority(),
  );
}

/// Narrow read-only presentation seam for surfaces such as Settings that
/// need to reconcile an optional reminder without owning the daily-access
/// service or mutating ritual cadence.
Future<DailyWisdomStatus> readDailyWisdomStatus() {
  return createDailyWisdomAccessService().status();
}

// ---------------------------------------------------------------------
// Protected Kept storage bootstrap (Build 26 Phase 3D-C production cutover).
//
// `main()` gives initializeKeptStorage() to BootstrapGate, which never builds
// WisdomApp until this Future completes, so the `late final` service below
// is populated before any screen can ever read `savedReflectionsService`.
// Idempotent: concurrent or
// repeated calls all await the exact same single underlying bootstrap
// attempt — migration never runs twice, and the bootstrap result is never
// remapped a second time.
//
// This performs exactly one migration attempt
// (`KeptMigrationCoordinator.migrateIfNeeded`) and maps its outcome to a
// content-safe `KeptBootstrapResult`:
//   * every successful `KeptMigrationResult` status (`noLegacyData`,
//     `alreadyProtected`, `migrated`, `alreadyComplete`) maps to
//     `KeptBootstrapResult.ready()`;
//   * a thrown `KeptMigrationException` maps to
///    `KeptBootstrapResult.unavailable(exception.stage)`;
//   * any other thrown error maps to
//     `KeptBootstrapResult.unavailable('unknown')`.
// `KeptRepository` itself never calls migration and never re-derives this
// result — it is supplied once, here, at construction.
// ---------------------------------------------------------------------

final PersistenceOperationCoordinator keptOperationCoordinator =
    PersistenceOperationCoordinator();

// Constructed eagerly (exactly once each, on first access — ordinary Dart
// top-level `final` lazy-initialization) rather than inside the bootstrap
// function itself. Their own constructors do no I/O; only `migrateIfNeeded()`
// and the store's own `load()`/`replace()` touch disk, and those are only
// ever invoked from inside `initializeKeptStorage()` below.
final ProtectedFileKeptStateStore keptStateStore = ProtectedFileKeptStateStore(
  operationCoordinator: keptOperationCoordinator,
);
final KeptMigrationCoordinator keptMigrationCoordinator =
    KeptMigrationCoordinator(
  legacyFavoritesStore: SharedPreferencesLegacyFavoritesStore(),
  journalStore: SharedPreferencesKeptMigrationJournalStore(),
  artifactStore: ProtectedKeptMigrationArtifactStore(
    operationCoordinator: keptOperationCoordinator,
  ),
  keptStateStore: keptStateStore,
  operationCoordinator: keptOperationCoordinator,
);

// ---------------------------------------------------------------------
// Build 26 Phase 4E-2: sync integration wiring.
//
// `syncIntegrationOperationCoordinator` is a dedicated
// `PersistenceOperationCoordinator` instance used for exactly one resource
// key (`KeptSyncIntegrationCoordinator.resourceKey`,
// `kept_sync_integration_v1`) -- never shared with `keptOperationCoordinator`
// (KeptRepository's own `kept_repository_v1`) or with either durable sync
// store's own internal coordinator below. `localSyncIntentStore` and
// `syncPersistenceStore` are each constructed with no `operationCoordinator`
// argument, so each defaults to its own separate internal instance (per
// their own constructors) -- distinct directories/files
// (`east_sync_integration_state`, `east_sync_state`), distinct resource
// keys, distinct coordinator instances, exactly as required.
//
// No CloudKit/native account lookup and no reconciliation trigger is wired
// here or anywhere else in this file --
// `keptSyncIntegrationCoordinator.reconcileForAssociatedAccount` remains
// callable but uncalled by any production code path in this phase.
// ---------------------------------------------------------------------

final PersistenceOperationCoordinator syncIntegrationOperationCoordinator =
    PersistenceOperationCoordinator();
final ProtectedLocalSyncIntentStore localSyncIntentStore =
    ProtectedLocalSyncIntentStore();
final ProtectedSyncPersistenceStore syncPersistenceStore =
    ProtectedSyncPersistenceStore();

/// Populated exactly once, as a side effect of `buildService` below, inside
/// the same single bootstrap attempt that populates
/// [savedReflectionsService] — never constructed a second time. Exposed as
/// its own global so the explicit
/// account-association/bootstrap flow has a single, already-correctly-wired
/// instance to call [KeptSyncIntegrationCoordinator
/// .reconcileForAssociatedAccount] on; nothing in this phase calls it.
late final KeptSyncIntegrationCoordinator keptSyncIntegrationCoordinator;

/// Build 26 Phase 4E-3b: the production incoming-CloudKit-apply coordinator.
/// Populated in the same single bootstrap attempt, alongside
/// [keptSyncIntegrationCoordinator] — shares the exact same
/// [syncIntegrationOperationCoordinator] instance and resource key
/// (`kept_sync_integration_v1`), never a second, separately-constructed
/// integration coordinator, so an incoming apply and every outgoing user
/// mutation/reconciliation step always serialize against each other. Nothing
/// in this phase (or any production code path) calls
/// [IncomingKeptSyncCoordinator.applyIncomingBatch] automatically — Phase 4F
/// owns wiring an automatic trigger.
late final IncomingKeptSyncCoordinator incomingKeptSyncCoordinator;

/// Build 26 Phase 4E-4: the production existing-user remote-first
/// bootstrap/account-association/legacy-backfill coordinator. Populated in
/// the same single bootstrap attempt, alongside
/// [keptSyncIntegrationCoordinator] and [incomingKeptSyncCoordinator] --
/// shares the exact same [syncIntegrationOperationCoordinator] instance and
/// resource key (`kept_sync_integration_v1`), so bootstrap, every outgoing
/// user mutation, and every incoming-apply pass always serialize against
/// each other. `cloudKitPlatformBridge` below is the first production
/// construction of a [CloudKitPlatformBridge] anywhere in this app --
/// [SyncOrchestrator] has no production instance yet either. Nothing in this
/// phase (or any production code path) calls
/// [KeptSyncBootstrapCoordinator.evaluateAssociation],
/// [KeptSyncBootstrapCoordinator.authorizeAssociation],
/// [KeptSyncBootstrapCoordinator.repairLegacyAssociationMarker], or
/// [KeptSyncBootstrapCoordinator.runBootstrap] automatically -- Phase 4F
/// owns wiring an automatic trigger.
late final KeptSyncBootstrapCoordinator keptSyncBootstrapCoordinator;

/// See [keptSyncBootstrapCoordinator]'s doc comment. `const` -- the
/// method-channel bridge holds no mutable state of its own.
const MethodChannelCloudKitPlatformBridge cloudKitPlatformBridge =
    MethodChannelCloudKitPlatformBridge();

/// Build 26 Phase 4F: the first production [SyncOrchestrator] instance
/// anywhere in this app. Shares the exact same [cloudKitPlatformBridge] and
/// [syncPersistenceStore] instances every other sync coordinator above
/// already uses -- never a second, separately-constructed bridge or
/// persistence store. `SyncOrchestrator` has its own internal single-flight
/// de-dup and does not use [syncIntegrationOperationCoordinator] (it does not
/// touch `LocalSyncIntent`/Kept envelope state at all -- only the outbox/
/// server-token/system-fields state already owned by [syncPersistenceStore]
/// itself). Populated in the same single bootstrap attempt as the other
/// sync coordinators, alongside [cloudKitSyncRuntimeCoordinator] below.
late final SyncOrchestrator syncOrchestrator;

/// Build 26 Phase 4F: the one production runtime trigger/retry/lifecycle
/// coordinator. Constructed over the four real coordinators above (never a
/// second, separately-constructed coordinator graph) plus
/// [cloudKitPlatformBridge] directly (for `accountChangeEvents` -- see its
/// own doc comment for why this coordinator subscribes to that stream
/// itself rather than through any of the four coordinators, none of which
/// expose or consume it). `lib/main.dart` calls
/// [CloudKitSyncRuntimeCoordinator.requestSync] on startup and on
/// `AppLifecycleState.resumed`; the account-change subscription started in
/// this coordinator's own constructor is another production trigger. Build
/// 26 Phase 4F fast-follow: [keptSyncIntegrationCoordinator]'s
/// `onMutationCommitted` callback (wired below, inside this same
/// `buildService` closure) is the fourth production trigger -- it calls
/// [CloudKitSyncRuntimeCoordinator.requestSync] with
/// [SyncRuntimeTrigger.localMutation] exactly once per fresh,
/// successfully-committed Keep/Reflection-save/Reflection-delete/Remove
/// mutation, fire-and-forget, with any returned-future error contained.
/// This is the only place `SyncRuntimeTrigger` is referenced outside
/// `lib/sync_runtime/` itself -- [KeptSyncIntegrationCoordinator] never
/// imports `lib/sync_runtime/` and never learns this enum exists; it only
/// ever calls the plain, argument-free callback constructed here.
late final CloudKitSyncRuntimeCoordinator cloudKitSyncRuntimeCoordinator;

/// Build 26 Phase 4G: the Settings-facing explicit one-time iCloud
/// association surface (see `lib/controllers/sync_association_controller
/// .dart` for why it is named platform-neutrally rather than after
/// CloudKit). Populated in the same single bootstrap attempt as every other
/// sync coordinator above, alongside [cloudKitSyncRuntimeCoordinator] --
/// composes [keptSyncBootstrapCoordinator] with a fire-and-forget closure
/// over [cloudKitSyncRuntimeCoordinator] (the fourth `requestSync` call
/// site, alongside `lib/main.dart`'s startup/foreground triggers and this
/// coordinator's own retry/account-change triggers -- see
/// `test/sync_runtime/sync_runtime_layering_test.dart`'s structural proof of
/// exactly these call sites). `lib/screens/settings_screen.dart` is this
/// controller's only production caller; it never touches
/// `KeptSyncBootstrapCoordinator`, `CloudKitSyncRuntimeCoordinator`, or any
/// CloudKit type directly.
///
/// Deliberately **nullable**, never `late final`: unlike every other
/// sync-coordinator global above, this one is read directly from
/// `SettingsScreen`'s widget tree (via [SettingsScreen
/// .cloudKitAssociationController]'s fallback), and existing isolated
/// HomeScreen/SettingsScreen widget tests construct that UI without ever
/// calling [initializeKeptStorage] first. A `late final` field would throw
/// `LateInitializationError` the instant such a test mounts Settings. `null`
/// here means exactly "the composition root has not finished bootstrapping
/// yet" -- `SettingsScreen` treats that the same as any other
/// non-actionable state (row reads "Not enabled", never tappable), never as
/// proof that sync is disabled, and never by silently constructing a second,
/// disconnected controller or touching CloudKit/native infrastructure.
SyncAssociationController? cloudKitAssociationController;

/// Build 26 Phase 5 (final slice): the Settings-facing "Remove from iCloud"
/// surface (see `lib/controllers/icloud_removal_controller.dart` for why it
/// is named platform-neutrally rather than after CloudKit). Populated in the
/// same single bootstrap attempt as every other sync coordinator above,
/// alongside [cloudKitAssociationController] -- composes
/// [syncPersistenceStore] with a fire-and-forget closure over
/// [cloudKitSyncRuntimeCoordinator] (another `requestSync` call site,
/// alongside the ones `test/sync_runtime/sync_runtime_layering_test.dart`
/// already discloses). `lib/screens/settings_screen.dart` is this
/// controller's only production caller; it never touches
/// `CloudKitSyncRuntimeCoordinator`, `SyncPersistenceStore` directly, or any
/// CloudKit type.
///
/// Deliberately **nullable**, never `late final` -- mirrors
/// [cloudKitAssociationController]'s own identical reasoning exactly: it is
/// read directly from `SettingsScreen`'s widget tree, and existing isolated
/// Settings widget tests construct that UI without ever calling
/// [initializeKeptStorage] first. `null` here means exactly "the composition
/// root has not finished bootstrapping yet" -- `SettingsScreen` treats that
/// the same as any other non-actionable state (row reads "Nothing to
/// remove.", never tappable), never as proof there is nothing to remove, and
/// never by silently constructing a second, disconnected controller.
ICloudRemovalController? icloudRemovalController;

/// Build 26 (Sync Diagnostics / Safe Recovery core): the pure, read-only
/// health-classification composition over [keptSyncBootstrapCoordinator]'s/
/// [cloudKitSyncRuntimeCoordinator]'s own already-canonical state -- never a
/// new source of truth. Settings reads this evaluator directly to report the
/// real state; it never re-derives health from a cosmetic local flag.
/// Populated in the same single bootstrap attempt as every other sync
/// coordinator above, alongside [syncRecoveryCoordinator].
///
/// Deliberately **nullable**, never `late final` -- mirrors
/// [cloudKitAssociationController]'s own identical reasoning: safe to read
/// before [initializeKeptStorage] has finished (or in an isolated widget
/// test that never calls it), with `null` meaning exactly "the composition
/// root has not finished bootstrapping yet."
SyncHealthEvaluator? syncHealthEvaluator;

/// Build 26 (Sync Diagnostics / Safe Recovery core): the narrowly-scoped
/// "resume the existing safe sync/recovery pipeline, only when
/// [syncHealthEvaluator] says it is safe to" coordinator (see
/// `lib/sync_diagnostics/sync_recovery_coordinator.dart`'s own doc comment
/// for exactly what it will and will not do). Composes
/// [syncHealthEvaluator] with a fire-and-forget closure over
/// [cloudKitSyncRuntimeCoordinator] using
/// [SyncRuntimeTrigger.diagnosticsRecovery] -- another disclosed
/// `requestSync` call site alongside
/// [cloudKitAssociationController]'s/[icloudRemovalController]'s own, per
/// `test/sync_runtime/sync_runtime_layering_test.dart`. Not called
/// automatically by any lifecycle hook in this phase -- `lib/main.dart`'s
/// existing startup/foreground triggers, plus this coordinator's own
/// account-change/retry triggers, already resume every recoverable state
/// [syncHealthEvaluator] can classify. Settings invokes this coordinator
/// only for states its own decision table declares safely resumable; an
/// explicit `recoveryRequired` state remains non-actionable.
///
/// Deliberately **nullable**, never `late final` -- mirrors
/// [syncHealthEvaluator]'s own identical reasoning.
SyncRecoveryCoordinator? syncRecoveryCoordinator;

/// The pure sequencing helper (see `kept_storage_bootstrap.dart`) doing the
/// actual "migrate once, map the result, then construct" work. Production
/// wires it to the real migration coordinator and the real stores above;
/// `test/kept_storage_bootstrap_test.dart` exercises the identical class
/// with fakes, with no Application Support storage or native file
/// protection involved.
final KeptStorageBootstrapper<KeptRepository, SavedReflectionsService>
    _keptStorageBootstrapper = KeptStorageBootstrapper(
  migrate: keptMigrationCoordinator.migrateIfNeeded,
  buildRepository: (bootstrap) => KeptRepository(
    store: keptStateStore,
    bootstrap: bootstrap,
    operationCoordinator: keptOperationCoordinator,
  ),
  buildService: (repository) {
    keptSyncIntegrationCoordinator = KeptSyncIntegrationCoordinator(
      keptRepository: repository,
      intentStore: localSyncIntentStore,
      syncPersistenceStore: syncPersistenceStore,
      integrationCoordinator: syncIntegrationOperationCoordinator,
      // Build 26 Phase 4F fast-follow: fire-and-forget only. Safe to
      // reference the `late final` `cloudKitSyncRuntimeCoordinator` here
      // even though it is not assigned until later in this same closure --
      // this callback is never invoked until a real user mutation commits,
      // and `initializeKeptStorage()` (which runs this entire closure) is
      // always completed by `main()`'s BootstrapGate before WisdomApp is
      // built, so `cloudKitSyncRuntimeCoordinator` is guaranteed assigned by
      // the time any mutation can occur. Never awaited, and any error the
      // returned `Future` carries is swallowed here so it can never surface
      // as an unhandled async error.
      onMutationCommitted: () {
        unawaited(
          cloudKitSyncRuntimeCoordinator
              .requestSync(SyncRuntimeTrigger.localMutation)
              .catchError((_) {}),
        );
      },
    );
    incomingKeptSyncCoordinator = IncomingKeptSyncCoordinator(
      keptRepository: repository,
      intentStore: localSyncIntentStore,
      syncPersistenceStore: syncPersistenceStore,
      integrationCoordinator: syncIntegrationOperationCoordinator,
      // Build 26 Phase 4H-6: the sole production bridge from a durable
      // incoming-apply's material Kept-content change to any mounted
      // Kept/Reflections UI. Synchronous, fire-and-forget from this
      // coordinator's own perspective -- IncomingKeptSyncCoordinator only
      // ever calls a plain `void Function()?`; this closure alone decides
      // it means "notify keptStateRevisionNotifier's listeners".
      onIncomingStateChanged: keptStateRevisionNotifier.notify,
    );
    keptSyncBootstrapCoordinator = KeptSyncBootstrapCoordinator(
      bridge: cloudKitPlatformBridge,
      keptRepository: repository,
      intentStore: localSyncIntentStore,
      syncPersistenceStore: syncPersistenceStore,
      integrationCoordinator: syncIntegrationOperationCoordinator,
    );
    syncOrchestrator = SyncOrchestrator(
      bridge: cloudKitPlatformBridge,
      persistenceStore: syncPersistenceStore,
    );
    cloudKitSyncRuntimeCoordinator = CloudKitSyncRuntimeCoordinator(
      bootstrapCoordinator: keptSyncBootstrapCoordinator,
      integrationCoordinator: keptSyncIntegrationCoordinator,
      incomingCoordinator: incomingKeptSyncCoordinator,
      orchestrator: syncOrchestrator,
      syncPersistenceStore: syncPersistenceStore,
      // Build 26 Phase 5 (slice 3): the exact same production
      // `localSyncIntentStore` global every other sync coordinator above
      // already shares -- never a second, uncoordinated
      // `ProtectedLocalSyncIntentStore()` instance. Used internally only to
      // construct this coordinator's default `LocalDeletionFinalizer` (see
      // that class's own constructor).
      localSyncIntentStore: localSyncIntentStore,
      bridge: cloudKitPlatformBridge,
      onPassFinished: productionDiagnosticsService.recordSyncOutcome,
    );
    cloudKitAssociationController = SyncAssociationController(
      bootstrapCoordinator: keptSyncBootstrapCoordinator,
      // Fire-and-forget only, mirroring keptSyncIntegrationCoordinator's own
      // onMutationCommitted callback above: never awaited by the caller,
      // and any error the returned Future carries is swallowed here so it
      // can never surface as an unhandled async error or block the
      // Settings screen on a CloudKit round trip.
      requestSyncAfterAssociation: () {
        unawaited(
          cloudKitSyncRuntimeCoordinator
              .requestSync(SyncRuntimeTrigger.explicitAssociation)
              .catchError((_) {}),
        );
      },
    );
    icloudRemovalController = ICloudRemovalController(
      syncPersistenceStore: syncPersistenceStore,
      // Fire-and-forget only, mirroring cloudKitAssociationController's own
      // requestSyncAfterAssociation callback above: never awaited by the
      // caller, and any error the returned Future carries is swallowed here
      // so it can never surface as an unhandled async error or block the
      // Settings screen on a CloudKit round trip.
      requestSyncAfterRemoval: () {
        unawaited(
          cloudKitSyncRuntimeCoordinator
              .requestSync(SyncRuntimeTrigger.explicitDeletion)
              .catchError((_) {}),
        );
      },
    );
    syncHealthEvaluator = SyncHealthEvaluator(
      syncPersistenceStore: syncPersistenceStore,
      bridge: cloudKitPlatformBridge,
      readRuntimeStatus: () => cloudKitSyncRuntimeCoordinator.status,
    );
    syncRecoveryCoordinator = SyncRecoveryCoordinator(
      evaluateHealth: syncHealthEvaluator!.evaluate,
      // Fire-and-forget only, mirroring cloudKitAssociationController's own
      // requestSyncAfterAssociation callback above: never awaited by the
      // caller, and any error the returned Future carries is swallowed here
      // so it can never surface as an unhandled async error.
      triggerRecoverySync: () => cloudKitSyncRuntimeCoordinator
          .requestSync(SyncRuntimeTrigger.diagnosticsRecovery)
          .catchError((_) {}),
    );
    return SavedReflectionsService(
      keptRepository: repository,
      syncCoordinator: keptSyncIntegrationCoordinator,
      analyticsService: analyticsService,
    );
  },
);

late final SavedReflectionsService savedReflectionsService;

Future<void>? _keptStorageInitialization;

/// Idempotent Kept-storage bootstrap entry point. Safe to call more than
/// once (including concurrently) — every call after the first observes the
/// same single in-flight or completed attempt, and the `late final` globals
/// above are each assigned exactly once regardless of how many times this
/// is called.
Future<void> initializeKeptStorage() {
  return _keptStorageInitialization ??= _applyKeptStorageBootstrap();
}

Future<void> _applyKeptStorageBootstrap() async {
  final result = await _keptStorageBootstrapper.run();
  savedReflectionsService = result.service;
}
