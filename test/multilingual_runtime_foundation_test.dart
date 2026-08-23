import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/data/wisdoms.dart';
import 'package:wisdom_app/localization/east_locale_registry.dart';
import 'package:wisdom_app/localization/east_typography_resolver.dart';
import 'package:wisdom_app/localization/visual_fit.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/services/ritual_audio_policy.dart';
import 'package:wisdom_app/services/journal_pdf_builder.dart';
import 'package:wisdom_app/services/wisdom_localization_resolver.dart';
import 'package:wisdom_app/utils/date_formatter.dart';

void main() {
  test('target registry preserves all fifteen canonical locale tags', () {
    expect(EastLocaleRegistry.targets, hasLength(15));
    expect(
      EastLocaleRegistry.canonicalTag(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      ),
      'zh-Hant',
    );
    expect(
      EastLocaleRegistry.canonicalTag(
        const Locale.fromSubtags(languageCode: 'pt', countryCode: 'BR'),
      ),
      'pt-BR',
    );
    expect(EastLocaleRegistry.runtimeSupported, const <Locale>[Locale('en')]);
  });

  test('Arabic is RTL and every other current target is LTR', () {
    for (final target in EastLocaleRegistry.targets) {
      expect(
        EastLocaleRegistry.textDirectionFor(target.locale),
        target.tag == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      );
    }
  });

  test('ritual audio keeps English voice and universal arrival sound', () {
    expect(
        RitualAudioPolicy.forLocale(const Locale('en')).playsVoiceCues, isTrue);
    expect(RitualAudioPolicy.forLocale(const Locale('tr')).playsVoiceCues,
        isFalse);
    expect(RitualAudioPolicy.forLocale(const Locale('ar')).playsVoiceCues,
        isFalse);
    expect(RitualAudioPolicy.forLocale(const Locale('en')).playsRevealSound,
        isTrue);
    expect(RitualAudioPolicy.forLocale(const Locale('ja')).playsRevealSound,
        isTrue);
  });

  test('dates use CLDR ordering while legacy display remains available',
      () async {
    await initializeEastDateFormatting();
    final date = DateTime(2026, 8, 22);
    expect(formatFavoriteDisplayDate(date), 'August 22, 2026');
    expect(formatFavoriteDisplayDate(date, localeTag: 'tr'), '22 Ağustos 2026');
    expect(formatFavoriteDisplayDate(date, localeTag: 'ja'), '2026年8月22日');
    expect(
      formatLocalizedDateOrLegacy(
        timestamp: null,
        legacyDisplay: 'August 22, 2026',
        localeTag: 'tr',
      ),
      'August 22, 2026',
    );
  });

  test('typography resolver uses Latin Garamond and reports PDF blockers', () {
    final latin = EastTypographyResolver.forLocale(const Locale('tr'));
    final arabic = EastTypographyResolver.forLocale(const Locale('ar'));
    expect(latin.family, 'EBGaramond');
    expect(latin.hasEmbeddedPdfFont, isTrue);
    expect(arabic.family, 'Noto Naskh Arabic');
    expect(arabic.hasEmbeddedPdfFont, isFalse);
  });

  test(
      'non-Latin Journal PDF presentation fails safely until a font is bundled',
      () async {
    final builder = JournalPdfBuilder(
      presentation: const JournalPdfPresentation(
        locale: Locale('ar'),
        textDirection: TextDirection.rtl,
      ),
    );
    await expectLater(
      builder.build(items: const <FavoriteItem>[], now: DateTime.utc(2026)),
      throwsA(isA<UnsupportedError>()),
    );
  });

  test('wisdom resolution is presentation-only and preserves legacy fallback',
      () {
    final first = wisdoms.first;
    final resolver = WisdomLocalizationResolver();
    expect(
      resolver.resolve(
        wisdomId: first['id'] as String,
        locale: const Locale('sv'),
        persistedSnapshot: 'legacy',
      ),
      first['text'],
    );
    expect(
      resolver.resolve(
        wisdomId: null,
        locale: const Locale('tr'),
        persistedSnapshot: 'legacy snapshot',
      ),
      'legacy snapshot',
    );
  });

  testWidgets(
      'visual measurements are deterministic and the English corpus fits',
      (tester) async {
    final heights = wisdoms
        .map((wisdom) =>
            EastVisualFit.measureWisdomHeight(wisdom['text'] as String))
        .toList(growable: false);
    final maximum = heights.reduce((a, b) => a > b ? a : b);

    expect(EastVisualFit.measureWisdomHeight('Pause.'),
        EastVisualFit.measureWisdomHeight('Pause.'));
    expect(maximum, EastVisualFit.englishWisdomMaximumHeight);
    expect(
      heights,
      everyElement(lessThanOrEqualTo(EastVisualFit.englishWisdomMaximumHeight)),
    );
  });
}
