import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:wisdom_app/data/localized_wisdoms.dart';
import 'package:wisdom_app/data/wisdoms.dart';
import 'package:wisdom_app/l10n/app_localizations.dart';
import 'package:wisdom_app/localization/east_locale_registry.dart';
import 'package:wisdom_app/localization/east_typography_resolver.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/services/journal_layout.dart';
import 'package:wisdom_app/services/journal_pdf_builder.dart';
import 'package:wisdom_app/services/wisdom_share_service.dart';

import 'test_support/visual_fit.dart';
import 'test_support/wisdom_localization_review.dart';

const _nonLatinTags = <String>['ja', 'ko', 'zh-Hant', 'ar', 'th'];
const _allFitTags = <String>[
  'en',
  'tr',
  'de',
  'fr',
  'ko',
  'ja',
  'zh-Hant',
  'ar',
  'es',
  'pt-BR',
  'it',
  'th',
  'nl',
  'pl',
  'vi',
];

final _englishById = <String, String>{
  for (final wisdom in wisdoms)
    wisdom['id']! as String: wisdom['text']! as String,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    for (final font in EastTypographyResolver.productionFonts) {
      final loader = FontLoader(font.family)
        ..addFont(rootBundle.load(font.asset));
      await loader.load();
    }
  });

  test('production font registry maps every script centrally', () {
    expect(
      EastTypographyResolver.forLocale(const Locale('en')).family,
      'EBGaramond',
    );
    expect(
      EastTypographyResolver.forLocale(const Locale('ja')).family,
      'NotoSerifJP',
    );
    expect(
      EastTypographyResolver.forLocale(const Locale('ko')).family,
      'NotoSerifKR',
    );
    expect(
      EastTypographyResolver.forLocale(
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      ).family,
      'NotoSerifTC',
    );
    expect(
      EastTypographyResolver.forLocale(const Locale('ar')).family,
      'NotoNaskhArabic',
    );
    expect(
      EastTypographyResolver.forLocale(const Locale('th')).family,
      'NotoSerifThai',
    );
    for (final target in EastLocaleRegistry.targets) {
      final plan = EastTypographyResolver.forLocale(target.locale);
      expect(plan.hasEmbeddedPdfFont, isTrue, reason: target.tag);
      expect(plan.pdfFallbackAssets, hasLength(6), reason: target.tag);
      expect(
        plan.pdfFallbackAssets.first,
        EastTypographyResolver.pdfEmojiFontAsset,
        reason: target.tag,
      );
      expect(
        <String>[plan.family, ...plan.fallbacks],
        contains('EBGaramond'),
        reason: target.tag,
      );
    }
    expect(EastLocaleRegistry.runtimeSupported, hasLength(15));
  });

  test('bundled assets, OFL, source documentation, and inventories exist',
      () async {
    expect(
      EastTypographyResolver.productionFonts.map((font) => font.licenseAsset),
      everyElement(isNotNull),
    );
    final licenseAssets = EastTypographyResolver.productionFonts
        .map((font) => font.licenseAsset)
        .whereType<String>()
        .toSet();
    expect(licenseAssets, hasLength(4));
    for (final asset in licenseAssets) {
      final license = await rootBundle.loadString(asset);
      expect(license, contains('SIL OPEN FONT LICENSE'));
      expect(license, contains('Version 1.1'));
    }
    final documentation = File('assets/fonts/README.md').readAsStringSync();
    expect(documentation, contains('985fa52c81c1'));
    expect(documentation, contains('| ar | Noto Naskh Arabic'));
    expect(documentation, contains('2.021'));
    expect(documentation, contains('Noto Serif Thai'));
    expect(documentation, contains('Noto Color Emoji 2.051'));
    expect(documentation, contains('OFL-EBGaramond.txt'));
    expect(documentation, contains('ef9512f92f6d'));

    final emojiLicense = await rootBundle.loadString(
      EastTypographyResolver.pdfEmojiLicenseAsset,
    );
    expect(emojiLicense, contains('SIL OPEN FONT LICENSE'));
    expect(emojiLicense, contains('Version 1.1'));
    final emojiData = await rootBundle.load(
      EastTypographyResolver.pdfEmojiFontAsset,
    );
    expect(
      emojiData.lengthInBytes,
      EastTypographyResolver.pdfEmojiFontByteLength,
    );

    for (final font in EastTypographyResolver.productionFonts) {
      final data = await rootBundle.load(font.asset);
      expect(data.lengthInBytes, font.byteLength, reason: font.family);
      expect(font.sourceVersion, isNotEmpty, reason: font.family);
    }
  });

  test('controlled-copy inventories have real glyphs and shaping tables',
      () async {
    for (final tag in _nonLatinTags) {
      final locale = _localeForTag(tag);
      final plan = EastTypographyResolver.forLocale(locale);
      final fontBytes = await rootBundle.load(plan.asset);
      final font = _TrueTypeFont(fontBytes);
      final inventory =
          await File('assets/fonts/glyphs/$tag.txt').readAsString();
      final missing = inventory.runes
          .where((rune) => String.fromCharCode(rune).trim().isNotEmpty)
          .where((rune) => !font.supports(rune))
          .map((rune) => 'U+${rune.toRadixString(16).toUpperCase()}')
          .toList(growable: false);
      expect(missing, isEmpty, reason: '$tag missing controlled glyphs');
      expect(font.tableTags, containsAll(<String>['GDEF', 'GPOS', 'GSUB']));
      expect(font.tableTags, isNot(contains('fvar')),
          reason: '$tag must be a static production instance');
    }
  });

  testWidgets('all 3015 non-Latin wisdoms fit with production fonts',
      (tester) async {
    const renderedLine =
        EastVisualFit.wisdomFontSize * EastVisualFit.wisdomHeight;
    for (final tag in _nonLatinTags) {
      final locale = _localeForTag(tag);
      final catalog = reviewedLocalizedWisdomCatalogs[tag]!;
      expect(catalog, hasLength(603), reason: tag);
      final suspicious = <String>[];
      for (final entry in catalog.entries) {
        final sourceHeight = EastVisualFit.measureWisdomHeight(
          _englishById[entry.key]!,
        );
        final targetHeight = EastVisualFit.measureWisdomHeight(
          entry.value,
          locale: locale,
        );
        expect(
          targetHeight,
          lessThanOrEqualTo(EastVisualFit.englishWisdomMaximumHeight),
          reason: '$tag/${entry.key} exceeds the 728 px height ceiling',
        );
        final proportionalLimit =
            sourceHeight * 1.75 > sourceHeight + (renderedLine * 2)
                ? sourceHeight * 1.75
                : sourceHeight + (renderedLine * 2);
        if (targetHeight > proportionalLimit) {
          suspicious.add(
            '${entry.key}: $sourceHeight -> $targetHeight '
            '(limit $proportionalLimit)',
          );
        }
      }
      expect(
        suspicious,
        isEmpty,
        reason: '$tag suspicious source-relative expansion:\n'
            '${suspicious.join('\n')}',
      );
    }
  });

  testWidgets('all fifteen wisdom catalogs pass the production height ceiling',
      (tester) async {
    for (final tag in _allFitTags) {
      final locale = _localeForTag(tag);
      final catalog =
          tag == 'en' ? _englishById : reviewedLocalizedWisdomCatalogs[tag]!;
      expect(catalog, hasLength(603), reason: tag);
      for (final entry in catalog.entries) {
        final height = EastVisualFit.measureWisdomHeight(
          entry.value,
          locale: locale,
        );
        expect(
          height,
          lessThanOrEqualTo(EastVisualFit.englishWisdomMaximumHeight),
          reason: '$tag/${entry.key}',
        );
      }
    }
  });

  testWidgets('Arabic joins, uses RTL, and keeps mixed punctuation renderable',
      (tester) async {
    const locale = Locale('ar');
    final style = EastVisualFit.wisdomStyleForLocale(locale);
    final joined = _painter('سلام (123) — حكمةٌ.', style, TextDirection.rtl);
    final separatedWidth = 'سلام'
        .runes
        .map((rune) => _painter(
              String.fromCharCode(rune),
              style,
              TextDirection.rtl,
            ).width)
        .fold<double>(0, (sum, width) => sum + width);
    final joinedWord = _painter('سلام', style, TextDirection.rtl);
    expect(EastLocaleRegistry.textDirectionFor(locale), TextDirection.rtl);
    expect(joined.width, greaterThan(0));
    expect(joinedWord.width, lessThan(separatedWidth));
    expect(joined.computeLineMetrics(), isNotEmpty);
  });

  testWidgets('Thai combining marks shape without vertical clipping',
      (tester) async {
    final painter = _painter(
      'การไตร่ตรองที่ลึกซึ้งขึ้น',
      EastVisualFit.wisdomStyleForLocale(const Locale('th')),
      TextDirection.ltr,
    );
    final lines = painter.computeLineMetrics();
    expect(lines, isNotEmpty);
    expect(painter.height, greaterThan(0));
    for (final line in lines) {
      expect(line.ascent, greaterThan(0));
      expect(line.descent, greaterThanOrEqualTo(0));
      expect(line.height, lessThanOrEqualTo(painter.height));
    }
  });

  testWidgets('reviewed high-risk UI terms fit their production containers',
      (tester) async {
    for (final tag in _nonLatinTags) {
      final locale = _localeForTag(tag);
      final l10n = lookupAppLocalizations(locale);
      final plan = EastTypographyResolver.forLocale(locale);
      final direction = EastLocaleRegistry.textDirectionFor(locale);

      final ritualStyle = TextStyle(
        fontFamily: plan.family,
        fontFamilyFallback: plan.fallbacks,
        fontSize: 60,
        fontWeight: FontWeight.w400,
        height: 1.18,
        letterSpacing: 0.5,
      );
      expect(_painter(l10n.askFrom, ritualStyle, direction).height,
          lessThanOrEqualTo(142));
      expect(_painter(l10n.yourHeart, ritualStyle, direction).height,
          lessThanOrEqualTo(142));

      final keepStyle = TextStyle(
        fontFamily: plan.family,
        fontFamilyFallback: plan.fallbacks,
        fontSize: 14.5,
        fontWeight: FontWeight.w400,
        height: 1.3,
        letterSpacing: 0.4,
      );
      expect(
        _painter(l10n.keepThisWisdom, keepStyle, direction, width: 131).height,
        lessThanOrEqualTo(48),
        reason: '$tag keepThisWisdom',
      );

      final utilityStyle = TextStyle(
        fontFamily: plan.family,
        fontFamilyFallback: plan.fallbacks,
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.35,
        letterSpacing: 1.15,
      );
      for (final text in <String>[
        l10n.kept,
        l10n.addReflection,
        l10n.journal,
        l10n.systemDefault,
      ]) {
        expect(
          _painter(text, utilityStyle, direction, width: 342).height,
          lessThanOrEqualTo(72),
          reason: '$tag/$text',
        );
      }
    }
  });

  test('share renderer selects and paints every non-Latin family', () async {
    const renderer = WisdomShareCardRenderer();
    for (final tag in _nonLatinTags) {
      final locale = _localeForTag(tag);
      final catalog = reviewedLocalizedWisdomCatalogs[tag]!;
      final longest = catalog.values.reduce(
        (a, b) => a.length >= b.length ? a : b,
      );
      final layout = renderer.layoutFor(longest, locale: locale);
      expect(
        layout.fontFamily,
        EastTypographyResolver.forLocale(locale).family,
      );
      expect(
        layout.textDirection,
        EastLocaleRegistry.textDirectionFor(locale),
      );
      expect(layout.didExceedMaxLines, isFalse, reason: tag);
      expect(layout.textSize.height, lessThanOrEqualTo(980), reason: tag);
      final png = await renderer.renderForLocale(longest, locale: locale);
      expect(png.length, greaterThan(1000), reason: tag);
      expect(png.take(8), <int>[137, 80, 78, 71, 13, 10, 26, 10]);
    }
  });

  test('Journal PDFs embed locale fonts with cross-script Reflection fallback',
      () async {
    const reflection = 'Latin reflection. 日本語 한국어 繁體中文 العربية ไทย';
    for (final tag in _nonLatinTags) {
      final locale = _localeForTag(tag);
      final direction = EastLocaleRegistry.textDirectionFor(locale);
      final original = FavoriteItem(
        id: 'font-$tag',
        revealId: 'reveal-$tag',
        text: reviewedLocalizedWisdomCatalogs[tag]!.values.first,
        date: '23 AUG 2026',
        reflection: reflection,
        keptAt: DateTime.utc(2026, 8, 23).toIso8601String(),
      );
      final warnings = <String>[];
      final bytes = await runZoned(
        () => JournalPdfBuilder(
          localizations: lookupAppLocalizations(locale),
          presentation: JournalPdfPresentation(
            locale: locale,
            textDirection: direction,
          ),
        ).build(
          items: <FavoriteItem>[original],
          ownerName: 'EAST. 日本語 العربية ไทย',
          now: DateTime.utc(2026, 8, 23),
          compress: false,
        ),
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => warnings.add(line),
        ),
      );
      expect(bytes.length, greaterThan(1000), reason: tag);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(
        warnings.where((line) => line.contains('Unable to find a font')),
        isEmpty,
        reason: '$tag PDF missing-glyph warnings: $warnings',
      );
      expect(original.reflection, reflection, reason: tag);
      expect(original.text, reviewedLocalizedWisdomCatalogs[tag]!.values.first);
    }
    expect(JournalBodyLayout.folioAlignment, pw.Alignment.centerRight);
  });

  test('release build permanently enables package:pdf Arabic shaping', () {
    final release = File('ios/Flutter/Release.xcconfig').readAsStringSync();
    final debug = File('ios/Flutter/Debug.xcconfig').readAsStringSync();
    const encodedUseArabic = 'dXNlX2FyYWJpYz10cnVl';
    expect(release, contains(encodedUseArabic));
    expect(debug, contains(encodedUseArabic));
  });

  test('Phase 5B closes only the five real-font review blockers', () {
    for (final tag in _nonLatinTags) {
      expect(
        wisdomLocalizationReviewSummaries[tag]!.finalFontRenderQaRequired,
        isFalse,
        reason: tag,
      );
    }
  });
}

