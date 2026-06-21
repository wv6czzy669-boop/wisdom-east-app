import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PurchaseService extends ChangeNotifier {
  PurchaseService({
    Future<bool> Function()? entitlementWriter,
    this.purchaseInitiationTimeout = const Duration(seconds: 12),
    this.purchaseResponseTimeout = const Duration(seconds: 45),
    this.restoreInitiationTimeout = const Duration(seconds: 12),
    this.restoreResponseWindow = const Duration(seconds: 8),
    this.storeRetryCooldown = const Duration(seconds: 3),
  }) : _entitlementWriter = entitlementWriter;

  static const String keeperProductId = 'com.dailywisdomeast.keeper';
  // Keep the existing persisted key so current Keeper purchases remain active.
  static const String _keeperKey = 'is_premium';

  final InAppPurchase _iap = InAppPurchase.instance;
  final Future<bool> Function()? _entitlementWriter;
  final Duration purchaseInitiationTimeout;
  final Duration purchaseResponseTimeout;
  final Duration restoreInitiationTimeout;
  final Duration restoreResponseWindow;
  final Duration storeRetryCooldown;

  StreamSubscription<List<PurchaseDetails>>? _subscription;
  Completer<void>? _restoreStreamSignal;
  Future<void> _purchaseEventTail = Future<void>.value();
  Future<bool>? _storeRefreshInProgress;
  DateTime? _lastStoreRefreshAttempt;
  Timer? _purchaseWatchdog;
  Timer? _restoreWindowTimer;
  final Set<String> _persistedTransactions = <String>{};
  final Set<String> _completedTransactions = <String>{};

  bool isAvailable = false;
  bool isKeeper = false;
  bool isLoading = false;
  bool entitlementPersistenceFailed = false;
  bool _disposed = false;
  bool _initialized = false;
  bool _purchasePending = false;
  bool _purchaseUncertain = false;
  bool _restorePending = false;
  bool _restoreUncertain = false;
  int _restoreSessionId = 0;
  int _buySessionId = 0;

  ProductDetails? keeperProduct;

  bool get purchaseNeedsRecovery =>
      _purchaseUncertain || entitlementPersistenceFailed;
  bool get restoreNeedsRecovery => _restoreUncertain;
  bool get isInitialized => _initialized;

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
        (purchases) => _enqueuePurchaseEvent(
          () => _handlePurchases(purchases),
        ),
        onError: (_) => _enqueuePurchaseEvent(_handlePurchaseStreamError),
      );

      await refreshStoreIfNeeded(force: true);
    } catch (_) {
      isAvailable = false;
      isLoading = false;
      safeNotifyListeners();
    } finally {
      if (!_disposed) {
        _initialized = true;
      }
    }
  }

  Future<bool> refreshStoreIfNeeded({bool force = false}) {
    if (_disposed) return Future<bool>.value(false);
    if (isAvailable && keeperProduct != null) {
      return Future<bool>.value(true);
    }

    final inProgress = _storeRefreshInProgress;
    if (inProgress != null) return inProgress;

    final now = DateTime.now();
    final lastAttempt = _lastStoreRefreshAttempt;
    if (!force &&
        lastAttempt != null &&
        now.difference(lastAttempt) < storeRetryCooldown) {
      return Future<bool>.value(false);
    }

    _lastStoreRefreshAttempt = now;
    final refresh = _refreshStore();
    _storeRefreshInProgress = refresh;
    return refresh.whenComplete(() {
      if (identical(_storeRefreshInProgress, refresh)) {
        _storeRefreshInProgress = null;
      }
    });
  }

  Future<bool> _refreshStore() async {
    try {
      isAvailable = await _iap
          .isAvailable()
          .timeout(const Duration(seconds: 8), onTimeout: () => false);
      if (_disposed) return false;

      if (!isAvailable) {
        keeperProduct = null;
        safeNotifyListeners();
        return false;
      }

      return _loadProducts();
    } catch (_) {
      if (_disposed) return false;
      isAvailable = false;
      keeperProduct = null;
      safeNotifyListeners();
      return false;
    }
  }

  Future<bool> _loadProducts() async {
    try {
      final response = await _iap.queryProductDetails(
          {keeperProductId}).timeout(const Duration(seconds: 10));

      if (_disposed) return false;

      keeperProduct = response.productDetails.isEmpty
          ? null
          : response.productDetails.first;

      safeNotifyListeners();
      return keeperProduct != null;
    } catch (_) {
      if (_disposed) return false;
      keeperProduct = null;
      safeNotifyListeners();
      return false;
    }
  }

  Future<bool> buyKeeper() async {
    if (_disposed ||
        isKeeper ||
        isLoading ||
        _purchaseUncertain ||
        entitlementPersistenceFailed) {
      return false;
    }

    if (!isAvailable || keeperProduct == null) {
      await refreshStoreIfNeeded();
    }

    if (_disposed ||
        isKeeper ||
        isLoading ||
        _purchaseUncertain ||
        entitlementPersistenceFailed ||
        !isAvailable ||
        keeperProduct == null) {
      return false;
    }

    entitlementPersistenceFailed = false;
    _purchaseUncertain = false;
    _purchasePending = true;
    final currentBuySessionId = ++_buySessionId;
    _refreshLoadingState();

    final purchaseParam = PurchaseParam(productDetails: keeperProduct!);

    try {
      final started = await _iap
          .buyNonConsumable(
            purchaseParam: purchaseParam,
          )
          .timeout(purchaseInitiationTimeout);

      if (!started && currentBuySessionId == _buySessionId) {
        _purchasePending = false;
        _purchaseUncertain = false;
        _cancelPurchaseWatchdog();
        _refreshLoadingState();
      } else if (started &&
          currentBuySessionId == _buySessionId &&
          _purchasePending) {
        _startPurchaseWatchdog(currentBuySessionId);
      }

      return started;
    } catch (_) {
      if (_disposed || currentBuySessionId != _buySessionId) return false;

      _purchasePending = false;
      _purchaseUncertain = true;
      _cancelPurchaseWatchdog();
      _refreshLoadingState();
      return false;
    }
  }

  Future<bool> restorePurchases() async {
    if (_disposed || _restorePending || _restoreUncertain || _purchasePending) {
      return false;
    }

    if (!isAvailable) {
      await refreshStoreIfNeeded();
    }

    if (_disposed ||
        _restorePending ||
        _restoreUncertain ||
        _purchasePending ||
        !isAvailable) {
      return false;
    }

    _restoreUncertain = false;
    _restorePending = true;
    final currentRestoreSessionId = ++_restoreSessionId;
    final streamSignal = Completer<void>();
    _restoreStreamSignal = streamSignal;
    _refreshLoadingState();

    try {
      await _iap.restorePurchases().timeout(restoreInitiationTimeout);
    } on TimeoutException {
      if (_disposed || currentRestoreSessionId != _restoreSessionId) {
        return false;
      }

      _restorePending = false;
      _restoreUncertain = true;
      if (identical(_restoreStreamSignal, streamSignal)) {
        _restoreStreamSignal = null;
      }
      _refreshLoadingState();
      return false;
    } catch (_) {
      if (_disposed || currentRestoreSessionId != _restoreSessionId) {
        return false;
      }

      _restorePending = false;
      _restoreUncertain = false;
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
    final timeoutSignal = Completer<void>();
    _restoreWindowTimer?.cancel();
    final timer = Timer(restoreResponseWindow, timeoutSignal.complete);
    _restoreWindowTimer = timer;

    await Future.any([
      streamSignal.future,
      timeoutSignal.future,
    ]);

    timer.cancel();
    if (identical(_restoreWindowTimer, timer)) {
      _restoreWindowTimer = null;
    }

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
        _purchaseUncertain = false;
        _purchasePending = true;
        _startPurchaseWatchdog(_buySessionId);
        _refreshLoadingState();
        continue;
      }

      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        final transactionKey = _transactionKey(purchase);
        var persisted = _persistedTransactions.contains(transactionKey);
        if (!persisted) {
          persisted = await _persistKeeperEntitlement();
          if (persisted) {
            _persistedTransactions.add(transactionKey);
          }
        }
        shouldComplete = persisted;
        entitlementPersistenceFailed = !persisted;
        _purchaseUncertain = false;
        _purchasePending = false;
        _cancelPurchaseWatchdog();
        _restoreUncertain = false;
        _signalRestoreStream();
      } else if (purchase.status == PurchaseStatus.error ||
          purchase.status == PurchaseStatus.canceled) {
        shouldComplete = true;
        _purchaseUncertain = false;
        _purchasePending = false;
        _cancelPurchaseWatchdog();
        _restoreUncertain = false;
        _signalRestoreStream();
      }

      final transactionKey = _transactionKey(purchase);
      if (shouldComplete &&
          purchase.pendingCompletePurchase &&
          !_completedTransactions.contains(transactionKey)) {
        try {
          await _iap.completePurchase(purchase);
          _completedTransactions.add(transactionKey);
        } catch (_) {
          // StoreKit will redeliver unfinished transactions for another attempt.
        }
      }

      _refreshLoadingState();
    }
  }

  void _enqueuePurchaseEvent(Future<void> Function() operation) {
    final next = _purchaseEventTail.then((_) => operation());
    _purchaseEventTail = next.catchError((_) {});
  }

  Future<void> _handlePurchaseStreamError() async {
    if (_disposed) return;

    if (_purchasePending) {
      _purchaseUncertain = true;
    }
    if (_restorePending) {
      _restoreUncertain = true;
    }
    _purchasePending = false;
    _cancelPurchaseWatchdog();
    _signalRestoreStream();
    _restorePending = false;
    _refreshLoadingState();
  }

  void _startPurchaseWatchdog(int sessionId) {
    _purchaseWatchdog?.cancel();
    _purchaseWatchdog = Timer(purchaseResponseTimeout, () {
      if (_disposed || sessionId != _buySessionId || !_purchasePending) return;

      _purchasePending = false;
      _purchaseUncertain = true;
      _refreshLoadingState();
    });
  }

  void _cancelPurchaseWatchdog() {
    _purchaseWatchdog?.cancel();
    _purchaseWatchdog = null;
  }

  String _transactionKey(PurchaseDetails purchase) {
    final purchaseId = purchase.purchaseID;
    if (purchaseId != null && purchaseId.isNotEmpty) return purchaseId;

    return '${purchase.productID}|${purchase.transactionDate ?? ''}|'
        '${purchase.verificationData.serverVerificationData}';
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
    _cancelPurchaseWatchdog();
    _restoreWindowTimer?.cancel();
    _restoreWindowTimer = null;
    _signalRestoreStream();
    _subscription?.cancel();
    super.dispose();
  }
}
