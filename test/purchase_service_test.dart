import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/models/daily_wisdom_record.dart';
import 'package:wisdom_app/services/analytics_event.dart';
import 'package:wisdom_app/services/analytics_service.dart';
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
    await _flushEvents();
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
    await _flushEvents();
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

  test('buy timeout observes late false result and becomes retryable',
      () async {
    service.dispose();
    service = PurchaseService(
      purchaseInitiationTimeout: Duration.zero,
    );
    await service.init();
    final firstNativeBuy = Completer<bool>();
    platform.buyCompleter = firstNativeBuy;

    expect(await service.buyKeeper(), isFalse);
    expect(service.isLoading, isFalse);
    expect(service.purchaseNeedsRecovery, isTrue);
    expect(await service.buyKeeper(), isFalse);
    expect(platform.buyCalls, 1);

    expect(await service.restorePurchases(), isFalse);
    expect(platform.restoreCalls, 0);

    firstNativeBuy.complete(false);
    await _flushEvents();

    expect(service.isKeeper, isFalse);
    expect(service.purchaseNeedsRecovery, isFalse);

    platform.buyCompleter = null;
    expect(await service.buyKeeper(), isTrue);
    expect(platform.buyCalls, 2);
  });

  test('buy timeout observes late throw and becomes retryable', () async {
    service.dispose();
    service = PurchaseService(
      purchaseInitiationTimeout: Duration.zero,
    );
    await service.init();
    final firstNativeBuy = Completer<bool>();
    platform.buyCompleter = firstNativeBuy;

    expect(await service.buyKeeper(), isFalse);
    expect(service.purchaseNeedsRecovery, isTrue);

    firstNativeBuy.completeError(StateError('Native buy failed late.'));
    await _flushEvents();

    expect(service.isKeeper, isFalse);
    expect(service.purchaseNeedsRecovery, isFalse);

    platform.buyCompleter = null;
    expect(await service.buyKeeper(), isTrue);
    expect(platform.buyCalls, 2);
  });

  test('buy timeout clears stale uncertainty after late true without stream',
      () async {
    service.dispose();
    service = PurchaseService(
      purchaseInitiationTimeout: Duration.zero,
      purchaseResponseTimeout: Duration.zero,
    );
    await service.init();
    final firstNativeBuy = Completer<bool>();
    platform.buyCompleter = firstNativeBuy;

    expect(await service.buyKeeper(), isFalse);
    expect(service.purchaseNeedsRecovery, isTrue);

    firstNativeBuy.complete(true);
    await _flushEvents();

    expect(service.isKeeper, isFalse);
    expect(service.purchaseNeedsRecovery, isFalse);
    expect(service.isLoading, isFalse);

    platform.buyCompleter = null;
    expect(await service.buyKeeper(), isTrue);
    expect(platform.buyCalls, 2);
  });

  test('permanently hung buy Future recovers without restart', () async {
    service.dispose();
    service = PurchaseService(
      purchaseInitiationTimeout: Duration.zero,
      purchaseOperationRecoveryTimeout: Duration.zero,
    );
    await service.init();
    platform.buyCompleter = Completer<bool>();

    expect(await service.buyKeeper(), isFalse);
    await _flushEvents();

    expect(service.isLoading, isFalse);
    expect(service.purchaseNeedsRecovery, isFalse);
    expect(service.isKeeper, isFalse);

    platform.buyCompleter = null;
    platform.buyResult = false;
    expect(await service.buyKeeper(), isFalse);
    expect(platform.buyCalls, 2);

    platform.buyResult = null;
    expect(await service.restorePurchases(), isTrue);
    expect(platform.restoreCalls, 1);
  });

  test('purchased stream before native false remains authoritative', () async {
    platform.buyCompleter = Completer<bool>();

    final purchase = service.buyKeeper();
    await _flushEvents();
    platform.emitPurchase(
      PurchaseStatus.purchased,
      pendingCompletePurchase: true,
    );
    await _flushEvents();

    platform.buyCompleter!.complete(false);

    expect(await purchase, isTrue);
    expect(service.isKeeper, isTrue);
    expect(service.status, PurchaseServiceStatus.purchased);
    expect(platform.completedPurchases, 1);
  });

  test('purchased stream before native throw remains authoritative', () async {
    platform.buyCompleter = Completer<bool>();

    final purchase = service.buyKeeper();
    await _flushEvents();
    platform.emitPurchase(
      PurchaseStatus.purchased,
      pendingCompletePurchase: true,
    );
    await _flushEvents();

    platform.buyCompleter!.completeError(StateError('Native buy failed late.'));

    expect(await purchase, isTrue);
    expect(service.isKeeper, isTrue);
    expect(service.status, PurchaseServiceStatus.purchased);
    expect(platform.completedPurchases, 1);
  });

  test('canceled stream before native buy success remains authoritative',
      () async {
    platform.buyCompleter = Completer<bool>();

    final purchase = service.buyKeeper();
    await _flushEvents();
    platform.emitPurchase(PurchaseStatus.canceled);
    await _flushEvents();

    platform.buyCompleter!.complete(true);

    expect(await purchase, isFalse);
    expect(service.isKeeper, isFalse);
    expect(service.status, PurchaseServiceStatus.canceled);
  });

  test('late buy Future completion cannot regress purchased stream result',
      () async {
    service.dispose();
    service = PurchaseService(
      purchaseInitiationTimeout: Duration.zero,
    );
    await service.init();
    final firstNativeBuy = Completer<bool>();
    platform.buyCompleter = firstNativeBuy;

    expect(await service.buyKeeper(), isFalse);
    expect(service.purchaseNeedsRecovery, isTrue);

    platform.emitPurchase(
      PurchaseStatus.purchased,
      pendingCompletePurchase: true,
    );
    await _flushEvents();

    expect(service.isKeeper, isTrue);
    expect(service.purchaseNeedsRecovery, isFalse);

    firstNativeBuy.complete(false);
    await _flushEvents();

    expect(service.isKeeper, isTrue);
    expect(service.purchaseNeedsRecovery, isFalse);
    expect(platform.completedPurchases, 1);
  });

  test('abandoned buy completion cannot clear a newer operation', () async {
    service.dispose();
    service = PurchaseService(
      purchaseInitiationTimeout: Duration.zero,
      purchaseOperationRecoveryTimeout: Duration.zero,
    );
    await service.init();
    final oldNativeBuy = Completer<bool>();
    platform.buyCompleter = oldNativeBuy;

    expect(await service.buyKeeper(), isFalse);
    await _flushEvents();
    expect(service.purchaseNeedsRecovery, isFalse);

    final newerNativeBuy = Completer<bool>();
    platform.buyCompleter = newerNativeBuy;
    expect(await service.buyKeeper(), isFalse);
    expect(service.purchaseNeedsRecovery, isFalse);

    oldNativeBuy.complete(false);
    await _flushEvents();

    expect(service.purchaseNeedsRecovery, isFalse);
    expect(service.isKeeper, isFalse);

    newerNativeBuy.complete(false);
    await _flushEvents();

    expect(service.purchaseNeedsRecovery, isFalse);
  });

  test('old purchase watchdog cannot regress purchased state', () async {
    service.dispose();
    service = PurchaseService(
      purchaseResponseTimeout: Duration.zero,
    );
    await service.init();

    expect(await service.buyKeeper(), isTrue);
    platform.emitPurchase(
      PurchaseStatus.purchased,
      pendingCompletePurchase: true,
    );
    await _flushEvents();
    await _flushEvents();

    expect(service.isKeeper, isTrue);
    expect(service.status, PurchaseServiceStatus.purchased);
    expect(platform.completedPurchases, 1);
  });

  test('late purchased event after abandoned buy still grants Keeper',
      () async {
    service.dispose();
    service = PurchaseService(
      purchaseInitiationTimeout: Duration.zero,
      purchaseOperationRecoveryTimeout: Duration.zero,
    );
    await service.init();
    platform.buyCompleter = Completer<bool>();

    expect(await service.buyKeeper(), isFalse);
    await _flushEvents();
    expect(service.purchaseNeedsRecovery, isFalse);

    platform.emitPurchase(
      PurchaseStatus.purchased,
      pendingCompletePurchase: true,
    );
    await _flushEvents();

    expect(service.isKeeper, isTrue);
    expect(service.status, PurchaseServiceStatus.purchased);
    expect(platform.completedPurchases, 1);
  });

  test('late abandoned purchase resolves newer active buy safely', () async {
    service.dispose();
    service = PurchaseService(
      purchaseOperationRecoveryTimeout: Duration.zero,
    );
    await service.init();
    final oldNativeBuy = Completer<bool>();
    platform.buyCompleter = oldNativeBuy;

    final abandonedBuy = service.buyKeeper();
    await _flushEvents();
    expect(service.purchaseNeedsRecovery, isFalse);

    final newerNativeBuy = Completer<bool>();
    platform.buyCompleter = newerNativeBuy;
    final newerBuy = service.buyKeeper();
    await _flushEvents();
    expect(platform.buyCalls, 2);
    expect(service.isLoading, isFalse);

    platform.emitPurchase(
      PurchaseStatus.purchased,
      pendingCompletePurchase: true,
    );
    await _flushEvents();

    expect(service.isKeeper, isTrue);
    expect(service.isLoading, isFalse);
    expect(service.status, PurchaseServiceStatus.purchased);

    oldNativeBuy.complete(false);
    newerNativeBuy.complete(false);
    expect(await abandonedBuy, isFalse);
    expect(await newerBuy, isFalse);
    expect(service.status, PurchaseServiceStatus.purchased);
  });

  test('repeated initialize calls subscribe once and share product loading',
      () async {
    service.dispose();
    await platform.dispose();
    platform = _FakeInAppPurchasePlatform();
    InAppPurchasePlatform.instance = platform;
    platform.productQueryCompleter = Completer<ProductDetailsResponse>();
    service = PurchaseService();

    final firstInit = service.init();
    final secondInit = service.init();
    await _flushEvents();

    expect(platform.purchaseStreamSubscriptions, 1);
    expect(platform.productQueryCalls, 1);

    platform.productQueryCompleter!.complete(
      platform.productResponse([platform.keeperProduct]),
    );
    await Future.wait([firstInit, secondInit]);

    expect(service.isInitialized, isTrue);
    expect(service.keeperProduct?.price, r'$4.99');
    expect(platform.purchaseStreamSubscriptions, 1);
  });

  test('persisted Keeper loads even when product query fails', () async {
    service.dispose();
    SharedPreferences.setMockInitialValues({'is_premium': true});
    platform.productQueryError = StateError('Products unavailable.');
    service = PurchaseService();
    await service.init();

    expect(service.isKeeper, isTrue);
    expect(service.keeperProduct, isNull);
    expect(service.status, PurchaseServiceStatus.failed);
  });

  test('wrong-type persisted Keeper preference fails closed', () async {
    service.dispose();
    SharedPreferences.setMockInitialValues({'is_premium': 'true'});
    service = PurchaseService();
    await service.init();

    expect(service.isKeeper, isFalse);
  });

  test('missing or wrong product details block purchase safely', () async {
    service.dispose();
    platform.products = <ProductDetails>[
      ProductDetails(
        id: 'wrong.product',
        title: 'Wrong',
        description: 'Wrong product',
        price: r'$9.99',
        rawPrice: 9.99,
        currencyCode: 'USD',
      ),
    ];
    service = PurchaseService();
    await service.init();

    expect(service.keeperProduct, isNull);
    expect(service.status, PurchaseServiceStatus.productUnavailable);
    expect(await service.buyKeeper(), isFalse);
    expect(platform.buyCalls, 0);
  });

  test('extra products are ignored while localized Keeper price is preserved',
      () async {
    service.dispose();
    final extra = ProductDetails(
      id: 'extra.product',
      title: 'Extra',
      description: 'Extra product',
      price: r'$99.99',
      rawPrice: 99.99,
      currencyCode: 'USD',
    );
    platform.products = <ProductDetails>[extra, platform.keeperProduct];
    service = PurchaseService();
    await service.init();

    expect(service.keeperProduct?.id, PurchaseService.keeperProductId);
    expect(service.keeperProduct?.price, r'$4.99');
  });

  test('buy false and buy throw do not grant Keeper', () async {
    service.dispose();
    service = PurchaseService();
    await service.init();
    platform.buyResult = false;

    expect(await service.buyKeeper(), isFalse);
    expect(service.isKeeper, isFalse);
    expect(service.status, PurchaseServiceStatus.failed);

    platform.buyResult = null;
    platform.buyError = StateError('Native buy failed.');
    expect(await service.buyKeeper(), isFalse);
    expect(service.isKeeper, isFalse);
    expect(service.purchaseNeedsRecovery, isFalse);
  });

  test('pending transaction does not grant Keeper', () async {
    expect(await service.buyKeeper(), isTrue);

    platform.emitPurchase(PurchaseStatus.pending);
    await _flushEvents();

    expect(service.isKeeper, isFalse);
    expect(service.status, PurchaseServiceStatus.purchasePending);
    expect(service.isLoading, isTrue);
  });

  test('wrong product transaction does not grant or complete', () async {
    expect(await service.buyKeeper(), isTrue);

    platform.emitPurchase(
      PurchaseStatus.purchased,
      productID: 'wrong.product',
      pendingCompletePurchase: true,
    );
    await _flushEvents();

    expect(service.isKeeper, isFalse);
    expect(platform.completedPurchases, 0);
  });

  test('canceled and error transactions do not grant Keeper and are retryable',
      () async {
    expect(await service.buyKeeper(), isTrue);
    platform.emitPurchase(PurchaseStatus.canceled);
    await _flushEvents();

    expect(service.isKeeper, isFalse);
    expect(service.purchaseNeedsRecovery, isFalse);
    expect(service.status, PurchaseServiceStatus.canceled);

    expect(await service.buyKeeper(), isTrue);
    platform.emitPurchase(PurchaseStatus.error);
    await _flushEvents();

    expect(service.isKeeper, isFalse);
    expect(service.purchaseNeedsRecovery, isFalse);
    expect(service.status, PurchaseServiceStatus.failed);
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

  test('purchase stream closure marks service uninitialized for recovery',
      () async {
    expect(service.isInitialized, isTrue);

    await platform.closePurchaseStream();
    await _flushEvents();

    expect(service.isInitialized, isFalse);
    expect(service.status, PurchaseServiceStatus.failed);
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

  test('restore timeout observes late throw and becomes retryable', () async {
    service.dispose();
    service = PurchaseService(
      restoreInitiationTimeout: Duration.zero,
    );
    await service.init();
    final firstNativeRestore = Completer<void>();
    platform.restoreCompleter = firstNativeRestore;

    expect(await service.restorePurchases(), isFalse);
    expect(service.restoreNeedsRecovery, isTrue);

    firstNativeRestore.completeError(StateError('Native restore failed late.'));
    await _flushEvents();

    expect(service.restoreNeedsRecovery, isFalse);
    expect(service.isKeeper, isFalse);

    platform.restoreCompleter = null;
    expect(await service.restorePurchases(), isTrue);
    expect(platform.restoreCalls, 2);
  });

  test('restore timeout observes late completion and exits empty window safely',
      () async {
    service.dispose();
    service = PurchaseService(
      restoreInitiationTimeout: Duration.zero,
      restoreResponseWindow: Duration.zero,
    );
    await service.init();
    final firstNativeRestore = Completer<void>();
    platform.restoreCompleter = firstNativeRestore;

    expect(await service.restorePurchases(), isFalse);
    expect(service.restoreNeedsRecovery, isTrue);

    firstNativeRestore.complete();
    await _flushEvents();

    expect(service.isKeeper, isFalse);
    expect(service.restoreNeedsRecovery, isFalse);
    expect(service.isLoading, isFalse);
    expect(service.status, PurchaseServiceStatus.ready);

    platform.restoreCompleter = null;
    expect(await service.restorePurchases(), isTrue);
    expect(platform.restoreCalls, 2);
  });

  test('permanently hung restore Future recovers without restart', () async {
    service.dispose();
    service = PurchaseService(
      restoreInitiationTimeout: Duration.zero,
      restoreOperationRecoveryTimeout: Duration.zero,
    );
    await service.init();
    platform.restoreCompleter = Completer<void>();

    expect(await service.restorePurchases(), isFalse);
    await _flushEvents();

    expect(service.isLoading, isFalse);
    expect(service.restoreNeedsRecovery, isFalse);
    expect(service.isKeeper, isFalse);

    platform.buyResult = false;
    expect(await service.buyKeeper(), isFalse);
    expect(platform.buyCalls, 1);

    platform.buyResult = null;
    platform.restoreCompleter = null;
    expect(await service.restorePurchases(), isTrue);
    expect(platform.restoreCalls, 2);
  });

  test('permanently hung restore recovery does not revoke existing Keeper',
      () async {
    service.dispose();
    SharedPreferences.setMockInitialValues({'is_premium': true});
    service = PurchaseService(
      restoreInitiationTimeout: Duration.zero,
      restoreOperationRecoveryTimeout: Duration.zero,
    );
    await service.init();
    platform.restoreCompleter = Completer<void>();

    expect(service.isKeeper, isTrue);
    expect(await service.restorePurchases(), isFalse);
    await _flushEvents();

    expect(service.isKeeper, isTrue);
    expect(service.restoreNeedsRecovery, isFalse);
    expect(service.isLoading, isFalse);
  });

  test('restore timeout empty late completion does not revoke Keeper',
      () async {
    service.dispose();
    SharedPreferences.setMockInitialValues({'is_premium': true});
    service = PurchaseService(
      restoreInitiationTimeout: Duration.zero,
      restoreResponseWindow: Duration.zero,
    );
    await service.init();
    final firstNativeRestore = Completer<void>();
    platform.restoreCompleter = firstNativeRestore;

    expect(service.isKeeper, isTrue);
    expect(await service.restorePurchases(), isFalse);

    firstNativeRestore.complete();
    await _flushEvents();

    expect(service.isKeeper, isTrue);
    expect(service.restoreNeedsRecovery, isFalse);
    expect(service.isLoading, isFalse);
  });

  test('restored stream before native throw remains authoritative', () async {
    platform.restoreCompleter = Completer<void>();

    final restore = service.restorePurchases();
    await _flushEvents();
    platform.emitPurchase(
      PurchaseStatus.restored,
      pendingCompletePurchase: true,
    );
    await _flushEvents();

    platform.restoreCompleter!
        .completeError(StateError('Native restore failed late.'));

    expect(await restore, isTrue);
    expect(service.isKeeper, isTrue);
    expect(service.status, PurchaseServiceStatus.restored);
    expect(platform.completedPurchases, 1);
  });

  test('error stream before native restore completion remains authoritative',
      () async {
    platform.restoreCompleter = Completer<void>();

    final restore = service.restorePurchases();
    await _flushEvents();
    platform.emitPurchase(PurchaseStatus.error);
    await _flushEvents();

    platform.restoreCompleter!.complete();

    expect(await restore, isFalse);
    expect(service.isKeeper, isFalse);
    expect(service.status, PurchaseServiceStatus.failed);
  });

  test('late restore Future completion cannot regress restored stream result',
      () async {
    service.dispose();
    service = PurchaseService(
      restoreInitiationTimeout: Duration.zero,
    );
    await service.init();
    final firstNativeRestore = Completer<void>();
    platform.restoreCompleter = firstNativeRestore;

    expect(await service.restorePurchases(), isFalse);
    expect(service.restoreNeedsRecovery, isTrue);

    platform.emitPurchase(
      PurchaseStatus.restored,
      pendingCompletePurchase: true,
    );
    await _flushEvents();

    expect(service.isKeeper, isTrue);
    expect(service.restoreNeedsRecovery, isFalse);

    firstNativeRestore.complete();
    await _flushEvents();

    expect(service.isKeeper, isTrue);
    expect(service.restoreNeedsRecovery, isFalse);
    expect(platform.completedPurchases, 1);
  });

  test('abandoned restore completion cannot clear a newer operation', () async {
    service.dispose();
    service = PurchaseService(
      restoreInitiationTimeout: Duration.zero,
      restoreOperationRecoveryTimeout: Duration.zero,
    );
    await service.init();
    final oldNativeRestore = Completer<void>();
    platform.restoreCompleter = oldNativeRestore;

    expect(await service.restorePurchases(), isFalse);
    await _flushEvents();
    expect(service.restoreNeedsRecovery, isFalse);

    final newerNativeRestore = Completer<void>();
    platform.restoreCompleter = newerNativeRestore;
    expect(await service.restorePurchases(), isFalse);
    expect(service.restoreNeedsRecovery, isFalse);

    oldNativeRestore.complete();
    await _flushEvents();

    expect(service.restoreNeedsRecovery, isFalse);
    expect(service.isKeeper, isFalse);

    newerNativeRestore.completeError(StateError('Newer restore failed.'));
    await _flushEvents();

    expect(service.restoreNeedsRecovery, isFalse);
  });

  test('old restore recovery watchdog cannot regress restored state', () async {
    service.dispose();
    service = PurchaseService(
      restoreInitiationTimeout: Duration.zero,
      restoreOperationRecoveryTimeout: Duration.zero,
    );
    await service.init();
    platform.restoreCompleter = Completer<void>();

    final restore = service.restorePurchases();
    platform.emitPurchase(
      PurchaseStatus.restored,
      pendingCompletePurchase: true,
    );
    await _flushEvents();

    expect(await restore, isTrue);
    await _flushEvents();

    expect(service.isKeeper, isTrue);
    expect(service.status, PurchaseServiceStatus.restored);
    expect(platform.completedPurchases, 1);
  });

  test('late restored event after abandoned restore still grants Keeper',
      () async {
    service.dispose();
    service = PurchaseService(
      restoreInitiationTimeout: Duration.zero,
      restoreOperationRecoveryTimeout: Duration.zero,
    );
    await service.init();
    platform.restoreCompleter = Completer<void>();

    expect(await service.restorePurchases(), isFalse);
    await _flushEvents();
    expect(service.restoreNeedsRecovery, isFalse);

    platform.emitPurchase(
      PurchaseStatus.restored,
      pendingCompletePurchase: true,
    );
    await _flushEvents();

    expect(service.isKeeper, isTrue);
    expect(service.status, PurchaseServiceStatus.restored);
    expect(platform.completedPurchases, 1);
  });

  test('late abandoned restore resolves newer active restore safely', () async {
    service.dispose();
    service = PurchaseService(
      restoreOperationRecoveryTimeout: Duration.zero,
    );
    await service.init();
    final oldNativeRestore = Completer<void>();
    platform.restoreCompleter = oldNativeRestore;

    final abandonedRestore = service.restorePurchases();
    await _flushEvents();
    expect(service.restoreNeedsRecovery, isFalse);

    final newerNativeRestore = Completer<void>();
    platform.restoreCompleter = newerNativeRestore;
    final newerRestore = service.restorePurchases();
    await _flushEvents();
    expect(platform.restoreCalls, 2);
    expect(service.isLoading, isFalse);

    platform.emitPurchase(
      PurchaseStatus.restored,
      pendingCompletePurchase: true,
    );
    await _flushEvents();

    expect(service.isKeeper, isTrue);
    expect(service.isLoading, isFalse);
    expect(service.status, PurchaseServiceStatus.restored);

    oldNativeRestore.complete();
    newerNativeRestore.complete();
    expect(await abandonedRestore, isTrue);
    expect(await newerRestore, isTrue);
    expect(service.status, PurchaseServiceStatus.restored);
  });

  test('restore without matching transaction does not grant Keeper', () async {
    service.dispose();
    service = PurchaseService(
      restoreResponseWindow: const Duration(milliseconds: 20),
    );
    await service.init();

    expect(await service.restorePurchases(), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(service.isLoading, isFalse);
    expect(service.isKeeper, isFalse);
    expect(service.restoreNeedsRecovery, isFalse);
  });

  test('restore does not revoke an existing local Keeper entitlement',
      () async {
    service.dispose();
    SharedPreferences.setMockInitialValues({'is_premium': true});
    service = PurchaseService(
      restoreResponseWindow: const Duration(milliseconds: 20),
    );
    await service.init();

    expect(service.isKeeper, isTrue);
    expect(await service.restorePurchases(), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(service.isKeeper, isTrue);
  });

  test('purchase and restore cannot overlap', () async {
    platform.buyCompleter = Completer<bool>();

    final purchase = service.buyKeeper();
    await _flushEvents();
    expect(service.isLoading, isTrue);
    expect(await service.restorePurchases(), isFalse);

    platform.buyCompleter!.complete(true);
    expect(await purchase, isTrue);
    platform.emitPurchase(PurchaseStatus.pending);
    await _flushEvents();

    expect(await service.restorePurchases(), isFalse);
  });

  test('existing Keeper cannot repurchase', () async {
    service.dispose();
    SharedPreferences.setMockInitialValues({'is_premium': true});
    service = PurchaseService();
    await service.init();

    expect(service.isKeeper, isTrue);
    expect(await service.buyKeeper(), isFalse);
    expect(platform.buyCalls, 0);
  });

  test('pendingCompletePurchase false does not call completePurchase',
      () async {
    expect(await service.buyKeeper(), isTrue);

    platform.emitPurchase(PurchaseStatus.purchased);
    await _flushEvents();

    expect(service.isKeeper, isTrue);
    expect(platform.completedPurchases, 0);
  });

  test('completePurchase failure leaves entitlement coherent for redelivery',
      () async {
    platform.completeShouldThrow = true;
    expect(await service.buyKeeper(), isTrue);

    platform.emitPurchase(
      PurchaseStatus.purchased,
      pendingCompletePurchase: true,
    );
    await _flushEvents();

    expect(service.isKeeper, isTrue);
    expect(platform.completedPurchases, 1);

    platform.completeShouldThrow = false;
    platform.emitPurchase(
      PurchaseStatus.purchased,
      pendingCompletePurchase: true,
    );
    await _flushEvents();

    expect(service.isKeeper, isTrue);
    expect(platform.completedPurchases, 2);
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

  // EAST. Phase 7 — privacy-safe analytics wiring.
  test(
      'keeper_purchase_started fires once an attempt genuinely begins, and '
      'keeper_purchase_completed fires only once the purchase is persisted',
      () async {
    service.dispose();
    final transport = _FakeAnalyticsTransport();
    service = PurchaseService(
      analyticsService: AnalyticsService(transport: transport),
    );
    await service.init();

    expect(transport.tracked, isEmpty);

    expect(await service.buyKeeper(), isTrue);
    expect(transport.tracked, [AnalyticsEvent.keeperPurchaseStarted]);

    platform.emitPurchase(
      PurchaseStatus.purchased,
      pendingCompletePurchase: true,
    );
    await _flushEvents();

    expect(service.isKeeper, isTrue);
    expect(transport.tracked, [
      AnalyticsEvent.keeperPurchaseStarted,
      AnalyticsEvent.keeperPurchaseCompleted,
    ]);
  });

  test(
      'keeper_purchase_started never fires when a purchase attempt is '
      'blocked before it genuinely begins (already Keeper)', () async {
    service.dispose();
    final transport = _FakeAnalyticsTransport();
    service = PurchaseService(
      entitlementWriter: () async => true,
      analyticsService: AnalyticsService(transport: transport),
    );
    await service.init();
    expect(await service.buyKeeper(), isTrue);
    platform.emitPurchase(
      PurchaseStatus.purchased,
      pendingCompletePurchase: true,
    );
    await _flushEvents();
    transport.tracked.clear();

    // Already Keeper: buyKeeper's own guard returns false before ever
    // reaching the "purchasing" state.
    expect(await service.buyKeeper(), isFalse);
    expect(transport.tracked, isEmpty);
  });

  test(
      'keeper_purchase_completed never fires for a canceled or failed '
      'purchase', () async {
    service.dispose();
    final transport = _FakeAnalyticsTransport();
    service = PurchaseService(
      analyticsService: AnalyticsService(transport: transport),
    );
    await service.init();

    expect(await service.buyKeeper(), isTrue);
    platform.emitPurchase(PurchaseStatus.canceled);
    await _flushEvents();

    expect(service.isKeeper, isFalse);
    expect(transport.tracked, [AnalyticsEvent.keeperPurchaseStarted]);
  });

  test(
      'keeper_purchase_completed never fires twice for a redelivered '
      'duplicate transaction', () async {
    service.dispose();
    final transport = _FakeAnalyticsTransport();
    service = PurchaseService(
      analyticsService: AnalyticsService(transport: transport),
    );
    await service.init();

    expect(await service.buyKeeper(), isTrue);
    platform.emitPurchase(
      PurchaseStatus.purchased,
      pendingCompletePurchase: true,
    );
    await _flushEvents();
    expect(
      transport.tracked
          .where((e) => e == AnalyticsEvent.keeperPurchaseCompleted),
      hasLength(1),
    );

    // StoreKit may redeliver the same transaction; the stream may emit it
    // again with the same purchaseID.
    platform.emitPurchase(
      PurchaseStatus.purchased,
      pendingCompletePurchase: true,
    );
    await _flushEvents();

    expect(
      transport.tracked
          .where((e) => e == AnalyticsEvent.keeperPurchaseCompleted),
      hasLength(1),
    );
  });

  test(
      'keeper_restore_completed fires only once restore actually confirms '
      'Keeper, never when nothing to restore is found', () async {
    service.dispose();
    final transport = _FakeAnalyticsTransport();
    service = PurchaseService(
      restoreResponseWindow: Duration.zero,
      analyticsService: AnalyticsService(transport: transport),
    );
    await service.init();

    // A restore that completes with no matching purchase event at all --
    // the response window simply times out.
    expect(await service.restorePurchases(), isTrue);
    await _flushEvents();
    expect(transport.tracked, isEmpty);

    // A genuine restore that does confirm Keeper.
    expect(await service.restorePurchases(), isTrue);
    platform.emitPurchase(
      PurchaseStatus.restored,
      pendingCompletePurchase: true,
    );
    await _flushEvents();

    expect(service.isKeeper, isTrue);
    expect(transport.tracked, [AnalyticsEvent.keeperRestoreCompleted]);
  });

  test(
      'a failing analytics transport never affects a real purchase or '
      'restore completing', () async {
    service.dispose();
    final transport = _FakeAnalyticsTransport()..shouldThrow = true;
    service = PurchaseService(
      analyticsService: AnalyticsService(transport: transport),
    );
    await service.init();

    expect(await service.buyKeeper(), isTrue);
    platform.emitPurchase(
      PurchaseStatus.purchased,
      pendingCompletePurchase: true,
    );
    await _flushEvents();

    expect(service.isKeeper, isTrue);
    expect(service.entitlementPersistenceFailed, isFalse);
    expect(platform.completedPurchases, 1);
  });
}

class _FakeAnalyticsTransport implements AnalyticsTransport {
  final List<AnalyticsEvent> tracked = [];
  bool shouldThrow = false;

  @override
  void track(AnalyticsEvent event) {
    if (shouldThrow) {
      throw StateError('transport unavailable');
    }
    tracked.add(event);
  }
}

Future<void> _flushEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _FakeInAppPurchasePlatform extends InAppPurchasePlatform {
  late final StreamController<List<PurchaseDetails>> _purchaseController =
      StreamController<List<PurchaseDetails>>.broadcast(
    onListen: () => purchaseStreamSubscriptions++,
  );
  bool _purchaseControllerClosed = false;

  Completer<bool>? buyCompleter;
  Completer<void>? restoreCompleter;
  Completer<ProductDetailsResponse>? productQueryCompleter;
  Object? productQueryError;
  Object? buyError;
  bool? buyResult;
  bool available = true;
  bool completeShouldThrow = false;
  int completedPurchases = 0;
  int restoreCalls = 0;
  int productQueryCalls = 0;
  int purchaseStreamSubscriptions = 0;
  int buyCalls = 0;
  List<ProductDetails>? products;

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
    final error = productQueryError;
    if (error != null) throw error;

    final completer = productQueryCompleter;
    if (completer != null) return completer.future;

    return productResponse(products ?? (available ? [keeperProduct] : []));
  }

  @override
  Future<bool> buyNonConsumable({required PurchaseParam purchaseParam}) {
    buyCalls++;
    final error = buyError;
    if (error != null) throw error;
    final result = buyResult;
    if (result != null) return Future<bool>.value(result);
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
    if (completeShouldThrow) {
      throw StateError('Completion failed.');
    }
  }

  ProductDetailsResponse productResponse(List<ProductDetails> productDetails) {
    return ProductDetailsResponse(
      productDetails: productDetails,
      notFoundIDs: productDetails.any(
        (product) => product.id == PurchaseService.keeperProductId,
      )
          ? const []
          : [PurchaseService.keeperProductId],
    );
  }

  void emitPurchase(
    PurchaseStatus status, {
    String purchaseID = 'keeper-purchase',
    String productID = PurchaseService.keeperProductId,
    bool pendingCompletePurchase = false,
  }) {
    final purchase = PurchaseDetails(
      purchaseID: purchaseID,
      productID: productID,
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

  Future<void> closePurchaseStream() async {
    if (_purchaseControllerClosed) return;
    _purchaseControllerClosed = true;
    await _purchaseController.close();
  }

  Future<void> dispose() => closePurchaseStream();
}
