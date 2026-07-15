import 'package:flutter/widgets.dart';

import 'app.dart';
import 'services/app_services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WisdomApp());

  Future.microtask(() async {
    try {
      await purchaseService.init();
    } catch (_) {
      // StoreKit startup failures must never block app startup.
    }
  });
}
