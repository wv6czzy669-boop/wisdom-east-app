// EAST. 1.2 Slice 3 -- WidgetPresentationSyncCoordinator: ownership,
// generation-guarded newest-wins ordering, disposal safety, and
// presentation resolution (locale/appearance), entirely independent of
// HomeScreen and the real platform channel.
import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/controllers/appearance_preference_controller.dart';
import 'package:wisdom_app/controllers/locale_preference_controller.dart';
import 'package:wisdom_app/services/daily_wisdom_access_service.dart';
import 'package:wisdom_app/services/widget_presentation_sync_coordinator.dart';
import 'package:wisdom_app/services/widget_snapshot_service.dart';
import 'package:wisdom_app/services/wisdom_localization_resolver.dart';

import '../persistence_test_helpers.dart';

/// Overrides `status()` only -- every other member (identity, migration,
/// reveal-preparation) is inherited unused, since this coordinator's own
/// tests never exercise them. A queued completer lets a test hold `status()`
/// "in flight" for as long as it needs, to simulate a slow lookup racing a
/// newer preference change; when the queue is empty, [nextStatus] resolves
/// immediately, matching ordinary fast-path behavior.
class _DelayableDailyWisdomAccessService extends DailyWisdomAccessService {
  _DelayableDailyWisdomAccessService({required super.repository});

  final List<Completer<DailyWisdomStatus>> _pending = [];
  DailyWisdomStatus nextStatus = const DailyWisdomStatus(isReady: true);
  int statusCallCount = 0;

  Completer<DailyWisdomStatus> queueDelayed() {
    final completer = Completer<DailyWisdomStatus>();
    _pending.add(completer);
    return completer;
  }

  @override
  Future<DailyWisdomStatus> status() async {
    statusCallCount++;
    if (_pending.isNotEmpty) {
      return _pending.removeAt(0).future;
    }
    return nextStatus;
  }
}

class _RecordedPublishRevealed {
  _RecordedPublishRevealed({
    required this.text,
    required this.unlockAt,
    required this.appearanceMode,
    required this.localeOverrideTag,
  });
  final String text;
  final DateTime unlockAt;
  final EastAppearanceMode appearanceMode;
  final String? localeOverrideTag;
}

class _RecordedPublishSilence {
  _RecordedPublishSilence({
    required this.appearanceMode,
    required this.localeOverrideTag,
  });
  final EastAppearanceMode appearanceMode;
  final String? localeOverrideTag;
}

/// Records every call instead of crossing a platform channel, mirroring
/// `home_screen_test.dart`'s own `_Recording*` fakes for other services.
/// `WidgetSnapshotService`'s own channel contract is covered directly in
/// `test/services/widget_snapshot_service_test.dart`.
class _RecordingWidgetSnapshotService implements WidgetSnapshotService {
  final List<Object> calls = [];

  @override
  Future<void> publishRevealed({
    required String text,
    required DateTime unlockAt,
    required EastAppearanceMode appearanceMode,
    required String? localeOverrideTag,
  }) async {
    calls.add(_RecordedPublishRevealed(
      text: text,
      unlockAt: unlockAt,
      appearanceMode: appearanceMode,
      localeOverrideTag: localeOverrideTag,
    ));
  }

