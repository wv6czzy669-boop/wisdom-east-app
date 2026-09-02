import 'dart:math';

import '../data/wisdoms.dart';
import '../persistence/persistence_operation_coordinator.dart';
import '../persistence/wisdom_selection_history_store.dart';

/// Selects a varied wisdom while keeping recent occurrences device-local.
///
/// The last [recentWisdomLimit] canonical occurrences survive process
/// restarts. Normal draws avoid that rolling history, while deliberately tiny
/// repeat lanes keep the book-like possibility of meeting a wisdom again.
/// The history is deliberately independent of the daily-access and Kept
/// domains: losing it may reduce variety, but can never block a ritual or
/// alter user data. Reads and writes therefore fail open.
class WisdomSelectorService {
  WisdomSelectorService({
    WisdomSelectionHistoryStore? historyStore,
    Random? random,
    List<Map<String, dynamic>>? catalog,
    PersistenceOperationCoordinator? operationCoordinator,
  })  : _historyStore =
            historyStore ?? SharedPreferencesWisdomSelectionHistoryStore(),
        _random = random ?? Random(),
        _catalog = List<Map<String, dynamic>>.unmodifiable(
          catalog ?? wisdoms,
        ),
        _operationCoordinator =
            operationCoordinator ?? PersistenceOperationCoordinator() {
    _catalogById = <String, Map<String, dynamic>>{
      for (final wisdom in _catalog)
        if (wisdom['id'] case final String id) id: wisdom,
    };
  }

  /// One selection per rolling 24 hours makes this an approximate month.
  static const int recentWisdomLimit = 30;

  /// Probability scale used by the repeat policy: 1 point = 0.01%.
  static const int probabilityBasisPoints = 10000;

  /// The immediately previous wisdom may recur on 0.20% of draws.
  static const int consecutiveRepeatBasisPoints = 20;

  /// Any repeat from the last seven occurrences is capped at 0.30% total.
  ///
  /// The first 0.20% belongs to [consecutiveRepeatBasisPoints], leaving a
  /// separate 0.10% lane for the other six recent occurrences.
  static const int withinWeekRepeatBasisPoints = 30;

  /// A wisdom last seen 8-30 occurrences ago may recur on 0.30% of draws.
  static const int olderMonthRepeatBasisPoints = 30;

  static const int recentTagLimit = 12;
  static const int recentToneLimit = 5;
  static const String _resourceKey = 'wisdom_selection_history';

  final WisdomSelectionHistoryStore _historyStore;
  final Random _random;
  final List<Map<String, dynamic>> _catalog;
  final PersistenceOperationCoordinator _operationCoordinator;
  late final Map<String, Map<String, dynamic>> _catalogById;

  final List<String> _recentWisdomIds = <String>[];
  final List<String> _recentTags = <String>[];
  final List<String> _recentTones = <String>[];
  bool _historyLoaded = false;

  Future<Map<String, dynamic>> select() {
    // Concurrent callers share one in-flight selection rather than consuming
    // two wisdoms for one visual reveal.
    return _operationCoordinator.runMutation<Map<String, dynamic>>(
      resourceKey: _resourceKey,
      operationKey: 'select',
      operation: _select,
    );
  }

  Future<Map<String, dynamic>> _select() async {
    await _restoreHistoryBestEffort();

    if (_catalog.isEmpty) {
      return const <String, dynamic>{
        'text': 'Silence is still available.',
        'id': null,
        'tags': <String>['silence'],
        'tone': 'calm',
      };
    }

    final rareRepeat = _drawRareRepeat();
    if (rareRepeat != null) {
      _rememberPattern(rareRepeat);
      await _persistHistoryBestEffort();
      return rareRepeat;
    }

    final recentIds = _recentWisdomIds.toSet();
    var candidates = _catalog.where((wisdom) {
      final id = wisdom['id'];
      return id is! String || !recentIds.contains(id);
    }).toList(growable: false);

    // Relevant only for a deliberately tiny injected catalog. EAST.'s real
    // catalog cannot be exhausted by a 30-occurrence history window. Keep the
    // selector fail-open without erasing history: choose among the least-used
    // candidates when the strict normal pool is empty.
    if (candidates.isEmpty) {
      final occurrenceCounts = _occurrenceCounts();
      final minimumCount = _catalog.fold<int?>(null, (minimum, wisdom) {
        final id = wisdom['id'];
        final count = id is String ? occurrenceCounts[id] ?? 0 : 0;
        return minimum == null ? count : min(minimum, count);
      });
      candidates = _catalog.where((wisdom) {
        final id = wisdom['id'];
        final count = id is String ? occurrenceCounts[id] ?? 0 : 0;
        return count == minimumCount;
      }).toList(growable: false);
    }

    final weights = candidates.map(_weightFor).toList(growable: false);
    final selected = candidates[_chooseWeightedIndex(weights)];

    _rememberPattern(selected);
    await _persistHistoryBestEffort();
    return selected;
  }

