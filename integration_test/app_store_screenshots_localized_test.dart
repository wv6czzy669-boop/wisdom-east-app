import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/data/localized_wisdoms.dart';
import 'package:wisdom_app/data/wisdoms.dart';
import 'package:wisdom_app/l10n/app_localizations.dart';
import 'package:wisdom_app/localization/east_locale_registry.dart';
import 'package:wisdom_app/models/daily_wisdom_record.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/persistence/storage_preferences_adapter.dart';
import 'package:wisdom_app/screens/home_screen.dart';
import 'package:wisdom_app/screens/keeper_screen.dart';
import 'package:wisdom_app/screens/saved_reflections_screen.dart';
import 'package:wisdom_app/services/daily_wisdom_access_service.dart';
import 'package:wisdom_app/services/kept_discovery_hint_service.dart';
import 'package:wisdom_app/services/wisdom_notification_service.dart';
import 'package:wisdom_app/theme/east_design.dart';

import '../test/persistence_test_helpers.dart';

/// EAST. Phase 5F-A -- deterministic, locale-parameterized captures of the
/// six device-containing App Store plates (02 reveal, 03 Kept, 05 Pause,
/// 06 Pause/Feel, 07 Ask from your heart, 09 Keeper). Screenshot-tooling-only
/// infrastructure: exercises real production widgets/localization, never
/// shipped in the app, never alters ritual timing, the 24-hour lock, or any
/// persisted state shape.
///
/// TEST-ONLY -- never the app's entrypoint (see the identical warning atop
/// `app_store_screenshots_test.dart`, and the Phase 5F-B Build 31 incident
/// report: this file, run directly instead of `lib/main.dart`, is what
/// produces an apparently-autonomous ritual/Kept sequence ending in a
/// deliberate blank/black `tester.pumpWidget(const SizedBox.shrink())`
/// teardown -- it is unreachable from any production entrypoint).
///
/// Locale selection: `--dart-define=EAST_LOCALE=<tag>` (one of
/// [EastLocaleRegistry.targets]' tags). Defaults to `en`.
const String _localeTag =
    String.fromEnvironment('EAST_LOCALE', defaultValue: 'en');

const _revealId = 'a5f3c111-1111-4111-8111-111111111111';
const _keptRevealIdA = '00000000-0000-4000-8000-0000000000a1';
const _keptRevealIdB = '00000000-0000-4000-8000-0000000000a2';

// Canonical wisdom IDs backing the captured content -- resolved once via
// `resolveUniqueWisdomIdForEnglishSnapshot` against the exact English text
// the pre-existing English master plates already show, so every locale's
// capture presents a real, reviewed translation of the *same* wisdoms.
const _wisdomIdA = 'east_wisdom_0019'; // "Not every closed door is rejection."
const _wisdomIdB = 'east_wisdom_0222'; // "Stay close to what makes you honest."

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final definition = EastLocaleRegistry.targets.firstWhere(
    (d) => d.tag == _localeTag,
    orElse: () => EastLocaleRegistry.english,
  );
  final locale = definition.locale;

  testWidgets('capture localized App Store device states ($_localeTag)',
      (tester) async {
    if (Platform.isAndroid) {
      await binding.convertFlutterSurfaceToImage();
    }

    await _captureRitualSteps(tester, binding, locale);
    await _captureReveal(tester, binding, locale);
    await _captureKept(tester, binding, locale);
    await _captureKeeper(tester, binding, locale);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

String _wisdomText(String id, String localeTag) {
  if (localeTag == 'en') {
    return wisdoms.firstWhere((w) => w['id'] == id)['text'] as String;
  }
  final catalog = reviewedLocalizedWisdomCatalogs[localeTag];
  final text = catalog?[id];
  if (text == null) {
    throw StateError('No reviewed $localeTag translation for $id');
  }
  return text;
}

Widget _localizedApp(Locale locale, Widget home) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: eastTheme(locale: locale),
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: EastLocaleRegistry.runtimeSupported,
    home: home,
  );
}

Future<void> _resetPreferences() async {
  SharedPreferences.setMockInitialValues({
    WisdomNotificationService.permissionPromptHandledKey: true,
    KeptDiscoveryHintService.completedKey: true,
  });
}

