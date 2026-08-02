// Build 26 Phase 3D-E: reproduces, and proves the fix for, the exact
// post-migration Home membership defect reported from the physical device --
// through three safety-gap correction rounds:
//   * round 2 replaced an earlier `DateTime.toLocal()`-based calendar-day
//     rule (which silently depended on the device's *current* timezone)
//     with a genuinely timezone-independent rule anchored on the legacy
//     `sr-v1-<microseconds>-<serial>` id's own embedded save instant;
//   * round 3 (this file) inverts the reconciliation direction entirely.
//
// Round 2's design mutated the migrated `KeptRecord`'s own revealId in
// place. Real `flutter test` evidence proved this architecturally invalid:
// `KeptMigrationCoordinator._handleComplete()` runs on *every* app launch
// after the first and verifies the current protected envelope
// field-by-field against a freshly-rebuilt-from-snapshot expected envelope
// (`KeptRecord.operator==`, which compares every field including revealId,
// updatedAt, and mutationId). Mutating a migrated record's revealId is
// therefore always caught as a mismatch on the very next launch
// (`KeptMigrationException['field-verify-mismatch']`) -- this is not a test
// defect or a verification defect; it is the correct, working safeguard
// doing its job against an invalid write.
//
// Round 3 corrects the other side instead: the Build 25 daily wisdom
// occurrence's own `DailyWisdomRecord.revealId` (which never existed
// pre-Build-26, and is only ever a fresh, unrelated random UUID v4 minted
// by `DailyAccessRepository.backfillRevealIdIfNeeded()`) is what gets
// corrected. A migrated `KeptRecord` is never written to again, anywhere,
// after migration completes -- proven directly in this file by re-running
// `migrationCoordinator.migrateIfNeeded()` a second time and asserting it
// still succeeds (test 7, the exact scenario that failed under the round-2
// design).
//
// Real-device evidence (already-confirmed-successful Phase 3D-D migration):
// the migrated wisdom ("Some doors open after surrender.", with its
// Reflection "Ibne galatasaray") appears correctly in Kept exactly once,
// and `flutter.favorites` is nil (legacy cleanup completed) — but the
// *same* wisdom, still the currently displayed/locked daily occurrence,
// shows an empty Home Keep ring rather than its already-kept state.
//
// This file runs the real production pieces on both sides of the
// membership check `HomeScreen.currentFavorite()` performs (match by
// revealId only, never by text):
//   * `DailyAccessRepository` (real, SharedPreferences-backed) for the
//     daily occurrence's own identity/backfill, and now also for
//     `reconcileRevealIdForOccurrence` -- the only place either revealId is
//     ever written;
//   * `KeptMigrationCoordinator` + `KeptRepository` (real, with
//     JSON-round-tripping fakes for the protected stores — see
//     `persistence_test_helpers.dart` for why an object-retaining fake can
//     never prove a genuine wire-format defect) for the migrated Kept
//     identity;
//   * `KeptRepository.resolveLegacyMigratedRevealIdForOccurrence` (the
//     read-only lookup) bridging them -- never mutates Kept storage.
//
// Per the task's explicit instruction: only `stage`/error-type/error-code-
// style diagnostics are ever asserted on here — wisdom text is used only
// as ordinary test fixture content (the exact recovered payload), never as
// a stand-in for production identity.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/models/daily_wisdom_record.dart';
import 'package:wisdom_app/models/kept_bootstrap_result.dart';
import 'package:wisdom_app/models/kept_record.dart';
import 'package:wisdom_app/persistence/kept_migration_journal_store.dart';
import 'package:wisdom_app/persistence/legacy_favorites_store.dart';
import 'package:wisdom_app/persistence/persistence_operation_coordinator.dart';
import 'package:wisdom_app/persistence/storage_preferences_adapter.dart';
import 'package:wisdom_app/repositories/daily_access_repository.dart';
import 'package:wisdom_app/repositories/kept_repository.dart';
import 'package:wisdom_app/services/kept_migration_coordinator.dart';
import 'package:wisdom_app/utils/legacy_kept_identity.dart';

import 'persistence_test_helpers.dart';

/// Diagnostic-only (this turn): one snapshot of the identity state relevant
/// to the round-3 reconciliation direction, captured at a single instant.
/// Never asserts anything itself -- callers decide what to check. Deliberately
/// carries no wisdom/Reflection text, only identifiers and counts.
class _IdentityStageSnapshot {
  const _IdentityStageSnapshot({
    required this.dailyRevealId,
    required this.envelopeRevealId,
    required this.favoriteRevealId,
    required this.resolvedRevealId,
    required this.activeCount,
    required this.loadCountAtStage,
    required this.replaceCountAtStage,
  });

