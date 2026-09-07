import 'package:flutter/material.dart';

import 'east_locale_registry.dart';

/// A bundled production font and the redistribution facts that must remain
/// auditable alongside it.
class EastProductionFont {
  const EastProductionFont({
    required this.family,
    required this.asset,
    String? pdfAsset,
    required this.script,
    required this.byteLength,
    int? pdfByteLength,
    required this.sourceVersion,
    required this.licenseAsset,
  })  : pdfAsset = pdfAsset ?? asset,
        pdfByteLength = pdfByteLength ?? byteLength;

  final String family;

  /// Compact controlled-copy font used by Flutter's UI.
  final String asset;

  /// Full-glyph font retained for arbitrary user text in Journal PDFs.
  final String pdfAsset;
  final EastScript script;
  final int byteLength;
  final int pdfByteLength;
  final String sourceVersion;
  final String? licenseAsset;
}

/// The complete font plan for one locale. Compact app-copy assets drive
/// Flutter text; full PDF assets preserve arbitrary user-written Journal
/// content. Both stay behind this one registry so the two layers cannot
/// silently choose different typography.
class EastTypographyPlan {
  const EastTypographyPlan({
    required this.family,
    required this.asset,
    required this.primaryPdfAsset,
    required this.fallbacks,
    required this.pdfFallbackAssets,
    required this.script,
  });

  final String family;
  final String asset;
  final List<String> fallbacks;
  final List<String> pdfFallbackAssets;
  final EastScript script;

  String get pdfFontAsset => primaryPdfAsset;
  final String primaryPdfAsset;
  bool get hasEmbeddedPdfFont => true;
}

/// EAST.'s single script-to-production-font registry.
///
/// Japanese, Korean, and Traditional Chinese use reproducible controlled-copy
/// subsets in Flutter while retaining full-glyph static Regular instances for
/// arbitrary Reflection text in PDFs. Arabic and Thai are already compact
/// enough to share one full asset. Source hashes, build instructions, and the
/// OFL licenses are retained under `assets/fonts/`.
abstract final class EastTypographyResolver {
  /// PDF-only monochrome emoji fallback. It covers the normalized Unicode
  /// emoji scalar set without the 10 MB bitmap strike carried by
  /// NotoColorEmoji. EAST.'s editorial PDFs are monochrome, so this preserves
  /// every user-visible emoji while removing the package's largest single
  /// avoidable asset.
  static const String pdfEmojiFontAsset = 'assets/fonts/NotoEmoji-Regular.ttf';
  static const int pdfEmojiFontByteLength = 879832;
  static const String pdfEmojiSourceVersion =
      'Noto Emoji v62; Google Fonts monochrome variable instance';
  static const String pdfEmojiLicenseAsset =
      'assets/fonts/licenses/OFL-NotoEmoji.txt';

  static const EastProductionFont latinFont = EastProductionFont(
    family: 'EBGaramond',
    asset: 'assets/fonts/EBGaramond-Variable.ttf',
    script: EastScript.latin,
    byteLength: 851176,
    sourceVersion: 'google/fonts EB Garamond; upstream 106a4a6d3779',
    licenseAsset: 'assets/fonts/licenses/OFL-EBGaramond.txt',
  );
  static const EastProductionFont japaneseFont = EastProductionFont(
    family: 'NotoSerifJP',
    asset: 'assets/fonts/NotoSerifJP-App.ttf',
    pdfAsset: 'assets/fonts/NotoSerifJP-Regular.ttf',
    script: EastScript.japanese,
    byteLength: 494792,
    pdfByteLength: 8079968,
    sourceVersion: 'noto-cjk 985fa52c81c1; static wght=400',
    licenseAsset: 'assets/fonts/licenses/OFL-NotoCJK.txt',
  );
  static const EastProductionFont koreanFont = EastProductionFont(
    family: 'NotoSerifKR',
    asset: 'assets/fonts/NotoSerifKR-App.ttf',
    pdfAsset: 'assets/fonts/NotoSerifKR-Regular.ttf',
    script: EastScript.korean,
    byteLength: 368776,
    pdfByteLength: 14122756,
    sourceVersion: 'noto-cjk 985fa52c81c1; static wght=400',
    licenseAsset: 'assets/fonts/licenses/OFL-NotoCJK.txt',
  );
  static const EastProductionFont traditionalChineseFont = EastProductionFont(
    family: 'NotoSerifTC',
    asset: 'assets/fonts/NotoSerifTC-App.ttf',
    pdfAsset: 'assets/fonts/NotoSerifTC-Regular.ttf',
    script: EastScript.traditionalChinese,
    byteLength: 481376,
    pdfByteLength: 10003632,
    sourceVersion: 'noto-cjk 985fa52c81c1; static wght=400',
    licenseAsset: 'assets/fonts/licenses/OFL-NotoCJK.txt',
  );
  static const EastProductionFont arabicFont = EastProductionFont(
    family: 'NotoNaskhArabic',
    asset: 'assets/fonts/NotoNaskhArabic-Regular.ttf',
    script: EastScript.arabic,
    byteLength: 200416,
    sourceVersion: 'Noto Naskh Arabic 2.021; static wght=400',
    licenseAsset: 'assets/fonts/licenses/OFL-NotoNaskhArabic.txt',
  );
  static const EastProductionFont thaiFont = EastProductionFont(
    family: 'NotoSerifThai',
    asset: 'assets/fonts/NotoSerifThai-Regular.ttf',
    script: EastScript.thai,
    byteLength: 63008,
    sourceVersion: 'Noto Serif Thai 2.002; static wdth=100,wght=400',
    licenseAsset: 'assets/fonts/licenses/OFL-NotoSerifThai.txt',
  );

  static const List<EastProductionFont> productionFonts = <EastProductionFont>[
    latinFont,
    japaneseFont,
    koreanFont,
    traditionalChineseFont,
    arabicFont,
    thaiFont,
  ];

  static EastTypographyPlan forLocale(Locale locale) {
    final primary = _fontForScript(
      EastLocaleRegistry.definitionFor(locale).script,
    );
    final fallbackFonts = productionFonts
        .where((font) => font.family != primary.family)
        .toList(growable: false);
    return EastTypographyPlan(
      family: primary.family,
      asset: primary.asset,
      primaryPdfAsset: primary.pdfAsset,
      fallbacks: <String>[
        ...fallbackFonts.map((font) => font.family),
        'Georgia',
        'serif',
      ],
      pdfFallbackAssets: <String>[
        pdfEmojiFontAsset,
        ...fallbackFonts.map((font) => font.pdfAsset),
      ],
      script: primary.script,
    );
  }

  static TextStyle textStyleForLocale(
    Locale locale, {
    required double fontSize,
    FontWeight fontWeight = FontWeight.w400,
    double? height,
    double? letterSpacing,
    Color? color,
  }) {
    final plan = forLocale(locale);
    return TextStyle(
      color: color,
      fontFamily: plan.family,
      fontFamilyFallback: plan.fallbacks,
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static EastProductionFont _fontForScript(EastScript script) {
    switch (script) {
      case EastScript.latin:
        return latinFont;
      case EastScript.japanese:
        return japaneseFont;
      case EastScript.korean:
        return koreanFont;
      case EastScript.traditionalChinese:
        return traditionalChineseFont;
      case EastScript.arabic:
        return arabicFont;
      case EastScript.thai:
        return thaiFont;
    }
  }
}
