import 'package:wisdom_app/models/kept_bootstrap_result.dart';
import 'package:wisdom_app/models/kept_record.dart';
import 'package:wisdom_app/models/kept_state_envelope.dart';
import 'package:wisdom_app/persistence/kept_state_store.dart';
import 'package:wisdom_app/persistence/protected_file_kept_state_store.dart'
    show KeptStateStoreException;
import 'package:wisdom_app/persistence/storage_preferences_adapter.dart';
import 'package:wisdom_app/persistence/persistence_operation_coordinator.dart';
import 'package:wisdom_app/repositories/daily_access_repository.dart';
import 'package:wisdom_app/repositories/kept_repository.dart';
import 'package:wisdom_app/services/daily_wisdom_access_service.dart';
import 'package:wisdom_app/services/saved_reflections_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef PersistString = Future<void> Function();
typedef ReadString = Future<String?> Function();
typedef PersistRemove = Future<void> Function();
typedef GetStringInterceptor = Future<String?> Function(
  String key,
  ReadString read,
);
typedef SetStringInterceptor = Future<void> Function(
  String key,
  String value,
  PersistString persist,
);
typedef RemoveInterceptor = Future<void> Function(
  String key,
  PersistRemove persist,
);

class InterceptingStoragePreferencesAdapter extends StoragePreferencesAdapter {
  InterceptingStoragePreferencesAdapter({
    super.preferencesProvider,
    this.getStringInterceptor,
    this.setStringInterceptor,
    this.removeInterceptor,
  });

  final GetStringInterceptor? getStringInterceptor;
  final SetStringInterceptor? setStringInterceptor;
  final RemoveInterceptor? removeInterceptor;

  @override
  Future<String?> getString(String key) async {
    final interceptor = getStringInterceptor;
    if (interceptor == null) {
      return super.getString(key);
    }

    return interceptor(key, () => super.getString(key));
  }

  @override
  Future<void> setString(String key, String value) async {
    final interceptor = setStringInterceptor;
    if (interceptor == null) {
      await super.setString(key, value);
      return;
    }

    await interceptor(key, value, () => super.setString(key, value));
  }

  @override
  Future<void> remove(String key) async {
    final interceptor = removeInterceptor;
    if (interceptor == null) {
      await super.remove(key);
      return;
    }

    await interceptor(key, () => super.remove(key));
  }
}

class DailyAccessTestGraph {
  DailyAccessTestGraph({
    StoragePreferencesAdapter? adapter,
    PersistenceOperationCoordinator? coordinator,
    Future<void> Function(SharedPreferences prefs, String key)?
        obsoleteKeyRemover,
    Future<void> Function(SharedPreferences prefs, String key)?
        pendingRevealRemover,
    WisdomClock? clock,
    Duration statusTimeout = DailyWisdomAccessService.defaultStatusTimeout,
  })  : adapter = adapter ?? StoragePreferencesAdapter(),
        coordinator = coordinator ?? PersistenceOperationCoordinator() {
    repository = DailyAccessRepository(
      preferencesAdapter: this.adapter,
      operationCoordinator: this.coordinator,
      obsoleteKeyRemover: obsoleteKeyRemover,
      pendingRevealRemover: pendingRevealRemover,
    );
    service = DailyWisdomAccessService(
      repository: repository,
      clock: clock,
      statusTimeout: statusTimeout,
    );
  }

  final StoragePreferencesAdapter adapter;
  final PersistenceOperationCoordinator coordinator;
  late final DailyAccessRepository repository;
  late final DailyWisdomAccessService service;
}

/// Deterministic, in-memory [KeptStateStore] for tests. Never touches the
/// filesystem or platform channels. Holds exactly one [KeptStateEnvelope] in
/// memory (or none, before the first [replace]), mirroring the "no
/// authoritative envelope has ever been created yet" contract
/// [KeptStateStore.load] documents.
///
/// [failLoad]/[failReplace], when set, make the next matching call throw a
/// [KeptStateStoreException] instead of touching [envelope] — for tests that
/// need to exercise `KeptRepository`'s own store-failure mapping.
class InMemoryKeptStateStore implements KeptStateStore {
  KeptStateEnvelope? envelope;
  Object? failLoad;
  Object? failReplace;

  @override
  Future<KeptStateEnvelope?> load() async {
    final failure = failLoad;
    if (failure != null) {
      failLoad = null;
      throw failure;
    }
    return envelope;
  }

  @override
  Future<void> replace(KeptStateEnvelope newEnvelope) async {
    final failure = failReplace;
    if (failure != null) {
      failReplace = null;
      throw failure;
    }
    envelope = newEnvelope;
  }
}

/// Test-only wiring for the Build 26 Phase 3D-C protected Kept repository
/// graph, mirroring [DailyAccessTestGraph]'s role for daily access.
///
/// Every production `SavedReflectionsService` caller (`HomeScreen`,
/// `SavedReflectionsScreen`, `ReflectionScreen`) now reaches the Kept store
/// only through `KeptRepository`, so a widget test that wants to seed
/// "already kept" state, or read back what a widget interaction persisted,
/// needs the exact same [KeptRepository] instance the widget itself was
/// built with — never a disconnected second instance pointed at a different
/// in-memory store. Constructing one [KeptRepositoryTestGraph] and passing
/// its [service] into the widget under test (and reading [store].envelope /
/// calling [service].load() afterward) keeps both sides of a test looking at
/// the same protected state.
class KeptRepositoryTestGraph {
  KeptRepositoryTestGraph({
    KeptBootstrapResult bootstrap = const KeptBootstrapResult.ready(),
    KeptClock? clock,
    KeptIdFactory? idFactory,
    int freeKeptLimit = 3,
    int freeReflectionLimit = 3,
  }) : store = InMemoryKeptStateStore() {
    repository = KeptRepository(
      store: store,
      bootstrap: bootstrap,
      operationCoordinator: PersistenceOperationCoordinator(),
      clock: clock,
      idFactory: idFactory,
      freeKeptLimit: freeKeptLimit,
      freeReflectionLimit: freeReflectionLimit,
    );
    service = SavedReflectionsService(keptRepository: repository);
  }

  final InMemoryKeptStateStore store;
  late final KeptRepository repository;
  late final SavedReflectionsService service;

  /// Seeds [store] directly with [records] as the authoritative active
  /// records — for tests that need a deterministic "already kept" starting
  /// state without going through `keepOccurrence` (and its own generated
  /// id/mutationId/clock).
  void seed(List<KeptRecord> records) {
    store.envelope = KeptStateEnvelope(activeRecords: records);
  }
}
