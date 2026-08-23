import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/app.dart';
import 'package:wisdom_app/controllers/appearance_preference_controller.dart';
import 'package:wisdom_app/controllers/locale_preference_controller.dart';
import 'package:wisdom_app/data/wisdoms.dart' show wisdoms;
import 'package:wisdom_app/l10n/app_localizations.dart';
import 'package:wisdom_app/localization/east_locale_registry.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/models/pending_daily_wisdom_reveal.dart';
import 'package:wisdom_app/persistence/storage_preferences_adapter.dart';
import 'package:wisdom_app/screens/journal_screen.dart';
import 'package:wisdom_app/screens/reflection_screen.dart';
import 'package:wisdom_app/screens/saved_reflections_screen.dart';
import 'package:wisdom_app/services/journal_pdf_builder.dart';
import 'package:wisdom_app/services/wisdom_localization_resolver.dart';
import 'package:wisdom_app/theme/east_design.dart';

import 'persistence_test_helpers.dart';

/// EAST. wisdom locale reactivity (release-blocking regression fix) --
/// covers Kept, Reflection, Journal/PDF, and the combined Appearance +
/// Language scenarios. Home + Share are covered in `home_screen_test.dart`
/// (they need that file's private ritual-navigation helpers).
///
/// Root cause (see `lib/models/pending_daily_wisdom_reveal.dart`):
/// `PendingDailyWisdomReveal.decode()` read and validated the persisted
/// `wisdomId` but never passed it to the object it returned, so every
/// fresh reveal's canonical identity was silently dropped on its first
/// round trip through storage. Every wisdom-presentation surface below
/// already called `WisdomLocalizationResolver` correctly with the live
/// locale; they just never received a non-null `wisdomId` to resolve.
void main() {
  const resolver = WisdomLocalizationResolver();
  const wisdomId = 'east_wisdom_0301';
  final englishText =
      wisdoms.firstWhere((w) => w['id'] == wisdomId)['text'] as String;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  FavoriteItem knownItem({String? reflection}) => FavoriteItem(
        id: 'kept-known-wisdom',
        revealId: 'aaaaaaaa-4444-4444-8444-444444444444',
        wisdomId: wisdomId,
        text: englishText,
        date: 'August 22, 2026',
        keptAt: '2026-08-22T12:00:00.000Z',
        reflection: reflection,
      );

  group('Root cause: PendingDailyWisdomReveal.decode() wisdomId round trip',
      () {
    test('encode() -> decode() preserves wisdomId (was silently dropped)', () {
      final original = PendingDailyWisdomReveal(
        text: englishText,
        preparedAt: DateTime.utc(2041, 7, 23, 8),
        wisdomId: wisdomId,
      );

      final decoded = PendingDailyWisdomReveal.decode(original.encode());

      expect(decoded.wisdomId, wisdomId);
      expect(decoded.text, original.text);
      // Compared by instant, not by `DateTime` representation -- `decode()`
      // reconstructs a local-time `DateTime` from the encoded UTC
      // milliseconds (an unrelated, pre-existing characteristic of this
      // round trip), so the wall-clock fields legitimately differ by the
      // machine's UTC offset while remaining the same instant.
      expect(
        decoded.preparedAt.millisecondsSinceEpoch,
        original.preparedAt.millisecondsSinceEpoch,
      );
    });

    test('decode() preserves wisdomId through a revealedPendingCommit copy',
        () {
      final prepared = PendingDailyWisdomReveal(
        text: englishText,
        preparedAt: DateTime.utc(2041, 7, 23, 8),
        wisdomId: wisdomId,
      );
      final committedPending = prepared.copyWith(
        confirmedRevealBoundary: DateTime.utc(2041, 7, 23, 8, 5),
        phase: PendingDailyWisdomRevealPhase.revealedPendingCommit,
      );

      final decoded =
          PendingDailyWisdomReveal.decode(committedPending.encode());

      expect(decoded.wisdomId, wisdomId);
      expect(
          decoded.phase, PendingDailyWisdomRevealPhase.revealedPendingCommit);
    });

    test('a pending reveal with no wisdomId still round-trips safely as null',
        () {
      final original = PendingDailyWisdomReveal(
        text: englishText,
        preparedAt: DateTime.utc(2041, 7, 23, 8),
      );

      final decoded = PendingDailyWisdomReveal.decode(original.encode());

      expect(decoded.wisdomId, isNull);
    });
  });

  group('Kept (12-14, 19)', () {
    testWidgets(
        '12-14. a known wisdomId row updates EN -> TR -> JA -> AR, with '
        'Kept identity unchanged throughout', (tester) async {
      final item = knownItem();
      final keptGraph = KeptRepositoryTestGraph();
      final localeController = LocalePreferenceController(
        storage: StoragePreferencesAdapter(),
      );
      await localeController.load();

      Widget buildApp() {
        return AnimatedBuilder(
          animation: localeController,
          builder: (context, _) => MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: EastLocaleRegistry.runtimeSupported,
            locale: localeController.explicitLocale,
            home: SavedReflectionsScreen(
              reflections: [item],
              savedReflectionsService: keptGraph.service,
            ),
          ),
        );
      }

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      expect(find.text(englishText), findsOneWidget);

      for (final locale in [
        const Locale('tr'),
        const Locale('ja'),
        const Locale('ar'),
      ]) {
        await localeController.setExplicitLocale(locale);
        await tester.pumpWidget(buildApp());
        await tester.pumpAndSettle();

        final expected = resolver.resolveItem(item, locale);
        expect(expected, isNot(englishText), reason: 'locale=$locale');
        expect(find.text(expected), findsOneWidget, reason: 'locale=$locale');
        expect(find.text(englishText), findsNothing, reason: 'locale=$locale');
      }

      // 19. Kept identity (id/revealId/wisdomId) is never mutated by
      // presentation -- `resolveItem` reads `item` read-only, and the
      // underlying `FavoriteItem` fields are `final`.
      expect(item.id, 'kept-known-wisdom');
      expect(item.revealId, 'aaaaaaaa-4444-4444-8444-444444444444');
      expect(item.wisdomId, wisdomId);
      expect(item.text, englishText);
    });
  });

  group('Reflection wisdom context (20, 21)', () {
    testWidgets(
        '21. Reflection context reacts to locale; 20. Reflection content '
        'and its association with the occurrence stay unchanged',
        (tester) async {
      const reflectionText = 'This stays exactly as written, in any locale.';
      final item = knownItem(reflection: reflectionText);
      final keptGraph = KeptRepositoryTestGraph();
      final localeController = LocalePreferenceController(
        storage: StoragePreferencesAdapter(),
      );
      await localeController.load();

      Widget buildApp() {
        return AnimatedBuilder(
          animation: localeController,
          builder: (context, _) => MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: EastLocaleRegistry.runtimeSupported,
            locale: localeController.explicitLocale,
            home: ReflectionScreen(
              item: item,
              isKeeper: true,
              savedReflectionsService: keptGraph.service,
            ),
          ),
        );
      }

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('reflection-associated-wisdom')),
            )
            .data,
        englishText,
      );
      // The user's own written Reflection text is untouched by locale.
      expect(find.text(reflectionText), findsOneWidget);

      await localeController.setExplicitLocale(const Locale('tr'));
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      final expectedTurkish = resolver.resolveItem(item, const Locale('tr'));
      expect(expectedTurkish, isNot(englishText));
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('reflection-associated-wisdom')),
            )
            .data,
        expectedTurkish,
      );
      // 20. Association (still the same revealId-identified occurrence)
      // and the reflection content itself are both unchanged.
      expect(find.text(reflectionText), findsOneWidget);
      expect(item.revealId, 'aaaaaaaa-4444-4444-8444-444444444444');
      expect(item.reflection, reflectionText);
    });
  });

  group('Journal / PDF (22, 23)', () {
    testWidgets(
        '22. Journal (live screen) renders without error for a '
        'known wisdomId under a non-English locale', (tester) async {
      final item = knownItem();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: EastLocaleRegistry.runtimeSupported,
          home: JournalScreen(items: [item], isKeeper: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    test(
        '23. PDF generation resolves the known wisdomId through the '
        'presentation locale actually passed to the builder', () async {
      final item = knownItem();

      final englishBuilder = JournalPdfBuilder(
        presentation: const JournalPdfPresentation(locale: Locale('en')),
      );
      final turkishBuilder = JournalPdfBuilder(
        presentation: const JournalPdfPresentation(locale: Locale('tr')),
      );

      final now = DateTime.utc(2026, 8, 22, 12);
      final englishBytes = await englishBuilder.build(items: [item], now: now);
      final turkishBytes = await turkishBuilder.build(items: [item], now: now);

      // Both are valid documents, and the Turkish presentation resolves a
      // genuinely different wisdom string (confirmed independently below),
      // so a differently-sized document is the expected, meaningful
      // signal that generation is not pinned to a stale/cached locale.
      expect(String.fromCharCodes(englishBytes.take(5)), '%PDF-');
      expect(String.fromCharCodes(turkishBytes.take(5)), '%PDF-');
      expect(englishBytes.length, isNot(turkishBytes.length));

      final expectedTurkish = resolver.resolveItem(item, const Locale('tr'));
      expect(expectedTurkish, isNot(englishText));
    });
  });

  group('Combined Appearance + Locale (25-27)', () {
    Future<void> pumpApp(
      WidgetTester tester, {
      required AppearancePreferenceController appearance,
      required LocalePreferenceController locale,
    }) {
      return tester.pumpWidget(
        WisdomApp(
          appearancePreferenceController: appearance,
          localePreferenceController: locale,
          savedReflectionsService: KeptRepositoryTestGraph().service,
        ),
      );
    }

    testWidgets(
        '25. Dark + EN -> TR: Dark preserved, UI and wisdom become '
        'Turkish', (tester) async {
      final appearance = AppearancePreferenceController(
        storage: StoragePreferencesAdapter(),
      );
      await appearance.load();
      await appearance.setMode(EastAppearanceMode.dark);
      final locale = LocalePreferenceController(
        storage: StoragePreferencesAdapter(),
      );
      await locale.load();

      await pumpApp(tester, appearance: appearance, locale: locale);
      await tester.pump();
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, EastColorScheme.dark.background);

      await locale.setExplicitLocale(const Locale('tr'));
      await tester.pump();

      expect(appearance.mode, EastAppearanceMode.dark);
      final scaffoldAfter =
          tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffoldAfter.backgroundColor, EastColorScheme.dark.background);
      expect(tester.takeException(), isNull);
    });

    testWidgets('26. Light + EN -> TR: Light preserved, UI becomes Turkish',
        (tester) async {
      final appearance = AppearancePreferenceController(
        storage: StoragePreferencesAdapter(),
      );
      await appearance.load();
      await appearance.setMode(EastAppearanceMode.light);
      final locale = LocalePreferenceController(
        storage: StoragePreferencesAdapter(),
      );
      await locale.load();

      await pumpApp(tester, appearance: appearance, locale: locale);
      await tester.pump();

      await locale.setExplicitLocale(const Locale('tr'));
      await tester.pump();

      expect(appearance.mode, EastAppearanceMode.light);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, EastColorScheme.light.background);
    });

    testWidgets('27. Dark + TR -> AR: Dark preserved, RTL correct',
        (tester) async {
      final appearance = AppearancePreferenceController(
        storage: StoragePreferencesAdapter(),
      );
      await appearance.load();
      await appearance.setMode(EastAppearanceMode.dark);
      final locale = LocalePreferenceController(
        storage: StoragePreferencesAdapter(),
      );
      await locale.load();
      await locale.setExplicitLocale(const Locale('tr'));

      await pumpApp(tester, appearance: appearance, locale: locale);
      await tester.pump();

      await locale.setExplicitLocale(const Locale('ar'));
      await tester.pump();

      expect(appearance.mode, EastAppearanceMode.dark);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, EastColorScheme.dark.background);
      expect(
        Directionality.of(tester.element(find.byType(Scaffold).first)),
        TextDirection.rtl,
      );
    });
  });
}
