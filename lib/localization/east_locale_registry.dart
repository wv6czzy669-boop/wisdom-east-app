import 'package:flutter/widgets.dart';

/// The full target-language catalog. Only [runtimeSupported] is exposed to
/// Flutter until a locale has reviewed, translated resources.
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

  /// Deliberately remains English-only until translated ARBs exist.
  static const List<Locale> runtimeSupported = <Locale>[Locale('en')];

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
    final tag = canonicalTag(locale);
    return targets.firstWhere(
      (definition) => definition.tag == tag,
      orElse: () => targets.firstWhere(
        (definition) => definition.locale.languageCode == locale.languageCode,
        orElse: () => english,
      ),
    );
  }

  static bool isRtl(Locale locale) => definitionFor(locale).isRtl;

  static TextDirection textDirectionFor(Locale locale) =>
      isRtl(locale) ? TextDirection.rtl : TextDirection.ltr;
}
