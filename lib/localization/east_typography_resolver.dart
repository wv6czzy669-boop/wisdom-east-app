import 'package:flutter/material.dart';

import 'east_locale_registry.dart';

/// Selects a script-appropriate future typography plan in one place.
class EastTypographyPlan {
  const EastTypographyPlan({
    required this.family,
    required this.fallbacks,
    required this.script,
    required this.pdfFontAsset,
  });

  final String family;
  final List<String> fallbacks;
  final EastScript script;

  /// `null` means no explicitly embedded PDF font is bundled yet.
  final String? pdfFontAsset;

  bool get hasEmbeddedPdfFont => pdfFontAsset != null;
}

abstract final class EastTypographyResolver {
  static const String latinAsset = 'assets/fonts/EBGaramond-Variable.ttf';

  static EastTypographyPlan forLocale(Locale locale) {
    switch (EastLocaleRegistry.definitionFor(locale).script) {
      case EastScript.latin:
        return const EastTypographyPlan(
          family: 'EBGaramond',
          fallbacks: <String>['Georgia', 'serif'],
          script: EastScript.latin,
          pdfFontAsset: latinAsset,
        );
      case EastScript.arabic:
        return _missing(EastScript.arabic, 'Noto Naskh Arabic');
      case EastScript.japanese:
        return _missing(EastScript.japanese, 'Noto Serif JP');
      case EastScript.korean:
        return _missing(EastScript.korean, 'Noto Serif KR');
      case EastScript.traditionalChinese:
        return _missing(EastScript.traditionalChinese, 'Noto Serif TC');
      case EastScript.thai:
        return _missing(EastScript.thai, 'Noto Serif Thai');
    }
  }

  static EastTypographyPlan _missing(EastScript script, String family) {
    return EastTypographyPlan(
      family: family,
      fallbacks: <String>[family, 'serif'],
      script: script,
      pdfFontAsset: null,
    );
  }
}
