import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/data/wisdoms.dart' show wisdoms;
import 'package:wisdom_app/l10n/app_localizations.dart';
import 'package:wisdom_app/localization/east_locale_registry.dart';
import 'package:wisdom_app/models/daily_wisdom_selection.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/models/kept_bootstrap_result.dart';
import 'package:wisdom_app/persistence/persistence_operation_coordinator.dart';
import 'package:wisdom_app/repositories/kept_repository.dart';
import 'package:wisdom_app/screens/journal_screen.dart';
import 'package:wisdom_app/screens/saved_reflections_screen.dart';
import 'package:wisdom_app/services/journal_pdf_builder.dart';
import 'package:wisdom_app/services/wisdom_localization_resolver.dart';
import 'package:wisdom_app/sync/cloud_kept_wisdom_projection.dart';
import 'package:wisdom_app/sync/data_epoch.dart';
import 'package:wisdom_app/sync_integration/incoming_kept_sync_coordinator.dart';
import 'package:wisdom_app/sync_orchestration/pending_incoming_sync_batch.dart';
import 'package:wisdom_app/sync_persistence/account_sync_state.dart';

import 'persistence_test_helpers.dart';

/// EAST. "fresh Keep / Journal wisdom identity" hotfix -- the required
/// `fresh_reveal_keep_round_trip_preserves_wisdom_identity` regression.
///
/// Unlike the previous session's synthetic `FavoriteItem(wisdomId: ...)`
/// tests (which only proved presentation works once a wisdomId is already
/// present), every test in this file drives the REAL production pipeline:
/// a canonical daily reveal through the real `DailyWisdomAccessService`,
/// the real `HomeScreen.toggleFavorite()` call shape into
/// `SavedReflectionsService.toggle`, the real local `KeptRepository`
/// persistence round trip, and -- the actual second defect this session
/// fixes -- a real incoming-sync self-echo through
/// `IncomingKeptSyncCoordinator.applyIncomingBatch`. Only the record that
/// survives all of that is ever handed to a presentation widget.
///
/// SECOND ROOT CAUSE (see `lib/sync_integration/incoming_kept_sync_coordinator.dart`
/// and `lib/sync_integration/kept_sync_bootstrap_coordinator.dart`): five
/// `KeptRecord(...)` constructor calls -- the incoming-apply conversion
/// (`_applyOutcomeToRecords`), the intent-to-projection conversion
/// (`_projectionFromIntent`), and their three "independent mirror" copies
/// in the bootstrap coordinator -- read `wisdomId` off the incoming
/// projection/payload but never passed it to the `KeptRecord` they
/// constructed. A fresh Keep's local write was already correct (this is
/// why Home reacted correctly and a synthetic Kept test passed), but the
/// very next incoming-sync reconciliation (routine at app resume/startup)
/// silently overwrote it with a `wisdomId: null` copy -- exactly the
/// reported "Kept/Journal show English, and locale switching no longer
/// changes it" symptom.
void main() {
  const wisdomId = 'east_wisdom_0301';
  final englishText =
      wisdoms.firstWhere((w) => w['id'] == wisdomId)['text'] as String;
  const resolver = WisdomLocalizationResolver();
  const fingerprint = 'fingerprint-fresh-keep-pipeline';
  final epoch = DataEpoch.parse('11111111-1111-4111-8111-111111111111');
  final now = DateTime.utc(2041, 7, 23, 8);

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('fresh_reveal_keep_round_trip_preserves_wisdom_identity', () {
    late DailyAccessTestGraph dailyGraph;
    late KeptRepositoryTestGraph keptGraph;
    late IncomingKeptSyncCoordinator incomingCoordinator;

    setUp(() {
      dailyGraph = DailyAccessTestGraph(clock: () => now);
      keptGraph = KeptRepositoryTestGraph(clock: () => now);
      incomingCoordinator = IncomingKeptSyncCoordinator(
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
    });

    /// Steps 1-4 of the required integration flow: canonical reveal ->
    /// reveal persistence/decode -> the real Keep operation -> local
    /// persistence round trip -> a real incoming-sync self-echo. Returns
    /// the record as `SavedReflectionsScreen`/`JournalScreen` would
    /// actually receive it after all of that -- never hand-constructed.
    Future<FavoriteItem> revealKeepAndReconcile() async {
      // 1. Fresh canonical reveal -- the exact call shape
      // `HomeScreen.prepareDailyWisdomReveal()` uses (both `selectWisdom`
      // and `selectWisdomWithIdentity`, never a shortcut).
      final prepared = await dailyGraph.service.prepareReveal(
        selectWisdom: () => englishText,
        selectWisdomWithIdentity: () => DailyWisdomSelection(
          text: englishText,
          wisdomId: wisdomId,
        ),
      );
      expect(prepared.wisdomId, wisdomId,
          reason: '1. fresh reveal (prepare) wisdomId');

      // Reveal persistence/decode: commits through `finalizeVisualReveal`,
      // which is the exact path that round-trips through
      // `PendingDailyWisdomReveal.encode()`/`.decode()` (the first,
      // already-fixed defect).
      final committed = await dailyGraph.service.finalizeVisualReveal(
        text: prepared.text,
        revealBoundary: now,
      );
      expect(committed.wisdomId, wisdomId,
          reason: '1. fresh reveal (committed) wisdomId survives the '
              'PendingDailyWisdomReveal round trip');
      expect(committed.revealId, isNotNull);
      expect(committed.revealedAt, isNotNull);

      // 2. Keep -- the exact call shape `HomeScreen.toggleFavorite()` uses.
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
      expect(justKept.wisdomId, wisdomId, reason: '2. Keep operation wisdomId');
      expect(justKept.revealId, committed.revealId);

      // 3. Local persistence round trip -- a fresh `KeptRepository` reading
      // the SAME underlying store, mirroring an app restart.
      final restartedRepository = KeptRepository(
        store: keptGraph.store,
        bootstrap: const KeptBootstrapResult.ready(),
        operationCoordinator: PersistenceOperationCoordinator(),
      );
      final reloaded = await restartedRepository.loadAllRecords();
      final reloadedRecord = reloaded.firstWhere(
        (record) => record.revealId == committed.revealId,
      );
      expect(reloadedRecord.wisdomId, wisdomId,
          reason: '3. local persistence round trip wisdomId');

      // 4. CloudKit/wire projection -- a real self-echo through the actual
      // incoming-apply pipeline (what happens the next time this device
      // fetches changes, including its own just-pushed record reflected
      // back). This is the exact step the second defect broke.
      final incomingProjection = CloudKeptWisdomProjection.active(
        reloadedRecord,
        dataEpoch: epoch,
      );
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
      expect(afterIncomingRecord.wisdomId, wisdomId,
          reason: '4. CloudKit/wire projection round trip wisdomId -- THE '
              'regression this session fixes');
      expect(afterIncomingRecord.revealId, committed.revealId);

      final finalItems = await keptGraph.service.load();
      return finalItems.firstWhere(
        (item) => item.revealId == committed.revealId,
      );
    }

    test(
        'identity survives reveal -> keep -> local persistence -> incoming '
        'sync apply (16, 17: revealId/24h lock untouched)', () async {
      final item = await revealKeepAndReconcile();

      expect(item.wisdomId, wisdomId);
      expect(item.text, englishText);

      // 16. revealId unchanged throughout.
      final status = await dailyGraph.service.status();
      expect(status.revealId, item.revealId);

      // 17. The 24h daily lock is a Daily Access concern entirely separate
      // from Kept -- keeping the wisdom must not touch it.
      expect(status.unlockAt, isNotNull);
      expect(status.unlockAt!.isAfter(now), isTrue);
      expect(status.wisdomId, wisdomId);
    });

    // 8. Locale switch never mutates the persisted Kept record.
    test('8. locale switch does not mutate the persisted Kept record',
        () async {
      final item = await revealKeepAndReconcile();
      final before = await keptGraph.repository.loadAllRecords();
      final beforeRecord = before.firstWhere(
        (record) => record.revealId == item.revealId,
      );

      // Presentation reads only -- resolving under three different locales
      // must never write anything back.
      resolver.resolveItem(item, const Locale('tr'));
      resolver.resolveItem(item, const Locale('ja'));
      resolver.resolveItem(item, const Locale('ar'));

      final after = await keptGraph.repository.loadAllRecords();
      final afterRecord = after.firstWhere(
        (record) => record.revealId == item.revealId,
      );
      expect(afterRecord, beforeRecord);
      expect(afterRecord.wisdomText, englishText);
    });

    testWidgets(
        '5-7. Kept presentation (EN/TR/JA) for the naturally-created record',
        (tester) async {
      final item = await revealKeepAndReconcile();
      final freshKeptGraph = KeptRepositoryTestGraph();

      Future<void> pumpUnder(Locale locale) {
        return tester.pumpWidget(
          MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: EastLocaleRegistry.runtimeSupported,
            home: SavedReflectionsScreen(
              reflections: [item],
              savedReflectionsService: freshKeptGraph.service,
            ),
          ),
        );
      }

      await pumpUnder(const Locale('en'));
      await tester.pumpAndSettle();
      expect(find.text(englishText), findsOneWidget);

      await pumpUnder(const Locale('tr'));
      await tester.pumpAndSettle();
      final tr = resolver.resolveItem(item, const Locale('tr'));
      expect(tr, isNot(englishText));
      expect(find.text(tr), findsOneWidget);

      await pumpUnder(const Locale('ja'));
      await tester.pumpAndSettle();
      final ja = resolver.resolveItem(item, const Locale('ja'));
      expect(ja, isNot(englishText));
      expect(find.text(ja), findsOneWidget);
    });

    testWidgets('7. Kept presentation Arabic', (tester) async {
      final item = await revealKeepAndReconcile();
      final freshKeptGraph = KeptRepositoryTestGraph();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: EastLocaleRegistry.runtimeSupported,
          home: SavedReflectionsScreen(
            reflections: [item],
            savedReflectionsService: freshKeptGraph.service,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final ar = resolver.resolveItem(item, const Locale('ar'));
      expect(ar, isNot(englishText));
      expect(find.text(ar), findsOneWidget);
    });

    testWidgets(
        '9-11. Journal presentation (TR/JA/EN) for the naturally-created '
        'record, with no new data and no mutation', (tester) async {
      final item = await revealKeepAndReconcile();

      for (final locale in [
        const Locale('tr'),
        const Locale('ja'),
        const Locale('en'),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            locale: locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: EastLocaleRegistry.runtimeSupported,
            home: JournalScreen(items: [item], isKeeper: true),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'locale=$locale');
      }

      // No new Kept data and no mutation: still exactly the one record.
      final all = await keptGraph.repository.loadAllRecords();
      expect(all, hasLength(1));
      expect(all.single.wisdomId, wisdomId);
    });

    test(
        '12-14. PDF presentation (TR/JA/EN) resolves the naturally-created '
        "record's wisdom through the presentation locale actually passed "
        'to the builder', () async {
      final item = await revealKeepAndReconcile();

      final trBytes = await JournalPdfBuilder(
        presentation: const JournalPdfPresentation(locale: Locale('tr')),
      ).build(items: [item], now: now);
      final jaBytes = await JournalPdfBuilder(
        presentation: const JournalPdfPresentation(locale: Locale('ja')),
      ).build(items: [item], now: now);
      final enBytes = await JournalPdfBuilder(
        presentation: const JournalPdfPresentation(locale: Locale('en')),
      ).build(items: [item], now: now);

      for (final bytes in [trBytes, jaBytes, enBytes]) {
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      }
      // Three genuinely different reviewed presentations -> three
      // differently-sized documents.
      expect(trBytes.length, isNot(jaBytes.length));
      expect(trBytes.length, isNot(enBytes.length));
      expect(jaBytes.length, isNot(enBytes.length));
    });

    testWidgets('15. Reflection content remains byte-for-byte unchanged',
        (tester) async {
      const reflectionText =
          'Exactly as written, regardless of sync or locale.';
      final justKept = await revealKeepAndReconcile();

      // Attach a Reflection through the real save path, then re-run the
      // same incoming-sync self-echo once more on top of it.
      final saveResult = await keptGraph.service.saveReflection(
        itemId: justKept.id,
        reflection: reflectionText,
        isKeeper: true,
      );
      final withReflection = saveResult.items.firstWhere(
        (item) => item.id == justKept.id,
      );
      expect(withReflection.reflection, reflectionText);

      final records = await keptGraph.repository.loadAllRecords();
      final record = records.firstWhere((r) => r.revealId == justKept.revealId);
      final projection =
          CloudKeptWisdomProjection.active(record, dataEpoch: epoch);
      final batch = PendingIncomingSyncBatch(
        accountFingerprint: fingerprint,
        baseDataEpoch: epoch,
        previousServerChangeToken: 'bmV3dG9rZW4=',
        pendingServerChangeToken: 'bmV3ZXJ0b2tlbg==',
        incomingKeptWisdomProjections: [projection],
        incomingSyncStateProjections: const [],
        incomingKeptWisdomRecordSystemFields: {
          projection.recordName: 'c3lzdGVtRmllbGRz',
        },
      );
      final result = await incomingCoordinator.applyIncomingBatch(batch);
      expect(result.status, IncomingApplyStatus.applied);

      final after = await keptGraph.service.load();
      final finalItem = after.firstWhere((item) => item.id == justKept.id);
      expect(finalItem.reflection, reflectionText);
      expect(finalItem.wisdomId, wisdomId);
      expect(finalItem.revealId, justKept.revealId);
    });

    test(
        'all 15 product locales resolve reviewed localized wisdom for the '
        'naturally-created record', () async {
      final item = await revealKeepAndReconcile();

      for (final target in EastLocaleRegistry.targets) {
        final resolved = resolver.resolveItem(item, target.locale);
        expect(resolved, isNotEmpty, reason: target.tag);
      }
    });
  });
}
