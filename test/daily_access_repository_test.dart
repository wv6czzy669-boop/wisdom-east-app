import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/models/daily_access_snapshot.dart';
import 'package:wisdom_app/models/daily_wisdom_record.dart';
import 'package:wisdom_app/models/pending_daily_wisdom_reveal.dart';
import 'package:wisdom_app/persistence/persistence_operation_coordinator.dart';
import 'package:wisdom_app/persistence/storage_preferences_adapter.dart';
import 'package:wisdom_app/repositories/daily_access_repository.dart';

import 'persistence_test_helpers.dart';

final RegExp _uuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

void main() {
  late DateTime now;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime.utc(2026, 6, 20, 12);
  });

  DailyAccessRepository createRepository({
    StoragePreferencesAdapter? adapter,
    PersistenceOperationCoordinator? coordinator,
    Future<void> Function(SharedPreferences prefs, String key)?
        pendingRevealRemover,
  }) {
    return DailyAccessRepository(
      preferencesAdapter: adapter ?? StoragePreferencesAdapter(),
      operationCoordinator: coordinator ?? PersistenceOperationCoordinator(),
      pendingRevealRemover: pendingRevealRemover,
    );
  }

  test('atomic snapshot returns valid locked record consistently', () async {
    final repository = createRepository();
    final record = DailyWisdomRecord(
      text: 'Locked wisdom',
      revealedAt: now,
      unlockAt: now.add(DailyWisdomRecord.lockDuration),
    );
    await repository.saveDailyWisdomRecord(record);

    final snapshot = await repository.snapshot(
      now: now.add(const Duration(minutes: 1)),
    );

    expect(snapshot, isA<DailyAccessLocked>());
    expect((snapshot as DailyAccessLocked).record.text, 'Locked wisdom');
  });

  test('atomic snapshot returns prepared pending consistently', () async {
    final repository = createRepository();
    await repository.savePendingDailyWisdomReveal(
      PendingDailyWisdomReveal(
        text: 'Prepared wisdom',
        preparedAt: now,
      ),
    );

    final snapshot = await repository.snapshot(now: now);

    expect(snapshot, isA<DailyAccessReady>());
    expect((snapshot as DailyAccessReady).pending!.text, 'Prepared wisdom');
    expect(snapshot.pending!.phase, PendingDailyWisdomRevealPhase.prepared);
  });

  test('atomic snapshot returns revealedPendingCommit consistently', () async {
    final repository = createRepository();
    await repository.savePendingDailyWisdomReveal(
      PendingDailyWisdomReveal(
        text: 'Boundary wisdom',
        preparedAt: now,
        confirmedRevealBoundary: now.add(const Duration(seconds: 5)),
        phase: PendingDailyWisdomRevealPhase.revealedPendingCommit,
      ),
    );

    final snapshot = await repository.snapshot(now: now);

    expect(snapshot, isA<DailyAccessPendingCommit>());
    expect(
      (snapshot as DailyAccessPendingCommit)
          .pending
          .confirmedRevealBoundary!
          .millisecondsSinceEpoch,
      now.add(const Duration(seconds: 5)).millisecondsSinceEpoch,
    );
  });

  test('authoritative daily record wins over stale pending', () async {
    final repository = createRepository();
    final record = DailyWisdomRecord(
      text: 'Authoritative wisdom',
      revealedAt: now,
      unlockAt: now.add(DailyWisdomRecord.lockDuration),
    );
    await repository.saveDailyWisdomRecord(record);
    await repository.savePendingDailyWisdomReveal(
      PendingDailyWisdomReveal(
        text: 'Stale pending',
        preparedAt: now.subtract(const Duration(minutes: 1)),
      ),
    );

    final snapshot = await repository.snapshot(
      now: now.add(const Duration(minutes: 1)),
    );

    expect(snapshot, isA<DailyAccessLocked>());
    expect((snapshot as DailyAccessLocked).record.text, 'Authoritative wisdom');
  });

  test('corrupt daily with no pending returns ready without synthetic wisdom',
      () async {
    final repository = createRepository();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(DailyAccessRepository.dailyWisdomAccessKey, '{');

    final snapshot = await repository.snapshot(now: now);
    await Future<void>.delayed(Duration.zero);
    await repository.waitForIdle();

    expect(snapshot, isA<DailyAccessReady>());
    expect((snapshot as DailyAccessReady).pending, isNull);
    expect(
        prefs.containsKey(DailyAccessRepository.dailyWisdomAccessKey), isFalse);
  });

  test('corrupt daily with prepared pending preserves same text', () async {
    final repository = createRepository();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(DailyAccessRepository.dailyWisdomAccessKey, '{');
    await repository.savePendingDailyWisdomReveal(
      PendingDailyWisdomReveal(
        text: 'Prepared survives',
        preparedAt: now,
      ),
    );

    final snapshot = await repository.snapshot(now: now);
    await Future<void>.delayed(Duration.zero);
    await repository.waitForIdle();

    expect(snapshot, isA<DailyAccessReady>());
    expect((snapshot as DailyAccessReady).pending!.text, 'Prepared survives');
    expect(
        prefs.containsKey(DailyAccessRepository.dailyWisdomAccessKey), isFalse);
  });

  test('corrupt daily with revealedPendingCommit finalizes original boundary',
      () async {
    final repository = createRepository();
    final prefs = await SharedPreferences.getInstance();
    final boundary = now.add(const Duration(seconds: 8));
    await prefs.setString(DailyAccessRepository.dailyWisdomAccessKey, '{');
    await repository.savePendingDailyWisdomReveal(
      PendingDailyWisdomReveal(
        text: 'Recovered boundary wisdom',
        preparedAt: now,
        confirmedRevealBoundary: boundary,
        phase: PendingDailyWisdomRevealPhase.revealedPendingCommit,
      ),
    );

    final snapshot = await repository.snapshot(
      now: boundary.add(const Duration(minutes: 1)),
    );
    final record = await repository.loadDailyWisdomRecord();

    expect(snapshot, isA<DailyAccessLocked>());
    expect(record!.text, 'Recovered boundary wisdom');
    expect(
      record.revealedAt.millisecondsSinceEpoch,
      boundary.millisecondsSinceEpoch,
    );
    expect(
      record.unlockAt.millisecondsSinceEpoch,
      boundary.add(DailyWisdomRecord.lockDuration).millisecondsSinceEpoch,
    );
  });

  test('corrupt pending creates no lock or synthetic wisdom', () async {
    final repository = createRepository();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      DailyAccessRepository.pendingDailyWisdomRevealKey,
      '{',
    );

    final snapshot = await repository.snapshot(now: now);
    await Future<void>.delayed(Duration.zero);
    await repository.waitForIdle();

    expect(snapshot, isA<DailyAccessReady>());
    expect(await repository.loadDailyWisdomRecord(), isNull);
    expect(
      prefs.containsKey(DailyAccessRepository.pendingDailyWisdomRevealKey),
      isFalse,
    );
  });

  test('snapshot excludes concurrent finalize until snapshot completes',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final boundary = now.add(const Duration(seconds: 5));
    await prefs.setString(
      DailyAccessRepository.pendingDailyWisdomRevealKey,
      PendingDailyWisdomReveal(
        text: 'Exclusive snapshot wisdom',
        preparedAt: now,
      ).encode(),
    );

    final snapshotReadDaily = Completer<void>();
    final snapshotWaitingBeforePending = Completer<void>();
    final allowSnapshotPendingRead = Completer<void>();
    final events = <String>[];
    var dailyReadCount = 0;

    final adapter = InterceptingStoragePreferencesAdapter(
      getStringInterceptor: (key, read) async {
        if (key == DailyAccessRepository.dailyWisdomAccessKey) {
          dailyReadCount++;
          if (dailyReadCount == 1) {
            events.add('snapshot-read-daily');
            snapshotReadDaily.complete();
          } else {
            events.add('finalize-read-daily');
          }
        }

        if (key == DailyAccessRepository.pendingDailyWisdomRevealKey &&
            dailyReadCount == 1 &&
            !allowSnapshotPendingRead.isCompleted) {
          events.add('snapshot-wait-before-pending');
          snapshotWaitingBeforePending.complete();
          await allowSnapshotPendingRead.future;
          events.add('snapshot-read-pending');
        }

        return read();
      },
      setStringInterceptor: (key, value, persist) async {
        if (key == DailyAccessRepository.dailyWisdomAccessKey) {
          events.add('finalize-write-daily');
        }
        await persist();
      },
    );
    final repository = createRepository(adapter: adapter);

    final snapshotFuture = repository.snapshot(now: now);
    await snapshotReadDaily.future;
    await snapshotWaitingBeforePending.future;

    final finalizeFuture = repository.finalizeVisualReveal(
      text: 'Exclusive snapshot wisdom',
      revealBoundary: boundary,
      now: boundary,
    );

    expect(events, contains('snapshot-read-daily'));
    expect(events, contains('snapshot-wait-before-pending'));
    expect(events, isNot(contains('finalize-read-daily')));

    allowSnapshotPendingRead.complete();
    final snapshot = await snapshotFuture;

    expect(snapshot, isA<DailyAccessReady>());
    expect((snapshot as DailyAccessReady).pending!.text,
        'Exclusive snapshot wisdom');

    final finalized = await finalizeFuture;
    expect(finalized.text, 'Exclusive snapshot wisdom');
    expect(events, [
      'snapshot-read-daily',
      'snapshot-wait-before-pending',
      'snapshot-read-pending',
      'finalize-read-daily',
      'finalize-write-daily',
    ]);

    final lockedSnapshot = await repository.snapshot(
      now: boundary.add(const Duration(minutes: 1)),
    );
    expect(lockedSnapshot, isA<DailyAccessLocked>());
  });

  test('finalize excludes snapshot until daily and pending cleanup complete',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final boundary = now.add(const Duration(seconds: 5));
    await prefs.setString(
      DailyAccessRepository.pendingDailyWisdomRevealKey,
      PendingDailyWisdomReveal(
        text: 'Finalize first wisdom',
        preparedAt: now,
      ).encode(),
    );

    final dailyWriteStarted = Completer<void>();
    final allowDailyWrite = Completer<void>();
    final events = <String>[];
    var snapshotRequested = false;

    final adapter = InterceptingStoragePreferencesAdapter(
      getStringInterceptor: (key, read) async {
        if (snapshotRequested &&
            key == DailyAccessRepository.dailyWisdomAccessKey) {
          events.add('snapshot-read-daily');
        }
        return read();
      },
      setStringInterceptor: (key, value, persist) async {
        if (key == DailyAccessRepository.dailyWisdomAccessKey) {
          events.add('finalize-write-daily-start');
          dailyWriteStarted.complete();
          await allowDailyWrite.future;
          await persist();
          events.add('finalize-write-daily-end');
          return;
        }

        await persist();
      },
    );
    final repository = createRepository(adapter: adapter);

    final finalizeFuture = repository.finalizeVisualReveal(
      text: 'Finalize first wisdom',
      revealBoundary: boundary,
      now: boundary,
    );
    await dailyWriteStarted.future;

    snapshotRequested = true;
    final snapshotFuture = repository.snapshot(
      now: boundary.add(const Duration(minutes: 1)),
    );

    expect(events, ['finalize-write-daily-start']);

    allowDailyWrite.complete();
    final finalized = await finalizeFuture;
    final snapshot = await snapshotFuture;

    expect(finalized.text, 'Finalize first wisdom');
    expect(snapshot, isA<DailyAccessLocked>());
    expect(
        (snapshot as DailyAccessLocked).record.text, 'Finalize first wisdom');
    expect(events, [
      'finalize-write-daily-start',
      'finalize-write-daily-end',
      'snapshot-read-daily',
    ]);
  });

  test('corruption recovery snapshot excludes concurrent prepare', () async {
    final prefs = await SharedPreferences.getInstance();
    final boundary = now.add(const Duration(seconds: 5));
    await prefs.setString(DailyAccessRepository.dailyWisdomAccessKey, '{');
    await prefs.setString(
      DailyAccessRepository.pendingDailyWisdomRevealKey,
      PendingDailyWisdomReveal(
        text: 'Recovered exclusively',
        preparedAt: now,
        confirmedRevealBoundary: boundary,
        phase: PendingDailyWisdomRevealPhase.revealedPendingCommit,
      ).encode(),
    );

    final recoveryWriteStarted = Completer<void>();
    final allowRecoveryWrite = Completer<void>();
    var selections = 0;

    final adapter = InterceptingStoragePreferencesAdapter(
      setStringInterceptor: (key, value, persist) async {
        if (key == DailyAccessRepository.dailyWisdomAccessKey) {
          recoveryWriteStarted.complete();
          await allowRecoveryWrite.future;
        }
        await persist();
      },
    );
    final repository = createRepository(adapter: adapter);

    final snapshotFuture = repository.snapshot(
      now: boundary.add(const Duration(minutes: 1)),
    );
    await recoveryWriteStarted.future;

    final prepareFuture = repository.prepareReveal(
      selectWisdom: () => 'Competing ${++selections}',
      preparedAt: boundary.add(const Duration(seconds: 1)),
      now: boundary.add(const Duration(minutes: 1)),
    );

    expect(selections, 0);

    allowRecoveryWrite.complete();
    final snapshot = await snapshotFuture;
    final prepared = await prepareFuture;

    expect(snapshot, isA<DailyAccessLocked>());
    expect(
        (snapshot as DailyAccessLocked).record.text, 'Recovered exclusively');
    expect(prepared.hasAuthoritativeRecord, isTrue);
    expect(prepared.text, 'Recovered exclusively');
    expect(selections, 0);
  });

  test('prepare callers select exactly once and return the same text',
      () async {
    final repository = createRepository();
    var selections = 0;

    final results = await Future.wait([
      repository.prepareReveal(
        selectWisdom: () => 'Selected ${++selections}',
        preparedAt: now,
        now: now,
      ),
      repository.prepareReveal(
        selectWisdom: () => 'Selected ${++selections}',
        preparedAt: now,
        now: now,
      ),
    ]);

    expect(selections, 1);
    expect(results.map((result) => result.text).toSet(), {'Selected 1'});
  });

  test('same storage with shared coordinator serializes separate repositories',
      () async {
    final coordinator = PersistenceOperationCoordinator();
    final firstRepository = createRepository(
      adapter: StoragePreferencesAdapter(),
      coordinator: coordinator,
    );
    final secondRepository = createRepository(
      adapter: StoragePreferencesAdapter(),
      coordinator: coordinator,
    );
    var selections = 0;

    final results = await Future.wait([
      firstRepository.prepareReveal(
        selectWisdom: () => 'Shared domain ${++selections}',
        preparedAt: now,
        now: now,
      ),
      secondRepository.prepareReveal(
        selectWisdom: () => 'Shared domain ${++selections}',
        preparedAt: now,
        now: now,
      ),
    ]);
    final pending = await firstRepository.loadPendingDailyWisdomReveal();

    expect(selections, 1);
    expect(results.map((result) => result.text).toSet(), {'Shared domain 1'});
    expect(pending!.text, 'Shared domain 1');
  });

  test('separately injected coordinators remain intentionally isolated',
      () async {
    final firstWriteStarted = Completer<void>();
    final allowFirstWrite = Completer<void>();
    final firstRepository = createRepository(
      adapter: InterceptingStoragePreferencesAdapter(
        setStringInterceptor: (key, value, persist) async {
          if (key == DailyAccessRepository.pendingDailyWisdomRevealKey) {
            firstWriteStarted.complete();
            await allowFirstWrite.future;
          }
          await persist();
        },
      ),
      coordinator: PersistenceOperationCoordinator(),
    );
    final secondRepository = createRepository(
      coordinator: PersistenceOperationCoordinator(),
    );
    var selections = 0;

    final firstPrepare = firstRepository.prepareReveal(
      selectWisdom: () => 'Isolated ${++selections}',
      preparedAt: now,
      now: now,
    );
    await firstWriteStarted.future;

    final secondPrepare = await secondRepository.prepareReveal(
      selectWisdom: () => 'Isolated ${++selections}',
      preparedAt: now,
      now: now,
    );

    allowFirstWrite.complete();
    final firstResult = await firstPrepare;

    expect(firstResult.text, 'Isolated 1');
    expect(secondPrepare.text, 'Isolated 2');
    expect(selections, 2);
  });

  test('concurrent finalize callers return the same authoritative record',
      () async {
    final repository = createRepository();
    final boundary = now.add(const Duration(seconds: 5));
    await repository.prepareReveal(
      selectWisdom: () => 'Finalized once',
      preparedAt: now,
      now: now,
    );

    final records = await Future.wait([
      repository.finalizeVisualReveal(
        text: 'Finalized once',
        revealBoundary: boundary,
        now: boundary,
      ),
      repository.finalizeVisualReveal(
        text: 'Finalized once',
        revealBoundary: boundary,
        now: boundary,
      ),
    ]);

    expect(records.first.text, 'Finalized once');
    expect(records.last.revealedAt, boundary);
    await Future<void>.delayed(Duration.zero);
    await repository.waitForIdle();
    expect(await repository.loadPendingDailyWisdomReveal(), isNull);
  });

  test('different-text concurrent finalize is rejected', () async {
    var dailyWriteStarted = false;
    final adapter = InterceptingStoragePreferencesAdapter(
      setStringInterceptor: (key, value, persist) {
        if (key == DailyAccessRepository.dailyWisdomAccessKey) {
          dailyWriteStarted = true;
          return Completer<void>().future;
        }

        return persist();
      },
    );
    final repository = createRepository(adapter: adapter);
    await repository.prepareReveal(
      selectWisdom: () => 'Original',
      preparedAt: now,
      now: now,
    );

    final first = repository.finalizeVisualReveal(
      text: 'Original',
      revealBoundary: now.add(const Duration(seconds: 5)),
      now: now,
    );
    await Future<void>.delayed(Duration.zero);

    expect(dailyWriteStarted, isTrue);
    expect(first, isA<Future<DailyWisdomRecord>>());
    await expectLater(
      repository.finalizeVisualReveal(
        text: 'Different',
        revealBoundary: now.add(const Duration(seconds: 6)),
        now: now,
      ),
      throwsStateError,
    );
  });

  test('cleanup failure does not invalidate authoritative record', () async {
    final repository = createRepository(
      pendingRevealRemover: (prefs, key) async {
        throw StateError('cleanup failed');
      },
    );
    final boundary = now.add(const Duration(seconds: 5));
    await repository.prepareReveal(
      selectWisdom: () => 'Cleanup failure survives',
      preparedAt: now,
      now: now,
    );

    final record = await repository.finalizeVisualReveal(
      text: 'Cleanup failure survives',
      revealBoundary: boundary,
      now: boundary,
    );

    expect(record.text, 'Cleanup failure survives');
    expect(await repository.loadDailyWisdomRecord(), isNotNull);
  });

  test('exact 24-hour invariant remains', () async {
    final repository = createRepository();
    final boundary = now.add(const Duration(milliseconds: 123));
    await repository.prepareReveal(
      selectWisdom: () => 'Exact boundary',
      preparedAt: now,
      now: now,
    );

    final record = await repository.finalizeVisualReveal(
      text: 'Exact boundary',
      revealBoundary: boundary,
      now: boundary,
    );

    expect(record.unlockAt.difference(record.revealedAt),
        DailyWisdomRecord.lockDuration);
  });

  test('process reconstruction uses persisted state correctly', () async {
    final repository = createRepository();
    final boundary = now.add(const Duration(seconds: 5));
    await repository.prepareReveal(
      selectWisdom: () => 'Reconstructed wisdom',
      preparedAt: now,
      now: now,
    );
    await repository.finalizeVisualReveal(
      text: 'Reconstructed wisdom',
      revealBoundary: boundary,
      now: boundary,
    );

    final reconstructed = createRepository();
    final snapshot = await reconstructed.snapshot(
      now: boundary.add(const Duration(minutes: 1)),
    );

    expect(snapshot, isA<DailyAccessLocked>());
    expect((snapshot as DailyAccessLocked).record.text, 'Reconstructed wisdom');
  });

  // ---------------------------------------------------------------------
  // Build 26 Phase 2: revealId identity and Build 25 backfill.
  // ---------------------------------------------------------------------

  // Requirement 1: a genuinely new authoritative reveal receives a
  // non-empty, valid UUID revealId.
  test('new authoritative reveal receives a valid non-empty UUID revealId',
      () async {
    final repository = createRepository();
    await repository.prepareReveal(
      selectWisdom: () => 'RevealId wisdom',
      preparedAt: now,
      now: now,
    );

    final record = await repository.finalizeVisualReveal(
      text: 'RevealId wisdom',
      revealBoundary: now,
      now: now,
    );

    expect(record.revealId, isNotNull);
    expect(record.revealId, isNotEmpty);
    expect(record.revealId, matches(_uuidV4Pattern));
  });

  // Requirement 2: the same authoritative record retains its revealId
  // across a reload from persistence.
  test('authoritative record retains the same revealId after reload', () async {
    final repository = createRepository();
    await repository.prepareReveal(
      selectWisdom: () => 'Stable identity wisdom',
      preparedAt: now,
      now: now,
    );
    final finalized = await repository.finalizeVisualReveal(
      text: 'Stable identity wisdom',
      revealBoundary: now,
      now: now,
    );

    final reloaded = await repository.loadDailyWisdomRecord();

    expect(reloaded, isNotNull);
    expect(reloaded!.revealId, finalized.revealId);
  });

  // Requirement 3 and 17: two genuinely separate reveals receive different
  // revealIds even when their wisdomText is identical, and identity is
  // never derived from the text itself.
  test('two separate reveals with identical text receive different revealIds',
      () async {
    final repository = createRepository();
    await repository.prepareReveal(
      selectWisdom: () => 'Repeated wisdom',
      preparedAt: now,
      now: now,
    );
    final first = await repository.finalizeVisualReveal(
      text: 'Repeated wisdom',
      revealBoundary: now,
      now: now,
    );

    final nextWindow = now.add(
      DailyWisdomRecord.lockDuration + const Duration(seconds: 1),
    );
    await repository.prepareReveal(
      selectWisdom: () => 'Repeated wisdom',
      preparedAt: nextWindow,
      now: nextWindow,
    );
    final second = await repository.finalizeVisualReveal(
      text: 'Repeated wisdom',
      revealBoundary: nextWindow,
      now: nextWindow,
    );

    expect(first.text, second.text);
    expect(first.revealId, isNotNull);
    expect(second.revealId, isNotNull);
    expect(first.revealId, isNot(second.revealId));
    expect(first.revealId, isNot(first.text));
  });

  // Requirements 4, 5, 6, 7, 8: an existing Build 25 record without a
  // revealId is backfilled exactly once, with wisdom text, revealedAt,
  // unlockAt, and the 24-hour lock window all preserved exactly.
  test(
      'Build 25 record without revealId is backfilled once with all fields '
      'preserved', () async {
    final repository = createRepository();
    final legacyRecord = DailyWisdomRecord(
      text: 'Build 25 wisdom',
      revealedAt: now,
      unlockAt: now.add(DailyWisdomRecord.lockDuration),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      DailyAccessRepository.dailyWisdomAccessKey,
      legacyRecord.encode(),
    );

    await repository.backfillRevealIdIfNeeded();
    final firstBackfill = await repository.loadDailyWisdomRecord();

    expect(firstBackfill, isNotNull);
    expect(firstBackfill!.revealId, isNotNull);
    expect(firstBackfill.revealId, matches(_uuidV4Pattern));
    expect(firstBackfill.text, legacyRecord.text);
    expect(
      firstBackfill.revealedAt.millisecondsSinceEpoch,
      legacyRecord.revealedAt.millisecondsSinceEpoch,
    );
    expect(
      firstBackfill.unlockAt.millisecondsSinceEpoch,
      legacyRecord.unlockAt.millisecondsSinceEpoch,
    );
    expect(
      firstBackfill.unlockAt.difference(firstBackfill.revealedAt),
      DailyWisdomRecord.lockDuration,
    );

    // Idempotent: calling backfill again must not regenerate the id.
    await repository.backfillRevealIdIfNeeded();
    final secondBackfill = await repository.loadDailyWisdomRecord();
    expect(secondBackfill!.revealId, firstBackfill.revealId);
  });

  // An already-Build-26 record (revealId already present) must be left
  // completely untouched by backfill: exact revealId and every other
  // field must survive unchanged, and no rewrite should occur at all.
  test(
      'backfill on an existing Build 26 record is a no-op preserving its '
      'exact revealId and fields', () async {
    final repository = createRepository();
    const existingRevealId = '123e4567-e89b-42d3-a456-426614174000';
    final build26Record = DailyWisdomRecord(
      text: 'Already Build 26 wisdom',
      revealedAt: now,
      unlockAt: now.add(DailyWisdomRecord.lockDuration),
      revealId: existingRevealId,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      DailyAccessRepository.dailyWisdomAccessKey,
      build26Record.encode(),
    );

    await repository.backfillRevealIdIfNeeded();
    final afterBackfill = await repository.loadDailyWisdomRecord();

    expect(afterBackfill, isNotNull);
    expect(afterBackfill!.revealId, existingRevealId);
    expect(afterBackfill.text, build26Record.text);
    expect(
      afterBackfill.revealedAt.millisecondsSinceEpoch,
      build26Record.revealedAt.millisecondsSinceEpoch,
    );
    expect(
      afterBackfill.unlockAt.millisecondsSinceEpoch,
      build26Record.unlockAt.millisecondsSinceEpoch,
    );
    // No rewrite occurred at all: the persisted JSON is byte-for-byte
    // identical to what was seeded.
    expect(
      prefs.getString(DailyAccessRepository.dailyWisdomAccessKey),
      build26Record.encode(),
    );
  });

  // Requirement 9: backfill survives a restart (a fresh repository
  // instance over the same persisted storage) and reuses the already
  // persisted revealId rather than generating another.
  test('backfill survives restart and reuses the persisted revealId', () async {
    final legacyRecord = DailyWisdomRecord(
      text: 'Restart survives wisdom',
      revealedAt: now,
      unlockAt: now.add(DailyWisdomRecord.lockDuration),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      DailyAccessRepository.dailyWisdomAccessKey,
      legacyRecord.encode(),
    );

    final firstProcess = createRepository();
    await firstProcess.backfillRevealIdIfNeeded();
    final afterFirstProcess = await firstProcess.loadDailyWisdomRecord();

    final secondProcess = createRepository();
    await secondProcess.backfillRevealIdIfNeeded();
    final afterSecondProcess = await secondProcess.loadDailyWisdomRecord();

    expect(afterFirstProcess!.revealId, isNotNull);
    expect(afterSecondProcess!.revealId, afterFirstProcess.revealId);
  });

  // Requirement 10: a failed backfill write must not corrupt or invalidate
  // the previously valid Build 25 record, and a later retry must succeed.
  test(
      'write failure during backfill preserves the prior valid record and '
      'allows retry', () async {
    final legacyRecord = DailyWisdomRecord(
      text: 'Retry survives wisdom',
      revealedAt: now,
      unlockAt: now.add(DailyWisdomRecord.lockDuration),
    );
    var shouldFailWrite = true;
    final adapter = InterceptingStoragePreferencesAdapter(
      setStringInterceptor: (key, value, persist) async {
        if (key == DailyAccessRepository.dailyWisdomAccessKey &&
            shouldFailWrite) {
          throw StateError('simulated write failure');
        }
        await persist();
      },
    );
    final repository = createRepository(adapter: adapter);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      DailyAccessRepository.dailyWisdomAccessKey,
      legacyRecord.encode(),
    );

    await repository.backfillRevealIdIfNeeded();
    final afterFailedAttempt = await repository.loadDailyWisdomRecord();

    expect(afterFailedAttempt, isNotNull);
    expect(afterFailedAttempt!.revealId, isNull);
    expect(afterFailedAttempt.text, 'Retry survives wisdom');
    expect(
      afterFailedAttempt.revealedAt.millisecondsSinceEpoch,
      now.millisecondsSinceEpoch,
    );

    shouldFailWrite = false;
    await repository.backfillRevealIdIfNeeded();
    final afterRetry = await repository.loadDailyWisdomRecord();

    expect(afterRetry!.revealId, isNotNull);
    expect(afterRetry.text, 'Retry survives wisdom');
  });

  // Requirement 11: a failed read-back verification must not silently
  // accept a mismatched backfill; it must roll back to the prior valid
  // record instead.
  test(
      'failed read-back verification rolls back rather than accepting an '
      'invalid backfill', () async {
    final legacyRecord = DailyWisdomRecord(
      text: 'Verification guarded wisdom',
      revealedAt: now,
      unlockAt: now.add(DailyWisdomRecord.lockDuration),
    );
    final legacyEncoded = legacyRecord.encode();
    var dailyGetCount = 0;
    final adapter = InterceptingStoragePreferencesAdapter(
      getStringInterceptor: (key, read) async {
        if (key == DailyAccessRepository.dailyWisdomAccessKey) {
          dailyGetCount++;
          if (dailyGetCount == 2) {
            // Simulate a stale/mismatched read-back immediately after the
            // backfill write (e.g. a torn or not-yet-durable write).
            return legacyEncoded;
          }
        }
        return read();
      },
    );
    final repository = createRepository(adapter: adapter);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      DailyAccessRepository.dailyWisdomAccessKey,
      legacyEncoded,
    );

    await repository.backfillRevealIdIfNeeded();

    final plainAdapter = StoragePreferencesAdapter();
    final finalEncoded = await plainAdapter.getString(
      DailyAccessRepository.dailyWisdomAccessKey,
    );
    final finalRecord = DailyWisdomRecord.decode(finalEncoded!);

    expect(finalRecord.revealId, isNull);
    expect(finalRecord.text, 'Verification guarded wisdom');
    expect(
      finalRecord.revealedAt.millisecondsSinceEpoch,
      now.millisecondsSinceEpoch,
    );
    expect(
      finalRecord.unlockAt.millisecondsSinceEpoch,
      now.add(DailyWisdomRecord.lockDuration).millisecondsSinceEpoch,
    );
  });

  // Requirement 12: if a crash occurs after the authoritative write
  // succeeded but before the deferred pending-reveal cleanup completed,
  // the next recovery must reuse the already-persisted revealId.
  test('recovery reuses the persisted revealId when cleanup did not complete',
      () async {
    final repository = createRepository();
    await repository.prepareReveal(
      selectWisdom: () => 'Crash before cleanup wisdom',
      preparedAt: now,
      now: now,
    );
    final committed = await repository.finalizeVisualReveal(
      text: 'Crash before cleanup wisdom',
      revealBoundary: now,
      now: now,
    );
    await Future<void>.delayed(Duration.zero);
    await repository.waitForIdle();

    // Simulate a crash after the authoritative write succeeded but before
    // the deferred pending-reveal cleanup ran: re-inject the pending
    // reveal payload the real flow would already have cleared.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      DailyAccessRepository.pendingDailyWisdomRevealKey,
      PendingDailyWisdomReveal(
        text: 'Crash before cleanup wisdom',
        preparedAt: now,
        confirmedRevealBoundary: now,
        phase: PendingDailyWisdomRevealPhase.revealedPendingCommit,
      ).encode(),
    );

    final recovered = await repository.recoverIncompleteReveal(
      now: now.add(const Duration(minutes: 1)),
    );

    expect(recovered, isNotNull);
    expect(recovered!.revealId, committed.revealId);
  });

  // Requirements 13 and 14: recovery promoting a revealedPendingCommit
  // pending mints exactly one revealId at the promotion commit, and
  // replaying/recovering the already-committed reveal never creates a
  // second one.
  test(
      'recovery promotion mints one revealId and later recovery calls reuse '
      'it', () async {
    final repository = createRepository();
    final boundary = now.add(const Duration(seconds: 5));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      DailyAccessRepository.pendingDailyWisdomRevealKey,
      PendingDailyWisdomReveal(
        text: 'Promoted wisdom',
        preparedAt: now,
        confirmedRevealBoundary: boundary,
        phase: PendingDailyWisdomRevealPhase.revealedPendingCommit,
      ).encode(),
    );

    final promoted = await repository.recoverIncompleteReveal(
      now: boundary.add(const Duration(minutes: 1)),
    );
    expect(promoted, isNotNull);
    expect(promoted!.revealId, isNotNull);

    final recoveredAgain = await repository.recoverIncompleteReveal(
      now: boundary.add(const Duration(minutes: 2)),
    );
    expect(recoveredAgain, isNotNull);
    expect(recoveredAgain!.revealId, promoted.revealId);

    final recoveredThirdTime = await repository.recoverIncompleteReveal(
      now: boundary.add(const Duration(minutes: 3)),
    );
    expect(recoveredThirdTime, isNotNull);
    expect(recoveredThirdTime!.revealId, promoted.revealId);
  });

  // Requirement 15: a missing daily_wisdom_access record still behaves as
  // ready/null exactly as before, and backfill is a safe no-op against it.
  test('backfill on a missing daily record is a no-op and access stays ready',
      () async {
    final repository = createRepository();

    await repository.backfillRevealIdIfNeeded();

    expect(await repository.loadDailyWisdomRecord(), isNull);
    final snapshot = await repository.snapshot(now: now);
    expect(snapshot, isA<DailyAccessReady>());
    expect((snapshot as DailyAccessReady).pending, isNull);
  });
}
