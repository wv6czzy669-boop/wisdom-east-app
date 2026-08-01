import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/models/kept_migration_journal.dart';
import 'package:wisdom_app/models/kept_migration_recovery_artifact.dart';
import 'package:wisdom_app/models/kept_migration_snapshot.dart';
import 'package:wisdom_app/models/kept_record.dart';
import 'package:wisdom_app/models/kept_state_envelope.dart';
import 'package:wisdom_app/persistence/kept_migration_artifact_store.dart';
import 'package:wisdom_app/persistence/kept_migration_journal_store.dart';
import 'package:wisdom_app/persistence/kept_state_store.dart';
import 'package:wisdom_app/persistence/legacy_favorites_store.dart';
import 'package:wisdom_app/persistence/stored_favorite_entry_codec.dart';
import 'package:wisdom_app/services/kept_migration_coordinator.dart';

class _FakeLegacyFavoritesStore implements LegacyFavoritesStore {
  List<String>? entries;
  bool removeShouldFail = false;
  int removeCallCount = 0;

  @override
  Future<bool> containsLegacyData() async => entries != null;

  @override
  Future<List<String>?> readRawEntries() async =>
      entries == null ? null : List.unmodifiable(entries!);

  @override
  Future<void> removeAndVerify() async {
    removeCallCount += 1;
    if (removeShouldFail) {
      throw StateError('Simulated legacy removal failure.');
    }
    entries = null;
  }
}

class _FakeJournalStore implements KeptMigrationJournalStore {
  KeptMigrationJournal? journal;
  bool saveShouldFail = false;
  int saveCallCount = 0;

  @override
  Future<KeptMigrationJournal?> load() async => journal;

  @override
  Future<void> save(KeptMigrationJournal newJournal) async {
    saveCallCount += 1;
    if (saveShouldFail) throw StateError('Simulated journal save failure.');
    journal = newJournal;
  }
}

class _FakeArtifactStore implements KeptMigrationArtifactStore {
  final Map<String, KeptMigrationSnapshot> snapshots = {};
  final Map<String, KeptMigrationRecoveryArtifact> recoveryArtifacts = {};
  bool writeSnapshotShouldFail = false;
  bool writeRecoveryShouldFail = false;

  @override
  Future<KeptMigrationSnapshot?> loadSnapshot(String fileName) async =>
      snapshots[fileName];

  @override
  Future<void> writeSnapshot(
    String fileName,
    KeptMigrationSnapshot snapshot,
  ) async {
    if (writeSnapshotShouldFail) {
      throw StateError('Simulated snapshot write failure.');
    }
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
    if (writeRecoveryShouldFail) {
      throw StateError('Simulated recovery artifact write failure.');
    }
    recoveryArtifacts[fileName] = artifact;
  }
}

class _FakeKeptStateStore implements KeptStateStore {
  KeptStateEnvelope? envelope;
  bool replaceShouldFail = false;
  int replaceCallCount = 0;
  int loadCallCount = 0;
  KeptStateEnvelope? Function(int callCount, KeptStateEnvelope? stored)?
      loadOverride;

  @override
  Future<KeptStateEnvelope?> load() async {
    loadCallCount += 1;
    if (loadOverride != null) return loadOverride!(loadCallCount, envelope);
    return envelope;
  }

  @override
  Future<void> replace(KeptStateEnvelope newEnvelope) async {
    replaceCallCount += 1;
    if (replaceShouldFail) {
      throw StateError('Simulated envelope replace failure.');
    }
    envelope = newEnvelope;
  }
}

