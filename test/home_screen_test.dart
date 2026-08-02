import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/models/daily_wisdom_record.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/models/kept_record.dart';
import 'package:wisdom_app/models/pending_daily_wisdom_reveal.dart';
import 'package:wisdom_app/repositories/daily_access_repository.dart';
import 'package:wisdom_app/screens/home_screen.dart';
import 'package:wisdom_app/services/daily_wisdom_access_service.dart';
import 'package:wisdom_app/services/kept_discovery_hint_service.dart';
import 'package:wisdom_app/services/saved_reflections_service.dart';
import 'package:wisdom_app/services/storage_service.dart';
import 'package:wisdom_app/services/wisdom_notification_service.dart';
import 'package:wisdom_app/services/wisdom_share_service.dart';
import 'package:wisdom_app/theme/muted_text_color.dart';
import 'package:wisdom_app/utils/date_formatter.dart';
import 'package:wisdom_app/utils/legacy_kept_identity.dart';
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

      expect(
          find.byKey(const ValueKey('home-settings-control')), findsOneWidget);
      final settingsNode = tester
          .getSemantics(find.byKey(const ValueKey('home-settings-control')));
      expect(
        settingsNode.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
      expect(
          find.byKey(const ValueKey('home-objects-control')), findsOneWidget);
      final objectsNode = tester
          .getSemantics(find.byKey(const ValueKey('home-objects-control')));
      expect(
        objectsNode.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
      expect(find.byKey(const ValueKey('home-kept-control')), findsOneWidget);
      final keptNode =
          tester.getSemantics(find.byKey(const ValueKey('home-kept-control')));
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

    expect(find.byKey(const ValueKey('home-settings-control')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-objects-control')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-kept-control')), findsOneWidget);

    // The far-left three-line control opens Settings directly (no drawer,
    // popup menu, or bottom sheet).
    expect(_homeNavigationInProgress(tester), isFalse);
    final pushesBeforeSettings = pushObserver.pushCount;
    await tester.tap(find.byKey(const ValueKey('home-settings-control')));
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
    await tester.tap(find.byKey(const ValueKey('home-objects-control')));
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
    await tester.tap(find.byKey(const ValueKey('home-kept-control')));
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
    // Item 3 (3D-C correction, Section 4): the late-arriving authoritative
    // commit's revealId/revealedAt are what the live `HomeScreen` state
    // ends up holding — not left null or stale from before the slow write
    // resolved.
    expect(persisted.revealId, isNotNull);
    expect(_homeCurrentRevealId(tester), persisted.revealId);
    expect(
      _homeCurrentRevealedAt(tester)?.millisecondsSinceEpoch,
      persisted.revealedAt.millisecondsSinceEpoch,
    );
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
      revealId: _fixedRevealId,
    );
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': originalRecord.encode(),
    });
    final keptGraph = KeptRepositoryTestGraph()
      ..seed([
        _testKeptRecord(
          id: 'existing-locked-reflection',
          revealId: _fixedRevealId,
          wisdomText: existingWisdom,
          revealedAt: now,
        ),
      ]);

    await tester.pumpWidget(
      _homeApp(keptGraph: keptGraph),
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
    expect(find.byKey(const ValueKey('home-settings-control')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-objects-control')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-kept-control')), findsOneWidget);
    // Item 2 (3D-C correction, Section 4): a locked `DailyWisdomStatus`
    // reopened from disk retains its authoritative revealId/revealedAt on
    // the live `HomeScreen` state — not just in the persisted record — so
    // `currentFavorite()`/`toggleFavorite()` keep working from a re-view.
    expect(_homeCurrentRevealId(tester), _fixedRevealId);
    expect(
      _homeCurrentRevealedAt(tester)?.millisecondsSinceEpoch,
      now.millisecondsSinceEpoch,
    );
    expect(
        find.byKey(const ValueKey('home-save-control-kept')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-save-control-kept')),
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

  testWidgets(
      'Phase 3D-E safety-gap correction: a Build 25 wisdom already Kept '
      'before the upgrade shows a filled Keep ring on the very first '
      'stable render -- no interactive empty-ring frame, no duplicate '
      'record, idempotent across relaunch, and preserved after returning '
      'from Kept', (tester) async {
    final now = DateTime.now();
    const wisdom = 'A Build 25 wisdom already Kept before the Build 26 upgrade';

    // No revealId: exactly how a pre-Build-26 authoritative daily record
    // looks before `backfillRevealIdIfNeeded()` ever runs.
    final legacyDailyRecord = DailyWisdomRecord(
      text: wisdom,
      revealedAt: now,
      unlockAt: now.add(const Duration(hours: 24)),
    );
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': legacyDailyRecord.encode(),
    });

    // A migrated KeptRecord for the exact same occurrence: a real,
    // parseable `sr-v1-<micros>-<serial>` legacy id whose embedded save
    // instant falls inside [revealedAt, unlockAt), carrying the
    // deterministic v5 revealId `KeptMigrationCoordinator` would have
    // minted for it -- the exact real-world state a successful Phase 3D-D
    // migration leaves behind, *before* this reconciliation fix existed.
    final legacyId = 'sr-v1-${now.microsecondsSinceEpoch}-0';
    final keptGraph = KeptRepositoryTestGraph()
      ..seed([
        _testKeptRecord(
          id: legacyId,
          revealId: deriveLegacyMigrationRevealId(legacyId),
          wisdomText: wisdom,
          revealedAt: now,
          reflectionText: 'A private reflection kept before the upgrade',
        ),
      ]);

    await tester.pumpWidget(_homeApp(keptGraph: keptGraph));
    await _finishOpeningIntro(tester);
    await _openExistingWisdom(tester);

    // First stable render: the ring is already filled -- never an
    // interactive empty-ring frame first, even transiently.
    expect(find.text(wisdom), findsOneWidget);
    expect(
        find.byKey(const ValueKey('home-save-control-kept')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('home-save-control-unsaved')), findsNothing);

    final afterFirstRender = await keptGraph.service.load();
    expect(afterFirstRender, hasLength(1));
    final backfilledRevealId = _homeCurrentRevealId(tester);
    expect(backfilledRevealId, isNotNull);
    expect(afterFirstRender.single.revealId, backfilledRevealId);
    expect(afterFirstRender.single.id, legacyId);
    expect(
      afterFirstRender.single.reflection,
      'A private reflection kept before the upgrade',
    );

    final mutationIdAfterFirstRender =
        keptGraph.store.envelope!.activeRecords.single.mutationId;

    // Relaunch: a fresh HomeScreen (and a fresh DailyAccessRepository,
    // exactly like a real app restart) built against the same underlying
    // persisted daily-access state and the same protected Kept store --
    // reconciliation must be a pure no-op this time.
    await tester.pumpWidget(_homeApp(keptGraph: keptGraph));
    await _finishOpeningIntro(tester);
    await _openExistingWisdom(tester);

    expect(
        find.byKey(const ValueKey('home-save-control-kept')), findsOneWidget);
    final afterRelaunch = await keptGraph.service.load();
    expect(afterRelaunch, hasLength(1));
    expect(afterRelaunch.single.revealId, backfilledRevealId);
    expect(
      keptGraph.store.envelope!.activeRecords.single.mutationId,
      mutationIdAfterFirstRender,
      reason: 'no second mutation occurred on relaunch',
    );

    // Returning from Kept preserves the filled state.
    await tester.tap(find.byKey(const ValueKey('home-kept-control')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(find.text(wisdom), findsOneWidget);
    expect(
        find.byKey(const ValueKey('home-save-control-kept')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('home-save-control-unsaved')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Phase 3D-E safety-gap correction: insufficient migration evidence '
      '(no parseable legacy save-instant) leaves the Keep ring unfilled, '
      'and the daily record still safely falls back to an ordinary v4 '
      'backfill', (tester) async {
    final now = DateTime.now();
    const wisdom = 'Text matches, but the evidence does not';

    // No revealId: same pre-Build-26 shape as the successful-reconciliation
    // test above.
    final legacyDailyRecord = DailyWisdomRecord(
      text: wisdom,
      revealedAt: now,
      unlockAt: now.add(const Duration(hours: 24)),
    );
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': legacyDailyRecord.encode(),
    });

    // Matching text and a revealId that satisfies the provenance gate, but
    // an id shape (`legacy-v1-...`) that carries no timestamp at all --
    // `parseLegacySavedReflectionId` correctly returns null for it, so the
    // resolver can never prove this is the same occurrence. Mirrors
    // `kept_repository_test.dart` test 66.
    const noTimestampId = 'legacy-v1-3-abcd1234';
    final keptGraph = KeptRepositoryTestGraph()
      ..seed([
        _testKeptRecord(
          id: noTimestampId,
          revealId: deriveLegacyMigrationRevealId(noTimestampId),
          wisdomText: wisdom,
          revealedAt: now,
        ),
      ]);

    await tester.pumpWidget(_homeApp(keptGraph: keptGraph));
    await _finishOpeningIntro(tester);
    await _openExistingWisdom(tester);

    // The ring must remain unfilled -- text/provenance alone is never
    // enough evidence to reconcile.
    expect(find.text(wisdom), findsOneWidget);
    expect(find.byKey(const ValueKey('home-save-control-kept')), findsNothing);
    expect(find.byKey(const ValueKey('home-save-control-unsaved')),
        findsOneWidget);

    // The daily record itself remains safe and usable: it received an
    // ordinary fresh v4 backfill (Case D), never the unrelated Kept
    // record's revealId, and the pre-existing, unrelated Kept record was
    // never touched.
    final dailyRevealId = _homeCurrentRevealId(tester);
    expect(dailyRevealId, isNotNull);
    expect(dailyRevealId, isNot(deriveLegacyMigrationRevealId(noTimestampId)));

    final favorites = await keptGraph.service.load();
    expect(favorites, hasLength(1));
    expect(favorites.single.id, noTimestampId);
    expect(tester.takeException(), isNull);
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
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': DailyWisdomRecord(
        text: wisdom,
        revealedAt: now,
        unlockAt: now.add(const Duration(hours: 24)),
        revealId: _fixedRevealId,
      ).encode(),
    });
    final keptGraph = KeptRepositoryTestGraph()
      ..seed([
        _testKeptRecord(
          id: 'remove-from-kept',
          revealId: _fixedRevealId,
          wisdomText: wisdom,
          revealedAt: now,
          reflectionText: 'A private reflection',
        ),
      ]);

    await tester.pumpWidget(_homeApp(keptGraph: keptGraph));
    await _finishOpeningIntro(tester);
    await _openExistingWisdom(tester);
    expect(
        find.byKey(const ValueKey('home-save-control-kept')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-kept-control')));
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
    expect(find.byKey(const ValueKey('home-save-control-unsaved')),
        findsOneWidget);
    expect(await keptGraph.service.load(), isEmpty);
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
    expect(find.byKey(const ValueKey('home-save-control-unsaved')),
        findsOneWidget);

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
    // The startup backfill gives this re-viewed legacy record a real
    // identity before the refresh below wipes it — proving the wipe (not
    // an identity that was simply never set) is what Item 4 depends on.
    expect(_homeCurrentRevealId(tester), isNotNull);

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
    // Item 4 (3D-C correction, Section 4): returning to the ready/unlocked
    // state clears the stale reveal identity — a later reveal must never
    // inherit an old occurrence's revealId/revealedAt.
    expect(_homeCurrentRevealId(tester), isNull);
    expect(_homeCurrentRevealedAt(tester), isNull);
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

    // Objects renders exactly one ring; Kept renders exactly two. Each ring
    // `CustomPaint` is located directly by its own stable key (asserted
    // unique before being read), not by walking up from a tooltip/ancestor.
    final objectsPainter =
        _topNavRingPainterByKey(tester, 'objects-top-nav-ring');
    expect(objectsPainter.ringCount, 1);

    final keptPainter = _topNavRingPainterByKey(tester, 'kept-top-nav-ring');
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
      tester.getSize(find.byKey(const ValueKey('home-objects-control'))),
      tester.getSize(find.byKey(const ValueKey('home-kept-control'))),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('home-settings-control'))),
      tester.getSize(find.byKey(const ValueKey('home-kept-control'))),
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey('home-objects-control'))).dy,
      tester.getCenter(find.byKey(const ValueKey('home-kept-control'))).dy,
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey('home-settings-control'))).dy,
      tester.getCenter(find.byKey(const ValueKey('home-kept-control'))).dy,
    );
    // Objects sits immediately to the left of Kept, which stays the
    // far-right control; the hamburger stays on the far left.
    expect(
      tester.getCenter(find.byKey(const ValueKey('home-settings-control'))).dx,
      lessThan(
        tester.getCenter(find.byKey(const ValueKey('home-objects-control'))).dx,
      ),
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey('home-objects-control'))).dx,
      lessThan(
        tester.getCenter(find.byKey(const ValueKey('home-kept-control'))).dx,
      ),
    );

    // Semantics/destinations remain correct.
    expect(find.byKey(const ValueKey('home-settings-control')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-objects-control')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-kept-control')), findsOneWidget);

    // No grey background/ripple/halo on any of the three controls. Each key
    // is on the actual `IconButton` itself now (the `Tooltip` wrapper that
    // used to sit between the tooltip finder and the button is gone), so
    // `tester.widget<IconButton>` reads it directly rather than via an
    // ancestor walk.
    for (final controlKey in [
      'home-settings-control',
      'home-objects-control',
      'home-kept-control',
    ]) {
      final button =
          tester.widget<IconButton>(find.byKey(ValueKey(controlKey)));
      final style = button.style!;
      expect(style.backgroundColor?.resolve({}), Colors.transparent);
      expect(style.overlayColor?.resolve({}), Colors.transparent);
    }

    await tester.tap(find.byKey(const ValueKey('home-objects-control')));
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

    await tester.tap(find.byKey(const ValueKey('home-kept-control')));
    await _settleRoutePush(
        tester, find.byKey(const ValueKey('kept-screen-root')));
    expect(find.text('Kept'), findsOneWidget);
  });

  testWidgets(
      'Settings, Objects, and Kept all push as plain (right-origin) '
      'MaterialPageRoutes with native interactive edge-swipe-back',
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
    await tester.tap(find.byKey(const ValueKey('home-settings-control')));
    final settingsDuration = await _settleRoutePush(
      tester,
      find.byKey(const ValueKey('settings-scroll')),
    );
    expect(pushObserver.pushCount, pushesBeforeSettings + 1);
    final settingsRoute = ModalRoute.of(
      tester.element(find.byKey(const ValueKey('settings-scroll'))),
    );
    // Item 3: Settings now uses exactly the same route type as Objects and
    // Kept — a plain `MaterialPageRoute`, not a custom directional route.
    expect(settingsRoute, isA<MaterialPageRoute>());
    // The route's own transitionDuration is exactly what was just used to
    // settle its push above — this is the canonical, single-sourced
    // production value (`MaterialPageRoute`'s own default), not a value
    // re-declared in the test.
    expect(settingsRoute!.transitionDuration, settingsDuration);
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
    await tester.tap(find.byKey(const ValueKey('home-objects-control')));
    final objectsDuration = await _settleRoutePush(
      tester,
      find.byKey(const ValueKey('objects-screen-root')),
    );
    expect(pushObserver.pushCount, pushesBeforeObjects + 1);
    final objectsRoute = ModalRoute.of(
      tester.element(find.byKey(const ValueKey('objects-screen-root'))),
    );
    expect(objectsRoute, isA<MaterialPageRoute>());
    await tester.tap(find.byTooltip('Back'));
    await _settleRoutePop(
      tester,
      objectsDuration,
      poppedRouteFinder: find.byKey(const ValueKey('objects-screen-root')),
    );
    expect(find.byKey(const ValueKey('top-navigation')), findsOneWidget);

    expect(_homeNavigationInProgress(tester), isFalse);
    final pushesBeforeKept = pushObserver.pushCount;
    await tester.tap(find.byKey(const ValueKey('home-kept-control')));
    final keptDuration = await _settleRoutePush(
      tester,
      find.byKey(const ValueKey('kept-screen-root')),
    );
    expect(pushObserver.pushCount, pushesBeforeKept + 1);
    final keptRoute = ModalRoute.of(
      tester.element(find.byKey(const ValueKey('kept-screen-root'))),
    );
    expect(keptRoute, isA<MaterialPageRoute>());
    expect(keptDuration, keptRoute!.transitionDuration);

    // Settings, Objects, and Kept all resolve to the exact same
    // `MaterialPageRoute` forward transition duration — checked by direct
    // cross-comparison rather than an assumed absolute value, since the
    // underlying default is Flutter's own and not something this app
    // re-declares anywhere.
    expect(
      objectsDuration,
      settingsDuration,
      reason: 'Objects must use the same route transition duration as '
          'Settings.',
    );
    expect(
      keptDuration,
      settingsDuration,
      reason: 'Kept must use the same route transition duration as '
          'Settings.',
    );
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
    expect(find.byKey(const ValueKey('home-settings-control')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-objects-control')), findsOneWidget);
    // The ring icons are drawn geometrically (CustomPaint), not from text
    // glyphs, so a 3x text scale cannot distort or overflow them.
    final objectsPainterAt3x =
        _topNavRingPainterByKey(tester, 'objects-top-nav-ring');
    expect(objectsPainterAt3x.ringCount, 1);
    expect(find.byKey(const ValueKey('home-kept-control')), findsOneWidget);
    final keptPainterAt3x =
        _topNavRingPainterByKey(tester, 'kept-top-nav-ring');
    expect(keptPainterAt3x.ringCount, 2);
    // All three top-navigation controls share the same tap-target size so
    // the restrained hamburger control balances visually with the circles.
    expect(
      tester.getSize(find.byKey(const ValueKey('home-objects-control'))),
      tester.getSize(find.byKey(const ValueKey('home-kept-control'))),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('home-settings-control'))),
      tester.getSize(find.byKey(const ValueKey('home-kept-control'))),
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
    expect(find.byKey(const ValueKey('home-settings-control')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-objects-control')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-kept-control')), findsOneWidget);
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
    expect(find.byKey(const ValueKey('home-settings-control')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-objects-control')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-kept-control')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byKey(const ValueKey('black-silence')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-settings-control')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-objects-control')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-kept-control')), findsOneWidget);
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
    expect(find.byKey(const ValueKey('home-save-control-unsaved')),
        findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-save-control-unsaved')),
        matching: find.text('○'),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('home-save-control-unsaved')),
              matching: find.text('○'),
            ),
          )
          .style
          ?.fontSize,
      31,
    );

    await tester.tap(find.byKey(const ValueKey('home-save-control-unsaved')));
    await tester.pump();
    expect(
        find.byKey(const ValueKey('home-save-control-kept')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-save-control-kept')),
        matching: find.text('●'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    // Update 1D: by this point in the test the discovery hint has already
    // been visible for well over a second, so this save is also the one
    // that completes discovery — which now schedules the ~6.3s top-right
    // teaching-breath Timer chain (irrelevant to this test's own route-push
    // assertions above). Dispose the widget tree here so `dispose()`
    // cancels that chain cleanly, rather than leaving it pending at test
    // teardown.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
      'Home startup backfills a Build 25 record without changing text, '
      'revealedAt, unlockAt, or the rolling lock', (tester) async {
    final now = DateTime.utc(2041, 7, 23, 8);
    const wisdom = 'A Build 25 wisdom awaiting backfill on this launch.';
    final legacyRecord = DailyWisdomRecord(
      text: wisdom,
      revealedAt: now,
      unlockAt: now.add(const Duration(hours: 24)),
    );
    final dailyGraph = DailyAccessTestGraph(clock: () => now);
    SharedPreferences.setMockInitialValues({
      DailyAccessRepository.dailyWisdomAccessKey: legacyRecord.encode(),
    });

    await tester.pumpWidget(
      _homeApp(dailyGraph: dailyGraph, clock: () => now),
    );
    await _finishOpeningIntro(tester);

    final backfilled = await dailyGraph.repository.loadDailyWisdomRecord();

    expect(backfilled, isNotNull);
    expect(backfilled!.revealId, isNotNull);
    expect(backfilled.text, legacyRecord.text);
    expect(
      backfilled.revealedAt.millisecondsSinceEpoch,
      legacyRecord.revealedAt.millisecondsSinceEpoch,
    );
    expect(
      backfilled.unlockAt.millisecondsSinceEpoch,
      legacyRecord.unlockAt.millisecondsSinceEpoch,
    );
    expect(
      backfilled.unlockAt.difference(backfilled.revealedAt),
      DailyWisdomRecord.lockDuration,
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
    // A Build 26 record with a revealId already present, so startup's
    // backfillRevealIdIfNeeded() is a no-op and the persisted JSON below
    // cannot change out from under this test's exact-state assertion. A
    // Build 25 record without revealId would be backfilled during
    // loadInitialState(), which is correct product behavior but would race
    // this test's own expectations rather than testing sharing.
    const fixedRevealId = '123e4567-e89b-42d3-a456-426614174000';
    final record = DailyWisdomRecord(
      text: wisdom,
      revealedAt: now,
      unlockAt: now.add(const Duration(hours: 24)),
      revealId: fixedRevealId,
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
    final keptGraph = KeptRepositoryTestGraph();

    await tester.pumpWidget(
      _homeApp(keptGraph: keptGraph),
    );
    await _finishOpeningIntro(tester);
    await _openExistingWisdom(tester);
    await tester.pump();

    final save = find.byKey(const ValueKey('home-save-control-unsaved'));
    expect(save, findsOneWidget);
    expect(_keptGuard(tester).ignoring, isFalse);
    final saveButton = tester.widget<IconButton>(save);
    saveButton.onPressed!();
    saveButton.onPressed!();
    await tester.pump(const Duration(milliseconds: 20));

    final persisted = await keptGraph.service.load();
    expect(persisted, hasLength(1));
    expect(persisted.single.text, wisdom);
    expect(
        find.byKey(const ValueKey('home-save-control-kept')), findsOneWidget);
  });

  testWidgets(
      'the Kept save control renders no grey background, overlay, or splash '
      'in any interaction state, while its one-way save and tap target are '
      'unaffected', (tester) async {
    final now = DateTime.now();
    const wisdom = 'A wisdom used to verify the save control has no halo';
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': DailyWisdomRecord(
        text: wisdom,
        revealedAt: now,
        unlockAt: now.add(const Duration(hours: 24)),
      ).encode(),
    });
    final keptGraph = KeptRepositoryTestGraph();

    await tester.pumpWidget(_homeApp(keptGraph: keptGraph));
    await _finishOpeningIntro(tester);
    await _openExistingWisdom(tester);
    await tester.pump();

    final unsavedButton = tester.widget<IconButton>(
      find.byKey(const ValueKey('home-save-control-unsaved')),
    );
    final unsavedStyle = unsavedButton.style;
    expect(unsavedStyle, isNotNull);
    for (final states in [
      <WidgetState>{},
      {WidgetState.hovered},
      {WidgetState.focused},
      {WidgetState.pressed},
    ]) {
      // The behavioral contract is "no non-transparent background/overlay
      // is ever painted" — a resolved `null` (no color property set for
      // this state at all, so nothing is painted) satisfies that exactly
      // as well as an explicit `Colors.transparent` does. Requiring the
      // literal `Colors.transparent` value regardless of `null` is what
      // failed on the Mac run for at least one state.
      expect(
        unsavedStyle!.backgroundColor?.resolve(states),
        anyOf(isNull, Colors.transparent),
      );
      expect(
        unsavedStyle.overlayColor?.resolve(states),
        anyOf(isNull, Colors.transparent),
      );
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-save-control-unsaved')),
        matching: find.text('○'),
      ),
      findsOneWidget,
    );
    final unsavedSize =
        tester.getSize(find.byKey(const ValueKey('home-save-control-unsaved')));

    await tester.tap(find.byKey(const ValueKey('home-save-control-unsaved')));
    await tester.pump();

    expect(
        find.byKey(const ValueKey('home-save-control-kept')), findsOneWidget);
    expect(
      (await keptGraph.service.load()).single.text,
      wisdom,
    );

    // Correction pass (2nd revision): the kept state is a dedicated no-op
    // `GestureDetector` wrapping a *disabled* (`onPressed: null`) IconButton
    // built from the exact same style as the unsaved button — reusing the
    // same construction (rather than a hand-picked size) so the tap-target
    // geometry matches by construction. The disabled IconButton still
    // carries the transparent background/overlay style, so no grey halo is
    // introduced, and having `onPressed: null` means it contributes no tap
    // recognizer of its own — the wrapping GestureDetector is the only
    // functioning recognizer at this position.
    final savedRing = tester.widget<GestureDetector>(
      find.byKey(const ValueKey('home-save-control-kept')),
    );
    expect(savedRing.behavior, HitTestBehavior.opaque);
    expect(savedRing.excludeFromSemantics, isTrue);
    expect(savedRing.onTap, isNotNull);

    final savedButton = tester.widget<IconButton>(
      find.descendant(
        of: find.byKey(const ValueKey('home-save-control-kept')),
        matching: find.byType(IconButton),
      ),
    );
    expect(
      savedButton.onPressed,
      isNull,
      reason: 'Disabled so it contributes no recognizer of its own; the '
          'wrapping GestureDetector is what actually claims the tap.',
    );
    final savedStyle = savedButton.style;
    expect(savedStyle, isNotNull);
    for (final states in [
      <WidgetState>{},
      {WidgetState.hovered},
      {WidgetState.focused},
      {WidgetState.pressed},
      // The disabled state specifically: this button is always disabled
      // (`onPressed: null`) once kept, so this is the one that actually
      // matters for what gets painted.
      {WidgetState.disabled},
    ]) {
      // Same contract as the unsaved loop above: `null` (nothing painted)
      // and `Colors.transparent` (explicitly painted transparent) are both
      // acceptable — only a non-transparent, non-null color would violate
      // "no grey background/overlay".
      expect(
        savedStyle!.backgroundColor?.resolve(states),
        anyOf(isNull, Colors.transparent),
      );
      expect(
        savedStyle.overlayColor?.resolve(states),
        anyOf(isNull, Colors.transparent),
      );
    }
    // Correction: the disabled kept-state IconButton must not resolve its
    // own `IconTheme` foreground color to `ThemeData.disabledColor` (a
    // dimmed grey) — it must resolve to the same intended kept-ring token
    // the glyph itself already hardcodes.
    const keptRingColor = Color(0xFFF4F0E8);
    final savedForegroundColor = savedStyle!.foregroundColor;
    expect(savedForegroundColor, isNotNull);
    final resolvedSavedForegroundColor = savedForegroundColor!;
    expect(
      resolvedSavedForegroundColor.resolve(<WidgetState>{}),
      keptRingColor,
    );
    expect(
      resolvedSavedForegroundColor.resolve(
        <WidgetState>{WidgetState.disabled},
      ),
      keptRingColor,
    );
    // The definitive proof, independent of `IconTheme` resolution entirely:
    // the actual rendered glyph is a `Text` with its own explicit color, so
    // this is what a user actually sees regardless of IconButton's own
    // disabled-state theming.
    final savedGlyph = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('home-save-control-kept')),
        matching: find.text('●'),
      ),
    );
    expect(savedGlyph.style?.color, keptRingColor);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-save-control-kept')),
        matching: find.text('●'),
      ),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('home-save-control-kept'))),
      unsavedSize,
      reason: 'The kept-state GestureDetector wraps the exact same '
          'IconButton construction as the unsaved state, so its rendered '
          'size matches by construction rather than by an assumed pixel '
          'value.',
    );

    // Item 4: the save ring is one-way. Tapping the already-filled ring
    // must do nothing — no removal, no toggle-off, ring remains filled.
    await tester.tap(find.byKey(const ValueKey('home-save-control-kept')));
    await tester.pump();
    expect(
        find.byKey(const ValueKey('home-save-control-kept')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('home-save-control-unsaved')), findsNothing);
    expect(
      (await keptGraph.service.load()).single.text,
      wisdom,
    );
  });

  testWidgets(
      'Correction: the kept save ring exposes exactly one semantics node '
      '(no duplicate leaked from the disabled inner IconButton), with no '
      'button flag, no tap action, and no remove action', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final now = DateTime.now();
      const wisdom = 'A wisdom used to verify no duplicate kept semantics';
      SharedPreferences.setMockInitialValues({
        'daily_wisdom_access': DailyWisdomRecord(
          text: wisdom,
          revealedAt: now,
          unlockAt: now.add(const Duration(hours: 24)),
          revealId: _fixedRevealId,
        ).encode(),
      });
      final keptGraph = KeptRepositoryTestGraph()
        ..seed([
          _testKeptRecord(
            id: 'already-kept-for-semantics-isolation-test',
            revealId: _fixedRevealId,
            wisdomText: wisdom,
            revealedAt: now,
          ),
        ]);

      await tester.pumpWidget(_homeApp(keptGraph: keptGraph));
      await _finishOpeningIntro(tester);
      await _openExistingWisdom(tester);
      await tester.pump();

      // Direct proof that `GestureDetector.excludeFromSemantics` (which
      // only excludes the GestureDetector's own gesture semantics) plus the
      // surrounding `ExcludeSemantics` (which excludes the whole ring
      // subtree, including the disabled inner `IconButton`'s own
      // semantics) leaves exactly one meaningful node for this label — not
      // a second, duplicate node contributed by the disabled IconButton.
      final keptLabelMatches = find.semantics.byLabel('Kept').evaluate();
      expect(
        keptLabelMatches,
        hasLength(1),
        reason: 'Exactly one "Kept" semantics node must exist — the '
            'disabled inner IconButton must not contribute a second, '
            'duplicate node.',
      );
      final keptLabelData = keptLabelMatches.single.getSemanticsData();
      expect(keptLabelData.flagsCollection.isButton, isFalse);
      expect(keptLabelData.hasAction(SemanticsAction.tap), isFalse);
      // Deliberately not asserted: `flagsCollection.isEnabled`. A bare,
      // non-interactive semantics label with no `button`/`enabled` state of
      // its own reports "none" (`Tristate.mixed`) here, not `false` —
      // requiring `false` would over-constrain a node that simply has no
      // enabled/disabled concept to begin with.

      final keptNode = tester.getSemantics(
        find.byKey(const ValueKey('home-save-control-kept')),
      );
      expect(keptNode.value, 'Kept');
      // `SemanticsNode.hint` is a non-null `String` in this Flutter
      // version (a `null` `Semantics.hint` normalizes to `''` by the time
      // it reaches here) — assert the behavioral contract directly rather
      // than through a now-redundant `?? ''` null-aware expression.
      expect(keptNode.hint, isEmpty);
      expect(
        keptNode.getSemanticsData().hasAction(SemanticsAction.tap),
        isFalse,
      );
      expect(
        keptNode.getSemanticsData().hasAction(SemanticsAction.dismiss),
        isFalse,
        reason: 'No remove action may ever be exposed on Home.',
      );
      expect(
        keptNode.getSemanticsData().customSemanticsActionIds,
        isEmpty,
        reason: 'No custom "remove" (or any other) action is exposed.',
      );
    } finally {
      semantics.dispose();
    }
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
                dailyWisdomAccessService: DailyAccessTestGraph().service,
                // Correction: this test constructs `HomeScreen` directly
                // rather than through `_homeApp()` (which always supplies
                // this). Without an explicit `savedReflectionsService`,
                // `initState` falls back to
                // `app_services.savedReflectionsService` — a `late final`
                // global only ever populated by production's
                // `initializeKeptStorage()` before `runApp()`, which this
                // isolated widget test never runs. A fresh, test-local
                // `KeptRepositoryTestGraph` (in-memory store only — no
                // Application Support directory, no native file
                // protection, no production global touched) avoids that
                // uninitialized access entirely.
                savedReflectionsService: KeptRepositoryTestGraph().service,
              ),
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

  // Correction: the `Tooltip`/`RawTooltip` wrapper has been removed entirely
  // from `_HomeSettingsMenuControl` and `_HomeTopNavigation` — it was never
  // the real hit-testable control, and `find.byTooltip(...)` no longer
  // resolves to anything for these three controls. Each control now carries
  // its own stable key directly on the actual hit-testable `IconButton`
  // (`home-settings-control`, `home-objects-control`, `home-kept-control`),
  // and this data table drives one loop iteration per control, each against
  // its own fresh Home instance so a destination-tap check for one control
  // can never leak navigation state into the next control's checks.
  const topNavControls = [
    (
      key: 'home-settings-control',
      overlayLabel: 'Settings',
      semanticsLabel: 'Settings',
      semanticsHint: null,
      destinationKey: 'settings-scroll',
    ),
    (
      key: 'home-objects-control',
      overlayLabel: 'Objects',
      semanticsLabel: 'Objects',
      semanticsHint: null,
      destinationKey: 'objects-screen-root',
    ),
    (
      key: 'home-kept-control',
      overlayLabel: 'Kept',
      semanticsLabel: 'Kept wisdoms',
      semanticsHint: 'Double tap to view wisdoms you have kept',
      destinationKey: 'kept-screen-root',
    ),
  ];

  for (final control in topNavControls) {
    testWidgets(
        'Build 25 Item 2 correction: "${control.semanticsLabel}" never '
        'shows a long-press tooltip/label overlay, and its explicit '
        'Semantics and normal tap are intact', (tester) async {
      final now = DateTime.now();
      const wisdom = 'A wisdom used to verify tooltip suppression';
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

      final controlFinder = find.byKey(ValueKey(control.key));
      expect(controlFinder, findsOneWidget);

      // Correction: verify the behavioral contract directly (a real
      // long-press produces no visible overlay) instead of finding or
      // casting any tooltip widget — there is none. None of these three
      // controls have any other on-screen `Text` reading "Settings" /
      // "Objects" / "Kept" at this point (they are icon-only), so
      // `find.text(...)` finding nothing, before and well past the former
      // tooltip show delay, is a direct behavioral proof no overlay ever
      // appears.
      expect(find.text(control.overlayLabel), findsNothing);
      await tester.longPress(controlFinder);
      await tester.pump(const Duration(seconds: 2));
      expect(
        find.text(control.overlayLabel),
        findsNothing,
        reason: '"${control.semanticsLabel}" must never show a visible '
            'tooltip/label overlay on long-press.',
      );
      expect(tester.takeException(), isNull);

      // Correction pass Item 5: each control exposes an explicit, stable
      // Semantics node — accessibility never depended on `Tooltip.message`
      // and continues not to now that `Tooltip` is gone.
      final semantics = tester.ensureSemantics();

      // Exactly one meaningful semantics node carries this control's
      // label — proves the wrapping `GestureDetector` (added to absorb a
      // no-op long-press) never contributes a second, separate node.
      expect(
        find.semantics.byLabel(control.semanticsLabel),
        findsOneWidget,
        reason: '"${control.semanticsLabel}" must expose exactly one '
            'meaningful semantics node.',
      );

      final node = tester.getSemantics(controlFinder);
      expect(node.label, control.semanticsLabel);
      if (control.semanticsHint != null) {
        expect(node.hint, control.semanticsHint);
      }
      final nodeData = node.getSemanticsData();
      expect(nodeData.hasAction(SemanticsAction.tap), isTrue);
      // Correction: the outer `GestureDetector`'s no-op `onLongPress` must
      // not leak its own `longPress` semantics action onto this node —
      // `excludeFromSemantics: true` on that `GestureDetector` is what
      // keeps the explicit `Semantics` above as the sole accessibility
      // source of truth.
      expect(
        nodeData.hasAction(SemanticsAction.longPress),
        isFalse,
        reason: '"${control.semanticsLabel}" must not expose a longPress '
            'semantics action — the no-op long-press absorber is purely a '
            'physical hit-test guard, not an accessibility action.',
      );

      // The control's own `IconButton` remains wrapped in `ExcludeSemantics`
      // so its implicit semantics never leak past the explicit `Semantics`
      // node above — this is independent of, and unaffected by, the
      // `Tooltip` removal.
      final excludeSemantics = tester
          .element(controlFinder)
          .findAncestorWidgetOfExactType<ExcludeSemantics>();
      expect(
        excludeSemantics,
        isNotNull,
        reason: '"${control.semanticsLabel}" control must be wrapped in '
            'ExcludeSemantics so its own implicit semantics never leak.',
      );
      semantics.dispose();

      // A long press must be a complete no-op for navigation: still on
      // Home, no destination mounted, no guard left engaged, no
      // exception — not merely "no visible overlay" (already proven
      // above).
      expect(find.byKey(ValueKey(control.destinationKey)), findsNothing);
      expect(_homeNavigationInProgress(tester), isFalse);
      expect(find.byKey(const ValueKey('top-navigation')), findsOneWidget);

      // A normal tap right after the long press does navigate to the
      // correct destination — the long press left the control's own
      // onPressed entirely untouched.
      await tester.tap(controlFinder);
      await _settleRoutePush(
        tester,
        find.byKey(ValueKey(control.destinationKey)),
      );
      expect(find.byKey(ValueKey(control.destinationKey)), findsOneWidget);
    });
  }

  testWidgets('Build 25 Item 5: swiping left on a revealed wisdom opens Kept',
      (tester) async {
    final now = DateTime.now();
    const wisdom = 'A wisdom used to verify the Home left-swipe gesture';
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

    await tester.drag(
      find.byKey(const ValueKey('home-ritual-gesture-surface')),
      const Offset(-140, 0),
    );
    await _settleRoutePush(
      tester,
      find.byKey(const ValueKey('kept-screen-root')),
    );

    expect(find.byKey(const ValueKey('kept-screen-root')), findsOneWidget);
  });

  testWidgets(
      'Build 25 Item 5: the left-swipe gesture is a no-op during Pause, '
      'Feel, and Ask from your heart', (tester) async {
    await tester.pumpWidget(
      _homeApp(dailyGraph: DailyAccessTestGraph()),
    );
    await _finishOpeningIntro(tester);
    await _advanceFromLaunchToPause(tester);

    // Pause/Feel. Dragging the actual hit-testable ritual gesture surface
    // (not the `AnimatedOpacity` it lives inside) — this is the same
    // `home-ritual-gesture-surface` key used by every other swipe test in
    // this file, and is what makes `HitTestBehavior.opaque` on that
    // `GestureDetector` meaningful to prove: even opaque, the surface's own
    // `onPanStart`/`onPanUpdate`/`onPanEnd` remain gated on
    // `swipeToKeptEnabled`, so the drag below must still be a no-op before
    // reveal.
    await tester.drag(
      find.byKey(const ValueKey('home-ritual-gesture-surface')),
      const Offset(-140, 0),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('kept-screen-root')), findsNothing);
    expect(_homeNavigationInProgress(tester), isFalse);

    // Ask from your heart.
    await _tapCenter(tester);
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.drag(
      find.byKey(const ValueKey('home-ritual-gesture-surface')),
      const Offset(-140, 0),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('kept-screen-root')), findsNothing);
    expect(_homeNavigationInProgress(tester), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Build 25 Item 4: the save ring exposes distinct unsaved/kept '
      'semantics, with no remove action ever exposed once kept',
      (tester) async {
    final now = DateTime.now();
    const wisdom = 'A wisdom used to verify one-way save semantics';
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

    final semantics = tester.ensureSemantics();
    final unsavedNode = tester.getSemantics(
      find.byKey(const ValueKey('home-save-control-unsaved')),
    );
    expect(unsavedNode.label, 'Keep this wisdom');
    expect(unsavedNode.value, 'Not kept');
    expect(unsavedNode.hint, 'Double tap to keep this wisdom');
    expect(
        unsavedNode.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    semantics.dispose();

    await tester.tap(find.byKey(const ValueKey('home-save-control-unsaved')));
    await tester.pump(const Duration(milliseconds: 50));

    final semanticsAfterSave = tester.ensureSemantics();
    final keptNode = tester.getSemantics(
      find.byKey(const ValueKey('home-save-control-kept')),
    );
    expect(keptNode.label, 'Kept');
    expect(keptNode.value, 'Kept');
    // `SemanticsNode.hint` is a non-null `String` in this Flutter version
    // (a `null` `Semantics.hint` normalizes to `''` by the time it reaches
    // here) — assert the behavioral contract directly rather than through
    // a now-redundant `?? ''` null-aware expression.
    expect(keptNode.hint, isEmpty);
    expect(
      keptNode.getSemanticsData().hasAction(SemanticsAction.tap),
      isFalse,
      reason: 'Once kept, no remove action may be exposed on Home.',
    );
    semanticsAfterSave.dispose();
  });

  testWidgets(
      'Discovery test isolation: an independently constructed '
      'KeptDiscoveryHintService never observes another instance\'s '
      'in-memory completed/count state, regardless of test execution order',
      (tester) async {
    // Part 1: drive an environment to actually complete discovery, using
    // its own fresh service (exactly what `_homeApp()` now does by
    // default) and its own fresh, empty `SharedPreferences` store.
    final now = DateTime.now();
    const firstWisdom = 'A wisdom used to complete discovery in part 1';
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': DailyWisdomRecord(
        text: firstWisdom,
        revealedAt: now,
        unlockAt: now.add(const Duration(hours: 24)),
      ).encode(),
    });
    final serviceA = KeptDiscoveryHintService();

    await tester.pumpWidget(_homeApp(keptDiscoveryHintService: serviceA));
    await _finishOpeningIntro(tester);
    await _openExistingWisdom(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.tap(find.byKey(const ValueKey('home-save-control-unsaved')));
    await tester.pump(const Duration(milliseconds: 50));

    expect(await serviceA.isCompleted(), isTrue);
    expect(await serviceA.displayCount(), 1);

    // Part 2: a brand-new environment, in the same test (so this proves
    // the contract deterministically rather than depending on whichever
    // order the test runner happens to execute files/tests in) — a fresh
    // `SharedPreferences` store *and* a second, independently constructed
    // `KeptDiscoveryHintService` instance. If in-memory state ever leaked
    // between instances (as it previously did when tests fell back to the
    // shared `app_services.keptDiscoveryHintService` process-wide
    // singleton), this would incorrectly see `isCompleted() == true` and
    // `displayCount() == 1` carried over from Part 1 above.
    SharedPreferences.setMockInitialValues({});
    final serviceB = KeptDiscoveryHintService();

    expect(
      await serviceB.isCompleted(),
      isFalse,
      reason: 'A fresh KeptDiscoveryHintService instance must never '
          'observe another instance\'s completed state.',
    );
    expect(
      await serviceB.displayCount(),
      0,
      reason: 'A fresh KeptDiscoveryHintService instance must never '
          'observe another instance\'s display count.',
    );
    expect(await serviceB.isEligible(), isTrue);

    // And a fresh `_homeApp()` environment (the actual mechanism every
    // other discovery test in this file relies on) independently confirms
    // the hint is offerable again from a clean slate.
    const secondWisdom = 'A wisdom used to verify part 2 starts fresh';
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': DailyWisdomRecord(
        text: secondWisdom,
        revealedAt: now,
        unlockAt: now.add(const Duration(hours: 24)),
      ).encode(),
    });

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(_homeApp(keptDiscoveryHintService: serviceB));
    await _finishOpeningIntro(tester);
    await _openExistingWisdom(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1100));

    expect(
      find.text('Keep this wisdom.'),
      findsOneWidget,
      reason: 'A fresh environment must still be able to offer the '
          'discovery hint — it must not inherit completion from the '
          'unrelated environment in Part 1.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Build 25 Item 6 (Update 1): the Save -> Kept discovery hint shows '
      'once for 7.5s with 4 center breaths, transitions to "Kept." for '
      '~1.3s on a successful save, runs exactly 5 top-right Kept teaching '
      'breaths starting ~350ms after that first completing save, and marks '
      'the discovery permanently complete', (tester) async {
    final now = DateTime.now();
    const wisdom = 'A wisdom used to verify the Kept discovery hint';
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': DailyWisdomRecord(
        text: wisdom,
        revealedAt: now,
        unlockAt: now.add(const Duration(hours: 24)),
      ).encode(),
    });
    final keptGraph = KeptRepositoryTestGraph();

    await tester.pumpWidget(_homeApp(keptGraph: keptGraph));
    await _finishOpeningIntro(tester);
    await _openExistingWisdom(tester);
    await tester.pump();
    expect(_keptGuard(tester).ignoring, isFalse);

    // The hint's own internal ~1000ms delay after the save ring settles.
    await tester.pump(const Duration(milliseconds: 1100));

    expect(find.text('Keep this wisdom.'), findsOneWidget);

    // Update 1B: the first of 4 center save-ring breaths begins ~250ms
    // after the text above just appeared.
    await _pumpInSteps(tester, const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('save-ring-breath')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-save-control-unsaved')));
    await tester.pump(const Duration(milliseconds: 50));

    // Update 1A/C: saving interrupts the remaining discovery hint duration
    // immediately — the center breath stops, and text transitions straight
    // to "Kept.".
    expect(find.text('Kept.'), findsOneWidget);
    expect(find.text('Keep this wisdom.'), findsNothing);
    expect(find.byKey(const ValueKey('save-ring-breath')), findsNothing);
    expect(
      (await keptGraph.service.load()).single.text,
      wisdom,
    );

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(KeptDiscoveryHintService.completedKey), isTrue);

    // Update 1D: this save is the first to complete discovery, so exactly
    // 5 top-right Kept teaching breaths must run, starting ~350ms from now
    // — counted here as the number of absent->present transitions of the
    // teaching-breath overlay over the whole ~5.9s emphasis window.
    // Total: 350ms start delay + 5 * 1050ms breaths + 4 * 165ms pauses =
    // 6260ms. Pumped well past that (6500ms) so the 5th breath's own end is
    // definitely captured before the loop finishes.
    const emphasisKey = ValueKey('kept-icon-emphasis-pulse');
    var breathStarts = 0;
    var wasPresent = false;
    for (var elapsed = 0; elapsed < 6500; elapsed += 50) {
      await tester.pump(const Duration(milliseconds: 50));
      final isPresent = find.byKey(emphasisKey).evaluate().isNotEmpty;
      if (isPresent && !wasPresent) breathStarts++;
      wasPresent = isPresent;
    }
    expect(
      breathStarts,
      5,
      reason: 'The top-right Kept teaching emphasis must run exactly 5 '
          'breaths on the first save that completes discovery.',
    );
    expect(
      find.byKey(emphasisKey),
      findsNothing,
      reason: 'The teaching emphasis must have fully finished well within '
          'the ~5.8-6.2s total window.',
    );

    // "Kept." itself faded on its own independent ~1.3s timer, well before
    // the teaching-emphasis loop above finished.
    expect(find.text('Kept.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Correction pass Item 1: a successful save before the discovery hint '
      'ever appears still permanently completes discovery, with no "Kept." '
      'text, no display-count increment, and the top-right Kept teaching '
      'breath still runs exactly once for this incomplete -> completed '
      'transition', (tester) async {
    final now = DateTime.now();
    const wisdom = 'A wisdom used to verify completion before the hint appears';
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': DailyWisdomRecord(
        text: wisdom,
        revealedAt: now,
        unlockAt: now.add(const Duration(hours: 24)),
      ).encode(),
    });
    final keptGraph = KeptRepositoryTestGraph();

    await tester.pumpWidget(_homeApp(keptGraph: keptGraph));
    await _finishOpeningIntro(tester);
    await _openExistingWisdom(tester);
    await tester.pump();
    expect(_keptGuard(tester).ignoring, isFalse);

    // Save immediately — well before the hint's own ~1000ms internal delay
    // has elapsed, so the hint has never become visible for this reveal.
    expect(find.text('Keep this wisdom.'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('home-save-control-unsaved')));
    await tester.pump(const Duration(milliseconds: 50));

    expect(
      (await keptGraph.service.load()).single.text,
      wisdom,
    );
    expect(find.text('Kept.'), findsNothing);
    expect(
        find.byKey(const ValueKey('home-save-control-kept')), findsOneWidget);

    final prefsRightAfterSave = await SharedPreferences.getInstance();
    expect(
      prefsRightAfterSave.getBool(KeptDiscoveryHintService.completedKey),
      isTrue,
      reason: 'Completion must be persisted immediately on a successful '
          'save even though the hint was never visible.',
    );

    // Let the originally-scheduled hint timer's window fully elapse: it
    // must never present now that discovery is already complete.
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.text('Keep this wisdom.'), findsNothing);
    expect(find.text('Kept.'), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(KeptDiscoveryHintService.hintCountKey) ?? 0, 0);

    // Correction: the top-right Kept teaching breath is gated only on
    // `justCompletedDiscovery`, never on `hintWasShowing` — this save is
    // the one that changed discovery from incomplete to completed, even
    // though the hint text itself never appeared, so the 5-breath teaching
    // sequence must still run once. Counted the same way as the "hint
    // visible" test above: absent->present transitions of the overlay over
    // the whole ~6.3s emphasis window (350ms start delay + 5 * 1050ms
    // breaths + 4 * 165ms pauses = 6260ms).
    const emphasisKey = ValueKey('kept-icon-emphasis-pulse');
    var breathStarts = 0;
    var wasPresent = false;
    for (var elapsed = 0; elapsed < 6500; elapsed += 50) {
      await tester.pump(const Duration(milliseconds: 50));
      final isPresent = find.byKey(emphasisKey).evaluate().isNotEmpty;
      if (isPresent && !wasPresent) breathStarts++;
      wasPresent = isPresent;
    }
    expect(
      breathStarts,
      5,
      reason: 'The top-right Kept teaching emphasis must run exactly 5 '
          'breaths for the first incomplete -> completed transition, even '
          'when the hint text was never visible for the completing save.',
    );
    expect(find.byKey(emphasisKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Build 25 Item 6: the discovery hint never appears once already '
      'completed, an ordinary save away from the hint stays silent, and '
      'the top-right Kept teaching breath does not run again for this '
      'later save', (tester) async {
    final now = DateTime.now();
    const wisdom = 'A wisdom used to verify the discovery hint is retired';
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': DailyWisdomRecord(
        text: wisdom,
        revealedAt: now,
        unlockAt: now.add(const Duration(hours: 24)),
      ).encode(),
      KeptDiscoveryHintService.completedKey: true,
    });
    final keptGraph = KeptRepositoryTestGraph();

    await tester.pumpWidget(_homeApp(keptGraph: keptGraph));
    await _finishOpeningIntro(tester);
    await _openExistingWisdom(tester);
    await tester.pump();
    expect(_keptGuard(tester).ignoring, isFalse);

    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.text('Keep this wisdom.'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('home-save-control-unsaved')));
    await tester.pump(const Duration(milliseconds: 50));

    // A save that happens with no hint showing must stay silent: no
    // "Kept." text appears even though the save itself still succeeds.
    expect(find.text('Kept.'), findsNothing);
    expect(
        find.byKey(const ValueKey('home-save-control-kept')), findsOneWidget);
    expect(
      (await keptGraph.service.load()).single.text,
      wisdom,
    );

    // Test 3 (requested correction): discovery was already completed
    // *before* this save (`completedKey: true` seeded above), so this is
    // not the incomplete -> completed transition — the top-right Kept
    // teaching breath must never run for it. Pumped well past the ~6.3s
    // window the teaching sequence would occupy if it (incorrectly) ran.
    await _pumpInSteps(tester, const Duration(milliseconds: 6500));
    expect(
      find.byKey(const ValueKey('kept-icon-emphasis-pulse')),
      findsNothing,
      reason: 'The top-right Kept teaching breath must not run again once '
          'discovery was already completed before this save.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Correction pass Item 4 correction: a granted native permission '
      'prompt whose Future is left genuinely pending blocks the discovery '
      'hint until it resolves, then schedules once and shows the hint '
      '~800-1200ms later, never twice', (tester) async {
    final now = DateTime.utc(2041, 7, 23, 8);
    final dailyGraph = DailyAccessTestGraph(clock: () => now);
    // A controllable `Completer`, not a mock that resolves immediately —
    // this is what lets this test actually model a real native dialog: the
    // permission Future stays pending until this test explicitly completes
    // it below, so every "request is still in flight" assertion here is
    // proving real intermediate behavior rather than racing an
    // already-resolved value.
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

    // PHASE A — unresolved native prompt Future: `permissionGate` has not
    // been completed at all yet at this point. A real Mac run confirmed
    // that, with the corrected `home_screen.dart` flag lifecycle (the
    // scheduled/showing guards no longer have a gap between them), the
    // native permission request has already fired exactly once by this
    // checkpoint — it no longer waits for a further pump past this delay.
    // A separate, still-guarded-against regression is the discovery hint
    // itself appearing this early: that must remain impossible for as
    // long as the prompt stays genuinely unresolved.
    await _pumpInSteps(tester, const Duration(milliseconds: 6900));
    expect(
      notificationPlatform.permissionRequests,
      1,
      reason:
          'PHASE A (gate unresolved): exactly one native permission request must be pending.',
    );
    expect(
      permissionGate.isCompleted,
      isFalse,
      reason:
          'PHASE A (gate unresolved): the native permission request must still be awaiting its result.',
    );
    expect(
      find.text('Keep this wisdom.'),
      findsNothing,
      reason: 'PHASE A (gate unresolved): hint must be absent.',
    );
    expect(
      await _keptDiscoveryDisplayCount(),
      0,
      reason: 'PHASE A (gate unresolved): display count must still be 0.',
    );

    // Reconfirm the same PHASE A invariants a little further into the
    // still-pending wait: the request must not fire a second time, and the
    // Future must still be unresolved.
    await _pumpInSteps(tester, const Duration(milliseconds: 300));
    expect(
      notificationPlatform.permissionRequests,
      1,
      reason: 'PHASE A (gate unresolved): the native request must have '
          'fired exactly once by now.',
    );
    expect(
      permissionGate.isCompleted,
      isFalse,
      reason: 'PHASE A (gate unresolved): the permission Future must still '
          'be pending.',
    );

    // PHASE A continued — while the prompt is genuinely pending —
    // regardless of how long — nothing related to the discovery hint may
    // appear, and nothing is scheduled yet.
    await _pumpInSteps(tester, const Duration(seconds: 3));
    expect(
      find.text('Keep this wisdom.'),
      findsNothing,
      reason: 'PHASE A (gate unresolved): hint must still be absent no '
          'matter how long the prompt stays pending.',
    );
    expect(
      await _keptDiscoveryDisplayCount(),
      0,
      reason: 'PHASE A (gate unresolved): display count must still be 0.',
    );
    expect(
      notificationPlatform.schedules,
      isEmpty,
      reason: 'PHASE A (gate unresolved): nothing may be scheduled yet.',
    );

    // The user grants the permission. Pump microtasks so the completion
    // actually propagates through the awaiting service/screen code. This
    // marks the boundary into PHASE B.
    permissionGate.complete(true);
    await tester.pump();

    // PHASE B — resolved, before the ~800ms discovery delay: the hint must
    // still be absent, and the earlier single native request must not be
    // repeated.
    await _pumpInSteps(tester, const Duration(milliseconds: 799));
    expect(
      notificationPlatform.permissionRequests,
      1,
      reason: 'PHASE B (resolved, <800ms): the native request count must '
          'remain exactly 1.',
    );
    expect(
      find.text('Keep this wisdom.'),
      findsNothing,
      reason: 'PHASE B (resolved, <800ms): hint must still be absent.',
    );
    expect(
      await _keptDiscoveryDisplayCount(),
      0,
      reason: 'PHASE B (resolved, <800ms): display count must still be 0.',
    );

    // PHASE C — resolved, ~800-1200ms: the hint appears exactly once, and
    // the schedule was written exactly once.
    await _pumpInSteps(tester, const Duration(milliseconds: 300));
    expect(
      notificationPlatform.permissionRequests,
      1,
      reason: 'PHASE C (resolved, ~800-1200ms): the native request count '
          'must remain exactly 1.',
    );
    expect(
      find.text('Keep this wisdom.'),
      findsOneWidget,
      reason: 'PHASE C (resolved, ~800-1200ms): hint must now be visible.',
    );
    expect(
      await _keptDiscoveryDisplayCount(),
      1,
      reason: 'PHASE C (resolved, ~800-1200ms): display count must become 1.',
    );
    expect(
      notificationPlatform.schedules,
      hasLength(1),
      reason: 'PHASE C (resolved, ~800-1200ms): the granted permission must '
          'have written exactly one schedule.',
    );

    // No duplicate presentation past PHASE C.
    await _pumpInSteps(tester, const Duration(milliseconds: 500));
    expect(
      find.text('Keep this wisdom.'),
      findsOneWidget,
      reason: 'PHASE C (resolved, past 1200ms): hint must not disappear or '
          'duplicate.',
    );
    expect(
      await _keptDiscoveryDisplayCount(),
      1,
      reason: 'PHASE C (resolved, past 1200ms): display count must not '
          'increment again — no duplicate presentation.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Correction pass Item 4 correction: a denied native permission '
      'prompt whose Future is left genuinely pending is nonfatal once '
      'resolved, and the discovery hint still appears afterward, never '
      'twice', (tester) async {
    final now = DateTime.utc(2041, 7, 23, 8);
    final dailyGraph = DailyAccessTestGraph(clock: () => now);
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

    // PHASE A — unresolved native prompt Future (see the matching, more
    // detailed note in the granted test above: with the corrected
    // `home_screen.dart` flag lifecycle, the native permission request has
    // already fired exactly once by this checkpoint).
    await _pumpInSteps(tester, const Duration(milliseconds: 6900));
    expect(
      notificationPlatform.permissionRequests,
      1,
      reason:
          'PHASE A (gate unresolved): exactly one native permission request must be pending.',
    );
    expect(
      permissionGate.isCompleted,
      isFalse,
      reason:
          'PHASE A (gate unresolved): the native permission request must still be awaiting its result.',
    );
    expect(
      find.text('Keep this wisdom.'),
      findsNothing,
      reason: 'PHASE A (gate unresolved): hint must be absent.',
    );
    expect(
      await _keptDiscoveryDisplayCount(),
      0,
      reason: 'PHASE A (gate unresolved): display count must still be 0.',
    );

    // Reconfirm the same PHASE A invariants a little further into the
    // still-pending wait: the request must not fire a second time, and the
    // Future must still be unresolved.
    await _pumpInSteps(tester, const Duration(milliseconds: 300));
    expect(
      notificationPlatform.permissionRequests,
      1,
      reason: 'PHASE A (gate unresolved): the native request must have '
          'fired exactly once by now.',
    );
    expect(
      permissionGate.isCompleted,
      isFalse,
      reason: 'PHASE A (gate unresolved): the permission Future must still '
          'be pending.',
    );

    // PHASE A continued.
    await _pumpInSteps(tester, const Duration(seconds: 3));
    expect(
      find.text('Keep this wisdom.'),
      findsNothing,
      reason: 'PHASE A (gate unresolved): hint must still be absent no '
          'matter how long the prompt stays pending.',
    );
    expect(
      await _keptDiscoveryDisplayCount(),
      0,
      reason: 'PHASE A (gate unresolved): display count must still be 0.',
    );
    expect(
      notificationPlatform.schedules,
      isEmpty,
      reason: 'PHASE A (gate unresolved): nothing may be scheduled yet.',
    );

    // The user denies the permission. Pump microtasks. This marks the
    // boundary into PHASE B.
    permissionGate.complete(false);
    await tester.pump();

    // PHASE B — resolved, before the ~800ms discovery delay: the hint must
    // still be absent, and the earlier single native request must not be
    // repeated.
    await _pumpInSteps(tester, const Duration(milliseconds: 799));
    expect(
      notificationPlatform.permissionRequests,
      1,
      reason: 'PHASE B (resolved, <800ms): the native request count must '
          'remain exactly 1.',
    );
    expect(
      find.text('Keep this wisdom.'),
      findsNothing,
      reason: 'PHASE B (resolved, <800ms): hint must still be absent.',
    );
    expect(
      await _keptDiscoveryDisplayCount(),
      0,
      reason: 'PHASE B (resolved, <800ms): display count must still be 0.',
    );

    // PHASE C — resolved, ~800-1200ms: the hint appears exactly once. A
    // denial is nonfatal and must never schedule a notification.
    await _pumpInSteps(tester, const Duration(milliseconds: 300));
    expect(
      notificationPlatform.permissionRequests,
      1,
      reason: 'PHASE C (resolved, ~800-1200ms): the native request count '
          'must remain exactly 1.',
    );
    expect(
      find.text('Keep this wisdom.'),
      findsOneWidget,
      reason: 'PHASE C (resolved, ~800-1200ms): hint must now be visible.',
    );
    expect(
      await _keptDiscoveryDisplayCount(),
      1,
      reason: 'PHASE C (resolved, ~800-1200ms): display count must become 1.',
    );
    expect(
      notificationPlatform.schedules,
      isEmpty,
      reason: 'PHASE C (resolved, ~800-1200ms): a denial must never write a '
          'schedule.',
    );

    // No duplicate presentation past PHASE C.
    await _pumpInSteps(tester, const Duration(milliseconds: 500));
    expect(
      find.text('Keep this wisdom.'),
      findsOneWidget,
      reason: 'PHASE C (resolved, past 1200ms): hint must not disappear or '
          'duplicate.',
    );
    expect(
      await _keptDiscoveryDisplayCount(),
      1,
      reason: 'PHASE C (resolved, past 1200ms): display count must not '
          'increment again — no duplicate presentation.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Correction pass Item 4 & 3: the notification-offer path and '
      "onFullyVisible's own call both reach _maybeOfferKeptDiscoveryHint "
      'for the same reveal, but only one presentation ever results',
      (tester) async {
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

    // Save control's own onFullyVisible fires well before the 7s native
    // trigger delay elapses, so both call paths are exercised for this one
    // reveal.
    await _pumpInSteps(tester, const Duration(seconds: 7));
    await _pumpInSteps(tester, const Duration(milliseconds: 1100));

    expect(find.text('Keep this wisdom.'), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(KeptDiscoveryHintService.hintCountKey), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Correction pass Item 3: navigating away before the discovery hint\'s '
      'own delay elapses invalidates it — no display count increment, no '
      'exception, no hint on return', (tester) async {
    final now = DateTime.now();
    const wisdom = 'A wisdom used to verify hint invalidation on navigation';
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
    expect(_keptGuard(tester).ignoring, isFalse);

    // Navigate to Kept before the hint's own ~1000ms delay elapses.
    await tester.tap(find.byKey(const ValueKey('home-kept-control')));
    await _settleRoutePush(
      tester,
      find.byKey(const ValueKey('kept-screen-root')),
    );

    // Let the originally-scheduled delay fully elapse while Kept is open.
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.text('Keep this wisdom.'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Back'));
    await _settleRoutePop(
      tester,
      const Duration(milliseconds: 300),
      poppedRouteFinder: find.byKey(const ValueKey('kept-screen-root')),
    );
    expect(find.byKey(const ValueKey('top-navigation')), findsOneWidget);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt(KeptDiscoveryHintService.hintCountKey) ?? 0, 0);
    expect(find.text('Keep this wisdom.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Correction pass Item 3: disposing the widget before the discovery '
      "hint's own delay elapses never calls setState after dispose",
      (tester) async {
    final now = DateTime.now();
    const wisdom = 'A wisdom used to verify hint invalidation on disposal';
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
    expect(_keptGuard(tester).ignoring, isFalse);

    // Replace the whole widget tree before the hint's own delay elapses —
    // this disposes HomeScreen while `_keptDiscoveryShowTimer` is pending.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1100));

    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Disposing HomeScreen while the discovery hint\'s own center '
      'breath-chain timer is pending (not merely the 1000ms offer-delay '
      'timer the test above covers) cancels it cleanly — no pending Timer, '
      'no setState-after-dispose exception', (tester) async {
    final now = DateTime.now();
    const wisdom =
        'A wisdom used to verify the breath-reset timer is cancelled '
        'on dispose';
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': DailyWisdomRecord(
        text: wisdom,
        revealedAt: now,
        unlockAt: now.add(const Duration(hours: 24)),
      ).encode(),
    });

    // A fresh service (see "Discovery test isolation" above) so this test
    // is independent of every other test's discovery state.
    await tester.pumpWidget(
      _homeApp(keptDiscoveryHintService: KeptDiscoveryHintService()),
    );
    await _finishOpeningIntro(tester);
    await _openExistingWisdom(tester);
    await tester.pump();
    expect(_keptGuard(tester).ignoring, isFalse);

    // The hint's own internal ~1000ms offer-delay must actually elapse to
    // reach presentation. Pumped in bounded 100ms steps (never
    // `pumpAndSettle`, which would never return while Home's continuous
    // ritual animations are running) rather than one fixed guessed
    // duration.
    await _pumpInSteps(tester, const Duration(milliseconds: 1100));

    expect(find.text('Keep this wisdom.'), findsOneWidget);

    // Update 1B: the first of 4 center save-ring breaths begins ~250ms
    // after the text above just appeared — not synchronously with it.
    await _pumpInSteps(tester, const Duration(milliseconds: 300));

    // `_HomeScreenState`'s discovery fields are private and unreachable
    // from this test file, so the breath timer's existence is confirmed
    // behaviorally: `_startKeptDiscoveryBreath` mounts the save-ring breath
    // and schedules `_keptDiscoveryBreathResetTimer` (the timer that
    // previously leaked past disposal) in the exact same `setState`/guard
    // block — the breath widget being mounted here is direct proof that
    // timer now exists and is pending, which the existing "disposing...
    // before the hint's own delay elapses" test above never reaches (it
    // disposes before presentation ever happens, so that timer is never
    // even created).
    expect(find.byKey(const ValueKey('save-ring-breath')), findsOneWidget);

    // Dispose HomeScreen right now, while the breath's own ~1.2s duration
    // timer is freshly scheduled and nowhere near its own fire time yet —
    // then stop. Deliberately not pumping past that window: doing so would
    // let an uncancelled timer simply fire and disappear here, proving
    // nothing. Whether `dispose()`'s `_cancelAllDiscoveryTimers()` actually
    // cancelled it is instead left entirely to flutter_test's own
    // end-of-test teardown, which fails the test on any Timer still
    // pending once it ends.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Correction pass (2nd revision) Item 1: the filled ring uses a '
      'dedicated no-op tap recognizer that wins the arena, absorbing a '
      'physical tap with no toggle, no main-tap handler, no navigation, no '
      'screenStep change, no VoiceOver action, and unchanged tap-target '
      'size', (tester) async {
    final now = DateTime.now();
    const wisdom = 'A wisdom used to verify the filled ring absorbs taps';
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': DailyWisdomRecord(
        text: wisdom,
        revealedAt: now,
        unlockAt: now.add(const Duration(hours: 24)),
        revealId: _fixedRevealId,
      ).encode(),
    });
    final keptGraph = KeptRepositoryTestGraph()
      ..seed([
        _testKeptRecord(
          id: 'already-kept-for-absorb-test',
          revealId: _fixedRevealId,
          wisdomText: wisdom,
          revealedAt: now,
        ),
      ]);

    await tester.pumpWidget(_homeApp(keptGraph: keptGraph));
    await _finishOpeningIntro(tester);
    await _openExistingWisdom(tester);
    await tester.pump();

    final keptSize = tester.getSize(
      find.byKey(const ValueKey('home-save-control-kept')),
    );

    final ringRecognizer = tester.widget<GestureDetector>(
      find.byKey(const ValueKey('home-save-control-kept')),
    );
    expect(
      ringRecognizer.behavior,
      HitTestBehavior.opaque,
      reason: 'The kept-state recognizer must claim this hit-test region '
          'opaquely so nothing behind it — the full-screen ritual gesture '
          '— can also be hit at this exact position.',
    );
    expect(ringRecognizer.excludeFromSemantics, isTrue);
    expect(
      ringRecognizer.onTap,
      isNotNull,
      reason: 'A non-null onTap is required for this GestureDetector to '
          'actually enter (and, by being the deeper/first-registered '
          'member, win) the tap gesture arena ahead of the ancestor '
          'full-screen ritual GestureDetector.',
    );

    final screenStepBefore = _homeScreenStep(tester);
    final navigationBefore = _homeNavigationInProgress(tester);

    // Exercise the exact filled-ring target directly (not just its
    // ancestor region), the same way a real touch would land on it.
    await tester.tap(find.byKey(const ValueKey('home-save-control-kept')));
    await tester.pump(const Duration(milliseconds: 100));

    // No navigation was triggered (the main ritual's `Kept`/`Settings`/
    // `Objects` routes never opened) and no ritual-flow change occurred —
    // i.e. the ancestor full-screen ritual GestureDetector's own tap
    // handler never fired.
    expect(find.byKey(const ValueKey('kept-screen-root')), findsNothing);
    expect(find.byKey(const ValueKey('settings-scroll')), findsNothing);
    expect(find.byKey(const ValueKey('objects-screen-root')), findsNothing);
    expect(_homeScreenStep(tester), screenStepBefore);
    expect(_homeNavigationInProgress(tester), navigationBefore);
    expect(find.text(wisdom), findsOneWidget);

    // No semantic tap action is exposed for the kept state.
    final semantics = tester.ensureSemantics();
    final keptNode = tester.getSemantics(
      find.byKey(const ValueKey('home-save-control-kept')),
    );
    expect(
      keptNode.getSemanticsData().hasAction(SemanticsAction.tap),
      isFalse,
    );
    semantics.dispose();

    // Tap-target size sanity check only: this test seeds the wisdom as
    // already-kept, so there is no unsaved-state IconButton rendered in
    // this same test to compare against, and no exact pixel value is
    // hardcoded here (IconButton's own default minimum interactive
    // dimension is Material-version-dependent and was not independently
    // confirmed against this project's toolchain). The actual size-parity
    // proof — that the kept-state control renders at exactly the same
    // size as the unsaved-state control — is covered by the "no grey
    // background, overlay, or splash" test above, which measures both
    // states within a single run and compares them directly.
    expect(keptSize.width, keptSize.height);
    expect(keptSize.width, greaterThan(0));

    // Persistence is byte-for-byte unchanged: still exactly the one
    // pre-existing Kept entry, not removed and not duplicated.
    final persisted = await keptGraph.service.load();
    expect(persisted, hasLength(1));
    expect(persisted.single.id, 'already-kept-for-absorb-test');
    expect(persisted.single.text, wisdom);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Final correction Item 2: Reduce Motion still shows the discovery '
      'hint text and completes a save, while the save-ring breath and the '
      'Kept-icon emphasis pulse do not run', (tester) async {
    final now = DateTime.now();
    const wisdom = 'A wisdom used to verify Reduce Motion discovery';
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': DailyWisdomRecord(
        text: wisdom,
        revealedAt: now,
        unlockAt: now.add(const Duration(hours: 24)),
      ).encode(),
    });
    final keptGraph = KeptRepositoryTestGraph();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: HomeScreen(
                dailyWisdomAccessService: DailyAccessTestGraph().service,
                // Discovery test isolation: this test drives a real save
                // through the discovery hint and reads back
                // `KeptDiscoveryHintService.completedKey` — a fresh
                // instance keeps it independent of every other test in
                // this file (see `_homeApp`'s own doc comment).
                keptDiscoveryHintService: KeptDiscoveryHintService(),
                // Correction: this test (unlike every other reveal test in
                // this file) constructs `HomeScreen` directly instead of
                // going through `_homeApp()` — which is exactly what
                // `_homeApp()`'s own default (`savedReflectionsService ??
                // keptGraph.service`) exists to protect against. A fresh,
                // test-local `KeptRepositoryTestGraph` (its own in-memory
                // store and its own `PersistenceOperationCoordinator`)
                // removes any dependency on other tests' in-flight
                // operations, and this test reads the save back through
                // that exact same graph below.
                savedReflectionsService: keptGraph.service,
              ),
            );
          },
        ),
      ),
    );
    await _finishOpeningIntro(tester);
    await _openExistingWisdom(tester);
    await tester.pump();
    expect(_keptGuard(tester).ignoring, isFalse);

    // The hint's own internal ~1000ms delay after the save ring settles.
    await tester.pump(const Duration(milliseconds: 1100));

    // "Keep this wisdom." still appears under Reduce Motion.
    expect(find.text('Keep this wisdom.'), findsOneWidget);

    // The save-ring breath never mounts: `_presentKeptDiscoveryHint` sets
    // `_keptDiscoveryBreathActive = !_reduceMotion`, and `_HomeSaveControl`
    // itself additionally gates on `showBreath && !reduceMotion` — both
    // layers must agree here.
    expect(find.byKey(const ValueKey('save-ring-breath')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('home-save-control-unsaved')));
    await tester.pump(const Duration(milliseconds: 50));

    // The save still succeeds and "Kept." still appears.
    expect(find.text('Kept.'), findsOneWidget);
    expect(find.text('Keep this wisdom.'), findsNothing);
    // Correction: assert the list actually has exactly one entry before
    // reading `.single` — this is the exact expression the reported
    // "Bad state: No element" came from (`.single` on a list that was, in
    // fact, still empty because this test previously read from the
    // process-wide `SavedReflectionsService` singleton's persistence
    // queue rather than a test-local instance; see the `savedReflectionsService:
    // keptGraph.service` correction above).
    final savedAfterReduceMotionSave = await keptGraph.service.load();
    expect(savedAfterReduceMotionSave, hasLength(1));
    expect(savedAfterReduceMotionSave.single.text, wisdom);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(KeptDiscoveryHintService.completedKey), isTrue);

    // Update 1G: the top-right Kept teaching breath never runs under
    // Reduce Motion either — `_onWisdomSuccessfullyKept` itself now checks
    // `!_reduceMotion` before ever scheduling `_scheduleKeptTopNavBreaths`,
    // so `_keptIconEmphasized` is never even set true here (a stricter,
    // state-level gate on top of `_KeptIconEmphasis`'s own render-time
    // `!MediaQuery.of(context).disableAnimations` check).
    await _pumpInSteps(tester, const Duration(milliseconds: 500));
    expect(
      find.byKey(const ValueKey('kept-icon-emphasis-pulse')),
      findsNothing,
    );

    // "Kept." fades on its own ~1.3s timer.
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('Kept.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Final correction Item 3: long-press-share still fires exactly once '
      'when a small realistic finger movement occurs mid-press, with no '
      'Kept navigation and no screenStep change', (tester) async {
    final now = DateTime.utc(2041, 7, 23, 8);
    const wisdom = 'A wisdom used to verify long-press-share survives pan';
    final record = DailyWisdomRecord(
      text: wisdom,
      revealedAt: now,
      unlockAt: now.add(const Duration(hours: 24)),
    );
    SharedPreferences.setMockInitialValues({
      DailyAccessRepository.dailyWisdomAccessKey: record.encode(),
    });
    final shareService = _RecordingWisdomShareService();
    final pushObserver = _HomePushCountingNavigatorObserver();

    await tester.pumpWidget(
      _homeApp(
        dailyGraph: DailyAccessTestGraph(clock: () => now),
        clock: () => now,
        wisdomShareService: shareService,
        navigatorObservers: [pushObserver],
      ),
    );
    await _finishOpeningIntro(tester);
    await _openExistingWisdom(tester);
    await _pumpUntilWisdomShareEnabled(tester);

    final screenStepBefore = _homeScreenStep(tester);
    final pushesBefore = pushObserver.pushCount;

    // A real long press, driven through the actual gesture arena (not a
    // manual `.onLongPress!()` invocation), with a small incidental finger
    // movement partway through the hold — well under both the long-press
    // recognizer's own move tolerance and the Home swipe-to-Kept gesture's
    // 60px distance / 320px/s velocity thresholds (see
    // `_homeSwipeToKeptEligible`/`_handleHomeSwipeEnd` in home_screen.dart).
    // This is the exact regression the horizontal pan callbacks newly added
    // to the ancestor `_HomeMainRitualGesture` GestureDetector could have
    // introduced: the wisdom text's own nested, deeper GestureDetector
    // (`wisdomShareOriginKey`, real `onLongPress`) must still win the tap
    // arena over both the ancestor's no-op `onLongPress: () {}` and its pan
    // recognizers.
    final wisdomCenter = tester.getCenter(find.text(wisdom));
    final gesture = await tester.startGesture(wisdomCenter);
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.moveBy(const Offset(2, 1));
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await tester.pump();

    expect(
      shareService.calls,
      1,
      reason: 'Long-press-share must still fire exactly once.',
    );
    expect(shareService.wisdoms, [wisdom]);
    expect(find.byKey(const ValueKey('kept-screen-root')), findsNothing);
    expect(_homeScreenStep(tester), screenStepBefore);
    expect(
      pushObserver.pushCount,
      pushesBefore,
      reason: 'No duplicate (or any) navigation occurred from this gesture.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Final correction Item 4: Home swipe-to-Kept gesture boundaries — '
      'short left, vertical, and rightward movement are no-ops; a rapid '
      'repeated qualifying swipe opens Kept exactly once; the save-ring tap '
      'is not intercepted by the swipe recognizer', (tester) async {
    final now = DateTime.now();
    const wisdom = 'A wisdom used to verify Home swipe gesture boundaries';
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': DailyWisdomRecord(
        text: wisdom,
        revealedAt: now,
        unlockAt: now.add(const Duration(hours: 24)),
      ).encode(),
    });
    final pushObserver = _HomePushCountingNavigatorObserver();
    final keptGraph = KeptRepositoryTestGraph();

    await tester.pumpWidget(
      _homeApp(navigatorObservers: [pushObserver], keptGraph: keptGraph),
    );
    await _finishOpeningIntro(tester);
    await _openExistingWisdom(tester);
    await tester.pump();

    final screenStepBefore = _homeScreenStep(tester);
    final pushesBefore = pushObserver.pushCount;

    // Each drag below starts on `home-ritual-gesture-surface` — the key
    // sits directly on the actual `GestureDetector` that owns the pan
    // recognizer (`_HomeMainRitualGesture`'s own), rather than on the
    // interior `revealed-wisdom-layout` `SizedBox`, which sits beneath a
    // `FittedBox` transform and is not itself the gesture-owning surface.
    // Starting there risked `tester.drag`'s own hit-test warning firing
    // (finder resolved to a widget whose exact center did not reliably hit
    // the real recognizer) without ever actually failing an assertion,
    // silently making these boundary checks pass trivially.
    //
    // Short left movement: well under the 60px distance / 320px/s velocity
    // thresholds `_handleHomeSwipeEnd` requires — must do nothing.
    await tester.drag(
      find.byKey(const ValueKey('home-ritual-gesture-surface')),
      const Offset(-25, 0),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('kept-screen-root')), findsNothing);
    expect(_homeNavigationInProgress(tester), isFalse);
    expect(_homeScreenStep(tester), screenStepBefore);

    // Vertical movement: fails `_handleHomeSwipeEnd`'s `isLeftward` and
    // `horizontalDominant` checks — must do nothing.
    await tester.drag(
      find.byKey(const ValueKey('home-ritual-gesture-surface')),
      const Offset(0, -140),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('kept-screen-root')), findsNothing);
    expect(_homeNavigationInProgress(tester), isFalse);
    expect(_homeScreenStep(tester), screenStepBefore);

    // Rightward movement: fails `isLeftward` (`dx < 0`) — must do nothing.
    await tester.drag(
      find.byKey(const ValueKey('home-ritual-gesture-surface')),
      const Offset(140, 0),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('kept-screen-root')), findsNothing);
    expect(_homeNavigationInProgress(tester), isFalse);
    expect(_homeScreenStep(tester), screenStepBefore);
    expect(
      pushObserver.pushCount,
      pushesBefore,
      reason: 'None of the three boundary gestures above pushed a route.',
    );

    // The save-ring tap is not intercepted by the swipe/pan recognizer now
    // present on the same ancestor GestureDetector: a normal tap on the
    // unsaved ring, with the pan recognizers live and eligible
    // (`_homeSwipeToKeptEligible` is true on the revealed-wisdom step),
    // still saves normally.
    await tester.tap(find.byKey(const ValueKey('home-save-control-unsaved')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(
        find.byKey(const ValueKey('home-save-control-kept')), findsOneWidget);
    expect(
      (await keptGraph.service.load()).single.text,
      wisdom,
    );
    expect(find.byKey(const ValueKey('kept-screen-root')), findsNothing);
    expect(_homeScreenStep(tester), screenStepBefore);

    // Rapid, repeated qualifying swipe: two back-to-back qualifying
    // left-swipes (well past the 60px/320px/s thresholds), fired with no
    // settling frame between them, must still only ever open Kept once —
    // `_handleHomeSwipeEnd`'s own `_homeSwipeHandled` guard plus
    // `openFavorites()`'s `navigationInProgress` guard (which
    // `_homeSwipeToKeptEligible` also checks) must collapse both attempts
    // into a single route push.
    //
    // Correction: calling `tester.drag(finder, ...)` a second time here
    // previously re-resolved `home-ritual-gesture-surface` *after* the
    // first swipe's pointer-up had already started `openFavorites()` —
    // by the time the second `tester.drag()` queried the finder's
    // position, Kept's route had begun mounting on top of Home, so the
    // second call warned about not hitting the widget it resolved to
    // (Home's gesture surface, now covered). The fix is to resolve the
    // gesture surface's coordinate exactly once, before either swipe, and
    // to dispatch both complete pointer-down/move/up sequences manually
    // via `TestGesture` — supplying real, increasing per-event
    // timestamps (so the velocity tracker still sees a genuine
    // above-threshold swipe) but never calling `tester.pump()` between or
    // during them. No frame is built between the two gestures, so Kept's
    // route has no opportunity to mount/paint over Home before the
    // second gesture lands — both are dispatched against the exact same,
    // still-uncovered Home surface. Only after both gestures have fully
    // landed does this test pump for the route transition.
    final pushesBeforeSwipe = pushObserver.pushCount;
    final gestureSurfaceCenter = tester.getCenter(
      find.byKey(const ValueKey('home-ritual-gesture-surface')),
    );

    Future<void> fireQualifyingSwipeWithNoIntermediateFrame() async {
      final gesture = await tester.startGesture(gestureSurfaceCenter);
      await gesture.moveBy(
        const Offset(-70, 0),
        timeStamp: const Duration(milliseconds: 20),
      );
      await gesture.moveBy(
        const Offset(-70, 0),
        timeStamp: const Duration(milliseconds: 40),
      );
      await gesture.up();
    }

    await fireQualifyingSwipeWithNoIntermediateFrame();
    await fireQualifyingSwipeWithNoIntermediateFrame();

    await _settleRoutePush(
      tester,
      find.byKey(const ValueKey('kept-screen-root')),
    );

    expect(find.byKey(const ValueKey('kept-screen-root')), findsOneWidget);
    expect(
      pushObserver.pushCount,
      pushesBeforeSwipe + 1,
      reason: 'Exactly one Kept route push resulted from the repeated '
          'rapid qualifying swipe.',
    );
    expect(tester.takeException(), isNull);
  });

  // ---------------------------------------------------------------------
  // 3D-C correction (Section 4): HomeScreen reveal-identity tests. These
  // prove the 16 listed scenarios directly rather than assuming them from
  // source inspection. Items 2, 3, 4, 12, 13, 14 are covered above/already
  // existed (see the edits to "active lock reopens to the existing wisdom
  // without revealing", "slow authoritative write does not delay reveal
  // animation but gates save", "locked wisdom returns to launch after
  // expiry refresh", and the pre-existing one-way/rapid-tap save tests);
  // the remaining items are covered by the dedicated tests below.
  // ---------------------------------------------------------------------

  testWidgets(
      'Item 1: a successful new reveal commit retains its revealId and '
      'revealedAt on the live HomeScreen state', (tester) async {
    final now = DateTime.utc(2041, 7, 23, 8);
    final dailyGraph = DailyAccessTestGraph(clock: () => now);

    await tester.pumpWidget(
      _homeApp(dailyGraph: dailyGraph, clock: () => now),
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
    expect(persisted!.revealId, isNotNull);
    expect(_homeCurrentRevealId(tester), persisted.revealId);
    expect(
      _homeCurrentRevealedAt(tester)?.millisecondsSinceEpoch,
      persisted.revealedAt.millisecondsSinceEpoch,
    );

    await _pumpUntilWisdomFullyAppeared(tester);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets(
      'Items 5/7/8: currentFavorite matches strictly by revealId, never by '
      'wisdom text', (tester) async {
    await tester.pumpWidget(_homeApp());
    await _finishOpeningIntro(tester);

    final dynamic homeState = tester.state(find.byType(HomeScreen));

    const sharedText = 'A wisdom the pool repeats across two distinct days';
    const matchingItem = FavoriteItem(
      id: 'match-by-id',
      revealId: 'reveal-aaaa',
      text: sharedText,
      date: 'Jan 1, 2026',
    );
    const sameTextDifferentRevealItem = FavoriteItem(
      id: 'same-text-different-reveal',
      revealId: 'reveal-bbbb',
      text: sharedText,
      date: 'Jan 2, 2026',
    );

    homeState.favorites = <FavoriteItem>[
      matchingItem,
      sameTextDifferentRevealItem,
    ];

    // Item 8: identical text on screen, but the current revealId matches
    // neither seeded record — never treated as already kept.
    homeState.currentRevealId = 'reveal-cccc';
    homeState.currentText = sharedText;
    expect(homeState.isCurrentFavorite(), isFalse);
    expect(homeState.currentFavorite(), isNull);

    // Items 5/7: currentRevealId matches `matchingItem`'s revealId exactly,
    // even though the text currently on screen is completely different —
    // the match is by identity, never by text.
    homeState.currentRevealId = 'reveal-aaaa';
    homeState.currentText = 'A completely different piece of text on screen';
    expect(homeState.isCurrentFavorite(), isTrue);
    expect(homeState.currentFavorite(), same(matchingItem));

    // The other record shares identical text with `matchingItem` but a
    // distinct revealId — it remains its own distinct, separately matched
    // identity, proving identical text never collapses two occurrences.
    homeState.currentRevealId = 'reveal-bbbb';
    expect(homeState.currentFavorite(), same(sameTextDifferentRevealItem));
  });

  testWidgets(
      'Item 9: a null revealId blocks save before SavedReflectionsService '
      'is ever called', (tester) async {
    final now = DateTime.utc(2041, 7, 23, 8);
    final dailyGraph = DailyAccessTestGraph(clock: () => now);
    final keptGraph = KeptRepositoryTestGraph();

    await tester.pumpWidget(
      _homeApp(dailyGraph: dailyGraph, clock: () => now, keptGraph: keptGraph),
    );
    await _finishOpeningIntro(tester);
    await _advanceToQuestion(tester);
    await _tapCenter(tester);
    await tester.pump(const Duration(milliseconds: 1250));
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    await tester.pump();
    await _pumpUntilWisdomFullyAppeared(tester);

    expect(_homeCurrentRevealId(tester), isNotNull);
    final dynamic homeState = tester.state(find.byType(HomeScreen));
    homeState.currentRevealId = null;

    // The wisdom text's own fade (1200ms) completes before the save ring's
    // separate opacity animation (which does not even start until 900ms
    // after commit, and itself takes 1000ms) does — an explicit real-time
    // pump is needed here so `saveInteractionEnabled` has actually flipped
    // true by the time the tap below is attempted, rather than the tap
    // being swallowed by the unrelated "still fading in" guard.
    await tester.pump(const Duration(seconds: 2));
    await _pumpUntilCondition(
        tester, () => _keptGuard(tester).ignoring == false);
    expect(_keptGuard(tester).ignoring, isFalse);

    await tester.tap(find.byKey(const ValueKey('home-save-control-unsaved')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(await keptGraph.service.load(), isEmpty);
    expect(find.byKey(const ValueKey('home-save-control-unsaved')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('home-save-control-kept')), findsNothing);
    expect(find.textContaining('could not be kept'), findsOneWidget);
  });

  testWidgets(
      'Item 10: a null revealedAt blocks save before SavedReflectionsService '
      'is ever called', (tester) async {
    final now = DateTime.utc(2041, 7, 23, 8);
    final dailyGraph = DailyAccessTestGraph(clock: () => now);
    final keptGraph = KeptRepositoryTestGraph();

    await tester.pumpWidget(
      _homeApp(dailyGraph: dailyGraph, clock: () => now, keptGraph: keptGraph),
    );
    await _finishOpeningIntro(tester);
    await _advanceToQuestion(tester);
    await _tapCenter(tester);
    await tester.pump(const Duration(milliseconds: 1250));
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    await tester.pump();
    await _pumpUntilWisdomFullyAppeared(tester);

    expect(_homeCurrentRevealedAt(tester), isNotNull);
    final dynamic homeState = tester.state(find.byType(HomeScreen));
    // revealId is deliberately left non-null: this isolates the
    // `revealedAt == null` half of `toggleFavorite`'s
    // `revealId == null || revealedAt == null` guard from the `revealId`
    // half already proven by Item 9 above — a combination `toggleFavorite`
    // never produces on its own, since both fields are always assigned
    // together on every production code path, but the guard itself checks
    // them independently and must be proven to do so.
    homeState.currentRevealedAt = null;

    // See Item 9's identical comment above: the save ring's own opacity
    // animation finishes well after the wisdom text's fade does, so a real
    // elapsed-time pump is required before the interaction guard reliably
    // reads false.
    await tester.pump(const Duration(seconds: 2));
    await _pumpUntilCondition(
        tester, () => _keptGuard(tester).ignoring == false);
    expect(_keptGuard(tester).ignoring, isFalse);

    await tester.tap(find.byKey(const ValueKey('home-save-control-unsaved')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(await keptGraph.service.load(), isEmpty);
    expect(find.byKey(const ValueKey('home-save-control-unsaved')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('home-save-control-kept')), findsNothing);
    expect(find.textContaining('could not be kept'), findsOneWidget);
  });

  testWidgets(
      'Item 11: a locked record whose revealId backfill has persistently '
      'failed remains viewable but blocks save without falling back to '
      'text-based identity', (tester) async {
    final now = DateTime.now();
    const wisdom = 'A pre-identity legacy wisdom whose backfill never lands';
    final legacyRecord = DailyWisdomRecord(
      text: wisdom,
      revealedAt: now,
      unlockAt: now.add(const Duration(hours: 24)),
    );
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': legacyRecord.encode(),
    });
    final failingAdapter = InterceptingStoragePreferencesAdapter(
      setStringInterceptor: (key, value, persist) async {
        if (key == DailyAccessRepository.dailyWisdomAccessKey) {
          // The backfill write always fails; the original legacy record on
          // disk is therefore never touched by it, and revealId remains
          // null indefinitely across every launch this test performs.
          throw StateError('backfill persistently fails');
        }
        await persist();
      },
    );
    final dailyGraph =
        DailyAccessTestGraph(adapter: failingAdapter, clock: () => now);
    final keptGraph = KeptRepositoryTestGraph();

    await tester.pumpWidget(
      _homeApp(dailyGraph: dailyGraph, clock: () => now, keptGraph: keptGraph),
    );
    await _finishOpeningIntro(tester);
    await _openExistingWisdom(tester);
    await tester.pump();

    // Viewable: the locked wisdom's text is on screen despite the failed
    // backfill.
    expect(find.text(wisdom), findsOneWidget);
    expect(_homeCurrentRevealId(tester), isNull);

    final prefs = await SharedPreferences.getInstance();
    final persistedOnDisk =
        DailyWisdomRecord.decode(prefs.getString('daily_wisdom_access')!);
    expect(persistedOnDisk.revealId, isNull);
    expect(persistedOnDisk.text, wisdom);

    final save = find.byKey(const ValueKey('home-save-control-unsaved'));
    expect(save, findsOneWidget);
    await _pumpUntilCondition(
        tester, () => _keptGuard(tester).ignoring == false);
    expect(_keptGuard(tester).ignoring, isFalse);

    await tester.tap(save);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // Blocked before any SavedReflectionsService call: no record is kept,
    // and the block never fell back to matching/saving by wisdom text.
    expect(await keptGraph.service.load(), isEmpty);
    expect(find.byKey(const ValueKey('home-save-control-unsaved')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('home-save-control-kept')), findsNothing);
    expect(find.textContaining('could not be kept'), findsOneWidget);
  });

  testWidgets(
      'Item 15: a free-limit result still shows the existing Kept Limit '
      'dialog and does not persist a new record', (tester) async {
    final now = DateTime.now();
    const wisdom = 'A new wisdom attempted while already at the free limit';
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': DailyWisdomRecord(
        text: wisdom,
        revealedAt: now,
        unlockAt: now.add(const Duration(hours: 24)),
        revealId: _fixedRevealId,
      ).encode(),
    });
    final keptGraph = KeptRepositoryTestGraph()
      ..seed([
        _testKeptRecord(
          id: 'limit-1',
          revealId: _testUuid(1),
          wisdomText: 'One',
          revealedAt: now,
        ),
        _testKeptRecord(
          id: 'limit-2',
          revealId: _testUuid(2),
          wisdomText: 'Two',
          revealedAt: now,
        ),
        _testKeptRecord(
          id: 'limit-3',
          revealId: _testUuid(3),
          wisdomText: 'Three',
          revealedAt: now,
        ),
      ]);

    await tester.pumpWidget(_homeApp(keptGraph: keptGraph));
    await _finishOpeningIntro(tester);
    await _openExistingWisdom(tester);
    await tester.pump();

    expect(find.byKey(const ValueKey('home-save-control-unsaved')),
        findsOneWidget);
    await _pumpUntilCondition(
        tester, () => _keptGuard(tester).ignoring == false);

    // Correction: `pumpAndSettle()` never returns here — HomeScreen's
    // ritual screen keeps perpetual ambient animation (grain, breathing,
    // glow) continuously scheduling new frames for as long as this screen
    // is mounted, so "settled" (no pending frames) never actually occurs.
    // A bounded, real-duration pump sequence is used instead: one pump to
    // let the tap's callback and the in-memory repository Future resolve,
    // then a further 300ms to let the dialog's own (short, one-shot)
    // entrance transition finish rendering — without ever waiting for the
    // screen's own unrelated continuous animation to stop.
    await tester.tap(find.byKey(const ValueKey('home-save-control-unsaved')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Kept Limit'), findsOneWidget);
    expect(find.text('Become a Keeper'), findsOneWidget);
    final storedAfterLimit = await keptGraph.service.load();
    expect(storedAfterLimit, hasLength(3));
    // The attempted (blocked) wisdom's revealId — `_fixedRevealId`, set on
    // the seeded `DailyWisdomRecord` above and therefore this screen's
    // `currentRevealId` — never made it into protected storage.
    expect(
      storedAfterLimit.any((item) => item.revealId == _fixedRevealId),
      isFalse,
    );
    expect(find.byKey(const ValueKey('home-save-control-unsaved')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Item 16: Keeper unlimited behavior still follows the existing UI '
      'flow beyond the free limit', (tester) async {
    final now = DateTime.now();
    const wisdom = 'A new wisdom kept by a Keeper beyond the free limit';
    SharedPreferences.setMockInitialValues({
      'daily_wisdom_access': DailyWisdomRecord(
        text: wisdom,
        revealedAt: now,
        unlockAt: now.add(const Duration(hours: 24)),
        revealId: _fixedRevealId,
      ).encode(),
    });
    final keptGraph = KeptRepositoryTestGraph()
      ..seed([
        _testKeptRecord(
          id: 'keeper-limit-1',
          revealId: _testUuid(4),
          wisdomText: 'One',
          revealedAt: now,
        ),
        _testKeptRecord(
          id: 'keeper-limit-2',
          revealId: _testUuid(5),
          wisdomText: 'Two',
          revealedAt: now,
        ),
        _testKeptRecord(
          id: 'keeper-limit-3',
          revealId: _testUuid(6),
          wisdomText: 'Three',
          revealedAt: now,
        ),
      ]);

    await tester.pumpWidget(_homeApp(keptGraph: keptGraph));
    await _finishOpeningIntro(tester);
    await _openExistingWisdom(tester);
    await tester.pump();

    final dynamic homeState = tester.state(find.byType(HomeScreen));
    // `isKeeper` is an ordinary (non-underscore) instance field on
    // `_HomeScreenState`, populated in production from
    // `app_services.purchaseService.isKeeper` — a process-wide singleton
    // this test file has no existing seam to flip. Writing it directly here
    // is the same narrow, already-established dynamic-dispatch technique
    // used for `currentRevealId`/`currentRevealedAt` above, not a new
    // production seam.
    homeState.isKeeper = true;

    expect(find.byKey(const ValueKey('home-save-control-unsaved')),
        findsOneWidget);
    await _pumpUntilCondition(
        tester, () => _keptGuard(tester).ignoring == false);

    await tester.tap(find.byKey(const ValueKey('home-save-control-unsaved')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('Kept Limit'), findsNothing);
    final persisted = await keptGraph.service.load();
    expect(persisted, hasLength(4));
    expect(persisted.any((item) => item.text == wisdom), isTrue);
    expect(
        find.byKey(const ValueKey('home-save-control-kept')), findsOneWidget);
  });

  // ---------------------------------------------------------------------
  // Correction (toggle rename): `SavedReflectionsService.toggle` now takes
  // text/date/isKeeper/revealId/revealedAt/existingId. `date` is a
  // compatibility-only field HomeScreen fills with `formattedToday()` (the
  // real wall-clock date) — it must never be confused with or substitute
  // for `revealedAt` (the authoritative, possibly-injected-clock reveal
  // moment). This test proves the two are never conflated.
  // ---------------------------------------------------------------------
  testWidgets(
      'toggleFavorite passes the authoritative revealedAt independent of '
      'the date compatibility field', (tester) async {
    // Deliberately far from the real date this test actually runs on, so
    // `date` (always today's real wall-clock date) and `revealedAt` (this
    // injected clock) can never coincidentally match.
    final revealBoundary = DateTime.utc(2019, 3, 14, 8);
    final dailyGraph = DailyAccessTestGraph(clock: () => revealBoundary);
    final keptGraph = KeptRepositoryTestGraph();
    final spy = _RecordingSavedReflectionsService(keptGraph.service);

    await tester.pumpWidget(
      _homeApp(
        dailyGraph: dailyGraph,
        clock: () => revealBoundary,
        savedReflectionsService: spy,
      ),
    );
    await _finishOpeningIntro(tester);
    await _advanceToQuestion(tester);
    await _tapCenter(tester);
    await tester.pump(const Duration(milliseconds: 1250));
    await tester.pump(const Duration(milliseconds: 550));
    await tester.pump();
    await tester.pump();
    await _pumpUntilWisdomFullyAppeared(tester);
    await tester.pump(const Duration(seconds: 2));
    await _pumpUntilCondition(
        tester, () => _keptGuard(tester).ignoring == false);

    await tester.tap(find.byKey(const ValueKey('home-save-control-unsaved')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(spy.toggleCallCount, 1);
    expect(spy.capturedIsKeeper, isFalse);
    expect(spy.capturedExistingId, isNull);

    final persistedDailyRecord =
        await dailyGraph.repository.loadDailyWisdomRecord();
    expect(persistedDailyRecord, isNotNull);
    expect(spy.capturedRevealId, persistedDailyRecord!.revealId);
    expect(spy.capturedText, persistedDailyRecord.text);

    // The authoritative timestamp is exactly the injected reveal boundary
    // — never today's real date.
    expect(
      spy.capturedRevealedAt?.millisecondsSinceEpoch,
      revealBoundary.millisecondsSinceEpoch,
    );
    // `date` is today's real display date, not a formatting of
    // `revealedAt`/`revealBoundary` — proving `date` carries no identity or
    // timestamp authority of its own.
    expect(spy.capturedDate, formattedToday());
    expect(spy.capturedDate, isNot(formatFavoriteDisplayDate(revealBoundary)));

    // The persisted `KeptRecord` itself reflects the authoritative
    // `revealedAt`, never `date`.
    final storedRecord = keptGraph.store.envelope!.activeRecords.single;
    expect(
      storedRecord.revealedAt.millisecondsSinceEpoch,
      revealBoundary.millisecondsSinceEpoch,
    );
    expect(storedRecord.revealId, persistedDailyRecord.revealId);

    await tester.pump(const Duration(seconds: 6));
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

/// Build 26 Phase 3D-C: a single fixed, canonical UUID v4 used across this
/// file's "already kept" test setups. Kept identity is now `revealId`-only
/// (never text/date), so an "already kept" fixture must give the seeded
/// `DailyWisdomRecord` this exact `revealId` and pre-populate a matching
/// `KeptRecord` under the same `revealId` — never rely on `backfillRevealIdIfNeeded()`'s
/// own freshly minted (and therefore unpredictable) UUID. Reused verbatim
/// across different tests is safe: each test constructs its own isolated
/// `KeptRepositoryTestGraph`/store, so there is no cross-test collision.
const _fixedRevealId = 'a5f3c111-1111-4111-8111-111111111111';

/// Deterministic, repeatable canonical UUID v4 for test-only fixtures that
/// need several *distinct* valid Kept identities (`KeptRecord.revealId`/
/// `mutationId` — see `KeptRecord._validate`/`isCanonicalUuidV4OrV5` —
/// require a canonical UUID v4 or v5; arbitrary strings like `'reveal-1'`
/// are rejected). Every call with a distinct [suffix] produces a distinct,
/// valid UUID; the same [suffix] always produces the same UUID, so
/// fixtures remain reproducible across runs with no random collision risk.
/// Never used outside this test file.
String _testUuid(int suffix) {
  assert(suffix >= 0 && suffix <= 0xFFFFFFFFFFFF);
  return '00000000-0000-4000-8000-'
      '${suffix.toRadixString(16).padLeft(12, '0')}';
}

/// Builds one active [KeptRecord] for seeding a [KeptRepositoryTestGraph]
/// directly (bypassing `keepOccurrence`'s own id/mutationId generation) so
/// an "already kept" fixture's identity is entirely deterministic.
KeptRecord _testKeptRecord({
  required String id,
  required String revealId,
  required String wisdomText,
  required DateTime revealedAt,
  DateTime? keptAt,
  String? reflectionText,
  DateTime? reflectedAt,
}) {
  final effectiveKeptAt = keptAt ?? revealedAt;
  final effectiveUpdatedAt = reflectedAt ?? effectiveKeptAt;
  return KeptRecord(
    id: id,
    revealId: revealId,
    wisdomText: wisdomText,
    revealedAt: revealedAt,
    keptAt: effectiveKeptAt,
    reflectionText: reflectionText,
    reflectedAt: reflectedAt,
    updatedAt: effectiveUpdatedAt,
    mutationId: revealId,
  );
}

Widget _homeApp({
  DailyAccessTestGraph? dailyGraph,
  StorageService? storageService,
  KeptRepositoryTestGraph? keptGraph,
  SavedReflectionsService? savedReflectionsService,
  WisdomShareHandler? wisdomShareService,
  WisdomNotificationService? wisdomNotificationService,
  KeptDiscoveryHintService? keptDiscoveryHintService,
  WisdomClock? clock,
  Duration dailyWisdomOperationTimeout = const Duration(seconds: 8),
  Duration dailyWisdomStatusTimeout =
      DailyWisdomAccessService.defaultStatusTimeout,
  List<NavigatorObserver> navigatorObservers = const <NavigatorObserver>[],
}) {
  final resolvedDailyGraph = dailyGraph ?? DailyAccessTestGraph(clock: clock);
  // Build 26 Phase 3D-C: `SavedReflectionsService` no longer has a bare
  // no-arg constructor — it now requires a `KeptRepository`. A fresh
  // `KeptRepositoryTestGraph` per call (never shared, never a process-wide
  // singleton) keeps every test's Kept persistence fully isolated, exactly
  // as `resolvedDailyGraph` already does for daily access above. Tests that
  // need to read back what a widget interaction persisted pass their own
  // `keptGraph:` in and read `keptGraph.service.load()` afterward.
  final resolvedKeptGraph = keptGraph ?? KeptRepositoryTestGraph();
  return MaterialApp(
    navigatorObservers: navigatorObservers,
    home: HomeScreen(
      storageService: storageService ?? StorageService(),
      savedReflectionsService:
          savedReflectionsService ?? resolvedKeptGraph.service,
      dailyWisdomAccessService: resolvedDailyGraph.service,
      wisdomShareService: wisdomShareService,
      wisdomNotificationService: wisdomNotificationService,
      // Correction (Discovery test isolation): a fresh instance every call,
      // never the process-wide `app_services.keptDiscoveryHintService`
      // singleton. That singleton's in-memory `_completedInMemory`/
      // `_displayCountInMemory` caches persist for the lifetime of the test
      // *process*, not per-test — so without this, one test marking
      // discovery completed (or incrementing its display count) silently
      // leaked that in-memory state into every other test in this file
      // that used `_homeApp()`, regardless of `SharedPreferences
      // .setMockInitialValues` resetting the underlying persisted store
      // between tests. See "Discovery test isolation" below for the
      // regression test proving this.
      keptDiscoveryHintService:
          keptDiscoveryHintService ?? KeptDiscoveryHintService(),
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

/// Locates a top-nav ring `CustomPaint` directly by its own stable key
/// (`objects-top-nav-ring` / `kept-top-nav-ring`, set in `top_nav_ring.dart`)
/// rather than by walking up from a tooltip/ancestor — that ancestry-based
/// approach broke once the `Tooltip` wrapper was removed entirely from
/// `_HomeTopNavigation`. The key is asserted to resolve to exactly one
/// widget before it is read, so this never calls `.single`/`.painter` on an
/// unverified or broad finder.
TopNavRingPainter _topNavRingPainterByKey(WidgetTester tester, String key) {
  final finder = find.byKey(ValueKey(key));
  expect(finder, findsOneWidget);
  return tester.widget<CustomPaint>(finder).painter! as TopNavRingPainter;
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

/// Reads the discovery hint's own persisted display counter directly —
/// used by the granted/denied notification-Completer tests to prove the
/// hint was presented exactly once (never zero while pending, never twice
/// after resolution), independent of `find.text(...)`'s own timing.
Future<int> _keptDiscoveryDisplayCount() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getInt(KeptDiscoveryHintService.hintCountKey) ?? 0;
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

int _homeScreenStep(WidgetTester tester) {
  final dynamic homeState = tester.state(find.byType(HomeScreen));
  return homeState.screenStep as int;
}

/// 3D-C correction (Section 4): reads the live `currentRevealId`/
/// `currentRevealedAt` straight off the mounted `HomeScreen`'s `State`, the
/// same non-underscore-field dynamic-dispatch technique
/// `_homeScreenStep`/`_homeNavigationInProgress` already use above. Both
/// fields are ordinary (non-underscore) instance members of the private
/// `_HomeScreenState`, so no new test-only production seam is introduced by
/// reading — or, where a test needs to force an otherwise-unreachable
/// combination (see the null-revealId/null-revealedAt tests below), writing
/// — them via a `dynamic` reference.
String? _homeCurrentRevealId(WidgetTester tester) {
  final dynamic homeState = tester.state(find.byType(HomeScreen));
  return homeState.currentRevealId as String?;
}

DateTime? _homeCurrentRevealedAt(WidgetTester tester) {
  final dynamic homeState = tester.state(find.byType(HomeScreen));
  return homeState.currentRevealedAt as DateTime?;
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

/// Correction pass (toggle rename to text/date/isKeeper/revealId/
/// revealedAt/existingId): wraps a real [SavedReflectionsService] and
/// records exactly what `HomeScreen.toggleFavorite` passed to [toggle],
/// while still delegating to the real instance so persisted Kept state
/// behaves identically to production. Used to prove `date` is passed
/// through untouched (today's real display date) while `revealedAt` is the
/// authoritative reveal moment — the two are never conflated.
class _RecordingSavedReflectionsService implements SavedReflectionsService {
  _RecordingSavedReflectionsService(this._inner);

  final SavedReflectionsService _inner;

  int toggleCallCount = 0;
  String? capturedText;
  String? capturedDate;
  bool? capturedIsKeeper;
  String? capturedRevealId;
  DateTime? capturedRevealedAt;
  String? capturedExistingId;

  @override
  Future<List<FavoriteItem>> load() => _inner.load();

  @override
  Future<SavedReflectionsResult> toggle({
    required String text,
    required String date,
    required bool isKeeper,
    required String revealId,
    required DateTime revealedAt,
    String? existingId,
  }) {
    toggleCallCount += 1;
    capturedText = text;
    capturedDate = date;
    capturedIsKeeper = isKeeper;
    capturedRevealId = revealId;
    capturedRevealedAt = revealedAt;
    capturedExistingId = existingId;
    return _inner.toggle(
      text: text,
      date: date,
      isKeeper: isKeeper,
      revealId: revealId,
      revealedAt: revealedAt,
      existingId: existingId,
    );
  }

  @override
  Future<SavedReflectionsResult> saveReflection({
    required String itemId,
    required String reflection,
    required bool isKeeper,
    DateTime? reflectedAt,
  }) {
    return _inner.saveReflection(
      itemId: itemId,
      reflection: reflection,
      isKeeper: isKeeper,
      reflectedAt: reflectedAt,
    );
  }

  @override
  Future<List<FavoriteItem>> deleteReflection({required String itemId}) {
    return _inner.deleteReflection(itemId: itemId);
  }

  @override
  Future<RemovedSavedReflection?> remove({required String itemId}) {
    return _inner.remove(itemId: itemId);
  }

  @override
  Future<List<FavoriteItem>> restore(RemovedSavedReflection removed) {
    return _inner.restore(removed);
  }

  @override
  Future<String?> resolveLegacyMigratedRevealIdForOccurrence({
    required String wisdomText,
    required DateTime committedRevealedAt,
    required DateTime committedUnlockAt,
  }) {
    return _inner.resolveLegacyMigratedRevealIdForOccurrence(
      wisdomText: wisdomText,
      committedRevealedAt: committedRevealedAt,
      committedUnlockAt: committedUnlockAt,
    );
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
