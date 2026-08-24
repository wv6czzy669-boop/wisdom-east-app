// TEST-ONLY -- never the app's entrypoint. This file is a
// `flutter_test`/`integration_test` target; it is reachable only via
// `flutter drive --driver=test_driver/app_store_screenshots_driver.dart
// --target=integration_test/app_store_screenshots_test.dart` (or an
// equivalent `flutter test integration_test/...` invocation). It is never
// imported by `lib/main.dart` or anything it depends on, so it cannot be
// compiled into `Runner`/a Release archive or a TestFlight/App Store build
// -- Dart's AOT compiler only includes code reachable from the declared
// entrypoint, and no production entrypoint references this file.
//
// Build 31 incident (Phase 5F-B): running this file *as if it were the
// app* -- e.g. via an IDE's "Run"/▶ button while this file (not
// `lib/main.dart`) is the active editor tab/launch target -- looks exactly
// like the app acting autonomously: `IntegrationTestWidgetsFlutterBinding`
// drives real `tester.tap()` calls through the ritual with no human touch,
// pushes the real `SavedReflectionsScreen`/`JournalScreen` routes, and the
// final `tester.pumpWidget(const SizedBox.shrink())` below intentionally
// blanks the whole widget tree (a black screen) as test teardown. If you
// see this sequence on a real device/simulator, you are looking at this
// file being driven, not the shipped app -- always launch EAST. itself via
// the `Runner` scheme / `flutter run`/`flutter build` targeting
// `lib/main.dart`, never this one.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/models/daily_wisdom_record.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/persistence/storage_preferences_adapter.dart';
import 'package:wisdom_app/screens/home_screen.dart';
import 'package:wisdom_app/screens/journal_screen.dart';
import 'package:wisdom_app/screens/reflection_screen.dart';
import 'package:wisdom_app/screens/saved_reflections_screen.dart';
import 'package:wisdom_app/services/daily_wisdom_access_service.dart';
import 'package:wisdom_app/services/journal_owner_service.dart';
import 'package:wisdom_app/services/kept_discovery_hint_service.dart';
import 'package:wisdom_app/services/wisdom_notification_service.dart';

import '../test/persistence_test_helpers.dart';

const _stone = Color(0xFFE2E0D9);
const _ink = Color(0xFF2C2924);
const _revealId = 'a5f3c111-1111-4111-8111-111111111111';
const _reflection = 'Today, I want to move without rushing.';
const _heroWisdom = 'Some answers arrive only after silence.';
const _presenceWisdom = 'A quiet life can still be meaningful.';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture authentic App Store states', (tester) async {
    if (Platform.isAndroid) {
      await binding.convertFlutterSurfaceToImage();
    }

    await _captureAskFromHeart(tester, binding);

    await _captureExistingWisdom(
      tester,
      binding,
      screenshotName: '02_wisdom_reveal_raw',
      wisdom: _heroWisdom,
      now: DateTime.utc(2026, 8, 4, 9, 41),
      remaining: const Duration(hours: 19, minutes: 24),
    );

    await _captureKept(tester, binding);
    await _captureReflection(tester, binding);
    await _captureJournal(tester, binding);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

ThemeData _eastTheme() {
  return ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: _stone,
    colorScheme: const ColorScheme.light(
      surface: _stone,
      onSurface: _ink,
    ),
    textTheme: ThemeData.light().textTheme.apply(
          fontFamily: 'EBGaramond',
        ),
  );
}

Widget _materialScreen(Widget home) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _eastTheme(),
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

