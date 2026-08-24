import 'dart:async';

typedef DiscoveryActiveChanged = void Function(bool active);
typedef DiscoveryShouldContinue = bool Function();

/// Owns the three independent timer chains used by Home's Kept discovery.
///
/// It contains timing only: Home remains the owner of eligibility,
/// persistence, copy and visible state. Cancelling invalidates the central
/// breath generation so no stale callback can reach a replacement wisdom.
class KeptDiscoveryTimerController {
  KeptDiscoveryTimerController({
    this.centralFirstDelay = const Duration(milliseconds: 250),
    this.centralActiveDuration = const Duration(milliseconds: 1200),
    this.centralPause = const Duration(milliseconds: 200),
    this.savedTextDuration = const Duration(milliseconds: 1300),
    this.navFirstDelay = Duration.zero,
    this.navActiveDuration = const Duration(milliseconds: 1050),
    this.navPause = const Duration(milliseconds: 165),
  });

  final Duration centralFirstDelay;
  final Duration centralActiveDuration;
  final Duration centralPause;
  final Duration savedTextDuration;
  final Duration navFirstDelay;
  final Duration navActiveDuration;
  final Duration navPause;

  Timer? _centralTimer;
  Timer? _savedTextTimer;
  Timer? _navTimer;
  int _centralGeneration = 0;
  bool _disposed = false;

  bool get hasNavTimer => _navTimer != null;

  void startCentralBreathing({
    required DiscoveryActiveChanged onActiveChanged,
    required DiscoveryShouldContinue shouldContinue,
  }) {
    if (_disposed) return;
    _centralTimer?.cancel();
    final generation = ++_centralGeneration;
    _centralTimer = Timer(
      centralFirstDelay,
      () => _beginCentralBreath(
        generation,
        onActiveChanged,
        shouldContinue,
      ),
    );
  }

  void _beginCentralBreath(
    int generation,
    DiscoveryActiveChanged onActiveChanged,
    DiscoveryShouldContinue shouldContinue,
  ) {
    if (!_isCurrentCentral(generation)) return;
    onActiveChanged(true);
    _centralTimer = Timer(
      centralActiveDuration,
      () => _endCentralBreath(
        generation,
        onActiveChanged,
        shouldContinue,
      ),
    );
  }

  void _endCentralBreath(
    int generation,
    DiscoveryActiveChanged onActiveChanged,
    DiscoveryShouldContinue shouldContinue,
  ) {
    if (!_isCurrentCentral(generation)) return;
    onActiveChanged(false);
    if (!shouldContinue()) {
      _centralTimer = null;
      return;
    }
    _centralTimer = Timer(
      centralPause,
      () => _beginCentralBreath(
        generation,
        onActiveChanged,
        shouldContinue,
      ),
    );
  }

  bool _isCurrentCentral(int generation) {
    return !_disposed && generation == _centralGeneration;
  }

  void scheduleSavedTextHide(void Function() onHide) {
    if (_disposed) return;
    _savedTextTimer?.cancel();
    _savedTextTimer = Timer(savedTextDuration, () {
      _savedTextTimer = null;
      if (!_disposed) onHide();
    });
  }

  void startNavBreathing({
    required DiscoveryActiveChanged onActiveChanged,
    required DiscoveryShouldContinue shouldContinue,
  }) {
    if (_disposed) return;
    _navTimer?.cancel();
    _navTimer = Timer(
      navFirstDelay,
      () => _beginNavBreath(onActiveChanged, shouldContinue),
    );
  }

  void _beginNavBreath(
    DiscoveryActiveChanged onActiveChanged,
    DiscoveryShouldContinue shouldContinue,
  ) {
    if (_disposed || !shouldContinue()) {
      _navTimer = null;
      return;
    }
    onActiveChanged(true);
    _navTimer = Timer(
      navActiveDuration,
      () => _endNavBreath(onActiveChanged, shouldContinue),
    );
  }

  void _endNavBreath(
    DiscoveryActiveChanged onActiveChanged,
    DiscoveryShouldContinue shouldContinue,
  ) {
    if (_disposed) return;
    onActiveChanged(false);
    if (!shouldContinue()) {
      _navTimer = null;
      return;
    }
    _navTimer = Timer(
      navPause,
      () => _beginNavBreath(onActiveChanged, shouldContinue),
    );
  }

  void cancelNav() {
    _navTimer?.cancel();
    _navTimer = null;
  }

  void cancelAll() {
    _centralGeneration++;
    _centralTimer?.cancel();
    _centralTimer = null;
    _savedTextTimer?.cancel();
    _savedTextTimer = null;
    cancelNav();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    cancelAll();
  }
}