Future<void> _clearCaptureSurface(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

Widget _homeApp({
  required Locale locale,
  required DailyAccessTestGraph dailyGraph,
  required WisdomClock clock,
}) {
  final keptGraph = KeptRepositoryTestGraph();
  final notificationService = WisdomNotificationService(
    platform: _ScreenshotNotificationPlatform(),
    clock: clock,
  );
  return _localizedApp(
    locale,
    HomeScreen(
      clock: clock,
      dailyWisdomAccessService: dailyGraph.service,
      savedReflectionsService: keptGraph.service,
      wisdomNotificationService: notificationService,
      keptDiscoveryHintService: KeptDiscoveryHintService(),
    ),
  );
}

Future<void> _tapCenter(WidgetTester tester) {
  return tester.tap(
    find.byKey(const ValueKey('home-ritual-gesture-surface')),
  );
}

Future<void> _waitForHomeState(
  WidgetTester tester,
  bool Function(dynamic state) condition, {
  int maximumPumps = 240,
}) async {
  for (var attempt = 0; attempt < maximumPumps; attempt += 1) {
    final dynamic state = tester.state(find.byType(HomeScreen));
    if (condition(state)) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
  final dynamic state = tester.state(find.byType(HomeScreen));
  fail(
    'Home did not reach the requested screenshot state ($_localeTag). '
    'screenStep=${state.screenStep}, '
    'transitionInProgress=${state.transitionInProgress}, '
    'pauseFeelOpacity=${state.pauseFeelOpacity}',
  );
}

Future<void> _pumpFrames(
  WidgetTester tester,
  Duration duration, {
  Duration step = const Duration(milliseconds: 100),
}) async {
  var remaining = duration;
  while (remaining > Duration.zero) {
    final next = remaining < step ? remaining : step;
    await tester.pump(next);
    remaining -= next;
  }
}

/// Slots 05 (Pause.), 06 (Pause./Feel.), 07 (Ask from your heart.) -- the
/// same three ritual states the pre-existing intro capture already walks
/// through en route to its own fourth (Reveal) tap, each now captured on
/// the way past.
Future<void> _captureRitualSteps(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  Locale locale,
) async {
  await _clearCaptureSurface(tester);
  await _resetPreferences();
  final now = DateTime.utc(2026, 8, 4, 9, 41);
  await tester.pumpWidget(
    _homeApp(
      locale: locale,
      dailyGraph: DailyAccessTestGraph(
        adapter: _MemoryStoragePreferencesAdapter(),
        clock: () => now,
      ),
      clock: () => now,
    ),
  );
  await _waitForHomeState(
    tester,
    (state) => state.mainRitualActionSemanticsEnabled as bool,
  );

  // Pause.
  await _tapCenter(tester);
  await _waitForHomeState(
    tester,
    (state) => state.screenStep == 1 && !(state.transitionInProgress as bool),
  );
  await _pumpFrames(tester, const Duration(milliseconds: 300));
  await binding.takeScreenshot('05_pause');

  // Pause. Feel.
  await _tapCenter(tester);
  await _waitForHomeState(
    tester,
    (state) =>
        (state.pauseFeelOpacity as double) >= 1.0 &&
        !(state.transitionInProgress as bool),
  );
  await _pumpFrames(tester, const Duration(milliseconds: 300));
  await binding.takeScreenshot('06_pause_feel');

  // Ask from your heart.
  await _tapCenter(tester);
  await _waitForHomeState(
    tester,
    (state) => state.screenStep == 2 && !(state.transitionInProgress as bool),
  );
  await _pumpFrames(tester, const Duration(milliseconds: 500));
  await binding.takeScreenshot('07_ask');
}

/// Slot 02 -- the Reveal screen for an already-unlocked occurrence, matching
/// the exact wisdom (`east_wisdom_0019`) the pre-existing English master
/// shows, translated through the same reviewed catalog every other Flutter
/// surface already uses.
Future<void> _captureReveal(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  Locale locale,
) async {
  await _clearCaptureSurface(tester);
  await _resetPreferences();
  final now = DateTime.utc(2026, 8, 19, 16, 42);
  final wisdomText = _wisdomText(_wisdomIdA, _localeTag);
  final dailyGraph = DailyAccessTestGraph(
    adapter: _MemoryStoragePreferencesAdapter(),
    clock: () => now,
  );
  final revealedAt = now.subtract(
    DailyWisdomRecord.lockDuration - const Duration(hours: 19, minutes: 24),
  );
  await dailyGraph.repository.saveDailyWisdomRecord(
    DailyWisdomRecord(
      text: wisdomText,
      revealedAt: revealedAt,
      unlockAt: revealedAt.add(DailyWisdomRecord.lockDuration),
      revealId: _revealId,
    ),
  );

  await tester.pumpWidget(
    _homeApp(locale: locale, dailyGraph: dailyGraph, clock: () => now),
  );
  await _waitForHomeState(
    tester,
    (state) => state.mainRitualActionSemanticsEnabled as bool,
  );
  await _tapCenter(tester);
  await _waitForHomeState(
    tester,
    (state) => state.screenStep == 4 && !(state.transitionInProgress as bool),
  );
  await _pumpFrames(tester, const Duration(milliseconds: 500));
  expect(find.text(wisdomText), findsOneWidget);
  await binding.takeScreenshot('02_reveal');
}

/// Slot 03 -- the current Kept screen (Back / Kept / icon-only Journal),
/// carrying the same two wisdoms (`east_wisdom_0019` kept without a
/// Reflection, `east_wisdom_0222` kept with one) the pre-existing English
/// master already shows, translated per locale.
Future<void> _captureKept(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  Locale locale,
) async {
  await _clearCaptureSurface(tester);
  await _resetPreferences();
  final keptGraph = KeptRepositoryTestGraph();
  final textA = _wisdomText(_wisdomIdA, _localeTag);
  final textB = _wisdomText(_wisdomIdB, _localeTag);
  // `SavedReflectionsScreen` renders `_items.reversed` (most-recent-first),
  // so listing B before A here is what puts the plain-Kept entry (matching
  // the pre-existing English master's top row) first on screen.
  final items = <FavoriteItem>[
    FavoriteItem(
      id: 'kept-b',
      revealId: _keptRevealIdB,
      date: 'August 19, 2026',
      text: textB,
      reflection: textB,
      reflectedAt: DateTime.utc(2026, 8, 19).toIso8601String(),
      keptAt: DateTime.utc(2026, 8, 19).toIso8601String(),
    ),
    FavoriteItem(
      id: 'kept-a',
      revealId: _keptRevealIdA,
      date: 'August 19, 2026',
      text: textA,
      keptAt: DateTime.utc(2026, 8, 19).toIso8601String(),
    ),
  ];

  // Pushed (never bare-root), for the same reason `_captureKeeper` pushes
  // `KeeperScreen`: production only ever reaches Kept via a real
  // `Navigator.push`, and its leading `EastBackButton` depends on
  // `Navigator.canPop(context)`.
  await tester.pumpWidget(
    _localizedApp(locale, const Scaffold(body: SizedBox.expand())),
  );
  final context = tester.element(find.byType(Scaffold));
  unawaited(
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SavedReflectionsScreen(
          reflections: items,
          savedReflectionsService: keptGraph.service,
        ),
      ),
    ),
  );
  await _pumpFrames(tester, const Duration(milliseconds: 800));
  expect(find.text(textA), findsOneWidget);
  await binding.takeScreenshot('03_kept');
}

