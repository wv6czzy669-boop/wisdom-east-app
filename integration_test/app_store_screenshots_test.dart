import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/models/daily_wisdom_record.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/persistence/storage_preferences_adapter.dart';
import 'package:wisdom_app/screens/home_screen.dart';
import 'package:wisdom_app/screens/reflection_screen.dart';
import 'package:wisdom_app/screens/saved_reflections_screen.dart';
import 'package:wisdom_app/services/daily_wisdom_access_service.dart';
import 'package:wisdom_app/services/kept_discovery_hint_service.dart';
import 'package:wisdom_app/services/storage_service.dart';
import 'package:wisdom_app/services/wisdom_notification_service.dart';

import '../test/persistence_test_helpers.dart';

const _warmBlack = Color(0xFF040404);
const _ivory = Color(0xFFF4F0E8);
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

    await _captureExistingWisdom(
      tester,
      binding,
      screenshotName: '01_wisdom_reveal_raw',
      wisdom: _heroWisdom,
      now: DateTime.utc(2026, 8, 4, 9, 41),
      remaining: const Duration(hours: 19, minutes: 24),
    );

    await _captureRitualCandidates(tester, binding);
    await _captureKept(tester, binding);
    await _captureReflection(tester, binding);
    await _captureOpening(tester, binding);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

ThemeData _eastTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: _warmBlack,
    colorScheme: const ColorScheme.dark(
      surface: _warmBlack,
      onSurface: _ivory,
    ),
    textTheme: ThemeData.dark().textTheme.apply(
          fontFamily: 'CormorantGaramond',
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

Future<void> _captureRitualCandidates(
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

  await _tapCenter(tester);
  await _waitForHomeState(
    tester,
    (state) => state.screenStep == 1 && !(state.transitionInProgress as bool),
  );
  expect(find.text('Pause.'), findsOneWidget);
  await binding.takeScreenshot('02_pause_raw');

  await _tapCenter(tester);
  await _waitForHomeState(
    tester,
    (state) =>
        (state.pauseFeelOpacity as double) >= 1.0 &&
        !(state.transitionInProgress as bool),
  );
  await _pumpFrames(tester, const Duration(milliseconds: 400));

  expect(find.text('Pause.'), findsOneWidget);
  expect(find.text('Feel.'), findsOneWidget);
  await binding.takeScreenshot('02_pause_feel_raw');
}

Future<void> _captureOpening(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
) async {
  await _clearCaptureSurface(tester);
  await _resetPreferences();
  final now = DateTime.utc(2026, 8, 4, 9, 41);
  await tester.pumpWidget(
    _homeApp(
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
  await _pumpFrames(tester, const Duration(milliseconds: 500));
  expect(find.byKey(const ValueKey('launch-ritual-mark')), findsOneWidget);
  expect(find.text('EAST.'), findsOneWidget);
  await binding.takeScreenshot('05_opening_raw');
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
      storageService: StorageService(),
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
