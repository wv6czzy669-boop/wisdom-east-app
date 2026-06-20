import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PurchaseService extends ChangeNotifier {
  PurchaseService({
    Future<bool> Function()? entitlementWriter,
  }) : _entitlementWriter = entitlementWriter;

  static const String keeperProductId = 'com.dailywisdomeast.keeper';
  // Keep the existing persisted key so current Keeper purchases remain active.
  static const String _keeperKey = 'is_premium';

  final InAppPurchase _iap = InAppPurchase.instance;
  final Future<bool> Function()? _entitlementWriter;

  StreamSubscription<List<PurchaseDetails>>? _subscription;
  Completer<void>? _restoreStreamSignal;

  bool isAvailable = false;
  bool isKeeper = false;
  bool isLoading = false;
  bool entitlementPersistenceFailed = false;
  bool _disposed = false;
  bool _purchasePending = false;
  bool _restorePending = false;
  int _restoreSessionId = 0;
  int _buySessionId = 0;

  ProductDetails? keeperProduct;

  void safeNotifyListeners() {
    if (_disposed) return;
    notifyListeners();
  }

  void _refreshLoadingState() {
    isLoading = _purchasePending || _restorePending;
    safeNotifyListeners();
  }

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_disposed) return;

      isKeeper = prefs.getBool(_keeperKey) ?? false;
      safeNotifyListeners();

      await _subscription?.cancel();

      _subscription = _iap.purchaseStream.listen(
        _handlePurchases,
        onError: (_) {
          _purchasePending = false;
          _signalRestoreStream();
          _restorePending = false;
          _refreshLoadingState();
        },
      );

      isAvailable = await _iap
          .isAvailable()
          .timeout(const Duration(seconds: 8), onTimeout: () => false);

      if (_disposed) return;

      if (!isAvailable) {
        safeNotifyListeners();
        return;
      }

      await _loadProducts();
    } catch (_) {
      isAvailable = false;
      isLoading = false;
      safeNotifyListeners();
    }
  }

  Future<void> _loadProducts() async {
    try {
      final response = await _iap.queryProductDetails(
          {keeperProductId}).timeout(const Duration(seconds: 10));

      if (_disposed) return;

      if (response.productDetails.isNotEmpty) {
        keeperProduct = response.productDetails.first;
      }

      safeNotifyListeners();
    } catch (_) {
      keeperProduct = null;
      safeNotifyListeners();
    }
  }

  Future<bool> buyKeeper() async {
    if (_disposed || isKeeper || isLoading || entitlementPersistenceFailed) {
      return false;
    }

    if (!isAvailable || keeperProduct == null) {
      return false;
    }

    entitlementPersistenceFailed = false;
    _purchasePending = true;
    final currentBuySessionId = ++_buySessionId;
    _refreshLoadingState();

    final purchaseParam = PurchaseParam(productDetails: keeperProduct!);

    try {
      final started = await _iap.buyNonConsumable(
        purchaseParam: purchaseParam,
      );

      if (!started && currentBuySessionId == _buySessionId) {
        _purchasePending = false;
        _refreshLoadingState();
      }

      return started;
    } catch (_) {
      if (_disposed || currentBuySessionId != _buySessionId) return false;

      _purchasePending = false;
      _refreshLoadingState();
      return false;
    }
  }

  Future<bool> restorePurchases() async {
    if (_disposed || isLoading || !isAvailable) return false;

    _restorePending = true;
    final currentRestoreSessionId = ++_restoreSessionId;
    final streamSignal = Completer<void>();
    _restoreStreamSignal = streamSignal;
    _refreshLoadingState();

    try {
      await _iap.restorePurchases().timeout(const Duration(seconds: 12));
    } catch (_) {
      if (_disposed || currentRestoreSessionId != _restoreSessionId) {
        return false;
      }

      _restorePending = false;
      if (identical(_restoreStreamSignal, streamSignal)) {
        _restoreStreamSignal = null;
      }
      _refreshLoadingState();
      return false;
    }

    unawaited(
      _finishRestoreWindow(currentRestoreSessionId, streamSignal),
    );
    return true;
  }

  Future<void> _finishRestoreWindow(
    int sessionId,
    Completer<void> streamSignal,
  ) async {
    await Future.any([
      streamSignal.future,
      Future<void>.delayed(const Duration(seconds: 8)),
    ]);

    if (_disposed || sessionId != _restoreSessionId) return;

    _restorePending = false;
    if (identical(_restoreStreamSignal, streamSignal)) {
      _restoreStreamSignal = null;
    }
    _refreshLoadingState();
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    if (_disposed) return;

    for (final purchase in purchases) {
      if (purchase.productID != keeperProductId) continue;

      var shouldComplete = false;

      if (purchase.status == PurchaseStatus.pending) {
        _purchasePending = true;
        _refreshLoadingState();
        continue;
      }

      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        final persisted = await _persistKeeperEntitlement();
        shouldComplete = persisted;
        entitlementPersistenceFailed = !persisted;
        _purchasePending = false;
        _signalRestoreStream();
      } else if (purchase.status == PurchaseStatus.error ||
          purchase.status == PurchaseStatus.canceled) {
        shouldComplete = true;
        _purchasePending = false;
        _signalRestoreStream();
      }

      if (shouldComplete && purchase.pendingCompletePurchase) {
        try {
          await _iap.completePurchase(purchase);
        } catch (_) {
          // StoreKit will redeliver unfinished transactions for another attempt.
        }
      }

      _refreshLoadingState();
    }
  }

  Future<bool> _persistKeeperEntitlement() async {
    try {
      final entitlementWriter = _entitlementWriter;
      if (entitlementWriter != null) {
        final persisted = await entitlementWriter();
        if (!persisted) return false;
        isKeeper = true;
        return true;
      }

      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setBool(_keeperKey, true);
      if (!saved || prefs.getBool(_keeperKey) != true) return false;

      isKeeper = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  void _signalRestoreStream() {
    final signal = _restoreStreamSignal;
    if (signal != null && !signal.isCompleted) {
      signal.complete();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _restoreSessionId += 1;
    _buySessionId += 1;
    _signalRestoreStream();
    _subscription?.cancel();
    super.dispose();
  }
}
