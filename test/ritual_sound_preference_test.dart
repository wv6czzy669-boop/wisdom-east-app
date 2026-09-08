import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/controllers/ritual_sound_preference_controller.dart';
import 'package:wisdom_app/persistence/storage_preferences_adapter.dart';
import 'package:wisdom_app/services/ritual_audio_policy.dart';
import 'package:wisdom_app/screens/ritual_sound_selection_screen.dart';
import 'package:wisdom_app/screens/settings_screen.dart';
import 'package:wisdom_app/l10n/app_localizations.dart';
import 'package:wisdom_app/localization/east_typography_resolver.dart';
import 'package:wisdom_app/theme/east_design.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    for (final font in EastTypographyResolver.productionFonts) {
      await (FontLoader(font.family)..addFont(rootBundle.load(font.asset)))
          .load();
    }
  });
  test('default preserves sound, and silent survives a restart', () async {
    final c = RitualSoundPreferenceController();
    expect(c.canPlay, isFalse);
    await c.load();
    expect(c.canPlay, isTrue);
    await c.setMode(RitualSoundMode.silent);
    final restarted = RitualSoundPreferenceController();
    await restarted.load();
    expect(restarted.canPlay, isFalse);
    expect(restarted.mode, RitualSoundMode.silent);
    c.dispose();
    restarted.dispose();
  });
  test('late restore cannot overwrite a fresh choice and writes stay ordered',
      () async {
    final storage = _SoundStorage();
    storage.pendingRead = Completer<String?>();
    final c = RitualSoundPreferenceController(storage: storage);
    final loading = c.load();
    await c.setMode(RitualSoundMode.silent);
    storage.pendingRead!.complete('sound');
    await loading;
    expect(c.mode, RitualSoundMode.silent);
    final one = c.setMode(RitualSoundMode.sound);
    final two = c.setMode(RitualSoundMode.silent);
    await Future.wait([one, two]);
    expect(storage.value, 'silent');
    c.dispose();
  });
  test('failed persistence keeps the session silent and can be retried',
      () async {
    final storage = _SoundStorage()..fail = true;
    final c = RitualSoundPreferenceController(storage: storage);
    await c.load();
    await c.setMode(RitualSoundMode.silent);
    expect(c.saveFailed, isTrue);
    expect(c.canPlay, isFalse);
    storage.fail = false;
    await c.setMode(c.mode);
    expect(c.saveFailed, isFalse);
    expect(storage.value, 'silent');
    c.dispose();
  });
  test(
      'silent disables every locale audio cue without adding other-language voices',
      () {
    for (final locale in AppLocalizations.supportedLocales) {
      final silent =
          RitualAudioPolicy.forLocale(locale, mode: RitualSoundMode.silent);
      expect(silent.playsVoiceCues, isFalse);
      expect(silent.playsRevealSound, isFalse);
      final audible = RitualAudioPolicy.forLocale(locale);
      expect(audible.playsVoiceCues, locale.languageCode == 'en');
      expect(audible.playsRevealSound, isTrue);
    }
  });
  testWidgets('membership comes first and Settings opens the two sound choices',
      (tester) async {
    final c = RitualSoundPreferenceController();
    await c.load();
    await tester.pumpWidget(
        MaterialApp(home: SettingsScreen(ritualSoundPreferenceController: c)));
    await tester.pumpAndSettle();
    Finder row(String name) => find.byKey(ValueKey('settings-$name-row'));
    expect(tester.getTopLeft(row('keeper')).dy,
        lessThan(tester.getTopLeft(row('restore-purchases')).dy));
    expect(tester.getTopLeft(row('restore-purchases')).dy,
        lessThan(tester.getTopLeft(row('language')).dy));
    await tester.ensureVisible(row('ritual-sound'));
    await tester.tap(row('ritual-sound'));
    await tester.pumpAndSettle();
    expect(find.byType(RitualSoundSelectionScreen), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ritual-sound-silent')));
    await tester.pumpAndSettle();
    expect(c.mode, RitualSoundMode.silent);
    await tester.tap(find.byKey(const ValueKey('east-back-button')));
    await tester.pumpAndSettle();
    expect(find.text('Silent'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });
  testWidgets('both choices fit every language, theme and large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = RitualSoundPreferenceController();
    await c.load();
    for (final locale in AppLocalizations.supportedLocales) {
      for (final brightness in Brightness.values) {
        for (final scale in [1.0, 2.0]) {
          await tester.pumpWidget(MaterialApp(
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: eastTheme(locale: locale, brightness: brightness),
              home: MediaQuery(
                  data: MediaQueryData(
                      size: const Size(320, 740),
                      textScaler: TextScaler.linear(scale)),
                  child: RitualSoundSelectionScreen(controller: c))));
          await tester.pump();
          for (final mode in RitualSoundMode.values) {
            final option = find.byKey(ValueKey('ritual-sound-${mode.name}'));
            await tester.ensureVisible(option);
            await tester.tap(option);
            await tester.pump();
            expect(c.mode, mode);
            expect(tester.takeException(), isNull,
                reason: '$locale $brightness $scale');
          }
        }
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });
}

class _SoundStorage extends StoragePreferencesAdapter {
  Completer<String?>? pendingRead;
  String? value;
  bool fail = false;
  @override
  Future<String?> getString(String key) async =>
      pendingRead == null ? value : await pendingRead!.future;
  @override
  Future<void> setString(String key, String value) async {
    if (fail) throw StateError('unavailable');
    this.value = value;
  }
}
