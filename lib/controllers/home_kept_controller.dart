import '../models/favorite_item.dart';
import 'latest_request_guard.dart';

typedef LoadHomeKeptItems = Future<List<FavoriteItem>> Function();
typedef KeepHomeWisdom = Future<HomeKeptWriteResult> Function(
  HomeKeepRequest request,
);

class HomeKeepRequest {
  const HomeKeepRequest({
    required this.text,
    required this.date,
    required this.isKeeper,
    required this.revealId,
    required this.revealedAt,
    this.wisdomId,
  });

  final String text;
  final String date;
  final bool isKeeper;
  final String revealId;
  final DateTime revealedAt;
  final String? wisdomId;
}

class HomeKeptWriteResult {
  const HomeKeptWriteResult({
    required this.items,
    required this.limitReached,
  });

  final List<FavoriteItem> items;
  final bool limitReached;
}

enum HomeKeepStatus { kept, limitReached, failed }

class HomeKeepResult {
  const HomeKeepResult._(this.status);

  const HomeKeepResult.kept() : this._(HomeKeepStatus.kept);
  const HomeKeepResult.limitReached() : this._(HomeKeepStatus.limitReached);
  const HomeKeepResult.failed() : this._(HomeKeepStatus.failed);

  final HomeKeepStatus status;
}

/// Owns Home's non-visual projection of Kept occurrences.
///
/// The screen remains responsible for whether the Keep control is currently
/// eligible, for feedback/overlays, and for navigation. This controller owns
/// only identity-based matching, failure-preserving loads, the one Keep write,
/// and newest-wins refreshes requested after an incoming CloudKit change.
class HomeKeptController {
  HomeKeptController({
    required LoadHomeKeptItems loadItems,
    required KeepHomeWisdom keepWisdom,
  })  : _loadItems = loadItems,
        _keepWisdom = keepWisdom;

  final LoadHomeKeptItems _loadItems;
  final KeepHomeWisdom _keepWisdom;
  final LatestRequestGuard _incomingRefreshGuard = LatestRequestGuard();

  List<FavoriteItem> _items = const <FavoriteItem>[];

  List<FavoriteItem> get items => _items;

  FavoriteItem? currentFavorite(String? revealId) {
    if (revealId == null) return null;
    for (final item in _items) {
      if (item.revealId == revealId) return item;
    }
    return null;
  }

  bool isCurrentFavorite(String? revealId) => currentFavorite(revealId) != null;

  /// Loads the current projection. A failure deliberately preserves the
  /// last known list instead of turning a transient protected-storage error
  /// into a visible empty state.
  Future<bool> load() async {
    try {
      _items = List<FavoriteItem>.unmodifiable(await _loadItems());
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<HomeKeepResult> keep(HomeKeepRequest request) async {
    try {
      final result = await _keepWisdom(request);
      if (result.limitReached) {
        return const HomeKeepResult.limitReached();
      }
      _items = List<FavoriteItem>.unmodifiable(result.items);
      return const HomeKeepResult.kept();
    } catch (_) {
      return const HomeKeepResult.failed();
    }
  }

  /// Re-loads after a durable incoming Kept-state notification. If multiple
  /// notifications overlap, only the newest request may replace the screen's
  /// projection, even when an older read completes last.
  Future<bool> refreshAfterIncomingChange() async {
    final generation = _incomingRefreshGuard.begin();
    late final List<FavoriteItem> loaded;
    try {
      loaded = await _loadItems();
    } catch (_) {
      return false;
    }
    if (!_incomingRefreshGuard.isCurrent(generation)) return false;
    _items = List<FavoriteItem>.unmodifiable(loaded);
    return true;
  }

  void dispose() {
    _incomingRefreshGuard.invalidate();
  }
}
