import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/services/purchase_service.dart';

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
}

Future<void> _flushEvents() async {
  await Future<void>.delayed(const Duration(milliseconds: 20));
}

class _FakeInAppPurchasePlatform extends InAppPurchasePlatform {
  final StreamController<List<PurchaseDetails>> _purchaseController =
      StreamController<List<PurchaseDetails>>.broadcast();

  Completer<bool>? buyCompleter;
  Completer<void>? restoreCompleter;
  int completedPurchases = 0;
  int restoreCalls = 0;

  final ProductDetails keeperProduct = ProductDetails(
    id: PurchaseService.keeperProductId,
    title: 'Keeper',
    description: 'Support East',
    price: r'$4.99',
    rawPrice: 4.99,
    currencyCode: 'USD',
  );

  @override
  Stream<List<PurchaseDetails>> get purchaseStream =>
      _purchaseController.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ProductDetailsResponse> queryProductDetails(
    Set<String> identifiers,
  ) async {
    return ProductDetailsResponse(
      productDetails: [keeperProduct],
      notFoundIDs: const [],
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
