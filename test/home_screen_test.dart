import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/models/daily_wisdom_record.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/models/pending_daily_wisdom_reveal.dart';
import 'package:wisdom_app/repositories/daily_access_repository.dart';
import 'package:wisdom_app/screens/home_screen.dart';
import 'package:wisdom_app/services/daily_wisdom_access_service.dart';
import 'package:wisdom_app/services/saved_reflections_service.dart';
import 'package:wisdom_app/services/storage_service.dart';
import 'package:wisdom_app/widgets/grain_painter.dart';

import 'persistence_test_helpers.dart';

void main() {
  final removedRevealAnother = ['Reveal', 'another'].join(' ');

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
      _homeApp(),
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

  testWidgets('Home unresolved launch has one disabled EAST semantic node',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        _homeApp(),
      );

      _expectSemanticNode(
        label: 'EAST.',
        isButton: false,
        isEnabled: Tristate.isFalse,
        hasTap: false,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('Home semantics expose ritual action without hidden duplicates',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final dailyGraph = DailyAccessTestGraph();
      await tester.pumpWidget(
        _homeApp(dailyGraph: dailyGraph),
      );
      await _finishOpeningIntro(tester);

      _expectSemanticNode(
        label: 'EAST.',
        isButton: true,
        isEnabled: Tristate.isTrue,
        hasTap: true,
      );

      await _tapCenter(tester);
      await tester.pump(const Duration(milliseconds: 820));
      await tester.pump(const Duration(milliseconds: 220));

      _expectSemanticNode(
        label: 'Pause.',
        isButton: false,
        isEnabled: Tristate.isFalse,
        hasTap: false,
      );

      await tester.pump(const Duration(milliseconds: 820));

      expect(find.semantics.byLabel('EAST.'), findsNothing);

      expect(find.byTooltip('Settings'), findsOneWidget);
      final settingsNode = tester.getSemantics(find.byTooltip('Settings'));
      expect(
        settingsNode.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
      expect(find.byTooltip('Kept'), findsOneWidget);
      final keptNode = tester.getSemantics(find.byTooltip('Kept'));
      expect(
        keptNode.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );

      await _tapCenter(tester);
      await tester.pump(const Duration(milliseconds: 1300));
      await _tapCenter(tester);
      await tester.pump(const Duration(milliseconds: 850));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      _expectSemanticNode(
        label: 'Ask from your heart.',
        isButton: true,
        isEnabled: Tristate.isTrue,
        hasTap: true,
      );

      await _tapCenter(tester);
      await tester.pump(const Duration(milliseconds: 1250));

      expect(find.byKey(const ValueKey('black-silence')), findsOneWidget);
      expect(find.semantics.byLabel('Ask from your heart.'), findsNothing);

      await tester.pump(const Duration(milliseconds: 550));
      await tester.pump();

      final record = await dailyGraph.repository.loadDailyWisdomRecord();
      expect(record, isNotNull);
      await tester.pump(const Duration(milliseconds: 950));
      expect(find.text(record!.text), findsOneWidget);
      _expectSemanticNode(
        label: record.text,
        isButton: false,
        isEnabled: Tristate.none,
        hasTap: false,
      );
      await tester.pump(const Duration(milliseconds: 600));
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('lifecycle interruption restores visible ritual content',
      (tester) async {
    await tester.pumpWidget(
      _homeApp(),
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

  testWidgets('Ask-fade interruption keeps pending wisdom without daily lock',
      (tester) async {
    SharedPreferences.setMockInitialValues({'is_premium': true});
    final dailyGraph = DailyAccessTestGraph();

    await tester.pumpWidget(
      _homeApp(dailyGraph: dailyGraph),
    );
    await _finishOpeningIntro(tester);
    await _advanceToQuestion(tester);

    await _tapCenter(tester);
    await tester.pump(const Duration(milliseconds: 20));

    final pendingBeforePause =
        await dailyGraph.repository.loadPendingDailyWisdomReveal();
    final persistedBeforePause =
        await dailyGraph.repository.loadDailyWisdomRecord();
    expect(pendingBeforePause, isNotNull);
    expect(persistedBeforePause, isNull);
    final selectedWisdom = pendingBeforePause!.text;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 50));

    final persistedAfterResumeBeforeReveal =
        await dailyGraph.repository.loadDailyWisdomRecord();
    expect(persistedAfterResumeBeforeReveal, isNull);

    await _tapCenter(tester);
    await tester.pump(const Duration(milliseconds: 1250));
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();

    expect(find.text(selectedWisdom), findsOneWidget);
    expect(find.text('Ask from your heart.'), findsNothing);

    final persistedAfterResume =
        await dailyGraph.repository.loadDailyWisdomRecord();
    expect(persistedAfterResume!.text, selectedWisdom);

    await tester.pump(const Duration(milliseconds: 950));
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets(
      'black-silence interruption keeps pending wisdom without daily lock',
      (tester) async {
    final dailyGraph = DailyAccessTestGraph();
    await tester.pumpWidget(
      _homeApp(dailyGraph: dailyGraph),
    );
    await _finishOpeningIntro(tester);
    await _advanceToQuestion(tester);

    await _tapCenter(tester);
    await tester.pump(const Duration(milliseconds: 1250));

    final pendingDuringBlackSilence =
        await dailyGraph.repository.loadPendingDailyWisdomReveal();
    final persistedDuringBlackSilence =
        await dailyGraph.repository.loadDailyWisdomRecord();

    expect(find.byKey(const ValueKey('black-silence')), findsOneWidget);
    expect(pendingDuringBlackSilence, isNotNull);
    expect(persistedDuringBlackSilence, isNull);
    final selectedWisdom = pendingDuringBlackSilence!.text;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      await dailyGraph.repository.loadDailyWisdomRecord(),
      isNull,
    );

    await _tapCenter(tester);
    await tester.pump(const Duration(milliseconds: 1250));
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();

    final committed = await dailyGraph.repository.loadDailyWisdomRecord();

    expect(committed, isNotNull);
    expect(committed!.text, selectedWisdom);
    expect(find.text(selectedWisdom), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 950));
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('final Ask tap fades immediately while pending save is delayed',
      (tester) async {
    final dailyGraph = _DelayedPendingDailyAccessGraph();

    await tester.pumpWidget(
      _homeApp(
        dailyGraph: dailyGraph.graph,
        dailyWisdomOperationTimeout: const Duration(seconds: 5),
      ),
    );
    await _finishOpeningIntro(tester);
    await _advanceToQuestion(tester);

    final askTextFinder = find.text('Ask from your heart.');
    expect(askTextFinder, findsOneWidget);

    await _tapCenter(tester);
    await tester.pump();
    expect(dailyGraph.pendingSaveStarted, isTrue);
    expect(_askFadeValue(tester), 1.0);

    await tester.pump(const Duration(milliseconds: 300));
    expect(askTextFinder, findsOneWidget);
    expect(_askFadeValue(tester), lessThan(1.0));
    expect(_askFadeValue(tester), greaterThan(0.0));
    expect(find.byKey(const ValueKey('black-silence')), findsNothing);
    final prefsDuringPendingSave = await SharedPreferences.getInstance();
    expect(prefsDuringPendingSave.containsKey('daily_wisdom_access'), isFalse);

    dailyGraph.releasePendingSave();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 949));
    expect(find.byKey(const ValueKey('black-silence')), findsNothing);

    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey('black-silence')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 549));
    final pendingBeforeReveal =
        await dailyGraph.repository.loadPendingDailyWisdomReveal();
    expect(pendingBeforeReveal, isNotNull);
    expect(
      pendingBeforeReveal!.phase,
      PendingDailyWisdomRevealPhase.prepared,
    );
    expect(find.byKey(const ValueKey('wisdom-reveal-fade')), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(find.byKey(const ValueKey('wisdom-reveal-fade')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 950));
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('never-completing prepare times out to a retryable Ask state',
      (tester) async {
    final dailyGraph = _HangingPendingDailyAccessGraph();

    await tester.pumpWidget(
      _homeApp(
        dailyGraph: dailyGraph.graph,
        dailyWisdomOperationTimeout: const Duration(milliseconds: 100),
      ),
    );
    await _finishOpeningIntro(tester);
    await _advanceToQuestion(tester);

    await _tapCenter(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(_askFadeValue(tester), lessThan(1.0));
    expect(_askFadeValue(tester), greaterThan(0.0));

    await tester.pump(const Duration(milliseconds: 1200));
    expect(find.byKey(const ValueKey('black-silence')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 550));
    expect(find.byKey(const ValueKey('black-silence')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 101));

    expect(find.text('Ask from your heart.'), findsOneWidget);
    expect(find.byKey(const ValueKey('black-silence')), findsNothing);
    final prefsAfterPrepareTimeout = await SharedPreferences.getInstance();
    expect(
        prefsAfterPrepareTimeout.containsKey('daily_wisdom_access'), isFalse);

    await _tapCenter(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(_askFadeValue(tester), lessThan(1.0));
    expect(_askFadeValue(tester), greaterThan(0.0));

    await tester.pump(const Duration(milliseconds: 2000));
  });

  testWidgets('commit timeout keeps revealed wisdom unsaved and retryable',
      (tester) async {
    final revealBoundary = DateTime.utc(2026, 6, 20, 12);
    final dailyGraph = _HangingDailyWriteAccessGraph(
      clock: () => revealBoundary,
    );

    await tester.pumpWidget(
      _homeApp(
        dailyGraph: dailyGraph.graph,
        clock: () => revealBoundary,
        dailyWisdomOperationTimeout: const Duration(milliseconds: 100),
      ),
    );
    await _finishOpeningIntro(tester);
    await _advanceToQuestion(tester);

    await _tapCenter(tester);
    await tester.pump(const Duration(milliseconds: 1250));
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    await _pumpUntilCondition(tester, () => dailyGraph.dailyWriteStarted);

    expect(find.byKey(const ValueKey('black-silence')), findsNothing);
    expect(find.byKey(const ValueKey('wisdom-reveal-fade')), findsOneWidget);
    expect(dailyGraph.dailyWriteStarted, isTrue);
    await tester.pump(const Duration(milliseconds: 101));

    expect(_keptGuard(tester).ignoring, isTrue);
    final prefsDuringCommitTimeout = await SharedPreferences.getInstance();
    expect(
        prefsDuringCommitTimeout.containsKey('daily_wisdom_access'), isFalse);
    final pending = PendingDailyWisdomReveal.decode(
      prefsDuringCommitTimeout
          .getString(DailyAccessRepository.pendingDailyWisdomRevealKey)!,
    );
    expect(pending, isNotNull);
    expect(pending.phase, PendingDailyWisdomRevealPhase.revealedPendingCommit);
    expect(
      pending.confirmedRevealBoundary!.millisecondsSinceEpoch,
      revealBoundary.millisecondsSinceEpoch,
    );
  });

  testWidgets('event-loop delayed reveal uses actual callback clock time',
      (tester) async {
    var clockNow = DateTime.utc(2026, 6, 20, 12);
    final dailyGraph = DailyAccessTestGraph(clock: () => clockNow);
    final delayedCallbackTime = clockNow.add(const Duration(milliseconds: 37));

    await tester.pumpWidget(
      _homeApp(
        dailyGraph: dailyGraph,
        clock: () => clockNow,
        dailyWisdomOperationTimeout: const Duration(seconds: 5),
      ),
    );
    await _finishOpeningIntro(tester);
    await _advanceToQuestion(tester);

    await _tapCenter(tester);
    await tester.pump(const Duration(milliseconds: 1250));
    expect(find.byKey(const ValueKey('black-silence')), findsOneWidget);
    expect(find.byKey(const ValueKey('wisdom-reveal-fade')), findsNothing);

    clockNow = delayedCallbackTime;
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('wisdom-reveal-fade')), findsOneWidget);
    final persisted = await dailyGraph.repository.loadDailyWisdomRecord();
    expect(persisted, isNotNull);
    expect(
      persisted!.revealedAt.millisecondsSinceEpoch,
      delayedCallbackTime.millisecondsSinceEpoch,
    );

    await tester.pump(const Duration(milliseconds: 950));
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets(
      'slow authoritative write does not delay reveal animation but gates save',
      (tester) async {
    final revealBoundary = DateTime.utc(2026, 6, 20, 12, 30);
    final dailyGraph = _DelayedDailyWriteAccessGraph(
      clock: () => revealBoundary,
    );
    final expectedBoundary = revealBoundary;

    await tester.pumpWidget(
      _homeApp(
        dailyGraph: dailyGraph.graph,
        clock: () => revealBoundary,
        dailyWisdomOperationTimeout: const Duration(seconds: 5),
      ),
    );
    await _finishOpeningIntro(tester);
    await _advanceToQuestion(tester);

    await _tapCenter(tester);
    await tester.pump(const Duration(milliseconds: 1250));
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    await _pumpUntilCondition(tester, () => dailyGraph.dailyWriteStarted);

    expect(find.byKey(const ValueKey('wisdom-reveal-fade')), findsOneWidget);
    expect(dailyGraph.dailyWriteStarted, isTrue);
    expect(dailyGraph.attemptedRecord, isNotNull);
    expect(
      dailyGraph.attemptedRecord!.revealedAt.millisecondsSinceEpoch,
      expectedBoundary.millisecondsSinceEpoch,
    );
    expect(_keptGuard(tester).ignoring, isTrue);
    final prefsDuringSlowWrite = await SharedPreferences.getInstance();
    expect(prefsDuringSlowWrite.containsKey('daily_wisdom_access'), isFalse);

    await tester.pump(const Duration(milliseconds: 600));
    final revealFade = tester.widget<FadeTransition>(
      find.byKey(const ValueKey('wisdom-reveal-fade')),
    );
    expect(revealFade.opacity.value, greaterThan(0.0));
    expect(_keptGuard(tester).ignoring, isTrue);

    dailyGraph.releaseDailyWrite();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    await tester.pump();
    expect(_keptGuard(tester).ignoring, isTrue);
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2000));

    final persisted = await dailyGraph.repository.loadDailyWisdomRecord();
    expect(persisted, isNotNull);
    expect(
      persisted!.revealedAt.millisecondsSinceEpoch,
      expectedBoundary.millisecondsSinceEpoch,
    );
    expect(_keptGuard(tester).ignoring, isFalse);
  });

  testWidgets('retry after failed finalization uses original reveal boundary',
      (tester) async {
    final revealBoundary = DateTime.utc(2026, 6, 20, 14, 45);
    final dailyGraph = _FailingFirstBoundaryMarkAccessGraph(
      clock: () => revealBoundary,
    );
    final expectedBoundary = revealBoundary;

    await tester.pumpWidget(
      _homeApp(
        dailyGraph: dailyGraph.graph,
        clock: () => revealBoundary,
        dailyWisdomOperationTimeout: const Duration(seconds: 5),
      ),
    );
    await _finishOpeningIntro(tester);
    await _advanceToQuestion(tester);

    await _tapCenter(tester);
    await tester.pump(const Duration(milliseconds: 1250));
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    await _pumpUntilCondition(tester, () => dailyGraph.failedBoundaryMarkOnce);

    expect(find.byKey(const ValueKey('wisdom-reveal-fade')), findsOneWidget);
    expect(dailyGraph.failedBoundaryMarkOnce, isTrue);
    expect(_keptGuard(tester).ignoring, isTrue);
    expect(
      await dailyGraph.repository.loadDailyWisdomRecord(),
      isNull,
    );
    final pendingBeforeRetry =
        await dailyGraph.repository.loadPendingDailyWisdomReveal();
    expect(pendingBeforeRetry, isNotNull);
    expect(
      pendingBeforeRetry!.phase,
      PendingDailyWisdomRevealPhase.prepared,
    );
    expect(pendingBeforeRetry.confirmedRevealBoundary, isNull);

    await _tapCenter(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    final persisted = await dailyGraph.repository.loadDailyWisdomRecord();
    expect(persisted, isNotNull);
    expect(
      persisted!.revealedAt.millisecondsSinceEpoch,
      expectedBoundary.millisecondsSinceEpoch,
    );
    expect(
      persisted.unlockAt.millisecondsSinceEpoch,
      expectedBoundary.add(const Duration(hours: 24)).millisecondsSinceEpoch,
    );
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
          id: 'existing-locked-reflection',
          text: existingWisdom,
          date: 'June 21, 2026',
        ).encode(),
      ],
    });

    await tester.pumpWidget(
      _homeApp(),
    );
    await _finishOpeningIntro(tester);
    expect(find.byKey(const ValueKey('launch-ritual-mark')), findsOneWidget);

    await _openExistingWisdom(tester);

    expect(find.text(existingWisdom), findsOneWidget);
    expect(
      find.textContaining('Return when the silence opens again.'),
      findsOneWidget,
    );
    expect(find.text(removedRevealAnother), findsNothing);
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

  testWidgets('free locked wisdom offers no extra reveal action',
      (tester) async {
    final now = DateTime.now();
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': DailyWisdomRecord(
        text: 'Free received wisdom',
        revealedAt: now,
        unlockAt: now.add(const Duration(hours: 24)),
      ).encode(),
    });

    await tester.pumpWidget(
      _homeApp(),
    );
    await _finishOpeningIntro(tester);
    await _openExistingWisdom(tester);

    expect(find.text('Free received wisdom'), findsOneWidget);
    expect(find.text(removedRevealAnother), findsNothing);
    expect(find.byKey(const ValueKey('reveal-another')), findsNothing);
  });

  testWidgets('Keeper reopens to the shared locked wisdom without extra reveal',
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
      _homeApp(),
    );
    await _finishOpeningIntro(tester);
    await _openExistingWisdom(tester);

    expect(find.text('Keeper received wisdom'), findsOneWidget);
    expect(find.text(removedRevealAnother), findsNothing);
    expect(
      find.textContaining('Return when the silence opens again.'),
      findsOneWidget,
    );
    expect(find.text('Pause.'), findsNothing);
    expect(find.text('Feel.'), findsNothing);
    expect(find.text('Ask from your heart.'), findsNothing);
  });

  testWidgets('Keeper cannot restart the ritual inside the rolling lock',
      (tester) async {
    final now = DateTime.now();
    SharedPreferences.setMockInitialValues({
      'is_premium': true,
      'daily_wisdom_access': DailyWisdomRecord(
        text: 'Keeper one daily wisdom',
        revealedAt: now,
        unlockAt: now.add(const Duration(hours: 24)),
      ).encode(),
    });

    await tester.pumpWidget(
      _homeApp(),
    );
    await _finishOpeningIntro(tester);
    await _openExistingWisdom(tester);

    expect(find.text('Keeper one daily wisdom'), findsOneWidget);
    expect(find.text(removedRevealAnother), findsNothing);
    expect(find.byTooltip('Keep reflection'), findsOneWidget);

    final countdown = tester.widget<Text>(
      find.textContaining('Return when the silence opens again.'),
    );
    final countdownLines = countdown.data!.split('\n');
    expect(countdownLines.first, 'Return when the silence opens again.');
    expect(countdownLines, hasLength(2));
    expect(
      countdownLines.last,
      anyOf(
        matches(RegExp(r'^\d+h \d+m$')),
        matches(RegExp(r'^\d+ min$')),
      ),
    );
  });

  testWidgets('obsolete Keeper quota cache is ignored on launch',
      (tester) async {
    final today = DateTime.now();
    final localDate =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    SharedPreferences.setMockInitialValues({
      'is_premium': true,
      'keeper_daily_wisdom_state':
          '{"localDate":"$localDate","revealCount":2,"lastWisdom":"Legacy Keeper wisdom","hasPendingReveal":false}',
    });

    await tester.pumpWidget(
      _homeApp(),
    );
    await _finishOpeningIntro(tester);
    await _advanceFromLaunchToPause(tester);

    expect(find.text('Legacy Keeper wisdom'), findsNothing);
    expect(find.text(removedRevealAnother), findsNothing);
    expect(find.textContaining('Return when the silence opens again.'),
        findsNothing);
    expect(find.text('Pause.'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('daily_wisdom_access'), isFalse);
    expect(prefs.containsKey('keeper_daily_wisdom_state'), isFalse);
  });

  testWidgets('corrupt locked state returns ready without synthetic wisdom',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': '{',
    });

    await tester.pumpWidget(
      _homeApp(),
    );
    await _finishOpeningIntro(tester);
    await _advanceFromLaunchToPause(tester);

    expect(
      find.textContaining('Return when the silence opens again.'),
      findsNothing,
    );
    expect(
      find.text('Silence is still available.'),
      findsNothing,
    );
    expect(find.text('Pause.'), findsOneWidget);
    expect(find.text('Ask from your heart.'), findsNothing);
  });

  testWidgets('legacy sentinel is not reopened as locked wisdom',
      (tester) async {
    final now = DateTime.now();
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': DailyWisdomRecord(
        text: DailyWisdomAccessService.corruptRecordRecoveryText,
        revealedAt: now,
        unlockAt: now.add(const Duration(hours: 24)),
      ).encode(),
    });

    await tester.pumpWidget(
      _homeApp(),
    );
    await _finishOpeningIntro(tester);
    await _openExistingWisdom(tester);

    expect(
      find.text(DailyWisdomAccessService.corruptRecordRecoveryText),
      findsNothing,
    );
    expect(
      find.textContaining('Return when the silence opens again.'),
      findsOneWidget,
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
      _homeApp(),
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
      _homeApp(),
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
      _homeApp(),
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
    await tester.pump();
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
      _homeApp(),
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
    await tester.pump(const Duration(milliseconds: 548));
    expect(find.byKey(const ValueKey('black-silence')), findsOneWidget);
    expect(find.byKey(const ValueKey('wisdom-reveal-fade')), findsNothing);

    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey('black-silence')), findsOneWidget);

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
      _homeApp(),
    );
    await _finishOpeningIntro(tester);
    await _advanceToQuestion(tester);

    await _tapCenter(tester);
    await tester.pump(const Duration(milliseconds: 1250));
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();

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

  testWidgets('rapid save taps persist one consistent reflection',
      (tester) async {
    final now = DateTime.now();
    const wisdom = 'One reflection under rapid taps';
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': DailyWisdomRecord(
        text: wisdom,
        revealedAt: now,
        unlockAt: now.add(const Duration(hours: 24)),
      ).encode(),
    });

    await tester.pumpWidget(
      _homeApp(),
    );
    await _finishOpeningIntro(tester);
    await _openExistingWisdom(tester);
    await tester.pump();

    final save = find.byTooltip('Keep reflection');
    expect(save, findsOneWidget);
    expect(_keptGuard(tester).ignoring, isFalse);
    final saveButton = tester.widget<IconButton>(
      find.ancestor(of: save, matching: find.byType(IconButton)),
    );
    saveButton.onPressed!();
    saveButton.onPressed!();
    await tester.pump(const Duration(milliseconds: 20));

    final persisted = await SavedReflectionsService().load();
    expect(persisted, hasLength(1));
    expect(persisted.single.text, wisdom);
    expect(find.byTooltip('Remove kept reflection'), findsOneWidget);
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
              child: HomeScreen(
                  dailyWisdomAccessService: DailyAccessTestGraph().service),
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

