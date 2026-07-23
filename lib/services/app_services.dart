import '../persistence/persistence_operation_coordinator.dart';
import '../persistence/storage_preferences_adapter.dart';
import '../repositories/daily_access_repository.dart';
import 'daily_wisdom_access_service.dart';
import 'purchase_service.dart';
import 'saved_reflections_service.dart';
import 'storage_service.dart';
import 'wisdom_notification_service.dart';
import 'wisdom_share_service.dart';

final PurchaseService purchaseService = PurchaseService();
final StorageService storageService = StorageService();
final SavedReflectionsService savedReflectionsService =
    SavedReflectionsService();
final WisdomShareHandler wisdomShareService = WisdomShareService();
final WisdomNotificationService wisdomNotificationService =
    WisdomNotificationService();

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
