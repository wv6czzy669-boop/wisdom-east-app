import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/models/daily_wisdom_record.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/screens/home_screen.dart';
import 'package:wisdom_app/widgets/grain_painter.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('launch ritual mark is static and geometrically restrained',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen()),
    );

    final markFinder = find.byKey(const ValueKey('launch-ritual-mark'));
    final removedLaunchSubtitle = ['Where', 'silence', 'speaks.'].join(' ');
    expect(markFinder, findsOneWidget);
    expect(find.byKey(const ValueKey('top-navigation')), findsNothing);
    expect(_grainPainters(tester), isEmpty);
    expect(find.text(removedLaunchSubtitle), findsNothing);
    expect(_ritualOpacity(tester), 1.0);

    final mark = tester.widget<Container>(markFinder);
    final decoration = mark.decoration! as BoxDecoration;
    expect(tester.getSize(markFinder).width, closeTo(228.15, 0.1));
    expect(tester.getSize(markFinder).height, closeTo(228.15, 0.1));
    expect(decoration.shape, BoxShape.circle);
    expect(decoration.color, isNull);
    expect(decoration.boxShadow, isNull);
    expect(decoration.border!.top.width, 0.85);
    expect(decoration.border!.top.color.a, closeTo(0.70, 0.001));

    final launchText = tester.widget<Text>(
      find.descendant(of: markFinder, matching: find.text('EAST.')),
    );
    expect(launchText.style?.fontFamily, 'CormorantGaramond');
    expect(launchText.style?.fontSize, 21.5);
    expect(launchText.style?.color, const Color(0xFFF4F0E8));

    await tester.pump(const Duration(milliseconds: 300));
    expect(_ritualOpacity(tester), 1.0);

    await _tapCenter(tester);
    await tester.pump();
    final launchFade = tester.widget<AnimatedOpacity>(
      find.byKey(const ValueKey('ritual-content-opacity')),
    );
    expect(launchFade.opacity, 0.0);
    expect(launchFade.duration, const Duration(milliseconds: 750));

    await tester.pump(const Duration(milliseconds: 2000));
  });

  testWidgets('lifecycle interruption restores visible ritual content',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen()),
    );
    await _finishOpeningIntro(tester);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      const Color(0xFF040404),
    );
    expect(find.byKey(const ValueKey('top-navigation')), findsNothing);
    expect(find.byKey(const ValueKey('launch-ritual-mark')), findsOneWidget);

    await _tapCenter(tester);
    await tester.pump();
    expect(_ritualOpacity(tester), 0.0);

    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.inactive,
    );
    await tester.pump();

    expect(_ritualOpacity(tester), 1.0);
    expect(find.byKey(const ValueKey('launch-ritual-mark')), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await tester.pump(const Duration(milliseconds: 1300));
  });

  testWidgets('active lock reopens to the existing wisdom without revealing',
      (tester) async {
    final now = DateTime.now();
    const existingWisdom = 'Already received wisdom';
    final originalRecord = DailyWisdomRecord(
      text: existingWisdom,
      revealedAt: now,
      unlockAt: now.add(const Duration(hours: 24)),
    );
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': originalRecord.encode(),
      'favorites': [
        FavoriteItem(
          text: existingWisdom,
          date: 'June 21, 2026',
        ).encode(),
      ],
    });

    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen()),
    );
    await _finishOpeningIntro(tester);
    expect(find.byKey(const ValueKey('launch-ritual-mark')), findsOneWidget);

    await _openExistingWisdom(tester);

    expect(find.text(existingWisdom), findsOneWidget);
    expect(
      find.textContaining('Return when the silence opens again.'),
      findsOneWidget,
    );
    expect(find.text('Pause.'), findsNothing);
    expect(find.text('Feel.'), findsNothing);
    expect(find.text('Ask from your heart.'), findsNothing);
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.byTooltip('Kept'), findsOneWidget);
    expect(find.byTooltip('Remove kept reflection'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byTooltip('Remove kept reflection'),
        matching: find.text('●'),
      ),
      findsOneWidget,
    );

    final prefs = await SharedPreferences.getInstance();
    final persistedRecord = DailyWisdomRecord.decode(
      prefs.getString('daily_wisdom_access')!,
    );
    expect(persistedRecord.text, originalRecord.text);
    expect(
      persistedRecord.revealedAt.millisecondsSinceEpoch,
      originalRecord.revealedAt.millisecondsSinceEpoch,
    );
    expect(
      persistedRecord.unlockAt.millisecondsSinceEpoch,
      originalRecord.unlockAt.millisecondsSinceEpoch,
    );
    expect(prefs.getStringList('daily_wisdom_archive'), isNull);
  });

  testWidgets('Keeper reopens to the same existing locked wisdom',
      (tester) async {
    final now = DateTime.now();
    SharedPreferences.setMockInitialValues({
      'is_premium': true,
      'daily_wisdom_access': DailyWisdomRecord(
        text: 'Keeper received wisdom',
        revealedAt: now,
        unlockAt: now.add(const Duration(hours: 24)),
      ).encode(),
    });

    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen()),
    );
    await _finishOpeningIntro(tester);
    await _openExistingWisdom(tester);

    expect(find.text('Keeper received wisdom'), findsOneWidget);
    expect(
      find.textContaining('Return when the silence opens again.'),
      findsOneWidget,
    );
    expect(find.text('Pause.'), findsNothing);
    expect(find.text('Feel.'), findsNothing);
    expect(find.text('Ask from your heart.'), findsNothing);
  });

  testWidgets('corrupt locked state falls back to conservative countdown',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': '{',
    });

    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen()),
    );
    await _finishOpeningIntro(tester);
    await _openLockedCountdown(tester);

    final countdown = tester.widget<Text>(
      find.textContaining('Return when the silence opens again.'),
    );
    final countdownLines = countdown.data!.split('\n');
    expect(countdownLines, hasLength(2));
    expect(countdownLines.first, 'Return when the silence opens again.');
    expect(countdownLines.last, matches(RegExp(r'^\d+h \d+m$')));
    expect(
      find.text('Silence is still available.'),
      findsNothing,
    );
    expect(find.text('Pause.'), findsNothing);
    expect(find.text('Feel.'), findsNothing);
    expect(find.text('Ask from your heart.'), findsNothing);
  });

  testWidgets('expired lock returns launch tap to the normal ritual',
      (tester) async {
    final now = DateTime.now();
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': DailyWisdomRecord(
        text: 'Expired wisdom',
        revealedAt: now.subtract(const Duration(hours: 25)),
        unlockAt: now.subtract(const Duration(hours: 1)),
      ).encode(),
    });

    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen()),
    );
    await _finishOpeningIntro(tester);
    await _advanceFromLaunchToPause(tester);

    expect(find.text('Pause.'), findsOneWidget);
    expect(
      find.textContaining('Return when the silence opens again.'),
      findsNothing,
    );
  });

  testWidgets('locked wisdom returns to launch after expiry refresh',
      (tester) async {
    final now = DateTime.now();
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': DailyWisdomRecord(
        text: 'Nearly unlocked wisdom',
        revealedAt: now.subtract(
          const Duration(hours: 23, minutes: 59, seconds: 30),
        ),
        unlockAt: now.add(const Duration(seconds: 30)),
      ).encode(),
    });

    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen()),
    );
    await _finishOpeningIntro(tester);
    await _openExistingWisdom(tester);
    expect(find.text('Nearly unlocked wisdom'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'daily_wisdom_access',
      DailyWisdomRecord(
        text: 'Now expired wisdom',
        revealedAt: now.subtract(const Duration(hours: 25)),
        unlockAt: now.subtract(const Duration(hours: 1)),
      ).encode(),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(find.byKey(const ValueKey('launch-ritual-mark')), findsOneWidget);
    expect(find.byKey(const ValueKey('top-navigation')), findsNothing);
  });

  testWidgets('ritual uses the restrained haptic sequence', (tester) async {
    final haptics = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen()),
    );
    await _finishOpeningIntro(tester);

    await _tapCenter(tester);
    await tester.pump();
    expect(haptics.last, 'HapticFeedbackType.selectionClick');
    await tester.pump(const Duration(milliseconds: 850));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 850));

    await _tapCenter(tester);
    await tester.pump();
    expect(haptics.last, 'HapticFeedbackType.lightImpact');
    await tester.pump(const Duration(milliseconds: 1300));

    await _tapCenter(tester);
    await tester.pump();
    expect(haptics.last, 'HapticFeedbackType.lightImpact');
    await tester.pump(const Duration(milliseconds: 850));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 600));

    await _tapCenter(tester);
    await tester.pump();
    expect(haptics.last, 'HapticFeedbackType.mediumImpact');
    expect(haptics, hasLength(4));

    await tester.pump(const Duration(milliseconds: 1250));
    expect(find.byKey(const ValueKey('black-silence')), findsOneWidget);
    expect(haptics, hasLength(4));

    await tester.pump(const Duration(milliseconds: 550));
    expect(haptics, hasLength(5));
    expect(haptics.last, 'HapticFeedbackType.selectionClick');

    await tester.pump(const Duration(milliseconds: 1420));
  });

  testWidgets('ritual remains overflow-safe on iPhone SE at 3x text scale',
      (tester) async {
    final removedRevealPrompt = ['Tap', 'to', 'Reveal'].join(' ');

    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.platformDispatcher.clearTextScaleFactorTestValue,
    );

    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen()),
    );
    await _finishOpeningIntro(tester);

    await _tapCenter(tester);
    await tester.pump(const Duration(milliseconds: 850));

    expect(
      tester
          .widget<Positioned>(
            find.byKey(const ValueKey('top-navigation')),
          )
          .top,
      0,
    );
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byTooltip('Settings'),
              matching: find.text('◎'),
            ),
          )
          .style
          ?.fontSize,
      29,
    );
    expect(find.byTooltip('Kept'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byTooltip('Kept'),
              matching: find.text('○'),
            ),
          )
          .style
          ?.fontSize,
      36,
    );
    expect(
      tester.getSize(find.byTooltip('Settings')),
      tester.getSize(find.byTooltip('Kept')),
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 850));

    await _tapCenter(tester);
    await tester.pump(const Duration(milliseconds: 1300));
    expect(find.text('Pause.'), findsOneWidget);
    expect(find.text('Feel.'), findsOneWidget);
    expect(tester.widget<Text>(find.text('Pause.')).style?.fontSize, 33);
    expect(tester.widget<Text>(find.text('Feel.')).style?.fontSize, 33);

    await _tapCenter(tester);
    await tester.pump(const Duration(milliseconds: 850));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Ask from your heart.'), findsOneWidget);
    expect(find.text(removedRevealPrompt), findsNothing);
    final askTextFinder = find.text('Ask from your heart.');
    final askSizeBeforeFade = tester.getSize(askTextFinder);
    final askStyleBeforeFade = tester.widget<Text>(askTextFinder).style;

    await _tapCenter(tester);
    await tester.pump();
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.byTooltip('Kept'), findsOneWidget);
    expect(find.text(removedRevealPrompt), findsNothing);
    expect(askTextFinder, findsOneWidget);
    expect(
      find.ancestor(
        of: askTextFinder,
        matching: find.byType(AnimatedScale),
      ),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: askTextFinder,
        matching: find.byType(FittedBox),
      ),
      findsNothing,
    );
    expect(_ritualOpacity(tester), 1.0);
    final askFade = tester.widget<FadeTransition>(
      find.byKey(const ValueKey('ask-fade')),
    );
    final askCurve = askFade.opacity as CurvedAnimation;
    final askController = askCurve.parent as AnimationController;
    expect(askFade.opacity.value, 1.0);
    expect(askController.duration, const Duration(milliseconds: 1250));
    expect(askCurve.reverseCurve, Curves.easeInCubic);

    await tester.pump(const Duration(milliseconds: 300));
    expect(askTextFinder, findsOneWidget);
    expect(tester.getSize(askTextFinder), askSizeBeforeFade);
    final askStyleDuringFade = tester.widget<Text>(askTextFinder).style;
    expect(askStyleDuringFade?.fontSize, askStyleBeforeFade?.fontSize);
    expect(askStyleDuringFade?.height, askStyleBeforeFade?.height);
    expect(askFade.opacity.value, greaterThan(0.0));
    expect(askFade.opacity.value, lessThan(1.0));
    expect(find.byKey(const ValueKey('black-silence')), findsNothing);

    await tester.pump(const Duration(milliseconds: 949));
    expect(find.byKey(const ValueKey('black-silence')), findsNothing);
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.byTooltip('Kept'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey('black-silence')), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.byTooltip('Kept'), findsOneWidget);
    expect(find.text(removedRevealPrompt), findsNothing);
    expect(
      tester
          .widget<ColoredBox>(
            find.byKey(const ValueKey('black-silence')),
          )
          .color,
      Colors.black,
    );

    await _tapCenter(tester);
    await _tapCenter(tester);
    await tester.pump(const Duration(milliseconds: 549));
    expect(find.byKey(const ValueKey('black-silence')), findsOneWidget);
    expect(find.byKey(const ValueKey('wisdom-reveal-fade')), findsNothing);

    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey('black-silence')), findsNothing);

    expect(find.text(removedRevealPrompt), findsNothing);
    final revealFadeFinder = find.byKey(
      const ValueKey('wisdom-reveal-fade'),
    );
    final wisdomText = tester.widget<Text>(
      find.descendant(
        of: revealFadeFinder,
        matching: find.byType(Text),
      ),
    );
    expect(wisdomText.style?.fontSize, 32);
    expect(wisdomText.style?.height, 1.48);
    expect(
      tester
          .widget<SizedBox>(
            find.byKey(const ValueKey('revealed-wisdom-layout')),
          )
          .width,
      192,
    );
    final revealFade = tester.widget<FadeTransition>(
      revealFadeFinder,
    );
    final revealCurve = revealFade.opacity as CurvedAnimation;
    final revealController = revealCurve.parent as AnimationController;
    expect(revealFade.opacity.value, 0.0);
    expect(
      revealController.duration,
      greaterThanOrEqualTo(const Duration(milliseconds: 1100)),
    );
    expect(revealController.duration, const Duration(milliseconds: 1200));
    expect(revealCurve.curve, Curves.easeOutCubic);

    await tester.pump(const Duration(milliseconds: 1));
    expect(revealFade.opacity.value, lessThan(0.01));

    await tester.pump(const Duration(milliseconds: 600));
    expect(revealFade.opacity.value, greaterThan(0.0));
    expect(revealFade.opacity.value, lessThan(1.0));

    await tester.pump(const Duration(milliseconds: 600));
    expect(revealFade.opacity.value, 1.0);
    final countdown = tester.widget<Text>(
      find.textContaining('Return when the silence opens again.'),
    );
    final countdownLines = countdown.data!.split('\n');
    expect(countdownLines.first, 'Return when the silence opens again.');
    expect(countdownLines, hasLength(2));
    expect(countdownLines.last, matches(RegExp(r'^\d+h \d+m$')));
    expect(_keptGuard(tester).ignoring, isTrue);
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(milliseconds: 950));
    expect(_keptGuard(tester).ignoring, isTrue);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(_keptGuard(tester).ignoring, isFalse);
    expect(find.byTooltip('Back'), findsNothing);
    expect(find.byTooltip('Keep reflection'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byTooltip('Keep reflection'),
        matching: find.text('○'),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byTooltip('Keep reflection'),
              matching: find.text('○'),
            ),
          )
          .style
          ?.fontSize,
      31,
    );

    await tester.tap(find.byTooltip('Keep reflection'));
    await tester.pump();
    expect(find.byTooltip('Remove kept reflection'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byTooltip('Remove kept reflection'),
        matching: find.text('●'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('archive failure cannot replace a persisted daily wisdom',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_archive': 1,
    });

    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen()),
    );
    await _finishOpeningIntro(tester);
    await _advanceToQuestion(tester);

    await _tapCenter(tester);
    await tester.pump(const Duration(milliseconds: 1250));
    await tester.pump(const Duration(milliseconds: 550));

    final prefs = await SharedPreferences.getInstance();
    final persisted = DailyWisdomRecord.decode(
      prefs.getString('daily_wisdom_access')!,
    );

    expect(find.text(persisted.text), findsOneWidget);
    expect(
      find.text('Silence is still available.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pump(const Duration(milliseconds: 1100));
  });

  testWidgets('reduce motion freezes continuous grain movement',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: true),
              child: const HomeScreen(),
            );
          },
        ),
      ),
    );
    await _finishOpeningIntro(tester);
    await _tapCenter(tester);
    await tester.pump(const Duration(milliseconds: 850));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 850));

    expect(_grainPainter(tester).movement, 0.0);
    expect(_grainPainter(tester).intensity, 0.01235);
    await tester.pump(const Duration(milliseconds: 600));
    expect(_grainPainter(tester).movement, 0.0);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _finishOpeningIntro(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 450));
  await tester.pump(const Duration(milliseconds: 950));
  await tester.pump(const Duration(milliseconds: 550));
}

