import 'dart:async';

import 'package:flutter/material.dart';

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

  @override
  State<WisdomApp> createState() => _WisdomAppState();
}

class _WisdomAppState extends State<WisdomApp> {
  late final LocalePreferenceController _localePreferenceController =
      widget.localePreferenceController ?? LocalePreferenceController();

  @override
  void initState() {
    super.initState();
    if (widget.localePreferenceController == null) {
      unawaited(_localePreferenceController.load());
    }
  }

  @override
  void dispose() {
    if (widget.localePreferenceController == null) {
      _localePreferenceController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _localePreferenceController,
      builder: (context, _) => MaterialApp(
        title: AppLocalizationsEn().appTitle,
        onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
        debugShowCheckedModeBanner: false,
        theme: eastTheme(
          locale:
              _localePreferenceController.explicitLocale ?? const Locale('en'),
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        // Generated resources include the reviewed Phase 4C catalogs, but
        // only the release-ready registry may participate in runtime locale
        // resolution. The new catalogs remain hidden until wisdoms, fonts,
        // PDFs, and layout regression are complete.
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
        ),
      ),
    );
  }
}
