import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/models/daily_wisdom_record.dart';
import 'package:wisdom_app/models/pending_daily_wisdom_reveal.dart';
import 'package:wisdom_app/persistence/storage_preferences_adapter.dart';
import 'package:wisdom_app/repositories/daily_access_repository.dart';
import 'package:wisdom_app/services/app_services.dart' as app_services;
import 'package:wisdom_app/services/daily_wisdom_access_service.dart';

import 'persistence_test_helpers.dart';

void main() {
  late DateTime now;
  late DailyAccessTestGraph graph;
  late DailyAccessRepository repository;
  late DailyWisdomAccessService service;

  void useGraph(DailyAccessTestGraph nextGraph) {
    graph = nextGraph;
    repository = graph.repository;
    service = graph.service;
  }

  DailyAccessTestGraph createGraph({
    StoragePreferencesAdapter? adapter,
    Future<void> Function(SharedPreferences prefs, String key)?
        obsoleteKeyRemover,
    Future<void> Function(SharedPreferences prefs, String key)?
        pendingRevealRemover,
    WisdomClock? clock,
    Duration statusTimeout = DailyWisdomAccessService.defaultStatusTimeout,
  }) {
    return DailyAccessTestGraph(
      adapter: adapter,
      obsoleteKeyRemover: obsoleteKeyRemover,
      pendingRevealRemover: pendingRevealRemover,
      clock: clock ?? () => now,
      statusTimeout: statusTimeout,
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime.utc(2026, 6, 20, 12);
    useGraph(createGraph());
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

    final recreated = createGraph(
      clock: () => now.add(const Duration(hours: 1)),
    ).service;
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
    'non-map JSON': '[]',
    'missing fields': '{"text":"Incomplete wisdom"}',
    'invalid timestamp type':
        '{"text":"Invalid wisdom","revealedAtMs":"now","unlockAtMs":2}',
    'invalid timestamp order':
        '{"text":"Invalid wisdom","revealedAtMs":2,"unlockAtMs":1}',
    'invalid short interval':
        '{"text":"Invalid wisdom","revealedAtMs":1000,"unlockAtMs":301000}',
    'invalid long interval':
        '{"text":"Invalid wisdom","revealedAtMs":1000,"unlockAtMs":90001000}',
    'empty text': '{"text":"   ","revealedAtMs":1000,"unlockAtMs":86401000}',
    'invalid stored value type': 42,
  };

  for (final corruptRecord in corruptRecords.entries) {
    test('corrupt daily record returns ready: ${corruptRecord.key}', () async {
      SharedPreferences.setMockInitialValues({
        'daily_wisdom_access': corruptRecord.value,
      });
      useGraph(createGraph());
      var selected = false;

      final status = await service.status();
      final result = await service.reveal(
        selectWisdom: () {
          selected = true;
          return 'New wisdom';
        },
      );
      final recovered = await repository.loadDailyWisdomRecord();

      expect(selected, isTrue);
      expect(status.isReady, isTrue);
      expect(result.text, 'New wisdom');
      expect(result.isNew, isTrue);
      expect(recovered, isNotNull);
      expect(recovered!.text, 'New wisdom');
    });
  }

  test('corrupt daily relaunch remains ready without recovery window',
      () async {
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': '{',
    });
    useGraph(createGraph());

    final first = await service.status();
    final recreatedGraph = createGraph(
      clock: () => now.add(const Duration(minutes: 5)),
    );
    final relaunched = await recreatedGraph.service.status();
    final repeated = await service.status();
    await Future<void>.delayed(Duration.zero);
    await repository.waitForIdle();
    await recreatedGraph.repository.waitForIdle();
    final prefs = await SharedPreferences.getInstance();

    expect(first.isReady, isTrue);
    expect(relaunched.isReady, isTrue);
    expect(repeated.isReady, isTrue);
    expect(prefs.containsKey('daily_wisdom_access'), isFalse);
  });

  test('corrupt daily record preserves prepared pending without lock',
      () async {
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': '{',
      'pending_daily_wisdom_reveal': PendingDailyWisdomReveal(
        text: 'Prepared interrupted wisdom',
        preparedAt: now,
      ).encode(),
    });
    useGraph(createGraph());

    final status = await service.status();
    final prepared = await service.prepareReveal(
      selectWisdom: () => 'Different wisdom',
    );
    final pending = await repository.loadPendingDailyWisdomReveal();
    await Future<void>.delayed(Duration.zero);
    await repository.waitForIdle();
    final prefs = await SharedPreferences.getInstance();

    expect(status.isReady, isTrue);
    expect(prepared.text, 'Prepared interrupted wisdom');
    expect(prepared.hasAuthoritativeRecord, isFalse);
    expect(pending, isNotNull);
    expect(pending!.text, 'Prepared interrupted wisdom');
    expect(pending.phase, PendingDailyWisdomRevealPhase.prepared);
    expect(prefs.containsKey('daily_wisdom_access'), isFalse);
  });

  test('corrupt daily cleanup failure does not fabricate lock or wisdom',
      () async {
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': '{',
    });
    useGraph(
      createGraph(
        adapter: InterceptingStoragePreferencesAdapter(
          removeInterceptor: (key, remove) {
            if (key == DailyAccessRepository.dailyWisdomAccessKey) {
              throw StateError('Simulated daily wisdom cleanup failure.');
            }

            return remove();
          },
        ),
      ),
    );

    final status = await service.status();
    final result = await service.reveal(
      selectWisdom: () => 'Wisdom after cleanup failure',
    );
    final recovered = await repository.loadDailyWisdomRecord();

    expect(status.isReady, isTrue);
    expect(result.text, 'Wisdom after cleanup failure');
    expect(result.isNew, isTrue);
    expect(recovered, isNotNull);
    expect(recovered!.text, 'Wisdom after cleanup failure');
  });

  test('corrupt daily record recovers from durable revealed pending commit',
      () async {
    final revealAt = now.subtract(const Duration(minutes: 5));
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': '{',
      'pending_daily_wisdom_reveal': PendingDailyWisdomReveal(
        text: 'Interrupted committed wisdom',
        preparedAt: revealAt.subtract(const Duration(seconds: 2)),
        confirmedRevealBoundary: revealAt,
        phase: PendingDailyWisdomRevealPhase.revealedPendingCommit,
      ).encode(),
    });
    useGraph(createGraph());

    final status = await service.status();
    final recovered = await repository.loadDailyWisdomRecord();
    await Future<void>.delayed(Duration.zero);
    await repository.waitForIdle();
    final pending = await repository.loadPendingDailyWisdomReveal();

    expect(status.isReady, isFalse);
    expect(recovered, isNotNull);
    expect(recovered!.text, 'Interrupted committed wisdom');
    expect(
      recovered.revealedAt.millisecondsSinceEpoch,
      revealAt.millisecondsSinceEpoch,
    );
    expect(
      recovered.unlockAt.millisecondsSinceEpoch,
      revealAt.add(const Duration(hours: 24)).millisecondsSinceEpoch,
    );
    expect(pending, isNull);
  });

  test('daily record decoder enforces exact 24-hour records', () {
    final hugeTimestamp = 1 << 62;
    final revealedAt = now;

    String encodeRecord({
      required String text,
      required DateTime revealedAt,
      required DateTime unlockAt,
    }) {
      return jsonEncode({
        'text': text,
        'revealedAtMs': revealedAt.millisecondsSinceEpoch,
        'unlockAtMs': unlockAt.millisecondsSinceEpoch,
      });
    }

    final exact = DailyWisdomRecord.decode(
      encodeRecord(
        text: 'Exact wisdom',
        revealedAt: revealedAt,
        unlockAt: revealedAt.add(const Duration(hours: 24)),
      ),
    );

    expect(exact.text, 'Exact wisdom');
    expect(
      exact.unlockAt.difference(exact.revealedAt),
      const Duration(hours: 24),
    );
    expect(
      () => DailyWisdomRecord.decode(
        encodeRecord(
          text: 'Too short wisdom',
          revealedAt: revealedAt,
          unlockAt: revealedAt.add(const Duration(minutes: 5)),
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => DailyWisdomRecord.decode(
        encodeRecord(
          text: 'Twenty-three hour wisdom',
          revealedAt: revealedAt,
          unlockAt: revealedAt.add(const Duration(hours: 23)),
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => DailyWisdomRecord.decode(
        encodeRecord(
          text: 'Twenty-five hour wisdom',
          revealedAt: revealedAt,
          unlockAt: revealedAt.add(const Duration(hours: 25)),
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => DailyWisdomRecord.decode(
        encodeRecord(
          text: 'Ten-year wisdom',
          revealedAt: revealedAt,
          unlockAt: DateTime.utc(2036, 6, 20, 12),
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => DailyWisdomRecord.decode(
        encodeRecord(
          text: 'Equal boundary wisdom',
          revealedAt: revealedAt,
          unlockAt: revealedAt,
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => DailyWisdomRecord.decode('[]'),
      throwsFormatException,
    );
    expect(
      () => DailyWisdomRecord.decode(
        jsonEncode({
          'text': 7,
          'revealedAtMs': revealedAt.millisecondsSinceEpoch,
          'unlockAtMs':
              revealedAt.add(const Duration(hours: 24)).millisecondsSinceEpoch,
        }),
      ),
      throwsFormatException,
    );
    expect(
      () => DailyWisdomRecord.decode(
        jsonEncode({
          'text': 'Missing unlock wisdom',
          'revealedAtMs': revealedAt.millisecondsSinceEpoch,
        }),
      ),
      throwsFormatException,
    );
    expect(
      () => DailyWisdomRecord.decode(
        jsonEncode({
          'text': 'Negative wisdom',
          'revealedAtMs': -1,
          'unlockAtMs': const Duration(hours: 24).inMilliseconds - 1,
        }),
      ),
      throwsFormatException,
    );
    expect(
      () => DailyWisdomRecord.decode(
        jsonEncode({
          'text': 'Overflow wisdom',
          'revealedAtMs': hugeTimestamp,
          'unlockAtMs': hugeTimestamp + 1,
        }),
      ),
      throwsFormatException,
    );
    expect(
      () => DailyWisdomRecord.decode(
        jsonEncode({
          'text': 'Underflow wisdom',
          'revealedAtMs': -hugeTimestamp,
          'unlockAtMs': -hugeTimestamp + 1,
        }),
      ),
      throwsFormatException,
    );
  });

  test('revealId absent decodes as a valid Build 25 record with null', () {
    final decoded = DailyWisdomRecord.decode(
      jsonEncode({
        'text': 'No revealId wisdom',
        'revealedAtMs': now.millisecondsSinceEpoch,
        'unlockAtMs': now.add(const Duration(hours: 24)).millisecondsSinceEpoch,
      }),
    );

    expect(decoded.revealId, isNull);
    expect(decoded.text, 'No revealId wisdom');
  });

  test('valid canonical UUID v4 revealId round-trips', () {
    const revealId = '123e4567-e89b-42d3-a456-426614174000';
    final original = DailyWisdomRecord(
      text: 'Round trip wisdom',
      revealedAt: now,
      unlockAt: now.add(const Duration(hours: 24)),
      revealId: revealId,
    );

    final decoded = DailyWisdomRecord.decode(original.encode());

    expect(decoded.revealId, revealId);
  });

  test('malformed non-empty revealId is rejected', () {
    expect(
      () => DailyWisdomRecord.decode(
        jsonEncode({
          'text': 'Malformed revealId wisdom',
          'revealedAtMs': now.millisecondsSinceEpoch,
          'unlockAtMs':
              now.add(const Duration(hours: 24)).millisecondsSinceEpoch,
          'revealId': 'not-a-uuid',
        }),
      ),
      throwsFormatException,
    );
  });

  test('whitespace-padded revealId is rejected', () {
    expect(
      () => DailyWisdomRecord.decode(
        jsonEncode({
          'text': 'Whitespace revealId wisdom',
          'revealedAtMs': now.millisecondsSinceEpoch,
          'unlockAtMs':
              now.add(const Duration(hours: 24)).millisecondsSinceEpoch,
          'revealId': ' 123e4567-e89b-42d3-a456-426614174000 ',
        }),
      ),
      throwsFormatException,
    );
  });

  test('a non-v4 UUID revealId is rejected', () {
    expect(
      () => DailyWisdomRecord.decode(
        jsonEncode({
          'text': 'Non-v4 revealId wisdom',
          'revealedAtMs': now.millisecondsSinceEpoch,
          'unlockAtMs':
              now.add(const Duration(hours: 24)).millisecondsSinceEpoch,
          // Version nibble '1' (a v1/time-based UUID shape) instead of '4'.
          'revealId': '123e4567-e89b-12d3-a456-426614174000',
        }),
      ),
      throwsFormatException,
    );
  });

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
    final pending = await repository.loadPendingDailyWisdomReveal();

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

    final recreated = createGraph(
      clock: () => now.add(const Duration(minutes: 4)),
    ).service;
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
    useGraph(createGraph());
    var selections = 0;

    final prepared = await service.prepareReveal(
      selectWisdom: () => 'Valid pending wisdom ${++selections}',
    );
    final prefs = await SharedPreferences.getInstance();
    final pending = await repository.loadPendingDailyWisdomReveal();

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
    final hugeTimestamp = 1 << 62;

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
    expect(
      () => PendingDailyWisdomReveal.decode('[]'),
      throwsFormatException,
    );
    expect(
      () => PendingDailyWisdomReveal.decode(
        jsonEncode({
          'schemaVersion': 1,
          'text': 'Missing phase wisdom',
          'preparedAtMs': preparedAt,
        }),
      ),
      throwsFormatException,
    );
    expect(
      () => PendingDailyWisdomReveal.decode(
        encodePending({'confirmedRevealBoundaryMs': 'later'}),
      ),
      throwsFormatException,
    );
    expect(
      () => PendingDailyWisdomReveal.decode(
        encodePending({'preparedAtMs': hugeTimestamp}),
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
    final persisted = await repository.loadDailyWisdomRecord();

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
    await Future<void>.delayed(Duration.zero);
    await repository.waitForIdle();
    final pending = await repository.loadPendingDailyWisdomReveal();

    expect(pending, isNull);
  });

  test('pending cleanup failure does not invalidate committed wisdom',
      () async {
    useGraph(
      createGraph(
        pendingRevealRemover: (prefs, key) async {
          throw StateError('Simulated pending cleanup failure.');
        },
      ),
    );

    await service.prepareReveal(selectWisdom: () => 'Cleanup failure wisdom');
    final committed = await service.finalizeVisualReveal(
      text: 'Cleanup failure wisdom',
      revealBoundary: now.add(const Duration(seconds: 1)),
    );
    final persisted = await repository.loadDailyWisdomRecord();

    expect(committed.text, 'Cleanup failure wisdom');
    expect(committed.isNew, isTrue);
    expect(persisted!.text, 'Cleanup failure wisdom');
  });

  test('commit persistence failure preserves pending without daily lock',
      () async {
    useGraph(
      createGraph(
        adapter: InterceptingStoragePreferencesAdapter(
          setStringInterceptor: (key, value, persist) {
            if (key == DailyAccessRepository.dailyWisdomAccessKey) {
              throw StateError(
                'Simulated daily wisdom persistence failure.',
              );
            }

            return persist();
          },
        ),
      ),
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
    final pending = await repository.loadPendingDailyWisdomReveal();

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
    final pending = await repository.loadPendingDailyWisdomReveal();

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

    final recreated = createGraph(
      clock: () => revealAt.add(const Duration(minutes: 1)),
    ).service;
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
    await repository.savePendingDailyWisdomReveal(
      PendingDailyWisdomReveal(
        text: 'Boundary survived kill',
        preparedAt: now,
        confirmedRevealBoundary: revealAt,
        phase: PendingDailyWisdomRevealPhase.revealedPendingCommit,
      ),
    );

    final recreated = createGraph(
      clock: () => revealAt.add(const Duration(minutes: 4)),
    ).service;
    final committed = await recreated.recoverIncompleteReveal();
    final persisted = await repository.loadDailyWisdomRecord();

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
      repository: repository,
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
    final persisted = await repository.loadDailyWisdomRecord();

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

  test('AppServices-created services share observable production daily state',
      () async {
    await app_services.dailyAccessRepository.clearDailyWisdomRecordBestEffort();
    await app_services.dailyAccessRepository.clearPendingDailyWisdomReveal();

    final firstService = app_services.createDailyWisdomAccessService(
      clock: () => now,
    );
    final secondService = app_services.createDailyWisdomAccessService(
      clock: () => now,
    );

    var selections = 0;

    try {
      final first = await firstService.prepareReveal(
        selectWisdom: () {
          selections += 1;
          return 'Production shared repository wisdom';
        },
      );
      final second = await secondService.prepareReveal(
        selectWisdom: () {
          selections += 1;
          return 'Different production wisdom';
        },
      );
      final pending = await app_services.dailyAccessRepository
          .loadPendingDailyWisdomReveal();

      expect(selections, 1);
      expect(first.text, 'Production shared repository wisdom');
      expect(second.text, first.text);
      expect(pending, isNotNull);
      expect(pending!.text, first.text);
    } finally {
      await app_services.dailyAccessRepository.clearPendingDailyWisdomReveal();
      await app_services.dailyAccessRepository
          .clearDailyWisdomRecordBestEffort();
    }
  });

  test('two services sharing one repository prepare once', () async {
    final firstService = DailyWisdomAccessService(
      repository: repository,
      clock: () => now,
    );
    final secondService = DailyWisdomAccessService(
      repository: repository,
      clock: () => now,
    );
    var selections = 0;

    final prepared = await Future.wait([
      firstService.prepareReveal(
        selectWisdom: () => 'Runtime pending ${++selections}',
      ),
      secondService.prepareReveal(
        selectWisdom: () => 'Runtime pending ${++selections}',
      ),
    ]);
    final pending = await repository.loadPendingDailyWisdomReveal();

    expect(selections, 1);
    expect(
        prepared.map((result) => result.text).toSet(), {'Runtime pending 1'});
    expect(pending!.text, 'Runtime pending 1');
  });

  test('two services sharing one repository finalize once', () async {
    final dailyWriteStarted = Completer<void>();
    final allowDailyWrite = Completer<void>();
    final adapter = InterceptingStoragePreferencesAdapter(
      setStringInterceptor: (key, value, persist) async {
        if (key == DailyAccessRepository.dailyWisdomAccessKey) {
          dailyWriteStarted.complete();
          await allowDailyWrite.future;
        }
        await persist();
      },
    );
    useGraph(createGraph(adapter: adapter));
    final firstService = DailyWisdomAccessService(
      repository: repository,
      clock: () => now,
    );
    final secondService = DailyWisdomAccessService(
      repository: repository,
      clock: () => now,
    );
    await firstService.prepareReveal(
      selectWisdom: () => 'Runtime committed once',
    );
    final firstBoundary = now.add(const Duration(seconds: 5));
    final secondBoundary = now.add(const Duration(seconds: 9));

    final firstFinalize = firstService.finalizeVisualReveal(
      text: 'Runtime committed once',
      revealBoundary: firstBoundary,
    );
    await dailyWriteStarted.future;
    final secondFinalize = secondService.finalizeVisualReveal(
      text: 'Runtime committed once',
      revealBoundary: secondBoundary,
    );

    allowDailyWrite.complete();
    final results = await Future.wait([firstFinalize, secondFinalize]);
    final persisted = await repository.loadDailyWisdomRecord();

    expect(results.map((result) => result.text).toSet(),
        {'Runtime committed once'});
    expect(
      results.map((result) => result.unlockAt!.millisecondsSinceEpoch).toSet(),
      {firstBoundary.add(const Duration(hours: 24)).millisecondsSinceEpoch},
    );
    expect(
      persisted!.revealedAt.millisecondsSinceEpoch,
      firstBoundary.millisecondsSinceEpoch,
    );
  });

  test(
      'shared repository prepare blocks invalid cross-instance finalize overlap',
      () async {
    final pendingWriteStarted = Completer<void>();
    final allowPendingWrite = Completer<void>();
    final adapter = InterceptingStoragePreferencesAdapter(
      setStringInterceptor: (key, value, persist) async {
        if (key == DailyAccessRepository.pendingDailyWisdomRevealKey) {
          pendingWriteStarted.complete();
          await allowPendingWrite.future;
        }
        await persist();
      },
    );
    useGraph(createGraph(adapter: adapter));
    final firstService = DailyWisdomAccessService(
      repository: repository,
      clock: () => now,
    );
    final secondService = DailyWisdomAccessService(
      repository: repository,
      clock: () => now,
    );

    final prepare = firstService.prepareReveal(
      selectWisdom: () => 'Runtime ordered wisdom',
    );
    await pendingWriteStarted.future;

    await expectLater(
      secondService.finalizeVisualReveal(
        text: 'Runtime ordered wisdom',
        revealBoundary: now.add(const Duration(seconds: 5)),
      ),
      throwsStateError,
    );

    allowPendingWrite.complete();
    final prepared = await prepare;

    expect(prepared.text, 'Runtime ordered wisdom');
  });

  test('in-flight finalization rejects a different wisdom text', () async {
    final dailyWriteStarted = Completer<void>();
    final allowDailyWrite = Completer<void>();
    useGraph(
      createGraph(
        adapter: InterceptingStoragePreferencesAdapter(
          setStringInterceptor: (key, value, persist) async {
            if (key == DailyAccessRepository.dailyWisdomAccessKey) {
              dailyWriteStarted.complete();
              await allowDailyWrite.future;
            }

            await persist();
          },
        ),
      ),
    );
    await service.prepareReveal(selectWisdom: () => 'Original wisdom');
    final revealAt = now.add(const Duration(seconds: 5));

    final first = service.finalizeVisualReveal(
      text: 'Original wisdom',
      revealBoundary: revealAt,
    );
    await dailyWriteStarted.future;

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
    final prefs = await SharedPreferences.getInstance();
    final pending = PendingDailyWisdomReveal.decode(
      prefs.getString(DailyAccessRepository.pendingDailyWisdomRevealKey)!,
    );

    expect(observed, 'still waiting');
    expect(pending.text, 'Original wisdom');
    expect(
      pending.confirmedRevealBoundary!.millisecondsSinceEpoch,
      revealAt.millisecondsSinceEpoch,
    );

    allowDailyWrite.complete();
    await first;
  });

  test('existing locked record wins over pending state', () async {
    await repository.savePendingDailyWisdomReveal(
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
    await repository.saveDailyWisdomRecord(authoritative);

    final prepared = await service.prepareReveal(
      selectWisdom: () => 'Should not select',
    );
    final committed = await service.finalizeVisualReveal(
      text: authoritative.text,
      revealBoundary: now.add(const Duration(seconds: 1)),
    );

    expect(prepared.text, authoritative.text);
    expect(prepared.hasAuthoritativeRecord, isTrue);
    expect(committed.text, authoritative.text);
    expect(committed.isNew, isFalse);
  });

  test('stale pending before expired record unlock is ignored', () async {
    final expiredRecord = DailyWisdomRecord(
      text: 'Yesterday wisdom',
      revealedAt: now.subtract(const Duration(hours: 25)),
      unlockAt: now.subtract(const Duration(hours: 1)),
    );
    await repository.saveDailyWisdomRecord(expiredRecord);
    await repository.savePendingDailyWisdomReveal(
      PendingDailyWisdomReveal(
        text: 'Stale yesterday pending',
        preparedAt: now.subtract(const Duration(hours: 2)),
      ),
    );
    var selections = 0;

    final prepared = await service.prepareReveal(
      selectWisdom: () => 'Fresh wisdom ${++selections}',
    );
    final pending = await repository.loadPendingDailyWisdomReveal();
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
    await repository.saveDailyWisdomRecord(expiredRecord);
    await repository.savePendingDailyWisdomReveal(
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
    final hangingGraph = createGraph(
      adapter: InterceptingStoragePreferencesAdapter(
        setStringInterceptor: (key, value, persist) {
          if (key == DailyAccessRepository.pendingDailyWisdomRevealKey) {
            return Completer<void>().future;
          }

          return persist();
        },
      ),
    );
    final hangingService = hangingGraph.service;
    var selections = 0;

    final first = hangingService.prepareReveal(
      selectWisdom: () => 'Never persisted ${++selections}',
    );
    final second = hangingService.prepareReveal(
      selectWisdom: () => 'Never persisted ${++selections}',
    );
    final observed = await Future.any([
      first.then((_) => 'completed'),
      second.then((_) => 'completed'),
      Future<void>.delayed(const Duration(milliseconds: 20))
          .then((_) => 'still waiting'),
    ]);

    expect(observed, 'still waiting');
    expect(selections, 1);
  });

  test('only legacy wisdom text is ignored and removed', () async {
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_text': 'Legacy wisdom text',
    });
    useGraph(createGraph());

    final status = await service.status();
    await Future<void>.delayed(Duration.zero);
    await repository.waitForIdle();
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
    useGraph(createGraph());

    final status = await service.status();
    await Future<void>.delayed(Duration.zero);
    await repository.waitForIdle();
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
    useGraph(createGraph());

    final status = await service.status();
    var selected = false;
    final result = await service.reveal(
      selectWisdom: () {
        selected = true;
        return 'First real wisdom';
      },
    );
    final prefs = await SharedPreferences.getInstance();
    await Future<void>.delayed(Duration.zero);
    await repository.waitForIdle();
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
    useGraph(createGraph());

    final loaded = await repository.loadDailyWisdomRecord();
    await Future<void>.delayed(Duration.zero);
    await repository.waitForIdle();
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
    useGraph(createGraph());

    final status = await service.status();
    await Future<void>.delayed(Duration.zero);
    await repository.waitForIdle();
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
    final persisted = await repository.loadDailyWisdomRecord();

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
    useGraph(createGraph());

    final status = await service.status();
    await Future<void>.delayed(Duration.zero);
    await repository.waitForIdle();
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
    useGraph(createGraph());

    final status = await service.status();
    await Future<void>.delayed(Duration.zero);
    await repository.waitForIdle();
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
    useGraph(
      createGraph(
        obsoleteKeyRemover: (prefs, key) async {
          throw StateError('Simulated obsolete-key removal failure.');
        },
      ),
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

  test('service delegates backfillRevealIdIfNeeded to the repository',
      () async {
    final legacyRecord = DailyWisdomRecord(
      text: 'Service delegation wisdom',
      revealedAt: now,
      unlockAt: now.add(const Duration(hours: 24)),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('daily_wisdom_access', legacyRecord.encode());

    await service.backfillRevealIdIfNeeded();

    final backfilled = await repository.loadDailyWisdomRecord();
    expect(backfilled!.revealId, isNotNull);
    expect(backfilled.text, 'Service delegation wisdom');
  });

  group('revealId/revealedAt propagation (Phase 3D-B)', () {
    test('a new successful commit returns a non-null revealId/revealedAt',
        () async {
      final result = await service.reveal(
        selectWisdom: () => 'Newly committed wisdom',
      );

      expect(result.revealId, isNotNull);
      expect(result.revealedAt, isNotNull);
      expect(
        result.revealedAt!.millisecondsSinceEpoch,
        now.millisecondsSinceEpoch,
      );
    });

    test(
        'rereading an already-locked reveal via reveal() returns the same '
        'revealId/revealedAt without minting a new one', () async {
      final first = await service.reveal(
        selectWisdom: () => 'Locked wisdom',
      );

      now = now.add(const Duration(minutes: 1));
      final second = await service.reveal(
        selectWisdom: () => 'Should not be selected',
      );

      expect(second.revealId, first.revealId);
      expect(
        second.revealedAt!.millisecondsSinceEpoch,
        first.revealedAt!.millisecondsSinceEpoch,
      );
    });

    test(
        'a recovery commit returns the promoted authoritative revealId/'
        'revealedAt', () async {
      // Simulate a crash after visual reveal was confirmed but before the
      // daily record was committed: a revealedPendingCommit pending reveal
      // exists, with no authoritative daily_wisdom_access record yet.
      final boundary = now.add(const Duration(seconds: 5));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'pending_daily_wisdom_reveal',
        PendingDailyWisdomReveal(
          text: 'Recovering wisdom',
          preparedAt: now,
          confirmedRevealBoundary: boundary,
          phase: PendingDailyWisdomRevealPhase.revealedPendingCommit,
        ).encode(),
      );

      now = boundary.add(const Duration(minutes: 1));
      final recoveredAccess = await service.recoverIncompleteReveal();

      expect(recoveredAccess, isNotNull);
      expect(recoveredAccess!.revealId, isNotNull);
      expect(
        recoveredAccess.revealedAt!.millisecondsSinceEpoch,
        boundary.millisecondsSinceEpoch,
      );

      final persisted = await repository.loadDailyWisdomRecord();
      expect(persisted!.revealId, recoveredAccess.revealId);
    });

    test('a locked status carries the authoritative revealId/revealedAt',
        () async {
      final committed = await service.reveal(
        selectWisdom: () => 'Status wisdom',
      );

      now = now.add(const Duration(hours: 1));
      final status = await service.status();

      expect(status.isReady, isFalse);
      expect(status.revealId, committed.revealId);
      expect(
        status.revealedAt!.millisecondsSinceEpoch,
        committed.revealedAt!.millisecondsSinceEpoch,
      );
    });

    test('a ready status carries neither revealId nor revealedAt', () async {
      final status = await service.status();

      expect(status.isReady, isTrue);
      expect(status.revealId, isNull);
      expect(status.revealedAt, isNull);
    });

    test(
        'a fresh prepared reveal (DailyWisdomPreparedReveal) has null '
        'revealId/revealedAt', () async {
      final prepared = await service.prepareReveal(
        selectWisdom: () => 'Fresh prepared wisdom',
      );

      expect(prepared.hasAuthoritativeRecord, isFalse);
      expect(prepared.revealId, isNull);
      expect(prepared.revealedAt, isNull);
    });

    test(
        'preparing against an already-authoritative record carries its '
        'revealId/revealedAt through DailyWisdomPreparedReveal', () async {
      final committed = await service.reveal(
        selectWisdom: () => 'Authoritative wisdom',
      );

      now = now.add(const Duration(minutes: 1));
      final prepared = await service.prepareReveal(
        selectWisdom: () => 'Should not be selected',
      );

      expect(prepared.hasAuthoritativeRecord, isTrue);
      expect(prepared.revealId, committed.revealId);
      expect(
        prepared.revealedAt!.millisecondsSinceEpoch,
        committed.revealedAt!.millisecondsSinceEpoch,
      );
    });

    test(
        'an existing pre-Build-26 authoritative record without a revealId '
        'is preserved (not fabricated) through status()', () async {
      final legacyRecord = DailyWisdomRecord(
        text: 'Pre-Build-26 wisdom',
        revealedAt: now,
        unlockAt: now.add(const Duration(hours: 24)),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('daily_wisdom_access', legacyRecord.encode());

      now = now.add(const Duration(hours: 1));
      final status = await service.status();

      expect(status.isReady, isFalse);
      expect(status.revealId, isNull);
      expect(status.revealedAt, isNotNull);
    });
  });
}
