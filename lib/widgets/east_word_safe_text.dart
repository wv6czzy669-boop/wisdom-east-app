import 'package:flutter/widgets.dart';

import '../localization/east_locale_registry.dart';

/// Renders editorial text without allowing Flutter to split a word between
/// two lines in languages whose reviewed typography uses whitespace-delimited
/// words.
///
/// East Asian and Thai scripts retain their native character-level wrapping.
/// The original string remains the semantic value. Any line breaks calculated
/// here are presentation-only and never reach persistence, sharing, or
/// VoiceOver.
class EastWordSafeText extends StatelessWidget {
  const EastWordSafeText(
    this.text, {
    super.key,
    required this.style,
    this.textAlign = TextAlign.start,
    this.preferredLineWidth,
  });

  static final RegExp _whitespace = RegExp(r'\s+');

  /// The widest reviewed whitespace-delimited token in each locale catalog.
  ///
  /// Fitting against this locale-level reference (rather than [text]) keeps
  /// every wisdom at exactly the same type size on the same device. A catalog
  /// regression test proves that no current token is wider than its reference.
  static const Map<String, String> _widestReviewedTokens = <String, String>{
    'en': 'self-abandonment.',
    'tr': 'düzenleyemediğini',
    'de': 'Selbstverteidigung',
    'fr': 'qu’impressionnant.',
    'ar': 'والانكماش.',
    'es': 'arrepentimiento.',
    'pt-BR': 'desaparecimento.',
    'it': 'riconoscimento.',
    'nl': 'onderscheidingsvermogen',
    'pl': 'błogosławieństwami',
    'vi': 'nhường.',
  };

  final String text;
  final TextStyle style;
  final TextAlign textAlign;

  /// EAST.'s preferred editorial measure. A reviewed long word may use more
  /// of the available hard width, but ordinary lines retain this narrower
  /// measure and remain centered.
  final double? preferredLineWidth;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context) ?? const Locale('en');
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final protectsWords = _protectsWhitespaceDelimitedWords(locale);

    return LayoutBuilder(
      builder: (context, constraints) {
        final fittedStyle = protectsWords && constraints.maxWidth.isFinite
            ? _fitUniformLocaleStyle(
                style,
                maxWidth: constraints.maxWidth,
                locale: locale,
                direction: direction,
                scaler: scaler,
              )
            : style;
        final lineWidth = preferredLineWidth == null
            ? constraints.maxWidth
            : preferredLineWidth!.clamp(1.0, constraints.maxWidth).toDouble();
        final displayText = protectsWords && constraints.maxWidth.isFinite
            ? _wrapOnlyAtWhitespace(
                text,
                style: fittedStyle,
                maxWidth: lineWidth,
                locale: locale,
                direction: direction,
                scaler: scaler,
              )
            : text;

        return Text.rich(
          TextSpan(
            text: displayText,
            // Keeps widget tests, accessibility tooling, and any semantic
            // reader on the clean source string rather than exposing the
            // presentation-only line breaks.
            semanticsLabel: text,
          ),
          textAlign: textAlign,
          locale: locale,
          style: fittedStyle,
        );
      },
    );
  }

  static bool _protectsWhitespaceDelimitedWords(Locale locale) {
    switch (EastLocaleRegistry.definitionFor(locale).script) {
      case EastScript.latin:
      case EastScript.arabic:
        return true;
      case EastScript.japanese:
      case EastScript.korean:
      case EastScript.traditionalChinese:
      case EastScript.thai:
        return false;
    }
  }

  TextStyle _fitUniformLocaleStyle(
    TextStyle source, {
    required double maxWidth,
    required Locale locale,
    required TextDirection direction,
    required TextScaler scaler,
  }) {
    final fontSize = source.fontSize;
    final widestToken =
        _widestReviewedTokens[EastLocaleRegistry.canonicalTag(locale)];
    if (fontSize == null || widestToken == null || maxWidth <= 0) {
      return source;
    }

    var fitted = source;
    var widestWidth = _measure(
      widestToken,
      style: fitted,
      locale: locale,
      direction: direction,
      scaler: scaler,
    );
    if (widestWidth <= maxWidth) return source;

    var scale = 1.0;
    for (var attempt = 0; attempt < 4 && widestWidth > maxWidth; attempt++) {
      scale *= (maxWidth / widestWidth) * 0.995;
      fitted = source.copyWith(
        fontSize: fontSize * scale,
        letterSpacing:
            source.letterSpacing == null ? null : source.letterSpacing! * scale,
      );
      widestWidth = _measure(
        widestToken,
        style: fitted,
        locale: locale,
        direction: direction,
        scaler: scaler,
      );
    }
    return fitted;
  }

  String _wrapOnlyAtWhitespace(
    String source, {
    required TextStyle style,
    required double maxWidth,
    required Locale locale,
    required TextDirection direction,
    required TextScaler scaler,
  }) {
    return source.split('\n').map((paragraph) {
      final words = paragraph.trim().split(_whitespace);
      if (words.length <= 1) return paragraph;

      final lines = <String>[];
      var line = words.first;
      for (final word in words.skip(1)) {
        final candidate = '$line $word';
        if (_measure(
              candidate,
              style: style,
              locale: locale,
              direction: direction,
              scaler: scaler,
            ) <=
            maxWidth) {
          line = candidate;
        } else {
          lines.add(line);
          line = word;
        }
      }
      lines.add(line);
      return lines.join('\n');
    }).join('\n');
  }

  double _measure(
    String value, {
    required TextStyle style,
    required Locale locale,
    required TextDirection direction,
    required TextScaler scaler,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: direction,
      textScaler: scaler,
      locale: locale,
      maxLines: 1,
    )..layout();
    return painter.width;
  }
}
