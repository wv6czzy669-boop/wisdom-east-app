import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../localization/east_typography_resolver.dart';

/// EAST.'s quiet, printed-page visual system.
///
/// The locked EAST. base field: #E2E0D9. Kept exactly as originally
/// authored -- every existing call site (including `const` defaults, e.g.
/// [TopNavRingGeometry.color]) continues to resolve the same Light-mode
/// pixel values it always has. Screens that must react to Appearance read
/// [EastColors.of] instead, which resolves the theme-attached
/// [EastColorScheme] (falling back to [EastColorScheme.light], identical to
/// this class).
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

  /// The active Appearance palette for [context]: [EastColorScheme.dark] in
  /// Dark Mode, [EastColorScheme.light] otherwise. Safe to call before
  /// `MaterialApp` has attached a theme (returns light).
  static EastColorScheme of(BuildContext context) {
    return Theme.of(context).extension<EastColorScheme>() ??
        EastColorScheme.light;
  }
}

/// The same nine-token palette as [EastColors], carried through
/// `ThemeData.extensions` so it can react to Appearance (System/Light/Dark)
/// above `MaterialApp`. [light] is pixel-identical to [EastColors] -- Light
/// Mode is unchanged by this feature.
///
/// [dark] is EAST.'s locked Dark Mode field: background `#1C1B18`, primary
/// text `#D8D4CB`, secondary text/icons `#A9A49B`, divider `#34312C`. Three
/// further tones (`utilityInk`, `hint`, `accent`) are *derived* -- the
/// locked palette only specifies four stops, but the Light palette carries
/// nine -- kept warm/matte/charcoal and proportioned the same way the Light
/// tiers step down from `ink` toward `background`:
///  - `utilityInk`: interpolated 30% from `ink` toward `secondary`, for the
///    same "dark but not headline-weight" body-copy role `utilityInk` plays
///    in Light.
///  - `hint`: interpolated 35% from `secondary` toward `background`, dimmer
///    than secondary text (placeholders/hints must recede) but kept well
///    clear of the divider tone so it never becomes illegible.
///  - `accent`: the Light accent (`#8B7652`) lightened 35% toward `ink` so
///    it stays visible against a dark field without introducing a bright or
///    saturated color.
@immutable
class EastColorScheme extends ThemeExtension<EastColorScheme> {
  const EastColorScheme({
    required this.background,
    required this.surface,
    required this.ink,
    required this.secondary,
    required this.utilityInk,
    required this.hint,
    required this.divider,
    required this.accent,
    required this.overlay,
  });

  final Color background;
  final Color surface;
  final Color ink;
  final Color secondary;
  final Color utilityInk;
  final Color hint;
  final Color divider;
  final Color accent;
  final Color overlay;

  static const EastColorScheme light = EastColorScheme(
    background: EastColors.background,
    surface: EastColors.surface,
    ink: EastColors.ink,
    secondary: EastColors.secondary,
    utilityInk: EastColors.utilityInk,
    hint: EastColors.hint,
    divider: EastColors.divider,
    accent: EastColors.accent,
    overlay: EastColors.overlay,
  );

  static const EastColorScheme dark = EastColorScheme(
    background: Color(0xFF1C1B18),
    surface: Color(0xFF1C1B18),
    ink: Color(0xFFD8D4CB),
    secondary: Color(0xFFA9A49B),
    utilityInk: Color(0xFFCAC6BD),
    hint: Color(0xFF78746D),
    divider: Color(0xFF34312C),
    accent: Color(0xFFA6977C),
    overlay: Color(0xF01C1B18),
  );

  @override
  EastColorScheme copyWith({
    Color? background,
    Color? surface,
    Color? ink,
    Color? secondary,
    Color? utilityInk,
    Color? hint,
    Color? divider,
    Color? accent,
    Color? overlay,
  }) {
    return EastColorScheme(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      ink: ink ?? this.ink,
      secondary: secondary ?? this.secondary,
      utilityInk: utilityInk ?? this.utilityInk,
      hint: hint ?? this.hint,
      divider: divider ?? this.divider,
      accent: accent ?? this.accent,
      overlay: overlay ?? this.overlay,
    );
  }

