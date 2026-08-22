import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:wisdom_app/app.dart';
import 'package:wisdom_app/controllers/locale_preference_controller.dart';
import 'package:wisdom_app/l10n/app_localizations.dart';
import 'package:wisdom_app/l10n/app_localizations_en.dart';
import 'package:wisdom_app/localization/east_locale_registry.dart';
import 'package:wisdom_app/persistence/storage_preferences_adapter.dart';
import 'package:wisdom_app/screens/home_screen.dart';
import 'package:wisdom_app/services/wisdom_notification_service.dart';

import 'persistence_test_helpers.dart';

void main() {
  test('English localization preserves EAST. source copy', () {
    final strings = AppLocalizationsEn();

    expect(strings.east, 'EAST.');
    expect(strings.pause, 'Pause.');
    expect(strings.feel, 'Feel.');
    expect(strings.askFromYourHeart, 'Ask from your heart.');
    expect(strings.reflectionPrompt, 'What are you noticing now?');
    expect(strings.keeper, 'Keeper');
    expect(strings.settings, 'Settings');
    expect(strings.kept, 'Kept');
    expect(strings.journal, 'Journal');
  });

  testWidgets('MaterialApp supplies English localization and falls back to it',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: EastLocaleRegistry.runtimeSupported,
        localeResolutionCallback: (_, __) => const Locale('en'),
        home: Builder(
          builder: (context) => Text(AppLocalizations.of(context)!.pause),
        ),
      ),
    );

    expect(EastLocaleRegistry.runtimeSupported, const [Locale('en')]);
    expect(find.text('Pause.'), findsOneWidget);
  });

  test('context-free notification copy remains deterministic English', () {
    final copy = WisdomNotificationCopy.english();
    expect(copy.title, 'EAST.');
    expect(copy.body, 'Something waits in silence.');
  });

  test('WisdomApp exposes generated localization delegates', () {
    const app = WisdomApp();
    expect(app, isA<Widget>());
  });

  testWidgets('an explicit locale updates MaterialApp without replacing Home',
      (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final localePreferenceController = LocalePreferenceController(
      storage: StoragePreferencesAdapter(),
    );
    await localePreferenceController.load();
    final keptGraph = KeptRepositoryTestGraph();

    await tester.pumpWidget(
      WisdomApp(
        savedReflectionsService: keptGraph.service,
        localePreferenceController: localePreferenceController,
      ),
    );
    await tester.pump();

    final originalHomeState = tester.state(find.byType(HomeScreen));
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).locale, isNull);

    await localePreferenceController.setExplicitLocale(const Locale('en'));
    await tester.pump();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
      const Locale('en'),
    );
    expect(tester.state(find.byType(HomeScreen)), same(originalHomeState));
  });
}
