import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/data/wisdoms.dart'
    show
        wisdoms,
        resolveUniqueWisdomIdForEnglishSnapshot,
        buildUniqueWisdomIdByEnglishSnapshotFrom;
import 'package:wisdom_app/l10n/app_localizations.dart';
import 'package:wisdom_app/localization/east_locale_registry.dart';
import 'package:wisdom_app/models/daily_wisdom_selection.dart';
import 'package:wisdom_app/models/kept_bootstrap_result.dart';
import 'package:wisdom_app/models/kept_record.dart';
import 'package:wisdom_app/models/kept_state_envelope.dart';
import 'package:wisdom_app/models/pending_daily_wisdom_reveal.dart';
import 'package:wisdom_app/persistence/persistence_operation_coordinator.dart';
import 'package:wisdom_app/repositories/kept_repository.dart';
import 'package:wisdom_app/screens/journal_screen.dart';
import 'package:wisdom_app/screens/saved_reflections_screen.dart';
import 'package:wisdom_app/services/wisdom_localization_resolver.dart';
import 'package:wisdom_app/sync/cloud_kept_wisdom_projection.dart';
import 'package:wisdom_app/sync/data_epoch.dart';
import 'package:wisdom_app/sync_integration/incoming_kept_sync_coordinator.dart';
import 'package:wisdom_app/sync_orchestration/pending_incoming_sync_batch.dart';
import 'package:wisdom_app/sync_persistence/account_sync_state.dart';

import 'persistence_test_helpers.dart';

