import 'package:wisdom_app/persistence/storage_preferences_adapter.dart';
import 'package:wisdom_app/persistence/persistence_operation_coordinator.dart';
import 'package:wisdom_app/repositories/daily_access_repository.dart';
import 'package:wisdom_app/services/daily_wisdom_access_service.dart';
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
