import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/controllers/locale_preference_controller.dart';
import 'package:wisdom_app/persistence/storage_preferences_adapter.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  LocalePreferenceController controller() {
    return LocalePreferenceController(storage: StoragePreferencesAdapter());
  }

  test('a missing preference is System Default', () async {
    final preference = controller();

    await preference.load();

    expect(preference.isSystemDefault, isTrue);
    expect(preference.explicitLocale, isNull);
  });

  test('explicit English persists as its canonical BCP-47 tag', () async {
    final preference = controller();

    await preference.setExplicitLocale(const Locale('en'));

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(LocalePreferenceController.preferenceKey),
      'en',
    );

    final relaunched = controller();
    await relaunched.load();
    expect(relaunched.explicitLocale, const Locale('en'));
  });

  test('System Default removes the explicit override', () async {
    final preference = controller();
    await preference.setExplicitLocale(const Locale('en'));
    await preference.setExplicitLocale(null);

    final prefs = await SharedPreferences.getInstance();
    expect(
        prefs.containsKey(LocalePreferenceController.preferenceKey), isFalse);
    expect(preference.isSystemDefault, isTrue);
  });

  test('corrupt and unsupported values safely become System Default', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      LocalePreferenceController.preferenceKey: 17,
    });
    final corrupt = controller();
    await corrupt.load();
    expect(corrupt.isSystemDefault, isTrue);

    SharedPreferences.setMockInitialValues(<String, Object>{
      LocalePreferenceController.preferenceKey: 'tr-TR',
    });
    final unsupported = controller();
    await unsupported.load();
    expect(unsupported.isSystemDefault, isTrue);
  });

  test('System Default resolves supported devices and falls back to English',
      () {
    const supported = <Locale>[Locale('en')];

    expect(
      LocalePreferenceController.resolveSystemLocale(
        const Locale.fromSubtags(languageCode: 'en', countryCode: 'US'),
        supported,
      ),
      const Locale('en'),
    );
    expect(
      LocalePreferenceController.resolveSystemLocale(
        const Locale.fromSubtags(languageCode: 'tr', countryCode: 'TR'),
        supported,
      ),
      const Locale('en'),
    );
    expect(
      LocalePreferenceController.resolveSystemLocale(
        const Locale.fromSubtags(languageCode: 'ja', countryCode: 'JP'),
        supported,
      ),
      const Locale('en'),
    );
  });

  test('future script and region locale tags remain canonical', () {
    final traditionalChinese = Locale.fromSubtags(
      languageCode: 'zh',
      scriptCode: 'hant',
    );
    final brazilianPortuguese = Locale.fromSubtags(
      languageCode: 'pt',
      countryCode: 'br',
    );

    expect(
      LocalePreferenceController.toBcp47Tag(traditionalChinese),
      'zh-Hant',
    );
    expect(
      LocalePreferenceController.toBcp47Tag(brazilianPortuguese),
      'pt-BR',
    );
    expect(
      LocalePreferenceController.toBcp47Tag(
        LocalePreferenceController.parseBcp47Tag('zh-Hant')!,
      ),
      'zh-Hant',
    );
  });

  test('changing the preference touches no ritual or user-content values',
      () async {
    const dailyAccess = 'unchanged-daily-access';
    const revealId = 'aaaaaaaa-1111-4111-8111-111111111111';
    const wisdomId = 'wisdom-unchanged';
    const reflection = 'A user reflection.';
    SharedPreferences.setMockInitialValues(<String, Object>{
      'daily_access': dailyAccess,
      'reveal_id': revealId,
      'wisdom_id': wisdomId,
      'reflection': reflection,
    });
    final preference = controller();

    await preference.setExplicitLocale(const Locale('en'));
    await preference.setExplicitLocale(null);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('daily_access'), dailyAccess);
    expect(prefs.getString('reveal_id'), revealId);
    expect(prefs.getString('wisdom_id'), wisdomId);
    expect(prefs.getString('reflection'), reflection);
  });
}
