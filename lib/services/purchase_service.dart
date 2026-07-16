import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PurchaseServiceStatus {
  initial,
  loadingProduct,
  ready,
  purchasing,
  purchasePending,
  purchased,
  restoring,
  restored,
  canceled,
  failed,
  productUnavailable,
}

class _OperationWaitTimedOut implements Exception {
  const _OperationWaitTimedOut();
}

class PurchaseService extends ChangeNotifier {
  PurchaseService({
    Future<bool> Function()? entitlementWriter,
    this.purchaseInitiationTimeout = const Duration(seconds: 12),
    this.purchaseResponseTimeout = const Duration(seconds: 45),
    this.restoreInitiationTimeout = const Duration(seconds: 12),
    this.restoreResponseWindow = const Duration(seconds: 8),
    this.storeRetryCooldown = const Duration(seconds: 3),
    this.storeAvailabilityTimeout = const Duration(seconds: 8),
    this.productDetailsTimeout = const Duration(seconds: 10),
    this.purchaseOperationRecoveryTimeout = const Duration(seconds: 60),
    this.restoreOperationRecoveryTimeout = const Duration(seconds: 60),
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
  final Duration storeAvailabilityTimeout;
  final Duration productDetailsTimeout;
  final Duration purchaseOperationRecoveryTimeout;
  final Duration restoreOperationRecoveryTimeout;

  StreamSubscription<List<PurchaseDetails>>? _subscription;
  Completer<void>? _restoreStreamSignal;
  Future<void>? _initInProgress;
  Future<bool>? _buyInProgress;
  Future<bool>? _restoreInProgress;
  Future<void> _purchaseEventTail = Future<void>.value();
  Future<bool>? _storeRefreshInProgress;
  DateTime? _lastStoreRefreshAttempt;
  Timer? _purchaseWatchdog;
  Timer? _purchaseOperationRecoveryWatchdog;
  Timer? _purchaseReconciliationWatchdog;
  Timer? _restoreOperationRecoveryWatchdog;
  Timer? _restoreWindowTimer;
  final Set<String> _persistedTransactions = <String>{};
  final Set<String> _completedTransactions = <String>{};

  bool _isAvailable = false;
  bool _isKeeper = false;
  bool _entitlementPersistenceFailed = false;
  bool _disposed = false;
  bool _initialized = false;
  bool _purchasePending = false;
  bool _purchaseUncertain = false;
  bool _restorePending = false;
  bool _restoreUncertain = false;
  bool _currentRestoreMatchedKeeper = false;
  int _storeRefreshGeneration = 0;
  int _restoreSessionId = 0;
  int? _restoreWindowStartedSessionId;
  int? _restoreStreamEventSessionId;
  int _buySessionId = 0;
  int? _purchaseStreamEventSessionId;
  PurchaseServiceStatus _status = PurchaseServiceStatus.initial;

  ProductDetails? _keeperProduct;

  bool get isAvailable => _isAvailable;
  bool get isKeeper => _isKeeper;
  bool get isLoading => _purchasePending || _restorePending;
  bool get entitlementPersistenceFailed => _entitlementPersistenceFailed;
  ProductDetails? get keeperProduct => _keeperProduct;
  PurchaseServiceStatus get status => _status;
  bool get purchaseNeedsRecovery =>
      _purchaseUncertain || _entitlementPersistenceFailed;
  bool get restoreNeedsRecovery => _restoreUncertain;
  bool get isInitialized => _initialized;

  void safeNotifyListeners() {
    if (_disposed) return;
    notifyListeners();
  }

  void _setStatus(PurchaseServiceStatus status) {
    _status = status;
    safeNotifyListeners();
  }

  void _notifyState() {
    safeNotifyListeners();
  }

  Future<void> init() {
    if (_disposed || _initialized) return Future<void>.value();

    final inProgress = _initInProgress;
    if (inProgress != null) return inProgress;

    final initialized = _init();
    _initInProgress = initialized;
    return initialized.whenComplete(() {
      if (identical(_initInProgress, initialized)) {
        _initInProgress = null;
      }
    });
  }

  Future<void> _init() async {
    var streamSubscribed = _subscription != null;
    try {
      await _loadPersistedKeeperEntitlement();
      streamSubscribed = _subscribeToPurchaseStreamOnce();
      await refreshStoreIfNeeded(force: true);
    } catch (_) {
      _isAvailable = false;
      _keeperProduct = null;
      _setStatus(PurchaseServiceStatus.failed);
    } finally {
      if (!_disposed) {
        _initialized = streamSubscribed || _subscription != null;
        _notifyState();
      }
    }
  }

  Future<void> _loadPersistedKeeperEntitlement() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_disposed) return;

      if (prefs.getBool(_keeperKey) == true) {
        _isKeeper = true;
      }
      _notifyState();
    } catch (_) {
      if (!_disposed) {
        _isKeeper = false;
        _notifyState();
      }
    }
  }

  bool _subscribeToPurchaseStreamOnce() {
    if (_subscription != null) return true;
    if (_disposed) return false;

    _subscription = _iap.purchaseStream.listen(
      (purchases) => _enqueuePurchaseEvent(
        () => _handlePurchases(purchases),
      ),
      onError: (_) => _enqueuePurchaseEvent(_handlePurchaseStreamError),
      onDone: () {
        _subscription = null;
        _initialized = false;
        if (_purchasePending) {
          _purchasePending = false;
          _purchaseUncertain = true;
        }
        if (_restorePending) {
          _restorePending = false;
          _restoreUncertain = true;
        }
        _setStatus(PurchaseServiceStatus.failed);
      },
    );
    return true;
  }

  Future<bool> refreshStoreIfNeeded({bool force = false}) {
    if (_disposed) return Future<bool>.value(false);
    if (!force && _isAvailable && _keeperProduct != null) {
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
    final generation = ++_storeRefreshGeneration;
    if (!_purchasePending && !_restorePending) {
      _setStatus(PurchaseServiceStatus.loadingProduct);
    }
    final refresh = _refreshStore(generation);
    _storeRefreshInProgress = refresh;
    return refresh.whenComplete(() {
      if (identical(_storeRefreshInProgress, refresh)) {
        _storeRefreshInProgress = null;
      }
    });
  }

  Future<bool> _refreshStore(int generation) async {
    try {
      final available = await _iap
          .isAvailable()
          .timeout(storeAvailabilityTimeout, onTimeout: () => false);
      if (_disposed) return false;
      if (generation != _storeRefreshGeneration) {
        return _keeperProduct != null;
      }

      _isAvailable = available;

      if (!_isAvailable) {
        _keeperProduct = null;
        _setStatus(PurchaseServiceStatus.productUnavailable);
        return false;
      }

      return _loadProducts(generation);
    } catch (_) {
      if (_disposed) return false;
      if (generation == _storeRefreshGeneration) {
        _isAvailable = false;
        _keeperProduct = null;
        _setStatus(PurchaseServiceStatus.failed);
      }
      return false;
    }
  }

  Future<bool> _loadProducts(int generation) async {
    try {
      final response = await _iap.queryProductDetails(
          {keeperProductId}).timeout(productDetailsTimeout);

      if (_disposed) return false;
      if (generation != _storeRefreshGeneration) {
        return _keeperProduct != null;
      }

      final matchingProducts = response.productDetails
          .where((product) => product.id == keeperProductId)
          .toList(growable: false);
      _keeperProduct = matchingProducts.isEmpty ? null : matchingProducts.first;

      _setStatus(_keeperProduct == null
          ? PurchaseServiceStatus.productUnavailable
          : PurchaseServiceStatus.ready);
      return _keeperProduct != null;
    } catch (_) {
      if (_disposed) return false;
      if (generation == _storeRefreshGeneration) {
        _keeperProduct = null;
        _setStatus(PurchaseServiceStatus.failed);
      }
      return false;
    }
  }

  Future<bool> buyKeeper() {
    final inProgress = _buyInProgress;
    if (inProgress != null) return Future<bool>.value(false);

    final purchase = _buyKeeper();
    _buyInProgress = purchase;
    return purchase.whenComplete(() {
      if (identical(_buyInProgress, purchase)) {
        _buyInProgress = null;
      }
    });
  }

  Future<bool> _buyKeeper() async {
    await init();

    if (_disposed ||
        _isKeeper ||
        _purchasePending ||
        _purchaseUncertain ||
        _restorePending ||
        _restoreUncertain ||
        _entitlementPersistenceFailed) {
      return false;
    }

    if (!_isAvailable || _keeperProduct == null) {
      await refreshStoreIfNeeded();
    }

    if (_disposed ||
        _isKeeper ||
        _purchasePending ||
        _purchaseUncertain ||
        _restorePending ||
        _restoreUncertain ||
        _entitlementPersistenceFailed ||
        !_isAvailable ||
        _keeperProduct == null) {
      return false;
    }

    _entitlementPersistenceFailed = false;
    _purchaseUncertain = false;
    _purchasePending = true;
    final currentBuySessionId = ++_buySessionId;
    _purchaseStreamEventSessionId = null;
    _setStatus(PurchaseServiceStatus.purchasing);

    final purchaseParam = PurchaseParam(productDetails: _keeperProduct!);

    try {
      final nativePurchase = _iap.buyNonConsumable(
        purchaseParam: purchaseParam,
      );
      _startPurchaseOperationRecoveryWatchdog(currentBuySessionId);
      unawaited(
        _observePurchaseInitiation(
          currentBuySessionId,
          nativePurchase,
        ),
      );

      final started = await nativePurchase.timeout(
        purchaseInitiationTimeout,
        onTimeout: () => throw const _OperationWaitTimedOut(),
      );

      if (_purchaseStreamEventSessionId == currentBuySessionId) {
        return _purchaseStreamResolvedBuyResult();
      }
      if (!started && currentBuySessionId == _buySessionId) {
        _cancelPurchaseOperationRecoveryWatchdog();
        _purchasePending = false;
        _purchaseUncertain = false;
        _cancelPurchaseWatchdog();
        _cancelPurchaseReconciliationWatchdog();
        _setStatus(PurchaseServiceStatus.failed);
      } else if (started &&
          currentBuySessionId == _buySessionId &&
          _purchasePending) {
        _cancelPurchaseOperationRecoveryWatchdog();
        _startPurchaseWatchdog(currentBuySessionId);
      }

      return started;
    } on _OperationWaitTimedOut {
      if (_disposed || currentBuySessionId != _buySessionId) return false;
      if (_purchaseStreamEventSessionId == currentBuySessionId) {
        return _purchaseStreamResolvedBuyResult();
      }

      _purchasePending = false;
      _purchaseUncertain = true;
      _cancelPurchaseWatchdog();
      _setStatus(PurchaseServiceStatus.failed);
      return false;
    } catch (_) {
      if (_disposed || currentBuySessionId != _buySessionId) return false;
      if (_purchaseStreamEventSessionId == currentBuySessionId) {
        return _purchaseStreamResolvedBuyResult();
      }

      _purchasePending = false;
      _purchaseUncertain = false;
      _cancelPurchaseOperationRecoveryWatchdog();
      _cancelPurchaseWatchdog();
      _cancelPurchaseReconciliationWatchdog();
      _setStatus(PurchaseServiceStatus.failed);
      return false;
    }
  }

  Future<void> _observePurchaseInitiation(
    int sessionId,
    Future<bool> nativePurchase,
  ) async {
    try {
      final started = await nativePurchase;
      if (_disposed || sessionId != _buySessionId) return;
      if (_purchaseStreamEventSessionId == sessionId) return;
      if (!_purchasePending && !_purchaseUncertain) return;

      if (!started) {
        _cancelPurchaseOperationRecoveryWatchdog();
        _purchasePending = false;
        _purchaseUncertain = false;
        _cancelPurchaseWatchdog();
        _cancelPurchaseReconciliationWatchdog();
        _setStatus(PurchaseServiceStatus.failed);
        return;
      }

      if (_purchaseUncertain && !_purchasePending) {
        _cancelPurchaseOperationRecoveryWatchdog();
        _startPurchaseReconciliationWatchdog(sessionId);
      } else if (_purchasePending) {
        _cancelPurchaseOperationRecoveryWatchdog();
        _startPurchaseWatchdog(sessionId);
      }
    } catch (_) {
      if (_disposed || sessionId != _buySessionId) return;
      if (_purchaseStreamEventSessionId == sessionId) return;
      if (!_purchasePending && !_purchaseUncertain) return;

      _cancelPurchaseOperationRecoveryWatchdog();
      _purchasePending = false;
      _purchaseUncertain = false;
      _cancelPurchaseWatchdog();
      _cancelPurchaseReconciliationWatchdog();
      _setStatus(PurchaseServiceStatus.failed);
    }
  }

  Future<bool> restorePurchases() {
    final inProgress = _restoreInProgress;
    if (inProgress != null) return Future<bool>.value(false);

    final restore = _restorePurchases();
    _restoreInProgress = restore;
    return restore.whenComplete(() {
      if (identical(_restoreInProgress, restore)) {
        _restoreInProgress = null;
      }
    });
  }

  Future<bool> _restorePurchases() async {
    await init();

    if (_disposed ||
        _restorePending ||
        _restoreUncertain ||
        _purchasePending ||
        _purchaseUncertain) {
      return false;
    }

    if (!_isAvailable) {
      await refreshStoreIfNeeded();
    }

    if (_disposed ||
        _restorePending ||
        _restoreUncertain ||
        _purchasePending ||
        _purchaseUncertain ||
        !_isAvailable) {
      return false;
    }

    _restoreUncertain = false;
    _restorePending = true;
    _currentRestoreMatchedKeeper = false;
    final currentRestoreSessionId = ++_restoreSessionId;
    _restoreStreamEventSessionId = null;
    _restoreWindowStartedSessionId = null;
    final streamSignal = Completer<void>();
    _restoreStreamSignal = streamSignal;
    _setStatus(PurchaseServiceStatus.restoring);

    try {
      final nativeRestore = _iap.restorePurchases();
      _startRestoreOperationRecoveryWatchdog(currentRestoreSessionId);
      unawaited(
        _observeRestoreInitiation(
          currentRestoreSessionId,
          streamSignal,
          nativeRestore,
        ),
      );

      await nativeRestore.timeout(
        restoreInitiationTimeout,
        onTimeout: () => throw const _OperationWaitTimedOut(),
      );
      if (_restoreStreamEventSessionId == currentRestoreSessionId) {
        return _restoreStreamResolvedResult();
      }
      _cancelRestoreOperationRecoveryWatchdog();
    } on _OperationWaitTimedOut {
      if (_disposed || currentRestoreSessionId != _restoreSessionId) {
        return false;
      }
      if (_restoreStreamEventSessionId == currentRestoreSessionId) {
        return _restoreStreamResolvedResult();
      }

      _restorePending = false;
      _restoreUncertain = true;
      _setStatus(PurchaseServiceStatus.failed);
      return false;
    } catch (_) {
      if (_disposed || currentRestoreSessionId != _restoreSessionId) {
        return false;
      }
      if (_restoreStreamEventSessionId == currentRestoreSessionId) {
        return _restoreStreamResolvedResult();
      }

      _restorePending = false;
      _restoreUncertain = false;
      _cancelRestoreOperationRecoveryWatchdog();
      if (identical(_restoreStreamSignal, streamSignal)) {
        _restoreStreamSignal = null;
      }
      _setStatus(PurchaseServiceStatus.failed);
      return false;
    }

    _startRestoreWindowIfNeeded(currentRestoreSessionId, streamSignal);
    return true;
  }

  Future<void> _observeRestoreInitiation(
    int sessionId,
    Completer<void> streamSignal,
    Future<void> nativeRestore,
  ) async {
    try {
      await nativeRestore;
    } catch (_) {
      if (_disposed || sessionId != _restoreSessionId) return;
      if (_restoreStreamEventSessionId == sessionId) return;
      if (!_restorePending && !_restoreUncertain) return;

      _cancelRestoreOperationRecoveryWatchdog();
      _restorePending = false;
      _restoreUncertain = false;
      if (identical(_restoreStreamSignal, streamSignal)) {
        _restoreStreamSignal = null;
      }
      _setStatus(PurchaseServiceStatus.failed);
      return;
    }

    if (_disposed || sessionId != _restoreSessionId) return;
    if (_restoreStreamEventSessionId == sessionId) return;
    if (!_restorePending && !_restoreUncertain) return;

    _cancelRestoreOperationRecoveryWatchdog();
    if (_restoreUncertain && !_restorePending) {
      _restoreUncertain = false;
      _restorePending = true;
      _setStatus(PurchaseServiceStatus.restoring);
    }
    _startRestoreWindowIfNeeded(sessionId, streamSignal);
  }

  void _startRestoreWindowIfNeeded(
    int sessionId,
    Completer<void> streamSignal,
  ) {
    if (_restoreWindowStartedSessionId == sessionId) return;
    _restoreWindowStartedSessionId = sessionId;
    unawaited(
      _finishRestoreWindow(sessionId, streamSignal),
    );
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
    if (_restoreWindowStartedSessionId == sessionId) {
      _restoreWindowStartedSessionId = null;
    }
    if (identical(_restoreStreamSignal, streamSignal)) {
      _restoreStreamSignal = null;
    }
    _setStatus(_currentRestoreMatchedKeeper
        ? PurchaseServiceStatus.restored
        : _keeperProduct == null
            ? PurchaseServiceStatus.productUnavailable
            : PurchaseServiceStatus.ready);
  }

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    if (_disposed) return;

    for (final purchase in purchases) {
      if (purchase.productID != keeperProductId) continue;

      final purchaseOperationActive = _purchasePending || _purchaseUncertain;
      final restoreOperationActive = _restorePending || _restoreUncertain;
      final operationActive = purchaseOperationActive || restoreOperationActive;

      if (purchaseOperationActive) {
        _purchaseStreamEventSessionId = _buySessionId;
      }
      if (restoreOperationActive) {
        _restoreStreamEventSessionId = _restoreSessionId;
      }
      var shouldComplete = false;

      if (purchase.status == PurchaseStatus.pending) {
        if (!operationActive) continue;

        _cancelPurchaseOperationRecoveryWatchdog();
        _cancelRestoreOperationRecoveryWatchdog();
        _purchaseUncertain = false;
        _purchasePending = true;
        _cancelPurchaseReconciliationWatchdog();
        _setStatus(PurchaseServiceStatus.purchasePending);
        _startPurchaseWatchdog(_buySessionId);
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
        _entitlementPersistenceFailed = !persisted;
        _purchaseUncertain = false;
        _purchasePending = false;
        _buyInProgress = null;
        _restoreInProgress = null;
        _cancelPurchaseOperationRecoveryWatchdog();
        _cancelPurchaseWatchdog();
        _cancelPurchaseReconciliationWatchdog();
        _cancelRestoreOperationRecoveryWatchdog();
        _restoreUncertain = false;
        _restorePending = false;
        if (purchase.status == PurchaseStatus.restored) {
          _currentRestoreMatchedKeeper = persisted;
        }
        _signalRestoreStream();
        _setStatus(persisted
            ? purchase.status == PurchaseStatus.restored
                ? PurchaseServiceStatus.restored
                : PurchaseServiceStatus.purchased
            : PurchaseServiceStatus.failed);
      } else if (purchase.status == PurchaseStatus.error ||
          purchase.status == PurchaseStatus.canceled) {
        shouldComplete = true;
        if (operationActive) {
          _purchaseUncertain = false;
          _purchasePending = false;
          _buyInProgress = null;
          _restoreInProgress = null;
          _cancelPurchaseOperationRecoveryWatchdog();
          _cancelPurchaseWatchdog();
          _cancelPurchaseReconciliationWatchdog();
          _cancelRestoreOperationRecoveryWatchdog();
          _restoreUncertain = false;
          _restorePending = false;
          _signalRestoreStream();
          _setStatus(purchase.status == PurchaseStatus.canceled
              ? PurchaseServiceStatus.canceled
              : PurchaseServiceStatus.failed);
        }
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

      _notifyState();
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
    _cancelPurchaseOperationRecoveryWatchdog();
    _cancelPurchaseWatchdog();
    _signalRestoreStream();
    _cancelRestoreOperationRecoveryWatchdog();
    _restorePending = false;
    _setStatus(PurchaseServiceStatus.failed);
  }

  bool _purchaseStreamResolvedBuyResult() {
    return _isKeeper ||
        _purchasePending ||
        _status == PurchaseServiceStatus.purchasePending ||
        _status == PurchaseServiceStatus.purchased ||
        _status == PurchaseServiceStatus.restored;
  }

  bool _restoreStreamResolvedResult() {
    return _isKeeper ||
        _restorePending ||
        _status == PurchaseServiceStatus.restoring ||
        _status == PurchaseServiceStatus.restored;
  }

  void _startPurchaseOperationRecoveryWatchdog(int sessionId) {
    _purchaseOperationRecoveryWatchdog?.cancel();
    _purchaseOperationRecoveryWatchdog =
        Timer(purchaseOperationRecoveryTimeout, () {
      if (_disposed ||
          sessionId != _buySessionId ||
          _purchaseStreamEventSessionId == sessionId ||
          (!_purchasePending && !_purchaseUncertain)) {
        return;
      }

      _buySessionId += 1;
      _purchasePending = false;
      _purchaseUncertain = false;
      _buyInProgress = null;
      _cancelPurchaseWatchdog();
      _cancelPurchaseReconciliationWatchdog();
      _purchaseOperationRecoveryWatchdog = null;
      _setStatus(PurchaseServiceStatus.failed);
    });
  }

  void _cancelPurchaseOperationRecoveryWatchdog() {
    _purchaseOperationRecoveryWatchdog?.cancel();
    _purchaseOperationRecoveryWatchdog = null;
  }

  void _startRestoreOperationRecoveryWatchdog(int sessionId) {
    _restoreOperationRecoveryWatchdog?.cancel();
    _restoreOperationRecoveryWatchdog =
        Timer(restoreOperationRecoveryTimeout, () {
      if (_disposed ||
          sessionId != _restoreSessionId ||
          _restoreStreamEventSessionId == sessionId ||
          (!_restorePending && !_restoreUncertain)) {
        return;
      }

      _restoreSessionId += 1;
      _restorePending = false;
      _restoreUncertain = false;
      _restoreInProgress = null;
      if (identical(_restoreWindowStartedSessionId, sessionId)) {
        _restoreWindowStartedSessionId = null;
      }
      _restoreStreamSignal = null;
      _restoreOperationRecoveryWatchdog = null;
      _setStatus(PurchaseServiceStatus.failed);
    });
  }

  void _cancelRestoreOperationRecoveryWatchdog() {
    _restoreOperationRecoveryWatchdog?.cancel();
    _restoreOperationRecoveryWatchdog = null;
  }

  void _startPurchaseWatchdog(int sessionId) {
    _purchaseWatchdog?.cancel();
    _purchaseWatchdog = Timer(purchaseResponseTimeout, () {
      if (_disposed || sessionId != _buySessionId || !_purchasePending) return;

      _purchasePending = false;
      _purchaseUncertain = true;
      _setStatus(PurchaseServiceStatus.failed);
    });
  }

  void _startPurchaseReconciliationWatchdog(int sessionId) {
    _purchaseReconciliationWatchdog?.cancel();
    _purchaseReconciliationWatchdog = Timer(purchaseResponseTimeout, () {
      if (_disposed ||
          sessionId != _buySessionId ||
          _purchasePending ||
          !_purchaseUncertain) {
        return;
      }

      _purchaseUncertain = false;
      _setStatus(PurchaseServiceStatus.failed);
    });
  }

  void _cancelPurchaseWatchdog() {
    _purchaseWatchdog?.cancel();
    _purchaseWatchdog = null;
  }

  void _cancelPurchaseReconciliationWatchdog() {
    _purchaseReconciliationWatchdog?.cancel();
    _purchaseReconciliationWatchdog = null;
  }

  String _transactionKey(PurchaseDetails purchase) {
    final purchaseId = purchase.purchaseID;
    if (purchaseId != null && purchaseId.isNotEmpty) return purchaseId;

    return '${purchase.productID}|${purchase.transactionDate ?? ''}|'
        '${purchase.verificationData.serverVerificationData}';
  }

  Future<bool> _persistKeeperEntitlement() async {
    try {
      if (_isKeeper) return true;

      final entitlementWriter = _entitlementWriter;
      if (entitlementWriter != null) {
        final persisted = await entitlementWriter();
        if (!persisted) return false;
        _isKeeper = true;
        return true;
      }

      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setBool(_keeperKey, true);
      if (!saved || prefs.getBool(_keeperKey) != true) return false;

      _isKeeper = true;
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
    _cancelRestoreOperationRecoveryWatchdog();
    _cancelPurchaseWatchdog();
    _cancelPurchaseOperationRecoveryWatchdog();
    _cancelPurchaseReconciliationWatchdog();
    _restoreWindowTimer?.cancel();
    _restoreWindowTimer = null;
    _signalRestoreStream();
    _subscription?.cancel();
    super.dispose();
  }
}
