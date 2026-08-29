import 'dart:async';

import 'package:flutter/material.dart';

import 'controllers/appearance_preference_controller.dart';
import 'controllers/locale_preference_controller.dart';
import 'l10n/app_localizations.dart';
import 'l10n/app_localizations_en.dart';
import 'localization/east_locale_registry.dart';
import 'screens/home_screen.dart';
import 'services/app_services.dart' as app_services;
import 'services/keeper_ritual_widget_coordinator.dart';
import 'services/saved_reflections_service.dart';
import 'services/widget_presentation_sync_coordinator.dart';
import 'services/wisdom_selector.dart';
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

  /// Production supplies one controller loaded before BootstrapGate builds
  /// WisdomApp, while isolated widget hosts may use the screen-local fallback.
  final LocalePreferenceController? localePreferenceController;

  /// Production supplies one controller loaded before BootstrapGate builds
  /// WisdomApp, mirroring [localePreferenceController] exactly -- the two are otherwise fully
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

  // EAST. 1.2 Slice 3 -- the single Medium Widget presentation-sync
  // coordinator, owned here and never moved into HomeScreen or
  // app_services. Uses the exact same locale/appearance controllers this
  // state already owns above, so Appearance and Language stay driven by
  // one source of truth each.
  late final WidgetPresentationSyncCoordinator
      _widgetPresentationSyncCoordinator = WidgetPresentationSyncCoordinator(
    appearanceController: _appearancePreferenceController,
    localeController: _localePreferenceController,
    dailyWisdomAccessService: app_services.createDailyWisdomAccessService(),
    widgetSnapshotService: app_services.widgetSnapshotService,
  );

  // One selector instance is shared by Home and the Keeper widget. This is
  // what prevents two concurrent entry points from consuming two catalog
  // choices for one daily occurrence.
  late final WisdomSelectorService _wisdomSelector = WisdomSelectorService();

  late final KeeperRitualWidgetCoordinator _keeperRitualWidgetCoordinator =
      KeeperRitualWidgetCoordinator(
    appearanceController: _appearancePreferenceController,
    localeController: _localePreferenceController,
    purchaseService: app_services.purchaseService,
    dailyWisdomAccessService: app_services.createDailyWisdomAccessService(),
    dailyWisdomAccessServiceFactory: ({clock}) =>
        app_services.createDailyWisdomAccessService(clock: clock),
    widgetService: app_services.keeperRitualWidgetService,
    wisdomSelector: _wisdomSelector,
  );

  @override
  void initState() {
    super.initState();
    if (widget.localePreferenceController == null) {
      unawaited(_localePreferenceController.load());
    }
    if (widget.appearancePreferenceController == null) {
      unawaited(_appearancePreferenceController.load());
    }
    _widgetPresentationSyncCoordinator.start();
    _keeperRitualWidgetCoordinator.start();
  }

  @override
  void dispose() {
    // Disposed before the preference controllers below, so the coordinator
    // never observes a disposed controller mid-teardown.
    _keeperRitualWidgetCoordinator.dispose();
    _widgetPresentationSyncCoordinator.dispose();
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
            widgetPresentationSyncCoordinator:
                _widgetPresentationSyncCoordinator,
            keeperRitualWidgetCoordinator: _keeperRitualWidgetCoordinator,
            wisdomSelectorService: _wisdomSelector,
          ),
        );
      },
    );
  }
}
