import 'dart:async';

import 'package:flutter/material.dart';

import 'controllers/appearance_preference_controller.dart';
import 'controllers/locale_preference_controller.dart';
import 'l10n/app_localizations.dart';
import 'l10n/app_localizations_en.dart';
import 'localization/east_locale_registry.dart';
import 'screens/home_screen.dart';
import 'services/saved_reflections_service.dart';
import 'theme/east_design.dart';

class WisdomApp extends StatefulWidget {
  const WisdomApp({
    super.key,
    this.savedReflectionsService,
    this.localePreferenceController,
    this.appearancePreferenceController,
  });

  /// Test-only injection seam. Always `null` in the real app (`main.dart`
  /// never passes this) — `HomeScreen`'s own existing fallback
  /// (`widget.savedReflectionsService ?? app_services.savedReflectionsService`)
  /// then reaches the production global exactly as before this field
  /// existed. Only isolated widget tests that mount `WisdomApp` itself
  /// (rather than `HomeScreen` directly) need to pass a test-owned
  /// `SavedReflectionsService` here, so `HomeScreen`'s `initState` never
  /// falls through to the uninitialized production
  /// `app_services.savedReflectionsService` (only populated by production's
  /// own `initializeKeptStorage()`, which isolated widget tests never run).
  /// No storage is lazily initialized and no bootstrap failure is caught or
  /// hidden here — this only changes which `SavedReflectionsService`
  /// instance `HomeScreen` receives, nothing about when or how it is built.
  final SavedReflectionsService? savedReflectionsService;

  /// Production supplies one controller loaded before `runApp`, while
  /// isolated widget hosts may safely use the screen-local fallback.
  final LocalePreferenceController? localePreferenceController;

  /// Production supplies one controller loaded before `runApp`, mirroring
  /// [localePreferenceController] exactly -- the two are otherwise fully
  /// independent (Appearance and Language never read or gate each other).
  final AppearancePreferenceController? appearancePreferenceController;

  @override
  State<WisdomApp> createState() => _WisdomAppState();
}

class _WisdomAppState extends State<WisdomApp> {
  late final LocalePreferenceController _localePreferenceController =
      widget.localePreferenceController ?? LocalePreferenceController();
  late final AppearancePreferenceController _appearancePreferenceController =
      widget.appearancePreferenceController ?? AppearancePreferenceController();

  @override
  void initState() {
    super.initState();
    if (widget.localePreferenceController == null) {
      unawaited(_localePreferenceController.load());
    }
    if (widget.appearancePreferenceController == null) {
      unawaited(_appearancePreferenceController.load());
    }
  }

  @override
  void dispose() {
    if (widget.localePreferenceController == null) {
      _localePreferenceController.dispose();
    }
    if (widget.appearancePreferenceController == null) {
      _appearancePreferenceController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(
        [_localePreferenceController, _appearancePreferenceController],
      ),
      builder: (context, _) {
        final effectiveThemeLocale =
            _localePreferenceController.explicitLocale ??
                EastLocaleRegistry.resolveProductLocale(
                  WidgetsBinding.instance.platformDispatcher.locale,
                );
        return MaterialApp(
          title: AppLocalizationsEn().appTitle,
          onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
          debugShowCheckedModeBanner: false,
          theme: eastTheme(locale: effectiveThemeLocale),
          darkTheme: eastTheme(
            locale: effectiveThemeLocale,
            brightness: Brightness.dark,
          ),
          themeMode: _appearancePreferenceController.themeMode,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: EastLocaleRegistry.runtimeSupported,
          locale: _localePreferenceController.explicitLocale,
          localeResolutionCallback: (deviceLocale, supportedLocales) {
            return LocalePreferenceController.resolveSystemLocale(
              deviceLocale,
              supportedLocales,
            );
          },
          home: HomeScreen(
            savedReflectionsService: widget.savedReflectionsService,
            localePreferenceController: _localePreferenceController,
            appearancePreferenceController: _appearancePreferenceController,
          ),
        );
      },
    );
  }
}
