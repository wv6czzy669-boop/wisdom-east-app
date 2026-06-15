import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PurchaseService extends ChangeNotifier {
  static const String keeperProductId = 'com.dailywisdomeast.keeper';
  static const String _premiumKey = 'is_premium';

  final InAppPurchase _iap = InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? _subscription;

  bool isAvailable = false;
  bool isPremium = false;
  bool isLoading = false;
  bool _disposed = false;
  int _restoreSessionId = 0;
  int _buySessionId = 0;

  ProductDetails? keeperProduct;

  void safeNotifyListeners() {
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_disposed) return;

      isPremium = prefs.getBool(_premiumKey) ?? false;
      safeNotifyListeners();

      isAvailable = await _iap
          .isAvailable()
          .timeout(const Duration(seconds: 8), onTimeout: () => false);

      if (_disposed) return;

      if (!isAvailable) {
        safeNotifyListeners();
        return;
      }

      await _subscription?.cancel();

      _subscription = _iap.purchaseStream.listen(
        _handlePurchases,
        onError: (_) {
          isLoading = false;
          safeNotifyListeners();
        },
      );

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
    if (_disposed || isLoading) return false;

    if (!isAvailable || keeperProduct == null) {
      return false;
    }

    isLoading = true;
    final currentBuySessionId = ++_buySessionId;
    safeNotifyListeners();

    final purchaseParam = PurchaseParam(productDetails: keeperProduct!);

    try {
      final started = await _iap
          .buyNonConsumable(purchaseParam: purchaseParam)
          .timeout(const Duration(seconds: 12), onTimeout: () => false);

      Future.delayed(const Duration(seconds: 20), () {
        if (_disposed || currentBuySessionId != _buySessionId) return;

        if (isLoading) {
          isLoading = false;
          safeNotifyListeners();
        }
      });

      return started;
    } catch (_) {
      if (_disposed || currentBuySessionId != _buySessionId) return false;

      isLoading = false;
      safeNotifyListeners();
      return false;
    }
  }

  Future<void> restorePurchases() async {
    if (_disposed || isLoading) return;

    isLoading = true;
    final currentRestoreSessionId = ++_restoreSessionId;
    safeNotifyListeners();

    try {
      await _iap.restorePurchases().timeout(const Duration(seconds: 12));
    } catch (_) {
      if (_disposed || currentRestoreSessionId != _restoreSessionId) return;

      isLoading = false;
      safeNotifyListeners();
      return;
    }

    Future.delayed(const Duration(seconds: 8), () {
      if (_disposed || currentRestoreSessionId != _restoreSessionId) return;

      if (isLoading) {
        isLoading = false;
        safeNotifyListeners();
      }
    });
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    if (_disposed) return;

    for (final purchase in purchases) {
      try {
        if (purchase.productID == keeperProductId) {
          if (purchase.status == PurchaseStatus.purchased ||
              purchase.status == PurchaseStatus.restored) {
            await _unlockPremium();
          }

          if (purchase.status == PurchaseStatus.error ||
              purchase.status == PurchaseStatus.canceled) {
            isLoading = false;
            safeNotifyListeners();
          }
        }
      } finally {
        if (purchase.pendingCompletePurchase) {
          try {
            await _iap.completePurchase(purchase);
          } catch (_) {}
        }
      }
    }

    isLoading = false;
    safeNotifyListeners();
  }

  Future<void> _unlockPremium() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_premiumKey, true);

      isPremium = true;
    } catch (_) {
      // Purchase completion still happens in _handlePurchases finally.
    } finally {
      isLoading = false;
      safeNotifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _restoreSessionId += 1;
    _buySessionId += 1;
    _subscription?.cancel();
    super.dispose();
  }
}
