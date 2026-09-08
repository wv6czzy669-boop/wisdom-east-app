import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app.dart';
import 'bootstrap/bootstrap_gate.dart';
import 'controllers/appearance_preference_controller.dart';
import 'controllers/locale_preference_controller.dart';
import 'services/app_services.dart';
import 'sync_runtime/cloud_kit_sync_runtime_coordinator.dart';
import 'utils/date_formatter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Loading this tiny preference alongside the existing mandatory bootstrap
  // ensures MaterialApp has its final locale before the first frame, without
  // introducing a second startup delay or recreating any EAST. services.
  final localePreferenceController = LocalePreferenceController();
  final localePreferenceLoad = localePreferenceController.load();
  // Same reasoning, same startup shape as the locale preference above --
  // Appearance is independent of Language but loads alongside it so
  // MaterialApp has its final ThemeMode before the first frame too (no
  // light-to-dark flash for a returning Dark/Light user).
  final appearancePreferenceController = AppearancePreferenceController();
  final appearancePreferenceLoad = appearancePreferenceController.load();
  final dateFormattingLoad = initializeEastDateFormatting();

  // Keep one authoritative bootstrap Future. BootstrapGate observes this
  // exact instance without timing it out, canceling it, or recreating it, so
  // migration remains single-shot and uninterrupted while Flutter can still
  // paint a safe waiting/error surface immediately.
  final bootstrap = Future.wait<void>([
    initializeKeptStorage(),
    localePreferenceLoad,
    appearancePreferenceLoad,
    ritualSoundPreferenceController.load(),
    dateFormattingLoad,
  ]);

  runApp(
    BootstrapGate(
      bootstrap: bootstrap,
      localePreferenceController: localePreferenceController,
      appearancePreferenceController: appearancePreferenceController,
      readyBuilder: (_) => WisdomApp(
        localePreferenceController: localePreferenceController,
        appearancePreferenceController: appearancePreferenceController,
      ),
    ),
  );

  // Runtime services may only observe fully-initialized app_services late
  // finals. This listens to the same bootstrap Future as BootstrapGate and
  // remains exception-contained if an unexpected bootstrap failure occurs.
  unawaited(bootstrap.then((_) => _startRuntimeServices()).catchError((_) {}));
}

void _startRuntimeServices() {
  Future.microtask(() async {
    try {
      await purchaseService.init();
    } catch (_) {
      // StoreKit startup failures must never block app startup.
    }
  });

  // Build 26 Phase 4F: fire-and-forget startup sync trigger. Scheduled
  // after `runApp` (never delays first frame) and fully exception-contained
  // — a CloudKit sync failure at launch must never block or crash app
  // startup, exactly like the StoreKit initialization above.
  // `CloudKitSyncRuntimeCoordinator._runOnce` already contains every
  // exception from its own four-step pipeline internally; this `catch`
  // exists only as a last-resort safety net around `requestSync` itself.
  Future.microtask(() async {
    try {
      await cloudKitSyncRuntimeCoordinator.requestSync(
        SyncRuntimeTrigger.startup,
      );
    } catch (_) {
      // See comment above: never let a sync failure escape startup.
    }
  });

  // Build 26 Phase 4F: the sole production foreground-resume sync trigger.
  // Registered once, for the app's lifetime — never removed, so no matching
  // `removeObserver` is needed. Deliberately independent of `HomeScreen`'s
  // own `WidgetsBindingObserver` (`lib/screens/home_screen.dart`), which
  // remains entirely ritual-domain (pausing/resuming audio, the countdown,
  // and the pulse animation) and is not modified by this phase.
  WidgetsBinding.instance.addObserver(_CloudKitSyncLifecycleObserver());
  WidgetsBinding.instance.addObserver(_KeeperEntitlementLifecycleObserver());
}

/// Re-checks StoreKit 2 when the app returns to the foreground so refunds
/// and revocations are reflected without requiring a relaunch.
class _KeeperEntitlementLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(purchaseService.reconcileKeeperEntitlement().catchError((_) {}));
  }
}

/// See its registration in [main] for why this exists as an independent
/// observer rather than as logic inside `HomeScreen`.
class _CloudKitSyncLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(
      cloudKitSyncRuntimeCoordinator
          .requestSync(SyncRuntimeTrigger.foreground)
          .catchError((_) {}),
    );
  }
}