/// Slot 09 -- the Keeper screen. `purchaseService` is left uninjected: the
/// visible "Enter the Circle" label never renders a price (only its
/// accessibility semantics do), so no StoreKit/platform-channel mocking is
/// needed for a faithful capture.
Future<void> _captureKeeper(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  Locale locale,
) async {
  await _clearCaptureSurface(tester);
  await _resetPreferences();
  // A real `Navigator.push` onto a throwaway root route, so `KeeperScreen`'s
  // own `Navigator.canPop(context)` is true and its production leading
  // `EastBackButton` renders -- exactly the pushed-screen state the real app
  // is always in when Keeper is reached (Settings -> Keeper), never Keeper
  // as a bare, unreachable-in-production root screen.
  await tester.pumpWidget(
    _localizedApp(locale, const Scaffold(body: SizedBox.expand())),
  );
  final context = tester.element(find.byType(Scaffold));
  unawaited(
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const KeeperScreen()),
    ),
  );
  await _pumpFrames(tester, const Duration(milliseconds: 600));
  await binding.takeScreenshot('09_keeper');
}

class _ScreenshotNotificationPlatform implements WisdomNotificationPlatform {
  @override
  Future<void> initialize() async {}

  @override
  Future<bool?> notificationsEnabled() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime unlockAt,
  }) async {}
}

class _MemoryStoragePreferencesAdapter extends StoragePreferencesAdapter {
  final Map<String, Object> _values = <String, Object>{};

  @override
  Future<String?> getString(String key) async => _values[key] as String?;

  @override
  Future<void> setString(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }
}
