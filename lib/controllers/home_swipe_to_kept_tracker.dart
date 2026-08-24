/// Tracks one Home gesture and decides whether it should open Kept.
///
/// This class deliberately knows nothing about Flutter navigation or ritual
/// state. Home supplies whether the action is currently eligible and remains
/// the sole owner of the navigation itself.
class HomeSwipeToKeptTracker {
  static const double distanceThreshold = 60.0;
  static const double velocityThreshold = 320.0;
  static const double horizontalDominanceRatio = 1.6;

  double _dx = 0;
  double _dy = 0;
  bool _handled = false;

  void start() {
    _dx = 0;
    _dy = 0;
    _handled = false;
  }

  void update({required double dx, required double dy}) {
    _dx += dx;
    _dy += dy;
  }

  bool shouldOpenKept({
    required double velocityX,
    required bool isRtl,
    required bool isEligible,
  }) {
    if (_handled || !isEligible) return false;

    final isTowardKept =
        isRtl ? _dx > 0 && velocityX >= 0 : _dx < 0 && velocityX <= 0;
    final horizontalDominant = _dx.abs() > _dy.abs() * horizontalDominanceRatio;
    final meetsThreshold =
        _dx.abs() >= distanceThreshold || velocityX.abs() >= velocityThreshold;

    if (!isTowardKept || !horizontalDominant || !meetsThreshold) {
      return false;
    }

    _handled = true;
    return true;
  }
}
