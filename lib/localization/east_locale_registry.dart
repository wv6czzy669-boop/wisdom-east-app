import 'package:flutter/widgets.dart';

/// EAST.'s reviewed product-language catalog.
enum EastScript { latin, arabic, japanese, korean, traditionalChinese, thai }

class EastLocaleDefinition {
  const EastLocaleDefinition({
    required this.tag,
    required this.nativeName,
    required this.locale,
    required this.script,
    this.isRtl = false,
  });

  final String tag;
  final String nativeName;
  final Locale locale;
  final EastScript script;
  final bool isRtl;
}

abstract final class EastLocaleRegistry {
  static const EastLocaleDefinition english = EastLocaleDefinition(
    tag: 'en',
    nativeName: 'English',
    locale: Locale('en'),
    script: EastScript.latin,
  );

  static const List<EastLocaleDefinition> targets = <EastLocaleDefinition>[
    english,
    EastLocaleDefinition(
        tag: 'tr',
        nativeName: 'Türkçe',
        locale: Locale('tr'),
        script: EastScript.latin),
    EastLocaleDefinition(
        tag: 'ja',
        nativeName: '日本語',
        locale: Locale('ja'),
        script: EastScript.japanese),
    EastLocaleDefinition(
        tag: 'de',
        nativeName: 'Deutsch',
        locale: Locale('de'),
        script: EastScript.latin),
    EastLocaleDefinition(
        tag: 'fr',
        nativeName: 'Français',
        locale: Locale('fr'),
        script: EastScript.latin),
    EastLocaleDefinition(
        tag: 'ko',
        nativeName: '한국어',
        locale: Locale('ko'),
        script: EastScript.korean),
    EastLocaleDefinition(
        tag: 'zh-Hant',
        nativeName: '繁體中文',
        locale: Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
        script: EastScript.traditionalChinese),
    EastLocaleDefinition(
        tag: 'ar',
        nativeName: 'العربية',
        locale: Locale('ar'),
        script: EastScript.arabic,
        isRtl: true),
    EastLocaleDefinition(
        tag: 'es',
        nativeName: 'Español',
        locale: Locale('es'),
        script: EastScript.latin),
    EastLocaleDefinition(
        tag: 'pt-BR',
        nativeName: 'Português (Brasil)',
        locale: Locale.fromSubtags(languageCode: 'pt', countryCode: 'BR'),
        script: EastScript.latin),
    EastLocaleDefinition(
        tag: 'it',
        nativeName: 'Italiano',
        locale: Locale('it'),
        script: EastScript.latin),
    EastLocaleDefinition(
        tag: 'th',
        nativeName: 'ไทย',
        locale: Locale('th'),
        script: EastScript.thai),
    EastLocaleDefinition(
        tag: 'nl',
        nativeName: 'Nederlands',
        locale: Locale('nl'),
        script: EastScript.latin),
    EastLocaleDefinition(
        tag: 'pl',
        nativeName: 'Polski',
        locale: Locale('pl'),
        script: EastScript.latin),
    EastLocaleDefinition(
        tag: 'vi',
        nativeName: 'Tiếng Việt',
        locale: Locale('vi'),
        script: EastScript.latin),
  ];

  /// Only reviewed product locales participate in Flutter runtime selection.
  /// Generic technical ARB fallbacks such as `pt` and `zh` are deliberately
  /// absent: they are implementation fallbacks, not EAST. products.
  static const List<Locale> runtimeSupported = <Locale>[
    Locale('en'),
    Locale('tr'),
    Locale('ja'),
    Locale('de'),
    Locale('fr'),
    Locale('ko'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    Locale('ar'),
    Locale('es'),
    Locale.fromSubtags(languageCode: 'pt', countryCode: 'BR'),
    Locale('it'),
    Locale('th'),
    Locale('nl'),
    Locale('pl'),
    Locale('vi'),
  ];

  static String canonicalTag(Locale locale) {
    final script = locale.scriptCode;
    final region = locale.countryCode;
    return <String>[
      locale.languageCode.toLowerCase(),
      if (script != null && script.isNotEmpty)
        '${script[0].toUpperCase()}${script.substring(1).toLowerCase()}',
      if (region != null && region.isNotEmpty) region.toUpperCase(),
    ].join('-');
  }

  static EastLocaleDefinition definitionFor(Locale locale) {
    final resolved = resolveProductLocale(locale);
    return targets.firstWhere(
      (definition) => canonicalTag(definition.locale) == canonicalTag(resolved),
      orElse: () => english,
    );
  }

  /// Returns an approved product locale for [locale], or English when no
  /// product mapping is safe. Traditional Chinese and Brazilian Portuguese
  /// intentionally require their reviewed script/region forms; `zh-Hans`,
  /// `zh-CN`, and `pt-PT` never cross those product boundaries.
  static Locale? productLocaleOrNull(Locale? locale) {
    if (locale == null) return null;
    final language = locale.languageCode.toLowerCase();
    final script = locale.scriptCode?.toLowerCase();
    final region = locale.countryCode?.toUpperCase();

    if (language == 'zh') {
      if (script == 'hant' ||
          region == 'TW' ||
          region == 'HK' ||
          region == 'MO') {
        return const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
      }
      return null;
    }
    if (language == 'pt') {
      return region == 'BR'
          ? const Locale.fromSubtags(languageCode: 'pt', countryCode: 'BR')
          : null;
    }

    for (final definition in targets) {
      if (definition.locale.languageCode == language) return definition.locale;
    }
    return null;
  }

  static Locale resolveProductLocale(Locale? locale) =>
      productLocaleOrNull(locale) ?? english.locale;

  static bool isProductLocale(Locale locale) =>
      canonicalTag(resolveProductLocale(locale)) == canonicalTag(locale);

  static bool isRtl(Locale locale) => definitionFor(locale).isRtl;

  static TextDirection textDirectionFor(Locale locale) =>
      isRtl(locale) ? TextDirection.rtl : TextDirection.ltr;
}
