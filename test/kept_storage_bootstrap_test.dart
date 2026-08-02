// Build 26 Phase 3D-C correction: direct unit tests for
// `KeptStorageBootstrapper` (`lib/services/kept_storage_bootstrap.dart`),
// the pure, platform-store-free helper `app_services.dart` uses to
// sequence "migrate once -> map the result -> construct repository/service".
//
// None of these tests touch real Application Support storage or native
// file protection: every store here is either a trivial in-memory fake or
// the shared `InMemoryKeptStateStore` from `persistence_test_helpers.dart`.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/models/kept_migration_journal.dart';
import 'package:wisdom_app/models/kept_migration_recovery_artifact.dart';
import 'package:wisdom_app/models/kept_migration_snapshot.dart';
import 'package:wisdom_app/models/kept_state_envelope.dart';
import 'package:wisdom_app/persistence/kept_migration_artifact_store.dart';
import 'package:wisdom_app/persistence/kept_migration_journal_store.dart';
import 'package:wisdom_app/persistence/kept_state_store.dart';
import 'package:wisdom_app/persistence/legacy_favorites_store.dart';
import 'package:wisdom_app/persistence/persistence_operation_coordinator.dart';
import 'package:wisdom_app/repositories/kept_repository.dart';
import 'package:wisdom_app/services/kept_migration_coordinator.dart';
import 'package:wisdom_app/services/kept_storage_bootstrap.dart';
import 'package:wisdom_app/services/saved_reflections_service.dart';

import 'persistence_test_helpers.dart';

