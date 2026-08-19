import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// EAST.'s quiet, printed-page visual system.
///
/// The locked EAST. base field: #E2E0D9.
abstract final class EastColors {
  static const Color background = Color(0xFFE2E0D9);
  static const Color surface = Color(0xFFE2E0D9);
  static const Color ink = Color(0xFF2C2924);
  static const Color secondary = Color(0xFF625D54);
  static const Color utilityInk = Color(0xFF4F4A42);
  static const Color hint = Color(0xFF938D82);
  static const Color divider = Color(0xFFC3BDB2);
  static const Color accent = Color(0xFF8B7652);
  static const Color overlay = Color(0xF0E2E0D9);
}

abstract final class EastTypography {
  static const String fontFamily = 'EBGaramond';
  static const List<String> fontFamilyFallback = <String>['Georgia', 'serif'];

  static TextStyle editorial({
    required double size,
    Color color = EastColors.ink,
    double height = 1.35,
    double letterSpacing = 0.35,
    FontStyle fontStyle = FontStyle.normal,
  }) {
    return TextStyle(
      color: color,
      fontSize: size,
      fontWeight: FontWeight.w400,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      fontStyle: fontStyle,
      height: height,
      letterSpacing: letterSpacing,
    );
  }
}

ThemeData eastTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: EastColors.ink,
    brightness: Brightness.light,
    surface: EastColors.background,
  ).copyWith(
    primary: EastColors.ink,
    onPrimary: EastColors.background,
    secondary: EastColors.accent,
    onSecondary: EastColors.background,
    surface: EastColors.background,
    onSurface: EastColors.ink,
    outline: EastColors.divider,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: EastColors.background,
    canvasColor: EastColors.background,
    dialogTheme: const DialogThemeData(backgroundColor: EastColors.surface),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: EastColors.surface,
      modalBackgroundColor: EastColors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: EastColors.surface,
      contentTextStyle: TextStyle(
        color: EastColors.ink,
        fontFamily: EastTypography.fontFamily,
        fontFamilyFallback: EastTypography.fontFamilyFallback,
      ),
    ),
    dividerTheme: const DividerThemeData(color: EastColors.divider),
    appBarTheme: const AppBarTheme(
      backgroundColor: EastColors.background,
      foregroundColor: EastColors.ink,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
    ),
    textTheme: ThemeData.light().textTheme.apply(
          fontFamily: EastTypography.fontFamily,
          bodyColor: EastColors.ink,
          displayColor: EastColors.ink,
        ),
    cupertinoOverrideTheme: const CupertinoThemeData(
      brightness: Brightness.light,
      primaryColor: EastColors.ink,
      scaffoldBackgroundColor: EastColors.background,
      barBackgroundColor: EastColors.background,
      textTheme: CupertinoTextThemeData(
        textStyle: TextStyle(
          color: EastColors.ink,
          fontFamily: EastTypography.fontFamily,
          fontFamilyFallback: EastTypography.fontFamilyFallback,
        ),
      ),
    ),
  );
}
