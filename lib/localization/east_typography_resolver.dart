import 'package:flutter/material.dart';

import 'east_locale_registry.dart';

/// A bundled production font and the redistribution facts that must remain
/// auditable alongside it.
class EastProductionFont {
  const EastProductionFont({
    required this.family,
    required this.asset,
    required this.script,
    required this.byteLength,
    required this.sourceVersion,
    required this.licenseAsset,
  });

  final String family;
  final String asset;
  final EastScript script;
  final int byteLength;
  final String sourceVersion;
  final String? licenseAsset;
}

/// The complete font plan for one locale. The same plan drives Flutter text,
/// share cards, render QA, and the Journal PDF foundation.
class EastTypographyPlan {
  const EastTypographyPlan({
    required this.family,
    required this.asset,
    required this.fallbacks,
    required this.pdfFallbackAssets,
    required this.script,
  });

  final String family;
  final String asset;
  final List<String> fallbacks;
  final List<String> pdfFallbackAssets;
  final EastScript script;

  String get pdfFontAsset => asset;
  bool get hasEmbeddedPdfFont => true;
}

/// EAST.'s single script-to-production-font registry.
///
/// The five Noto assets are full-glyph static Regular instances, not
/// corpus-only subsets. Consequently locale-controlled copy and arbitrary
/// user Reflection text can use the same deterministic fallback chain without
/// losing characters. Source hashes, build instructions, and the OFL license
/// are retained under `assets/fonts/`.
abstract final class EastTypographyResolver {
  static const EastProductionFont latinFont = EastProductionFont(
    family: 'EBGaramond',
    asset: 'assets/fonts/EBGaramond-Variable.ttf',
    script: EastScript.latin,
    byteLength: 851176,
    sourceVersion: 'existing EAST. production asset',
    licenseAsset: null,
  );
  static const EastProductionFont japaneseFont = EastProductionFont(
    family: 'NotoSerifJP',
    asset: 'assets/fonts/NotoSerifJP-Regular.ttf',
    script: EastScript.japanese,
    byteLength: 8079968,
    sourceVersion: 'noto-cjk 985fa52c81c1; static wght=400',
    licenseAsset: 'assets/fonts/licenses/OFL-NotoCJK.txt',
  );
  static const EastProductionFont koreanFont = EastProductionFont(
    family: 'NotoSerifKR',
    asset: 'assets/fonts/NotoSerifKR-Regular.ttf',
    script: EastScript.korean,
    byteLength: 14122756,
    sourceVersion: 'noto-cjk 985fa52c81c1; static wght=400',
    licenseAsset: 'assets/fonts/licenses/OFL-NotoCJK.txt',
  );
  static const EastProductionFont traditionalChineseFont = EastProductionFont(
    family: 'NotoSerifTC',
    asset: 'assets/fonts/NotoSerifTC-Regular.ttf',
    script: EastScript.traditionalChinese,
    byteLength: 10003632,
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
      fallbacks: <String>[
        ...fallbackFonts.map((font) => font.family),
        'Georgia',
        'serif',
      ],
      pdfFallbackAssets:
          fallbackFonts.map((font) => font.asset).toList(growable: false),
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
