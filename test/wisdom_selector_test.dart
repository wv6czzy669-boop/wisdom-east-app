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

  test('normal draws avoid the rolling recurrence history', () async {
    final selector = WisdomSelectorService(
      historyStore: _MemoryWisdomSelectionHistoryStore(),
      random: _FixedRandom(6000),
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

  test('last thirty occurrences survive service restarts', () async {
    final selectedIds = <String>[];

    for (var index = 0; index < 31; index++) {
      final restartedSelector = WisdomSelectorService(
        historyStore: SharedPreferencesWisdomSelectionHistoryStore(),
        random: _FixedRandom(6000 + index * 73),
      );
      selectedIds.add((await restartedSelector.select())['id'] as String);
    }

    final prefs = await SharedPreferences.getInstance();
    final storedIds = prefs.getStringList(
      SharedPreferencesWisdomSelectionHistoryStore.storageKey,
    );

    expect(selectedIds.toSet(), hasLength(31));
    expect(storedIds, selectedIds.skip(1).toList());
    expect(storedIds, hasLength(WisdomSelectorService.recentWisdomLimit));
  });

  test('restored history drops unknown IDs but preserves occurrences',
      () async {
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
        'east_wisdom_0001',
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

  group('bounded rare recurrence policy', () {
    final catalog = List<Map<String, dynamic>>.generate(
      9,
      (index) => _wisdom(index + 1),
    );
    final history = <String>[
      'east_wisdom_0003', // Distance 8: older-month lane.
      'east_wisdom_0004',
      'east_wisdom_0005',
      'east_wisdom_0006',
      'east_wisdom_0007',
      'east_wisdom_0008',
      'east_wisdom_0002', // Distance 2: within-week lane.
      'east_wisdom_0001', // Distance 1: consecutive lane.
    ];

    Future<String> selectWithDraw(int draw) async {
      final selected = await WisdomSelectorService(
        historyStore: _MemoryWisdomSelectionHistoryStore(history),
        random: _FixedRandom(draw),
        catalog: catalog,
      ).select();
      return selected['id'] as String;
    }

    test('probability constants encode the agreed maximums exactly', () {
      expect(WisdomSelectorService.probabilityBasisPoints, 10000);
      expect(WisdomSelectorService.consecutiveRepeatBasisPoints, 20);
      expect(WisdomSelectorService.withinWeekRepeatBasisPoints, 30);
      expect(WisdomSelectorService.olderMonthRepeatBasisPoints, 30);
    });

    test('0.20% consecutive lane has exact lower and upper boundaries',
        () async {
      expect(await selectWithDraw(0), 'east_wisdom_0001');
      expect(await selectWithDraw(19), 'east_wisdom_0001');
    });

    test('remaining 0.10% weekly lane makes the total weekly cap 0.30%',
        () async {
      const weeklyIds = <String>{
        'east_wisdom_0002',
        'east_wisdom_0004',
        'east_wisdom_0005',
        'east_wisdom_0006',
        'east_wisdom_0007',
        'east_wisdom_0008',
      };

      expect(weeklyIds, contains(await selectWithDraw(20)));
      expect(weeklyIds, contains(await selectWithDraw(29)));
    });

    test('0.30% older-month lane is separate from the weekly cap', () async {
      expect(await selectWithDraw(30), 'east_wisdom_0003');
      expect(await selectWithDraw(59), 'east_wisdom_0003');
    });

    test('draws outside rare lanes use a wisdom absent from the last month',
        () async {
      expect(await selectWithDraw(60), 'east_wisdom_0009');
      expect(await selectWithDraw(9999), 'east_wisdom_0009');
    });

    test('repeat probability stays non-zero after a third occurrence',
        () async {
      final store = _MemoryWisdomSelectionHistoryStore(<String>[
        'east_wisdom_0001',
        'east_wisdom_0001',
      ]);
      final selector = WisdomSelectorService(
        historyStore: store,
        random: _FixedRandom(0),
        catalog: catalog,
      );

      expect((await selector.select())['id'], 'east_wisdom_0001');
      expect(store.ids.where((id) => id == 'east_wisdom_0001'), hasLength(3));

      expect((await selector.select())['id'], 'east_wisdom_0001');
      expect(store.ids.where((id) => id == 'east_wisdom_0001'), hasLength(4));
    });

    test('legacy 20-item history upgrades without reset or schema change',
        () async {
      final legacyIds = List<String>.generate(
        20,
        (index) => 'east_wisdom_${(index + 1).toString().padLeft(4, '0')}',
      );
      final store = _MemoryWisdomSelectionHistoryStore(legacyIds);
      final selector = WisdomSelectorService(
        historyStore: store,
        random: _FixedRandom(6000),
      );

      final selectedId = (await selector.select())['id'] as String;

      expect(store.ids.take(20), legacyIds);
      expect(store.ids.last, selectedId);
      expect(store.ids, hasLength(21));
    });
  });
}

Map<String, dynamic> _wisdom(int number) => <String, dynamic>{
      'id': 'east_wisdom_${number.toString().padLeft(4, '0')}',
      'text': 'Wisdom $number.',
      'tags': <String>['tag-$number'],
      'tone': 'tone-$number',
    };

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
