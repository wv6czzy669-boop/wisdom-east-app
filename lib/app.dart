import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/saved_reflections_service.dart';
import 'theme/east_design.dart';

class WisdomApp extends StatelessWidget {
  const WisdomApp({super.key, this.savedReflectionsService});

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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Daily Wisdom: EAST.',
      debugShowCheckedModeBanner: false,
      theme: eastTheme(),
      home: HomeScreen(savedReflectionsService: savedReflectionsService),
    );
  }
}