Future<void> _tapCenter(WidgetTester tester) {
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  return tester.tapAt(size.center(Offset.zero));
}

Future<void> _advanceFromLaunchToPause(WidgetTester tester) async {
  await _tapCenter(tester);
  await tester.pump(const Duration(milliseconds: 850));
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 850));
}

Future<void> _openLockedCountdown(WidgetTester tester) async {
  await _tapCenter(tester);
  await tester.pump(const Duration(milliseconds: 850));
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _openExistingWisdom(WidgetTester tester) async {
  await _tapCenter(tester);
  await tester.pump(const Duration(milliseconds: 850));
  await tester.pump(const Duration(milliseconds: 1200));
  await tester.pump(const Duration(milliseconds: 1100));
}

Future<void> _advanceToQuestion(WidgetTester tester) async {
  await _advanceFromLaunchToPause(tester);

  await _tapCenter(tester);
  await tester.pump(const Duration(milliseconds: 1300));

  await _tapCenter(tester);
  await tester.pump(const Duration(milliseconds: 850));
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 600));
}

double _ritualOpacity(WidgetTester tester) {
  return tester
      .widget<AnimatedOpacity>(
        find.byKey(const ValueKey('ritual-content-opacity')),
      )
      .opacity;
}

IgnorePointer _keptGuard(WidgetTester tester) {
  return tester.widget<IgnorePointer>(
    find.byKey(const ValueKey('kept-interaction-guard')),
  );
}

GrainPainter _grainPainter(WidgetTester tester) {
  return _grainPainters(tester).single;
}

Iterable<GrainPainter> _grainPainters(WidgetTester tester) {
  return tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((widget) => widget.painter)
      .whereType<GrainPainter>();
}
