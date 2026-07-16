import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/models/daily_wisdom_record.dart';
import 'package:wisdom_app/services/daily_wisdom_access_service.dart';
import 'package:wisdom_app/services/purchase_service.dart';

import 'persistence_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeInAppPurchasePlatform platform;
  late PurchaseService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});

    // Ensure the facade exists before replacing its platform implementation.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    InAppPurchase.instance;
    platform = _FakeInAppPurchasePlatform();
    InAppPurchasePlatform.instance = platform;
    service = PurchaseService();
    await service.init();
  });

  tearDown(() async {
    service.dispose();
    await platform.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  test('buy guard remains active while purchase is pending', () async {
    platform.buyCompleter = Completer<bool>();

    final firstAttempt = service.buyKeeper();
    expect(service.isLoading, isTrue);
    expect(await service.buyKeeper(), isFalse);

    platform.buyCompleter!.complete(true);
    expect(await firstAttempt, isTrue);
    expect(service.isLoading, isTrue);

    platform.emitPurchase(PurchaseStatus.pending);
    await _flushEvents();
    expect(service.isLoading, isTrue);

    platform.emitPurchase(
      PurchaseStatus.purchased,
      pendingCompletePurchase: true,
    );
    await _flushEvents();

    expect(service.isKeeper, isTrue);
    expect(service.isLoading, isFalse);
    expect(platform.completedPurchases, 1);
  });

  test('restore guard blocks duplicate requests until stream response',
      () async {
    platform.restoreCompleter = Completer<void>();

    final firstAttempt = service.restorePurchases();
    expect(service.isLoading, isTrue);
    expect(await service.restorePurchases(), isFalse);

    platform.restoreCompleter!.complete();
    expect(await firstAttempt, isTrue);
    expect(service.isLoading, isTrue);

    platform.emitPurchase(
      PurchaseStatus.restored,
      pendingCompletePurchase: true,
    );
    await _flushEvents();

    expect(service.isKeeper, isTrue);
    expect(service.isLoading, isFalse);
    expect(platform.completedPurchases, 1);
  });

  test('failed entitlement persistence leaves transaction unfinished',
      () async {
    service.dispose();
    service = PurchaseService(entitlementWriter: () async => false);
    await service.init();

    expect(await service.buyKeeper(), isTrue);
    platform.emitPurchase(
      PurchaseStatus.purchased,
      pendingCompletePurchase: true,
    );
    await _flushEvents();

    expect(service.isKeeper, isFalse);
    expect(service.entitlementPersistenceFailed, isTrue);
    expect(service.isLoading, isFalse);
    expect(platform.completedPurchases, 0);
    expect(await service.buyKeeper(), isFalse);
  });

  test('buy timeout blocks duplicate purchases and leaves restore available',
      () async {
    service.dispose();
    service = PurchaseService(
      purchaseInitiationTimeout: const Duration(milliseconds: 20),
    );
    await service.init();
    platform.buyCompleter = Completer<bool>();

    expect(await service.buyKeeper(), isFalse);
    expect(service.isLoading, isFalse);
    expect(service.purchaseNeedsRecovery, isTrue);
    expect(await service.buyKeeper(), isFalse);

    expect(await service.restorePurchases(), isTrue);
    expect(service.isLoading, isTrue);
  });

  test('purchase stream error keeps duplicate purchase guard active', () async {
    expect(await service.buyKeeper(), isTrue);
    expect(service.isLoading, isTrue);

    platform.emitError(StateError('Simulated purchase stream failure.'));
    await _flushEvents();

    expect(service.isKeeper, isFalse);
    expect(service.isLoading, isFalse);
    expect(service.purchaseNeedsRecovery, isTrue);
    expect(await service.buyKeeper(), isFalse);
  });

  test('purchase watchdog recovers loading and accepts a late success',
      () async {
    service.dispose();
    service = PurchaseService(
      purchaseResponseTimeout: const Duration(milliseconds: 20),
    );
    await service.init();

    expect(await service.buyKeeper(), isTrue);
    expect(service.isLoading, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(service.isLoading, isFalse);
    expect(service.purchaseNeedsRecovery, isTrue);
    expect(service.isKeeper, isFalse);

    platform.emitPurchase(PurchaseStatus.pending);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(service.isLoading, isFalse);
    expect(service.purchaseNeedsRecovery, isTrue);

    platform.emitPurchase(
      PurchaseStatus.purchased,
      pendingCompletePurchase: true,
    );
    await _flushEvents();

    expect(service.isKeeper, isTrue);
    expect(service.purchaseNeedsRecovery, isFalse);
    expect(platform.completedPurchases, 1);
  });

  test('duplicate purchase events serialize persistence and completion',
      () async {
    service.dispose();
    final writer = Completer<bool>();
    var writerCalls = 0;
    var activeWriters = 0;
    var maximumActiveWriters = 0;
    service = PurchaseService(
      entitlementWriter: () async {
        writerCalls++;
        activeWriters++;
        maximumActiveWriters = activeWriters > maximumActiveWriters
            ? activeWriters
            : maximumActiveWriters;
        final result = await writer.future;
        activeWriters--;
        return result;
      },
    );
    await service.init();
    expect(await service.buyKeeper(), isTrue);

    platform.emitPurchase(
      PurchaseStatus.purchased,
      pendingCompletePurchase: true,
    );
    platform.emitPurchase(
      PurchaseStatus.purchased,
      pendingCompletePurchase: true,
    );
    await _flushEvents();

    expect(writerCalls, 1);
    expect(maximumActiveWriters, 1);
    expect(platform.completedPurchases, 0);

    writer.complete(true);
    await _flushEvents();

    expect(service.isKeeper, isTrue);
    expect(writerCalls, 1);
    expect(maximumActiveWriters, 1);
    expect(platform.completedPurchases, 1);
  });

  test('buy reloads StoreKit product state after startup unavailability',
      () async {
    service.dispose();
    platform.productQueryCalls = 0;
    platform.available = false;
    service = PurchaseService(storeRetryCooldown: Duration.zero);
    await service.init();

    expect(service.isAvailable, isFalse);
    expect(service.keeperProduct, isNull);

    platform.available = true;
    expect(await service.buyKeeper(), isTrue);
    expect(service.isAvailable, isTrue);
    expect(service.keeperProduct, isNotNull);
    expect(platform.productQueryCalls, 1);
  });

  test('restore reloads StoreKit availability after startup failure', () async {
    service.dispose();
    platform.available = false;
    service = PurchaseService(storeRetryCooldown: Duration.zero);
    await service.init();

    platform.available = true;
    expect(await service.restorePurchases(), isTrue);
    expect(service.isAvailable, isTrue);
    expect(platform.restoreCalls, 1);
  });

  test('restore timeout blocks overlap until a late response is reconciled',
      () async {
    service.dispose();
    service = PurchaseService(
      restoreInitiationTimeout: const Duration(milliseconds: 20),
    );
    await service.init();
    platform.restoreCompleter = Completer<void>();

    expect(await service.restorePurchases(), isFalse);
    expect(service.isLoading, isFalse);
    expect(service.restoreNeedsRecovery, isTrue);
    expect(await service.restorePurchases(), isFalse);
    expect(platform.restoreCalls, 1);

    platform.emitPurchase(
      PurchaseStatus.restored,
      pendingCompletePurchase: true,
    );
    await _flushEvents();

    expect(service.isKeeper, isTrue);
    expect(service.restoreNeedsRecovery, isFalse);
    expect(platform.completedPurchases, 1);
  });

  test('successful purchase does not unlock a second wisdom', () async {
    final now = DateTime.utc(2026, 6, 20, 12);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'daily_wisdom_access',
      DailyWisdomRecord(
        text: 'Purchased while locked wisdom',
        revealedAt: now,
        unlockAt: now.add(const Duration(hours: 24)),
      ).encode(),
    );

    expect(await service.buyKeeper(), isTrue);
    platform.emitPurchase(
      PurchaseStatus.purchased,
      pendingCompletePurchase: true,
    );
    await _flushEvents();

    final dailyAccess = DailyWisdomAccessService(
      repository: DailyAccessTestGraph().repository,
      clock: () => now.add(const Duration(hours: 1)),
    );
    var selected = false;
    final result = await dailyAccess.reveal(
      selectWisdom: () {
        selected = true;
        return 'Second wisdom';
      },
    );

    expect(service.isKeeper, isTrue);
    expect(selected, isFalse);
    expect(result.text, 'Purchased while locked wisdom');
    expect(result.isNew, isFalse);
  });

  test('successful restore does not unlock a second wisdom', () async {
    final now = DateTime.utc(2026, 6, 20, 12);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'daily_wisdom_access',
      DailyWisdomRecord(
        text: 'Restored while locked wisdom',
        revealedAt: now,
        unlockAt: now.add(const Duration(hours: 24)),
      ).encode(),
    );

    expect(await service.restorePurchases(), isTrue);
    platform.emitPurchase(
      PurchaseStatus.restored,
      pendingCompletePurchase: true,
    );
    await _flushEvents();

    final dailyAccess = DailyWisdomAccessService(
      repository: DailyAccessTestGraph().repository,
      clock: () => now.add(const Duration(hours: 1)),
    );
    var selected = false;
    final result = await dailyAccess.reveal(
      selectWisdom: () {
        selected = true;
        return 'Second wisdom';
      },
    );

    expect(service.isKeeper, isTrue);
    expect(selected, isFalse);
    expect(result.text, 'Restored while locked wisdom');
    expect(result.isNew, isFalse);
  });
}