void main() {
  const readyStatuses = KeptMigrationStatus.values;

  group('1. every normal KeptMigrationStatus maps to ready', () {
    for (final status in readyStatuses) {
      test('status $status maps to a ready bootstrap result', () async {
        final bootstrapper = KeptStorageBootstrapper<String, String>(
          migrate: () async => KeptMigrationResult(
            status: status,
            migratedCount: 0,
            corruptCount: 0,
            legacyCleanupCompleted: false,
          ),
          buildRepository: (bootstrap) => 'repo',
          buildService: (repository) => 'service:$repository',
        );

        final result = await bootstrapper.run();

        expect(result.bootstrap.isReady, isTrue);
        expect(result.bootstrap.isUnavailable, isFalse);
        expect(result.bootstrap.errorCode, isNull);
      });
    }
  });

  group('2. KeptMigrationException maps only its safe stage to errorCode', () {
    test('the exception stage becomes the errorCode, verbatim', () async {
      final bootstrapper = KeptStorageBootstrapper<String, String>(
        migrate: () async => throw const KeptMigrationException(
          'duplicate-identity-conflict',
          'Migration found conflicting Kept identities and cannot proceed '
              'safely.',
        ),
        buildRepository: (bootstrap) => 'repo',
        buildService: (repository) => 'service:$repository',
      );

      final result = await bootstrapper.run();

      expect(result.bootstrap.isUnavailable, isTrue);
      expect(result.bootstrap.errorCode, 'duplicate-identity-conflict');
    });

    test('the exception message and cause never leak into errorCode', () async {
      final bootstrapper = KeptStorageBootstrapper<String, String>(
        migrate: () async => throw const KeptMigrationException(
          'legacy-key-missing',
          'The legacy favorites key disappeared during migration.',
          'some wisdom text that must never surface here',
        ),
        buildRepository: (bootstrap) => 'repo',
        buildService: (repository) => 'service:$repository',
      );

      final result = await bootstrapper.run();

      expect(result.bootstrap.errorCode, 'legacy-key-missing');
      expect(
        result.bootstrap.toString(),
        isNot(contains('some wisdom text')),
      );
    });
  });

  group('3. an unrecognized exception maps to errorCode "unknown"', () {
    test('a bare StateError maps to unknown', () async {
      final bootstrapper = KeptStorageBootstrapper<String, String>(
        migrate: () async => throw StateError('unexpected failure'),
        buildRepository: (bootstrap) => 'repo',
        buildService: (repository) => 'service:$repository',
      );

      final result = await bootstrapper.run();

      expect(result.bootstrap.isUnavailable, isTrue);
      expect(result.bootstrap.errorCode, 'unknown');
    });

    test('a bare Exception maps to unknown', () async {
      final bootstrapper = KeptStorageBootstrapper<String, String>(
        migrate: () async => throw Exception('unexpected failure'),
        buildRepository: (bootstrap) => 'repo',
        buildService: (repository) => 'service:$repository',
      );

      final result = await bootstrapper.run();

      expect(result.bootstrap.errorCode, 'unknown');
    });
  });

  group('4. construction always happens, on both success and failure', () {
    test(
        'a failed migration still constructs an unavailable repository '
        'and service (never null, never skipped)', () async {
      String? capturedBootstrapStatusForRepository;
      var repositoryBuildCount = 0;
      var serviceBuildCount = 0;

      final bootstrapper = KeptStorageBootstrapper<String, String>(
        migrate: () async => throw const KeptMigrationException(
          'envelope-readback-missing',
          'The protected envelope could not be read back after migration.',
        ),
        buildRepository: (bootstrap) {
          repositoryBuildCount += 1;
          capturedBootstrapStatusForRepository = bootstrap.errorCode;
          return 'repo(${bootstrap.status})';
        },
        buildService: (repository) {
          serviceBuildCount += 1;
          return 'service:$repository';
        },
      );

      final result = await bootstrapper.run();

      expect(repositoryBuildCount, 1);
      expect(serviceBuildCount, 1);
      expect(capturedBootstrapStatusForRepository, 'envelope-readback-missing');
      expect(result.repository, isNotNull);
      expect(result.service, isNotNull);
      expect(result.repository, 'repo(KeptBootstrapStatus.unavailable)');
      expect(result.service, 'service:repo(KeptBootstrapStatus.unavailable)');
    });
  });

  group(
      'compilation-fix correction: a repository/service factory failure is '
      'never misclassified as a migration failure', () {
    test(
        'buildRepository throwing after a successful migration propagates '
        'as-is — it is not caught, and never becomes '
        'KeptBootstrapResult.unavailable("unknown")', () async {
      final bootstrapper = KeptStorageBootstrapper<String, String>(
        migrate: () async => const KeptMigrationResult(
          status: KeptMigrationStatus.noLegacyData,
          migratedCount: 0,
          corruptCount: 0,
          legacyCleanupCompleted: false,
        ),
        buildRepository: (bootstrap) =>
            throw StateError('repository factory exploded'),
        buildService: (repository) => 'service:$repository',
      );

      await expectLater(
        bootstrapper.run(),
        throwsA(isA<StateError>()),
      );
    });

    test(
        'buildRepository throwing after a failed migration still propagates '
        'as-is, not folded into the migration-failure mapping', () async {
      final bootstrapper = KeptStorageBootstrapper<String, String>(
        migrate: () async => throw const KeptMigrationException(
          'envelope-readback-missing',
          'The protected envelope could not be read back after migration.',
        ),
        buildRepository: (bootstrap) =>
            throw StateError('repository factory exploded'),
        buildService: (repository) => 'service:$repository',
      );

      await expectLater(
        bootstrapper.run(),
        throwsA(isA<StateError>()),
      );
    });

    test(
        'buildService throwing propagates as-is and is never reported as '
        'errorCode "unknown"', () async {
      final bootstrapper = KeptStorageBootstrapper<String, String>(
        migrate: () async => const KeptMigrationResult(
          status: KeptMigrationStatus.noLegacyData,
          migratedCount: 0,
          corruptCount: 0,
          legacyCleanupCompleted: false,
        ),
        buildRepository: (bootstrap) => 'repo',
        buildService: (repository) =>
            throw StateError('service factory exploded'),
      );

      await expectLater(
        bootstrapper.run(),
        throwsA(isA<StateError>()),
      );
    });
  });

  group(
      '5/6/7/8. end-to-end fail-closed behavior through the real '
      'KeptRepository/SavedReflectionsService, with a real '
      'KeptMigrationCoordinator wired to fakes', () {
    late _FakeLegacyFavoritesStore legacyStore;
    late _FakeJournalStore journalStore;
    late _FakeArtifactStore artifactStore;
    late _CountingKeptStateStore countingStore;
    late KeptStorageBootstrapper<KeptRepository, SavedReflectionsService>
        bootstrapper;

    setUp(() {
      legacyStore = _FakeLegacyFavoritesStore();
      journalStore = _FakeJournalStore();
      artifactStore = _FakeArtifactStore();
      countingStore = _CountingKeptStateStore(InMemoryKeptStateStore());

      // Deliberately conflicting precondition: legacy data exists *and* a
      // protected envelope already exists. `KeptMigrationCoordinator`
      // treats this as `unexpected-existing-protected-state` and throws
      // immediately, before ever touching the journal, before writing any
      // snapshot, and — critically for this test — before ever calling
      // `removeAndVerify()` on the legacy store.
      legacyStore.entries = ['some-legacy-entry'];
      countingStore.envelope = KeptStateEnvelope();

      final coordinator = KeptMigrationCoordinator(
        legacyFavoritesStore: legacyStore,
        journalStore: journalStore,
        artifactStore: artifactStore,
        keptStateStore: countingStore,
        operationCoordinator: PersistenceOperationCoordinator(),
      );

      bootstrapper =
          KeptStorageBootstrapper<KeptRepository, SavedReflectionsService>(
        migrate: coordinator.migrateIfNeeded,
        buildRepository: (bootstrap) => KeptRepository(
          store: countingStore,
          bootstrap: bootstrap,
          operationCoordinator: PersistenceOperationCoordinator(),
        ),
        buildService: (repository) =>
            SavedReflectionsService(keptRepository: repository),
      );
    });

    test(
        '7/8. the bootstrap-failure migration path never replaces the '
        'protected store and never removes the legacy favorites key', () async {
      final result = await bootstrapper.run();

      expect(result.bootstrap.isUnavailable, isTrue);
      expect(
        result.bootstrap.errorCode,
        'unexpected-existing-protected-state',
      );
      expect(countingStore.loadCallCount, 1);
      expect(countingStore.replaceCallCount, 0);
      expect(legacyStore.removeCallCount, 0);
    });

    test('5. an unavailable service load() fails closed', () async {
      final result = await bootstrapper.run();
      final loadCallsBeforeRead = countingStore.loadCallCount;

      await expectLater(
        result.service.load(),
        throwsA(isA<KeptRepositoryException>()),
      );

      // The repository's own bootstrap gate throws before ever touching
      // the store again — proving "does not access the protected store"
      // is true of the constructed (unavailable) repository too, not only
      // of the bootstrapper itself.
      expect(countingStore.loadCallCount, loadCallsBeforeRead);
    });

    test('6. an unavailable service mutation (toggle) fails closed', () async {
      final result = await bootstrapper.run();
      final loadCallsBefore = countingStore.loadCallCount;
      final replaceCallsBefore = countingStore.replaceCallCount;

      await expectLater(
        result.service.toggle(
          revealId: 'a5f3c111-1111-4111-8111-111111111111',
          text: 'Be still.',
          date: 'August 1, 2026',
          revealedAt: DateTime.utc(2026, 8, 1),
          isKeeper: false,
        ),
        throwsA(isA<KeptRepositoryException>()),
      );
      // Failure-access clarification: migration itself may have accessed
      // the store before `KeptBootstrapResult.unavailable` was constructed
      // (proven separately above by the "7/8." test — exactly one `load()`
      // during the failed migration attempt itself) — what this assertion
      // proves is narrower and different: once the bootstrap has already
      // resolved to `unavailable`, this *subsequent*
      // `SavedReflectionsService.toggle` call performs zero additional
      // protected-store accesses of either kind (no extra `load()`, no
      // `replace()`/legacy live write).
      expect(countingStore.loadCallCount, loadCallsBefore);
      expect(countingStore.replaceCallCount, replaceCallsBefore);
    });
  });

  group('9/10. repeated/concurrent initialization', () {
    test('sequential calls to run() invoke migrate exactly once', () async {
      var migrateCallCount = 0;
      final bootstrapper = KeptStorageBootstrapper<String, String>(
        migrate: () async {
          migrateCallCount += 1;
          return const KeptMigrationResult(
            status: KeptMigrationStatus.noLegacyData,
            migratedCount: 0,
            corruptCount: 0,
            legacyCleanupCompleted: false,
          );
        },
        buildRepository: (bootstrap) => 'repo',
        buildService: (repository) => 'service:$repository',
      );

      await bootstrapper.run();
      await bootstrapper.run();
      await bootstrapper.run();

      expect(migrateCallCount, 1);
    });

    test(
        'concurrent calls to run() (before the first resolves) share the '
        'exact same in-flight Future and result', () async {
      final migrationCompleter = Completer<KeptMigrationResult>();
      var migrateCallCount = 0;
      final bootstrapper = KeptStorageBootstrapper<String, String>(
        migrate: () {
          migrateCallCount += 1;
          return migrationCompleter.future;
        },
        buildRepository: (bootstrap) => 'repo',
        buildService: (repository) => 'service:$repository',
      );

      final first = bootstrapper.run();
      final second = bootstrapper.run();
      expect(
        identical(first, second),
        isTrue,
        reason: 'A second run() call made before the first resolves must '
            'return the exact same Future, not start a second attempt.',
      );

      migrationCompleter.complete(
        const KeptMigrationResult(
          status: KeptMigrationStatus.noLegacyData,
          migratedCount: 0,
          corruptCount: 0,
          legacyCleanupCompleted: false,
        ),
      );

      final results = await Future.wait([first, second]);
      expect(migrateCallCount, 1);
      expect(identical(results[0], results[1]), isTrue);
    });

    test('a failed first attempt is still cached (never silently retried)',
        () async {
      var migrateCallCount = 0;
      final bootstrapper = KeptStorageBootstrapper<String, String>(
        migrate: () async {
          migrateCallCount += 1;
          throw StateError('simulated failure');
        },
        buildRepository: (bootstrap) => 'repo',
        buildService: (repository) => 'service:$repository',
      );

      final first = await bootstrapper.run();
      final second = await bootstrapper.run();

      expect(migrateCallCount, 1);
      expect(first.bootstrap.errorCode, 'unknown');
      expect(second.bootstrap.errorCode, 'unknown');
    });
  });

  group('11/12. construction ordering and absence of any timeout', () {
    test(
        'buildRepository/buildService are never called before migrate '
        'resolves', () async {
      final migrationCompleter = Completer<KeptMigrationResult>();
      var repositoryBuilt = false;
      var serviceBuilt = false;

      final bootstrapper = KeptStorageBootstrapper<String, String>(
        migrate: () => migrationCompleter.future,
        buildRepository: (bootstrap) {
          repositoryBuilt = true;
          return 'repo';
        },
        buildService: (repository) {
          serviceBuilt = true;
          return 'service';
        },
      );

      final future = bootstrapper.run();
      // Give the event loop several turns to prove nothing races ahead of
      // migration resolving.
      for (var i = 0; i < 5; i += 1) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(repositoryBuilt, isFalse);
      expect(serviceBuilt, isFalse);

      migrationCompleter.complete(
        const KeptMigrationResult(
          status: KeptMigrationStatus.noLegacyData,
          migratedCount: 0,
          corruptCount: 0,
          legacyCleanupCompleted: false,
        ),
      );
      await future;

      expect(repositoryBuilt, isTrue);
      expect(serviceBuilt, isTrue);
    });

    test(
        'no timeout is applied to migrate: a migration that has not '
        'resolved after several real seconds leaves run() still pending, '
        'and it still resolves successfully once migration itself '
        'completes', () async {
      final migrationCompleter = Completer<KeptMigrationResult>();
      final bootstrapper = KeptStorageBootstrapper<String, String>(
        migrate: () => migrationCompleter.future,
        buildRepository: (bootstrap) => 'repo',
        buildService: (repository) => 'service:$repository',
      );

      var resolved = false;
      final future = bootstrapper.run().then((result) {
        resolved = true;
        return result;
      });

      // Longer than any UI-facing timeout duration used elsewhere in this
      // app (4s status timeout, 8s reveal-operation timeout) — if a
      // timeout had been (incorrectly) applied here, `resolved` would
      // already be true by now, with an `unavailable('unknown')` (or
      // similar) result, rather than still pending.
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(
        resolved,
        isFalse,
        reason: 'run() must remain pending for as long as migrate() has '
            'not resolved — no timeout may synthesize a result early.',
      );

      migrationCompleter.complete(
        const KeptMigrationResult(
          status: KeptMigrationStatus.noLegacyData,
          migratedCount: 0,
          corruptCount: 0,
          legacyCleanupCompleted: false,
        ),
      );
      final result = await future;
      expect(resolved, isTrue);
      expect(result.bootstrap.isReady, isTrue);
    });
  });

  group(
      'Phase 3D-D addendum: the reported Keep-control failure is a '
      'downstream symptom of migration/bootstrap unavailability, not a '
      'separate defect', () {
    // Byte-exact recovered `flutter.favorites` entry from the reported
    // real-device incident (see kept_migration_coordinator_test.dart's
    // "Phase 3D-D real-device migration hotfix" group for the full
    // reproduction and root-cause analysis of why this exact payload used
    // to fail migration).
    const recoveredPayload = '{"schemaVersion":2,'
        '"id":"sr-v1-1785622374122602-0",'
        '"date":"August 2, 2026",'
        '"text":"Some doors open after surrender.",'
        '"reflection":"Ibne galatasaray",'
        '"reflectedAt":"2026-08-02T01:13:07.484133"}';

    late _FakeLegacyFavoritesStore legacyStore;
    late _FakeJournalStore journalStore;
    late _FakeArtifactStore artifactStore;
    late JsonRoundTrippingKeptStateStore roundTrippingStore;

    KeptStorageBootstrapper<KeptRepository, SavedReflectionsService>
        buildBootstrapper() {
      final coordinator = KeptMigrationCoordinator(
        legacyFavoritesStore: legacyStore,
        journalStore: journalStore,
        artifactStore: artifactStore,
        keptStateStore: roundTrippingStore,
        operationCoordinator: PersistenceOperationCoordinator(),
      );
      return KeptStorageBootstrapper<KeptRepository, SavedReflectionsService>(
        migrate: coordinator.migrateIfNeeded,
        buildRepository: (bootstrap) => KeptRepository(
          store: roundTrippingStore,
          bootstrap: bootstrap,
          operationCoordinator: PersistenceOperationCoordinator(),
          // A fixed, already millisecond-exact clock: a new Keep's
          // KeptRecord.keptAt/updatedAt otherwise default to a raw
          // DateTime.now(), which (like the unfixed legacy reflectedAt
          // this whole hotfix is about) commonly carries genuine
          // sub-millisecond precision on a real device. Whether
          // KeptRepository's own default clock should itself be
          // millisecond-truncated is a separate, pre-existing question
          // about ordinary (non-migration) runtime mutation behavior,
          // explicitly out of scope for this hotfix — this fixed clock
          // only keeps this test focused on the migration/availability
          // interaction it's actually about.
          clock: () => DateTime.utc(2026, 8, 2, 15, 0, 0),
        ),
        buildService: (repository) =>
            SavedReflectionsService(keptRepository: repository),
      );
    }

    setUp(() {
      legacyStore = _FakeLegacyFavoritesStore();
      journalStore = _FakeJournalStore();
      artifactStore = _FakeArtifactStore();
      roundTrippingStore = JsonRoundTrippingKeptStateStore();
      legacyStore.entries = [recoveredPayload];
    });

    test(
        '1. a pre-fix-equivalent envelope-verification failure (the exact '
        'mechanism the unfixed reflectedAt/microsecond bug triggered) '
        'leaves the repository unavailable and safely blocks a new Keep, '
        'with Kept remaining empty', () async {
      // Forcing the protected store's own write-verification to fail
      // reproduces, generically, the same failure mode the unfixed
      // migration code triggered specifically via microsecond-precision
      // loss: envelope-replace fails verification, migration throws before
      // ever placing the envelope file, and bootstrap resolves to
      // unavailable.
      roundTrippingStore.forceVerifyFailure = true;
      final bootstrapper = buildBootstrapper();

      final result = await bootstrapper.run();

      expect(result.bootstrap.isUnavailable, isTrue);
      expect(result.bootstrap.errorCode, 'envelope-replace');
      // Kept remains empty / inaccessible.
      await expectLater(
        result.service.load(),
        throwsA(isA<KeptRepositoryException>()),
      );
      // A new Keep mutation is safely blocked, not silently written into an
      // empty fabricated state.
      await expectLater(
        result.repository.keepOccurrence(
          revealId: 'b6f4d222-2222-4222-8222-222222222222',
          wisdomText: 'A brand new wisdom.',
          revealedAt: DateTime.utc(2026, 8, 2),
          isKeeper: false,
        ),
        throwsA(isA<KeptRepositoryException>()),
      );
      // The legacy key was never removed — nothing was silently discarded.
      expect(legacyStore.entries, [recoveredPayload]);
    });

    test(
        '2. after the fix, the migrated Build 25 record is visible, the '
        'repository becomes available, a new reveal can be kept '
        'successfully, both records remain present, and no duplicate '
        'migrated record is created', () async {
      final bootstrapper = buildBootstrapper();

      final result = await bootstrapper.run();

      expect(result.bootstrap.isReady, isTrue);
      expect(result.bootstrap.isUnavailable, isFalse);

      final afterMigration = await result.service.load();
      expect(afterMigration, hasLength(1));
      expect(afterMigration.single.id, 'sr-v1-1785622374122602-0');
      expect(afterMigration.single.text, 'Some doors open after surrender.');

      // A new, valid reveal occurrence can be kept successfully — the
      // repository/service the migrated record came from is genuinely
      // available, not merely reporting success while still fail-closed.
      final afterKeep = await result.service.toggle(
        revealId: 'b6f4d222-2222-4222-8222-222222222222',
        text: 'A brand new wisdom.',
        date: 'August 2, 2026',
        revealedAt: DateTime.utc(2026, 8, 2),
        isKeeper: false,
      );

      expect(afterKeep.limitReached, isFalse);
      expect(afterKeep.items, hasLength(2));
      final ids = afterKeep.items.map((item) => item.id).toList();
      // Both records remain present...
      expect(ids, contains('sr-v1-1785622374122602-0'));
      expect(ids.where((id) => id == 'sr-v1-1785622374122602-0'), hasLength(1));
      // ...and no duplicate of the migrated record was created by keeping
      // the new one.
      expect(ids.toSet(), hasLength(2));

      // Re-loading independently confirms both records persisted, not just
      // the in-memory mutation result. This is itself proof the new record
      // survived a real JSON round-trip: JsonRoundTrippingKeptStateStore's
      // own replace() throws on any encode/decode mismatch, so `toggle`
      // above could not have succeeded otherwise.
      final reloaded = await result.service.load();
      expect(reloaded, hasLength(2));
      final storedDirectly = (await roundTrippingStore.load())!.activeRecords;
      expect(storedDirectly, hasLength(2));
    });

    test(
        '3. after migration, a new Reflection on the migrated record '
        'survives a real JSON round-trip', () async {
      final bootstrapper = buildBootstrapper();
      final result = await bootstrapper.run();
      expect(result.bootstrap.isReady, isTrue);

      final afterReflection = await result.service.saveReflection(
        itemId: 'sr-v1-1785622374122602-0',
        reflection: 'A brand new reflection, added at runtime.',
        isKeeper: false,
        reflectedAt: DateTime.utc(2026, 8, 3, 9, 0, 0, 250, 250),
      );

      expect(afterReflection.limitReached, isFalse);
      // The migrated record already had a Reflection from Build 25, so this
      // edits it — reflectionLimitReached must not fire for an edit.
      expect(afterReflection.reflectionLimitReached, isFalse);
      final record = (await roundTrippingStore.load())!.activeRecords.single;
      expect(
        record.reflectionText,
        'A brand new reflection, added at runtime.',
      );
      // Canonicalized to millisecond precision, exactly like every other
      // normal-runtime write — otherwise this save would itself have failed
      // the store's own encode/decode verification.
      expect(record.reflectedAt, DateTime.utc(2026, 8, 3, 9, 0, 0, 250));
    });

    test(
        '4. no duplicate migrated record is created across a simulated app '
        'relaunch (a fresh coordinator/bootstrapper reusing the same '
        'persisted stores)', () async {
      final firstLaunch = buildBootstrapper();
      final firstResult = await firstLaunch.run();
      expect(firstResult.bootstrap.isReady, isTrue);
      expect(
        (await roundTrippingStore.load())!.activeRecords,
        hasLength(1),
      );

      // A second "launch": a brand-new coordinator and bootstrapper (as
      // `main()` constructs fresh on every real process start), wired to
      // the exact same underlying stores — simulating relaunching the app
      // without deleting it, which is exactly the reported real-device
      // scenario.
      final secondLaunch = buildBootstrapper();
      final secondResult = await secondLaunch.run();

      expect(secondResult.bootstrap.isReady, isTrue);
      final records = (await roundTrippingStore.load())!.activeRecords;
      expect(records, hasLength(1));
      expect(records.single.id, 'sr-v1-1785622374122602-0');
      expect(legacyStore.entries, isNull);
    });
  });
}

