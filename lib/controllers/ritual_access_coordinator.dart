import '../services/daily_wisdom_access_service.dart';
import 'latest_request_guard.dart';
import 'ritual_access_view_state.dart';

typedef LoadDailyWisdomStatus = Future<DailyWisdomStatus> Function();

/// Loads Home's daily-access presentation with newest-request-wins ordering.
///
/// A `null` result means a newer refresh superseded this one or the
/// coordinator was disposed. Failures from the current request resolve to an
/// explicit unresolved state, preserving Home's established retry behavior.
class RitualAccessCoordinator {
  RitualAccessCoordinator({required LoadDailyWisdomStatus loadStatus})
      : _loadStatus = loadStatus;

  final LoadDailyWisdomStatus _loadStatus;
  final LatestRequestGuard _guard = LatestRequestGuard();
  bool _disposed = false;

  Future<RitualAccessViewState?> refresh() async {
    if (_disposed) return null;
    final generation = _guard.begin();

    RitualAccessViewState state;
    try {
      final status = await _loadStatus();
      state = RitualAccessViewState.fromStatus(status);
    } catch (_) {
      state = const RitualAccessViewState.unresolved();
    }

    if (_disposed || !_guard.isCurrent(generation)) return null;
    return state;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _guard.invalidate();
  }
}