Future<void> _flushEvents() async {
  await Future<void>.delayed(const Duration(milliseconds: 20));
}

class _FakeInAppPurchasePlatform extends InAppPurchasePlatform {
  final StreamController<List<PurchaseDetails>> _purchaseController =
      StreamController<List<PurchaseDetails>>.broadcast();

  Completer<bool>? buyCompleter;
  Completer<void>? restoreCompleter;
  bool available = true;
  int completedPurchases = 0;
  int restoreCalls = 0;
  int productQueryCalls = 0;

  final ProductDetails keeperProduct = ProductDetails(
    id: PurchaseService.keeperProductId,
    title: 'Keeper',
    description: 'Support EAST.',
    price: r'$4.99',
    rawPrice: 4.99,
    currencyCode: 'USD',
  );

  @override
  Stream<List<PurchaseDetails>> get purchaseStream =>
      _purchaseController.stream;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async {
    productQueryCalls++;
    return ProductDetailsResponse(
      productDetails: available ? [keeperProduct] : const [],
      notFoundIDs: available ? const [] : [PurchaseService.keeperProductId],
    );
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) {
    return buyCompleter?.future ?? Future<bool>.value(true);
  }

  @override
  Future<void> restorePurchases({String? applicationUserName}) {
    restoreCalls++;
    return restoreCompleter?.future ?? Future<void>.value();
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completedPurchases++;
  }

  void emitPurchase(
    PurchaseStatus status, {
    bool pendingCompletePurchase = false,
  }) {
    final purchase = PurchaseDetails(
      purchaseID: 'keeper-purchase',
      productID: PurchaseService.keeperProductId,
      verificationData: PurchaseVerificationData(
        localVerificationData: 'local',
        serverVerificationData: 'server',
        source: 'test',
      ),
      transactionDate: '0',
      status: status,
    )..pendingCompletePurchase = pendingCompletePurchase;

    _purchaseController.add([purchase]);
  }

  void emitError(Object error) {
    _purchaseController.addError(error);
  }

  Future<void> dispose() => _purchaseController.close();
}
