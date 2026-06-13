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

  ProductDetails? keeperProduct;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    isPremium = prefs.getBool(_premiumKey) ?? false;
    notifyListeners();

    isAvailable = await _iap.isAvailable();

    if (!isAvailable) {
      notifyListeners();
      return;
    }

    _subscription = _iap.purchaseStream.listen(
      _handlePurchases,
      onError: (_) {
        isLoading = false;
        notifyListeners();
      },
    );

    await _loadProducts();
  }

  Future<void> _loadProducts() async {
  final response = await _iap.queryProductDetails({keeperProductId});

  if (response.productDetails.isNotEmpty) {
    keeperProduct = response.productDetails.first;
  }

  notifyListeners();
}

  Future<bool> buyKeeper() async {
  if (isLoading) return false;

  if (!isAvailable || keeperProduct == null) {
    return false;
  }

  isLoading = true;
  notifyListeners();

  final purchaseParam = PurchaseParam(productDetails: keeperProduct!);
  try {
  return await _iap.buyNonConsumable(purchaseParam: purchaseParam);
} catch (_) {
  isLoading = false;
  notifyListeners();
  return false;
}
}

  Future<void> restorePurchases() async {
  if (isLoading) return;

  isLoading = true;
  notifyListeners();

  try {
  await _iap.restorePurchases();
} catch (_) {
  isLoading = false;
  notifyListeners();
  return;
}

  Future.delayed(const Duration(seconds: 3), () {
  if (!_disposed && isLoading) {
    isLoading = false;
    notifyListeners();
  }
});
}

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.productID == keeperProductId) {
        if (purchase.status == PurchaseStatus.purchased ||
            purchase.status == PurchaseStatus.restored) {
          await _unlockPremium();
        }

        if (purchase.status == PurchaseStatus.error ||
            purchase.status == PurchaseStatus.canceled) {
          isLoading = false;
          notifyListeners();
        }
      }

      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }

    isLoading = false;
    notifyListeners();
  }

  Future<void> _unlockPremium() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_premiumKey, true);

    isPremium = true;
    isLoading = false;
    notifyListeners();
  }

  @override
void dispose() {
  _disposed = true;
  _subscription?.cancel();
  super.dispose();
}
}