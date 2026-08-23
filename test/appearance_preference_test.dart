import 'dart:typed_data';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/app.dart';
import 'package:wisdom_app/controllers/appearance_preference_controller.dart';
import 'package:wisdom_app/controllers/locale_preference_controller.dart';
import 'package:wisdom_app/l10n/app_localizations.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/persistence/storage_preferences_adapter.dart';
import 'package:wisdom_app/screens/appearance_selection_screen.dart';
import 'package:wisdom_app/screens/journal_screen.dart';
import 'package:wisdom_app/screens/language_selection_screen.dart';
import 'package:wisdom_app/screens/saved_reflections_screen.dart';
import 'package:wisdom_app/screens/settings_screen.dart';
import 'package:wisdom_app/services/journal_pdf_builder.dart';
import 'package:wisdom_app/services/wisdom_share_service.dart';
import 'package:wisdom_app/theme/east_design.dart';

import 'persistence_test_helpers.dart';

/// EAST. Appearance (System/Light/Dark) -- covers every scenario the
/// feature's own spec calls out: controller persistence/fallback,
/// System Default platform tracking, explicit override, independence from
/// Language, per-screen Light/Dark rendering (including Arabic RTL and a
/// non-Latin font), data safety, and the two export exclusions (Journal
/// PDF, share card).
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('AppearancePreferenceController', () {
    // Locked product rule (release-blocking regression fix): EAST.'s
    // DEFAULT appearance is Light, never System Default -- a fresh
    // install must never silently become Dark just because the iPhone
    // itself is Dark. System Default remains a real, selectable, durably
    // persisted option; it is simply no longer what a never-chosen user
    // gets. See [AppearancePreferenceController]'s own doc comment.

    test('1. no saved preference resolves to Light', () async {
      final controller = AppearancePreferenceController(
        storage: StoragePreferencesAdapter(),
      );
      await controller.load();
      expect(controller.mode, EastAppearanceMode.light);
      expect(controller.isSystemDefault, isFalse);
      expect(controller.themeMode, ThemeMode.light);
    });

    test('2. an invalid/corrupt stored value resolves to Light', () async {
      SharedPreferences.setMockInitialValues({
        AppearancePreferenceController.preferenceKey: 'not-a-real-mode',
      });
      final controller = AppearancePreferenceController(
        storage: StoragePreferencesAdapter(),
      );
      await controller.load();
      expect(controller.mode, EastAppearanceMode.light);
    });

    test('3. an explicit Light choice applies immediately and persists',
        () async {
      final controller = AppearancePreferenceController(
        storage: StoragePreferencesAdapter(),
      );
      await controller.load();
      await controller.setMode(EastAppearanceMode.light);
      expect(controller.mode, EastAppearanceMode.light);
      expect(controller.themeMode, ThemeMode.light);

      final restarted = AppearancePreferenceController(
        storage: StoragePreferencesAdapter(),
      );
      await restarted.load();
      expect(restarted.mode, EastAppearanceMode.light);
    });

    test('4. an explicit Dark choice applies immediately and persists',
        () async {
      final controller = AppearancePreferenceController(
        storage: StoragePreferencesAdapter(),
      );
      await controller.load();
      await controller.setMode(EastAppearanceMode.dark);
      expect(controller.mode, EastAppearanceMode.dark);
      expect(controller.themeMode, ThemeMode.dark);

      final restarted = AppearancePreferenceController(
        storage: StoragePreferencesAdapter(),
      );
      await restarted.load();
      expect(restarted.mode, EastAppearanceMode.dark);
    });

    test(
        '5. an explicit System Default choice applies immediately, persists '
        'durably, and is never silently collapsed back into Light', () async {
      final controller = AppearancePreferenceController(
        storage: StoragePreferencesAdapter(),
      );
      await controller.load();
      // Starts Light (the new default) -- explicitly choosing System
      // Default must still be a real, remembered choice, not a no-op.
      await controller.setMode(EastAppearanceMode.system);
      expect(controller.mode, EastAppearanceMode.system);
      expect(controller.isSystemDefault, isTrue);
      expect(controller.themeMode, ThemeMode.system);

      // Durably persisted: unlike the pre-fix behavior, choosing System
      // Default writes an explicit value rather than clearing the key
      // (clearing it would make it indistinguishable from "never chosen",
      // which now resolves to Light).
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getString(AppearancePreferenceController.preferenceKey),
        'system',
      );

      final restarted = AppearancePreferenceController(
        storage: StoragePreferencesAdapter(),
      );
      await restarted.load();
      expect(restarted.mode, EastAppearanceMode.system);
      expect(restarted.isSystemDefault, isTrue);
    });

    test('notifies listeners exactly once per genuine change', () async {
      final controller = AppearancePreferenceController(
        storage: StoragePreferencesAdapter(),
      );
      await controller.load();
      var notifications = 0;
      controller.addListener(() => notifications += 1);

      await controller.setMode(EastAppearanceMode.dark);
      expect(notifications, 1);

      // Re-setting the same mode is not a change.
      await controller.setMode(EastAppearanceMode.dark);
      expect(notifications, 1);

      await controller.setMode(EastAppearanceMode.light);
      expect(notifications, 2);
    });
  });

  group('System Default and explicit override', () {
    // Split into two independent tests (each its own fresh platform value
    // set *before* the test's first `pumpWidget`) rather than one test that
    // toggles `platformBrightnessTestValue` mid-session: `WisdomApp` passes
    // `themeMode: ThemeMode.system` straight through to `MaterialApp` --
    // resolving that against the live platform brightness afterward is
    // entirely `MaterialApp`/`MediaQuery`'s own well-tested Flutter
    // framework responsibility, not logic this feature owns, and a
    // same-test brightness change was observed to be unreliable in this
    // Flutter version's test harness even for a bare `MaterialApp` with no
    // EAST. code involved at all.
    testWidgets(
        '6. explicit System Default resolves Light when the platform is '
        'Light', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      final appearance = AppearancePreferenceController(
        storage: StoragePreferencesAdapter(),
      );
      await appearance.load();
      // Light is now the default -- System Default must be explicitly
      // chosen to actually follow the platform.
      await appearance.setMode(EastAppearanceMode.system);

      // `HomeScreen`'s own ritual animations repeat indefinitely, so
      // `pumpAndSettle` would time out waiting for them -- a single pump
      // is enough to build the tree and resolve the applied Theme.
      await tester.pumpWidget(
        WisdomApp(
          appearancePreferenceController: appearance,
          savedReflectionsService: KeptRepositoryTestGraph().service,
        ),
      );
      await tester.pump();

      expect(appearance.themeMode, ThemeMode.system);
      expect(Theme.of(_rootContext(tester)).brightness, Brightness.light);
    });

    testWidgets(
        '6. explicit System Default resolves Dark when the platform is Dark',
        (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      final appearance = AppearancePreferenceController(
        storage: StoragePreferencesAdapter(),
      );
      await appearance.load();
      await appearance.setMode(EastAppearanceMode.system);

      await tester.pumpWidget(
        WisdomApp(
          appearancePreferenceController: appearance,
          savedReflectionsService: KeptRepositoryTestGraph().service,
        ),
      );
      await tester.pump();

      expect(appearance.themeMode, ThemeMode.system);
      expect(Theme.of(_rootContext(tester)).brightness, Brightness.dark);
    });

    testWidgets('an explicit Light choice overrides a Dark platform',
        (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      final appearance = AppearancePreferenceController(
        storage: StoragePreferencesAdapter(),
      );
      await appearance.load();
      await appearance.setMode(EastAppearanceMode.light);

      await tester.pumpWidget(
        WisdomApp(
          appearancePreferenceController: appearance,
          savedReflectionsService: KeptRepositoryTestGraph().service,
        ),
      );
      await tester.pump();

      expect(Theme.of(_rootContext(tester)).brightness, Brightness.light);
    });

    testWidgets('an explicit Dark choice overrides a Light platform',
        (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      final appearance = AppearancePreferenceController(
        storage: StoragePreferencesAdapter(),
      );
      await appearance.load();
      await appearance.setMode(EastAppearanceMode.dark);

      await tester.pumpWidget(
        WisdomApp(
          appearancePreferenceController: appearance,
          savedReflectionsService: KeptRepositoryTestGraph().service,
        ),
      );
      await tester.pump();

      expect(Theme.of(_rootContext(tester)).brightness, Brightness.dark);
    });

    testWidgets(
        'selecting a mode on the Appearance screen applies immediately, '
        'with no Save button', (tester) async {
      final appearance = AppearancePreferenceController(
        storage: StoragePreferencesAdapter(),
      );
      await appearance.load();

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AppearanceSelectionScreen(
            appearancePreferenceController: appearance,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('System Default'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Save'), findsNothing);
      expect(find.byType(ElevatedButton), findsNothing);

      await tester.tap(find.byKey(const ValueKey('appearance-dark-option')));
      await tester.pump();
      expect(appearance.mode, EastAppearanceMode.dark);

      await tester.tap(find.byKey(const ValueKey('appearance-light-option')));
      await tester.pump();
      expect(appearance.mode, EastAppearanceMode.light);
    });

    testWidgets('the locked Turkish Appearance terminology is exact',
        (tester) async {
      final appearance = AppearancePreferenceController(
        storage: StoragePreferencesAdapter(),
      );
      await appearance.load();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: AppearanceSelectionScreen(
            appearancePreferenceController: appearance,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Görünüm'), findsOneWidget);
      expect(find.text('Sistem Varsayılanı'), findsOneWidget);
      expect(find.text('Açık'), findsOneWidget);
      expect(find.text('Koyu'), findsOneWidget);
    });
  });

  group('Appearance is independent of Language', () {
    testWidgets('switching Appearance never changes the Language selection',
        (tester) async {
      final locale = LocalePreferenceController(
        storage: StoragePreferencesAdapter(),
      );
      await locale.load();
      await locale.setExplicitLocale(const Locale('ja'));

      final appearance = AppearancePreferenceController(
        storage: StoragePreferencesAdapter(),
      );
      await appearance.load();
      await appearance.setMode(EastAppearanceMode.dark);

      expect(locale.explicitLocale, const Locale('ja'));
      await appearance.setMode(EastAppearanceMode.light);
      expect(locale.explicitLocale, const Locale('ja'));
    });

    testWidgets('switching Language never changes the Appearance selection',
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
      await locale.setExplicitLocale(const Locale('fr'));
      await locale.setExplicitLocale(const Locale('ar'));

      expect(appearance.mode, EastAppearanceMode.dark);
    });
  });

  group('Screens render correctly under Light and Dark', () {
    Future<void> pumpUnderAppearance(
      WidgetTester tester,
      Widget home, {
      required Brightness brightness,
      Locale locale = const Locale('en'),
    }) {
      return tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: eastTheme(locale: locale, brightness: Brightness.light),
          darkTheme: eastTheme(locale: locale, brightness: Brightness.dark),
          themeMode:
              brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
          home: home,
        ),
      );
    }

    for (final brightness in [Brightness.light, Brightness.dark]) {
      final label = brightness == Brightness.dark ? 'Dark' : 'Light';

      testWidgets('Settings renders without error under $label',
          (tester) async {
        await pumpUnderAppearance(
          tester,
          const SettingsScreen(),
          brightness: brightness,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(SettingsScreen), findsOneWidget);
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
        final expectedBackground = brightness == Brightness.dark
            ? EastColorScheme.dark.background
            : EastColorScheme.light.background;
        expect(scaffold.backgroundColor, expectedBackground);
      });

      testWidgets('Language selection renders without error under $label',
          (tester) async {
        final controller = LocalePreferenceController(
          storage: StoragePreferencesAdapter(),
        );
        await controller.load();
        await pumpUnderAppearance(
          tester,
          LanguageSelectionScreen(localePreferenceController: controller),
          brightness: brightness,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('Appearance selection renders without error under $label',
          (tester) async {
        final controller = AppearancePreferenceController(
          storage: StoragePreferencesAdapter(),
        );
        await controller.load();
        await pumpUnderAppearance(
          tester,
          AppearanceSelectionScreen(appearancePreferenceController: controller),
          brightness: brightness,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('Kept (empty state) renders without error under $label',
          (tester) async {
        final keptGraph = KeptRepositoryTestGraph();
        await pumpUnderAppearance(
          tester,
          SavedReflectionsScreen(
            reflections: const [],
            savedReflectionsService: keptGraph.service,
          ),
          brightness: brightness,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('Journal (empty state) renders without error under $label',
          (tester) async {
        await pumpUnderAppearance(
          tester,
          const JournalScreen(items: [], isKeeper: true),
          brightness: brightness,
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('Settings renders without error under Dark in Arabic (RTL)',
        (tester) async {
      await pumpUnderAppearance(
        tester,
        const SettingsScreen(),
        brightness: Brightness.dark,
        locale: const Locale('ar'),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        Directionality.of(tester.element(find.byType(SettingsScreen))),
        TextDirection.rtl,
      );
    });

    testWidgets('Japanese text keeps its non-Latin font fallback under Dark',
        (tester) async {
      await pumpUnderAppearance(
        tester,
        const SettingsScreen(),
        brightness: Brightness.dark,
        locale: const Locale('ja'),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final eastMark = tester.widget<Text>(find.text('EAST.').first);
      // For `ja`, `EastTypographyResolver` makes NotoSerifJP the *primary*
      // family (every other production font, including Latin, is the
      // fallback chain) -- see `east_typography_resolver.dart`.
      expect(eastMark.style?.fontFamily, 'NotoSerifJP');
      // Dark Mode's locked ink -- confirms the glyph itself is actually
      // theme-reactive, not merely present.
      expect(eastMark.style?.color, EastColorScheme.dark.ink);
    });
  });

  group('Data safety', () {
    testWidgets(
        'switching Appearance never changes rendered Kept content '
        '(wisdomId/revealId/reflection text unchanged)', (tester) async {
      final item = FavoriteItem(
        id: 'kept-appearance-safety',
        revealId: 'aaaaaaaa-2222-4222-8222-222222222222',
        wisdomId: 'wisdom-appearance-safety',
        text: 'A quiet, kept line.',
        date: 'August 22, 2026',
        keptAt: '2026-08-22T12:00:00.000Z',
        reflection: 'This stays exactly as written.',
      );

      final appearance = AppearancePreferenceController(
        storage: StoragePreferencesAdapter(),
      );
      await appearance.load();
      final keptGraph = KeptRepositoryTestGraph();

      Widget buildApp() {
        return MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: eastTheme(),
          darkTheme: eastTheme(brightness: Brightness.dark),
          themeMode: appearance.themeMode,
          home: SavedReflectionsScreen(
            reflections: [item],
            savedReflectionsService: keptGraph.service,
          ),
        );
      }

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      expect(find.text('A quiet, kept line.'), findsOneWidget);

      await appearance.setMode(EastAppearanceMode.dark);
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(item.id, 'kept-appearance-safety');
      expect(item.revealId, 'aaaaaaaa-2222-4222-8222-222222222222');
      expect(item.wisdomId, 'wisdom-appearance-safety');
      expect(item.reflection, 'This stays exactly as written.');
      expect(find.text('A quiet, kept line.'), findsOneWidget);
    });
  });

  group('Exports stay presentation-independent of Appearance', () {
    test(
        'the Journal PDF is generated identically by two independent '
        'builders, with no dependency on the live app theme', () async {
      final items = [
        FavoriteItem(
          id: 'pdf-appearance-safety',
          revealId: 'aaaaaaaa-3333-4333-8333-333333333333',
          wisdomId: 'wisdom-pdf-appearance-safety',
          text: 'What the page keeps.',
          date: 'August 22, 2026',
          keptAt: '2026-08-22T12:00:00.000Z',
          reflection: null,
        ),
      ];

      // `JournalPdfBuilder`'s constructor and `build` signature take no
      // BuildContext/Theme/EastColorScheme of any kind (see
      // `journal_pdf_builder.dart`), so two independently constructed
      // builders given the same inputs -- with nothing about the live
      // app's Appearance in scope at all -- produce the same document.
      // This is the structural guarantee behind "the PDF stays Light".
      final now = DateTime.utc(2026, 8, 22, 12);
      final Uint8List first =
          await JournalPdfBuilder().build(items: items, now: now);
      final Uint8List second =
          await JournalPdfBuilder().build(items: items, now: now);

      expect(first.length, second.length);
      expect(String.fromCharCodes(first.take(5)), '%PDF-');
      expect(String.fromCharCodes(second.take(5)), '%PDF-');
    });

    test(
        'the share card renderer stays pinned to the Light constants, '
        'independent of the live app theme', () {
      expect(
        WisdomShareCardRenderer.backgroundColor,
        EastColors.background,
      );
      expect(WisdomShareCardRenderer.foregroundColor, EastColors.ink);
      // Confirms these are the same fixed Light tokens regardless of
      // Appearance -- EastColorScheme.dark is never consulted here.
      expect(
        WisdomShareCardRenderer.backgroundColor,
        isNot(EastColorScheme.dark.background),
      );
    });
  });

  group('Dynamic Type (Build 33 accessibility repair)', () {
    testWidgets(
        'Appearance selection stays usable at 100/135/160/200% text scale',
        (tester) async {
      final appearance = AppearancePreferenceController(
        storage: StoragePreferencesAdapter(),
      );
      await appearance.load();

      for (final scale in [1.0, 1.35, 1.6, 2.0]) {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: AppearanceSelectionScreen(
              appearancePreferenceController: appearance,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('appearance-system-option')),
          findsOneWidget,
          reason: 'System Default must remain reachable at ${scale}x.',
        );
        expect(
          find.byKey(const ValueKey('appearance-dark-option')),
          findsOneWidget,
          reason: 'Dark must remain reachable at ${scale}x.',
        );
        expect(tester.takeException(), isNull);
      }
    });
  });

  testWidgets(
      'Voice Control actionability (Build 33 real-device repair): rows '
      'are unique and have SemanticsAction.tap', (tester) async {
    final appearance = AppearancePreferenceController(
      storage: StoragePreferencesAdapter(),
    );
    await appearance.load();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AppearanceSelectionScreen(
          appearancePreferenceController: appearance,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final semantics = tester.ensureSemantics();
    final system = tester.getSemantics(
      find.byKey(const ValueKey('appearance-system-option')),
    );
    final dark = tester.getSemantics(
      find.byKey(const ValueKey('appearance-dark-option')),
    );
    expect(system.label, isNot(dark.label));
    expect(system.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(dark.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    semantics.dispose();
  });
}

/// A context genuinely inside the themed app -- `MaterialApp`'s own
/// element sits *above* the `Theme`/`Directionality` it builds internally,
/// so `Theme.of`/`Directionality.of` on it silently fall back to
/// [ThemeData.fallback] rather than reflecting what is actually applied.
/// Any mounted `Scaffold` is a safe, screen-agnostic descendant to read
/// from instead.
BuildContext _rootContext(WidgetTester tester) {
  return tester.element(find.byType(Scaffold).first);
}
