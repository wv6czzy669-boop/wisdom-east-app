import '../models/kept_bootstrap_result.dart';
import '../persistence/persistence_operation_coordinator.dart';
import '../persistence/protected_file_kept_state_store.dart';
import '../persistence/protected_kept_migration_artifact_store.dart';
import '../persistence/kept_migration_journal_store.dart';
import '../persistence/legacy_favorites_store.dart';
import '../persistence/storage_preferences_adapter.dart';
import '../repositories/daily_access_repository.dart';
import '../repositories/kept_repository.dart';
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
  buildService: (repository) =>
      SavedReflectionsService(keptRepository: repository),
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
