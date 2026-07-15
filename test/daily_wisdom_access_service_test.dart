import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/models/daily_wisdom_record.dart';
import 'package:wisdom_app/models/pending_daily_wisdom_reveal.dart';
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

  test('prepare creates pending wisdom without daily access', () async {
    var selections = 0;

    final prepared = await service.prepareReveal(
      selectWisdom: () => 'Pending wisdom ${++selections}',
    );
    final prefs = await SharedPreferences.getInstance();
    final pending = await storage.loadPendingDailyWisdomReveal();

    expect(prepared.text, 'Pending wisdom 1');
    expect(prepared.hasAuthoritativeRecord, isFalse);
    expect(selections, 1);
    expect(prefs.containsKey('daily_wisdom_access'), isFalse);
    expect(pending, isNotNull);
    expect(pending!.text, 'Pending wisdom 1');
    expect(
      pending.preparedAt.millisecondsSinceEpoch,
      now.millisecondsSinceEpoch,
    );
  });

  test('two prepare calls recover the same pending wisdom', () async {
    var selections = 0;

    final first = await service.prepareReveal(
      selectWisdom: () => 'Prepared wisdom ${++selections}',
    );
    now = now.add(const Duration(minutes: 7));
    final second = await service.prepareReveal(
      selectWisdom: () => 'Prepared wisdom ${++selections}',
    );

    expect(first.text, 'Prepared wisdom 1');
    expect(second.text, 'Prepared wisdom 1');
    expect(first.hasAuthoritativeRecord, isFalse);
    expect(second.hasAuthoritativeRecord, isFalse);
    expect(selections, 1);
  });

  test('cold relaunch with valid pending state recovers same wisdom', () async {
    await service.prepareReveal(
      selectWisdom: () => 'Interrupted pending wisdom',
    );

    final recreated = DailyWisdomAccessService(
      storageService: StorageService(),
      clock: () => now.add(const Duration(minutes: 4)),
    );
    var selectedAgain = false;

    final recovered = await recreated.prepareReveal(
      selectWisdom: () {
        selectedAgain = true;
        return 'Different post-relaunch wisdom';
      },
    );
    final prefs = await SharedPreferences.getInstance();

    expect(recovered.text, 'Interrupted pending wisdom');
    expect(recovered.hasAuthoritativeRecord, isFalse);
    expect(selectedAgain, isFalse);
    expect(prefs.containsKey('daily_wisdom_access'), isFalse);
  });

  test('corrupt pending state creates no lock or synthetic wisdom', () async {
    SharedPreferences.setMockInitialValues({
      'pending_daily_wisdom_reveal': '{',
    });
    storage = StorageService();
    service = DailyWisdomAccessService(
      storageService: storage,
      clock: () => now,
    );
    var selections = 0;

    final prepared = await service.prepareReveal(
      selectWisdom: () => 'Valid pending wisdom ${++selections}',
    );
    final prefs = await SharedPreferences.getInstance();
    final pending = await storage.loadPendingDailyWisdomReveal();

    expect(prepared.text, 'Valid pending wisdom 1');
    expect(prepared.hasAuthoritativeRecord, isFalse);
    expect(selections, 1);
    expect(prefs.containsKey('daily_wisdom_access'), isFalse);
    expect(pending, isNotNull);
    expect(pending!.text, 'Valid pending wisdom 1');
  });

  test('pending model rejects invalid phase and timestamp combinations', () {
    final preparedAt = now.millisecondsSinceEpoch;
    final confirmedAt =
        now.add(const Duration(seconds: 1)).millisecondsSinceEpoch;

    String encodePending(Map<String, Object?> fields) => jsonEncode({
          'schemaVersion': 1,
          'text': 'Valid wisdom',
          'preparedAtMs': preparedAt,
          'phase': 'prepared',
          ...fields,
        });

    expect(
      () => PendingDailyWisdomReveal.decode(
        encodePending({'confirmedRevealBoundaryMs': confirmedAt}),
      ),
      throwsFormatException,
    );
    expect(
      () => PendingDailyWisdomReveal.decode(
        encodePending({'phase': 'revealedPendingCommit'}),
      ),
      throwsFormatException,
    );
    expect(
      () => PendingDailyWisdomReveal.decode(
        encodePending({'preparedAtMs': -1}),
      ),
      throwsFormatException,
    );
    expect(
      () => PendingDailyWisdomReveal.decode(
        encodePending({
          'phase': 'revealedPendingCommit',
          'confirmedRevealBoundaryMs':
              now.subtract(const Duration(seconds: 1)).millisecondsSinceEpoch,
        }),
      ),
      throwsFormatException,
    );
    expect(
      () => PendingDailyWisdomReveal.decode(encodePending({'text': '   '})),
      throwsFormatException,
    );
    expect(
      () => PendingDailyWisdomReveal.decode(
        encodePending({'phase': 'boundaryReserved'}),
      ),
      throwsFormatException,
    );
    expect(
      () => PendingDailyWisdomReveal.decode(
        encodePending({'schemaVersion': 2}),
      ),
      throwsFormatException,
    );
    expect(
      () => PendingDailyWisdomReveal.decode(
        encodePending({'reservedBoundaryMs': confirmedAt}),
      ),
      throwsFormatException,
    );
  });

  test('commit uses visual reveal time rather than prepare time', () async {
    final preparedAt = now;
    await service.prepareReveal(
      selectWisdom: () => 'Boundary wisdom',
    );
    final visualRevealAt = preparedAt.add(const Duration(minutes: 19));

    final committed = await service.finalizeVisualReveal(
      text: 'Boundary wisdom',
      revealBoundary: visualRevealAt,
    );
    final persisted = await storage.loadDailyWisdomRecord(
      lockDuration: const Duration(hours: 24),
    );

    expect(committed.text, 'Boundary wisdom');
    expect(committed.isNew, isTrue);
    expect(
      persisted!.revealedAt.millisecondsSinceEpoch,
      visualRevealAt.millisecondsSinceEpoch,
    );
    expect(
      persisted.revealedAt.millisecondsSinceEpoch,
      isNot(preparedAt.millisecondsSinceEpoch),
    );
    expect(
      persisted.unlockAt.millisecondsSinceEpoch,
      visualRevealAt.add(const Duration(hours: 24)).millisecondsSinceEpoch,
    );
  });

  test('commit removes pending state after authoritative persistence',
      () async {
    await service.prepareReveal(selectWisdom: () => 'Cleanup wisdom');

    await service.finalizeVisualReveal(
      text: 'Cleanup wisdom',
      revealBoundary: now.add(const Duration(seconds: 2)),
    );
    final pending = await storage.loadPendingDailyWisdomReveal();

    expect(pending, isNull);
  });

  test('pending cleanup failure does not invalidate committed wisdom',
      () async {
    storage = StorageService(
      pendingRevealRemover: (prefs, key) async {
        throw StateError('Simulated pending cleanup failure.');
      },
    );
    service = DailyWisdomAccessService(
      storageService: storage,
      clock: () => now,
    );

    await service.prepareReveal(selectWisdom: () => 'Cleanup failure wisdom');
    final committed = await service.finalizeVisualReveal(
      text: 'Cleanup failure wisdom',
      revealBoundary: now.add(const Duration(seconds: 1)),
    );
    final persisted = await storage.loadDailyWisdomRecord(
      lockDuration: const Duration(hours: 24),
    );

    expect(committed.text, 'Cleanup failure wisdom');
    expect(committed.isNew, isTrue);
    expect(persisted!.text, 'Cleanup failure wisdom');
  });

  test('commit persistence failure preserves pending without daily lock',
      () async {
    storage = _FailingDailyWriteStorageService();
    service = DailyWisdomAccessService(
      storageService: storage,
      clock: () => now,
    );

    await service.prepareReveal(selectWisdom: () => 'Retryable wisdom');
    final revealBoundary = now.add(const Duration(seconds: 1));

    await expectLater(
      service.finalizeVisualReveal(
        text: 'Retryable wisdom',
        revealBoundary: revealBoundary,
      ),
      throwsStateError,
    );

    final prefs = await SharedPreferences.getInstance();
    final pending = await storage.loadPendingDailyWisdomReveal();

    expect(prefs.containsKey('daily_wisdom_access'), isFalse);
    expect(pending, isNotNull);
    expect(pending!.text, 'Retryable wisdom');
    expect(pending.confirmedRevealBoundary!.millisecondsSinceEpoch,
        revealBoundary.millisecondsSinceEpoch);
    expect(
      pending.phase,
      PendingDailyWisdomRevealPhase.revealedPendingCommit,
    );
  });

  test('direct commit before visual boundary is rejected', () async {
    await service.prepareReveal(selectWisdom: () => 'Unmarked wisdom');

    await expectLater(
      service.commitVisuallyRevealedPending(),
      throwsStateError,
    );

    final prefs = await SharedPreferences.getInstance();
    final pending = await storage.loadPendingDailyWisdomReveal();

    expect(prefs.containsKey('daily_wisdom_access'), isFalse);
    expect(pending, isNotNull);
    expect(pending!.text, 'Unmarked wisdom');
    expect(pending.confirmedRevealBoundary, isNull);
    expect(pending.phase, PendingDailyWisdomRevealPhase.prepared);
  });

  test('successful commit survives app kill and reopens as authoritative',
      () async {
    await service.prepareReveal(selectWisdom: () => 'Post-kill wisdom');
    final revealAt = now.add(const Duration(seconds: 3));
    await service.finalizeVisualReveal(
      text: 'Post-kill wisdom',
      revealBoundary: revealAt,
    );

    final recreated = DailyWisdomAccessService(
      storageService: StorageService(),
      clock: () => revealAt.add(const Duration(minutes: 1)),
    );
    var selectedAgain = false;
    final reopened = await recreated.prepareReveal(
      selectWisdom: () {
        selectedAgain = true;
        return 'Different wisdom';
      },
    );

    expect(reopened.text, 'Post-kill wisdom');
    expect(reopened.hasAuthoritativeRecord, isTrue);
    expect(
      reopened.unlockAt!.millisecondsSinceEpoch,
      revealAt.add(const Duration(hours: 24)).millisecondsSinceEpoch,
    );
    expect(selectedAgain, isFalse);
  });

  test('relaunch after visual boundary finalizes with original timestamp',
      () async {
    final revealAt = now.add(const Duration(seconds: 7));
    await storage.savePendingDailyWisdomReveal(
      PendingDailyWisdomReveal(
        text: 'Boundary survived kill',
        preparedAt: now,
        confirmedRevealBoundary: revealAt,
        phase: PendingDailyWisdomRevealPhase.revealedPendingCommit,
      ),
    );

    final recreated = DailyWisdomAccessService(
      storageService: StorageService(),
      clock: () => revealAt.add(const Duration(minutes: 4)),
    );
    final committed = await recreated.recoverIncompleteReveal();
    final persisted = await storage.loadDailyWisdomRecord(
      lockDuration: const Duration(hours: 24),
    );

    expect(committed!.text, 'Boundary survived kill');
    expect(persisted!.text, 'Boundary survived kill');
    expect(
      persisted.revealedAt.millisecondsSinceEpoch,
      revealAt.millisecondsSinceEpoch,
    );
    expect(
      persisted.unlockAt.millisecondsSinceEpoch,
      revealAt.add(const Duration(hours: 24)).millisecondsSinceEpoch,
    );
  });

  test('two service instances committing concurrently converge on one record',
      () async {
    await service.prepareReveal(selectWisdom: () => 'Shared commit wisdom');
    final secondService = DailyWisdomAccessService(
      storageService: StorageService(),
      clock: () => now,
    );
    final revealAt = now.add(const Duration(seconds: 5));

    final results = await Future.wait([
      service.finalizeVisualReveal(
        text: 'Shared commit wisdom',
        revealBoundary: revealAt,
      ),
      secondService.finalizeVisualReveal(
        text: 'Shared commit wisdom',
        revealBoundary: revealAt,
      ),
    ]);
    final persisted = await storage.loadDailyWisdomRecord(
      lockDuration: const Duration(hours: 24),
    );

    expect(
      results.map((result) => result.text).toSet(),
      {'Shared commit wisdom'},
    );
    expect(persisted!.text, 'Shared commit wisdom');
    expect(
      persisted.revealedAt.millisecondsSinceEpoch,
      revealAt.millisecondsSinceEpoch,
    );
    expect(
      persisted.unlockAt.millisecondsSinceEpoch,
      revealAt.add(const Duration(hours: 24)).millisecondsSinceEpoch,
    );
  });

  test('in-flight finalization rejects a different wisdom text', () async {
    storage = _HangingDailyWriteStorageService();
    service = DailyWisdomAccessService(
      storageService: storage,
      clock: () => now,
    );
    await service.prepareReveal(selectWisdom: () => 'Original wisdom');
    final revealAt = now.add(const Duration(seconds: 5));

    final first = service.finalizeVisualReveal(
      text: 'Original wisdom',
      revealBoundary: revealAt,
    );

    await expectLater(
      service.finalizeVisualReveal(
        text: 'Different wisdom',
        revealBoundary: revealAt.add(const Duration(seconds: 1)),
      ),
      throwsStateError,
    );
    final observed = await Future.any([
      first.then((_) => 'completed'),
      Future<void>.delayed(const Duration(milliseconds: 20))
          .then((_) => 'still waiting'),
    ]);
    final pending = await storage.loadPendingDailyWisdomReveal();

    expect(observed, 'still waiting');
    expect(pending!.text, 'Original wisdom');
    expect(
      pending.confirmedRevealBoundary!.millisecondsSinceEpoch,
      revealAt.millisecondsSinceEpoch,
    );
  });

  test('existing locked record wins over pending state', () async {
    await storage.savePendingDailyWisdomReveal(
      PendingDailyWisdomReveal(
        text: 'Stale pending wisdom',
        preparedAt: now.subtract(const Duration(minutes: 5)),
      ),
    );
    final authoritative = DailyWisdomRecord(
      text: 'Authoritative locked wisdom',
      revealedAt: now.subtract(const Duration(minutes: 2)),
      unlockAt: now.add(const Duration(hours: 23, minutes: 58)),
    );
    await storage.saveDailyWisdomRecord(authoritative);

    final prepared = await service.prepareReveal(
      selectWisdom: () => 'Should not select',
    );
    final committed = await service.finalizeVisualReveal(
      text: authoritative.text,
      revealBoundary: now.add(const Duration(seconds: 1)),
    );
    final pending = await storage.loadPendingDailyWisdomReveal();

    expect(prepared.text, authoritative.text);
    expect(prepared.hasAuthoritativeRecord, isTrue);
    expect(committed.text, authoritative.text);
    expect(committed.isNew, isFalse);
    expect(pending, isNull);
  });

  test('stale pending before expired record unlock is ignored', () async {
    final expiredRecord = DailyWisdomRecord(
      text: 'Yesterday wisdom',
      revealedAt: now.subtract(const Duration(hours: 25)),
      unlockAt: now.subtract(const Duration(hours: 1)),
    );
    await storage.saveDailyWisdomRecord(expiredRecord);
    await storage.savePendingDailyWisdomReveal(
      PendingDailyWisdomReveal(
        text: 'Stale yesterday pending',
        preparedAt: now.subtract(const Duration(hours: 2)),
      ),
    );
    var selections = 0;

    final prepared = await service.prepareReveal(
      selectWisdom: () => 'Fresh wisdom ${++selections}',
    );
    final pending = await storage.loadPendingDailyWisdomReveal();
    final revealAt = now.add(const Duration(seconds: 2));
    final committed = await service.finalizeVisualReveal(
      text: prepared.text,
      revealBoundary: revealAt,
    );

    expect(prepared.text, 'Fresh wisdom 1');
    expect(pending!.text, 'Fresh wisdom 1');
    expect(committed.text, 'Fresh wisdom 1');
    expect(selections, 1);
  });

  test('pending after expired record unlock is recovered', () async {
    final expiredRecord = DailyWisdomRecord(
      text: 'Previous wisdom',
      revealedAt: now.subtract(const Duration(hours: 25)),
      unlockAt: now.subtract(const Duration(hours: 1)),
    );
    await storage.saveDailyWisdomRecord(expiredRecord);
    await storage.savePendingDailyWisdomReveal(
      PendingDailyWisdomReveal(
        text: 'Interrupted next wisdom',
        preparedAt: now.subtract(const Duration(minutes: 30)),
      ),
    );
    var selected = false;

    final prepared = await service.prepareReveal(
      selectWisdom: () {
        selected = true;
        return 'Different wisdom';
      },
    );

    expect(prepared.text, 'Interrupted next wisdom');
    expect(prepared.hasAuthoritativeRecord, isFalse);
    expect(selected, isFalse);
  });

  test('Keeper flag does not change daily reveal transaction behavior',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_premium', true);
    var selections = 0;

    await service.prepareReveal(
      selectWisdom: () => 'Keeper same-lock wisdom ${++selections}',
    );
    final committed = await service.finalizeVisualReveal(
      text: 'Keeper same-lock wisdom 1',
      revealBoundary: now,
    );
    now = now.add(const Duration(hours: 1));
    final locked = await service.reveal(
      selectWisdom: () => 'Second Keeper wisdom ${++selections}',
    );

    expect(committed.text, 'Keeper same-lock wisdom 1');
    expect(locked.text, 'Keeper same-lock wisdom 1');
    expect(locked.isNew, isFalse);
    expect(selections, 1);
  });

  test('hung prepare operation remains single-flight and selects once',
      () async {
    final hangingService = DailyWisdomAccessService(
      storageService: _HangingPendingWriteStorageService(),
      clock: () => now,
      operationTimeout: const Duration(milliseconds: 20),
    );
    var selections = 0;

    final first = hangingService.prepareReveal(
      selectWisdom: () => 'Never persisted ${++selections}',
    );
    final second = hangingService.prepareReveal(
      selectWisdom: () => 'Never persisted ${++selections}',
    );
    final observed = await Future.any([
      first.then((_) => 'completed'),
      Future<void>.delayed(const Duration(milliseconds: 20))
          .then((_) => 'still waiting'),
    ]);

    expect(identical(first, second), isTrue);
    expect(observed, 'still waiting');
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
    expect(
      result.unlockAt!.millisecondsSinceEpoch,
      now.add(const Duration(hours: 24)).millisecondsSinceEpoch,
    );
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

class _FailingDailyWriteStorageService extends StorageService {
  @override
  Future<void> saveDailyWisdomRecord(DailyWisdomRecord record) async {
    throw StateError('Simulated daily wisdom persistence failure.');
  }
}

class _HangingPendingWriteStorageService extends StorageService {
  @override
  Future<void> savePendingDailyWisdomReveal(
    PendingDailyWisdomReveal reveal,
  ) {
    return Completer<void>().future;
  }
}

class _HangingDailyWriteStorageService extends StorageService {
  @override
  Future<void> saveDailyWisdomRecord(DailyWisdomRecord record) {
    return Completer<void>().future;
  }
}
