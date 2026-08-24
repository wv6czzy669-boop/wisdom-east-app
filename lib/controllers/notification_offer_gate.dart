import 'dart:async';

typedef RunNotificationOffer = Future<void> Function();

/// Single-flight lifecycle for Home's delayed notification-permission offer.
///
/// [isBusy] stays true continuously from scheduling through the completion
/// of the asynchronous offer. [isShowing] flips synchronously before the
/// callback's first await, preserving the gesture/navigation race guard.
class NotificationOfferGate {
  Timer? _timer;
  bool _scheduled = false;
  bool _showing = false;
  bool _disposed = false;

  bool get isBusy => _scheduled || _showing;
  bool get isShowing => _showing;

  bool schedule({
    required Duration delay,
    required RunNotificationOffer runOffer,
  }) {
    if (_disposed || isBusy) return false;

    _scheduled = true;
    _timer = Timer(delay, () {
      _timer = null;
      if (_disposed) return;
      _showing = true;
      unawaited(
        Future<void>.sync(runOffer).catchError((_) {
          // Permission offers are optional and never affect the ritual.
        }).whenComplete(() {
          _scheduled = false;
          _showing = false;
        }),
      );
    });
    return true;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _scheduled = false;
    _showing = false;
  }
}
