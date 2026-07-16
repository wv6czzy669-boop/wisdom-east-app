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
}