TextPainter _painter(
  String text,
  TextStyle style,
  TextDirection direction, {
  double width = 234,
}) {
  return TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: direction,
    textAlign: TextAlign.center,
    textScaler: TextScaler.noScaling,
  )..layout(maxWidth: width);
}

Locale _localeForTag(String tag) {
  switch (tag) {
    case 'zh-Hant':
      return const Locale.fromSubtags(
        languageCode: 'zh',
        scriptCode: 'Hant',
      );
    case 'pt-BR':
      return const Locale.fromSubtags(languageCode: 'pt', countryCode: 'BR');
    default:
      return Locale(tag);
  }
}

class _TrueTypeFont {
  _TrueTypeFont(ByteData data) : _data = data {
    final tableCount = _u16(4);
    for (var index = 0; index < tableCount; index++) {
      final record = 12 + (index * 16);
      final tag = String.fromCharCodes(<int>[
        _u8(record),
        _u8(record + 1),
        _u8(record + 2),
        _u8(record + 3),
      ]);
      _tables[tag] = _u32(record + 8);
    }
    final cmap = _tables['cmap']!;
    final subtableCount = _u16(cmap + 2);
    for (var index = 0; index < subtableCount; index++) {
      final record = cmap + 4 + (index * 8);
      final platform = _u16(record);
      final encoding = _u16(record + 2);
      final offset = cmap + _u32(record + 4);
      final format = _u16(offset);
      if ((platform == 0 || platform == 3) && format == 12) {
        _format12 = offset;
      } else if ((platform == 0 || (platform == 3 && encoding == 1)) &&
          format == 4) {
        _format4 = offset;
      }
    }
  }