/// EAST. Build 33 -- historical/previous-install null-wisdomId recovery, and
/// the paired current-build canonical-Keep safety proof.
///
/// ROOT CAUSE (see `lib/models/kept_record.dart` and
/// `lib/models/pending_daily_wisdom_reveal.dart`): both constructors already
/// computed `wisdomId ?? resolveUniqueWisdomIdForEnglishSnapshot(wisdomText)`
/// -- the pre-existing, correct "exactly one canonical match, else stay
/// unresolved" resolver already lived in `lib/data/wisdoms.dart` -- but the
/// computed value was passed only into an internal validation-only helper
/// and never assigned to the field itself, so a record decoded with no
/// persisted `wisdomId` stayed permanently null even when its snapshot text
/// exactly and uniquely matched a canonical wisdom. `FavoriteItem.decode()`
/// and `DailyWisdomRecord.decode()` already wired the identical fallback
/// expression correctly; only these two constructors had the bug. Fixing
/// the constructor (not the decode call sites, which already forwarded
/// whatever they read) makes recovery a pure, deterministic function of the
/// already-persisted `wisdomText`, re-evaluated on every construction --
/// every `KeptRepository.load()` and every `PendingDailyWisdomReveal.decode`
/// now recovers automatically, with no new disk write, no new sync trigger,
/// and no risk of a stray outbound mutation. See the `KeptRecord.wisdomId`
/// and `PendingDailyWisdomReveal.wisdomId` doc comments.
void main() {
  const resolver = WisdomLocalizationResolver();

  // The specific real-device record named in this task.
  const woundId = 'east_wisdom_0195';
  const woundText = 'The wound is not the whole story.';

  const revealIdV4 = '223e4567-e89b-42d3-a456-426614174001';
  const mutationIdV4 = 'b1b2c3d4-0000-4000-8000-000000000002';
  final revealedAt = DateTime.utc(2026, 6, 18, 9, 30);
  final keptAt = DateTime.utc(2026, 6, 18, 9, 31);
  final updatedAt = keptAt;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  /// The exact shape a previous-install / historical record has on disk:
  /// every other field present, `wisdomId` entirely absent -- never merely
  /// `null`-valued, since `KeptRecord.encode()` omits the key outright when
  /// `wisdomId` is null (see its `if (wisdomId != null) 'wisdomId': wisdomId`
  /// line). This is what a real restored-from-iCloud Build 26-32 record
  /// looks like once decoded off disk.
  Map<String, dynamic> historicalRawRecord({
    String id = 'legacy-previous-install-1',
    String wisdomText = woundText,
  }) =>
      {
        'schemaVersion': KeptRecord.currentSchemaVersion,
        'id': id,
        'revealId': revealIdV4,
        'wisdomText': wisdomText,
        'revealedAtMs': revealedAt.millisecondsSinceEpoch,
        'keptAtMs': keptAt.millisecondsSinceEpoch,
        'updatedAtMs': updatedAt.millisecondsSinceEpoch,
        'mutationId': mutationIdV4,
      };

  group('SPECIFIC RECORD: "The wound is not the whole story."', () {
    test('matches exactly one canonical wisdom (east_wisdom_0195)', () {
      final matches = wisdoms.where((w) => w['text'] == woundText).toList();
      expect(matches, hasLength(1));
      expect(matches.single['id'], woundId);
      expect(resolveUniqueWisdomIdForEnglishSnapshot(woundText), woundId);
    });

    test(
        'a historical record with no persisted wisdomId recovers it through '
        'the real KeptRepository.load() path', () async {
      final graph = KeptRepositoryTestGraph();
      final rawEnvelope = {
        'schemaVersion': KeptStateEnvelope.currentSchemaVersion,
        'activeRecords': [historicalRawRecord()],
      };
      graph.store.envelope = KeptStateEnvelope.decode(rawEnvelope);

      final loaded = await graph.repository.loadAllRecords();
      final record = loaded.single;
      expect(record.wisdomId, woundId);
      expect(record.wisdomText, woundText);
      expect(record.revealId, revealIdV4);

      final items = await graph.service.load();
      expect(items.single.wisdomId, woundId);
    });

    testWidgets(
        'Kept presentation resolves the recovered ID in all 15 product '
        'locales, and re-loading after each switch never mutates the '
        'persisted record', (tester) async {
      final graph = KeptRepositoryTestGraph();
      final rawEnvelope = {
        'schemaVersion': KeptStateEnvelope.currentSchemaVersion,
        'activeRecords': [historicalRawRecord()],
      };
      graph.store.envelope = KeptStateEnvelope.decode(rawEnvelope);
      final items = await graph.service.load();
      final item = items.single;
      final beforeAnyPresentation =
          (await graph.repository.loadAllRecords()).single;

      for (final target in EastLocaleRegistry.targets) {
        await tester.pumpWidget(
          MaterialApp(
            locale: target.locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: EastLocaleRegistry.runtimeSupported,
            home: SavedReflectionsScreen(
              reflections: [item],
              savedReflectionsService: graph.service,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: target.tag);

        final resolved = resolver.resolveItem(item, target.locale);
        expect(resolved, isNotEmpty, reason: target.tag);
        expect(find.text(resolved), findsWidgets, reason: target.tag);
      }

      final afterAllPresentation =
          (await graph.repository.loadAllRecords()).single;
      expect(afterAllPresentation, beforeAnyPresentation);
      expect(afterAllPresentation.wisdomId, woundId);
      expect(afterAllPresentation.wisdomText, woundText);
    });

    testWidgets(
        'Journal presentation resolves the recovered ID in all 15 product '
        'locales', (tester) async {
      final graph = KeptRepositoryTestGraph();
      final rawEnvelope = {
        'schemaVersion': KeptStateEnvelope.currentSchemaVersion,
        'activeRecords': [historicalRawRecord()],
      };
      graph.store.envelope = KeptStateEnvelope.decode(rawEnvelope);
      final items = await graph.service.load();
      final item = items.single;

      for (final target in EastLocaleRegistry.targets) {
        await tester.pumpWidget(
          MaterialApp(
            locale: target.locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: EastLocaleRegistry.runtimeSupported,
            home: JournalScreen(items: [item], isKeeper: true),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: target.tag);
      }

      final all = await graph.repository.loadAllRecords();
      expect(all, hasLength(1));
      expect(all.single.wisdomId, woundId);
    });
  });

  group('Safety Test A: exact unique match recovers canonical ID', () {
    test('KeptRecord.decode() recovers the unique canonical match', () {
      final decoded = KeptRecord.decode(historicalRawRecord());
      expect(decoded.wisdomId, woundId);
    });

    test(
        'PendingDailyWisdomReveal recovers the unique canonical match when '
        'constructed with no wisdomId', () {
      final pending = PendingDailyWisdomReveal(
        text: woundText,
        preparedAt: DateTime.utc(2026, 6, 18, 9),
      );
      expect(pending.wisdomId, woundId);
    });
  });

  group('Safety Test B: zero matches remain unresolved', () {
    const nonCatalogText = 'This exact sentence is not in the East catalog.';

    test('a text with zero canonical matches resolves to null', () {
      expect(wisdoms.where((w) => w['text'] == nonCatalogText), isEmpty);
      expect(resolveUniqueWisdomIdForEnglishSnapshot(nonCatalogText), isNull);
    });

    test('KeptRecord.decode() leaves wisdomId null for non-catalog text', () {
      final decoded = KeptRecord.decode(
        historicalRawRecord(wisdomText: nonCatalogText),
      );
      expect(decoded.wisdomId, isNull);
      expect(decoded.wisdomText, nonCatalogText);
    });
  });

  group('Safety Test C: duplicate/ambiguous matches remain unresolved', () {
    // The live catalog has zero exact-duplicate English texts today (see
    // `buildUniqueWisdomIdByEnglishSnapshotFrom`'s own doc comment), so this
    // exercises the exact production reduction algorithm against a
    // hand-built duplicate-text catalog rather than the live one -- the
    // only way to deterministically reach the ambiguous branch. Exact
    // duplicate wisdom text is an allowed catalog shape; ambiguity must
    // stay unresolved rather than guessing, per product decision.
    test('the live catalog currently has zero exact-duplicate texts', () {
      final byText = <String, int>{};
      for (final w in wisdoms) {
        final text = w['text'] as String;
        byText[text] = (byText[text] ?? 0) + 1;
      }
      expect(byText.values.where((count) => count > 1), isEmpty);
    });

    test(
        'the production reduction resolves duplicate text to null, and a '
        'third entry does not resurrect it', () {
      final synthetic = buildUniqueWisdomIdByEnglishSnapshotFrom([
        {'id': 'east_wisdom_0001', 'text': 'A duplicated sentence.'},
        {'id': 'east_wisdom_0002', 'text': 'A duplicated sentence.'},
        {'id': 'east_wisdom_0003', 'text': 'A duplicated sentence.'},
        {'id': 'east_wisdom_0004', 'text': 'A unique sentence.'},
      ]);
      expect(synthetic['A duplicated sentence.'], isNull);
      expect(synthetic['A unique sentence.'], 'east_wisdom_0004');
    });
  });

  group('Safety Test D / CURRENT_BUILD_CANONICAL_KEEP_NEVER_BECOMES_NULL_ID',
      () {
    const wisdomId = 'east_wisdom_0301';
    final englishText =
        wisdoms.firstWhere((w) => w['id'] == wisdomId)['text'] as String;
    const fingerprint = 'fingerprint-current-build-canonical-keep-safety';
    final epoch = DataEpoch.parse('22222222-2222-4222-8222-222222222222');
    final now = DateTime.utc(2041, 8, 23, 8);

    test(
        'CURRENT_BUILD_CANONICAL_KEEP_NEVER_BECOMES_NULL_ID: a genuine '
        'canonical reveal, driven through the real selection -> prepare -> '
        'commit -> Keep -> local persistence -> incoming self-echo pipeline, '
        'never produces a null wisdomId at any stage', () async {
      final dailyGraph = DailyAccessTestGraph(clock: () => now);
      final keptGraph = KeptRepositoryTestGraph(clock: () => now);
      final incomingCoordinator = IncomingKeptSyncCoordinator(
        keptRepository: keptGraph.repository,
        intentStore: keptGraph.intentStore,
        syncPersistenceStore: keptGraph.syncPersistenceStore,
      );
      keptGraph.syncPersistenceStore.seedAccount(
        fingerprint,
        AccountSyncState(
          dataEpoch: epoch,
          serverChangeToken: null,
          outbox: const [],
          recordSystemFields: const {},
          bootstrapState: AccountBootstrapState.complete,
        ),
      );

      // Stage 1: canonical selection -> PendingDailyWisdomReveal, the exact
      // call shape HomeScreen.prepareDailyWisdomReveal() uses.
      final prepared = await dailyGraph.service.prepareReveal(
        selectWisdom: () => englishText,
        selectWisdomWithIdentity: () => DailyWisdomSelection(
          text: englishText,
          wisdomId: wisdomId,
        ),
      );
      expect(prepared.wisdomId, isNotNull,
          reason: 'stage 1: prepare (selection -> pending reveal)');
      expect(prepared.wisdomId, wisdomId);

      // Stage 2: commit -> DailyWisdomRecord, round-tripping through
      // PendingDailyWisdomReveal.encode()/decode().
      final committed = await dailyGraph.service.finalizeVisualReveal(
        text: prepared.text,
        revealBoundary: now,
      );
      expect(committed.wisdomId, isNotNull, reason: 'stage 2: commit');
      expect(committed.wisdomId, wisdomId);

      // Stage 3: Keep, the exact call shape HomeScreen.toggleFavorite() /
      // SavedReflectionsService.toggle() use.
      final toggleResult = await keptGraph.service.toggle(
        text: committed.text,
        date: 'August 23, 2041',
        isKeeper: true,
        revealId: committed.revealId!,
        revealedAt: committed.revealedAt!,
        wisdomId: committed.wisdomId,
      );
      final justKept = toggleResult.items.firstWhere(
        (item) => item.revealId == committed.revealId,
      );
      expect(justKept.wisdomId, isNotNull, reason: 'stage 3: Keep');
      expect(justKept.wisdomId, wisdomId);

      // Stage 4: local persistence round trip (fresh repository, same
      // underlying store -- mirrors an app restart).
      final restartedRepository = KeptRepository(
        store: keptGraph.store,
        bootstrap: const KeptBootstrapResult.ready(),
        operationCoordinator: PersistenceOperationCoordinator(),
      );
      final reloaded = await restartedRepository.loadAllRecords();
      final reloadedRecord = reloaded.firstWhere(
        (record) => record.revealId == committed.revealId,
      );
      expect(reloadedRecord.wisdomId, isNotNull,
          reason: 'stage 4: local persistence reload');
      expect(reloadedRecord.wisdomId, wisdomId);

      // Stage 5: outgoing CloudKit projection -> incoming self-echo, the
      // exact reconciliation that runs at every app resume/startup.
      final incomingProjection = CloudKeptWisdomProjection.active(
        reloadedRecord,
        dataEpoch: epoch,
      );
      expect(incomingProjection.wisdomId, isNotNull,
          reason: 'stage 5a: outgoing CloudKit projection');
      final batch = PendingIncomingSyncBatch(
        accountFingerprint: fingerprint,
        baseDataEpoch: epoch,
        previousServerChangeToken: null,
        pendingServerChangeToken: 'bmV3dG9rZW4=',
        incomingKeptWisdomProjections: [incomingProjection],
        incomingSyncStateProjections: const [],
        incomingKeptWisdomRecordSystemFields: {
          incomingProjection.recordName: 'c3lzdGVtRmllbGRz',
        },
      );
      final applyResult = await incomingCoordinator.applyIncomingBatch(batch);
      expect(applyResult.status, IncomingApplyStatus.applied);

      final afterIncoming = await keptGraph.repository.loadAllRecords();
      final afterIncomingRecord = afterIncoming.firstWhere(
        (record) => record.revealId == committed.revealId,
      );
      expect(afterIncomingRecord.wisdomId, isNotNull,
          reason: 'stage 5b: incoming self-echo apply -- MUST NOT be null');
      expect(afterIncomingRecord.wisdomId, wisdomId);

      // Final assertion, restated as the exact required contract.
      expect(afterIncomingRecord.wisdomId, isNotNull,
          reason: 'current pipeline can create null canonical wisdomId: '
              'MUST BE false');
    });
  });

  group('Safety Test E: incoming CloudKit self-echo never strips wisdomId', () {
    const fingerprint = 'fingerprint-self-echo-recovered-record';
    final epoch = DataEpoch.parse('33333333-3333-4333-8333-333333333333');

    test(
        'a historically-recovered record (wisdomId resolved at decode time, '
        'never persisted as such by the sender) survives an incoming '
        'self-echo without losing wisdomId', () async {
      final keptGraph = KeptRepositoryTestGraph();
      final incomingCoordinator = IncomingKeptSyncCoordinator(
        keptRepository: keptGraph.repository,
        intentStore: keptGraph.intentStore,
        syncPersistenceStore: keptGraph.syncPersistenceStore,
      );
      keptGraph.syncPersistenceStore.seedAccount(
        fingerprint,
        AccountSyncState(
          dataEpoch: epoch,
          serverChangeToken: null,
          outbox: const [],
          recordSystemFields: const {},
          bootstrapState: AccountBootstrapState.complete,
        ),
      );

      // Seed local storage with the raw historical shape (no wisdomId key
      // at all), exactly like historicalRawRecord() above.
      final rawEnvelope = {
        'schemaVersion': KeptStateEnvelope.currentSchemaVersion,
        'activeRecords': [historicalRawRecord(id: 'legacy-self-echo-1')],
      };
      keptGraph.store.envelope = KeptStateEnvelope.decode(rawEnvelope);
      final beforeEcho = (await keptGraph.repository.loadAllRecords()).single;
      expect(beforeEcho.wisdomId, woundId);

      // The next incoming batch reflects this exact record back, as a real
      // CloudKit self-echo would (the projection is built from the
      // already-recovered in-memory record, since that is what any real
      // outgoing sync of this record would project).
      final projection = CloudKeptWisdomProjection.active(
        beforeEcho,
        dataEpoch: epoch,
      );
      final batch = PendingIncomingSyncBatch(
        accountFingerprint: fingerprint,
        baseDataEpoch: epoch,
        previousServerChangeToken: null,
        pendingServerChangeToken: 'bmV3dG9rZW4=',
        incomingKeptWisdomProjections: [projection],
        incomingSyncStateProjections: const [],
        incomingKeptWisdomRecordSystemFields: {
          projection.recordName: 'c3lzdGVtRmllbGRz',
        },
      );
      final result = await incomingCoordinator.applyIncomingBatch(batch);
      expect(result.status, IncomingApplyStatus.applied);

      final afterEcho = (await keptGraph.repository.loadAllRecords()).single;
      expect(afterEcho.wisdomId, woundId);
      expect(afterEcho.revealId, beforeEcho.revealId);
      expect(afterEcho.wisdomText, woundText);
    });
  });

  group('Safety Test F: KeptRecord construction never strips wisdomId', () {
    // `KeptSyncBootstrapCoordinator`'s three independent-mirror KeptRecord
    // construction sites (`_applyOutcomeToRecords`,
    // `_projectionFromIntentIndependentMirror`,
    // `_toSyncChangeIndependentMirror`) all already forward
    // `projection.wisdomId`/`payload.wisdomId` explicitly into KeptRecord's
    // `wisdomId:` parameter -- confirmed by direct source inspection of
    // lib/sync_integration/kept_sync_bootstrap_coordinator.dart, lines
    // ~1785, ~1846, ~1901. There is no existing test harness anywhere in
    // this codebase that drives KeptSyncBootstrapCoordinator.runBootstrap()
    // end-to-end (it requires a full CloudKitPlatformBridge control-record
    // ceremony this session did not stand up); that gap pre-dates this
    // change and is out of this task's scope. What this test proves
    // directly is the shared safety net all three of those call sites now
    // rely on: even a KeptRecord constructed exactly as they construct one
    // -- explicit wisdomId: null, from a projection/payload whose own
    // wisdomId happened to be null -- still recovers a resolvable
    // canonical ID from wisdomText, and stays correctly unresolved when it
    // genuinely cannot.
    test(
        'KeptRecord constructed with wisdomId: null (the bootstrap '
        'call-site shape) still recovers a unique canonical match', () {
      final record = KeptRecord(
        id: 'bootstrap-mirror-1',
        revealId: revealIdV4,
        wisdomText: woundText,
        wisdomId: null,
        revealedAt: revealedAt,
        keptAt: keptAt,
        updatedAt: updatedAt,
        mutationId: mutationIdV4,
      );
      expect(record.wisdomId, woundId);
    });

    test(
        'KeptRecord constructed with wisdomId: null and non-catalog text '
        'stays unresolved, never guesses', () {
      final record = KeptRecord(
        id: 'bootstrap-mirror-2',
        revealId: revealIdV4,
        wisdomText: 'Not in the catalog at all.',
        wisdomId: null,
        revealedAt: revealedAt,
        keptAt: keptAt,
        updatedAt: updatedAt,
        mutationId: mutationIdV4,
      );
      expect(record.wisdomId, isNull);
    });
  });
}
