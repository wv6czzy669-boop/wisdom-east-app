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
import 'package:wisdom_app/services/wisdom_notification_service.dart';
import 'package:wisdom_app/services/wisdom_share_service.dart';
import 'package:wisdom_app/theme/muted_text_color.dart';
import 'package:wisdom_app/utils/directional_page_route.dart';
import 'package:wisdom_app/widgets/grain_painter.dart';
import 'package:wisdom_app/widgets/home/top_nav_ring.dart';

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
    expect(find.byKey(const ValueKey('settings-menu-control')), findsNothing);
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
    expect(_renderedRitualOpacity(tester), 1.0);
    final opacityElement =
        find.byKey(const ValueKey('ritual-content-opacity')).evaluate().single;

    await _tapCenter(tester);
    await tester.pump();
    final launchFade = tester.widget<AnimatedOpacity>(
      find.byKey(const ValueKey('ritual-content-opacity')),
    );
    expect(launchFade.opacity, 0.0);
    expect(launchFade.duration, const Duration(milliseconds: 750));
    expect(
      find.byKey(const ValueKey('ritual-content-opacity')).evaluate().single,
      same(opacityElement),
    );

    expect(_renderedRitualOpacity(tester), 1.0);
    await tester.pump(const Duration(milliseconds: 375));
    expect(_renderedRitualOpacity(tester), inExclusiveRange(0.0, 1.0));
    expect(markFinder, findsOneWidget);

    await tester.pump(const Duration(milliseconds: 445));
    expect(find.text('Pause.'), findsOneWidget);
    expect(_renderedRitualOpacity(tester), 0.0);
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump(const Duration(milliseconds: 1250));
    await tester.pump(const Duration(milliseconds: 820));
  });

  testWidgets('ritual text transitions preserve fade frames', (tester) async {
    await tester.pumpWidget(
      _homeApp(),
    );
    await _finishOpeningIntro(tester);

    final launchMark = find.byKey(const ValueKey('launch-ritual-mark'));
    expect(launchMark, findsOneWidget);

    await _tapCenter(tester);
    await tester.pump();

    final launchFade = tester.widget<AnimatedOpacity>(
      find.byKey(const ValueKey('ritual-content-opacity')),
    );
    expect(launchFade.opacity, 0.0);
    expect(launchFade.duration, const Duration(milliseconds: 750));
    expect(launchMark, findsOneWidget);
    expect(_renderedRitualOpacity(tester), 1.0);

    await tester.pump(const Duration(milliseconds: 400));
    expect(launchMark, findsOneWidget);
    expect(_renderedRitualOpacity(tester), inExclusiveRange(0.0, 1.0));

    await tester.pump(const Duration(milliseconds: 420));
    await tester.pump();
    expect(find.text('Pause.'), findsOneWidget);
    expect(_ritualOpacity(tester), 0.0);
    expect(_renderedRitualOpacity(tester), 0.0);

    await tester.pump(const Duration(milliseconds: 220));
    expect(_ritualOpacity(tester), 1.0);
    expect(_renderedRitualOpacity(tester), 0.0);
    await tester.pump(const Duration(milliseconds: 625));
    expect(_renderedRitualOpacity(tester), inExclusiveRange(0.0, 1.0));
    await tester.pump(const Duration(milliseconds: 625));
    expect(_renderedRitualOpacity(tester), 1.0);
    await tester.pump(const Duration(milliseconds: 820));

    await _tapCenter(tester);
    await tester.pump();
    expect(_feelVisualOpacity(tester), 0.0);
    await tester.pump(const Duration(milliseconds: 625));
    expect(_feelVisualOpacity(tester), inExclusiveRange(0.0, 1.0));
    await tester.pump(const Duration(milliseconds: 625));
    expect(_feelVisualOpacity(tester), 1.0);
    expect(find.text('Pause.'), findsOneWidget);
    expect(find.text('Feel.'), findsOneWidget);
    expect(_ritualOpacity(tester), 1.0);

    await _tapCenter(tester);
    await tester.pump();
    expect(_ritualOpacity(tester), 0.0);
    expect(_renderedRitualOpacity(tester), 1.0);

    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Pause.'), findsOneWidget);
    expect(find.text('Feel.'), findsOneWidget);
    expect(find.text('Ask from your heart.'), findsNothing);
    expect(_renderedRitualOpacity(tester), inExclusiveRange(0.0, 1.0));

    await tester.pump(const Duration(milliseconds: 649));
    expect(find.text('Pause.'), findsOneWidget);
    expect(find.text('Feel.'), findsOneWidget);
    expect(find.text('Ask from your heart.'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(find.text('Ask from your heart.'), findsOneWidget);
    expect(_ritualOpacity(tester), 0.0);
    expect(_renderedRitualOpacity(tester), 0.0);

    await tester.pump(const Duration(milliseconds: 220));
    expect(_ritualOpacity(tester), 1.0);
    expect(_renderedRitualOpacity(tester), 0.0);
    await tester.pump(const Duration(milliseconds: 625));
    expect(_renderedRitualOpacity(tester), inExclusiveRange(0.0, 1.0));
    await tester.pump(const Duration(milliseconds: 625));
    expect(_renderedRitualOpacity(tester), 1.0);
    await tester.pump(const Duration(milliseconds: 560));
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
      expect(find.byTooltip('Objects'), findsOneWidget);
      final objectsNode = tester.getSemantics(find.byTooltip('Objects'));
      expect(
        objectsNode.getSemanticsData().hasAction(SemanticsAction.tap),
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
      await tester.pump(const Duration(milliseconds: 1250));
      await tester.pump(const Duration(milliseconds: 220));
      await tester.pump(const Duration(milliseconds: 560));
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

  testWidgets(
      'top navigation opens Settings, Objects, and Kept from their respective controls',
      (tester) async {
    final now = DateTime.now();
    const wisdom = 'A wisdom used to verify top navigation destinations';
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': DailyWisdomRecord(
        text: wisdom,
        revealedAt: now,
        unlockAt: now.add(const Duration(hours: 24)),
      ).encode(),
    });

    // Deterministic proof of push counts, independent of route-content
    // mount timing — see `_HomePushCountingNavigatorObserver`.
    final pushObserver = _HomePushCountingNavigatorObserver();
    // This test exercises Settings -> pop -> Objects -> pop -> Kept, which
    // means `openSettings()`'s post-pop `finally` (gated on
    // `synchronizeUnlockNotification()`) must resolve before the Objects
    // tap's guard check can be expected to let a push through. A fresh,
    // per-test `WisdomNotificationService` (wrapping the existing
    // `_HomeNotificationPlatform` fake already used elsewhere in this file)
    // keeps that resolution deterministic and test-local, rather than
    // depending on the shared process-wide `app_services
    // .wisdomNotificationService` singleton and however many operations
    // preceding tests in this file have already queued onto it.
    final notificationPlatform = _HomeNotificationPlatform(enabled: true);
    final notificationService =
        WisdomNotificationService(platform: notificationPlatform);
    await tester.pumpWidget(_homeApp(
      navigatorObservers: [pushObserver],
      wisdomNotificationService: notificationService,
    ));
    await _finishOpeningIntro(tester);
    await _openExistingWisdom(tester);

    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.byTooltip('Objects'), findsOneWidget);
    expect(find.byTooltip('Kept'), findsOneWidget);

    // The far-left three-line control opens Settings directly (no drawer,
    // popup menu, or bottom sheet).
    expect(_homeNavigationInProgress(tester), isFalse);
    final pushesBeforeSettings = pushObserver.pushCount;
    await tester.tap(find.byTooltip('Settings'));
    final settingsDuration = await _settleRoutePush(
      tester,
      find.byKey(const ValueKey('settings-scroll')),
    );
    expect(
      pushObserver.pushCount,
      pushesBeforeSettings + 1,
      reason: 'Settings tap must produce exactly one didPush.',
    );
    expect(find.text('Where silence speaks.'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await _settleRoutePop(
      tester,
      settingsDuration,
      poppedRouteFinder: find.byKey(const ValueKey('settings-scroll')),
    );
    expect(find.byKey(const ValueKey('top-navigation')), findsOneWidget);

    // The repurposed left circle now opens Objects — not Settings. This is
    // the exact tap that failed intermittently on real Mac validation
    // ("Found 0 widgets with key objects-screen-root") whenever this test
    // ran after other tests in the suite: if the Settings pop's guard
    // (`navigationInProgress`) had not actually reset yet, this tap would
    // be silently swallowed by `openObjects()`'s own guard check and no
    // push would happen at all. Proving both the guard state and the push
    // count directly (rather than only inferring them from mount timing)
    // is what makes this assertion meaningful.
    expect(
      _homeNavigationInProgress(tester),
      isFalse,
      reason: 'navigationInProgress must have reset after the Settings pop '
          'before the Objects tap can be expected to push anything.',
    );
    final pushesBeforeObjects = pushObserver.pushCount;
    await tester.tap(find.byTooltip('Objects'));
    final objectsDuration = await _settleRoutePush(
      tester,
      find.byKey(const ValueKey('objects-screen-root')),
    );
    expect(
      pushObserver.pushCount,
      pushesBeforeObjects + 1,
      reason: 'Objects tap must produce exactly one didPush.',
    );
    expect(find.text('Objects'), findsOneWidget);
    expect(find.text('Where silence speaks.'), findsNothing);
    await tester.tap(find.byTooltip('Back'));
    await _settleRoutePop(
      tester,
      objectsDuration,
      poppedRouteFinder: find.byKey(const ValueKey('objects-screen-root')),
    );
    expect(find.byKey(const ValueKey('top-navigation')), findsOneWidget);

    // The rightmost circle still opens Kept, unchanged.
    expect(_homeNavigationInProgress(tester), isFalse);
    final pushesBeforeKept = pushObserver.pushCount;
    await tester.tap(find.byTooltip('Kept'));
    await _settleRoutePush(
        tester, find.byKey(const ValueKey('kept-screen-root')));
    expect(
      pushObserver.pushCount,
      pushesBeforeKept + 1,
      reason: 'Kept tap must produce exactly one didPush.',
    );
    expect(find.text('Kept'), findsOneWidget);
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
    expect(find.byKey(const ValueKey('settings-menu-control')), findsNothing);
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
    expect(find.byTooltip('Objects'), findsOneWidget);
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

  testWidgets('returning from Kept reloads a removed current wisdom',
      (tester) async {
    final now = DateTime.now();
    const wisdom = 'A kept wisdom removed from its quiet list';
    final kept = FavoriteItem(
      id: 'remove-from-kept',
      text: wisdom,
      date: 'July 23, 2026',
      reflection: 'A private reflection',
    );
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': DailyWisdomRecord(
        text: wisdom,
        revealedAt: now,
        unlockAt: now.add(const Duration(hours: 24)),
      ).encode(),
      'favorites': [kept.encode()],
    });

    await tester.pumpWidget(_homeApp());
    await _finishOpeningIntro(tester);
    await _openExistingWisdom(tester);
    expect(find.byTooltip('Remove kept reflection'), findsOneWidget);

    await tester.tap(find.byTooltip('Kept'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('kept-remove-from-kept')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('kept-remove-from-kept-delete-action')),
    );
    await tester.pumpAndSettle();
    expect(find.text(wisdom), findsNothing);

    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(find.text(wisdom), findsOneWidget);
    expect(find.byTooltip('Keep reflection'), findsOneWidget);
    expect(await SavedReflectionsService().load(), isEmpty);
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
    expect(countdown.style?.color, eastMutedTextColor);
    expect(
      tester.widget<Text>(find.text('Keeper one daily wisdom')).style?.color,
      isNot(eastMutedTextColor),
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
    expect(find.byKey(const ValueKey('settings-menu-control')), findsNothing);
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
    await tester.pump(const Duration(milliseconds: 1250));
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump(const Duration(milliseconds: 560));

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

  testWidgets(
      'top navigation uses deliberate ring/bar geometry: Objects is a single '
      'ring, Kept is a concentric double ring, no Unicode circle glyphs '
      'remain, and tap targets/destinations/semantics are unchanged',
      (tester) async {
    final now = DateTime.now();
    const wisdom = 'A wisdom used to verify top navigation ring geometry';
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': DailyWisdomRecord(
        text: wisdom,
        revealedAt: now,
        unlockAt: now.add(const Duration(hours: 24)),
      ).encode(),
    });

    // Fresh, per-test notification service. This test doesn't pop Settings
    // before its own Objects/Kept taps, but it still mounts a HomeScreen
    // whose `initState` unconditionally calls `synchronizeUnlockNotification()`
    // — an injected instance keeps that call test-local instead of
    // depending on the shared `app_services.wisdomNotificationService`
    // singleton other tests in this file also touch.
    final notificationPlatform = _HomeNotificationPlatform(enabled: true);
    final notificationService =
        WisdomNotificationService(platform: notificationPlatform);
    await tester.pumpWidget(
      _homeApp(wisdomNotificationService: notificationService),
    );
    await _finishOpeningIntro(tester);
    await _openExistingWisdom(tester);

    // No Unicode circle glyphs remain anywhere in the top navigation.
    for (final glyph in ['○', '◎', '●']) {
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('top-navigation')),
          matching: find.text(glyph),
        ),
        findsNothing,
      );
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('settings-menu-control')),
        matching: find.byWidgetPredicate((w) => w is Text),
      ),
      findsNothing,
    );

    // Objects renders exactly one ring; Kept renders exactly two.
    final objectsPainter = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byTooltip('Objects'),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter! as TopNavRingPainter;
    expect(objectsPainter.ringCount, 1);

    final keptPainter = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byTooltip('Kept'),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter! as TopNavRingPainter;
    expect(keptPainter.ringCount, 2);

    // Objects and Kept share the exact same outer diameter, stroke width,
    // and color by construction (both read the one shared geometry token),
    // and identical outer bounding boxes / tap targets / vertical centers.
    expect(objectsPainter.ringCount == keptPainter.ringCount, isFalse);
    expect(TopNavRingGeometry.outerDiameter, greaterThan(0));
    expect(
      tester.getSize(find.byType(SingleRingIcon)),
      const Size.square(TopNavRingGeometry.outerDiameter),
    );
    expect(
      tester.getSize(find.byType(DoubleRingIcon)),
      const Size.square(TopNavRingGeometry.outerDiameter),
    );
    expect(
      tester.getSize(find.byTooltip('Objects')),
      tester.getSize(find.byTooltip('Kept')),
    );
    expect(
      tester.getSize(find.byTooltip('Settings')),
      tester.getSize(find.byTooltip('Kept')),
    );
    expect(
      tester.getCenter(find.byTooltip('Objects')).dy,
      tester.getCenter(find.byTooltip('Kept')).dy,
    );
    expect(
      tester.getCenter(find.byTooltip('Settings')).dy,
      tester.getCenter(find.byTooltip('Kept')).dy,
    );
    // Objects sits immediately to the left of Kept, which stays the
    // far-right control; the hamburger stays on the far left.
    expect(
      tester.getCenter(find.byTooltip('Settings')).dx,
      lessThan(tester.getCenter(find.byTooltip('Objects')).dx),
    );
    expect(
      tester.getCenter(find.byTooltip('Objects')).dx,
      lessThan(tester.getCenter(find.byTooltip('Kept')).dx),
    );

    // Semantics/tooltips/destinations remain correct.
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.byTooltip('Objects'), findsOneWidget);
    expect(find.byTooltip('Kept'), findsOneWidget);

    // No grey background/ripple/halo on any of the three controls.
    for (final tooltip in ['Settings', 'Objects', 'Kept']) {
      final button = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip(tooltip),
          matching: find.byType(IconButton),
        ),
      );
      final style = button.style!;
      expect(style.backgroundColor?.resolve({}), Colors.transparent);
      expect(style.overlayColor?.resolve({}), Colors.transparent);
    }

    await tester.tap(find.byTooltip('Objects'));
    final objectsDuration = await _settleRoutePush(
      tester,
      find.byKey(const ValueKey('objects-screen-root')),
    );
    expect(find.text('Objects'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await _settleRoutePop(
      tester,
      objectsDuration,
      poppedRouteFinder: find.byKey(const ValueKey('objects-screen-root')),
    );
    expect(find.byKey(const ValueKey('top-navigation')), findsOneWidget);

    await tester.tap(find.byTooltip('Kept'));
    await _settleRoutePush(
        tester, find.byKey(const ValueKey('kept-screen-root')));
    expect(find.text('Kept'), findsOneWidget);
  });

  testWidgets(
      'Settings pushes as a left-origin DirectionalPageRoute while Objects '
      'and Kept remain plain (right-origin) MaterialPageRoutes',
      (tester) async {
    final now = DateTime.now();
    const wisdom = 'A wisdom used to verify route transition directions';
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': DailyWisdomRecord(
        text: wisdom,
        revealedAt: now,
        unlockAt: now.add(const Duration(hours: 24)),
      ).encode(),
    });

    final pushObserver = _HomePushCountingNavigatorObserver();
    // Fresh, per-test notification service — see the identical rationale in
    // "top navigation opens Settings, Objects, and Kept…" above. This test
    // pops Settings then taps Objects, so it depends on the same post-pop
    // guard-reset timing.
    final notificationPlatform = _HomeNotificationPlatform(enabled: true);
    final notificationService =
        WisdomNotificationService(platform: notificationPlatform);
    await tester.pumpWidget(_homeApp(
      navigatorObservers: [pushObserver],
      wisdomNotificationService: notificationService,
    ));
    await _finishOpeningIntro(tester);
    await _openExistingWisdom(tester);

    expect(_homeNavigationInProgress(tester), isFalse);
    final pushesBeforeSettings = pushObserver.pushCount;
    await tester.tap(find.byTooltip('Settings'));
    final settingsDuration = await _settleRoutePush(
      tester,
      find.byKey(const ValueKey('settings-scroll')),
    );
    expect(pushObserver.pushCount, pushesBeforeSettings + 1);
    final settingsRoute = ModalRoute.of(
      tester.element(find.byKey(const ValueKey('settings-scroll'))),
    );
    expect(settingsRoute, isA<DirectionalPageRoute>());
    final directionalRoute = settingsRoute! as DirectionalPageRoute;
    expect(directionalRoute.beginOffset, const Offset(-1, 0));
    // The route's own transitionDuration is exactly what was just used to
    // settle its push above — this is the canonical, single-sourced
    // production value (see `DirectionalPageRoute`'s `_duration`), not a
    // value re-declared in the test.
    expect(directionalRoute.transitionDuration, settingsDuration);
    expect(settingsDuration, const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Back'));
    await _settleRoutePop(
      tester,
      settingsDuration,
      poppedRouteFinder: find.byKey(const ValueKey('settings-scroll')),
    );
    expect(find.byKey(const ValueKey('top-navigation')), findsOneWidget);

    // This is the tap that failed intermittently on real Mac validation
    // when this test ran as part of a larger suite: proving
    // `navigationInProgress` is false and asserting the exact push count
    // (rather than only inferring success from mount timing) turns "did
    // the tap get silently swallowed by a still-active guard" into a
    // directly observable fact.
    expect(
      _homeNavigationInProgress(tester),
      isFalse,
      reason: 'navigationInProgress must have reset after the Settings pop '
          'before the Objects tap can be expected to push anything.',
    );
    final pushesBeforeObjects = pushObserver.pushCount;
    await tester.tap(find.byTooltip('Objects'));
    final objectsDuration = await _settleRoutePush(
      tester,
      find.byKey(const ValueKey('objects-screen-root')),
    );
    expect(pushObserver.pushCount, pushesBeforeObjects + 1);
    final objectsRoute = ModalRoute.of(
      tester.element(find.byKey(const ValueKey('objects-screen-root'))),
    );
    expect(objectsRoute, isA<MaterialPageRoute>());
    expect(objectsRoute, isNot(isA<DirectionalPageRoute>()));
    await tester.tap(find.byTooltip('Back'));
    await _settleRoutePop(
      tester,
      objectsDuration,
      poppedRouteFinder: find.byKey(const ValueKey('objects-screen-root')),
    );
    expect(find.byKey(const ValueKey('top-navigation')), findsOneWidget);

    expect(_homeNavigationInProgress(tester), isFalse);
    final pushesBeforeKept = pushObserver.pushCount;
    await tester.tap(find.byTooltip('Kept'));
    final keptDuration = await _settleRoutePush(
      tester,
      find.byKey(const ValueKey('kept-screen-root')),
    );
    expect(pushObserver.pushCount, pushesBeforeKept + 1);
    final keptRoute = ModalRoute.of(
      tester.element(find.byKey(const ValueKey('kept-screen-root'))),
    );
    expect(keptRoute, isA<MaterialPageRoute>());
    expect(keptRoute, isNot(isA<DirectionalPageRoute>()));
    expect(keptDuration, keptRoute!.transitionDuration);
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
    expect(find.byTooltip('Objects'), findsOneWidget);
    // The ring icons are drawn geometrically (CustomPaint), not from text
    // glyphs, so a 3x text scale cannot distort or overflow them.
    final objectsPainterAt3x = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byTooltip('Objects'),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter! as TopNavRingPainter;
    expect(objectsPainterAt3x.ringCount, 1);
    expect(find.byTooltip('Kept'), findsOneWidget);
    final keptPainterAt3x = tester
        .widget<CustomPaint>(
          find.descendant(
            of: find.byTooltip('Kept'),
            matching: find.byType(CustomPaint),
          ),
        )
        .painter! as TopNavRingPainter;
    expect(keptPainterAt3x.ringCount, 2);
    // All three top-navigation controls share the same tap-target size so
    // the restrained hamburger control balances visually with the circles.
    expect(
      tester.getSize(find.byTooltip('Objects')),
      tester.getSize(find.byTooltip('Kept')),
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
    await tester.pump(const Duration(milliseconds: 1250));
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pump(const Duration(milliseconds: 560));
    expect(find.text('Ask from your heart.'), findsOneWidget);
    expect(find.text(removedRevealPrompt), findsNothing);
    final askTextFinder = find.text('Ask from your heart.');
    final askSizeBeforeFade = tester.getSize(askTextFinder);
    final askStyleBeforeFade = tester.widget<Text>(askTextFinder).style;

    await _tapCenter(tester);
    await tester.pump();
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.byTooltip('Objects'), findsOneWidget);
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
    expect(find.byTooltip('Objects'), findsOneWidget);
    expect(find.byTooltip('Kept'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey('black-silence')), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.byTooltip('Objects'), findsOneWidget);
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

  testWidgets('wisdom sharing is unavailable before a reveal', (tester) async {
    final shareService = _RecordingWisdomShareService();

    await tester.pumpWidget(
      _homeApp(wisdomShareService: shareService),
    );
    await _finishOpeningIntro(tester);

    await tester.longPress(
      find.byKey(const ValueKey('launch-ritual-mark')),
    );
    await tester.pump();

    expect(shareService.calls, 0);
    expect(find.byKey(const ValueKey('wisdom-reveal-fade')), findsNothing);
  });

  testWidgets(
      'revealed wisdom shares exact text without changing access or notification',
      (tester) async {
    final now = DateTime.utc(2041, 7, 23, 8);
    const wisdom = 'The current wisdom remains unchanged.';
    final record = DailyWisdomRecord(
      text: wisdom,
      revealedAt: now,
      unlockAt: now.add(const Duration(hours: 24)),
    );
    SharedPreferences.setMockInitialValues({
      DailyAccessRepository.dailyWisdomAccessKey: record.encode(),
    });
    final shareService = _RecordingWisdomShareService()..blockNext();
    final notificationPlatform = _HomeNotificationPlatform(enabled: true);
    final notificationService = WisdomNotificationService(
      platform: notificationPlatform,
      clock: () => now,
    );

    await tester.pumpWidget(
      _homeApp(
        dailyGraph: DailyAccessTestGraph(clock: () => now),
        clock: () => now,
        wisdomShareService: shareService,
        wisdomNotificationService: notificationService,
      ),
    );
    await _finishOpeningIntro(tester);
    await _openExistingWisdom(tester);
    await _pumpUntilWisdomShareEnabled(tester);

    final semantics = tester.getSemantics(find.text(wisdom));
    expect(semantics.label, wisdom);
    expect(semantics.hint, 'Long press to share this wisdom.');
    expect(
      semantics.getSemanticsData().hasAction(SemanticsAction.longPress),
      isTrue,
    );

    final schedulesBeforeShare = notificationPlatform.schedules.length;
    await tester.longPress(find.text(wisdom));
    _wisdomShareGesture(tester).onLongPress!();
    await tester.pump();

    expect(shareService.calls, 1);
    expect(shareService.wisdoms, [wisdom]);
    expect(shareService.origins.single.width, greaterThan(0));
    expect(shareService.origins.single.height, greaterThan(0));

    shareService.release();
    await tester.pump();
    _wisdomShareGesture(tester).onLongPress!();
    await tester.pump();

    expect(shareService.calls, 2);
    expect(notificationPlatform.schedules.length, schedulesBeforeShare);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(DailyAccessRepository.dailyWisdomAccessKey),
      record.encode(),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('share guard resets after failure and disposal is safe',
      (tester) async {
    final now = DateTime.utc(2041, 7, 23, 8);
    const wisdom = 'A quiet failure cannot disturb this wisdom.';
    final record = DailyWisdomRecord(
      text: wisdom,
      revealedAt: now,
      unlockAt: now.add(const Duration(hours: 24)),
    );
    SharedPreferences.setMockInitialValues({
      DailyAccessRepository.dailyWisdomAccessKey: record.encode(),
    });
    final shareService = _RecordingWisdomShareService()..failNext = true;

    await tester.pumpWidget(
      _homeApp(
        dailyGraph: DailyAccessTestGraph(clock: () => now),
        clock: () => now,
        wisdomShareService: shareService,
      ),
    );
    await _finishOpeningIntro(tester);
    await _openExistingWisdom(tester);
    await _pumpUntilWisdomShareEnabled(tester);

    _wisdomShareGesture(tester).onLongPress!();
    await tester.pump();
    expect(shareService.calls, 1);
    expect(tester.takeException(), isNull);

    shareService
      ..failNext = false
      ..blockNext();
    _wisdomShareGesture(tester).onLongPress!();
    await tester.pump();
    expect(shareService.calls, 2);

    await tester.pumpWidget(const SizedBox.shrink());
    shareService.release();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('successful reveal schedules persisted unlock exactly once',
      (tester) async {
    final now = DateTime.utc(2041, 7, 23, 8);
    final dailyGraph = DailyAccessTestGraph(clock: () => now);
    final notificationPlatform = _HomeNotificationPlatform(enabled: true);
    final notificationService = WisdomNotificationService(
      platform: notificationPlatform,
      clock: () => now,
    );

    await tester.pumpWidget(
      _homeApp(
        dailyGraph: dailyGraph,
        clock: () => now,
        wisdomNotificationService: notificationService,
      ),
    );
    await _finishOpeningIntro(tester);
    await _advanceToQuestion(tester);

    await _tapCenter(tester);
    await tester.pump(const Duration(milliseconds: 1250));
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    await tester.pump();

    final persisted = await dailyGraph.repository.loadDailyWisdomRecord();
    expect(persisted, isNotNull);
    expect(notificationPlatform.schedules, hasLength(1));
    expect(
      notificationPlatform.schedules.single.unlockAt.millisecondsSinceEpoch,
      persisted!.unlockAt.millisecondsSinceEpoch,
    );
    expect(notificationPlatform.schedules.single.title, 'EAST.');
    expect(
      notificationPlatform.schedules.single.body,
      'Something waits in silence.',
    );

    await _pumpUntilWisdomFullyAppeared(tester);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets(
      'notDetermined status triggers exactly one direct native permission '
      'request at the existing timing, with no custom permission dialog '
      'ever shown, and no repeat request on a later resume', (tester) async {
    final now = DateTime.utc(2041, 7, 23, 8);
    final notificationPlatform = _HomeNotificationPlatform(enabled: false);
    final notificationService = WisdomNotificationService(
      platform: notificationPlatform,
      clock: () => now,
    );

    await tester.pumpWidget(
      _homeApp(
        dailyGraph: DailyAccessTestGraph(clock: () => now),
        clock: () => now,
        wisdomNotificationService: notificationService,
      ),
    );
    await _finishOpeningIntro(tester);
    expect(notificationPlatform.permissionRequests, 0);

    await _advanceToQuestion(tester);
    await _tapCenter(tester);
    await tester.pump(const Duration(milliseconds: 1250));
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    await _pumpUntilWisdomFullyAppeared(tester);
    await _pumpInSteps(tester, const Duration(milliseconds: 5999));
    // Not yet at the existing trigger delay: no request fired, no dialog.
    expect(notificationPlatform.permissionRequests, 0);
    expect(find.text('Not now'), findsNothing);
    expect(find.text('Allow'), findsNothing);

    await _pumpInSteps(tester, const Duration(milliseconds: 2));
    // At the existing trigger delay: the native request fires directly.
    expect(notificationPlatform.permissionRequests, 1);
    expect(tester.takeException(), isNull);

    // No application-owned dialog was ever shown, at any point.
    expect(find.text('Not now'), findsNothing);
    expect(find.text('Allow'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);

    // The prompt is now marked handled, so a later resume must not
    // request again.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 6800));
    expect(notificationPlatform.permissionRequests, 1);
  });

  testWidgets(
      'native grant at the existing trigger schedules exactly once, with no '
      'tap or intermediate step required', (tester) async {
    final now = DateTime.utc(2041, 7, 23, 8);
    final dailyGraph = DailyAccessTestGraph(clock: () => now);
    final notificationPlatform = _HomeNotificationPlatform(
      enabled: false,
      permissionResult: true,
    );
    final notificationService = WisdomNotificationService(
      platform: notificationPlatform,
      clock: () => now,
    );

    await tester.pumpWidget(
      _homeApp(
        dailyGraph: dailyGraph,
        clock: () => now,
        wisdomNotificationService: notificationService,
      ),
    );
    await _finishOpeningIntro(tester);
    await _advanceToQuestion(tester);
    await _tapCenter(tester);
    await tester.pump(const Duration(milliseconds: 1250));
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    await _pumpUntilWisdomFullyAppeared(tester);
    await _pumpInSteps(tester, const Duration(seconds: 7));
    await tester.pump();

    final persisted = await dailyGraph.repository.loadDailyWisdomRecord();
    expect(notificationPlatform.permissionRequests, 1);
    expect(notificationPlatform.schedules, hasLength(1));
    expect(
      notificationPlatform.schedules.single.unlockAt.millisecondsSinceEpoch,
      persisted!.unlockAt.millisecondsSinceEpoch,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'native denial at the existing trigger is nonfatal, requests only '
      'once, and shows no custom UI', (tester) async {
    final now = DateTime.utc(2041, 7, 23, 8);
    final notificationPlatform = _HomeNotificationPlatform(
      enabled: false,
      permissionResult: false,
    );
    final notificationService = WisdomNotificationService(
      platform: notificationPlatform,
      clock: () => now,
    );

    await tester.pumpWidget(
      _homeApp(
        dailyGraph: DailyAccessTestGraph(clock: () => now),
        clock: () => now,
        wisdomNotificationService: notificationService,
      ),
    );
    await _finishOpeningIntro(tester);
    await _advanceToQuestion(tester);
    await _tapCenter(tester);
    await tester.pump(const Duration(milliseconds: 1250));
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    await _pumpUntilWisdomFullyAppeared(tester);
    await _pumpInSteps(tester, const Duration(seconds: 7));
    await tester.pump();

    expect(notificationPlatform.permissionRequests, 1);
    expect(notificationPlatform.schedules, isEmpty);
    expect(find.text('Not now'), findsNothing);
    expect(find.text('Allow'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'already-authorized status never requests native permission again at '
      'the existing trigger', (tester) async {
    final now = DateTime.utc(2041, 7, 23, 8);
    final notificationPlatform = _HomeNotificationPlatform(enabled: true);
    final notificationService = WisdomNotificationService(
      platform: notificationPlatform,
      clock: () => now,
    );

    await tester.pumpWidget(
      _homeApp(
        dailyGraph: DailyAccessTestGraph(clock: () => now),
        clock: () => now,
        wisdomNotificationService: notificationService,
      ),
    );
    await _finishOpeningIntro(tester);
    await _advanceToQuestion(tester);
    await _tapCenter(tester);
    await tester.pump(const Duration(milliseconds: 1250));
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    await _pumpUntilWisdomFullyAppeared(tester);
    await _pumpInSteps(tester, const Duration(seconds: 7));
    await tester.pump();

    expect(notificationPlatform.permissionRequests, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'an explicit Daily Reminder OFF blocks the reveal-time direct path '
      'entirely: no native permission request, no scheduling, no custom '
      'dialog, even though the system status is notDetermined', (tester) async {
    final now = DateTime.utc(2041, 7, 23, 8);
    final notificationPlatform = _HomeNotificationPlatform(
      enabled: false,
      permissionResult: true,
    );
    final notificationService = WisdomNotificationService(
      platform: notificationPlatform,
      clock: () => now,
    );
    await notificationService.disableDailyReminder();

    await tester.pumpWidget(
      _homeApp(
        dailyGraph: DailyAccessTestGraph(clock: () => now),
        clock: () => now,
        wisdomNotificationService: notificationService,
      ),
    );
    await _finishOpeningIntro(tester);
    await _advanceToQuestion(tester);
    await _tapCenter(tester);
    await tester.pump(const Duration(milliseconds: 1250));
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    await _pumpUntilWisdomFullyAppeared(tester);
    await _pumpInSteps(tester, const Duration(seconds: 7));
    await tester.pump();

    expect(notificationPlatform.permissionRequests, 0);
    expect(notificationPlatform.schedules, isEmpty);
    expect(find.text('Not now'), findsNothing);
    expect(find.text('Allow'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      await notificationService.reminderPreference(),
      DailyReminderPreference.disabled,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposal during an in-flight native permission request is safe',
      (tester) async {
    final now = DateTime.utc(2041, 7, 23, 8);
    final permissionGate = Completer<bool>();
    final notificationPlatform = _HomeNotificationPlatform(
      enabled: false,
      permissionGate: permissionGate,
    );
    final notificationService = WisdomNotificationService(
      platform: notificationPlatform,
      clock: () => now,
    );

    await tester.pumpWidget(
      _homeApp(
        dailyGraph: DailyAccessTestGraph(clock: () => now),
        clock: () => now,
        wisdomNotificationService: notificationService,
      ),
    );
    await _finishOpeningIntro(tester);
    await _advanceToQuestion(tester);
    await _tapCenter(tester);
    await tester.pump(const Duration(milliseconds: 1250));
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    await _pumpUntilWisdomFullyAppeared(tester);
    await _pumpInSteps(tester, const Duration(seconds: 7));
    expect(notificationPlatform.permissionRequests, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    permissionGate.complete(true);
    await tester.pump();
    await tester.pump();

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

  testWidgets(
      'the Kept save control renders no grey background, overlay, or splash '
      'in any interaction state, while toggling and tap target are unaffected',
      (tester) async {
    final now = DateTime.now();
    const wisdom = 'A wisdom used to verify the save control has no halo';
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': DailyWisdomRecord(
        text: wisdom,
        revealedAt: now,
        unlockAt: now.add(const Duration(hours: 24)),
      ).encode(),
    });

    await tester.pumpWidget(_homeApp());
    await _finishOpeningIntro(tester);
    await _openExistingWisdom(tester);
    await tester.pump();

    final unsavedButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('Keep reflection'),
        matching: find.byType(IconButton),
      ),
    );
    final unsavedStyle = unsavedButton.style;
    expect(unsavedStyle, isNotNull);
    for (final states in [
      <WidgetState>{},
      {WidgetState.hovered},
      {WidgetState.focused},
      {WidgetState.pressed},
    ]) {
      expect(
          unsavedStyle!.backgroundColor?.resolve(states), Colors.transparent);
      expect(unsavedStyle.overlayColor?.resolve(states), Colors.transparent);
    }
    expect(
      find.descendant(
        of: find.byTooltip('Keep reflection'),
        matching: find.text('○'),
      ),
      findsOneWidget,
    );
    final unsavedSize = tester.getSize(find.byTooltip('Keep reflection'));

    await tester.tap(find.byTooltip('Keep reflection'));
    await tester.pump();

    expect(find.byTooltip('Remove kept reflection'), findsOneWidget);
    expect(
      (await SavedReflectionsService().load()).single.text,
      wisdom,
    );

    final savedButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('Remove kept reflection'),
        matching: find.byType(IconButton),
      ),
    );
    final savedStyle = savedButton.style;
    expect(savedStyle, isNotNull);
    for (final states in [
      <WidgetState>{},
      {WidgetState.hovered},
      {WidgetState.focused},
      {WidgetState.pressed},
    ]) {
      expect(
        savedStyle!.backgroundColor?.resolve(states),
        Colors.transparent,
      );
      expect(savedStyle.overlayColor?.resolve(states), Colors.transparent);
    }
    expect(
      find.descendant(
        of: find.byTooltip('Remove kept reflection'),
        matching: find.text('●'),
      ),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byTooltip('Remove kept reflection')),
      unsavedSize,
    );

    await tester.tap(find.byTooltip('Remove kept reflection'));
    await tester.pump();
    expect(find.byTooltip('Keep reflection'), findsOneWidget);
    expect(await SavedReflectionsService().load(), isEmpty);
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
  WisdomShareHandler? wisdomShareService,
  WisdomNotificationService? wisdomNotificationService,
  WisdomClock? clock,
  Duration dailyWisdomOperationTimeout = const Duration(seconds: 8),
  Duration dailyWisdomStatusTimeout =
      DailyWisdomAccessService.defaultStatusTimeout,
  List<NavigatorObserver> navigatorObservers = const <NavigatorObserver>[],
}) {
  final resolvedDailyGraph = dailyGraph ?? DailyAccessTestGraph(clock: clock);
  return MaterialApp(
    navigatorObservers: navigatorObservers,
    home: HomeScreen(
      storageService: storageService ?? StorageService(),
      savedReflectionsService:
          savedReflectionsService ?? SavedReflectionsService(),
      dailyWisdomAccessService: resolvedDailyGraph.service,
      wisdomShareService: wisdomShareService,
      wisdomNotificationService: wisdomNotificationService,
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
  await tester.pump(const Duration(milliseconds: 1250));
  await tester.pump(const Duration(milliseconds: 220));
  await tester.pump(const Duration(milliseconds: 560));
}

double _ritualOpacity(WidgetTester tester) {
  return tester
      .widget<AnimatedOpacity>(
        find.byKey(const ValueKey('ritual-content-opacity')),
      )
      .opacity;
}

double _renderedRitualOpacity(WidgetTester tester) {
  final animatedOpacity = find.byKey(const ValueKey('ritual-content-opacity'));
  return tester
      .widget<FadeTransition>(
        find
            .descendant(
              of: animatedOpacity,
              matching: find.byType(FadeTransition),
            )
            .first,
      )
      .opacity
      .value;
}

double _feelVisualOpacity(WidgetTester tester) {
  final feelOpacity = find.ancestor(
    of: find.text('Feel.'),
    matching: find.byType(AnimatedOpacity),
  );
  return tester
      .widget<FadeTransition>(
        find
            .descendant(
              of: feelOpacity.first,
              matching: find.byType(FadeTransition),
            )
            .first,
      )
      .opacity
      .value;
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

GestureDetector _wisdomShareGesture(WidgetTester tester) {
  final reveal = find.byKey(const ValueKey('wisdom-reveal-fade'));
  return tester
      .widgetList<GestureDetector>(
        find.ancestor(
          of: reveal,
          matching: find.byType(GestureDetector),
        ),
      )
      .firstWhere(
        (gesture) => gesture.key is GlobalKey && gesture.onLongPress != null,
      );
}

Future<void> _pumpUntilWisdomShareEnabled(WidgetTester tester) async {
  for (var attempt = 0; attempt < 40; attempt += 1) {
    final reveal = find.byKey(const ValueKey('wisdom-reveal-fade'));
    if (reveal.evaluate().isNotEmpty) {
      final gestures = tester.widgetList<GestureDetector>(
        find.ancestor(
          of: reveal,
          matching: find.byType(GestureDetector),
        ),
      );
      if (gestures.any(
        (gesture) => gesture.key is GlobalKey && gesture.onLongPress != null,
      )) {
        return;
      }
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  final reveal = find.byKey(const ValueKey('wisdom-reveal-fade'));
  final revealOpacity = reveal.evaluate().isEmpty
      ? null
      : tester.widget<FadeTransition>(reveal).opacity.value;
  final globalGestures = reveal.evaluate().isEmpty
      ? const <GestureDetector>[]
      : tester
          .widgetList<GestureDetector>(
            find.ancestor(
              of: reveal,
              matching: find.byType(GestureDetector),
            ),
          )
          .where((gesture) => gesture.key is GlobalKey)
          .toList();
  fail(
    'Revealed wisdom did not become shareable: opacity=$revealOpacity, '
    'global gestures=${globalGestures.length}, '
    'callbacks=${globalGestures.map((gesture) => gesture.onLongPress != null)}.',
  );
}

Future<void> _pumpUntilWisdomFullyAppeared(WidgetTester tester) async {
  for (var attempt = 0; attempt < 200; attempt += 1) {
    final reveal = find.byKey(const ValueKey('wisdom-reveal-fade'));
    if (reveal.evaluate().isNotEmpty &&
        tester.widget<FadeTransition>(reveal).opacity.value >= 1.0) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 10));
  }
  fail('Wisdom reveal fade did not complete.');
}

Future<void> _pumpInSteps(
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

// Home's ritual pulse animation never idles on its own, so `pumpAndSettle()`
// would never return while Home is anywhere in the route stack. These
// helpers replace it with a bounded pump driven by the actual pushed
// route's own `transitionDuration` (rather than a disconnected magic
// value), plus a small fixed margin for rendering/test overhead.
const Duration _routeTransitionMargin = Duration(milliseconds: 50);

/// Maximum number of small pumps to wait for the newly pushed route's
/// content to actually mount before giving up. 30 * 16ms = 480ms, safely
/// more than the 300ms production route-transition duration, so a route
/// that mounts normally is found well within this bound.
const int _routeMountBoundedAttempts = 30;
const Duration _routeMountPollStep = Duration(milliseconds: 16);

/// Pumps until the newly pushed route's content actually mounts (a single
/// zero-duration pump is not guaranteed to be enough — the route's
/// content is built on the frame after the push, not synchronously with
/// it), then reads its real `transitionDuration` from `routeContentFinder`
/// (a finder that must match exactly one widget once the new route is
/// built — a unique widget type or stable `Key`, never ambiguous text),
/// pumps through that transition, and returns the duration so the caller
/// can reuse the exact same value when later popping back off this route.
Future<Duration> _settleRoutePush(
  WidgetTester tester,
  Finder routeContentFinder,
) async {
  await tester.pump();

  for (var attempt = 0;
      attempt < _routeMountBoundedAttempts &&
          routeContentFinder.evaluate().isEmpty;
      attempt++) {
    await tester.pump(_routeMountPollStep);
  }

  expect(
    routeContentFinder,
    findsOneWidget,
    reason: 'Route content did not mount within '
        '${_routeMountBoundedAttempts * _routeMountPollStep.inMilliseconds}ms '
        'of the push.',
  );

  final element = tester.element(routeContentFinder);
  final route = ModalRoute.of(element);
  expect(route, isNotNull);

  final transitionDuration = route!.transitionDuration;
  await tester.pump(transitionDuration + _routeTransitionMargin);
  await tester.pump();
  return transitionDuration;
}

/// Reads the live `navigationInProgress` guard straight off the mounted
/// `HomeScreen`'s `State`. The field is not underscore-prefixed, so — even
/// though `_HomeScreenState` itself is a private type this test file cannot
/// name — it is a perfectly ordinary public member and can be read via a
/// `dynamic` reference to the `State` object returned by `tester.state`.
///
/// `openSettings()`/`openObjects()`/`openKeeperScreen()` only flip this
/// guard back to `false` inside a `finally` block that runs *after*
/// `await Navigator.push(...)` resolves — and for `openSettings()`
/// specifically, that `finally` also waits on
/// `await synchronizeUnlockNotification()` first. Reading this guard
/// directly (bounded poll, see [_settleRoutePop]) proves whether it has
/// actually reset, instead of inferring that from a fixed pump duration.
bool _homeNavigationInProgress(WidgetTester tester) {
  final dynamic homeState = tester.state(find.byType(HomeScreen));
  return homeState.navigationInProgress as bool;
}

/// Pumps through a pop using the same `transitionDuration` obtained from
/// [_settleRoutePush] for the route being popped, then proves — rather than
/// assumes — that the pop has fully settled before the caller's next
/// action (typically another tap on a top-navigation control guarded by
/// `HomeScreen.navigationInProgress`):
///
/// 1. [poppedRouteFinder], when supplied, must stop matching (bounded poll)
///    — the popped route's content is actually gone and Home is back on
///    screen, not just mid-transition.
/// 2. `HomeScreen.navigationInProgress` must return to `false` (bounded
///    poll) — proving the post-pop `finally` block has actually completed
///    and the next tap's guard check will not be silently short-circuited.
Future<void> _settleRoutePop(
  WidgetTester tester,
  Duration transitionDuration, {
  Finder? poppedRouteFinder,
}) async {
  await tester.pump();
  await tester.pump(transitionDuration + _routeTransitionMargin);
  await tester.pump();

  if (poppedRouteFinder != null) {
    for (var attempt = 0;
        attempt < _routeMountBoundedAttempts &&
            poppedRouteFinder.evaluate().isNotEmpty;
        attempt++) {
      await tester.pump(_routeMountPollStep);
    }
    expect(
      poppedRouteFinder,
      findsNothing,
      reason: 'Popped route content is still mounted '
          '${_routeMountBoundedAttempts * _routeMountPollStep.inMilliseconds}ms '
          'after the pop.',
    );
  }

  for (var attempt = 0;
      attempt < _routeMountBoundedAttempts && _homeNavigationInProgress(tester);
      attempt++) {
    await tester.pump(_routeMountPollStep);
  }
  expect(
    _homeNavigationInProgress(tester),
    isFalse,
    reason: 'HomeScreen.navigationInProgress did not reset after the route '
        'pop.',
  );
}

/// Test-only `NavigatorObserver` that proves exactly how many pushes have
/// happened on the `HomeScreen`'s navigator, ignoring the initial route.
/// Used to give a deterministic, non-timing-based answer to "did this tap
/// actually push a route" instead of inferring it solely from whether the
/// destination's content later becomes findable.
class _HomePushCountingNavigatorObserver extends NavigatorObserver {
  int pushCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) {
      pushCount += 1;
    }
  }
}

class _RecordingWisdomShareService implements WisdomShareHandler {
  int calls = 0;
  bool failNext = false;
  Completer<void>? _gate;
  final List<String> wisdoms = [];
  final List<Rect> origins = [];

  void blockNext() {
    _gate = Completer<void>();
  }

  void release() {
    final gate = _gate;
    _gate = null;
    if (gate != null && !gate.isCompleted) {
      gate.complete();
    }
  }

  @override
  Future<void> shareWisdom({
    required String wisdom,
    required Rect sharePositionOrigin,
  }) async {
    calls += 1;
    wisdoms.add(wisdom);
    origins.add(sharePositionOrigin);
    final gate = _gate;
    if (gate != null) {
      await gate.future;
    }
    if (failNext) {
      failNext = false;
      throw StateError('share failed');
    }
  }
}

class _HomeNotificationPlatform implements WisdomNotificationPlatform {
  _HomeNotificationPlatform({
    required this.enabled,
    this.permissionResult = false,
    this.permissionGate,
  });

  bool enabled;
  final bool permissionResult;
  final Completer<bool>? permissionGate;
  int permissionRequests = 0;
  final List<_HomeScheduledNotification> schedules = [];

  @override
  Future<void> initialize() async {}

  @override
  Future<bool?> notificationsEnabled() async => enabled;

  @override
  Future<bool> requestPermission() async {
    permissionRequests += 1;
    final gate = permissionGate;
    final result = gate == null ? permissionResult : await gate.future;
    if (result) enabled = true;
    return result;
  }

  @override
  Future<void> cancel(int id) async {}

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime unlockAt,
  }) async {
    schedules.add(
      _HomeScheduledNotification(
        title: title,
        body: body,
        unlockAt: unlockAt,
      ),
    );
  }
}

class _HomeScheduledNotification {
  const _HomeScheduledNotification({
    required this.title,
    required this.body,
    required this.unlockAt,
  });

  final String title;
  final String body;
  final DateTime unlockAt;
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
