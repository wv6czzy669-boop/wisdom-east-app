import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/services/daily_wisdom_access_service.dart';
import 'package:wisdom_app/services/storage_service.dart';

void main() {
  late DateTime now;
  late StorageService storage;
  late DailyWisdomAccessService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime.utc(2026, 6, 20, 12);
    storage = StorageService();
    service = DailyWisdomAccessService(
      storageService: storage,
      clock: () => now,
    );
  });

  test('free user receives one new wisdom during a 24-hour window', () async {
    var selections = 0;
    String select() => 'Wisdom ${++selections}';

    final first = await service.reveal(
      selectWisdom: select,
    );
    now = now.add(const Duration(hours: 23, minutes: 59));
    final second = await service.reveal(
      selectWisdom: select,
    );

    expect(first.text, 'Wisdom 1');
    expect(first.isNew, isTrue);
    expect(second.text, 'Wisdom 1');
    expect(second.isNew, isFalse);
    expect(selections, 1);
  });

  test('free user receives a new wisdom at the exact 24-hour boundary',
      () async {
    var selections = 0;
    String select() => 'Wisdom ${++selections}';

    await service.reveal(selectWisdom: select);
    now = now.add(const Duration(hours: 24));
    final result = await service.reveal(
      selectWisdom: select,
    );

    expect(result.text, 'Wisdom 2');
    expect(result.isNew, isTrue);
    expect(selections, 2);
  });

  test('persisted lock survives service recreation', () async {
    await service.reveal(
      selectWisdom: () => 'Persisted wisdom',
    );

    final recreated = DailyWisdomAccessService(
      storageService: StorageService(),
      clock: () => now.add(const Duration(hours: 1)),
    );
    var selectedAgain = false;
    final result = await recreated.reveal(
      selectWisdom: () {
        selectedAgain = true;
        return 'Different wisdom';
      },
    );

    expect(result.text, 'Persisted wisdom');
    expect(selectedAgain, isFalse);
  });

  test('clock rollback cannot clear or shorten the active lock', () async {
    await service.reveal(
      selectWisdom: () => 'Locked wisdom',
    );
    now = now.subtract(const Duration(days: 10));

    final status = await service.status();
    final result = await service.reveal(
      selectWisdom: () => 'Bypassed wisdom',
    );

    expect(status.isReady, isFalse);
    expect(status.remaining, const Duration(hours: 24));
    expect(result.text, 'Locked wisdom');
  });

  final corruptRecords = <String, Object>{
    'malformed JSON': '{',
    'missing fields': '{"text":"Incomplete wisdom"}',
    'invalid timestamp type':
        '{"text":"Invalid wisdom","revealedAtMs":"now","unlockAtMs":2}',
    'invalid timestamp order':
        '{"text":"Invalid wisdom","revealedAtMs":2,"unlockAtMs":1}',
    'invalid stored value type': 42,
  };

  for (final corruptRecord in corruptRecords.entries) {
    test('corrupt daily record fails closed: ${corruptRecord.key}', () async {
      SharedPreferences.setMockInitialValues({
        'daily_wisdom_access': corruptRecord.value,
      });
      storage = StorageService();
      service = DailyWisdomAccessService(
        storageService: storage,
        clock: () => now,
      );
      var selected = false;

      final result = await service.reveal(
        selectWisdom: () {
          selected = true;
          return 'New wisdom';
        },
      );
      final recovered = await storage.loadDailyWisdomRecord(
        lockDuration: const Duration(hours: 24),
      );

      expect(selected, isFalse);
      expect(result.isNew, isFalse);
      expect(
        result.text,
        DailyWisdomAccessService.corruptRecordRecoveryText,
      );
      expect(result.unlockAt, now.add(const Duration(hours: 24)));
      expect(recovered, isNotNull);
      expect(recovered!.text, result.text);
      expect(
        recovered.unlockAt.millisecondsSinceEpoch,
        result.unlockAt!.millisecondsSinceEpoch,
      );
    });
  }

  test('rolling daily access remains locked inside 24 hours', () async {
    var selections = 0;
    String select() => 'Shared wisdom ${++selections}';

    final first = await service.reveal(
      selectWisdom: select,
    );
    now = now.add(const Duration(hours: 1));
    final second = await service.reveal(
      selectWisdom: select,
    );

    expect(first.text, 'Shared wisdom 1');
    expect(first.isNew, isTrue);
    expect(second.text, 'Shared wisdom 1');
    expect(second.isNew, isFalse);
    expect(selections, 1);
  });

  test('concurrent reveal requests create only one new wisdom', () async {
    var selections = 0;
    String select() => 'Concurrent wisdom ${++selections}';

    final results = await Future.wait([
      service.reveal(selectWisdom: select),
      service.reveal(selectWisdom: select),
    ]);

    expect(selections, 1);
    expect(
        results.map((result) => result.text).toSet(), {'Concurrent wisdom 1'});

    now = now.add(const Duration(hours: 1));
    final locked = await service.reveal(selectWisdom: select);
    expect(locked.text, 'Concurrent wisdom 1');
    expect(locked.isNew, isFalse);
    expect(selections, 1);
  });

  test('legacy cooldown keys migrate without opening a loophole', () async {
    final unlockAt = now.add(const Duration(hours: 8));
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_text': 'Legacy wisdom',
      'wisdom_unlock_time_ms': unlockAt.millisecondsSinceEpoch,
    });
    storage = StorageService();
    service = DailyWisdomAccessService(
      storageService: storage,
      clock: () => now,
    );

    final result = await service.reveal(
      selectWisdom: () => 'New wisdom',
    );
    final prefs = await SharedPreferences.getInstance();

    expect(result.text, 'Legacy wisdom');
    expect(prefs.getString('daily_wisdom_access'), isNotNull);
    expect(prefs.containsKey('daily_wisdom_text'), isFalse);
    expect(prefs.containsKey('wisdom_unlock_time_ms'), isFalse);
  });
}
