import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/models/daily_wisdom_record.dart';
import 'package:wisdom_app/screens/home_screen.dart';
import 'package:wisdom_app/widgets/grain_painter.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
      find.descendant(
        of: find.byTooltip('Settings'),
        matching: find.text('◎'),
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Kept'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byTooltip('Kept'),
        matching: find.text('○'),
      ),
      findsOneWidget,
    );

    await _tapCenter(tester);
    await tester.pump();
    expect(_ritualOpacity(tester), 0.0);

    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.inactive,
    );
    await tester.pump();

    expect(_ritualOpacity(tester), 1.0);
    expect(find.text('EAST.'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    await tester.pump(const Duration(milliseconds: 1300));
  });

  testWidgets('ritual remains overflow-safe on iPhone SE at 3x text scale',
      (tester) async {
    tester.view.physicalSize = const Size(640, 1136);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(
      tester.platformDispatcher.clearTextScaleFactorTestValue,
    );

    final now = DateTime.now();
    const longWisdom =
        'Stillness does not ask you to become smaller; it asks you to notice '
        'the quiet horizon already opening within every unfinished question.';
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': DailyWisdomRecord(
        text: longWisdom,
        revealedAt: now,
        unlockAt: now.add(const Duration(hours: 24)),
      ).encode(),
    });

    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen()),
    );
    await _finishOpeningIntro(tester);

    await _tapCenter(tester);
    await tester.pump(const Duration(milliseconds: 850));
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

    await _tapCenter(tester);
    await tester.pump();
    expect(find.byTooltip('Settings'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1249));
    expect(find.byKey(const ValueKey('black-silence')), findsNothing);

    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey('black-silence')), findsOneWidget);
    expect(
      tester
          .widget<ColoredBox>(
            find.byKey(const ValueKey('black-silence')),
          )
          .color,
      Colors.black,
    );

    await _tapCenter(tester);
    await tester.pump(const Duration(milliseconds: 1799));
    expect(find.byKey(const ValueKey('black-silence')), findsOneWidget);
    expect(find.text(longWisdom), findsNothing);

    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey('black-silence')), findsNothing);

    expect(find.text(longWisdom), findsOneWidget);
    final wisdomText = tester.widget<Text>(find.text(longWisdom));
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
    final revealOpacity = tester.widget<AnimatedOpacity>(
      find.byKey(const ValueKey('ritual-content-opacity')),
    );
    expect(revealOpacity.duration, const Duration(milliseconds: 850));
    expect(revealOpacity.curve, Curves.easeOutCubic);
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
    await tester.pump(const Duration(milliseconds: 1800));

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

Future<void> _advanceToQuestion(WidgetTester tester) async {
  await _tapCenter(tester);
  await tester.pump(const Duration(milliseconds: 850));
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 850));

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
  return tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((widget) => widget.painter)
      .whereType<GrainPainter>()
      .single;
}