  @override
  EastColorScheme lerp(ThemeExtension<EastColorScheme>? other, double t) {
    if (other is! EastColorScheme) return this;
    return EastColorScheme(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      utilityInk: Color.lerp(utilityInk, other.utilityInk, t)!,
      hint: Color.lerp(hint, other.hint, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
    );
  }
}

abstract final class EastTypography {
  static const String fontFamily = 'EBGaramond';
  static const List<String> fontFamilyFallback = <String>['Georgia', 'serif'];

  static EastTypographyPlan planFor(BuildContext context) =>
      EastTypographyResolver.forLocale(
        Localizations.maybeLocaleOf(context) ?? const Locale('en'),
      );

  /// The one call site every screen already routes text styling through.
  /// Passing an explicit [color] behaves exactly as before; omitting it now
  /// resolves the *current* theme's ink (light-locked -- unchanged --
  /// wherever Appearance is Light, and EAST.'s locked Dark Mode ink
  /// wherever it is Dark) instead of always defaulting to the static
  /// [EastColors.ink] constant. This is what makes the overwhelming
  /// majority of EAST.'s text Appearance-reactive without touching each of
  /// its call sites individually.
  static TextStyle localized(
    BuildContext context, {
    required double size,
    Color? color,
    double height = 1.35,
    double letterSpacing = 0.35,
    FontStyle fontStyle = FontStyle.normal,
  }) {
    final typography = planFor(context);
    return TextStyle(
      color: color ?? EastColors.of(context).ink,
      fontSize: size,
      fontWeight: FontWeight.w400,
      fontFamily: typography.family,
      fontFamilyFallback: typography.fallbacks,
      fontStyle: fontStyle,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

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

ThemeData eastTheme({
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.light,
}) {
  final typography = EastTypographyResolver.forLocale(locale);
  final palette = brightness == Brightness.dark
      ? EastColorScheme.dark
      : EastColorScheme.light;
  final colorScheme = ColorScheme.fromSeed(
    seedColor: palette.ink,
    brightness: brightness,
    surface: palette.background,
  ).copyWith(
    primary: palette.ink,
    onPrimary: palette.background,
    secondary: palette.accent,
    onSecondary: palette.background,
    surface: palette.background,
    onSurface: palette.ink,
    outline: palette.divider,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    extensions: <ThemeExtension<dynamic>>[palette],
    scaffoldBackgroundColor: palette.background,
    canvasColor: palette.background,
    dialogTheme: DialogThemeData(backgroundColor: palette.surface),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.surface,
      modalBackgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: palette.surface,
      contentTextStyle: TextStyle(
        color: palette.ink,
        fontFamily: typography.family,
        fontFamilyFallback: typography.fallbacks,
      ),
    ),
    dividerTheme: DividerThemeData(color: palette.divider),
    appBarTheme: AppBarTheme(
      backgroundColor: palette.background,
      foregroundColor: palette.ink,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
    ),
    textTheme:
        (brightness == Brightness.dark ? ThemeData.dark() : ThemeData.light())
            .textTheme
            .apply(
              fontFamily: typography.family,
              fontFamilyFallback: typography.fallbacks,
              bodyColor: palette.ink,
              displayColor: palette.ink,
            ),
    cupertinoOverrideTheme: CupertinoThemeData(
      brightness: brightness,
      primaryColor: palette.ink,
      scaffoldBackgroundColor: palette.background,
      barBackgroundColor: palette.background,
      textTheme: CupertinoTextThemeData(
        textStyle: TextStyle(
          color: palette.ink,
          fontFamily: typography.family,
          fontFamilyFallback: typography.fallbacks,
        ),
      ),
    ),
  );
}