void _expectSemanticNode({
  required String label,
  required bool isButton,
  required Tristate isEnabled,
  required bool hasTap,
}) {
  final matches = find.semantics.byLabel(label).evaluate();
  expect(matches, hasLength(1));
  final data = matches.single.getSemanticsData();
  final actualIsButton = data.flagsCollection.isButton;
  final actualIsEnabled = data.flagsCollection.isEnabled;
  final actualHasTap = data.hasAction(SemanticsAction.tap);
  final reason = 'Semantics for "$label": button=$actualIsButton, '
      'enabled=$actualIsEnabled, tap=$actualHasTap';
  expect(actualIsButton, isButton, reason: reason);
  expect(actualIsEnabled, isEnabled, reason: reason);
  expect(actualHasTap, hasTap, reason: reason);
}

Widget _homeApp({
  DailyAccessTestGraph? dailyGraph,
  StorageService? storageService,
  SavedReflectionsService? savedReflectionsService,
  WisdomClock? clock,
  Duration dailyWisdomOperationTimeout = const Duration(seconds: 8),
  Duration dailyWisdomStatusTimeout =
      DailyWisdomAccessService.defaultStatusTimeout,
}) {
  final resolvedDailyGraph = dailyGraph ?? DailyAccessTestGraph(clock: clock);
  return MaterialApp(
    home: HomeScreen(
      storageService: storageService ?? StorageService(),
      savedReflectionsService:
          savedReflectionsService ?? SavedReflectionsService(),
      dailyWisdomAccessService: resolvedDailyGraph.service,
      clock: clock,
      dailyWisdomOperationTimeout: dailyWisdomOperationTimeout,
      dailyWisdomStatusTimeout: dailyWisdomStatusTimeout,
    ),
  );
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

Future<void> _pumpUntilCondition(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 8,
}) async {
  for (var attempt = 0; attempt < maxPumps && !condition(); attempt += 1) {
    await tester.pump();
  }
}