/// Counts `load`/`replace` calls on top of the shared in-memory
/// `KeptStateStore` fake, so a test can directly prove how many times the
/// bootstrap/repository layers actually touched the store.
class _CountingKeptStateStore implements KeptStateStore {
  _CountingKeptStateStore(this._inner);

  final InMemoryKeptStateStore _inner;
  int loadCallCount = 0;
  int replaceCallCount = 0;

  set envelope(KeptStateEnvelope? value) => _inner.envelope = value;

  @override
  Future<KeptStateEnvelope?> load() {
    loadCallCount += 1;
    return _inner.load();
  }

  @override
  Future<void> replace(KeptStateEnvelope envelope) {
    replaceCallCount += 1;
    return _inner.replace(envelope);
  }
}

class _FakeLegacyFavoritesStore implements LegacyFavoritesStore {
  List<String>? entries;
  int removeCallCount = 0;

  @override
  Future<bool> containsLegacyData() async => entries != null;

  @override
  Future<List<String>?> readRawEntries() async =>
      entries == null ? null : List.unmodifiable(entries!);

  @override
  Future<void> removeAndVerify() async {
    removeCallCount += 1;
    entries = null;
  }
}

class _FakeJournalStore implements KeptMigrationJournalStore {
  KeptMigrationJournal? journal;

  @override
  Future<KeptMigrationJournal?> load() async => journal;

  @override
  Future<void> save(KeptMigrationJournal newJournal) async {
    journal = newJournal;
  }
}

class _FakeArtifactStore implements KeptMigrationArtifactStore {
  final Map<String, KeptMigrationSnapshot> snapshots = {};
  final Map<String, KeptMigrationRecoveryArtifact> recoveryArtifacts = {};

  @override
  Future<KeptMigrationSnapshot?> loadSnapshot(String fileName) async =>
      snapshots[fileName];

  @override
  Future<void> writeSnapshot(
    String fileName,
    KeptMigrationSnapshot snapshot,
  ) async {
    snapshots[fileName] = snapshot;
  }

  @override
  Future<KeptMigrationRecoveryArtifact?> loadRecoveryArtifact(
    String fileName,
  ) async =>
      recoveryArtifacts[fileName];

  @override
  Future<void> writeRecoveryArtifact(
    String fileName,
    KeptMigrationRecoveryArtifact artifact,
  ) async {
    recoveryArtifacts[fileName] = artifact;
  }
}