  Map<String, dynamic>? _drawRareRepeat() {
    if (_recentWisdomIds.isEmpty) return null;

    final draw = _random.nextInt(probabilityBasisPoints);
    final mostRecentDistance = _mostRecentDistanceById();

    if (draw < consecutiveRepeatBasisPoints) {
      final previousId = _recentWisdomIds.last;
      return _catalogById[previousId];
    }

    if (draw < withinWeekRepeatBasisPoints) {
      return _chooseRepeatFrom(
        mostRecentDistance.entries
            .where(
              (entry) => entry.value >= 2 && entry.value <= 7,
            )
            .map((entry) => entry.key),
      );
    }

    if (draw < withinWeekRepeatBasisPoints + olderMonthRepeatBasisPoints) {
      return _chooseRepeatFrom(
        mostRecentDistance.entries
            .where(
              (entry) => entry.value >= 8 && entry.value <= recentWisdomLimit,
            )
            .map((entry) => entry.key),
      );
    }

    return null;
  }

  Map<String, dynamic>? _chooseRepeatFrom(Iterable<String> ids) {
    final candidates = ids
        .map((id) => _catalogById[id])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    if (candidates.isEmpty) return null;

    final weights = candidates.map(_weightFor).toList(growable: false);
    return candidates[_chooseWeightedIndex(weights)];
  }

  Map<String, int> _occurrenceCounts() {
    final counts = <String, int>{};
    for (final id in _recentWisdomIds) {
      counts.update(id, (count) => count + 1, ifAbsent: () => 1);
    }
    return counts;
  }

  Map<String, int> _mostRecentDistanceById() {
    final distances = <String, int>{};
    for (var index = _recentWisdomIds.length - 1; index >= 0; index--) {
      final id = _recentWisdomIds[index];
      distances.putIfAbsent(
        id,
        () => _recentWisdomIds.length - index,
      );
    }
    return distances;
  }

  int _weightFor(Map<String, dynamic> wisdom) {
    var weight = 100;
    final tags = List<String>.from(wisdom['tags'] ?? const <String>[]);
    final tone = wisdom['tone'] as String? ?? 'neutral';

    for (final tag in tags) {
      if (_recentTags.contains(tag)) weight -= 18;
    }
    if (_recentTones.contains(tone)) weight -= 25;
    return max(5, weight);
  }

  int _chooseWeightedIndex(List<int> weights) {
    final totalWeight = weights.fold<int>(0, (sum, weight) => sum + weight);
    var draw = _random.nextInt(totalWeight);
    for (var index = 0; index < weights.length; index++) {
      draw -= weights[index];
      if (draw < 0) return index;
    }
    return weights.length - 1;
  }

  Future<void> _restoreHistoryBestEffort() async {
    if (_historyLoaded) return;
    _historyLoaded = true;

    List<String> storedIds;
    try {
      storedIds = await _historyStore.loadRecentWisdomIds();
    } catch (_) {
      return;
    }

    final newestFirst = <String>[];
    for (final id in storedIds.reversed) {
      if (!_catalogById.containsKey(id)) continue;
      newestFirst.add(id);
      if (newestFirst.length == recentWisdomLimit) break;
    }

    final normalizedIds = newestFirst.reversed.toList(growable: false);
    _recentWisdomIds.addAll(normalizedIds);
    for (final id in normalizedIds) {
      _rememberTagsAndTone(_catalogById[id]!);
    }
  }

  Future<void> _persistHistoryBestEffort() async {
    try {
      await _historyStore.replaceRecentWisdomIds(
        List<String>.unmodifiable(_recentWisdomIds),
      );
    } catch (_) {
      // Variety history is optional. A storage failure must never prevent a
      // valid wisdom from becoming the authoritative pending daily reveal.
    }
  }

  void _rememberPattern(Map<String, dynamic> selected) {
    final id = selected['id'] as String?;
    if (id != null) {
      _recentWisdomIds.add(id);
      while (_recentWisdomIds.length > recentWisdomLimit) {
        _recentWisdomIds.removeAt(0);
      }
    }
    _rememberTagsAndTone(selected);
  }

  void _rememberTagsAndTone(Map<String, dynamic> wisdom) {
    _recentTags.addAll(List<String>.from(wisdom['tags'] ?? const <String>[]));
    while (_recentTags.length > recentTagLimit) {
      _recentTags.removeAt(0);
    }

    _recentTones.add(wisdom['tone'] as String? ?? 'neutral');
    while (_recentTones.length > recentToneLimit) {
      _recentTones.removeAt(0);
    }
  }
}