Future<void> _captureExistingWisdom(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding, {
  required String screenshotName,
  required String wisdom,
  required DateTime now,
  required Duration remaining,
}) async {
  await _clearCaptureSurface(tester);
  await _resetPreferences();
  final dailyGraph = DailyAccessTestGraph(
    adapter: _MemoryStoragePreferencesAdapter(),
    clock: () => now,
  );
  final revealedAt = now.subtract(
    DailyWisdomRecord.lockDuration - remaining,
  );
  await dailyGraph.repository.saveDailyWisdomRecord(
    DailyWisdomRecord(
      text: wisdom,
      revealedAt: revealedAt,
      unlockAt: revealedAt.add(DailyWisdomRecord.lockDuration),
      revealId: _revealId,
    ),
  );

  await tester.pumpWidget(
    _homeApp(
      dailyGraph: dailyGraph,
      clock: () => now,
    ),
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
  expect(find.text(wisdom), findsOneWidget);
  expect(find.textContaining('Return when the silence opens again.'),
      findsOneWidget);
  await binding.takeScreenshot(screenshotName);
}

Future<void> _captureAskFromHeart(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  await _clearCaptureSurface(tester);
  await _resetPreferences();
  await tester.pumpWidget(
    _homeApp(
      dailyGraph: DailyAccessTestGraph(
        adapter: _MemoryStoragePreferencesAdapter(),
        clock: () => DateTime.utc(2026, 8, 4, 9, 41),
      ),
      clock: () => DateTime.utc(2026, 8, 4, 9, 41),
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

  // Pause. Feel.
  await _tapCenter(tester);
  await _waitForHomeState(
    tester,
    (state) =>
        (state.pauseFeelOpacity as double) >= 1.0 &&
        !(state.transitionInProgress as bool),
  );

  // Ask from your heart.
  await _tapCenter(tester);
  await _waitForHomeState(
    tester,
    (state) => state.screenStep == 2 && !(state.transitionInProgress as bool),
  );
  await _pumpFrames(tester, const Duration(milliseconds: 500));
  expect(find.text('Ask from'), findsOneWidget);
  expect(find.text('your heart.'), findsOneWidget);
  await binding.takeScreenshot('01_ask_raw');
}

Future<void> _captureJournal(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  await _clearCaptureSurface(tester);
  SharedPreferences.setMockInitialValues({
    JournalOwnerService.promptHandledKey: true,
  });
  final items = <FavoriteItem>[
    FavoriteItem(
      id: 'journal-1',
      revealId: '00000000-0000-4000-8000-000000000005',
      date: 'August 1, 2026',
      text: _presenceWisdom,
      keptAt: DateTime.utc(2026, 8, 1).toIso8601String(),
    ),
    FavoriteItem(
      id: 'journal-2',
      revealId: '00000000-0000-4000-8000-000000000006',
      date: 'August 2, 2026',
      text: 'Clarity often arrives after stillness.',
      reflection: _reflection,
      reflectedAt: '2026-08-02T09:41:00.000Z',
      keptAt: DateTime.utc(2026, 8, 2).toIso8601String(),
    ),
    FavoriteItem(
      id: 'journal-3',
      revealId: '00000000-0000-4000-8000-000000000007',
      date: 'August 3, 2026',
      text: _heroWisdom,
      keptAt: DateTime.utc(2026, 8, 3).toIso8601String(),
    ),
  ];

  await tester.pumpWidget(
    _materialScreen(
      JournalScreen(
        items: items,
        isKeeper: true,
      ),
    ),
  );

  var found = false;
  for (var attempt = 0; attempt < 200; attempt += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byType(PdfPreview).evaluate().isNotEmpty) {
      found = true;
      break;
    }
  }
  expect(found, isTrue, reason: 'Journal preview did not render in time.');
  await _pumpFrames(tester, const Duration(milliseconds: 900));
  expect(find.text('Journal'), findsOneWidget);

  await binding.takeScreenshot('05_journal_raw');
}

Future<void> _captureKept(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  await _clearCaptureSurface(tester);
  await _resetPreferences();
  final keptGraph = KeptRepositoryTestGraph();
  final items = <FavoriteItem>[
    const FavoriteItem(
      id: 'kept-1',
      revealId: '00000000-0000-4000-8000-000000000001',
      date: 'August 1, 2026',
      text: 'A quiet life can still be meaningful.',
    ),
    const FavoriteItem(
      id: 'kept-2',
      revealId: '00000000-0000-4000-8000-000000000002',
      date: 'August 2, 2026',
      text: 'Clarity often arrives after stillness.',
      reflection: 'Today, I want to move without rushing.',
      reflectedAt: '2026-08-02T09:41:00.000Z',
    ),
    const FavoriteItem(
      id: 'kept-3',
      revealId: '00000000-0000-4000-8000-000000000003',
      date: 'August 3, 2026',
      text: _heroWisdom,
    ),
  ];

  await tester.pumpWidget(
    _materialScreen(
      SavedReflectionsScreen(
        reflections: items,
        savedReflectionsService: keptGraph.service,
      ),
    ),
  );
  await _pumpFrames(tester, const Duration(milliseconds: 800));
  expect(find.text('Kept'), findsOneWidget);
  expect(find.text(_heroWisdom), findsOneWidget);
  expect(find.text('Clarity often arrives after stillness.'), findsOneWidget);
  expect(find.text(_presenceWisdom), findsOneWidget);
  await binding.takeScreenshot('03_kept_collection_raw');
}

Future<void> _captureReflection(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  await _clearCaptureSurface(tester);
  await _resetPreferences();
  final keptGraph = KeptRepositoryTestGraph();
  const item = FavoriteItem(
    id: 'reflection-1',
    revealId: '00000000-0000-4000-8000-000000000004',
    date: 'August 3, 2026',
    text: 'The path softens when resistance ends.',
    reflection: _reflection,
    reflectedAt: '2026-08-03T09:41:00.000Z',
  );

  await tester.pumpWidget(
    _materialScreen(
      ReflectionScreen(
        item: item,
        isKeeper: false,
        savedReflectionsService: keptGraph.service,
      ),
    ),
  );
  await _pumpFrames(tester, const Duration(milliseconds: 800));
  expect(find.text(item.text), findsOneWidget);
  expect(find.text(_reflection), findsOneWidget);
  await binding.takeScreenshot('04_reflection_raw');
}

Widget _homeApp({
  required DailyAccessTestGraph dailyGraph,
  required WisdomClock clock,
}) {
  final keptGraph = KeptRepositoryTestGraph();
  final notificationService = WisdomNotificationService(
    platform: _ScreenshotNotificationPlatform(),
    clock: clock,
  );
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _eastTheme(),
    home: HomeScreen(
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
    'Home did not reach the requested screenshot state. '
    'screenStep=${state.screenStep}, '
    'transitionInProgress=${state.transitionInProgress}, '
    'pauseFeelOpacity=${state.pauseFeelOpacity}, '
    'currentText=${state.currentText}',
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
