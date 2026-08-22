import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/controllers/locale_preference_controller.dart';
import 'package:wisdom_app/l10n/app_localizations.dart';
import 'package:wisdom_app/persistence/storage_preferences_adapter.dart';
import 'package:wisdom_app/screens/settings_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pumpSettings(
    WidgetTester tester,
    LocalePreferenceController controller,
  ) {
    return tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsScreen(localePreferenceController: controller),
      ),
    );
  }

  testWidgets('Settings exposes Language and its current value',
      (tester) async {
    final controller = LocalePreferenceController(
      storage: StoragePreferencesAdapter(),
    );
    await controller.load();
    await pumpSettings(tester, controller);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('settings-language-row')), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('System Default'), findsOneWidget);

    final semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(
        find.byKey(const ValueKey('settings-language-row')),
      ),
      matchesSemantics(
        label: 'Language. Current selection: System Default.',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        isHidden: true,
        hasTapAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('Language screen offers only System Default and English',
      (tester) async {
    final controller = LocalePreferenceController(
      storage: StoragePreferencesAdapter(),
    );
    await pumpSettings(tester, controller);
    await tester.pumpAndSettle();

    final languageRow = find.byKey(const ValueKey('settings-language-row'));
    await tester.ensureVisible(languageRow);
    await tester.tap(languageRow);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('language-system-default-option')),
      findsOneWidget,
    );
    expect(
        find.byKey(const ValueKey('language-english-option')), findsOneWidget);
    expect(find.text('System Default'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('Turkish'), findsNothing);
  });

  testWidgets('selection applies immediately, persists, and is localized',
      (tester) async {
    final controller = LocalePreferenceController(
      storage: StoragePreferencesAdapter(),
    );
    await pumpSettings(tester, controller);
    await tester.pumpAndSettle();

    final languageRow = find.byKey(const ValueKey('settings-language-row'));
    await tester.ensureVisible(languageRow);
    await tester.tap(languageRow);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('language-english-option')));
    await tester.pumpAndSettle();

    expect(controller.explicitLocale, const Locale('en'));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(LocalePreferenceController.preferenceKey), 'en');

    await tester.tap(find.byKey(const ValueKey('east-back-button')));
    await tester.pumpAndSettle();
    expect(find.text('English'), findsOneWidget);

    final settingsLanguageRow =
        find.byKey(const ValueKey('settings-language-row'));
    await tester.ensureVisible(settingsLanguageRow);
    await tester.tap(settingsLanguageRow);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('language-system-default-option')),
    );
    await tester.pumpAndSettle();
    expect(controller.isSystemDefault, isTrue);
    expect(
        prefs.containsKey(LocalePreferenceController.preferenceKey), isFalse);
  });
}