  final ByteData _data;
  final Map<String, int> _tables = <String, int>{};
  int? _format12;
  int? _format4;

  Set<String> get tableTags => _tables.keys.toSet();

  bool supports(int codePoint) {
    final format12 = _format12;
    if (format12 != null && _supportsFormat12(format12, codePoint)) {
      return true;
    }
    final format4 = _format4;
    return codePoint <= 0xFFFF &&
        format4 != null &&
        _supportsFormat4(format4, codePoint);
  }

  bool _supportsFormat12(int offset, int codePoint) {
    final groups = _u32(offset + 12);
    var low = 0;
    var high = groups - 1;
    while (low <= high) {
      final middle = (low + high) >> 1;
      final group = offset + 16 + (middle * 12);
      final start = _u32(group);
      final end = _u32(group + 4);
      if (codePoint < start) {
        high = middle - 1;
      } else if (codePoint > end) {
        low = middle + 1;
      } else {
        return _u32(group + 8) + codePoint - start != 0;
      }
    }
    return false;
  }

  bool _supportsFormat4(int offset, int codePoint) {
    final segmentCount = _u16(offset + 6) ~/ 2;
    final endCodes = offset + 14;
    final startCodes = endCodes + (segmentCount * 2) + 2;
    final deltas = startCodes + (segmentCount * 2);
    final rangeOffsets = deltas + (segmentCount * 2);
    for (var index = 0; index < segmentCount; index++) {
      final end = _u16(endCodes + (index * 2));
      if (codePoint > end) continue;
      final start = _u16(startCodes + (index * 2));
      if (codePoint < start) return false;
      final delta = _u16(deltas + (index * 2));
      final rangeOffsetAddress = rangeOffsets + (index * 2);
      final rangeOffset = _u16(rangeOffsetAddress);
      if (rangeOffset == 0) return ((codePoint + delta) & 0xFFFF) != 0;
      final glyphAddress =
          rangeOffsetAddress + rangeOffset + ((codePoint - start) * 2);
      var glyph = _u16(glyphAddress);
      if (glyph == 0) return false;
      glyph = (glyph + delta) & 0xFFFF;
      return glyph != 0;
    }
    return false;
  }

  int _u8(int offset) => _data.getUint8(offset);
  int _u16(int offset) => _data.getUint16(offset, Endian.big);
  int _u32(int offset) => _data.getUint32(offset, Endian.big);
}
