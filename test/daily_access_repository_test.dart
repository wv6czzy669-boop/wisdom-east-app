import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/models/daily_access_snapshot.dart';
import 'package:wisdom_app/models/daily_wisdom_record.dart';
import 'package:wisdom_app/models/daily_wisdom_selection.dart';
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

  test('prepare awaits one asynchronous identity selection only when ready',
      () async {
    final repository = createRepository();
    var selections = 0;

    final first = await repository.prepareReveal(
      selectWisdom: () async => 'Legacy fallback',
      selectWisdomWithIdentity: () async {
        selections++;
        await Future<void>.delayed(Duration.zero);
        return DailyWisdomSelection(
          text: 'Persisted selector wisdom',
          wisdomId: 'east_wisdom_0301',
        );
      },
      preparedAt: now,
      now: now,
    );
    final recoveredPending = await repository.prepareReveal(
      selectWisdom: () => throw StateError('must not select again'),
      selectWisdomWithIdentity: () => throw StateError('must not select again'),
      preparedAt: now,
      now: now,
    );

    expect(selections, 1);
    expect(first.text, 'Persisted selector wisdom');
    expect(first.wisdomId, 'east_wisdom_0301');
    expect(recoveredPending.text, first.text);
    expect(recoveredPending.wisdomId, first.wisdomId);
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

  group('PreparedDailyAccess revealId/revealedAt propagation (Phase 3D-B)', () {
    test('a genuinely fresh prepared reveal has null revealId/revealedAt',
        () async {
      final repository = createRepository();

      final prepared = await repository.prepareReveal(
        selectWisdom: () => 'Fresh wisdom',
        preparedAt: now,
        now: now,
      );

      expect(prepared.hasAuthoritativeRecord, isFalse);
      expect(prepared.revealId, isNull);
      expect(prepared.revealedAt, isNull);
    });

    test(
        'preparing against an already-locked authoritative record carries '
        'its revealId/revealedAt', () async {
      final repository = createRepository();
      final committed = await repository.finalizeVisualReveal(
        text: (await repository.prepareReveal(
          selectWisdom: () => 'Locked wisdom',
          preparedAt: now,
          now: now,
        ))
            .text,
        revealBoundary: now,
        now: now,
      );
      expect(committed.revealId, isNotNull);

      final prepared = await repository.prepareReveal(
        selectWisdom: () => 'Should not be selected',
        preparedAt: now.add(const Duration(minutes: 1)),
        now: now.add(const Duration(minutes: 1)),
      );

      expect(prepared.hasAuthoritativeRecord, isTrue);
      expect(prepared.revealId, committed.revealId);
      expect(
        prepared.revealedAt!.millisecondsSinceEpoch,
        committed.revealedAt.millisecondsSinceEpoch,
      );
    });

    test(
        'preparing against a locked record predating backfill carries a '
        'null revealId but a non-null revealedAt', () async {
      final repository = createRepository();
      final legacyRecord = DailyWisdomRecord(
        text: 'Pre-backfill wisdom',
        revealedAt: now,
        unlockAt: now.add(DailyWisdomRecord.lockDuration),
      );
      await repository.saveDailyWisdomRecord(legacyRecord);

      final prepared = await repository.prepareReveal(
        selectWisdom: () => 'Should not be selected',
        preparedAt: now.add(const Duration(minutes: 1)),
        now: now.add(const Duration(minutes: 1)),
      );

      expect(prepared.hasAuthoritativeRecord, isTrue);
      expect(prepared.revealId, isNull);
      expect(
        prepared.revealedAt!.millisecondsSinceEpoch,
        legacyRecord.revealedAt.millisecondsSinceEpoch,
      );
    });

    test(
        're-reading an already-locked record via prepareReveal mints no '
        'additional UUID (the returned revealId is identical across '
        'repeated calls)', () async {
      final repository = createRepository();
      final committed = await repository.finalizeVisualReveal(
        text: (await repository.prepareReveal(
          selectWisdom: () => 'Locked wisdom',
          preparedAt: now,
          now: now,
        ))
            .text,
        revealBoundary: now,
        now: now,
      );

      final first = await repository.prepareReveal(
        selectWisdom: () => 'Should not be selected',
        preparedAt: now.add(const Duration(minutes: 1)),
        now: now.add(const Duration(minutes: 1)),
      );
      final second = await repository.prepareReveal(
        selectWisdom: () => 'Should not be selected',
        preparedAt: now.add(const Duration(minutes: 2)),
        now: now.add(const Duration(minutes: 2)),
      );

      expect(first.revealId, committed.revealId);
      expect(second.revealId, committed.revealId);
    });

    test(
        'constructing a non-authoritative PreparedDailyAccess with a '
        'non-null revealId throws', () {
      expect(
        () => PreparedDailyAccess(
          text: 'x',
          hasAuthoritativeRecord: false,
          revealId: '3f2e1a4c-9b7d-4a6e-8c1f-0d2b5e7a9c11',
        ),
        throwsArgumentError,
      );
    });

    test(
        'constructing a non-authoritative PreparedDailyAccess with a '
        'non-null revealedAt throws', () {
      expect(
        () => PreparedDailyAccess(
          text: 'x',
          hasAuthoritativeRecord: false,
          revealedAt: now,
        ),
        throwsArgumentError,
      );
    });

    test(
        'constructing an authoritative PreparedDailyAccess with a null '
        'revealedAt throws', () {
      expect(
        () => PreparedDailyAccess(
          text: 'x',
          hasAuthoritativeRecord: true,
        ),
        throwsArgumentError,
      );
    });

    test(
        'constructing an authoritative PreparedDailyAccess with a null '
        'revealId but non-null revealedAt is valid (pre-backfill '
        'compatibility)', () {
      final prepared = PreparedDailyAccess(
        text: 'x',
        hasAuthoritativeRecord: true,
        revealedAt: now,
      );

      expect(prepared.revealId, isNull);
      expect(prepared.revealedAt, now);
    });
  });

  group(
      'Build 26 Phase 3D-E (safety-gap correction, round 3): '
      'reconcileRevealIdForOccurrence', () {
    const resolvedLegacyRevealId = '11111111-1111-4111-8111-111111111111';

    // Case A: a still-missing revealId adopts the resolved migrated
    // revealId directly -- it must never pass through an intermediate,
    // unrelated v4 first (i.e. no separate ordinary backfill ever runs when
    // a candidate was actually resolved).
    test(
        'Case A: missing revealId adopts the resolved migrated revealId '
        'directly, never an intermediate unrelated v4', () async {
      final repository = createRepository();
      final record = DailyWisdomRecord(
        text: 'Migrated occurrence',
        revealedAt: now,
        unlockAt: now.add(DailyWisdomRecord.lockDuration),
      );
      await repository.saveDailyWisdomRecord(record);

      await repository.reconcileRevealIdForOccurrence(
        expectedText: record.text,
        expectedRevealedAt: record.revealedAt,
        expectedUnlockAt: record.unlockAt,
        resolvedLegacyRevealId: resolvedLegacyRevealId,
      );

      final corrected = await repository.loadDailyWisdomRecord();
      expect(corrected!.revealId, resolvedLegacyRevealId);
      expect(corrected.text, record.text);
      expect(
        corrected.revealedAt.millisecondsSinceEpoch,
        record.revealedAt.millisecondsSinceEpoch,
      );
      expect(
        corrected.unlockAt.millisecondsSinceEpoch,
        record.unlockAt.millisecondsSinceEpoch,
      );
    });

    // Case B: a physical device already backfilled an unrelated Build 26 v4
    // during a prior debug launch, before a migrated candidate could ever be
    // resolved. The correction must still adopt the resolved migrated
    // revealId, replacing the unrelated v4 -- this is the exact gap the
    // physical-device evidence proved.
    test(
        'Case B: an already-backfilled unrelated v4 is replaced by the '
        'resolved migrated revealId', () async {
      final repository = createRepository();
      const priorUnrelatedV4 = '22222222-2222-4222-8222-222222222222';
      final record = DailyWisdomRecord(
        text: 'Migrated occurrence',
        revealedAt: now,
        unlockAt: now.add(DailyWisdomRecord.lockDuration),
        revealId: priorUnrelatedV4,
      );
      await repository.saveDailyWisdomRecord(record);

      await repository.reconcileRevealIdForOccurrence(
        expectedText: record.text,
        expectedRevealedAt: record.revealedAt,
        expectedUnlockAt: record.unlockAt,
        resolvedLegacyRevealId: resolvedLegacyRevealId,
      );

      final corrected = await repository.loadDailyWisdomRecord();
      expect(corrected!.revealId, resolvedLegacyRevealId);
      expect(corrected.revealId, isNot(priorUnrelatedV4));
      expect(corrected.text, record.text);
    });

    // Case C: the persisted revealId already equals the resolved migrated
    // revealId -- a pure no-op, and no write should occur at all.
    test(
        'Case C: already-consistent revealId is left untouched and no '
        'write occurs', () async {
      var writeCount = 0;
      final adapter = InterceptingStoragePreferencesAdapter(
        setStringInterceptor: (key, value, persist) async {
          if (key == DailyAccessRepository.dailyWisdomAccessKey) {
            writeCount++;
          }
          await persist();
        },
      );
      final repository = createRepository(adapter: adapter);
      final record = DailyWisdomRecord(
        text: 'Already consistent occurrence',
        revealedAt: now,
        unlockAt: now.add(DailyWisdomRecord.lockDuration),
        revealId: resolvedLegacyRevealId,
      );
      await repository.saveDailyWisdomRecord(record);
      writeCount = 0;

      await repository.reconcileRevealIdForOccurrence(
        expectedText: record.text,
        expectedRevealedAt: record.revealedAt,
        expectedUnlockAt: record.unlockAt,
        resolvedLegacyRevealId: resolvedLegacyRevealId,
      );

      expect(writeCount, 0);
      final unchanged = await repository.loadDailyWisdomRecord();
      expect(unchanged!.revealId, resolvedLegacyRevealId);
    });

    // Case D (missing): no safe migrated candidate was found and the
    // revealId is still missing -- falls back to the ordinary v4 backfill,
    // exactly as an unrelated, genuinely new Build 26 reveal would.
    test(
        'Case D (missing): no candidate and missing revealId falls back to '
        'an ordinary v4 backfill', () async {
      final repository = createRepository();
      final record = DailyWisdomRecord(
        text: 'Genuinely new occurrence',
        revealedAt: now,
        unlockAt: now.add(DailyWisdomRecord.lockDuration),
      );
      await repository.saveDailyWisdomRecord(record);

      await repository.reconcileRevealIdForOccurrence(
        expectedText: record.text,
        expectedRevealedAt: record.revealedAt,
        expectedUnlockAt: record.unlockAt,
        resolvedLegacyRevealId: null,
      );

      final corrected = await repository.loadDailyWisdomRecord();
      expect(corrected!.revealId, isNotNull);
      expect(corrected.revealId, matches(_uuidV4Pattern));
    });

    // Case D (existing): no safe migrated candidate and the record already
    // has a revealId -- left unchanged. Text/date are never used as a
    // runtime membership check on their own.
    test(
        'Case D (existing): no candidate and an existing revealId is left '
        'unchanged', () async {
      final repository = createRepository();
      const existingRevealId = '33333333-3333-4333-8333-333333333333';
      final record = DailyWisdomRecord(
        text: 'Ordinary occurrence',
        revealedAt: now,
        unlockAt: now.add(DailyWisdomRecord.lockDuration),
        revealId: existingRevealId,
      );
      await repository.saveDailyWisdomRecord(record);

      await repository.reconcileRevealIdForOccurrence(
        expectedText: record.text,
        expectedRevealedAt: record.revealedAt,
        expectedUnlockAt: record.unlockAt,
        resolvedLegacyRevealId: null,
      );

      final unchanged = await repository.loadDailyWisdomRecord();
      expect(unchanged!.revealId, existingRevealId);
    });

    // Atomic occurrence re-check: if daily access has moved on to a
    // different occurrence since the caller resolved a candidate (a new
    // reveal committed, or the record was cleared), the correction must
    // never be applied to the new, unrelated occurrence.
    test(
        'a resolved candidate for a stale occurrence is never applied to a '
        'different, currently-persisted occurrence', () async {
      final repository = createRepository();
      final staleRecord = DailyWisdomRecord(
        text: 'Stale occurrence text',
        revealedAt: now,
        unlockAt: now.add(DailyWisdomRecord.lockDuration),
      );
      final currentRecord = DailyWisdomRecord(
        text: 'Different, currently active occurrence',
        revealedAt: now.add(DailyWisdomRecord.lockDuration),
        unlockAt: now
            .add(DailyWisdomRecord.lockDuration)
            .add(DailyWisdomRecord.lockDuration),
      );
      await repository.saveDailyWisdomRecord(currentRecord);

      await repository.reconcileRevealIdForOccurrence(
        expectedText: staleRecord.text,
        expectedRevealedAt: staleRecord.revealedAt,
        expectedUnlockAt: staleRecord.unlockAt,
        resolvedLegacyRevealId: resolvedLegacyRevealId,
      );

      final unchanged = await repository.loadDailyWisdomRecord();
      expect(unchanged!.revealId, isNull);
      expect(unchanged.text, currentRecord.text);
    });

    // A missing daily record entirely (e.g. cleared or never committed) is
    // a safe no-op, mirroring backfillRevealIdIfNeeded's own precondition.
    test('reconcile against a missing daily record is a safe no-op', () async {
      final repository = createRepository();

      await repository.reconcileRevealIdForOccurrence(
        expectedText: 'Nothing persisted',
        expectedRevealedAt: now,
        expectedUnlockAt: now.add(DailyWisdomRecord.lockDuration),
        resolvedLegacyRevealId: resolvedLegacyRevealId,
      );

      expect(await repository.loadDailyWisdomRecord(), isNull);
    });

    // Write-failure safety: a failed adoption write must never corrupt or
    // invalidate the previously valid record, mirroring the existing
    // backfill write-failure guarantee -- both now share the same
    // underlying write/verify/revert primitive.
    //
    // Fixture defect (round 5 correction): this test previously armed
    // `shouldFailWrite = true` *before* seeding via
    // `repository.saveDailyWisdomRecord(record)` -- which itself performs a
    // `setString` for the exact same key the interceptor watches. That
    // seed write was the one that actually threw
    // (`Bad state: simulated write failure`, confirmed on real `flutter
    // test`), never the intended reconciliation/adoption write; the test
    // never reached the code path it was written to exercise. Seeding is
    // now done through the adapter with the failure disarmed, and the
    // failure is armed for exactly the next `setString` call only (via
    // `failNextWrite`, auto-disarmed the instant it fires) -- so it is
    // guaranteed to hit the reconciliation write specifically, however many
    // legitimate writes setup performs first.
    test(
        'a failed write during adoption preserves the prior valid record '
        'and allows retry', () async {
      var failNextWrite = false;
      var interceptedWriteCount = 0;
      var failureCount = 0;
      final adapter = InterceptingStoragePreferencesAdapter(
        setStringInterceptor: (key, value, persist) async {
          if (key == DailyAccessRepository.dailyWisdomAccessKey) {
            interceptedWriteCount++;
            if (failNextWrite) {
              failNextWrite = false;
              failureCount++;
              throw StateError('simulated write failure');
            }
          }
          await persist();
        },
      );
      final repository = createRepository(adapter: adapter);
      final record = DailyWisdomRecord(
        text: 'Retry adoption wisdom',
        revealedAt: now,
        unlockAt: now.add(DailyWisdomRecord.lockDuration),
      );

      // 1/2: seed the prior valid record successfully (failure is not yet
      // armed) and confirm it is persisted with the existing v4 revealId
      // -- here, no revealId at all yet, exactly the pre-backfill shape.
      await repository.saveDailyWisdomRecord(record);
      final seeded = await repository.loadDailyWisdomRecord();
      expect(seeded, isNotNull);
      expect(seeded!.revealId, isNull);
      expect(seeded.text, record.text);
      final writeCountAfterSeed = interceptedWriteCount;

      // 3/4: arm the interceptor only now, for exactly the next setString
      // call -- the one `reconcileRevealIdForOccurrence` is about to make.
      failNextWrite = true;

      final failedOutcome = await repository.reconcileRevealIdForOccurrence(
        expectedText: record.text,
        expectedRevealedAt: record.revealedAt,
        expectedUnlockAt: record.unlockAt,
        resolvedLegacyRevealId: resolvedLegacyRevealId,
      );

      // The returned outcome distinguishes this from every other silent
      // case (already-consistent, occurrence-changed, applied, ...).
      expect(
        failedOutcome,
        RevealIdReconciliationOutcome.storageWriteFailed,
      );
      // 5: the arm auto-disarmed after firing exactly once.
      expect(failNextWrite, isFalse);
      expect(interceptedWriteCount, writeCountAfterSeed + 1);

      // 6: the previous v4 (here, pre-backfill null) record remains
      // readable and completely unchanged -- the failed write never
      // touched it, so there is nothing to revert.
      final afterFailedAttempt = await repository.loadDailyWisdomRecord();
      expect(afterFailedAttempt, isNotNull);
      expect(afterFailedAttempt!.revealId, isNull);
      expect(afterFailedAttempt.text, record.text);
      expect(
        afterFailedAttempt.revealedAt.millisecondsSinceEpoch,
        record.revealedAt.millisecondsSinceEpoch,
      );
      expect(
        afterFailedAttempt.unlockAt.millisecondsSinceEpoch,
        record.unlockAt.millisecondsSinceEpoch,
      );

      // 7/8: call reconciliation again -- the failure was single-shot and
      // is no longer armed, so this retry must succeed and persist the
      // resolved v5.
      final retryOutcome = await repository.reconcileRevealIdForOccurrence(
        expectedText: record.text,
        expectedRevealedAt: record.revealedAt,
        expectedUnlockAt: record.unlockAt,
        resolvedLegacyRevealId: resolvedLegacyRevealId,
      );

      expect(retryOutcome, RevealIdReconciliationOutcome.applied);
      final afterRetry = await repository.loadDailyWisdomRecord();
      expect(afterRetry!.revealId, resolvedLegacyRevealId);
      // 9: text/revealedAt/unlockAt remain unchanged by the retry too.
      expect(afterRetry.text, record.text);
      expect(
        afterRetry.revealedAt.millisecondsSinceEpoch,
        record.revealedAt.millisecondsSinceEpoch,
      );
      expect(
        afterRetry.unlockAt.millisecondsSinceEpoch,
        record.unlockAt.millisecondsSinceEpoch,
      );

      // Repository reload (a fresh instance over the same persisted
      // storage) also returns the v5.
      final reloaded = createRepository(adapter: adapter);
      final reloadedRecord = await reloaded.loadDailyWisdomRecord();
      expect(reloadedRecord!.revealId, resolvedLegacyRevealId);

      // Exactly one simulated failure occurred in this entire test, and no
      // revert write was ever required for it: the failed write never
      // persisted anything (see the write/read-back-verify/revert
      // primitive's own `storageWriteFailed` branch, which returns before
      // any revert attempt -- a revert is only ever needed after a write
      // that *did* persist but read back wrong).
      expect(failureCount, 1);
      expect(interceptedWriteCount, writeCountAfterSeed + 2);
    });
  });

  group(
      'Build 26 Phase 3D-E (safety-gap correction, round 4): genuine '
      'canonical UUID v5 reconciliation (the exact real-device evidence)', () {
    // The exact two identifiers from the reported Mac evidence: the
    // existing, real Build 26 backfilled v4, and the real deterministic
    // migrated v5 the resolver actually returned. Every prior round-3 test
    // in the group above used a *v4-shaped* `resolvedLegacyRevealId`
    // ('11111111-1111-4111-8111-111111111111' -- version nibble '4'), which
    // incidentally satisfied `DailyWisdomRecord.decode`'s then-v4-only
    // acceptance and therefore never actually exercised a genuine v5
    // round-trip. That is precisely why those tests passed while the real
    // device failed: a real migrated revealId is always a v5, never a v4.
    const existingV4 = 'c947bbb4-f86a-4db3-87c9-ed5e718bbd98';
    const resolvedMigratedV5 = 'affbc527-29c4-5d19-b678-1bc7f9dfb7d4';

    test(
        'a genuine v5 resolved revealId replaces an existing v4, is written '
        'exactly once (never written-then-reverted), and is readable back '
        'through the repository -- the focused reproduction for the exact '
        'Mac evidence', () async {
      final setStringCalls = <String, String>{};
      var setStringCallCountForDailyKey = 0;
      final adapter = InterceptingStoragePreferencesAdapter(
        setStringInterceptor: (key, value, persist) async {
          if (key == DailyAccessRepository.dailyWisdomAccessKey) {
            setStringCallCountForDailyKey++;
            setStringCalls[key] = value;
          }
          await persist();
        },
      );
      final repository = createRepository(adapter: adapter);
      final record = DailyWisdomRecord(
        text: 'A Build 25 occurrence already Kept before the upgrade',
        revealedAt: now,
        unlockAt: now.add(DailyWisdomRecord.lockDuration),
        revealId: existingV4,
      );
      await repository.saveDailyWisdomRecord(record);
      // Reset counters/captures after the seed write above -- only the
      // reconciliation call itself is under observation.
      setStringCallCountForDailyKey = 0;
      setStringCalls.clear();

      await repository.reconcileRevealIdForOccurrence(
        expectedText: record.text,
        expectedRevealedAt: record.revealedAt,
        expectedUnlockAt: record.unlockAt,
        resolvedLegacyRevealId: resolvedMigratedV5,
      );

      // Step 3/4: inspect the raw stored string directly and decode it
      // independently of the repository's own read path, proving the v5
      // write itself was genuinely attempted and produced valid encoded
      // JSON containing the v5 value -- i.e. the write side is never the
      // failure point.
      expect(
        setStringCalls,
        isNotEmpty,
        reason: 'the write was never attempted -- setString was not called '
            'at all for the daily-access key',
      );
      final rawEncoded =
          setStringCalls[DailyAccessRepository.dailyWisdomAccessKey];
      final decodedFromRawWrite = DailyWisdomRecord.decode(rawEncoded!);
      expect(
        decodedFromRawWrite.revealId,
        resolvedMigratedV5,
        reason: 'the raw string actually written to storage must already '
            'contain the resolved v5 revealId',
      );

      // Step 5/6: load through the repository's own public path. Exactly
      // one setString call for this key proves the write was accepted and
      // kept -- never "written then reverted" (which would show a second,
      // corrective setString call restoring the prior v4 value).
      final corrected = await repository.loadDailyWisdomRecord();
      expect(
        setStringCallCountForDailyKey,
        1,
        reason: 'exactly one write must occur: written-then-reverted would '
            'show a second setString call restoring the prior v4 value',
      );
      expect(
        corrected!.revealId,
        resolvedMigratedV5,
        reason: 'loading through the repository must return the same v5 '
            'value that was actually written and decoded independently '
            'above -- this is the exact assertion that failed on the '
            'physical device/Mac before this fix',
      );
      expect(corrected.revealId, isNot(existingV4));

      // Step 7: text/revealedAt/unlockAt remain exactly unchanged.
      expect(corrected.text, record.text);
      expect(
        corrected.revealedAt.millisecondsSinceEpoch,
        record.revealedAt.millisecondsSinceEpoch,
      );
      expect(
        corrected.unlockAt.millisecondsSinceEpoch,
        record.unlockAt.millisecondsSinceEpoch,
      );
    });

    test(
        'the v5 correction survives a raw SharedPreferences wire round-trip '
        '(decode of the exact persisted string, independent of the '
        'repository)', () async {
      final repository = createRepository();
      final record = DailyWisdomRecord(
        text: 'Wire round-trip occurrence',
        revealedAt: now,
        unlockAt: now.add(DailyWisdomRecord.lockDuration),
        revealId: existingV4,
      );
      await repository.saveDailyWisdomRecord(record);

      await repository.reconcileRevealIdForOccurrence(
        expectedText: record.text,
        expectedRevealedAt: record.revealedAt,
        expectedUnlockAt: record.unlockAt,
        resolvedLegacyRevealId: resolvedMigratedV5,
      );

      final prefs = await SharedPreferences.getInstance();
      final rawString =
          prefs.getString(DailyAccessRepository.dailyWisdomAccessKey);
      final decodedDirectly = DailyWisdomRecord.decode(rawString!);
      expect(decodedDirectly.revealId, resolvedMigratedV5);
      expect(decodedDirectly.text, record.text);
    });

    test(
        'the v5 correction survives a full repository reload (a fresh '
        'DailyAccessRepository instance over the same persisted storage)',
        () async {
      final repository = createRepository();
      final record = DailyWisdomRecord(
        text: 'Reload survives occurrence',
        revealedAt: now,
        unlockAt: now.add(DailyWisdomRecord.lockDuration),
        revealId: existingV4,
      );
      await repository.saveDailyWisdomRecord(record);
      await repository.reconcileRevealIdForOccurrence(
        expectedText: record.text,
        expectedRevealedAt: record.revealedAt,
        expectedUnlockAt: record.unlockAt,
        resolvedLegacyRevealId: resolvedMigratedV5,
      );

      final reloaded = createRepository();
      final reloadedRecord = await reloaded.loadDailyWisdomRecord();
      expect(reloadedRecord!.revealId, resolvedMigratedV5);
    });

    test(
        'a missing revealId adopts a genuine resolved v5 directly (never an '
        'intermediate unrelated v4 first)', () async {
      final repository = createRepository();
      final record = DailyWisdomRecord(
        text: 'Missing revealId, genuine v5 candidate',
        revealedAt: now,
        unlockAt: now.add(DailyWisdomRecord.lockDuration),
      );
      await repository.saveDailyWisdomRecord(record);

      await repository.reconcileRevealIdForOccurrence(
        expectedText: record.text,
        expectedRevealedAt: record.revealedAt,
        expectedUnlockAt: record.unlockAt,
        resolvedLegacyRevealId: resolvedMigratedV5,
      );

      final corrected = await repository.loadDailyWisdomRecord();
      expect(corrected!.revealId, resolvedMigratedV5);
    });
  });

  group(
      'Build 26 Phase 3D-E (safety-gap correction, round 4): '
      'RevealIdReconciliationOutcome distinguishes every silent case', () {
    const resolvedMigratedV5 = 'affbc527-29c4-5d19-b678-1bc7f9dfb7d4';

    test('reconcileRevealIdForOccurrence returns applied on a genuine write',
        () async {
      final repository = createRepository();
      final record = DailyWisdomRecord(
        text: 'Applied occurrence',
        revealedAt: now,
        unlockAt: now.add(DailyWisdomRecord.lockDuration),
      );
      await repository.saveDailyWisdomRecord(record);

      final outcome = await repository.reconcileRevealIdForOccurrence(
        expectedText: record.text,
        expectedRevealedAt: record.revealedAt,
        expectedUnlockAt: record.unlockAt,
        resolvedLegacyRevealId: resolvedMigratedV5,
      );

      expect(outcome, RevealIdReconciliationOutcome.applied);
    });

    test(
        'reconcileRevealIdForOccurrence returns alreadyConsistent when the '
        'persisted revealId already equals the resolved value', () async {
      final repository = createRepository();
      final record = DailyWisdomRecord(
        text: 'Already consistent occurrence',
        revealedAt: now,
        unlockAt: now.add(DailyWisdomRecord.lockDuration),
        revealId: resolvedMigratedV5,
      );
      await repository.saveDailyWisdomRecord(record);

      final outcome = await repository.reconcileRevealIdForOccurrence(
        expectedText: record.text,
        expectedRevealedAt: record.revealedAt,
        expectedUnlockAt: record.unlockAt,
        resolvedLegacyRevealId: resolvedMigratedV5,
      );

      expect(outcome, RevealIdReconciliationOutcome.alreadyConsistent);
    });

    test(
        'reconcileRevealIdForOccurrence returns occurrenceChanged when the '
        'persisted record no longer matches the expected occurrence', () async {
      final repository = createRepository();
      final currentRecord = DailyWisdomRecord(
        text: 'A different, currently active occurrence',
        revealedAt: now.add(DailyWisdomRecord.lockDuration),
        unlockAt: now
            .add(DailyWisdomRecord.lockDuration)
            .add(DailyWisdomRecord.lockDuration),
      );
      await repository.saveDailyWisdomRecord(currentRecord);

      final outcome = await repository.reconcileRevealIdForOccurrence(
        expectedText: 'Stale occurrence text',
        expectedRevealedAt: now,
        expectedUnlockAt: now.add(DailyWisdomRecord.lockDuration),
        resolvedLegacyRevealId: resolvedMigratedV5,
      );

      expect(outcome, RevealIdReconciliationOutcome.occurrenceChanged);
    });

    test(
        'reconcileRevealIdForOccurrence returns noRecord when there is no '
        'persisted daily record at all', () async {
      final repository = createRepository();

      final outcome = await repository.reconcileRevealIdForOccurrence(
        expectedText: 'Nothing persisted',
        expectedRevealedAt: now,
        expectedUnlockAt: now.add(DailyWisdomRecord.lockDuration),
        resolvedLegacyRevealId: resolvedMigratedV5,
      );

      expect(outcome, RevealIdReconciliationOutcome.noRecord);
    });

    test(
        'reconcileRevealIdForOccurrence returns storageWriteFailed when the '
        'underlying write throws', () async {
      final adapter = InterceptingStoragePreferencesAdapter(
        setStringInterceptor: (key, value, persist) async {
          if (key == DailyAccessRepository.dailyWisdomAccessKey) {
            throw StateError('simulated write failure');
          }
          await persist();
        },
      );
      final repository = createRepository(adapter: adapter);
      final record = DailyWisdomRecord(
        text: 'Write-failure occurrence',
        revealedAt: now,
        unlockAt: now.add(DailyWisdomRecord.lockDuration),
      );
      // Seed directly through the plain, non-intercepting SharedPreferences
      // instance so the intercepted adapter (which always throws for this
      // key) is never involved in the seed write itself.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        DailyAccessRepository.dailyWisdomAccessKey,
        record.encode(),
      );

      final outcome = await repository.reconcileRevealIdForOccurrence(
        expectedText: record.text,
        expectedRevealedAt: record.revealedAt,
        expectedUnlockAt: record.unlockAt,
        resolvedLegacyRevealId: resolvedMigratedV5,
      );

      expect(outcome, RevealIdReconciliationOutcome.storageWriteFailed);
    });

    test(
        'reconcileRevealIdForOccurrence returns readBackVerificationFailed '
        'when the write succeeds but the read-back decode does not '
        'reproduce it -- the exact class of outcome the real v5 defect '
        'produced before the DailyWisdomRecord fix', () async {
      var dailyGetCount = 0;
      final record = DailyWisdomRecord(
        text: 'Read-back-mismatch occurrence',
        revealedAt: now,
        unlockAt: now.add(DailyWisdomRecord.lockDuration),
      );
      final adapter = InterceptingStoragePreferencesAdapter(
        getStringInterceptor: (key, read) async {
          if (key == DailyAccessRepository.dailyWisdomAccessKey) {
            dailyGetCount++;
            if (dailyGetCount == 2) {
              // Simulate a read-back that does not reflect the just-written
              // value (e.g. a torn write, or -- as in the real defect -- a
              // decode-side rejection of an otherwise validly-written
              // value). Returning the original, pre-correction encoding
              // here reproduces exactly that symptom without depending on
              // any particular decode rule.
              return record.encode();
            }
          }
          return read();
        },
      );
      final repository = createRepository(adapter: adapter);
      await repository.saveDailyWisdomRecord(record);
      dailyGetCount = 0;

      final outcome = await repository.reconcileRevealIdForOccurrence(
        expectedText: record.text,
        expectedRevealedAt: record.revealedAt,
        expectedUnlockAt: record.unlockAt,
        resolvedLegacyRevealId: resolvedMigratedV5,
      );

      expect(outcome, RevealIdReconciliationOutcome.readBackVerificationFailed);
      // Best-effort revert: the previously valid (no revealId) record is
      // restored, exactly like the pre-existing backfill write-failure
      // guarantee.
      final plainAdapter = StoragePreferencesAdapter();
      final finalEncoded = await plainAdapter.getString(
        DailyAccessRepository.dailyWisdomAccessKey,
      );
      final finalRecord = DailyWisdomRecord.decode(finalEncoded!);
      expect(finalRecord.revealId, isNull);
    });
  });
}