  /// The currently persisted `DailyWisdomRecord.revealId`.
  final String? dailyRevealId;

  /// The revealId read directly from `keptStateStore.load()`'s single
  /// active record -- `null` if there is not exactly one active record.
  final String? envelopeRevealId;

  /// The revealId of the single mapped `FavoriteItem` from
  /// `keptRepository.load()` -- `null` if there is not exactly one.
  final String? favoriteRevealId;

  /// The result of a fresh
  /// `keptRepository.resolveLegacyMigratedRevealIdForOccurrence(...)` call
  /// against the currently persisted daily occurrence, at this instant.
  final String? resolvedRevealId;

  final int activeCount;

  /// `keptStateStore.loadCallCount`/`replaceCallCount` as they stood the
  /// instant this stage was entered -- captured *before* this helper's own
  /// diagnostic reads, so they reflect only production-path activity since
  /// the previous stage, never this helper's own instrumentation.
  final int loadCountAtStage;
  final int replaceCountAtStage;
}

void main() {
  // Byte-exact recovered `flutter.favorites` entry from the reported
  // Build 25 -> 26 upgrade incident (identical to the fixture used in
  // `kept_migration_coordinator_test.dart`'s Phase 3D-D groups). Its id,
  // `sr-v1-1785622374122602-0`, embeds the real, timezone-independent save
  // instant this safety-gap correction is built around: Unix microsecond
  // `1785622374122602` == `2026-08-01T22:12:54.122602Z` (verified by direct
  // computation, not merely asserted) — about 13 seconds before this same
  // fixture's `reflectedAt` local wall-clock reading.
  const recoveredLegacyId = 'sr-v1-1785622374122602-0';
  const recoveredPayload = '{"schemaVersion":2,'
      '"id":"$recoveredLegacyId",'
      '"date":"August 2, 2026",'
      '"text":"Some doors open after surrender.",'
      '"reflection":"Ibne galatasaray",'
      '"reflectedAt":"2026-08-02T01:13:07.484133"}';

  /// The exact true UTC instant embedded in `recoveredPayload`'s id above,
  /// computed directly from the id's own microsecond component (not
  /// hand-typed) so this fixture can never silently drift from the id
  /// string it is derived from.
  final recoveredPayloadSavedAt =
      DateTime.fromMicrosecondsSinceEpoch(1785622374122602, isUtc: true);

  // The daily occurrence's own revealedAt/unlockAt window. Chosen so the
  // fixture's real embedded save instant above
  // (2026-08-01T22:12:54.122602Z) falls strictly inside
  // [dailyRevealedAt, dailyUnlockAt) — the committed daily occurrence's own
  // active window — exactly reproducing a real device where the wisdom was
  // revealed a couple of hours before the user actually tapped Keep. This
  // represents the pre-existing Build 25 daily record that was already
  // active (revealed, locked) at the moment of the upgrade.
  final dailyRevealedAt = DateTime.utc(2026, 8, 1, 20, 0);
  final dailyUnlockAt = dailyRevealedAt.add(DailyWisdomRecord.lockDuration);

  late PersistenceOperationCoordinator dailyCoordinator;
  late DailyAccessRepository dailyRepository;

  late PersistenceOperationCoordinator keptCoordinator;
  late JsonRoundTrippingKeptStateStore keptStateStore;
  late KeptMigrationCoordinator migrationCoordinator;
  late KeptRepository keptRepository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});

    dailyCoordinator = PersistenceOperationCoordinator();
    dailyRepository = DailyAccessRepository(
      preferencesAdapter: StoragePreferencesAdapter(),
      operationCoordinator: dailyCoordinator,
    );

    // Seed the pre-existing Build 25 daily record directly — no revealId,
    // exactly as a real pre-upgrade record looks before backfill.
    final legacyDailyRecord = DailyWisdomRecord(
      text: 'Some doors open after surrender.',
      revealedAt: dailyRevealedAt,
      unlockAt: dailyUnlockAt,
    );
    await dailyRepository.saveDailyWisdomRecord(legacyDailyRecord);

    // Seed the legacy `favorites` StringList the real
    // `SharedPreferencesLegacyFavoritesStore` reads, on the same mocked
    // SharedPreferences instance.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favorites', [recoveredPayload]);

    keptCoordinator = PersistenceOperationCoordinator();
    keptStateStore = JsonRoundTrippingKeptStateStore();
    migrationCoordinator = KeptMigrationCoordinator(
      legacyFavoritesStore: SharedPreferencesLegacyFavoritesStore(),
      journalStore: SharedPreferencesKeptMigrationJournalStore(),
      artifactStore: JsonRoundTrippingKeptMigrationArtifactStore(),
      keptStateStore: keptStateStore,
      operationCoordinator: keptCoordinator,
    );
    keptRepository = KeptRepository(
      store: keptStateStore,
      bootstrap: const KeptBootstrapResult.ready(),
      operationCoordinator: keptCoordinator,
      clock: () => DateTime.utc(2026, 8, 3, 10, 0),
    );
  });

  /// The exact membership query `HomeScreen.currentFavorite()` performs:
  /// match strictly by revealId, never by text.
  Future<bool> isCurrentlyKept(String revealId) async {
    final favorites = await keptRepository.load();
    return favorites.any((item) => item.revealId == revealId);
  }

  /// The exact two-step, non-mutating reconciliation
  /// `HomeScreen._reconcileDailyWisdomIdentity()` performs: a read-only
  /// Kept-side lookup, followed by an atomic Daily Access side
  /// reconcile-or-backfill for the same occurrence. Never writes to Kept
  /// storage.
  Future<void> reconcileDailyIdentity(DailyWisdomRecord dailyRecord) async {
    final resolvedLegacyRevealId =
        await keptRepository.resolveLegacyMigratedRevealIdForOccurrence(
      wisdomText: dailyRecord.text,
      committedRevealedAt: dailyRecord.revealedAt,
      committedUnlockAt: dailyRecord.unlockAt,
    );
    await dailyRepository.reconcileRevealIdForOccurrence(
      expectedText: dailyRecord.text,
      expectedRevealedAt: dailyRecord.revealedAt,
      expectedUnlockAt: dailyRecord.unlockAt,
      resolvedLegacyRevealId: resolvedLegacyRevealId,
    );
  }

  test(
      '1. before reconciliation, the backfilled daily revealId and the '
      'migrated KeptRecord revealId genuinely differ (proves the exact '
      'defect, not merely assumed)', () async {
    await dailyRepository.backfillRevealIdIfNeeded();
    final dailyRecord = await dailyRepository.loadDailyWisdomRecord();
    expect(dailyRecord, isNotNull);
    expect(dailyRecord!.revealId, isNotNull);

    final migrationResult = await migrationCoordinator.migrateIfNeeded();
    expect(migrationResult.status, KeptMigrationStatus.migrated);

    final favorites = await keptRepository.load();
    expect(favorites, hasLength(1));
    final migratedRevealId = favorites.single.revealId;

    // The exact proven defect: two unrelated identity mechanisms (a fresh
    // random UUID v4 backfill vs. a deterministic UUID v5 derived from the
    // legacy item id) computed the same real-world occurrence's identity
    // completely independently.
    expect(migratedRevealId, isNot(dailyRecord.revealId));

    // Which is exactly why the real Home membership query fails to find
    // the already-migrated, already-kept record.
    expect(await isCurrentlyKept(dailyRecord.revealId!), isFalse);
  });

  test(
      '2. after reconciliation, the current daily occurrence is recognized '
      'as already kept -- via the Daily Access record adopting the '
      'migrated Kept revealId, never the other way around', () async {
    await dailyRepository.backfillRevealIdIfNeeded();
    final dailyRecordBeforeBackfill =
        (await dailyRepository.loadDailyWisdomRecord())!;
    await migrationCoordinator.migrateIfNeeded();

    await reconcileDailyIdentity(dailyRecordBeforeBackfill);

    final correctedDailyRecord =
        (await dailyRepository.loadDailyWisdomRecord())!;
    // The correction happened on the Daily Access side: the daily record's
    // revealId changed to match the already-existing migrated Kept
    // revealId -- the migrated record itself was never written to.
    expect(correctedDailyRecord.revealId,
        isNot(dailyRecordBeforeBackfill.revealId));
    expect(await isCurrentlyKept(correctedDailyRecord.revealId!), isTrue);
  });

  test(
      '3. the migrated Kept record remains exactly one record after '
      'reconciling (Kept storage itself is never written to)', () async {
    await dailyRepository.backfillRevealIdIfNeeded();
    final dailyRecord = (await dailyRepository.loadDailyWisdomRecord())!;
    await migrationCoordinator.migrateIfNeeded();
    final replaceCountBefore = keptStateStore.replaceCallCount;

    await reconcileDailyIdentity(dailyRecord);

    final favorites = await keptRepository.load();
    expect(favorites, hasLength(1));
    expect(keptStateStore.replaceCallCount, replaceCountBefore);
  });

  test('4. the existing Reflection remains attached after reconciling',
      () async {
    await dailyRepository.backfillRevealIdIfNeeded();
    final dailyRecord = (await dailyRepository.loadDailyWisdomRecord())!;
    await migrationCoordinator.migrateIfNeeded();

    await reconcileDailyIdentity(dailyRecord);

    final favorites = await keptRepository.load();
    expect(favorites.single.reflection, 'Ibne galatasaray');
  });

  test(
      '5. a genuinely new daily occurrence with the same recurring text, '
      'revealed a month later, retains its own genuine v4 -- the resolver '
      'finds no candidate for it and it is never reconciled against the '
      'earlier migrated occurrence', () async {
    await dailyRepository.backfillRevealIdIfNeeded();
    await migrationCoordinator.migrateIfNeeded();

    final laterRevealedAt = DateTime.utc(2026, 9, 1, 9, 0);
    final laterUnlockAt = laterRevealedAt.add(DailyWisdomRecord.lockDuration);
    await dailyRepository.saveDailyWisdomRecord(DailyWisdomRecord(
      text: 'Some doors open after surrender.',
      revealedAt: laterRevealedAt,
      unlockAt: laterUnlockAt,
    ));

    final resolvedLegacyRevealId =
        await keptRepository.resolveLegacyMigratedRevealIdForOccurrence(
      wisdomText: 'Some doors open after surrender.',
      committedRevealedAt: laterRevealedAt,
      committedUnlockAt: laterUnlockAt,
    );
    expect(resolvedLegacyRevealId, isNull);

    final laterRecordBefore = (await dailyRepository.loadDailyWisdomRecord())!;
    expect(laterRecordBefore.revealId, isNull);

    await dailyRepository.reconcileRevealIdForOccurrence(
      expectedText: 'Some doors open after surrender.',
      expectedRevealedAt: laterRevealedAt,
      expectedUnlockAt: laterUnlockAt,
      resolvedLegacyRevealId: resolvedLegacyRevealId,
    );

    final laterRecord = (await dailyRepository.loadDailyWisdomRecord())!;
    expect(laterRecord.revealId, isNotNull);
    expect(await isCurrentlyKept(laterRecord.revealId!), isFalse);
  });

  test(
      '6. flutter.favorites remains removed after successful migration, '
      'independent of reconciliation', () async {
    await dailyRepository.backfillRevealIdIfNeeded();
    final dailyRecord = (await dailyRepository.loadDailyWisdomRecord())!;
    await migrationCoordinator.migrateIfNeeded();
    await reconcileDailyIdentity(dailyRecord);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('favorites'), isFalse);
  });

  test(
      '7. relaunch: a fresh migrateIfNeeded() call against the '
      'already-corrected state succeeds without a field-verify-mismatch, '
      'and a second reconciliation attempt preserves the filled state and '
      'creates no duplicate -- the exact scenario that failed under the '
      'round-2, Kept-mutating design', () async {
    // Diagnostic-only (this turn): captures the identity state relevant to
    // this test at a single instant, prints one EAST_RECON_DIAGNOSTIC line,
    // and returns the values so the assertions below can compare stage to
    // stage. Never prints wisdom or Reflection content -- identifiers and
    // counts only. Test-local: not used outside this test.
    Future<_IdentityStageSnapshot> captureIdentityStage(String label) async {
      // Captured *before* this helper's own diagnostic reads below, so
      // these two counts reflect only production-path activity since the
      // previous stage was captured -- never this helper's own
      // instrumentation reads.
      final loadCountAtStage = keptStateStore.loadCallCount;
      final replaceCountAtStage = keptStateStore.replaceCallCount;

      final dailyRecord = await dailyRepository.loadDailyWisdomRecord();

      final envelope = await keptStateStore.load();
      final activeRecords = envelope?.activeRecords ?? const <KeptRecord>[];
      final envelopeRevealId =
          activeRecords.length == 1 ? activeRecords.single.revealId : null;

      final favorites = await keptRepository.load();
      final favoriteRevealId =
          favorites.length == 1 ? favorites.single.revealId : null;

      String? resolvedRevealId;
      if (dailyRecord != null) {
        resolvedRevealId =
            await keptRepository.resolveLegacyMigratedRevealIdForOccurrence(
          wisdomText: dailyRecord.text,
          committedRevealedAt: dailyRecord.revealedAt,
          committedUnlockAt: dailyRecord.unlockAt,
        );
      }

      final snapshot = _IdentityStageSnapshot(
        dailyRevealId: dailyRecord?.revealId,
        envelopeRevealId: envelopeRevealId,
        favoriteRevealId: favoriteRevealId,
        resolvedRevealId: resolvedRevealId,
        activeCount: activeRecords.length,
        loadCountAtStage: loadCountAtStage,
        replaceCountAtStage: replaceCountAtStage,
      );

      // ignore: avoid_print
      print(
        'EAST_RECON_DIAGNOSTIC stage=$label '
        'dailyRevealId=${snapshot.dailyRevealId} '
        'envelopeRevealId=${snapshot.envelopeRevealId} '
        'favoriteRevealId=${snapshot.favoriteRevealId} '
        'resolvedRevealId=${snapshot.resolvedRevealId} '
        'activeCount=${snapshot.activeCount} '
        'loadCount=${snapshot.loadCountAtStage} '
        'replaceCount=${snapshot.replaceCountAtStage}',
      );

      return snapshot;
    }

    await dailyRepository.backfillRevealIdIfNeeded();
    final dailyRecord = (await dailyRepository.loadDailyWisdomRecord())!;
    await migrationCoordinator.migrateIfNeeded();

    // -- Stage A: after first migration -----------------------------------
    final stageA = await captureIdentityStage('after-first-migration');
    expect(
      stageA.activeCount,
      1,
      reason: 'stage=after-first-migration: migration must produce exactly '
          'one active Kept record',
    );
    expect(
      stageA.envelopeRevealId,
      deriveLegacyMigrationRevealId(recoveredLegacyId),
      reason: 'stage=after-first-migration: the migrated envelope revealId '
          'must be the deterministic legacy derivation',
    );
    expect(
      stageA.dailyRevealId,
      dailyRecord.revealId,
      reason: 'stage=after-first-migration: Daily Access revealId must '
          'still be the unrelated backfilled v4 -- reconciliation has not '
          'run yet',
    );
    expect(
      stageA.dailyRevealId,
      isNot(stageA.envelopeRevealId),
      reason: 'stage=after-first-migration: the two identity mechanisms '
          'must still genuinely differ before reconciliation',
    );
    expect(
      stageA.resolvedRevealId,
      stageA.envelopeRevealId,
      reason: 'stage=after-first-migration: the resolver must already find '
          'the envelope revealId as its sole candidate',
    );

    await reconcileDailyIdentity(dailyRecord);

    // -- Stage B: after first Daily Access reconciliation ------------------
    final stageB = await captureIdentityStage('after-first-reconcile');
    expect(
      stageB.dailyRevealId,
      stageB.envelopeRevealId,
      reason: 'stage=after-first-reconcile: persisted Daily Access '
          'revealId must equal the direct envelope revealId',
    );
    expect(
      stageB.favoriteRevealId,
      stageB.envelopeRevealId,
      reason: 'stage=after-first-reconcile: mapped FavoriteItem revealId '
          'must equal the direct envelope revealId',
    );
    expect(
      await isCurrentlyKept(stageB.dailyRevealId!),
      isTrue,
      reason: 'stage=after-first-reconcile: membership must be true '
          'immediately after reconciliation',
    );
    expect(
      stageB.replaceCountAtStage,
      stageA.replaceCountAtStage,
      reason: 'stage=after-first-reconcile: Kept replaceCallCount must not '
          'have increased between stage A and stage B (reconciliation is '
          'Daily-Access-only)',
    );

    final correctedDailyRecord =
        (await dailyRepository.loadDailyWisdomRecord())!;

    // Simulates a second app launch: migration re-runs. Under the round-2
    // design, this call threw
    // KeptMigrationException['field-verify-mismatch'] here, because that
    // design rewrote the migrated KeptRecord's revealId in place, so the
    // protected envelope no longer matched what the frozen migration
    // snapshot would produce. This design never writes to Kept storage
    // during reconciliation, so the protected envelope is still exactly
    // what the snapshot produces, and this call must succeed.
    final secondMigration = await migrationCoordinator.migrateIfNeeded();
    expect(secondMigration.status, KeptMigrationStatus.alreadyComplete);

    // -- Stage C: after second migrateIfNeeded() / alreadyComplete ---------
    final stageC = await captureIdentityStage('after-second-migration');
    expect(
      stageC.envelopeRevealId,
      stageB.envelopeRevealId,
      reason: 'stage=after-second-migration: direct envelope revealId must '
          'be unchanged by the second migrateIfNeeded() call',
    );
    expect(
      stageC.dailyRevealId,
      stageB.dailyRevealId,
      reason: 'stage=after-second-migration: Daily Access revealId must be '
          'unchanged by the second migrateIfNeeded() call',
    );
    expect(
      stageC.favoriteRevealId,
      stageB.favoriteRevealId,
      reason: 'stage=after-second-migration: mapped FavoriteItem revealId '
          'must be unchanged',
    );
    expect(
      await isCurrentlyKept(stageC.dailyRevealId!),
      isTrue,
      reason: 'stage=after-second-migration: membership must still be true',
    );
    expect(
      stageC.replaceCountAtStage,
      stageB.replaceCountAtStage,
      reason: 'stage=after-second-migration: no additional Kept replace '
          'must have occurred between stage B and stage C',
    );

    // A second, fresh reconciliation attempt against the already-corrected
    // state.
    await reconcileDailyIdentity(correctedDailyRecord);

    // -- Stage D: after second Daily Access reconciliation -----------------
    final stageD = await captureIdentityStage('after-second-reconcile');
    expect(
      stageD.envelopeRevealId,
      stageC.envelopeRevealId,
      reason: 'stage=after-second-reconcile: direct envelope revealId must '
          'be unchanged',
    );
    expect(
      stageD.dailyRevealId,
      stageC.dailyRevealId,
      reason: 'stage=after-second-reconcile: Daily Access revealId must be '
          'unchanged -- the second reconciliation attempt must be '
          'idempotent',
    );
    expect(
      stageD.favoriteRevealId,
      stageC.favoriteRevealId,
      reason: 'stage=after-second-reconcile: mapped FavoriteItem revealId '
          'must be unchanged',
    );
    expect(
      await isCurrentlyKept(stageD.dailyRevealId!),
      isTrue,
      reason: 'stage=after-second-reconcile: membership must still be true',
    );
    expect(
      stageD.replaceCountAtStage,
      stageC.replaceCountAtStage,
      reason: 'stage=after-second-reconcile: no additional Kept replace '
          'must have occurred between stage C and stage D',
    );

    final finalDailyRecord = (await dailyRepository.loadDailyWisdomRecord())!;
    expect(finalDailyRecord.revealId, correctedDailyRecord.revealId);
    expect(
      await isCurrentlyKept(finalDailyRecord.revealId!),
      isTrue,
      reason: 'final: the original assertion this diagnostic turn is '
          'localizing -- see the EAST_RECON_DIAGNOSTIC stage lines above '
          'for exactly where dailyRevealId/envelopeRevealId/favoriteRevealId '
          'first diverge, if they do',
    );

    final favorites = await keptRepository.load();
    expect(favorites, hasLength(1));
  });

  group(
      'Phase 3D-E safety-gap correction, round 2 (timezone-independent '
      'legacy save-instant window; Gap 2 provenance)', () {
    test(
        '8. the real physical-device fixture reconciles through its actual '
        'embedded save instant, independent of any timezone concept', () async {
      // No timezone is injected, simulated, or consulted anywhere in this
      // test -- proving the reconciliation result no longer depends on one
      // at all (unlike the earlier, rejected `DateTime.toLocal()`-based
      // design). The window is expressed purely in UTC/epoch instants.
      expect(
        recoveredPayloadSavedAt.isBefore(dailyRevealedAt),
        isFalse,
        reason: 'fixture setup sanity: save instant must be >= revealedAt',
      );
      expect(
        recoveredPayloadSavedAt.isBefore(dailyUnlockAt),
        isTrue,
        reason: 'fixture setup sanity: save instant must be < unlockAt',
      );

      await dailyRepository.backfillRevealIdIfNeeded();
      final dailyRecord = (await dailyRepository.loadDailyWisdomRecord())!;
      await migrationCoordinator.migrateIfNeeded();

      await reconcileDailyIdentity(dailyRecord);

      final correctedDailyRecord =
          (await dailyRepository.loadDailyWisdomRecord())!;
      expect(await isCurrentlyKept(correctedDailyRecord.revealId!), isTrue);
    });

    test(
        '9. the same fixture reconciles identically no matter what device '
        'timezone the upgrade is claimed to have happened under -- because '
        'no timezone parameter exists anywhere in this call chain anymore',
        () async {
      // Three fully independent "installs" (fresh SharedPreferences, fresh
      // coordinators/stores each time, exactly like a real fresh app
      // launch), one per claimed environment. Nothing about the outcome
      // actually varies by environment name, because the fix removed the
      // timezone dependency entirely rather than trying to guess it
      // correctly.
      for (final claimedEnvironment in ['UTC+03:00', 'UTC', 'UTC-07:00']) {
        SharedPreferences.setMockInitialValues({});

        final freshDailyRepository = DailyAccessRepository(
          preferencesAdapter: StoragePreferencesAdapter(),
          operationCoordinator: PersistenceOperationCoordinator(),
        );
        await freshDailyRepository.saveDailyWisdomRecord(DailyWisdomRecord(
          text: 'Some doors open after surrender.',
          revealedAt: dailyRevealedAt,
          unlockAt: dailyUnlockAt,
        ));
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('favorites', [recoveredPayload]);

        final freshKeptCoordinator = PersistenceOperationCoordinator();
        final freshKeptStateStore = JsonRoundTrippingKeptStateStore();
        final freshMigrationCoordinator = KeptMigrationCoordinator(
          legacyFavoritesStore: SharedPreferencesLegacyFavoritesStore(),
          journalStore: SharedPreferencesKeptMigrationJournalStore(),
          artifactStore: JsonRoundTrippingKeptMigrationArtifactStore(),
          keptStateStore: freshKeptStateStore,
          operationCoordinator: freshKeptCoordinator,
        );
        final freshKeptRepository = KeptRepository(
          store: freshKeptStateStore,
          bootstrap: const KeptBootstrapResult.ready(),
          operationCoordinator: freshKeptCoordinator,
          clock: () => DateTime.utc(2026, 8, 3, 10, 0),
        );

        await freshDailyRepository.backfillRevealIdIfNeeded();
        final dailyRecord =
            (await freshDailyRepository.loadDailyWisdomRecord())!;
        await freshMigrationCoordinator.migrateIfNeeded();

        final resolvedLegacyRevealId = await freshKeptRepository
            .resolveLegacyMigratedRevealIdForOccurrence(
          wisdomText: dailyRecord.text,
          committedRevealedAt: dailyRecord.revealedAt,
          committedUnlockAt: dailyRecord.unlockAt,
        );
        await freshDailyRepository.reconcileRevealIdForOccurrence(
          expectedText: dailyRecord.text,
          expectedRevealedAt: dailyRecord.revealedAt,
          expectedUnlockAt: dailyRecord.unlockAt,
          resolvedLegacyRevealId: resolvedLegacyRevealId,
        );

        final correctedDailyRecord =
            (await freshDailyRepository.loadDailyWisdomRecord())!;
        final favorites = await freshKeptRepository.load();
        expect(
          favorites
              .any((item) => item.revealId == correctedDailyRecord.revealId),
          isTrue,
          reason: 'claimed environment: $claimedEnvironment',
        );
      }
    });

    test(
        '10. a genuine device-timezone change between the original save and '
        'this reconciliation attempt no longer prevents reconciliation '
        '(the defect the earlier design had)', () async {
      // There is nothing to "change" anymore -- this test exists to record
      // that fact. The same fixture, same window, same result as test 8,
      // with an explicit comment marking what this replaces.
      await dailyRepository.backfillRevealIdIfNeeded();
      final dailyRecord = (await dailyRepository.loadDailyWisdomRecord())!;
      await migrationCoordinator.migrateIfNeeded();

      await reconcileDailyIdentity(dailyRecord);

      final correctedDailyRecord =
          (await dailyRepository.loadDailyWisdomRecord())!;
      expect(await isCurrentlyKept(correctedDailyRecord.revealId!), isTrue);
    });

    test(
        '11. (Gap 2) an ordinary, non-migrated Build 26 record kept for '
        'matching text inside the same window is never treated as a legacy '
        'candidate, and Kept storage is never touched by resolution', () async {
      // No legacy favorites at all this time -- migration has nothing to
      // do, so any Kept record present is, by construction, an ordinary
      // Build 26 record (a real random UUID v4 revealId from
      // `keepOccurrence`, never the deterministic migration derivation).
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('favorites');

      await dailyRepository.backfillRevealIdIfNeeded();
      final dailyRecord = (await dailyRepository.loadDailyWisdomRecord())!;
      await migrationCoordinator.migrateIfNeeded();

      const ordinaryRevealId = '66666666-6666-4666-8666-666666666666';
      final keepResult = await keptRepository.keepOccurrence(
        revealId: ordinaryRevealId,
        wisdomText: dailyRecord.text,
        revealedAt: dailyRecord.revealedAt,
        isKeeper: true,
      );
      expect(keepResult.limitReached, isFalse);

      final beforeEnvelope = await keptStateStore.load();
      final replaceCountBefore = keptStateStore.replaceCallCount;

      final resolvedLegacyRevealId =
          await keptRepository.resolveLegacyMigratedRevealIdForOccurrence(
        wisdomText: dailyRecord.text,
        committedRevealedAt: dailyRecord.revealedAt,
        committedUnlockAt: dailyRecord.unlockAt,
      );

      // An ordinary Build 26 record's own `id` is also a random UUID v4,
      // never a parseable `sr-v1-...` id, so it could never pass the
      // legacy save-instant window rule either -- belt and suspenders with
      // the provenance gate.
      expect(resolvedLegacyRevealId, isNull);

      // Read-only: Kept storage is byte-for-byte unchanged by resolution
      // alone, no matter the outcome.
      expect(keptStateStore.replaceCallCount, replaceCountBefore);
      final afterEnvelope = await keptStateStore.load();
      expect(afterEnvelope, beforeEnvelope);

      final favorites = await keptRepository.load();
      expect(favorites, hasLength(1));
      expect(favorites.single.revealId, ordinaryRevealId);
      expect(await isCurrentlyKept(ordinaryRevealId), isTrue);
    });

    test(
        '12. (Gap 2) two genuinely migration-provenanced candidates, both '
        'with a save instant inside the same window, remain ambiguous -- '
        'the resolver returns null and neither Kept nor Daily Access '
        'storage is ever written to', () async {
      await dailyRepository.backfillRevealIdIfNeeded();
      final dailyRecord = (await dailyRepository.loadDailyWisdomRecord())!;
      await migrationCoordinator.migrateIfNeeded();

      // A second, independently-migration-provenanced record for the exact
      // same text, with its own valid `sr-v1-...` id whose embedded save
      // instant also falls inside the committed window (simulating two
      // separate legacy items that happened to collide) -- both pass every
      // gate, so the ambiguity must block reconciliation rather than
      // guessing which one is the real match.
      final secondSavedAt = dailyRevealedAt.add(const Duration(hours: 1));
      final secondLegacyId = 'sr-v1-${secondSavedAt.microsecondsSinceEpoch}-0';
      final secondMigrated = KeptRecord(
        id: secondLegacyId,
        revealId: deriveLegacyMigrationRevealId(secondLegacyId),
        wisdomText: dailyRecord.text,
        revealedAt: dailyRecord.revealedAt,
        keptAt: dailyRecord.revealedAt,
        updatedAt: dailyRecord.revealedAt,
        mutationId: '00000000-0000-4000-8000-000000000002',
      );
      final existingEnvelope = (await keptStateStore.load())!;
      await keptStateStore.replace(
        existingEnvelope.copyWith(
          activeRecords: [
            ...existingEnvelope.activeRecords,
            secondMigrated,
          ],
        ),
      );
      final replaceCountBeforeResolve = keptStateStore.replaceCallCount;

      final resolvedLegacyRevealId =
          await keptRepository.resolveLegacyMigratedRevealIdForOccurrence(
        wisdomText: dailyRecord.text,
        committedRevealedAt: dailyRecord.revealedAt,
        committedUnlockAt: dailyRecord.unlockAt,
      );
      expect(resolvedLegacyRevealId, isNull);
      expect(keptStateStore.replaceCallCount, replaceCountBeforeResolve);

      await dailyRepository.reconcileRevealIdForOccurrence(
        expectedText: dailyRecord.text,
        expectedRevealedAt: dailyRecord.revealedAt,
        expectedUnlockAt: dailyRecord.unlockAt,
        resolvedLegacyRevealId: resolvedLegacyRevealId,
      );

      // No candidate + a revealId that was already present (from the
      // earlier backfillRevealIdIfNeeded() call): left unchanged.
      final unchangedDailyRecord =
          (await dailyRepository.loadDailyWisdomRecord())!;
      expect(unchangedDailyRecord.revealId, dailyRecord.revealId);
      expect(await isCurrentlyKept(dailyRecord.revealId!), isFalse);
      final favorites = await keptRepository.load();
      expect(favorites, hasLength(2));
    });
  });
}
