import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/controllers/locale_preference_controller.dart';
import 'package:wisdom_app/data/wisdoms.dart';
import 'package:wisdom_app/l10n/app_localizations.dart';
import 'package:wisdom_app/localization/east_locale_registry.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/persistence/storage_preferences_adapter.dart';
import 'package:wisdom_app/services/ritual_audio_policy.dart';
import 'package:wisdom_app/services/wisdom_localization_resolver.dart';
import 'package:wisdom_app/services/wisdom_share_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('runtime exposes exactly the fifteen approved product locales', () {
    final tags = EastLocaleRegistry.runtimeSupported
        .map(EastLocaleRegistry.canonicalTag)
        .toList(growable: false);

    expect(tags, EastLocaleRegistry.targets.map((item) => item.tag));
    expect(tags, hasLength(15));
    expect(tags, isNot(contains('pt')));
    expect(tags, isNot(contains('zh')));
    expect(tags, isNot(contains('zh-Hans')));
  });

  test('System Default maps only safe platform forms to product locales', () {
    final supported = EastLocaleRegistry.runtimeSupported;
    final deviceLocales = <Locale>[
      const Locale('en'),
      const Locale('tr'),
      const Locale('ja'),
      const Locale('de'),
      const Locale('fr'),
      const Locale('ko'),
      const Locale.fromSubtags(languageCode: 'zh', countryCode: 'TW'),
      const Locale('ar'),
      const Locale('es'),
      const Locale.fromSubtags(languageCode: 'pt', countryCode: 'BR'),
      const Locale('it'),
      const Locale('th'),
      const Locale('nl'),
      const Locale('pl'),
      const Locale('vi'),
    ];

    for (var index = 0; index < deviceLocales.length; index++) {
      final deviceLocale = deviceLocales[index];
      expect(
        EastLocaleRegistry.canonicalTag(
          LocalePreferenceController.resolveSystemLocale(
              deviceLocale, supported),
        ),
        EastLocaleRegistry.targets[index].tag,
      );
    }
    expect(
      LocalePreferenceController.resolveSystemLocale(
        const Locale.fromSubtags(languageCode: 'zh', countryCode: 'CN'),
        supported,
      ),
      const Locale('en'),
    );
    expect(
      LocalePreferenceController.resolveSystemLocale(
        const Locale.fromSubtags(languageCode: 'pt', countryCode: 'PT'),
        supported,
      ),
      const Locale('en'),
    );
  });

  test('explicit locale survives restart and System Default removes only it',
      () async {
    final controller = LocalePreferenceController(
      storage: StoragePreferencesAdapter(),
    );
    await controller.setExplicitLocale(const Locale('ja'));
    final restarted = LocalePreferenceController(
      storage: StoragePreferencesAdapter(),
    );
    await restarted.load();
    expect(restarted.explicitLocale, const Locale('ja'));

    await restarted.setExplicitLocale(null);
    expect(restarted.isSystemDefault, isTrue);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.containsKey(LocalePreferenceController.preferenceKey),
      isFalse,
    );
  });

  test('known occurrences switch presentation without changing their data', () {
    final source = wisdoms.first;
    final item = FavoriteItem(
      id: 'kept-1',
      revealId: 'aaaaaaaa-1111-4111-8111-111111111111',
      wisdomId: source['id'] as String,
      text: source['text'] as String,
      date: 'August 22, 2026',
      keptAt: '2026-08-22T12:00:00.000Z',
      reflection: 'Bugün biraz daha sakin hissediyorum.',
    );
    const resolver = WisdomLocalizationResolver();

    final english = resolver.resolveItem(item, const Locale('en'));
    final turkish = resolver.resolveItem(item, const Locale('tr'));
    final japanese = resolver.resolveItem(item, const Locale('ja'));
    expect(english, source['text']);
    // Phase 5G real-device scenario: EN -> TR -> JA, proving the known
    // wisdomId presentation change spans all three, never just a single
    // locale pair.
    expect(turkish, isNot(english));
    expect(japanese, isNot(english));
    expect(japanese, isNot(turkish));
    expect(item.id, 'kept-1');
    expect(item.revealId, 'aaaaaaaa-1111-4111-8111-111111111111');
    expect(item.wisdomId, source['id']);
    expect(item.reflection, 'Bugün biraz daha sakin hissediyorum.');

    final legacy = FavoriteItem(
      id: item.id,
      revealId: item.revealId,
      text: item.text,
      date: item.date,
      keptAt: item.keptAt,
      reflection: item.reflection,
    );
    expect(resolver.resolveItem(legacy, const Locale('ja')), item.text);
  });

  test('all products boot reviewed UI, share typography, and audio policy',
      () async {
    const shareRenderer = WisdomShareCardRenderer();
    for (final target in EastLocaleRegistry.targets) {
      final strings = await AppLocalizations.delegate.load(target.locale);
      final layout = shareRenderer.layoutFor(strings.askFromYourHeart,
          locale: target.locale);
      expect(strings.appTitle, isNotEmpty, reason: target.tag);
      expect(layout.fontFamily, isNotEmpty, reason: target.tag);
      expect(
        layout.textDirection,
        target.tag == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        reason: target.tag,
      );
      expect(
        RitualAudioPolicy.forLocale(target.locale).playsVoiceCues,
        target.tag == 'en',
        reason: target.tag,
      );
      expect(
        RitualAudioPolicy.forLocale(target.locale).playsRevealSound,
        isTrue,
      );
    }
  });
}
