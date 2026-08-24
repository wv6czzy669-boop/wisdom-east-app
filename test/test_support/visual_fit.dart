import 'package:flutter/widgets.dart';
import 'package:wisdom_app/localization/east_locale_registry.dart';
import 'package:wisdom_app/localization/east_typography_resolver.dart';
import 'package:wisdom_app/theme/east_design.dart';

/// Home revealed-wisdom metrics shared by localization and font QA tests.
///
/// This measures rendered height, never characters or words. It lives under
/// `test/` because the production app does not call these measurement helpers.
abstract final class EastVisualFit {
  static const double wisdomFontSize = 38;
  static const double wisdomHeight = 1.48;
  static const double defaultPhoneWidth = 390;
  static const double wisdomWidthFactor = 0.60;
  static const double englishWisdomMaximumHeight = 728;

  static TextStyle get wisdomStyle => const TextStyle(
        fontFamily: EastTypography.fontFamily,
        fontFamilyFallback: EastTypography.fontFamilyFallback,
        fontSize: wisdomFontSize,
        fontWeight: FontWeight.w400,
        height: wisdomHeight,
        letterSpacing: 0.5,
      );

  static TextStyle wisdomStyleForLocale(Locale locale) =>
      EastTypographyResolver.textStyleForLocale(
        locale,
        fontSize: wisdomFontSize,
        fontWeight: FontWeight.w400,
        height: wisdomHeight,
        letterSpacing: 0.5,
      );

  static double measureWisdomHeight(
    String text, {
    double width = defaultPhoneWidth * wisdomWidthFactor,
    Locale locale = const Locale('en'),
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: wisdomStyleForLocale(locale)),
      textDirection: EastLocaleRegistry.textDirectionFor(locale),
      textScaler: TextScaler.noScaling,
      textAlign: TextAlign.center,
    )..layout(maxWidth: width);
    return painter.height;
  }

  static double measureTextHeight(
    String text, {
    required TextStyle style,
    required double width,
    TextDirection direction = TextDirection.ltr,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      textScaler: TextScaler.noScaling,
    )..layout(maxWidth: width);
    return painter.height;
  }
}
