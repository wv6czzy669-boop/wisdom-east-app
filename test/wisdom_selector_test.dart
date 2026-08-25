import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/data/wisdoms.dart';
import 'package:wisdom_app/persistence/wisdom_selection_history_store.dart';
import 'package:wisdom_app/services/wisdom_selector.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('draws from the canonical database without immediate repeats', () async {
    final selector = WisdomSelectorService(
      historyStore: _MemoryWisdomSelectionHistoryStore(),
      random: Random(17),
    );
    final selectedIds = <String>{};
    final databaseIds = wisdoms.map((item) => item['id']).toSet();

    for (var index = 0; index < 20; index++) {
      final selection = await selector.select();
      final id = selection['id'] as String;

      expect(databaseIds, contains(id));
      expect(selectedIds.add(id), isTrue);
    }
  });

  test('last twenty selections survive a service restart', () async {
    final selectedIds = <String>[];

    for (var index = 0; index < 21; index++) {
      final restartedSelector = WisdomSelectorService(
        historyStore: SharedPreferencesWisdomSelectionHistoryStore(),
        random: Random(index + 1),
      );
      selectedIds.add((await restartedSelector.select())['id'] as String);
    }

    final prefs = await SharedPreferences.getInstance();
    final storedIds = prefs.getStringList(
      SharedPreferencesWisdomSelectionHistoryStore.storageKey,
    );

    expect(selectedIds.toSet(), hasLength(21));
    expect(storedIds, selectedIds.skip(1).toList());
    expect(storedIds, hasLength(WisdomSelectorService.recentWisdomLimit));
  });

  test('restored history drops unknown and duplicate IDs safely', () async {
    final store = _MemoryWisdomSelectionHistoryStore(
      <String>[
        'unknown-id',
        'east_wisdom_0001',
        'east_wisdom_0002',
        'east_wisdom_0001',
      ],
    );
    final selector = WisdomSelectorService(
      historyStore: store,
      random: Random(9),
    );

    final selected = await selector.select();

    expect(
        selected['id'], isNot(anyOf('east_wisdom_0001', 'east_wisdom_0002')));
    expect(
      store.ids,
      <String>[
        'east_wisdom_0002',
        'east_wisdom_0001',
        selected['id'] as String,
      ],
    );
  });

  test('history read and write failures never block a valid selection',
      () async {
    final store = _MemoryWisdomSelectionHistoryStore()
      ..failLoad = true
      ..failReplace = true;
    final selector = WisdomSelectorService(
      historyStore: store,
      random: Random(4),
    );

    final selected = await selector.select();

    expect(wisdoms.map((item) => item['id']), contains(selected['id']));
  });

  test('concurrent callers share exactly one in-flight selection', () async {
    final store = _MemoryWisdomSelectionHistoryStore();
    final selector = WisdomSelectorService(
      historyStore: store,
      random: Random(31),
    );

    final selections = await Future.wait(<Future<Map<String, dynamic>>>[
      selector.select(),
      selector.select(),
    ]);

    expect(selections[0]['id'], selections[1]['id']);
    expect(store.replaceCount, 1);
    expect(store.ids, hasLength(1));
  });

  test('equal candidates receive equal weighted ranges without sort ties',
      () async {
    final catalog = <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'east_wisdom_0001',
        'text': 'First.',
        'tags': <String>['stillness'],
        'tone': 'calm',
      },
      <String, dynamic>{
        'id': 'east_wisdom_0002',
        'text': 'Second.',
        'tags': <String>['stillness'],
        'tone': 'calm',
      },
    ];

    final first = await WisdomSelectorService(
      historyStore: _MemoryWisdomSelectionHistoryStore(),
      random: _FixedRandom(99),
      catalog: catalog,
    ).select();
    final second = await WisdomSelectorService(
      historyStore: _MemoryWisdomSelectionHistoryStore(),
      random: _FixedRandom(100),
      catalog: catalog,
    ).select();

    expect(first['id'], 'east_wisdom_0001');
    expect(second['id'], 'east_wisdom_0002');
  });
}

class _MemoryWisdomSelectionHistoryStore
    implements WisdomSelectionHistoryStore {
  _MemoryWisdomSelectionHistoryStore([List<String>? initialIds])
      : ids = List<String>.from(initialIds ?? const <String>[]);

  List<String> ids;
  bool failLoad = false;
  bool failReplace = false;
  int replaceCount = 0;

  @override
  Future<List<String>> loadRecentWisdomIds() async {
    if (failLoad) throw StateError('read failed');
    return List<String>.from(ids);
  }

  @override
  Future<void> replaceRecentWisdomIds(List<String> wisdomIds) async {
    replaceCount++;
    if (failReplace) throw StateError('write failed');
    ids = List<String>.from(wisdomIds);
  }
}

class _FixedRandom implements Random {
  _FixedRandom(this.value);

  final int value;

  @override
  bool nextBool() => value.isEven;

  @override
  double nextDouble() => (value % 1000) / 1000;

  @override
  int nextInt(int max) => value % max;
}
