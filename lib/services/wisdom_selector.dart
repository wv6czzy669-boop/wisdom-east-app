import 'dart:math';

import '../data/wisdoms.dart';
import '../persistence/persistence_operation_coordinator.dart';
import '../persistence/wisdom_selection_history_store.dart';

/// Selects a varied wisdom while keeping recent occurrences device-local.
///
/// The last [recentWisdomLimit] canonical IDs survive process restarts. The
/// history is deliberately independent of the daily-access and Kept domains:
/// losing it may reduce variety, but can never block a ritual or alter user
/// data. Reads and writes therefore fail open.
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

  static const int recentWisdomLimit = 20;
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

    var candidates = _catalog.where((wisdom) {
      final id = wisdom['id'];
      return id is! String || !_recentWisdomIds.contains(id);
    }).toList(growable: false);

    // Relevant only for a deliberately tiny injected catalog. EAST.'s real
    // 603-entry catalog cannot be exhausted by a 20-entry history window.
    if (candidates.isEmpty) {
      _recentWisdomIds.clear();
      _recentTags.clear();
      _recentTones.clear();
      candidates = _catalog;
    }

    final weights = candidates.map(_weightFor).toList(growable: false);
    final selected = candidates[_chooseWeightedIndex(weights)];

    _rememberPattern(selected);
    await _persistHistoryBestEffort();
    return selected;
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
    final seen = <String>{};
    for (final id in storedIds.reversed) {
      if (!_catalogById.containsKey(id) || !seen.add(id)) continue;
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