void main() {
  const migrationId = '123e4567-e89b-4d3a-a456-426614174000';
  final startedAt = DateTime.utc(2026, 8, 1, 9, 0);
  const uuid = Uuid();

  String revealIdFor(String favoriteId) => uuid.v5(Namespace.url.value,
      'com.dogukan.dailywisdom/build25/reveal/$favoriteId');
  String mutationIdFor(String favoriteId) => uuid.v5(Namespace.url.value,
      'com.dogukan.dailywisdom/build25/mutation/$favoriteId');

  late _FakeLegacyFavoritesStore legacy;
  late _FakeJournalStore journalStore;
  late _FakeArtifactStore artifactStore;
  late _FakeKeptStateStore keptStateStore;

  setUp(() {
    legacy = _FakeLegacyFavoritesStore();
    journalStore = _FakeJournalStore();
    artifactStore = _FakeArtifactStore();
    keptStateStore = _FakeKeptStateStore();
  });

  KeptMigrationCoordinator buildCoordinator({
    String Function()? migrationIdFactory,
    DateTime Function()? clock,
  }) {
    return KeptMigrationCoordinator(
      legacyFavoritesStore: legacy,
      journalStore: journalStore,
      artifactStore: artifactStore,
      keptStateStore: keptStateStore,
      migrationIdFactory: migrationIdFactory ?? (() => migrationId),
      clock: clock ?? (() => startedAt),
    );
  }

  String recoveryFileName([String id = migrationId]) =>
      'east_kept_migration_recovery_v1-$id.json';

  test(
      '43. no legacy data and no envelope returns noLegacyData with no journal',
      () async {
    final coordinator = buildCoordinator();

    final result = await coordinator.migrateIfNeeded();

    expect(result.status, KeptMigrationStatus.noLegacyData);
    expect(journalStore.journal, isNull);
  });

  test('44. no legacy data with an existing envelope returns alreadyProtected',
      () async {
    keptStateStore.envelope = KeptStateEnvelope();
    final coordinator = buildCoordinator();

    final result = await coordinator.migrateIfNeeded();

    expect(result.status, KeptMigrationStatus.alreadyProtected);
    expect(journalStore.journal, isNull);
  });

  test('45. legacy data plus an unexpected existing envelope blocks', () async {
    legacy.entries = ['2026-01-01T00:00:00.000Z|||some text'];
    keptStateStore.envelope = KeptStateEnvelope();
    final coordinator = buildCoordinator();

    await expectLater(
      coordinator.migrateIfNeeded(),
      throwsA(isA<KeptMigrationException>()),
    );
    expect(legacy.entries, isNotNull);
  });

  test('46. happy-path migration completes in one call', () async {
    final item = FavoriteItem(
      id: 'legacy-1',
      date: '2026-01-01T09:00:00.000Z',
      text: 'What is meant for you does not panic.',
    );
    legacy.entries = [item.encode()];
    final coordinator = buildCoordinator();

    final result = await coordinator.migrateIfNeeded();

    expect(result.status, KeptMigrationStatus.migrated);
    expect(result.migratedCount, 1);
    expect(result.corruptCount, 0);
    expect(result.legacyCleanupCompleted, isTrue);
    expect(legacy.entries, isNull);
    expect(journalStore.journal!.state, KeptMigrationState.complete);
    expect(keptStateStore.envelope!.activeRecords.single.id, 'legacy-1');
    expect(
      keptStateStore.envelope!.activeRecords.single.revealId,
      revealIdFor('legacy-1'),
    );
  });

  test('47. an empty legacy StringList migrates to an empty envelope safely',
      () async {
    legacy.entries = <String>[];
    final coordinator = buildCoordinator();

    final result = await coordinator.migrateIfNeeded();

    expect(result.status, KeptMigrationStatus.migrated);
    expect(result.migratedCount, 0);
    expect(keptStateStore.envelope!.activeRecords, isEmpty);
    expect(legacy.entries, isNull);
  });

  test('48. mixed legacy pipe and current JSON formats both migrate', () async {
    final jsonItem = FavoriteItem(
      id: 'json-1',
      date: '2026-01-02T09:00:00.000Z',
      text: 'JSON entry.',
    );
    legacy.entries = [
      '2026-01-01T09:00:00.000Z|||Pipe entry.',
      jsonItem.encode(),
    ];
    final coordinator = buildCoordinator();

    final result = await coordinator.migrateIfNeeded();

    expect(result.status, KeptMigrationStatus.migrated);
    expect(result.migratedCount, 2);
    expect(
      keptStateStore.envelope!.activeRecords.map((r) => r.wisdomText).toList(),
      ['Pipe entry.', 'JSON entry.'],
    );
  });

  test('49. a corrupt entry is preserved exactly while valid entries migrate',
      () async {
    final validItem = FavoriteItem(
      id: 'valid-1',
      date: '2026-01-01T09:00:00.000Z',
      text: 'Valid entry.',
    );
    legacy.entries = ['not a valid legacy or json entry', validItem.encode()];
    final coordinator = buildCoordinator();

    final result = await coordinator.migrateIfNeeded();

    expect(result.status, KeptMigrationStatus.migrated);
    expect(result.migratedCount, 1);
    expect(result.corruptCount, 1);
    final artifact = artifactStore.recoveryArtifacts[recoveryFileName()]!;
    expect(artifact.corruptEntries.single.rawValue,
        'not a valid legacy or json entry');
    expect(
      artifact.corruptEntries.single.stage,
      KeptMigrationFailureStage.decode,
    );
    expect(
      artifact.corruptEntries.single.reasonCode,
      'favorite_decode_failed',
    );
  });

  test(
      '50. a recovery-artifact write failure blocks and retains the legacy key',
      () async {
    legacy.entries = ['not a valid entry'];
    artifactStore.writeRecoveryShouldFail = true;
    final coordinator = buildCoordinator();

    await expectLater(
      coordinator.migrateIfNeeded(),
      throwsA(isA<KeptMigrationException>()),
    );
    expect(legacy.entries, isNotNull);
    expect(journalStore.journal!.state, KeptMigrationState.writing);
  });

  test('51. a duplicate record ID blocks and retains the legacy key', () async {
    final itemA = FavoriteItem(
      id: 'dup-1',
      date: '2026-01-01T09:00:00.000Z',
      text: 'First.',
    );
    final itemB = FavoriteItem(
      id: 'dup-1',
      date: '2026-01-02T09:00:00.000Z',
      text: 'Second.',
    );
    legacy.entries = [itemA.encode(), itemB.encode()];
    final coordinator = buildCoordinator();

    await expectLater(
      coordinator.migrateIfNeeded(),
      throwsA(isA<KeptMigrationException>()),
    );
    expect(legacy.entries, isNotNull);
    expect(journalStore.journal!.state, KeptMigrationState.writing);
    final artifact = artifactStore.recoveryArtifacts[recoveryFileName()]!;
    expect(artifact.corruptEntries.length, 2);
    expect(
      artifact.corruptEntries.every(
        (e) =>
            e.stage == KeptMigrationFailureStage.duplicateIdentity &&
            e.reasonCode == 'duplicate_record_id',
      ),
      isTrue,
    );
  });

  test(
      '52. a duplicate reveal ID (different record IDs) blocks and retains '
      'the legacy key', () async {
    final itemA = FavoriteItem(
      id: 'alpha',
      date: '2026-01-01T09:00:00.000Z',
      text: 'First.',
    );
    final itemB = FavoriteItem(
      id: 'beta',
      date: '2026-01-02T09:00:00.000Z',
      text: 'Second.',
    );
    legacy.entries = [itemA.encode(), itemB.encode()];
    // Rig the identity mapping so two different FavoriteItem IDs produce
    // the same deterministic revealId, exercising the revealId-collision
    // path independently of the id-collision path (which, with the real
    // v5 mapping, always co-occurs with a revealId collision since revealId
    // is derived purely from id).
    final coordinator = KeptMigrationCoordinator(
      legacyFavoritesStore: legacy,
      journalStore: journalStore,
      artifactStore: artifactStore,
      keptStateStore: keptStateStore,
      migrationIdFactory: () => migrationId,
      clock: () => startedAt,
      uuidV5Factory: (name) => name.contains('/reveal/')
          ? revealIdFor('forced-same')
          : mutationIdFor(name),
    );

    await expectLater(
      coordinator.migrateIfNeeded(),
      throwsA(isA<KeptMigrationException>()),
    );
    expect(legacy.entries, isNotNull);
    final artifact = artifactStore.recoveryArtifacts[recoveryFileName()]!;
    expect(
      artifact.corruptEntries.every(
        (e) =>
            e.stage == KeptMigrationFailureStage.duplicateIdentity &&
            e.reasonCode == 'duplicate_reveal_id',
      ),
      isTrue,
    );
  });

  test(
      '53. a snapshot write failure retains the legacy key and the '
      'already-persisted writing journal', () async {
    legacy.entries = ['2026-01-01T09:00:00.000Z|||text'];
    artifactStore.writeSnapshotShouldFail = true;
    final coordinator = buildCoordinator();

    await expectLater(
      coordinator.migrateIfNeeded(),
      throwsA(isA<KeptMigrationException>()),
    );

    // The durable `writing` journal is persisted *before* the snapshot
    // write is even attempted (the locked state machine's pre-snapshot
    // checkpoint), so it must survive this failure — it is not erased,
    // and it must not be mistaken for "no journal".
    expect(legacy.entries, isNotNull);
    final journal = journalStore.journal;
    expect(journal, isNotNull);
    expect(journal!.state, KeptMigrationState.writing);
    expect(journal.migrationId, migrationId);
    expect(journal.startedAt, startedAt);
    expect(journal.updatedAt, startedAt);
    // The snapshot write itself never succeeded, so nothing that depends
    // on it may be recorded yet.
    expect(journal.snapshotFileName, isNull);
    expect(journal.legacyEntryCount, isNull);
    expect(journal.usableEntryCount, isNull);
    expect(journal.corruptEntryCount, isNull);
    expect(journal.recoveryFileName, isNull);
    // No protected envelope may exist, and cleanup must not have run.
    expect(keptStateStore.envelope, isNull);
    expect(legacy.removeCallCount, 0);
  });

  test('54. an envelope replace failure retains the legacy key', () async {
    legacy.entries = ['2026-01-01T09:00:00.000Z|||text'];
    keptStateStore.replaceShouldFail = true;
    final coordinator = buildCoordinator();

    await expectLater(
      coordinator.migrateIfNeeded(),
      throwsA(isA<KeptMigrationException>()),
    );
    expect(legacy.entries, isNotNull);
    expect(journalStore.journal!.state, KeptMigrationState.writing);
  });

  test('55. an envelope read-back mismatch retains the legacy key', () async {
    legacy.entries = ['2026-01-01T09:00:00.000Z|||text'];
    keptStateStore.loadOverride = (count, stored) {
      if (count == 2) {
        return KeptStateEnvelope(); // wrong: empty, doesn't match migrated.
      }
      return stored;
    };
    final coordinator = buildCoordinator();

    await expectLater(
      coordinator.migrateIfNeeded(),
      throwsA(isA<KeptMigrationException>()),
    );
    expect(legacy.entries, isNotNull);
  });

  test('56. a verified-journal write failure retains the legacy key', () async {
    legacy.entries = ['2026-01-01T09:00:00.000Z|||text'];
    // A single clean entry produces exactly 2 journal saves before the
    // verified-transition save: the initial writing journal, then the
    // writing journal updated with legacyEntryCount/snapshotFileName. Fail
    // the 3rd save — the transition to verified — specifically.
    final wrappedJournalStore = _CountingFailOnNthSaveJournalStore(
      inner: journalStore,
      failOnSaveNumber: 3,
    );
    final coordinator = KeptMigrationCoordinator(
      legacyFavoritesStore: legacy,
      journalStore: wrappedJournalStore,
      artifactStore: artifactStore,
      keptStateStore: keptStateStore,
      migrationIdFactory: () => migrationId,
      clock: () => startedAt,
    );

    await expectLater(
      coordinator.migrateIfNeeded(),
      throwsA(isA<KeptMigrationException>()),
    );
    expect(legacy.entries, isNotNull);
    expect(journalStore.journal!.state, KeptMigrationState.writing);
  });

  test('57. the legacy key is never removed before verified persistence',
      () async {
    legacy.entries = ['2026-01-01T09:00:00.000Z|||text'];
    keptStateStore.replaceShouldFail = true;
    final coordinator = buildCoordinator();

    await expectLater(
      coordinator.migrateIfNeeded(),
      throwsA(isA<KeptMigrationException>()),
    );
    expect(legacy.removeCallCount, 0);
  });

  test('58. a cleanup failure leaves the journal verified', () async {
    legacy.entries = ['2026-01-01T09:00:00.000Z|||text'];
    legacy.removeShouldFail = true;
    final coordinator = buildCoordinator();

    await expectLater(
      coordinator.migrateIfNeeded(),
      throwsA(isA<KeptMigrationException>()),
    );
    expect(journalStore.journal!.state, KeptMigrationState.verified);
    expect(legacy.entries, isNotNull);
  });

  test('59. retrying from verified completes cleanup', () async {
    legacy.entries = ['2026-01-01T09:00:00.000Z|||text'];
    legacy.removeShouldFail = true;
    final coordinator = buildCoordinator();

    await expectLater(
      coordinator.migrateIfNeeded(),
      throwsA(isA<KeptMigrationException>()),
    );
    legacy.removeShouldFail = false;

    final result = await coordinator.migrateIfNeeded();

    expect(result.status, KeptMigrationStatus.migrated);
    expect(legacy.entries, isNull);
    expect(journalStore.journal!.state, KeptMigrationState.complete);
  });

  test(
      '60. a crash after legacy removal but before complete resumes '
      'correctly without repeating the removal', () async {
    legacy.entries = ['2026-01-01T09:00:00.000Z|||text'];
    final coordinator = buildCoordinator();
    // Drive to verified first: the removal itself fails, so the journal
    // stays at `verified` rather than advancing to `complete`.
    legacy.removeShouldFail = true;
    await expectLater(
      coordinator.migrateIfNeeded(),
      throwsA(isA<KeptMigrationException>()),
    );
    // The first attempt legitimately performed exactly one removal call —
    // this is not a lifetime-zero-removals scenario.
    expect(legacy.removeCallCount, 1);
    expect(journalStore.journal!.state, KeptMigrationState.verified);

    legacy.removeShouldFail = false;
    // Simulate the removal having actually already succeeded before a
    // crash prevented the `complete` journal write: the key is now absent
    // even though the journal still says verified.
    legacy.entries = null;

    final removalsBeforeRetry = legacy.removeCallCount;
    final result = await coordinator.migrateIfNeeded();

    // The retry re-verifies protected state and writes `complete` without
    // ever calling removeAndVerify() again, since the legacy key is
    // already absent.
    expect(legacy.removeCallCount, removalsBeforeRetry);
    expect(result.status, KeptMigrationStatus.migrated);
    expect(journalStore.journal!.state, KeptMigrationState.complete);
    expect(keptStateStore.envelope, isNotNull);
    expect(keptStateStore.envelope!.activeRecords, isNotEmpty);
  });

  test(
      '61. retrying from writing uses the frozen snapshot rather than '
      'changed SharedPreferences data', () async {
    final originalItem = FavoriteItem(
      id: 'original-1',
      date: '2026-01-01T09:00:00.000Z',
      text: 'Original.',
    );
    legacy.entries = [originalItem.encode()];

    final coordinator = buildCoordinator();
    // Fail after the snapshot is written but before the migration finishes,
    // by making the envelope replace fail once.
    keptStateStore.replaceShouldFail = true;
    await expectLater(
      coordinator.migrateIfNeeded(),
      throwsA(isA<KeptMigrationException>()),
    );
    keptStateStore.replaceShouldFail = false;

    // Now SharedPreferences changes underneath the migration.
    final changedItem = FavoriteItem(
      id: 'changed-1',
      date: '2026-01-05T09:00:00.000Z',
      text: 'Changed after snapshot.',
    );
    legacy.entries = [changedItem.encode()];

    final result = await coordinator.migrateIfNeeded();

    expect(result.status, KeptMigrationStatus.migrated);
    expect(keptStateStore.envelope!.activeRecords.single.id, 'original-1');
  });

  test(
      '62. a retry after a successful envelope write recognizes the equal '
      'envelope and does not replace again', () async {
    final item = FavoriteItem(
      id: 'retry-1',
      date: '2026-01-01T09:00:00.000Z',
      text: 'Retry entry.',
    );
    legacy.entries = [item.encode()];
    final coordinator = buildCoordinator();

    // Drive through the snapshot + envelope write, then fail on the 3rd
    // journal save — the transition to verified — so the envelope replace
    // has already succeeded once before the failure.
    final wrappedJournalStore = _CountingFailOnNthSaveJournalStore(
        inner: journalStore, failOnSaveNumber: 3);
    final firstAttempt = KeptMigrationCoordinator(
      legacyFavoritesStore: legacy,
      journalStore: wrappedJournalStore,
      artifactStore: artifactStore,
      keptStateStore: keptStateStore,
      migrationIdFactory: () => migrationId,
      clock: () => startedAt,
    );
    await expectLater(
      firstAttempt.migrateIfNeeded(),
      throwsA(isA<KeptMigrationException>()),
    );
    expect(keptStateStore.replaceCallCount, 1);

    final result = await coordinator.migrateIfNeeded();

    expect(result.status, KeptMigrationStatus.migrated);
    expect(keptStateStore.replaceCallCount, 1); // never called again.
  });

  test('63. a retry refuses a different existing envelope', () async {
    legacy.entries = ['2026-01-01T09:00:00.000Z|||text'];
    keptStateStore.envelope = KeptStateEnvelope(activeRecords: [
      KeptRecord(
        id: 'unrelated',
        revealId: revealIdFor('unrelated'),
        wisdomText: 'Unrelated pre-existing record.',
        revealedAt: startedAt,
        keptAt: startedAt,
        updatedAt: startedAt,
        mutationId: mutationIdFor('unrelated'),
      ),
    ]);
    // Force the not-started case (c) to be bypassed by pre-seeding a
    // writing journal directly instead, so we reach the mismatch check in
    // _handleWriting rather than the earlier unexpected-existing check.
    journalStore.journal = KeptMigrationJournal(
      state: KeptMigrationState.writing,
      migrationId: migrationId,
      startedAt: startedAt,
      updatedAt: startedAt,
    );
    final coordinator = buildCoordinator();

    await expectLater(
      coordinator.migrateIfNeeded(),
      throwsA(isA<KeptMigrationException>()),
    );
    expect(legacy.entries, isNotNull);
  });

  test('64. the complete state is idempotent', () async {
    final item = FavoriteItem(
      id: 'done-1',
      date: '2026-01-01T09:00:00.000Z',
      text: 'Already migrated.',
    );
    legacy.entries = [item.encode()];
    final coordinator = buildCoordinator();
    final first = await coordinator.migrateIfNeeded();
    expect(first.status, KeptMigrationStatus.migrated);

    final second = await coordinator.migrateIfNeeded();

    expect(second.status, KeptMigrationStatus.alreadyComplete);
    expect(second.migratedCount, first.migratedCount);
  });

  test('65. a completed journal with a reappeared legacy key blocks', () async {
    final item = FavoriteItem(
      id: 'done-1',
      date: '2026-01-01T09:00:00.000Z',
      text: 'Already migrated.',
    );
    legacy.entries = [item.encode()];
    final coordinator = buildCoordinator();
    await coordinator.migrateIfNeeded();
    expect(journalStore.journal!.state, KeptMigrationState.complete);

    // Legacy data reappears (e.g. an unsupported downgrade/upgrade cycle).
    legacy.entries = ['2026-02-01T00:00:00.000Z|||reappeared'];

    await expectLater(
      coordinator.migrateIfNeeded(),
      throwsA(isA<KeptMigrationException>()),
    );
  });

  test('66. a field-by-field mismatch blocks cleanup', () async {
    legacy.entries = ['2026-01-01T09:00:00.000Z|||text'];
    legacy.removeShouldFail = true;
    final coordinator = buildCoordinator();

    // Drive to verified: cleanup is attempted and fails, so the journal
    // stops at verified without ever reaching complete.
    await expectLater(
      coordinator.migrateIfNeeded(),
      throwsA(isA<KeptMigrationException>()),
    );
    expect(journalStore.journal!.state, KeptMigrationState.verified);
    expect(legacy.removeCallCount, 1);

    // Corrupt the protected envelope so it no longer matches the frozen
    // snapshot's reconstruction, and allow removal to succeed if reached.
    legacy.removeShouldFail = false;
    keptStateStore.envelope = KeptStateEnvelope();

    await expectLater(
      coordinator.migrateIfNeeded(),
      throwsA(isA<KeptMigrationException>()),
    );
    // Cleanup must not be attempted again: the field-by-field mismatch is
    // caught before the cleanup step is ever reached.
    expect(legacy.removeCallCount, 1);
  });

  test('67. usable/corrupt counts are verified against the journal', () async {
    legacy.entries = ['2026-01-01T09:00:00.000Z|||text'];
    legacy.removeShouldFail = true;
    final coordinator = buildCoordinator();
    await expectLater(
      coordinator.migrateIfNeeded(),
      throwsA(isA<KeptMigrationException>()),
    );
    expect(journalStore.journal!.state, KeptMigrationState.verified);

    // Tamper with the persisted journal's counts to claim a legacy count
    // that does not match the frozen snapshot's actual entry count, while
    // remaining internally self-consistent (usable + corrupt == legacy) so
    // the tampered value itself still passes the model's own invariant.
    journalStore.journal = journalStore.journal!.copyWith(
      legacyEntryCount: 2,
      usableEntryCount: 2,
    );
    legacy.removeShouldFail = false;

    await expectLater(
      coordinator.migrateIfNeeded(),
      throwsA(isA<KeptMigrationException>()),
    );
  });

  test('68. active-record order is preserved from the original StringList',
      () async {
    final items = [
      FavoriteItem(id: 'a', date: '2026-01-01T09:00:00.000Z', text: 'A'),
      FavoriteItem(id: 'b', date: '2026-01-02T09:00:00.000Z', text: 'B'),
      FavoriteItem(id: 'c', date: '2026-01-03T09:00:00.000Z', text: 'C'),
    ];
    legacy.entries = items.map((i) => i.encode()).toList();
    final coordinator = buildCoordinator();

    await coordinator.migrateIfNeeded();

    expect(
      keptStateStore.envelope!.activeRecords.map((r) => r.id).toList(),
      ['a', 'b', 'c'],
    );
  });

  test(
      '69. more than three Kept items are preserved with no free-limit '
      'truncation', () async {
    final items = List.generate(
      7,
      (i) => FavoriteItem(
        id: 'item-$i',
        date: '2026-01-0${i + 1}T09:00:00.000Z',
        text: 'Entry $i',
      ),
    );
    legacy.entries = items.map((i) => i.encode()).toList();
    final coordinator = buildCoordinator();

    final result = await coordinator.migrateIfNeeded();

    expect(result.migratedCount, 7);
    expect(keptStateStore.envelope!.activeRecords.length, 7);
  });

  test('70. the coordinator serializes concurrent migration calls', () async {
    final item = FavoriteItem(
      id: 'concurrent-1',
      date: '2026-01-01T09:00:00.000Z',
      text: 'Concurrent entry.',
    );
    legacy.entries = [item.encode()];
    final coordinator = buildCoordinator();

    final results = await Future.wait([
      coordinator.migrateIfNeeded(),
      coordinator.migrateIfNeeded(),
    ]);

    final statuses = results.map((r) => r.status).toSet();
    expect(
      statuses,
      anyOf(
        {KeptMigrationStatus.migrated},
        {KeptMigrationStatus.migrated, KeptMigrationStatus.alreadyComplete},
      ),
    );
    expect(legacy.entries, isNull);
    expect(journalStore.journal!.state, KeptMigrationState.complete);
  });

  group('fallback identity: exact Build 25 algorithm, index-dependent', () {
    test(
        '5. migration assigns each record the fallback ID for its own '
        'frozen snapshot index', () async {
      const rawX = '2026-01-01T09:00:00.000Z|||No explicit id, first.';
      const rawY = '2026-01-02T09:00:00.000Z|||No explicit id, second.';
      legacy.entries = [rawX, rawY];
      final coordinator = buildCoordinator();

      final result = await coordinator.migrateIfNeeded();

      expect(result.status, KeptMigrationStatus.migrated);
      final ids =
          keptStateStore.envelope!.activeRecords.map((r) => r.id).toList();
      expect(
          ids[0], StoredFavoriteEntryCodec.fallbackIdFor(raw: rawX, index: 0));
      expect(
          ids[1], StoredFavoriteEntryCodec.fallbackIdFor(raw: rawY, index: 1));
      // The coordinator never invents its own index-only scheme.
      expect(ids[0], isNot('legacy-favorite-0'));
      expect(ids[1], isNot('legacy-favorite-1'));
      expect(ids[0], startsWith('legacy-v1-0-'));
      expect(ids[1], startsWith('legacy-v1-1-'));
    });

    test(
        '6. a retry from the frozen snapshot produces identical IDs even '
        'if SharedPreferences order later changes', () async {
      const rawX = '2026-01-01T09:00:00.000Z|||First entry.';
      const rawY = '2026-01-02T09:00:00.000Z|||Second entry.';
      legacy.entries = [rawX, rawY];
      final expectedIdXAt0 =
          StoredFavoriteEntryCodec.fallbackIdFor(raw: rawX, index: 0);
      final expectedIdYAt1 =
          StoredFavoriteEntryCodec.fallbackIdFor(raw: rawY, index: 1);

      // Fail after the snapshot is captured (and thus frozen) but before
      // the migration finishes, forcing a retry.
      keptStateStore.replaceShouldFail = true;
      final coordinator = buildCoordinator();
      await expectLater(
        coordinator.migrateIfNeeded(),
        throwsA(isA<KeptMigrationException>()),
      );
      keptStateStore.replaceShouldFail = false;

      // SharedPreferences now reports the same two entries in reversed
      // order — as if something external re-wrote the StringList. The
      // frozen snapshot must be used instead, so the retry must not
      // recompute fallback IDs against this new order.
      legacy.entries = [rawY, rawX];

      final result = await coordinator.migrateIfNeeded();

      expect(result.status, KeptMigrationStatus.migrated);
      final ids =
          keptStateStore.envelope!.activeRecords.map((r) => r.id).toList();
      expect(ids, [expectedIdXAt0, expectedIdYAt1]);
    });

    test(
        '8. an explicit stored FavoriteItem.id is preserved unchanged and '
        'never replaced by the fallback path', () async {
      final item = FavoriteItem(
        id: 'explicit-stored-id',
        date: '2026-01-01T09:00:00.000Z',
        text: 'Has its own id already.',
      );
      legacy.entries = [item.encode()];
      final coordinator = buildCoordinator();

      final result = await coordinator.migrateIfNeeded();

      expect(result.status, KeptMigrationStatus.migrated);
      final migratedId = keptStateStore.envelope!.activeRecords.single.id;
      expect(migratedId, 'explicit-stored-id');
      expect(migratedId, isNot(startsWith('legacy-v1-')));
    });
  });

  group('complete-state full re-verification', () {
    Future<KeptMigrationResult> migrateOnceCleanly() async {
      final item = FavoriteItem(
        id: 'complete-1',
        date: '2026-01-01T09:00:00.000Z',
        text: 'Complete entry.',
      );
      legacy.entries = [item.encode()];
      final coordinator = buildCoordinator();
      final result = await coordinator.migrateIfNeeded();
      expect(result.status, KeptMigrationStatus.migrated);
      expect(journalStore.journal!.state, KeptMigrationState.complete);
      return result;
    }

    test('complete state with valid metadata returns alreadyComplete',
        () async {
      await migrateOnceCleanly();
      final coordinator = buildCoordinator();

      final result = await coordinator.migrateIfNeeded();

      expect(result.status, KeptMigrationStatus.alreadyComplete);
      expect(result.migratedCount, 1);
    });

    test('complete state with a reappeared legacy key blocks', () async {
      await migrateOnceCleanly();
      legacy.entries = ['2026-02-01T00:00:00.000Z|||reappeared'];
      final coordinator = buildCoordinator();

      await expectLater(
        coordinator.migrateIfNeeded(),
        throwsA(isA<KeptMigrationException>()),
      );
    });

    test('complete state with a missing snapshot blocks', () async {
      await migrateOnceCleanly();
      artifactStore.snapshots.clear();
      final coordinator = buildCoordinator();

      await expectLater(
        coordinator.migrateIfNeeded(),
        throwsA(isA<KeptMigrationException>()),
      );
    });

    test('complete state with a snapshot migrationId mismatch blocks',
        () async {
      await migrateOnceCleanly();
      final fileName = journalStore.journal!.snapshotFileName!;
      final original = artifactStore.snapshots[fileName]!;
      artifactStore.snapshots[fileName] = KeptMigrationSnapshot(
        migrationId: '223e4567-e89b-4d3a-a456-426614174099',
        capturedAt: original.capturedAt,
        legacyKey: original.legacyKey,
        entries: original.entries,
      );
      final coordinator = buildCoordinator();

      await expectLater(
        coordinator.migrateIfNeeded(),
        throwsA(isA<KeptMigrationException>()),
      );
    });

    test('complete state with a journal count mismatch blocks', () async {
      await migrateOnceCleanly();
      journalStore.journal = journalStore.journal!
          .copyWith(legacyEntryCount: 2, usableEntryCount: 2);
      final coordinator = buildCoordinator();

      await expectLater(
        coordinator.migrateIfNeeded(),
        throwsA(isA<KeptMigrationException>()),
      );
    });

    test('complete state with a changed protected envelope blocks', () async {
      await migrateOnceCleanly();
      keptStateStore.envelope = KeptStateEnvelope();
      final coordinator = buildCoordinator();

      await expectLater(
        coordinator.migrateIfNeeded(),
        throwsA(isA<KeptMigrationException>()),
      );
    });

    test('complete state with changed record order blocks', () async {
      final itemA = FavoriteItem(
        id: 'order-a',
        date: '2026-01-01T09:00:00.000Z',
        text: 'A',
      );
      final itemB = FavoriteItem(
        id: 'order-b',
        date: '2026-01-02T09:00:00.000Z',
        text: 'B',
      );
      legacy.entries = [itemA.encode(), itemB.encode()];
      final coordinator = buildCoordinator();
      final result = await coordinator.migrateIfNeeded();
      expect(result.status, KeptMigrationStatus.migrated);

      keptStateStore.envelope = KeptStateEnvelope(
        activeRecords: keptStateStore.envelope!.activeRecords.reversed.toList(),
      );

      await expectLater(
        coordinator.migrateIfNeeded(),
        throwsA(isA<KeptMigrationException>()),
      );
    });

    test('complete state with a changed individual KeptRecord field blocks',
        () async {
      await migrateOnceCleanly();
      final original = keptStateStore.envelope!.activeRecords.single;
      keptStateStore.envelope = KeptStateEnvelope(
        activeRecords: [
          original.copyWith(reflectionText: 'Tampered after completion.'),
        ],
      );
      final coordinator = buildCoordinator();

      await expectLater(
        coordinator.migrateIfNeeded(),
        throwsA(isA<KeptMigrationException>()),
      );
    });

    test('complete state requiring a missing recovery artifact blocks',
        () async {
      legacy.entries = ['not decodable at all'];
      final coordinator = buildCoordinator();
      final result = await coordinator.migrateIfNeeded();
      expect(result.status, KeptMigrationStatus.migrated);
      expect(result.corruptCount, 1);

      artifactStore.recoveryArtifacts.clear();

      await expectLater(
        coordinator.migrateIfNeeded(),
        throwsA(isA<KeptMigrationException>()),
      );
    });

    test('complete state with a mismatched recovery raw entry blocks',
        () async {
      legacy.entries = ['not decodable at all'];
      final coordinator = buildCoordinator();
      final result = await coordinator.migrateIfNeeded();
      expect(result.status, KeptMigrationStatus.migrated);

      final fileName = journalStore.journal!.recoveryFileName!;
      final original = artifactStore.recoveryArtifacts[fileName]!;
      artifactStore.recoveryArtifacts[fileName] = KeptMigrationRecoveryArtifact(
        migrationId: original.migrationId,
        createdAt: original.createdAt,
        legacyEntryCount: original.legacyEntryCount,
        usableEntryCount: original.usableEntryCount,
        corruptEntries: [
          KeptMigrationRecoveryEntry(
            index: original.corruptEntries.single.index,
            rawValue: 'a completely different raw value',
            stage: original.corruptEntries.single.stage,
            reasonCode: original.corruptEntries.single.reasonCode,
          ),
        ],
      );

      await expectLater(
        coordinator.migrateIfNeeded(),
        throwsA(isA<KeptMigrationException>()),
      );
    });

    test(
        'a journal with corruptCount zero and a non-null recoveryFileName '
        'cannot even be constructed, so this combination can never reach '
        'the coordinator', () async {
      await migrateOnceCleanly();
      expect(journalStore.journal!.corruptEntryCount, 0);
      expect(journalStore.journal!.recoveryFileName, isNull);

      // KeptMigrationJournal's own constructor enforces
      // "recoveryFileName present iff corruptEntryCount > 0" unconditionally
      // (see kept_migration_models_test.dart, "journal count invariants are
      // enforced") — so a tampered journal claiming corruptEntryCount: 0
      // together with a recoveryFileName cannot exist as a valid
      // KeptMigrationJournal instance in the first place.
      expect(
        () => KeptMigrationJournal(
          state: KeptMigrationState.complete,
          migrationId: journalStore.journal!.migrationId,
          startedAt: journalStore.journal!.startedAt,
          updatedAt: journalStore.journal!.updatedAt,
          legacyEntryCount: journalStore.journal!.legacyEntryCount,
          usableEntryCount: journalStore.journal!.usableEntryCount,
          corruptEntryCount: 0,
          snapshotFileName: journalStore.journal!.snapshotFileName,
          recoveryFileName: 'east_kept_migration_recovery_v1-fake.json',
        ),
        throwsFormatException,
      );
    });
  });

  // Every fixture above this group predates the FavoriteItem.date hotfix and
  // deliberately uses ISO-8601 `date` values, either to test ISO
  // compatibility specifically or because it was written before the real
  // production date shape was identified — those are left exactly as they
  // are (see the correction report accompanying this change). This group
  // adds the real Build 25 production shape: an English "MMMM d, yyyy"
  // display string, exactly what `formattedToday()` /
  // `HomeScreen.toggleFavorite` actually write. Before the hotfix, every one
  // of these entries would have failed `DateTime.parse` and been classified
  // as a convert-stage corrupt entry instead of migrating as active Kept
  // wisdom.
  group('real Build 25 production display-date migration', () {
    test(
        '14. a current-schema FavoriteItem with the real production '
        'display-date shape migrates to one active KeptRecord', () async {
      final item = FavoriteItem(
        id: 'display-date-1',
        date: 'August 1, 2026',
        text: 'A real Kept wisdom.',
      );
      legacy.entries = [item.encode()];
      final coordinator = buildCoordinator();

      final result = await coordinator.migrateIfNeeded();

      expect(result.status, KeptMigrationStatus.migrated);
      expect(result.migratedCount, 1);
      expect(result.corruptCount, 0);
      final record = keptStateStore.envelope!.activeRecords.single;
      expect(record.id, 'display-date-1');
      expect(record.wisdomText, 'A real Kept wisdom.');
      expect(record.revealedAt, DateTime.utc(2026, 8, 1, 12));
      expect(record.keptAt, DateTime.utc(2026, 8, 1, 12));
    });

    test(
        '15. a legacy pipe entry with the real production display-date '
        'shape migrates to one active KeptRecord', () async {
      legacy.entries = ['June 20, 2026|||A legacy pipe-format wisdom.'];
      final coordinator = buildCoordinator();

      final result = await coordinator.migrateIfNeeded();

      expect(result.status, KeptMigrationStatus.migrated);
      expect(result.migratedCount, 1);
      expect(result.corruptCount, 0);
      final record = keptStateStore.envelope!.activeRecords.single;
      expect(record.wisdomText, 'A legacy pipe-format wisdom.');
      expect(record.revealedAt, DateTime.utc(2026, 6, 20, 12));
    });

    test('16. a real display-date entry is not added to the recovery artifact',
        () async {
      final item = FavoriteItem(
        id: 'no-recovery-1',
        date: 'December 31, 2025',
        text: 'Should migrate cleanly.',
      );
      legacy.entries = [item.encode()];
      final coordinator = buildCoordinator();

      await coordinator.migrateIfNeeded();

      expect(journalStore.journal!.recoveryFileName, isNull);
      expect(artifactStore.recoveryArtifacts, isEmpty);
    });

    test(
        '17. a display-date record with a reflection preserves '
        'reflectionText, reflectedAt, and the existing updatedAt rule',
        () async {
      final item = FavoriteItem(
        id: 'reflected-1',
        date: 'August 1, 2026',
        text: 'Reflected wisdom.',
        reflection: 'What stayed with me.',
        reflectedAt: '2026-08-02T10:00:00.000Z',
      );
      legacy.entries = [item.encode()];
      final coordinator = buildCoordinator();

      await coordinator.migrateIfNeeded();

      final record = keptStateStore.envelope!.activeRecords.single;
      expect(record.reflectionText, 'What stayed with me.');
      expect(record.reflectedAt, DateTime.utc(2026, 8, 2, 10));
      // reflectedAt (Aug 2, 10:00 UTC) is after keptAt (Aug 1, 12:00 UTC
      // noon), so updatedAt must equal reflectedAt per the existing,
      // unchanged rule in _convertToKeptRecord.
      expect(record.updatedAt, DateTime.utc(2026, 8, 2, 10));
    });

    test('18. multiple real display-date records preserve original order',
        () async {
      final items = [
        FavoriteItem(id: 'a', date: 'January 1, 2026', text: 'A'),
        FavoriteItem(id: 'b', date: 'February 2, 2026', text: 'B'),
        FavoriteItem(id: 'c', date: 'March 3, 2026', text: 'C'),
      ];
      legacy.entries = items.map((i) => i.encode()).toList();
      final coordinator = buildCoordinator();

      await coordinator.migrateIfNeeded();

      expect(
        keptStateStore.envelope!.activeRecords.map((r) => r.id).toList(),
        ['a', 'b', 'c'],
      );
    });

    test('19. mixed real display-date and ISO-date records both migrate',
        () async {
      final displayItem = FavoriteItem(
        id: 'display-1',
        date: 'May 5, 2026',
        text: 'Display-dated.',
      );
      final isoItem = FavoriteItem(
        id: 'iso-1',
        date: '2026-01-01T09:00:00.000Z',
        text: 'ISO-dated.',
      );
      legacy.entries = [displayItem.encode(), isoItem.encode()];
      final coordinator = buildCoordinator();

      final result = await coordinator.migrateIfNeeded();

      expect(result.status, KeptMigrationStatus.migrated);
      expect(result.migratedCount, 2);
      expect(result.corruptCount, 0);
      final records = keptStateStore.envelope!.activeRecords;
      expect(records[0].revealedAt, DateTime.utc(2026, 5, 5, 12));
      expect(records[1].revealedAt, DateTime.utc(2026, 1, 1, 9));
    });

    test(
        '20. a malformed date remains an ordinary corrupt entry, preserved '
        'exactly in the protected recovery artifact', () async {
      final malformed = FavoriteItem(
        id: 'bad-date-1',
        date: 'Blorptober 40, 2026',
        text: 'Has an impossible date.',
      );
      legacy.entries = [malformed.encode()];
      final coordinator = buildCoordinator();

      final result = await coordinator.migrateIfNeeded();

      expect(result.status, KeptMigrationStatus.migrated);
      expect(result.migratedCount, 0);
      expect(result.corruptCount, 1);
      final artifact = artifactStore.recoveryArtifacts[recoveryFileName()]!;
      expect(artifact.corruptEntries.single.rawValue, malformed.encode());
      expect(
        artifact.corruptEntries.single.stage,
        KeptMigrationFailureStage.convert,
      );
      expect(
        artifact.corruptEntries.single.reasonCode,
        'kept_record_validation_failed',
      );
    });

    test(
        '21. a migration containing only valid real display dates has no '
        'corrupt entries and produces a non-empty active envelope', () async {
      final items = [
        FavoriteItem(id: 'x', date: 'July 4, 2026', text: 'X'),
        FavoriteItem(id: 'y', date: 'September 9, 2026', text: 'Y'),
      ];
      legacy.entries = items.map((i) => i.encode()).toList();
      final coordinator = buildCoordinator();

      await coordinator.migrateIfNeeded();

      expect(journalStore.journal!.legacyEntryCount, 2);
      expect(journalStore.journal!.usableEntryCount, 2);
      expect(journalStore.journal!.corruptEntryCount, 0);
      expect(journalStore.journal!.recoveryFileName, isNull);
      expect(keptStateStore.envelope!.activeRecords, isNotEmpty);
      expect(keptStateStore.envelope!.activeRecords, hasLength(2));
    });

    test('22. a successful real display-date migration reaches complete',
        () async {
      final item = FavoriteItem(id: 'z', date: 'October 10, 2026', text: 'Z');
      legacy.entries = [item.encode()];
      final coordinator = buildCoordinator();

      await coordinator.migrateIfNeeded();

      expect(journalStore.journal!.state, KeptMigrationState.complete);
    });

    test(
        '23. the legacy favorites key is removed only after the active '
        'envelope containing real display-date records is verified', () async {
      final item = FavoriteItem(id: 'w', date: 'November 11, 2026', text: 'W');
      legacy.entries = [item.encode()];
      keptStateStore.replaceShouldFail = true;
      final coordinator = buildCoordinator();

      await expectLater(
        coordinator.migrateIfNeeded(),
        throwsA(isA<KeptMigrationException>()),
      );
      // Envelope replace failed, so verified was never reached: the legacy
      // key must still be present and removeAndVerify must never have been
      // called.
      expect(legacy.entries, isNotNull);
      expect(legacy.removeCallCount, 0);

      keptStateStore.replaceShouldFail = false;
      final result = await coordinator.migrateIfNeeded();

      expect(result.status, KeptMigrationStatus.migrated);
      expect(legacy.entries, isNull);
      expect(legacy.removeCallCount, 1);
    });

    test(
        '24. retry from writing using the frozen snapshot reconstructs the '
        'identical UTC-noon envelope for a real display-date record', () async {
      final item = FavoriteItem(
        id: 'retry-date-1',
        date: 'April 4, 2026',
        text: 'Retry me.',
      );
      legacy.entries = [item.encode()];
      keptStateStore.replaceShouldFail = true;
      final coordinator = buildCoordinator();

      await expectLater(
        coordinator.migrateIfNeeded(),
        throwsA(isA<KeptMigrationException>()),
      );
      keptStateStore.replaceShouldFail = false;

      // SharedPreferences changes underneath the migration after the
      // snapshot was already frozen.
      legacy.entries = ['December 12, 2026|||Changed after snapshot.'];

      final result = await coordinator.migrateIfNeeded();

      expect(result.status, KeptMigrationStatus.migrated);
      final record = keptStateStore.envelope!.activeRecords.single;
      expect(record.id, 'retry-date-1');
      expect(record.revealedAt, DateTime.utc(2026, 4, 4, 12));
    });

    test(
        '25. complete-state re-verification succeeds for a real '
        'display-date migration', () async {
      final item = FavoriteItem(
        id: 'verify-1',
        date: 'May 15, 2026',
        text: 'Verify me.',
      );
      legacy.entries = [item.encode()];
      final coordinator = buildCoordinator();
      await coordinator.migrateIfNeeded();

      final result = await coordinator.migrateIfNeeded();

      expect(result.status, KeptMigrationStatus.alreadyComplete);
      expect(result.migratedCount, 1);
    });

    test(
        '26. complete-state re-verification detects a changed parsed '
        'timestamp', () async {
      final item = FavoriteItem(
        id: 'tamper-1',
        date: 'June 6, 2026',
        text: 'Tamper me.',
      );
      legacy.entries = [item.encode()];
      final coordinator = buildCoordinator();
      await coordinator.migrateIfNeeded();

      final original = keptStateStore.envelope!.activeRecords.single;
      keptStateStore.envelope = KeptStateEnvelope(
        activeRecords: [
          KeptRecord(
            id: original.id,
            revealId: original.revealId,
            wisdomText: original.wisdomText,
            // Tampered: a different revealedAt/keptAt than what re-parsing
            // "June 6, 2026" via the frozen snapshot would reproduce.
            // updatedAt is shifted by the same amount so it never falls
            // before the tampered keptAt (KeptRecord's own invariant) —
            // the point being verified is the mismatched revealedAt/keptAt,
            // not an unrelated updatedAt-before-keptAt violation.
            revealedAt: original.revealedAt.add(const Duration(days: 1)),
            keptAt: original.revealedAt.add(const Duration(days: 1)),
            updatedAt: original.updatedAt.add(const Duration(days: 1)),
            mutationId: original.mutationId,
          ),
        ],
      );

      await expectLater(
        coordinator.migrateIfNeeded(),
        throwsA(isA<KeptMigrationException>()),
      );
    });
  });
}

/// Thin journal-store wrapper that fails only on the Nth call to [save],
/// used to simulate a persistence failure at a precise point in the
/// migration state machine without needing arbitrary timing.
class _CountingFailOnNthSaveJournalStore implements KeptMigrationJournalStore {
  _CountingFailOnNthSaveJournalStore({
    required this.inner,
    required this.failOnSaveNumber,
  });

  final KeptMigrationJournalStore inner;
  final int failOnSaveNumber;
  int _saveCount = 0;

  @override
  Future<KeptMigrationJournal?> load() => inner.load();

  @override
  Future<void> save(KeptMigrationJournal journal) async {
    _saveCount += 1;
    if (_saveCount == failOnSaveNumber) {
      throw StateError('Simulated journal save failure at call $_saveCount.');
    }
    await inner.save(journal);
  }
}