  @override
  Future<void> publishSilence({
    required EastAppearanceMode appearanceMode,
    required String? localeOverrideTag,
  }) async {
    calls.add(_RecordedPublishSilence(
      appearanceMode: appearanceMode,
      localeOverrideTag: localeOverrideTag,
    ));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppearancePreferenceController appearanceController;
  late LocalePreferenceController localeController;
  late _DelayableDailyWisdomAccessService dailyService;
  late _RecordingWidgetSnapshotService widgetService;
  late WidgetPresentationSyncCoordinator coordinator;
  WidgetPresentationSyncCoordinator? extraCoordinator;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    appearanceController = AppearancePreferenceController();
    localeController = LocalePreferenceController();
    final graph = DailyAccessTestGraph();
    dailyService = _DelayableDailyWisdomAccessService(
      repository: graph.repository,
    );
    widgetService = _RecordingWidgetSnapshotService();
    coordinator = WidgetPresentationSyncCoordinator(
      appearanceController: appearanceController,
      localeController: localeController,
      dailyWisdomAccessService: dailyService,
      widgetSnapshotService: widgetService,
      // A small, fully controlled catalog rather than the real 603-wisdom
      // one, so "missing catalog entry" vs. "present catalog entry" is
      // deterministic and never depends on real content.
      wisdomPresentation: const WisdomLocalizationResolver(
        localizedCatalog: {
          'tr': {'w1': 'Türkçe metin.'},
        },
      ),
    );
    extraCoordinator = null;
  });

  tearDown(() {
    coordinator.dispose();
    extraCoordinator?.dispose();
    appearanceController.dispose();
    localeController.dispose();
    TestWidgetsFlutterBinding.instance.platformDispatcher
        .clearLocaleTestValue();
  });

  /// Starts the coordinator with an immediate (non-delayed) status, so the
  /// launch-triggered initial reconciliation resolves and publishes right
  /// away without interfering with a test's own delayed-completer scenario
  /// below. Always leaves [widgetService.calls] cleared afterward.
  Future<void> startAndSettle() async {
    coordinator.start();
    await pumpEventQueue();
    widgetService.calls.clear();
  }

  group('ownership and lifecycle', () {
    test('start() is safe against duplicate calls', () async {
      coordinator.start();
      await pumpEventQueue();
      final countAfterFirstStart = dailyService.statusCallCount;
      coordinator.start();
      await pumpEventQueue();
      expect(dailyService.statusCallCount, countAfterFirstStart);
    });

    test('dispose() is safe against duplicate calls', () async {
      await startAndSettle();
      coordinator.dispose();
      expect(coordinator.dispose, returnsNormally);
    });

    // 6. Initial ready status publishes silence with current presentation.
    test('initial ready status publishes silence with current presentation',
        () async {
      dailyService.nextStatus = const DailyWisdomStatus(isReady: true);
      coordinator.start();
      await pumpEventQueue();

      expect(widgetService.calls, hasLength(1));
      final call = widgetService.calls.single as _RecordedPublishSilence;
      expect(call.appearanceMode, EastAppearanceMode.light);
      expect(call.localeOverrideTag, isNull);
    });

    // 10. Resume triggers reconciliation.
    test('a foreground resume triggers reconciliation', () async {
      await startAndSettle();
      dailyService.nextStatus = const DailyWisdomStatus(isReady: true);

      TestWidgetsFlutterBinding.instance
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumpEventQueue();

      expect(widgetService.calls, hasLength(1));
      expect(widgetService.calls.single, isA<_RecordedPublishSilence>());
    });
  });

  group('newest-wins ordering', () {
    // 1. Locale A -> B while A's status is delayed: only B publishes.
    test('locale A -> B while A status is delayed: only B publishes', () async {
      await startAndSettle();

      // Queued *before* triggering each change: `status()` checks its
      // pending-completer queue synchronously, at the exact moment
      // `notifyListeners()` -> `_reconcile()` reaches it (still within the
      // same synchronous call stack as `setExplicitLocale` itself, since
      // nothing yields to the event loop before that point) -- queuing
      // after the trigger would miss the window and fall through to the
      // immediate default status instead.
      final completerA = dailyService.queueDelayed();
      unawaited(localeController.setExplicitLocale(const Locale('tr'))); // A
      await pumpEventQueue();

      final completerB = dailyService.queueDelayed();
      unawaited(localeController.setExplicitLocale(const Locale('ja'))); // B
      await pumpEventQueue();

      completerA.complete(const DailyWisdomStatus(isReady: true));
      await pumpEventQueue();
      completerB.complete(const DailyWisdomStatus(isReady: true));
      await pumpEventQueue();

      expect(widgetService.calls, hasLength(1));
      final call = widgetService.calls.single as _RecordedPublishSilence;
      expect(call.localeOverrideTag, 'ja');
    });

    // 2. Rapid A -> B -> C: only C publishes.
    test('rapid locale A -> B -> C: only C publishes', () async {
      await startAndSettle();

      // All three queued first, then all three changes fired back-to-back
      // with no intervening await -- each `setExplicitLocale` call's
      // synchronous `notifyListeners()` -> `_reconcile()` -> `status()`
      // chain consumes the queue strictly in FIFO order before the next
      // line runs, so completerA/B/C map to generations A/B/C exactly.
      final completerA = dailyService.queueDelayed();
      final completerB = dailyService.queueDelayed();
      final completerC = dailyService.queueDelayed();
      unawaited(localeController.setExplicitLocale(const Locale('tr'))); // A
      unawaited(localeController.setExplicitLocale(const Locale('ja'))); // B
      unawaited(localeController.setExplicitLocale(const Locale('ar'))); // C
      await pumpEventQueue();

      completerC.complete(const DailyWisdomStatus(isReady: true));
      completerB.complete(const DailyWisdomStatus(isReady: true));
      completerA.complete(const DailyWisdomStatus(isReady: true));
      await pumpEventQueue();

      expect(widgetService.calls, hasLength(1));
      final call = widgetService.calls.single as _RecordedPublishSilence;
      expect(call.localeOverrideTag, 'ar');
    });

    // 3. Appearance change during a pending locale reconciliation: final
    // publication contains the newest appearance and the correct (already
    // up-to-date) locale, never a cross-generation mix.
    test(
        'appearance change during a pending locale reconciliation never '
        'mixes generations', () async {
      await startAndSettle();

      final localeCompleter = dailyService.queueDelayed();
      unawaited(localeController.setExplicitLocale(const Locale('tr')));
      await pumpEventQueue();

      final appearanceCompleter = dailyService.queueDelayed();
      unawaited(appearanceController.setMode(EastAppearanceMode.dark));
      await pumpEventQueue();

      // The stale, locale-only generation resolving later must never
      // publish -- proves no cross-generation mixing is even possible.
      localeCompleter.complete(const DailyWisdomStatus(isReady: true));
      await pumpEventQueue();
      appearanceCompleter.complete(const DailyWisdomStatus(isReady: true));
      await pumpEventQueue();

      expect(widgetService.calls, hasLength(1));
      final call = widgetService.calls.single as _RecordedPublishSilence;
      expect(call.appearanceMode, EastAppearanceMode.dark);
      expect(call.localeOverrideTag, 'tr');
    });

    // 4. Dispose during an in-flight (delayed) reconciliation: no
    // publication afterward.
    test('dispose during a delayed reconciliation publishes nothing after',
        () async {
      await startAndSettle();

      final completer = dailyService.queueDelayed();
      unawaited(localeController.setExplicitLocale(const Locale('tr')));
      await pumpEventQueue();

      coordinator.dispose();
      completer.complete(const DailyWisdomStatus(isReady: true));
      await pumpEventQueue();

      expect(widgetService.calls, isEmpty);
    });

    // 5. Re-selecting an already-active preference: no coordinator/platform
    // publication.
    test('re-selecting an already-active preference publishes nothing',
        () async {
      await startAndSettle();
      final callCountBefore = dailyService.statusCallCount;

      // Appearance already defaults to light; locale already defaults to
      // System Default (null) -- both re-selections below are genuine no-ops
      // at the controller level, so neither ever notifies this coordinator.
      unawaited(appearanceController.setMode(EastAppearanceMode.light));
      unawaited(localeController.setExplicitLocale(null));
      await pumpEventQueue();

      expect(dailyService.statusCallCount, callCountBefore);
      expect(widgetService.calls, isEmpty);
    });

    // 11. Fresh reveal supersedes a delayed reconciliation and never calls
    // status() again.
    test(
        'a fresh reveal supersedes a delayed reconciliation without '
        'calling status() again', () async {
      await startAndSettle();

      dailyService.queueDelayed(); // never completed in this test
      unawaited(localeController.setExplicitLocale(const Locale('tr')));
      await pumpEventQueue();
      final statusCallsBeforeFreshReveal = dailyService.statusCallCount;

      coordinator.notifyFreshReveal(
        wisdomId: 'w1',
        text: 'English fallback.',
        unlockAt: DateTime.utc(2041, 1, 1),
      );
      await pumpEventQueue();

      expect(dailyService.statusCallCount, statusCallsBeforeFreshReveal);
      expect(widgetService.calls, hasLength(1));
      final call = widgetService.calls.single as _RecordedPublishRevealed;
      // Resolved through the explicit 'tr' override active at the time of
      // the fresh reveal, via wisdomId -- never the raw persisted text.
      expect(call.text, 'Türkçe metin.');
      expect(call.localeOverrideTag, 'tr');
    });
  });

  group('presentation resolution', () {
    // 7. Initial locked status resolves by wisdomId in the effective
    // locale.
    test(
        'a locked status resolves its text by wisdomId in the explicit '
        'locale', () async {
      unawaited(localeController.setExplicitLocale(const Locale('tr')));
      await pumpEventQueue();
      final unlockAt = DateTime.utc(2041, 1, 1);
      dailyService.nextStatus = DailyWisdomStatus(
        isReady: false,
        unlockAt: unlockAt,
        lockedText: 'English fallback.',
        wisdomId: 'w1',
      );

      coordinator.start();
      await pumpEventQueue();

      expect(widgetService.calls, hasLength(1));
      final call = widgetService.calls.single as _RecordedPublishRevealed;
      expect(call.text, 'Türkçe metin.');
      expect(call.unlockAt, unlockAt);
      expect(call.localeOverrideTag, 'tr');
    });

    // 8. Missing localized catalog entry falls back to persisted text.
    test('a wisdomId absent from the catalog falls back to persisted text',
        () async {
      unawaited(localeController.setExplicitLocale(const Locale('tr')));
      await pumpEventQueue();
      dailyService.nextStatus = DailyWisdomStatus(
        isReady: false,
        unlockAt: DateTime.utc(2041, 1, 1),
        lockedText: 'Persisted original text.',
        wisdomId: 'not-in-any-catalog',
      );

      coordinator.start();
      await pumpEventQueue();

      final call = widgetService.calls.single as _RecordedPublishRevealed;
      expect(call.text, 'Persisted original text.');
    });

    // 9. System Default sends localeOverrideTag null while resolving
    // revealed text from the current supported system locale.
    test(
        'System Default sends a null override while still resolving text '
        'from the current system locale', () async {
      TestWidgetsFlutterBinding.instance.platformDispatcher.localeTestValue =
          const Locale('tr');
      dailyService.nextStatus = DailyWisdomStatus(
        isReady: false,
        unlockAt: DateTime.utc(2041, 1, 1),
        lockedText: 'English fallback.',
        wisdomId: 'w1',
      );

      coordinator.start();
      await pumpEventQueue();

      final call = widgetService.calls.single as _RecordedPublishRevealed;
      expect(call.localeOverrideTag, isNull);
      expect(call.text, 'Türkçe metin.');
    });
  });
}
