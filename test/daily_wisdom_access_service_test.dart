import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/models/daily_wisdom_record.dart';
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

  test('only legacy wisdom text is ignored and removed', () async {
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_text': 'Legacy wisdom text',
    });
    storage = StorageService();
    service = DailyWisdomAccessService(
      storageService: storage,
      clock: () => now,
    );

    final status = await service.status();
    final prefs = await SharedPreferences.getInstance();

    expect(status.isReady, isTrue);
    expect(prefs.containsKey('daily_wisdom_access'), isFalse);
    expect(prefs.containsKey('daily_wisdom_text'), isFalse);
  });

  test('only legacy unlock timestamp is ignored and removed', () async {
    SharedPreferences.setMockInitialValues({
      'wisdom_unlock_time_ms':
          now.add(const Duration(hours: 8)).millisecondsSinceEpoch,
    });
    storage = StorageService();
    service = DailyWisdomAccessService(
      storageService: storage,
      clock: () => now,
    );

    final status = await service.status();
    final prefs = await SharedPreferences.getInstance();

    expect(status.isReady, isTrue);
    expect(prefs.containsKey('daily_wisdom_access'), isFalse);
    expect(prefs.containsKey('wisdom_unlock_time_ms'), isFalse);
  });

  test('legacy daily keys never restore authoritative wisdom', () async {
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_text': 'Legacy wisdom',
      'wisdom_unlock_time_ms':
          now.add(const Duration(hours: 8)).millisecondsSinceEpoch,
    });
    storage = StorageService();
    service = DailyWisdomAccessService(
      storageService: storage,
      clock: () => now,
    );

    final status = await service.status();
    var selected = false;
    final result = await service.reveal(
      selectWisdom: () {
        selected = true;
        return 'First real wisdom';
      },
    );
    final prefs = await SharedPreferences.getInstance();
    final persisted = DailyWisdomRecord.decode(
      prefs.getString('daily_wisdom_access')!,
    );

    expect(status.isReady, isTrue);
    expect(selected, isTrue);
    expect(result.text, 'First real wisdom');
    expect(result.isNew, isTrue);
    expect(persisted.text, 'First real wisdom');
    expect(
      persisted.revealedAt.millisecondsSinceEpoch,
      now.millisecondsSinceEpoch,
    );
    expect(
      persisted.unlockAt.millisecondsSinceEpoch,
      now.add(const Duration(hours: 24)).millisecondsSinceEpoch,
    );
    expect(prefs.containsKey('daily_wisdom_text'), isFalse);
    expect(prefs.containsKey('wisdom_unlock_time_ms'), isFalse);
  });

  test('valid daily record remains authoritative over all obsolete cache',
      () async {
    final originalRecord = DailyWisdomRecord(
      text: 'Authoritative daily wisdom',
      revealedAt: now.subtract(const Duration(hours: 3)),
      unlockAt: now.add(const Duration(hours: 21)),
    );
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': originalRecord.encode(),
      'daily_wisdom_text': 'Legacy daily wisdom',
      'wisdom_unlock_time_ms':
          now.add(const Duration(hours: 8)).millisecondsSinceEpoch,
      'keeper_daily_wisdom_state':
          '{"localDate":"2026-06-20","revealCount":2,"lastWisdom":"Obsolete Keeper wisdom","hasPendingReveal":false}',
    });
    storage = StorageService();

    final loaded = await storage.loadDailyWisdomRecord(
      lockDuration: const Duration(hours: 24),
    );
    final prefs = await SharedPreferences.getInstance();

    expect(loaded, isNotNull);
    expect(loaded!.text, originalRecord.text);
    expect(
      loaded.revealedAt.millisecondsSinceEpoch,
      originalRecord.revealedAt.millisecondsSinceEpoch,
    );
    expect(
      loaded.unlockAt.millisecondsSinceEpoch,
      originalRecord.unlockAt.millisecondsSinceEpoch,
    );
    expect(prefs.containsKey('daily_wisdom_text'), isFalse);
    expect(prefs.containsKey('wisdom_unlock_time_ms'), isFalse);
    expect(prefs.containsKey('keeper_daily_wisdom_state'), isFalse);
  });

  test('obsolete Keeper cache without daily record is ready for first wisdom',
      () async {
    SharedPreferences.setMockInitialValues({
      'is_premium': true,
      'keeper_daily_wisdom_state':
          '{"localDate":"2026-06-20","revealCount":2,"lastWisdom":"Old Keeper wisdom","hasPendingReveal":false}',
    });
    storage = StorageService();
    service = DailyWisdomAccessService(
      storageService: storage,
      clock: () => now,
    );

    final status = await service.status();
    final prefsAfterStatus = await SharedPreferences.getInstance();

    expect(status.isReady, isTrue);
    expect(prefsAfterStatus.containsKey('daily_wisdom_access'), isFalse);
    expect(
      prefsAfterStatus.containsKey('keeper_daily_wisdom_state'),
      isFalse,
    );

    var selected = false;
    final result = await service.reveal(
      selectWisdom: () {
        selected = true;
        return 'First actual wisdom';
      },
    );
    final persisted = await storage.loadDailyWisdomRecord(
      lockDuration: const Duration(hours: 24),
    );

    expect(selected, isTrue);
    expect(result.text, 'First actual wisdom');
    expect(result.isNew, isTrue);
    expect(persisted, isNotNull);
    expect(
      persisted!.revealedAt.millisecondsSinceEpoch,
      now.millisecondsSinceEpoch,
    );
    expect(
      persisted.unlockAt.millisecondsSinceEpoch,
      now.add(const Duration(hours: 24)).millisecondsSinceEpoch,
    );
  });

  test('corrupt obsolete Keeper cache is removed without synthetic wisdom',
      () async {
    SharedPreferences.setMockInitialValues({
      'is_premium': true,
      'keeper_daily_wisdom_state': '{',
    });
    storage = StorageService();
    service = DailyWisdomAccessService(
      storageService: storage,
      clock: () => now,
    );

    final status = await service.status();
    final prefs = await SharedPreferences.getInstance();

    expect(status.isReady, isTrue);
    expect(prefs.containsKey('daily_wisdom_access'), isFalse);
    expect(prefs.containsKey('keeper_daily_wisdom_state'), isFalse);

    final result = await service.reveal(
      selectWisdom: () => 'Actual post-corruption wisdom',
    );
    expect(result.text, 'Actual post-corruption wisdom');
    expect(result.isNew, isTrue);
    expect(result.unlockAt, now.add(const Duration(hours: 24)));
  });

  test('all obsolete access keys are ignored and removed', () async {
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_text': 'Legacy wisdom',
      'wisdom_unlock_time_ms':
          now.add(const Duration(hours: 8)).millisecondsSinceEpoch,
      'keeper_daily_wisdom_state':
          '{"localDate":"2026-06-20","revealCount":2,"lastWisdom":"Old Keeper wisdom","hasPendingReveal":false}',
    });
    storage = StorageService();
    service = DailyWisdomAccessService(
      storageService: storage,
      clock: () => now,
    );

    final status = await service.status();
    final prefs = await SharedPreferences.getInstance();

    expect(status.isReady, isTrue);
    expect(prefs.containsKey('daily_wisdom_access'), isFalse);
    expect(prefs.containsKey('daily_wisdom_text'), isFalse);
    expect(prefs.containsKey('wisdom_unlock_time_ms'), isFalse);
    expect(prefs.containsKey('keeper_daily_wisdom_state'), isFalse);
  });

  test('no keys after reinstall is ready for one normal wisdom', () async {
    final status = await service.status();
    var selections = 0;

    final result = await service.reveal(
      selectWisdom: () => 'Fresh wisdom ${++selections}',
    );

    expect(status.isReady, isTrue);
    expect(result.text, 'Fresh wisdom 1');
    expect(result.isNew, isTrue);
    expect(selections, 1);
  });

  test('obsolete-key removal failure does not block normal access', () async {
    SharedPreferences.setMockInitialValues({
      'is_premium': true,
      'keeper_daily_wisdom_state':
          '{"localDate":"2026-06-20","revealCount":1,"lastWisdom":"Ignored Keeper wisdom","hasPendingReveal":false}',
    });
    storage = StorageService(
      obsoleteKeyRemover: (prefs, key) async {
        throw StateError('Simulated obsolete-key removal failure.');
      },
    );
    service = DailyWisdomAccessService(
      storageService: storage,
      clock: () => now,
    );

    final status = await service.status();
    final result = await service.reveal(
      selectWisdom: () => 'First wisdom despite removal failure',
    );

    final prefs = await SharedPreferences.getInstance();
    final persisted = DailyWisdomRecord.decode(
      prefs.getString('daily_wisdom_access')!,
    );

    expect(status.isReady, isTrue);
    expect(result.text, 'First wisdom despite removal failure');
    expect(result.isNew, isTrue);
    expect(
      persisted.revealedAt.millisecondsSinceEpoch,
      now.millisecondsSinceEpoch,
    );
    expect(
      persisted.unlockAt.millisecondsSinceEpoch,
      now.add(const Duration(hours: 24)).millisecondsSinceEpoch,
    );
  });
}
