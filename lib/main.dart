import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app.dart';
import 'services/app_services.dart';
import 'sync_runtime/cloud_kit_sync_runtime_coordinator.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Build 26 production cutover: the protected Kept repository (and the
  // migration attempt it depends on) must be fully bootstrapped before the
  // widget tree is built, so every screen's `late final` service reference
  // (`app_services.savedReflectionsService`, `app_services.keptRepository`)
  // is already populated by the time it is first read. No timeout — a slow
  // or failed migration still resolves to a definite, content-safe
  // `KeptBootstrapResult` (see `initializeKeptStorage`), it never hangs
  // silently forever, and it must never race app startup.
  await initializeKeptStorage();

  runApp(const WisdomApp());

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