Future<void> _advanceFromLaunchToPause(WidgetTester tester) async {
  await _tapCenter(tester);
  await tester.pump(const Duration(milliseconds: 850));
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 850));
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

double _askFadeValue(WidgetTester tester) {
  return tester
      .widget<FadeTransition>(
        find.byKey(const ValueKey('ask-fade')),
      )
      .opacity
      .value;
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

class _DelayedPendingDailyAccessGraph {
  _DelayedPendingDailyAccessGraph._(this._adapter)
      : graph = DailyAccessTestGraph(adapter: _adapter);

  final _DelayedPendingAdapter _adapter;
  final DailyAccessTestGraph graph;

  bool get pendingSaveStarted => _adapter.pendingSaveStarted;
  DailyAccessRepository get repository => graph.repository;
  DailyWisdomAccessService get service => graph.service;

  void releasePendingSave() {
    _adapter.releasePendingSave();
  }

  factory _DelayedPendingDailyAccessGraph() {
    return _DelayedPendingDailyAccessGraph._(_DelayedPendingAdapter());
  }
}

class _HangingPendingDailyAccessGraph {
  _HangingPendingDailyAccessGraph()
      : graph =
            DailyAccessTestGraph(adapter: InterceptingStoragePreferencesAdapter(
          setStringInterceptor: (key, value, persist) {
            if (key == DailyAccessRepository.pendingDailyWisdomRevealKey) {
              return Completer<void>().future;
            }

            return persist();
          },
        ));

  final DailyAccessTestGraph graph;

  DailyWisdomAccessService get service => graph.service;
}

class _DelayedDailyWriteAccessGraph {
  _DelayedDailyWriteAccessGraph._(this._adapter, {WisdomClock? clock})
      : graph = DailyAccessTestGraph(adapter: _adapter, clock: clock);

  final _DelayedDailyWriteAdapter _adapter;
  final DailyAccessTestGraph graph;

  bool get dailyWriteStarted => _adapter.dailyWriteStarted;
  DailyWisdomRecord? get attemptedRecord => _adapter.attemptedRecord;
  DailyAccessRepository get repository => graph.repository;
  DailyWisdomAccessService get service => graph.service;

  void releaseDailyWrite() {
    _adapter.releaseDailyWrite();
  }

  factory _DelayedDailyWriteAccessGraph({WisdomClock? clock}) {
    return _DelayedDailyWriteAccessGraph._(
      _DelayedDailyWriteAdapter(),
      clock: clock,
    );
  }
}

class _HangingDailyWriteAccessGraph {
  _HangingDailyWriteAccessGraph._(this._adapter, {WisdomClock? clock})
      : graph = DailyAccessTestGraph(adapter: _adapter, clock: clock);

  final _HangingDailyWriteAdapter _adapter;
  final DailyAccessTestGraph graph;

  bool get dailyWriteStarted => _adapter.dailyWriteStarted;
  DailyWisdomAccessService get service => graph.service;

  factory _HangingDailyWriteAccessGraph({WisdomClock? clock}) {
    return _HangingDailyWriteAccessGraph._(
      _HangingDailyWriteAdapter(),
      clock: clock,
    );
  }
}

class _FailingFirstBoundaryMarkAccessGraph {
  _FailingFirstBoundaryMarkAccessGraph._(this._adapter, {WisdomClock? clock})
      : graph = DailyAccessTestGraph(adapter: _adapter, clock: clock);

  factory _FailingFirstBoundaryMarkAccessGraph({WisdomClock? clock}) {
    return _FailingFirstBoundaryMarkAccessGraph._(
      _FailingFirstBoundaryMarkAdapter(),
      clock: clock,
    );
  }

  final _FailingFirstBoundaryMarkAdapter _adapter;
  final DailyAccessTestGraph graph;

  bool get failedBoundaryMarkOnce => _adapter.failedBoundaryMarkOnce;
  DailyAccessRepository get repository => graph.repository;
  DailyWisdomAccessService get service => graph.service;
}

class _DelayedPendingAdapter extends InterceptingStoragePreferencesAdapter {
  final Completer<void> _pendingSaveGate = Completer<void>();
  bool pendingSaveStarted = false;

  void releasePendingSave() {
    if (!_pendingSaveGate.isCompleted) {
      _pendingSaveGate.complete();
    }
  }

  @override
  Future<void> setString(String key, String value) async {
    if (key == DailyAccessRepository.pendingDailyWisdomRevealKey) {
      pendingSaveStarted = true;
      await _pendingSaveGate.future;
    }

    await super.setString(key, value);
  }
}

class _DelayedDailyWriteAdapter extends InterceptingStoragePreferencesAdapter {
  final Completer<void> _dailyWriteGate = Completer<void>();
  bool dailyWriteStarted = false;
  DailyWisdomRecord? attemptedRecord;

  void releaseDailyWrite() {
    if (!_dailyWriteGate.isCompleted) {
      _dailyWriteGate.complete();
    }
  }

  @override
  Future<void> setString(String key, String value) async {
    if (key == DailyAccessRepository.dailyWisdomAccessKey) {
      dailyWriteStarted = true;
      attemptedRecord = DailyWisdomRecord.decode(value);
      await _dailyWriteGate.future;
    }

    await super.setString(key, value);
  }
}

class _HangingDailyWriteAdapter extends InterceptingStoragePreferencesAdapter {
  bool dailyWriteStarted = false;

  @override
  Future<void> setString(String key, String value) {
    if (key == DailyAccessRepository.dailyWisdomAccessKey) {
      dailyWriteStarted = true;
      return Completer<void>().future;
    }

    return super.setString(key, value);
  }
}

class _FailingFirstBoundaryMarkAdapter
    extends InterceptingStoragePreferencesAdapter {
  bool failedBoundaryMarkOnce = false;

  @override
  Future<void> setString(String key, String value) {
    if (key == DailyAccessRepository.pendingDailyWisdomRevealKey) {
      final reveal = PendingDailyWisdomReveal.decode(value);
      if (reveal.isRevealedPendingCommit && !failedBoundaryMarkOnce) {
        failedBoundaryMarkOnce = true;
        throw StateError('Boundary mark failed once.');
      }
    }

    return super.setString(key, value);
  }
}
