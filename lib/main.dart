import 'package:flutter/widgets.dart';

import 'app.dart';
import 'services/app_services.dart';

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
}
