import '../models/kept_bootstrap_result.dart';
import '../persistence/persistence_operation_coordinator.dart';
import '../persistence/protected_file_kept_state_store.dart';
import '../persistence/protected_kept_migration_artifact_store.dart';
import '../persistence/kept_migration_journal_store.dart';
import '../persistence/legacy_favorites_store.dart';
import '../persistence/storage_preferences_adapter.dart';
import '../repositories/daily_access_repository.dart';
import '../repositories/kept_repository.dart';
import '../sync_integration/incoming_kept_sync_coordinator.dart';
import '../sync_integration/kept_sync_bootstrap_coordinator.dart';
import '../sync_integration/kept_sync_integration_coordinator.dart';
import '../sync_integration/protected_local_sync_intent_store.dart';
import '../sync_persistence/protected_sync_persistence_store.dart';
import '../sync_platform/method_channel_cloud_kit_platform_bridge.dart';
import 'daily_wisdom_access_service.dart';
import 'kept_discovery_hint_service.dart';
import 'kept_migration_coordinator.dart';
import 'kept_storage_bootstrap.dart';
import 'purchase_service.dart';
import 'saved_reflections_service.dart';
import 'storage_service.dart';
import 'wisdom_notification_service.dart';
import 'wisdom_share_service.dart';

final PurchaseService purchaseService = PurchaseService();
final StorageService storageService = StorageService();
final WisdomShareHandler wisdomShareService = WisdomShareService();
final WisdomNotificationService wisdomNotificationService =
    WisdomNotificationService();
final KeptDiscoveryHintService keptDiscoveryHintService =
    KeptDiscoveryHintService();

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
  );
}

// ---------------------------------------------------------------------
// Protected Kept storage bootstrap (Build 26 Phase 3D-C production cutover).
//
// `main()` must `await initializeKeptStorage()` before `runApp()`, so every
// `late final` global below is populated before any screen can ever read
// `savedReflectionsService` or `keptRepository`. Idempotent: concurrent or
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
/// the same single bootstrap attempt that populates [keptRepository]/
/// [savedReflectionsService] — never constructed a second time. Exposed as
/// its own global (mirroring [keptRepository]) so a future phase's explicit
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
    );
    incomingKeptSyncCoordinator = IncomingKeptSyncCoordinator(
      keptRepository: repository,
      intentStore: localSyncIntentStore,
      syncPersistenceStore: syncPersistenceStore,
      integrationCoordinator: syncIntegrationOperationCoordinator,
    );
    keptSyncBootstrapCoordinator = KeptSyncBootstrapCoordinator(
      bridge: cloudKitPlatformBridge,
      keptRepository: repository,
      intentStore: localSyncIntentStore,
      syncPersistenceStore: syncPersistenceStore,
      integrationCoordinator: syncIntegrationOperationCoordinator,
    );
    return SavedReflectionsService(
      keptRepository: repository,
      syncCoordinator: keptSyncIntegrationCoordinator,
    );
  },
);

late final KeptBootstrapResult keptBootstrapResult;
late final KeptRepository keptRepository;
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
  keptBootstrapResult = result.bootstrap;
  keptRepository = result.repository;
  savedReflectionsService = result.service;
}
