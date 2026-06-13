import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PurchaseService extends ChangeNotifier {
  static const String keeperProductId = 'com.dailywisdomeast.keeper';
  static const String _premiumKey = 'is_premium_keeper';

  final InAppPurchase _iap = InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? _subscription;

  bool isAvailable = false;
  bool isPremium = false;
  bool isLoading = false;

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

  debugPrint('IAP product details: ${response.productDetails.length}');
  debugPrint('IAP not found IDs: ${response.notFoundIDs}');
  debugPrint('IAP error: ${response.error}');

  if (response.productDetails.isNotEmpty) {
    keeperProduct = response.productDetails.first;
    debugPrint('IAP loaded product: ${keeperProduct!.id}');
  }

  notifyListeners();
}

  Future<void> buyKeeper() async {
    if (keeperProduct == null || isLoading) return;

    isLoading = true;
    notifyListeners();

    final purchaseParam = PurchaseParam(productDetails: keeperProduct!);
    await _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  Future<void> restorePurchases() async {
    if (isLoading) return;

    isLoading = true;
    notifyListeners();

    await _iap.restorePurchases();
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
    _subscription?.cancel();
    super.dispose();
  }
}