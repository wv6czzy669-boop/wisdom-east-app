import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/latest_request_guard.dart';
import '../controllers/ritual_flow_controller.dart';
import '../models/favorite_item.dart';
import '../models/pending_daily_wisdom_reveal.dart';
import '../services/app_services.dart' as app_services;
import '../services/audio_service.dart';
import '../services/daily_wisdom_access_service.dart';
import '../services/kept_discovery_hint_service.dart';
import '../services/saved_reflections_service.dart';
import '../services/storage_service.dart';
import '../services/wisdom_notification_service.dart';
import '../services/wisdom_selector.dart';
import '../services/wisdom_share_service.dart';
import '../theme/muted_text_color.dart';
import '../utils/countdown_formatter.dart';
import '../utils/date_formatter.dart';
import '../widgets/grain_painter.dart';
import '../widgets/home/top_nav_ring.dart';
import 'keeper_screen.dart';
import 'objects_screen.dart';
import 'saved_reflections_screen.dart';
import 'settings_screen.dart';

part '../widgets/home/home_ritual_widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.clock,
    this.storageService,
    this.dailyWisdomAccessService,
    this.savedReflectionsService,
    this.wisdomShareService,
    this.wisdomNotificationService,
    this.keptDiscoveryHintService,
    this.dailyWisdomOperationTimeout = const Duration(seconds: 8),
    this.dailyWisdomStatusTimeout =
        DailyWisdomAccessService.defaultStatusTimeout,
  });

  final WisdomClock? clock;
  final StorageService? storageService;
  final DailyWisdomAccessService? dailyWisdomAccessService;
  final SavedReflectionsService? savedReflectionsService;
  final WisdomShareHandler? wisdomShareService;
  final WisdomNotificationService? wisdomNotificationService;
  final KeptDiscoveryHintService? keptDiscoveryHintService;
  final Duration dailyWisdomOperationTimeout;
  final Duration dailyWisdomStatusTimeout;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  int screenStep = 0;

  String currentText = "EAST.";

  double textOpacity = 1.0;
  double saveControlOpacity = 0.0;
  double postRevealMessageOpacity = 0.0;
  double textScale = 1.0;
  double revealGlowOpacity = 0.0;
  double backgroundDepth = 0.0;
  double pauseFeelOpacity = 0.0;

  bool transitionInProgress = false;
  bool _transitionLock = false;
  int flowSessionId = 0;
  bool navigationInProgress = false;
  bool saveInteractionEnabled = false;
  bool _reduceMotion = false;
  bool _isInBlackSilence = false;
  bool _dailyStatusResolved = false;
  bool _dailyLockActive = false;
  bool _showingLockedWisdom = false;
  bool _saveOperationInProgress = false;
  bool _shareInProgress = false;
  bool _notificationPermissionOfferShowing = false;
  bool _notificationPermissionOfferScheduled = false;
  bool _revealPersistenceNeedsRetry = false;
  DateTime? _pendingRevealBoundaryForRetry;
  DateTime? _pendingNotificationUnlockAt;
  String? _lockedWisdomText;

  // Item 5 — Home left-swipe opens Kept. Cumulative drag offset for the
  // current gesture, reset on every swipe start; `_homeSwipeHandled` makes
  // sure a single gesture can only trigger navigation once.
  double _homeSwipeDx = 0;
  double _homeSwipeDy = 0;
  bool _homeSwipeHandled = false;

  // Item 6 — Save -> Kept micro-guidance (one-time discovery hint).
  String _keptDiscoveryHintText = '';
  double _keptDiscoveryHintOpacity = 0.0;
  bool _keptDiscoveryBreathActive = false;
  bool _keptIconEmphasized = false;
  Timer? _keptDiscoveryShowTimer;
  Timer? _keptDiscoveryHideTimer;
  Timer? _keptDiscoverySavedTextTimer;
  // Update 1D: the top-right Kept teaching breath chain's own timer (start
  // delay, each breath's own duration, and the pause between breaths).
  Timer? _keptIconEmphasisTimer;
  // Update 1D: how many of the 5 top-right teaching breaths have started
  // so far in the current activation.
  int _keptTopNavBreathCycle = 0;
  // Update 1B: the center save-ring breath chain's own timer (first-breath
  // delay, each breath's own duration, and the pause between breaths).
  // Renamed in spirit from the old single one-shot "breath reset" timer,
  // which this field replaces — it now drives all 4 repeated breaths, not
  // just a single reset-to-false.
  Timer? _keptDiscoveryBreathResetTimer;
  // Update 1B: how many of the 4 center save-ring breaths have started so
  // far in the current presentation.
  int _keptDiscoveryBreathCycle = 0;
  int _keptDiscoverySessionId = 0;
  bool _keptDiscoveryOfferedForCurrentWisdom = false;

  // Update 1A/B: the discovery hint text remains visible for a total of
  // 7.5 seconds (replacing the previous ~4s window) unless a successful
  // save interrupts it first.
  static const Duration _keptDiscoveryHintDuration = Duration(
    milliseconds: 7500,
  );
  // Update 1B: exactly 4 center save-ring breaths, ~1.2s each (matching
  // `_SaveRingBreath`'s own animation duration), with a calm ~200ms pause
  // between each. The first breath begins ~250ms after the discovery text
  // begins appearing. 4 * 1200ms + 3 * 200ms = 5400ms, comfortably within
  // the 7.5s text window.
  static const int _keptDiscoveryBreathCount = 4;
  static const Duration _keptDiscoveryBreathFirstDelay = Duration(
    milliseconds: 250,
  );
  static const Duration _keptDiscoveryBreathDuration = Duration(
    milliseconds: 1200,
  );
  static const Duration _keptDiscoveryBreathPause = Duration(
    milliseconds: 200,
  );

  // Update 1C: "Kept." remains visible for approximately 1.3 seconds
  // (replacing the previous ~900ms window).
  static const Duration _keptDiscoverySavedTextDuration = Duration(
    milliseconds: 1300,
  );

  // Update 1D: exactly 5 top-right Kept teaching breaths, ~1.05s each
  // (matching `_KeptTopNavBreath`'s own animation duration), with a calm
  // ~165ms pause between each, starting ~350ms after a successful save
  // that completes discovery for the first time.
  static const int _keptTopNavBreathCount = 5;
  static const Duration _keptTopNavBreathStartDelay = Duration(
    milliseconds: 350,
  );
  static const Duration _keptTopNavBreathDuration = Duration(
    milliseconds: 1050,
  );
  static const Duration _keptTopNavBreathPause = Duration(
    milliseconds: 165,
  );

  final ritualFlowController = const RitualFlowController();
  final accessRefreshGuard = LatestRequestGuard();

  int delayedCallbackSession = 0;

  void invalidateDelayedCallbacks() {
    delayedCallbackSession++;
  }

  bool isCurrentFlow(int sessionId) {
    return mounted && sessionId == flowSessionId;
  }

  void interruptRitualForNavigation() {
    flowSessionId++;
    invalidateDelayedCallbacks();
    unawaited(audioService.stop());
    transitionInProgress = false;
    _transitionLock = false;
    _isInBlackSilence = false;
    // Item 6: any meaningful Home navigation dismisses the discovery hint
    // immediately, without altering the navigation action itself.
    _dismissKeptDiscoveryHint();
  }

  void restoreStableRitualState() {
    if (!mounted) return;

    wisdomRevealController.stop();
    wisdomRevealController.value = wisdomRevealed ? 1.0 : 0.0;
    askFadeController.stop();
    askFadeController.value = 1.0;

    setState(() {
      transitionInProgress = false;
      _transitionLock = false;
      _isInBlackSilence = false;
      textOpacity = 1.0;
      textScale = 1.0;

      if (screenStep == 0) {
        backgroundDepth = 0.0;
      } else {
        backgroundDepth = wisdomRevealed ? 0.30 : 0.0;
      }

      if (!onPauseScreen) {
        pauseFeelOpacity = 0.0;
      }

      if (wisdomRevealed) {
        saveControlOpacity = 1.0;
        postRevealMessageOpacity = 1.0;
        revealGlowOpacity = 0.10;
      } else {
        saveControlOpacity = 0.0;
        saveInteractionEnabled = false;
        postRevealMessageOpacity = 0.0;
        revealGlowOpacity = 0.0;
      }
    });
  }

  List<FavoriteItem> favorites = [];

  bool isKeeper = false;

  late AnimationController pulseController;
  late final AnimationController wisdomRevealController;
  late final Animation<double> wisdomRevealAnimation;
  late final AnimationController askFadeController;
  late final Animation<double> askFadeAnimation;

  Timer? countdownTimer;

  final AudioService audioService = AudioService();
  late final StorageService storageService;
  late final DailyWisdomAccessService dailyWisdomAccessService;
  late final SavedReflectionsService savedReflectionsService;
  late final WisdomShareHandler wisdomShareService;
  late final WisdomNotificationService wisdomNotificationService;
  late final KeptDiscoveryHintService keptDiscoveryHintService;
  final GlobalKey _wisdomShareOriginKey = GlobalKey();
  Timer? _notificationPermissionOfferTimer;

  void startCountdownTimer() {
    if (countdownTimer?.isActive ?? false) return;

    countdownTimer?.cancel();
    countdownTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) {
        if (!mounted) return;
        updateNextWisdomMessage();
      },
    );
  }

  void stopCountdownTimer() {
    countdownTimer?.cancel();
    countdownTimer = null;
  }

  String nextWisdomMessage = "";

  final WisdomSelectorService wisdomSelector = WisdomSelectorService();

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    app_services.purchaseService.addListener(_syncKeeperStatus);
    storageService = widget.storageService ?? app_services.storageService;
    dailyWisdomAccessService = widget.dailyWisdomAccessService ??
        app_services.createDailyWisdomAccessService(
          clock: widget.clock,
          statusTimeout: widget.dailyWisdomStatusTimeout,
        );
    savedReflectionsService =
        widget.savedReflectionsService ?? app_services.savedReflectionsService;
    wisdomShareService =
        widget.wisdomShareService ?? app_services.wisdomShareService;
    wisdomNotificationService = widget.wisdomNotificationService ??
        app_services.wisdomNotificationService;
    keptDiscoveryHintService = widget.keptDiscoveryHintService ??
        app_services.keptDiscoveryHintService;

    pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
    )..repeat(reverse: true);

    wisdomRevealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    wisdomRevealAnimation = CurvedAnimation(
      parent: wisdomRevealController,
      curve: Curves.easeOutCubic,
    );
    wisdomRevealController.addStatusListener(_handleWisdomRevealStatus);
    askFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1250),
      value: 1.0,
    );
    askFadeAnimation = CurvedAnimation(
      parent: askFadeController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    loadInitialState().catchError((_) {});
    startCountdownTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (_reduceMotion == reduceMotion) return;

    _reduceMotion = reduceMotion;
    if (_reduceMotion) {
      pulseController.stop();
      pulseController.value = 0.5;
    } else if (WidgetsBinding.instance.lifecycleState ==
            AppLifecycleState.resumed &&
        !pulseController.isAnimating) {
      pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    flowSessionId++;
    invalidateDelayedCallbacks();
    accessRefreshGuard.invalidate();

    WidgetsBinding.instance.removeObserver(this);
    app_services.purchaseService.removeListener(_syncKeeperStatus);
    stopCountdownTimer();
    _notificationPermissionOfferTimer?.cancel();
    _cancelAllDiscoveryTimers();
    pulseController.dispose();
    wisdomRevealController.dispose();
    askFadeController.dispose();
    audioService.dispose();
    super.dispose();
  }

  Future<void> _syncKeeperStatus() async {
    if (!mounted) return;
    await loadKeeperStatus();
    await updateNextWisdomMessage();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      flowSessionId++;
      invalidateDelayedCallbacks();
      unawaited(audioService.stop());
      stopCountdownTimer();
      // Correction pass Item 3: a lifecycle interruption invalidates any
      // pending discovery-hint timer immediately, rather than relying only
      // on the flow-session check the timer callback performs when it
      // eventually fires.
      _dismissKeptDiscoveryHint();

      if (pulseController.isAnimating) {
        pulseController.stop();
      }
      wisdomRevealController.stop();

      restoreStableRitualState();
      return;
    }

    if (state == AppLifecycleState.resumed) {
      if (!mounted) return;

      if (!_reduceMotion && !pulseController.isAnimating) {
        pulseController.repeat(reverse: true);
      }

      startCountdownTimer();
      unawaited(_resumeAccessState());
    }
  }

  bool get onPauseScreen => ritualFlowController.isPauseScreen(screenStep);
  bool get onHeartScreen => ritualFlowController.isHeartScreen(screenStep);
  bool get wisdomRevealed => ritualFlowController.isWisdomRevealed(screenStep);
  bool get onLockedCountdown => screenStep == 5;
  bool get mainRitualActionSemanticsEnabled {
    if (navigationInProgress || transitionInProgress || _transitionLock) {
      return false;
    }
    if (screenStep == 0) return _dailyStatusResolved;
    if (screenStep == 1 || screenStep == 2) return true;
    return wisdomRevealed && _revealPersistenceNeedsRetry;
  }

  bool get hideMainRitualContentSemantics {
    return _isInBlackSilence || textOpacity <= 0.01;
  }

  String? get mainRitualSemanticLabel {
    if (hideMainRitualContentSemantics) return null;
    if (screenStep == 0) return 'EAST.';
    if (onPauseScreen) {
      return pauseFeelOpacity < 1.0 ? 'Pause.' : 'Pause. Feel.';
    }
    if (onHeartScreen) return 'Ask from your heart.';
    if (wisdomRevealed && _revealPersistenceNeedsRetry) {
      return 'Try keeping this wisdom again.';
    }
    return null;
  }

  Future<void> loadInitialState() async {
    // Build 25 -> Build 26 upgrade: one-time reveal-identity backfill.
    // Must complete (or fail nonfatally) before updateNextWisdomMessage or
    // any other step below reads the authoritative daily record, so the
    // rest of startup never observes a pre-backfill record.
    try {
      await dailyWisdomAccessService.backfillRevealIdIfNeeded();
    } catch (_) {
      // Existing Build 25 daily-access behavior remains usable.
    }
    await loadFavorites();
    await loadKeeperStatus();
    await updateNextWisdomMessage();
    await synchronizeUnlockNotification();
  }

  Future<void> loadKeeperStatus() async {
    final keeperValue = app_services.purchaseService.isKeeper;

    if (!mounted) return;

    setState(() {
      isKeeper = keeperValue;
    });
  }

  Future<void> _resumeAccessState() async {
    await updateNextWisdomMessage();
    await synchronizeUnlockNotification();
    final unlockAt = _pendingNotificationUnlockAt;
    if (unlockAt != null) {
      _queueNotificationPermissionOffer(unlockAt);
    }
  }

  void showEastSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF111111),
        duration: const Duration(milliseconds: 1400),
        content: Text(
          message,
          style: _homeWisdomStyle(17),
        ),
      ),
    );
  }

  void _handleWisdomRevealStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted || !wisdomRevealed) {
      return;
    }
    setState(() {});
  }

  Future<void> saveDailyArchive(String text) async {
    await storageService.saveDailyArchive(
      text: text,
      today: formattedToday(),
    );
  }

  Future<void> handleMainTap() async {
    if (transitionInProgress || _transitionLock) return;

    invalidateDelayedCallbacks();

    if (screenStep == 0) {
      HapticFeedback.selectionClick();

      final launchFlowSession = flowSessionId;
      transitionInProgress = true;
      await updateNextWisdomMessage();

      if (!mounted || launchFlowSession != flowSessionId) return;

      transitionInProgress = false;

      if (!_dailyStatusResolved) return;

      if (_dailyLockActive) {
        final lockedWisdomText = _lockedWisdomText;
        if (lockedWisdomText == null) {
          await transitionToText(
            nextWisdomMessage,
            nextStep: 5,
          );
        } else {
          await transitionToExistingWisdom(lockedWisdomText);
        }
        return;
      }

      final callbackSession = delayedCallbackSession;
      final callbackFlowSession = flowSessionId + 1;

      Future.delayed(
        const Duration(milliseconds: 1200),
        () {
          if (!mounted) return;
          if (callbackSession != delayedCallbackSession) return;
          if (callbackFlowSession != flowSessionId) return;
          audioService.playPauseSound();
        },
      );

      await transitionToText(
        "Pause.",
        nextStep: 1,
      );

      return;
    }

    if (screenStep == 1) {
      HapticFeedback.lightImpact();

      if (pauseFeelOpacity < 1.0) {
        final callbackSession = delayedCallbackSession;
        final callbackFlowSession = flowSessionId + 1;

        Future.delayed(
          const Duration(milliseconds: 200),
          () {
            if (!mounted) return;
            if (callbackSession != delayedCallbackSession) return;
            if (callbackFlowSession != flowSessionId) return;
            audioService.playFeelSound();
          },
        );
        await revealFeelBesidePause();
      } else {
        final callbackSession = delayedCallbackSession;
        final callbackFlowSession = flowSessionId + 1;

        Future.delayed(
          const Duration(milliseconds: 1100),
          () {
            if (!mounted) return;
            if (callbackSession != delayedCallbackSession) return;
            if (callbackFlowSession != flowSessionId) return;
            audioService.playHeartSound();
          },
        );
        await transitionToText(
          "Ask from your heart.",
          nextStep: 2,
        );
      }

      return;
    }

    if (screenStep == 2) {
      await revealWisdom();
      return;
    }

    if (wisdomRevealed && _revealPersistenceNeedsRetry) {
      await retryRevealedWisdomCommit();
      return;
    }
  }

  Future<void> revealFeelBesidePause() async {
    if (transitionInProgress) return;

    final currentFlow = ++flowSessionId;
    transitionInProgress = true;

    try {
      if (!isCurrentFlow(currentFlow)) return;

      setState(() {
        pauseFeelOpacity = 1.0;
      });

      await Future.delayed(const Duration(milliseconds: 1250));

      if (!isCurrentFlow(currentFlow)) return;
    } finally {
      if (mounted && currentFlow == flowSessionId) {
        setState(() {
          transitionInProgress = false;
        });
      }
    }
  }

  Future<void> transitionToText(
    String newText, {
    required int nextStep,
  }) async {
    if (transitionInProgress) return;

    final currentFlow = ++flowSessionId;
    transitionInProgress = true;

    try {
      if (!isCurrentFlow(currentFlow)) return;

      setState(() {
        textOpacity = 0.0;
        saveControlOpacity = 0.0;
        saveInteractionEnabled = false;
        postRevealMessageOpacity = 0.0;
        revealGlowOpacity = 0.0;
        backgroundDepth =
            ritualFlowController.transitionBackgroundDepth(nextStep);
        textScale = 1.0;
      });

      final fadeOutDuration = onPauseScreen && nextStep == 2
          ? const Duration(milliseconds: 1250)
          : ritualFlowController.transitionFadeOutDuration(nextStep);

      await Future.delayed(fadeOutDuration);

      if (!isCurrentFlow(currentFlow)) return;

      if (nextStep == 2) {
        askFadeController.stop();
        askFadeController.value = 1.0;
      }

      setState(() {
        currentText = newText;
        screenStep = nextStep;
        if (nextStep != 1) {
          pauseFeelOpacity = 0.0;
        }
      });

      await Future.wait<void>([
        WidgetsBinding.instance.endOfFrame,
        Future<void>.delayed(const Duration(milliseconds: 220)),
      ]);

      if (!isCurrentFlow(currentFlow)) return;

      setState(() {
        textOpacity = 1.0;
        textScale = 1.0;
      });

      await Future.delayed(
        ritualFlowController.transitionSettleDuration(nextStep),
      );

      if (!isCurrentFlow(currentFlow)) return;
    } finally {
      if (mounted && currentFlow == flowSessionId) {
        setState(() {
          transitionInProgress = false;
        });
      }
    }
  }

  Future<void> transitionToExistingWisdom(String text) async {
    if (transitionInProgress) return;

    final currentFlow = ++flowSessionId;
    transitionInProgress = true;

    try {
      if (!isCurrentFlow(currentFlow)) return;

      setState(() {
        textOpacity = 0.0;
        saveControlOpacity = 0.0;
        saveInteractionEnabled = false;
        postRevealMessageOpacity = 0.0;
        revealGlowOpacity = 0.0;
        textScale = 1.0;
      });

      await Future.delayed(
        ritualFlowController.transitionFadeOutDuration(4),
      );

      if (!isCurrentFlow(currentFlow)) return;

      wisdomRevealController.stop();
      wisdomRevealController.value = 0.0;

      setState(() {
        currentText = text;
        screenStep = 4;
        _showingLockedWisdom = true;
        textOpacity = 1.0;
        textScale = 1.0;
        backgroundDepth = 0.30;
        revealGlowOpacity = 0.10;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isCurrentFlow(currentFlow) || !wisdomRevealed) return;
        wisdomRevealController.forward(from: 0.0);
      });

      await Future.delayed(const Duration(milliseconds: 900));

      if (!isCurrentFlow(currentFlow)) return;

      setState(() {
        saveControlOpacity = 1.0;
      });

      await Future.delayed(const Duration(milliseconds: 520));

      if (!isCurrentFlow(currentFlow)) return;

      setState(() {
        postRevealMessageOpacity = 1.0;
      });
    } finally {
      if (mounted && currentFlow == flowSessionId) {
        setState(() {
          transitionInProgress = false;
        });
      }
    }
  }

  Future<void> updateNextWisdomMessage() async {
    final refreshGeneration = accessRefreshGuard.begin();

    final DailyWisdomStatus status;

    try {
      status = await dailyWisdomAccessService.status();
    } catch (_) {
      if (_canCommitAccessRefresh(refreshGeneration)) {
        setState(() {
          nextWisdomMessage = "";
          _dailyStatusResolved = false;
        });
      }
      return;
    }

    if (status.isReady) {
      if (_canCommitAccessRefresh(refreshGeneration)) {
        setState(() {
          _dailyStatusResolved = true;
          _dailyLockActive = false;
          _lockedWisdomText = null;
          nextWisdomMessage =
              status.unlockAt == null ? "" : "A new wisdom is ready.";

          if (onLockedCountdown || _showingLockedWisdom) {
            screenStep = 0;
            _showingLockedWisdom = false;
            currentText = "EAST.";
            textOpacity = 1.0;
            textScale = 1.0;
            backgroundDepth = 0.0;
          }
        });
      }
      return;
    }

    String? lockedWisdomText;
    final text = status.lockedText?.trim();
    if (text != null &&
        text.isNotEmpty &&
        text != DailyWisdomAccessService.corruptRecordRecoveryText) {
      lockedWisdomText = status.lockedText;
    }

    final message = CountdownFormatter.silenceMessage(status.remaining!);

    if (_canCommitAccessRefresh(refreshGeneration)) {
      setState(() {
        _dailyStatusResolved = true;
        _dailyLockActive = true;
        _lockedWisdomText = lockedWisdomText;
        nextWisdomMessage = message;
        if (onLockedCountdown) {
          currentText = message;
        }
      });
    }
  }

  bool _canCommitAccessRefresh(int generation) {
    return mounted && accessRefreshGuard.isCurrent(generation);
  }

  Future<DailyWisdomPreparedReveal> prepareDailyWisdomReveal() {
    return dailyWisdomAccessService.prepareReveal(
      selectWisdom: () => wisdomSelector.select()["text"] as String,
    );
  }

  void finishCommittedDailyWisdom(DailyWisdomAccess access) {
    if (access.isNew) {
      unawaited(
        saveDailyArchive(access.text).catchError((_) {
          // Archiving is best-effort and must never hide a persisted wisdom.
        }),
      );
    }

    unawaited(
      updateNextWisdomMessage().catchError((_) {
        // Countdown copy is noncritical after the daily wisdom is persisted.
      }),
    );

    final unlockAt = access.unlockAt;
    if (unlockAt != null) {
      unawaited(
        wisdomNotificationService.scheduleFromAuthoritativeUnlock(unlockAt),
      );
      if (access.isNew) {
        _pendingNotificationUnlockAt = unlockAt;
      }
    }
  }

  Future<void> synchronizeUnlockNotification() async {
    try {
      final status = await dailyWisdomAccessService.status();
      await wisdomNotificationService.synchronizeWithStatus(status);
    } catch (_) {
      // Notification synchronization must not affect daily access.
    }
  }

  void _queueNotificationPermissionOffer(
    DateTime unlockAt, {
    Duration delay = const Duration(seconds: 6),
  }) {
    if (_notificationPermissionOfferScheduled ||
        _notificationPermissionOfferShowing) {
      return;
    }

    _notificationPermissionOfferScheduled = true;
    final offerFlow = flowSessionId;
    _notificationPermissionOfferTimer = Timer(
      delay,
      () {
        _notificationPermissionOfferTimer = null;
        // Correction: a real Mac run showed the discovery hint's display
        // count incrementing while the native permission Future was still
        // genuinely pending. Root cause: `_notificationPermissionOfferScheduled`
        // used to be cleared to `false` right here, *before*
        // `_showNotificationPermissionOffer`'s own `shouldOfferPermission()`
        // check (its first `await`) had resolved and set
        // `_notificationPermissionOfferShowing = true` — leaving a real
        // window, between this Timer firing and that first `await`
        // resolving, where *both* guard flags were `false` while the offer
        // was still genuinely in flight. `_maybeOfferKeptDiscoveryHint()`'s
        // own guard (and `_presentKeptDiscoveryHint`'s re-check) only look
        // at these two booleans, so anything reaching either check during
        // that window was wrongly let through.
        //
        // The fix: `_notificationPermissionOfferScheduled` is no longer
        // cleared here at all, and `_notificationPermissionOfferShowing` is
        // set `true` synchronously, right here, before this callback's own
        // first `await` — so from the moment this offer was queued (above)
        // through to the single `finally` in
        // `_runQueuedNotificationPermissionOffer` below, at least one of
        // the two flags is continuously `true`, with no tick where both
        // are `false`. Both are cleared together, exactly once, in that
        // `finally` — the sole completion path, reached regardless of
        // which branch is taken — which is also the single place the
        // discovery hint is retried afterward.
        _notificationPermissionOfferShowing = true;
        unawaited(_runQueuedNotificationPermissionOffer(offerFlow, unlockAt));
      },
    );
  }

  Future<void> _runQueuedNotificationPermissionOffer(
    int offerFlow,
    DateTime unlockAt,
  ) async {
    try {
      if (!mounted ||
          offerFlow != flowSessionId ||
          _pendingNotificationUnlockAt != unlockAt ||
          !wisdomRevealed ||
          transitionInProgress ||
          navigationInProgress ||
          _isInBlackSilence) {
        return;
      }
      await _showNotificationPermissionOffer(unlockAt);
    } finally {
      _notificationPermissionOfferScheduled = false;
      _notificationPermissionOfferShowing = false;
      // The permission flow — native prompt, "nothing to offer", or an
      // early guard return above — has now fully resolved one way or
      // another. Retry the discovery hint exactly once, now that both
      // guard flags are clear.
      _maybeOfferKeptDiscoveryHint();
    }
  }

  Future<void> _showNotificationPermissionOffer(DateTime unlockAt) async {
    if (!mounted) return;
    if (!await wisdomNotificationService.shouldOfferPermission()) {
      _pendingNotificationUnlockAt = null;
      // Item 6: no native prompt is coming after all — the caller's own
      // `finally` (in `_runQueuedNotificationPermissionOffer`) clears both
      // guard flags and retries the discovery hint.
      return;
    }
    if (!mounted ||
        !wisdomRevealed ||
        transitionInProgress ||
        navigationInProgress) {
      return;
    }

    try {
      // No application-owned pre-prompt: at this exact existing trigger
      // point, go straight to the native iOS permission request. Only
      // reached when `shouldOfferPermission()` is true (system status
      // notDetermined); authorized/denied never re-request here.
      await wisdomNotificationService.requestPermissionAndSchedule(unlockAt);
      _pendingNotificationUnlockAt = null;
    } catch (_) {
      // Native authorization is always optional and must never affect the
      // ritual.
    }
    // Flag clearing and the discovery-hint retry happen exactly once, in
    // the caller's own `finally` block (`_runQueuedNotificationPermissionOffer`),
    // regardless of which path above was taken.
  }

  // Item 6 — Save -> Kept micro-guidance.
  //
  // Never shown at the same time as the native notification-permission
  // prompt: if one is queued or currently on screen, this returns
  // immediately without scheduling anything. `_showNotificationPermissionOffer`
  // itself calls this again once the native prompt has resolved — granted
  // or denied — so the hint appears ~800-1200ms after that resolution when
  // the wisdom is still eligible and unsaved; `onFullyVisible` below also
  // calls it once the save ring has finished fading in, covering the "no
  // prompt is coming" case. Correction pass Item 3: single-flight — this
  // method may legitimately be reached twice for the same reveal (once
  // from `onFullyVisible`, once from a notification-offer exit path), so
  // the per-wisdom "already offered" flag is claimed *synchronously*,
  // before the only `await` in this method, so a second concurrent call
  // sees it already claimed and returns immediately rather than also
  // resolving `isEligible()` and scheduling a second timer.
  Future<void> _maybeOfferKeptDiscoveryHint() async {
    if (!mounted || !wisdomRevealed) return;
    if (transitionInProgress || _transitionLock || _isInBlackSilence) return;
    if (_revealPersistenceNeedsRetry) return;
    if (navigationInProgress) return;
    if (_shareInProgress || _saveOperationInProgress) return;
    if (isCurrentFavorite()) return;
    if (_keptDiscoveryHintOpacity > 0.0) return;
    if (_keptDiscoveryOfferedForCurrentWisdom) return;
    if (_notificationPermissionOfferScheduled ||
        _notificationPermissionOfferShowing) {
      return;
    }

    // Claim this reveal's one offer attempt now, before the await below,
    // so no second caller can also pass the check above and race to
    // schedule a duplicate presentation.
    _keptDiscoveryOfferedForCurrentWisdom = true;
    final session = ++_keptDiscoverySessionId;
    final currentFlow = flowSessionId;
    final scheduledForText = currentText;

    bool eligible;
    try {
      eligible = await keptDiscoveryHintService.isEligible();
    } catch (_) {
      eligible = false;
    }
    if (!eligible) return;
    // Re-validate after the only await in this method: navigation,
    // disposal, or a new flow session may have invalidated this attempt
    // while `isEligible()` was resolving.
    if (!mounted ||
        session != _keptDiscoverySessionId ||
        currentFlow != flowSessionId) {
      return;
    }

    _keptDiscoveryShowTimer?.cancel();
    _keptDiscoveryShowTimer = Timer(
      const Duration(milliseconds: 1000),
      () => _presentKeptDiscoveryHint(session, currentFlow, scheduledForText),
    );
  }

  // Correction: re-checked at both entry and immediately before commit, so
  // a call blocked by any of these conditions can never be mistaken for one
  // that actually presented (see `_presentKeptDiscoveryHint` below).
  bool _keptDiscoveryPresentationBlocked(
    int session,
    int currentFlow,
    String scheduledForText,
  ) {
    return !mounted ||
        session != _keptDiscoverySessionId ||
        currentFlow != flowSessionId ||
        currentText != scheduledForText ||
        !wisdomRevealed ||
        transitionInProgress ||
        _transitionLock ||
        _isInBlackSilence ||
        navigationInProgress ||
        _saveOperationInProgress ||
        _shareInProgress ||
        _revealPersistenceNeedsRetry ||
        _notificationPermissionOfferScheduled ||
        _notificationPermissionOfferShowing ||
        isCurrentFavorite();
  }

  Future<void> _presentKeptDiscoveryHint(
    int session,
    int currentFlow,
    String scheduledForText,
  ) async {
    if (_keptDiscoveryPresentationBlocked(
      session,
      currentFlow,
      scheduledForText,
    )) {
      return;
    }

    // Step 5's "service still eligible" re-check: `isEligible()` was
    // already true when this timer was scheduled, but discovery may have
    // been completed by some other path during the ~1000ms wait.
    bool eligible;
    try {
      eligible = await keptDiscoveryHintService.isEligible();
    } catch (_) {
      eligible = false;
    }
    if (!eligible) return;

    // Final re-check, immediately before committing to presentation: no
    // further `await` happens between this and the `setState`/
    // `recordDisplayShown()` pair below, so a blocked result can never
    // leave a "recorded but not shown" gap — the previous implementation
    // called `recordDisplayShown()` *before* this second re-check, which
    // meant a blocked/invalidated attempt could still have incremented the
    // display count despite never actually presenting anything.
    if (_keptDiscoveryPresentationBlocked(
      session,
      currentFlow,
      scheduledForText,
    )) {
      return;
    }

    final reduceMotion = _reduceMotion;
    setState(() {
      _keptDiscoveryHintText = 'Keep this wisdom.';
      _keptDiscoveryHintOpacity = 1.0;
      _keptDiscoveryBreathActive = false;
    });
    // Only reached once the hint is actually presented: mark it presented
    // for this wisdom (fire-and-forget, matching `markCompleted()`'s own
    // pattern elsewhere — its in-memory bookkeeping is what other calls in
    // this process observe; the persisted write is best-effort).
    unawaited(keptDiscoveryHintService.recordDisplayShown());

    // Update 1B: exactly 4 center save-ring breaths, the first beginning
    // ~250ms after the text above just appeared. Under Reduce Motion, no
    // breath ever starts (text-only, per Update 1G).
    if (!reduceMotion) {
      _keptDiscoveryBreathCycle = 0;
      _keptDiscoveryBreathResetTimer?.cancel();
      _keptDiscoveryBreathResetTimer = Timer(
        _keptDiscoveryBreathFirstDelay,
        () => _startKeptDiscoveryBreath(session),
      );
    }

    // Update 1A: if the user does not save, keep the hint visible for a
    // total of 7.5s, then fade it.
    _keptDiscoveryHideTimer?.cancel();
    _keptDiscoveryHideTimer = Timer(_keptDiscoveryHintDuration, () {
      if (!mounted || session != _keptDiscoverySessionId) return;
      if (isCurrentFavorite()) return;
      setState(() {
        _keptDiscoveryHintOpacity = 0.0;
      });
    });
  }

  // Update 1B: starts one center save-ring breath (`_keptDiscoveryBreathActive
  // = true`); `_endKeptDiscoveryBreath` (scheduled below) turns it back off
  // after that single breath's own ~1.2s duration and, unless the 4th
  // breath has already played, schedules the next one after a calm ~200ms
  // pause. Guarded by the same `session` id every other discovery timer
  // uses, so a stale chain from a dismissed/replaced reveal can never touch
  // a later reveal's state.
  void _startKeptDiscoveryBreath(int session) {
    if (!mounted || session != _keptDiscoverySessionId) return;
    setState(() => _keptDiscoveryBreathActive = true);
    _keptDiscoveryBreathCycle++;
    _keptDiscoveryBreathResetTimer = Timer(
      _keptDiscoveryBreathDuration,
      () => _endKeptDiscoveryBreath(session),
    );
  }

  void _endKeptDiscoveryBreath(int session) {
    if (!mounted || session != _keptDiscoverySessionId) return;
    setState(() => _keptDiscoveryBreathActive = false);
    if (_keptDiscoveryBreathCycle >= _keptDiscoveryBreathCount) return;
    _keptDiscoveryBreathResetTimer = Timer(
      _keptDiscoveryBreathPause,
      () => _startKeptDiscoveryBreath(session),
    );
  }

  // Correction: single central cancellation point for every discovery-hint
  // UI timer (offer delay, breath reset, hint auto-dismiss, "Kept."
  // dismissal, Kept-icon emphasis reset). Called from `dispose`, navigation
  // interruption and lifecycle pause/inactive (both via
  // `_dismissKeptDiscoveryHint` below), a successful save, and the start of
  // a replacement wisdom reveal — so no discovery timer can ever outlive
  // the state it was scheduled for.
  void _cancelAllDiscoveryTimers() {
    _keptDiscoveryShowTimer?.cancel();
    _keptDiscoveryShowTimer = null;
    _keptDiscoveryHideTimer?.cancel();
    _keptDiscoveryHideTimer = null;
    _keptDiscoverySavedTextTimer?.cancel();
    _keptDiscoverySavedTextTimer = null;
    _keptIconEmphasisTimer?.cancel();
    _keptIconEmphasisTimer = null;
    _keptTopNavBreathCycle = 0;
    _keptDiscoveryBreathResetTimer?.cancel();
    _keptDiscoveryBreathResetTimer = null;
    _keptDiscoveryBreathCycle = 0;
  }

  void _dismissKeptDiscoveryHint() {
    _keptDiscoverySessionId++;
    _cancelAllDiscoveryTimers();
    if (_keptDiscoveryHintOpacity != 0.0 ||
        _keptDiscoveryBreathActive ||
        _keptIconEmphasized) {
      _keptDiscoveryHintOpacity = 0.0;
      _keptDiscoveryBreathActive = false;
      _keptIconEmphasized = false;
    }
  }

  // Called only after `toggleFavorite()` has actually persisted a new save
  // (never on a failed save — see the try block in `toggleFavorite()`,
  // which only reaches this call after the persisted write succeeds).
  //
  // Correction pass Item 1: every successful save permanently completes
  // Kept discovery — in-memory immediately, persisted best-effort — no
  // matter whether the discovery hint happened to be visible for this
  // save. Only the *visual* "Kept." transition is gated on the hint having
  // actually been showing; an ordinary save (hint not visible) still
  // completes discovery, it just shows no new "Kept." feedback for it.
  //
  // Correction: the top-right Kept teaching breath is gated ONLY on
  // `justCompletedDiscovery` — whether *this* save is the one that changes
  // discovery from incomplete to completed (checked below via
  // `keptDiscoveryHintService.isCompleted()` *before* calling
  // `markCompleted()`). `hintWasShowing` must never suppress it: a save
  // made before "Keep this wisdom." ever became visible still completes
  // discovery for the first time, and the locked discovery contract
  // requires the teaching breath to run for that transition too — the
  // teaching animation's own trigger is "discovery just completed," not
  // "the text hint happened to be on screen." `hintWasShowing` is used
  // below only to gate the separate "Kept." text transition, which is a
  // distinct concern.
  Future<void> _onWisdomSuccessfullyKept() async {
    final hintWasShowing = _keptDiscoveryHintOpacity > 0.0;

    // Cancels every pending discovery timer (offer delay, breath chains,
    // any stale hint-hide) before deciding what — if anything — to show
    // next, so nothing from the pre-save state can fire later.
    _cancelAllDiscoveryTimers();
    _keptDiscoverySessionId++;

    bool wasCompletedBefore;
    try {
      wasCompletedBefore = await keptDiscoveryHintService.isCompleted();
    } catch (_) {
      wasCompletedBefore = false;
    }
    // Sets `_completedInMemory` (and persists best-effort) immediately
    // after the read above, so discovery is completed for the remainder of
    // this process regardless of what happens next in this method (see
    // `KeptDiscoveryHintService.markCompleted`).
    unawaited(keptDiscoveryHintService.markCompleted());
    if (!mounted) return;

    final justCompletedDiscovery = !wasCompletedBefore;

    if (hintWasShowing) {
      setState(() {
        _keptDiscoveryHintText = 'Kept.';
        _keptDiscoveryHintOpacity = 1.0;
        _keptDiscoveryBreathActive = false;
      });

      _keptDiscoverySavedTextTimer?.cancel();
      _keptDiscoverySavedTextTimer = Timer(
        _keptDiscoverySavedTextDuration,
        () {
          if (!mounted) return;
          setState(() {
            _keptDiscoveryHintOpacity = 0.0;
          });
        },
      );
    }

    // Update 1D/E: the 5-breath top-right Kept teaching emphasis runs only
    // once — on the first successful save that completes discovery,
    // regardless of whether the hint text was visible for it — and never
    // again on any later save. Reduce Motion skips scheduling entirely (in
    // addition to `_KeptIconEmphasis`'s own render-time gate).
    if (justCompletedDiscovery && !_reduceMotion) {
      _scheduleKeptTopNavBreaths();
    }
  }

  // Update 1D: schedules the 5-breath top-right Kept teaching emphasis,
  // starting ~350ms after the successful save that completes discovery.
  // Not tied to `_keptDiscoverySessionId` (that id belongs to the
  // reveal-scoped discovery-hint text/center-breath flow, which this
  // emphasis is deliberately independent of); guarded only by `mounted`,
  // and cancelled the same way every other discovery timer is — via
  // `_cancelAllDiscoveryTimers()` on dispose, navigation, lifecycle change,
  // or a new wisdom reveal.
  void _scheduleKeptTopNavBreaths() {
    _keptTopNavBreathCycle = 0;
    _keptIconEmphasisTimer?.cancel();
    _keptIconEmphasisTimer = Timer(
      _keptTopNavBreathStartDelay,
      _startKeptTopNavBreath,
    );
  }

  void _startKeptTopNavBreath() {
    if (!mounted) return;
    setState(() => _keptIconEmphasized = true);
    _keptTopNavBreathCycle++;
    _keptIconEmphasisTimer = Timer(
      _keptTopNavBreathDuration,
      _endKeptTopNavBreath,
    );
  }

  void _endKeptTopNavBreath() {
    if (!mounted) return;
    setState(() => _keptIconEmphasized = false);
    if (_keptTopNavBreathCycle >= _keptTopNavBreathCount) return;
    _keptIconEmphasisTimer = Timer(
      _keptTopNavBreathPause,
      _startKeptTopNavBreath,
    );
  }

  Future<void> shareCurrentWisdom() async {
    if (_shareInProgress ||
        !mounted ||
        !wisdomRevealed ||
        transitionInProgress ||
        _transitionLock ||
        _isInBlackSilence ||
        _revealPersistenceNeedsRetry ||
        wisdomRevealController.value < 1.0 ||
        currentText.trim().isEmpty) {
      return;
    }

    final renderBox = _wisdomShareOriginKey.currentContext?.findRenderObject();
    final Rect shareOrigin;
    if (renderBox is RenderBox && renderBox.hasSize) {
      shareOrigin = renderBox.localToGlobal(Offset.zero) & renderBox.size;
    } else {
      final size = MediaQuery.sizeOf(context);
      shareOrigin = Rect.fromCenter(
        center: size.center(Offset.zero),
        width: 1,
        height: 1,
      );
    }

    _shareInProgress = true;
    HapticFeedback.mediumImpact();
    try {
      await wisdomShareService.shareWisdom(
        wisdom: currentText,
        sharePositionOrigin: shareOrigin,
      );
    } catch (_) {
      // Dismissal and share failures must leave the ritual undisturbed.
    } finally {
      _shareInProgress = false;
    }
  }

  void restoreAskAfterRevealPersistenceFailure() {
    if (!mounted) return;

    wisdomRevealController.stop();
    wisdomRevealController.value = 0.0;
    askFadeController.stop();
    askFadeController.value = 1.0;

    setState(() {
      _isInBlackSilence = false;
      currentText = "Ask from your heart.";
      screenStep = 2;
      _showingLockedWisdom = false;
      _revealPersistenceNeedsRetry = false;
      _pendingRevealBoundaryForRetry = null;
      textOpacity = 1.0;
      saveControlOpacity = 0.0;
      saveInteractionEnabled = false;
      postRevealMessageOpacity = 0.0;
      pauseFeelOpacity = 0.0;
      revealGlowOpacity = 0.0;
      backgroundDepth = 0.0;
      textScale = 1.0;
    });
  }

  DateTime revealBoundaryNow() {
    return widget.clock?.call() ?? DateTime.now();
  }

  Future<void> revealWisdom() async {
    if (_transitionLock) return;

    _transitionLock = true;

    if (transitionInProgress) {
      _transitionLock = false;
      return;
    }

    final currentFlow = ++flowSessionId;
    transitionInProgress = true;

    try {
      HapticFeedback.mediumImpact();

      if (!mounted) return;

      wisdomRevealController.stop();
      wisdomRevealController.value = 0.0;
      askFadeController.stop();
      askFadeController.value = 1.0;
      askFadeController.reverse();
      Object? prepareFailure;
      final prepareFuture =
          prepareDailyWisdomReveal().then<DailyWisdomPreparedReveal?>(
        (prepared) => prepared,
        onError: (Object error, StackTrace stackTrace) {
          prepareFailure = error;
          return null;
        },
      );

      // Correction: a replacement wisdom reveal (a new daily reveal in the
      // same session) must not inherit the previous wisdom's discovery-hint
      // "already offered" flag or any of its pending timers — otherwise the
      // hint could never be offered again for a later eligible day, even
      // though `KeptDiscoveryHintService.isEligible()` would still allow up
      // to `maximumDisplayCount` presentations across different days.
      _keptDiscoveryOfferedForCurrentWisdom = false;
      _cancelAllDiscoveryTimers();

      setState(() {
        textOpacity = 1.0;
        saveControlOpacity = 0.0;
        saveInteractionEnabled = false;
        postRevealMessageOpacity = 0.0;
        pauseFeelOpacity = 0.0;
        revealGlowOpacity = 0.0;
        backgroundDepth = 1.0;
        textScale = 1.0;
        _revealPersistenceNeedsRetry = false;
        _pendingRevealBoundaryForRetry = null;
        // The timers that would otherwise have cleared these were just
        // cancelled above — clear the visual state itself directly so a
        // still-visible previous-wisdom hint can never carry over into the
        // new reveal with no timer left to ever dismiss it.
        _keptDiscoveryHintText = '';
        _keptDiscoveryHintOpacity = 0.0;
        _keptDiscoveryBreathActive = false;
        _keptIconEmphasized = false;
      });

      final silenceComplete =
          Future<void>.delayed(const Duration(milliseconds: 1800));
      final askFadeComplete =
          Future<void>.delayed(const Duration(milliseconds: 1250));

      await askFadeComplete;

      if (!mounted || currentFlow != flowSessionId) return;

      setState(() {
        _isInBlackSilence = true;
      });

      await silenceComplete;

      if (!mounted || currentFlow != flowSessionId) return;

      final DailyWisdomPreparedReveal? maybePreparedReveal;
      try {
        maybePreparedReveal = await prepareFuture.timeout(
          widget.dailyWisdomOperationTimeout,
        );
      } catch (_) {
        if (currentFlow == flowSessionId) {
          restoreAskAfterRevealPersistenceFailure();
        }
        return;
      }
      if (maybePreparedReveal == null || prepareFailure != null) {
        if (currentFlow == flowSessionId) {
          restoreAskAfterRevealPersistenceFailure();
        }
        return;
      }

      if (!mounted || currentFlow != flowSessionId) return;

      final revealReady = maybePreparedReveal;
      final revealBoundary = revealReady.phase ==
              PendingDailyWisdomRevealPhase.revealedPendingCommit
          ? revealReady.confirmedRevealBoundary!
          : revealBoundaryNow();

      final revealedAccess = revealReady.hasAuthoritativeRecord
          ? DailyWisdomAccess(
              text: revealReady.text,
              isNew: false,
              unlockAt: revealReady.unlockAt,
            )
          : DailyWisdomAccess(
              text: revealReady.text,
              isNew: true,
              unlockAt: revealBoundary.add(
                dailyWisdomAccessService.lockDuration,
              ),
            );

      if (!revealReady.hasAuthoritativeRecord) {
        _pendingRevealBoundaryForRetry = revealBoundary;
      }

      setState(() {
        _isInBlackSilence = false;
        currentText = revealedAccess.text;
        screenStep = 4;
        _showingLockedWisdom = !revealedAccess.isNew;
        textOpacity = 1.0;
        textScale = 1.0;
        backgroundDepth = 0.30;
        revealGlowOpacity = 0.16;
      });

      // Correction: the notification-offer "scheduled" guard
      // (`_notificationPermissionOfferScheduled`) must become active in
      // the same synchronous turn the reveal itself becomes visible — not
      // deferred to a post-frame callback. `onFullyVisible` (the save
      // ring's own fade-completion callback, reached independently ~1.9s
      // later via `Future.delayed`/`AnimatedOpacity`) also calls
      // `_maybeOfferKeptDiscoveryHint()`, and a real Mac run showed that
      // call winning the race and presenting the discovery hint before
      // this guard had been raised, incrementing its display count while
      // the native permission Future was still genuinely pending. Queueing
      // the offer here — synchronously, before anything in this method
      // yields control again — closes that window entirely. This is only
      // a reordering: the offer's own delay/Timer, its guard conditions,
      // and `wisdomRevealController.forward` (still correctly deferred to
      // the next frame below) are all unchanged.
      final unlockAt = revealedAccess.unlockAt;
      if (revealedAccess.isNew && unlockAt != null) {
        _queueNotificationPermissionOffer(
          unlockAt,
          delay: wisdomRevealController.duration! + const Duration(seconds: 6),
        );
      }

      unawaited(audioService.playRevealSound());
      HapticFeedback.selectionClick();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isCurrentFlow(currentFlow) || !wisdomRevealed) return;
        wisdomRevealController.forward(from: 0.0);
      });

      final commitFuture = revealReady.hasAuthoritativeRecord
          ? Future<DailyWisdomAccess>.value(revealedAccess)
          : dailyWisdomAccessService.finalizeVisualReveal(
              text: revealReady.text,
              revealBoundary: revealBoundary,
            );
      final DailyWisdomAccess committedAccess;
      try {
        committedAccess = await commitFuture.timeout(
          widget.dailyWisdomOperationTimeout,
        );
      } on TimeoutException {
        if (!mounted || currentFlow != flowSessionId) return;
        setState(() {
          _revealPersistenceNeedsRetry = true;
          saveControlOpacity = 0.0;
          saveInteractionEnabled = false;
          postRevealMessageOpacity = 0.0;
          revealGlowOpacity = 0.10;
        });
        unawaited(
          commitFuture.then(
            (lateAccess) {
              if (!mounted || currentFlow != flowSessionId) return;
              finishCommittedDailyWisdom(lateAccess);
              _pendingRevealBoundaryForRetry = null;
              setState(() {
                _revealPersistenceNeedsRetry = false;
                _showingLockedWisdom = !lateAccess.isNew;
                saveControlOpacity = 1.0;
                saveInteractionEnabled = true;
                postRevealMessageOpacity = 1.0;
                revealGlowOpacity = 0.10;
              });
            },
            onError: (_) {
              if (!mounted || currentFlow != flowSessionId) return;
              setState(() {
                _revealPersistenceNeedsRetry = true;
                saveControlOpacity = 0.0;
                saveInteractionEnabled = false;
                postRevealMessageOpacity = 0.0;
              });
            },
          ),
        );
        return;
      } catch (_) {
        if (!mounted || currentFlow != flowSessionId) return;
        setState(() {
          _revealPersistenceNeedsRetry = true;
          saveControlOpacity = 0.0;
          saveInteractionEnabled = false;
          postRevealMessageOpacity = 0.0;
          revealGlowOpacity = 0.10;
        });
        return;
      }

      if (!mounted || currentFlow != flowSessionId) return;

      finishCommittedDailyWisdom(committedAccess);
      _pendingRevealBoundaryForRetry = null;

      await Future.delayed(const Duration(milliseconds: 900));

      if (!mounted || currentFlow != flowSessionId) return;

      setState(() {
        _revealPersistenceNeedsRetry = false;
        saveControlOpacity = 1.0;
        revealGlowOpacity = 0.10;
      });

      await Future.delayed(const Duration(milliseconds: 520));

      if (!mounted || currentFlow != flowSessionId) return;

      setState(() {
        postRevealMessageOpacity = 1.0;
      });
    } finally {
      if (mounted && currentFlow == flowSessionId) {
        setState(() {
          transitionInProgress = false;
          _transitionLock = false;
        });
      }
    }
  }

  Future<void> retryRevealedWisdomCommit() async {
    if (_transitionLock) return;

    _transitionLock = true;
    final currentFlow = flowSessionId;
    Future<DailyWisdomAccess>? finalization;

    try {
      final retryBoundary = _pendingRevealBoundaryForRetry;
      if (retryBoundary == null) {
        setState(() {
          _revealPersistenceNeedsRetry = true;
          saveControlOpacity = 0.0;
          saveInteractionEnabled = false;
          postRevealMessageOpacity = 0.0;
        });
        return;
      }
      finalization = dailyWisdomAccessService.finalizeVisualReveal(
        text: currentText,
        revealBoundary: retryBoundary,
      );
      final committedAccess = await finalization.timeout(
        widget.dailyWisdomOperationTimeout,
      );

      if (!mounted || currentFlow != flowSessionId) return;

      finishCommittedDailyWisdom(committedAccess);
      _pendingRevealBoundaryForRetry = null;

      setState(() {
        _revealPersistenceNeedsRetry = false;
        _showingLockedWisdom = !committedAccess.isNew;
        saveControlOpacity = 1.0;
        revealGlowOpacity = 0.10;
      });
    } on TimeoutException {
      if (!mounted || currentFlow != flowSessionId) return;
      setState(() {
        _revealPersistenceNeedsRetry = true;
        saveControlOpacity = 0.0;
        saveInteractionEnabled = false;
        postRevealMessageOpacity = 0.0;
      });
      unawaited(
        finalization!.then(
          (lateAccess) {
            if (!mounted || currentFlow != flowSessionId) return;
            finishCommittedDailyWisdom(lateAccess);
            _pendingRevealBoundaryForRetry = null;
            setState(() {
              _revealPersistenceNeedsRetry = false;
              _showingLockedWisdom = !lateAccess.isNew;
              saveControlOpacity = 1.0;
              saveInteractionEnabled = true;
              postRevealMessageOpacity = 1.0;
              revealGlowOpacity = 0.10;
            });
          },
          onError: (_) {
            if (!mounted || currentFlow != flowSessionId) return;
            setState(() {
              _revealPersistenceNeedsRetry = true;
              saveControlOpacity = 0.0;
              saveInteractionEnabled = false;
              postRevealMessageOpacity = 0.0;
            });
          },
        ),
      );
    } catch (_) {
      if (!mounted || currentFlow != flowSessionId) return;
      setState(() {
        _revealPersistenceNeedsRetry = true;
        saveControlOpacity = 0.0;
        saveInteractionEnabled = false;
        postRevealMessageOpacity = 0.0;
      });
    } finally {
      if (currentFlow == flowSessionId) {
        _transitionLock = false;
      }
    }
  }

  Future<void> openKeeperScreen() async {
    if (navigationInProgress || transitionInProgress || _transitionLock) return;

    navigationInProgress = true;
    interruptRitualForNavigation();

    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const KeeperScreen(),
        ),
      );

      if (!mounted) return;
      await loadKeeperStatus();
      await updateNextWisdomMessage();
    } finally {
      if (mounted) {
        navigationInProgress = false;
      }
    }
  }

  Future<void> openObjects() async {
    if (navigationInProgress || transitionInProgress || _transitionLock) return;

    navigationInProgress = true;
    interruptRitualForNavigation();

    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const ObjectsScreen(),
        ),
      );
    } finally {
      if (mounted) {
        navigationInProgress = false;
      }
    }
  }

  Future<void> openSettings() async {
    if (navigationInProgress || transitionInProgress || _transitionLock) return;

    navigationInProgress = true;
    interruptRitualForNavigation();

    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const SettingsScreen(),
        ),
      );

      if (!mounted) return;
      await loadKeeperStatus();
      // The user may have changed the system notification authorization
      // while Settings was open (e.g. via the OS Settings app); reconcile
      // the actual scheduled notification against the live status
      // immediately on return, the same way app-resume already does,
      // instead of waiting for the next resume.
      await synchronizeUnlockNotification();
    } finally {
      if (mounted) {
        navigationInProgress = false;
      }
    }
  }

  bool isCurrentFavorite() {
    return currentFavorite() != null;
  }

  FavoriteItem? currentFavorite() {
    for (final item in favorites) {
      if (item.text == currentText) {
        return item;
      }
    }

    return null;
  }

  void showFavoriteLimitDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF111111),
          title: Text(
            "Kept Limit",
            style: _homeWisdomStyle(22),
          ),
          content: Text(
            "Free users can keep up to 3 wisdoms.",
            style: _homeWisdomStyle(18),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                openKeeperScreen();
              },
              child: Text(
                "Become a Keeper",
                style: _homeWisdomStyle(17),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> toggleFavorite() async {
    if (!wisdomRevealed || _saveOperationInProgress) return;

    // Item 4: the Home save ring is one-way. Once the current wisdom is
    // already kept, tapping the filled ring must do nothing — no removal,
    // no persistence mutation, no haptic, no dialog. Deletion only ever
    // happens from the explicit DELETE action inside Kept. This is the one
    // guard for the whole one-way behavior; `SavedReflectionsService`'s
    // toggle API itself is unchanged.
    if (isCurrentFavorite()) return;

    _saveOperationInProgress = true;

    try {
      final existing = currentFavorite();
      final result = await savedReflectionsService.toggle(
        text: currentText,
        date: formattedToday(),
        isKeeper: isKeeper,
        existingId: existing?.id,
      );

      if (!mounted) return;
      if (result.limitReached) {
        showFavoriteLimitDialog();
        return;
      }

      setState(() {
        favorites = result.items;
      });

      await _onWisdomSuccessfullyKept();
    } catch (_) {
      showEastSnack("Wisdom could not be kept. Please try again.");
    } finally {
      _saveOperationInProgress = false;
    }
  }

  Future<void> loadFavorites() async {
    List<FavoriteItem> loadedFavorites;

    try {
      loadedFavorites = await savedReflectionsService.load();
    } catch (_) {
      loadedFavorites = [];
    }

    if (!mounted) return;

    setState(() {
      favorites = loadedFavorites;
    });
  }

  Future<void> openFavorites() async {
    if (navigationInProgress || transitionInProgress || _transitionLock) return;

    navigationInProgress = true;
    interruptRitualForNavigation();

    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SavedReflectionsScreen(
            reflections: List<FavoriteItem>.from(favorites),
            isKeeper: isKeeper,
            savedReflectionsService: savedReflectionsService,
          ),
        ),
      );
      if (!mounted) return;
      await loadFavorites();
    } finally {
      if (mounted) {
        navigationInProgress = false;
      }
    }
  }

  // Item 5 — Home left-swipe opens Kept.
  //
  // Deliberately more restrictive than `openFavorites()`'s own guard: the
  // gesture must stay silent during Pause/Feel/Ask-from-your-heart, active
  // transitions, black silence, a pending persistence retry, the native
  // notification-permission offer, and an in-flight save/share, in addition
  // to reusing the exact same navigation guards `openFavorites()` already
  // checks. Restricted to the three states item 5 names: the initial
  // stable Home screen (0), fully revealed wisdom (4), and the locked
  // countdown (5).
  bool get _homeSwipeToKeptEligible {
    if (!mounted) return false;
    if (navigationInProgress || transitionInProgress || _transitionLock) {
      return false;
    }
    if (_isInBlackSilence) return false;
    if (_revealPersistenceNeedsRetry) return false;
    if (_notificationPermissionOfferShowing) return false;
    if (_saveOperationInProgress || _shareInProgress) return false;
    return screenStep == 0 || screenStep == 4 || screenStep == 5;
  }

  void _handleHomeSwipeStart(DragStartDetails details) {
    _homeSwipeDx = 0;
    _homeSwipeDy = 0;
    _homeSwipeHandled = false;
  }

  void _handleHomeSwipeUpdate(DragUpdateDetails details) {
    _homeSwipeDx += details.delta.dx;
    _homeSwipeDy += details.delta.dy;
  }

  void _handleHomeSwipeEnd(DragEndDetails details) {
    if (_homeSwipeHandled) return;
    if (!_homeSwipeToKeptEligible) return;

    const double distanceThreshold = 60.0;
    const double velocityThreshold = 320.0;

    final dx = _homeSwipeDx;
    final dy = _homeSwipeDy;
    final velocityX = details.velocity.pixelsPerSecond.dx;

    final isLeftward = dx < 0 && velocityX <= 0;
    final horizontalDominant = dx.abs() > dy.abs() * 1.6;
    final meetsThreshold =
        dx.abs() >= distanceThreshold || velocityX.abs() >= velocityThreshold;

    if (isLeftward && horizontalDominant && meetsThreshold) {
      _homeSwipeHandled = true;
      openFavorites();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          _isInBlackSilence ? Colors.black : const Color(0xFF040404),
      body: SafeArea(
        child: Stack(
          children: [
            _HomeBackgroundDepth(depth: backgroundDepth),
            if (screenStep != 0)
              _HomeGrainLayer(
                pulseController: pulseController,
                reduceMotion: _reduceMotion,
                wisdomRevealed: wisdomRevealed,
              ),
            if (wisdomRevealed || onPauseScreen || _transitionLock)
              _HomeRevealGlow(
                opacity: onPauseScreen ? 0.045 : revealGlowOpacity,
              ),
            Positioned.fill(
              child: _HomeMainRitualGesture(
                navigationDisabled: navigationInProgress || _transitionLock,
                semanticLabel: mainRitualSemanticLabel,
                semanticActionEnabled: mainRitualActionSemanticsEnabled,
                hideContentSemantics: hideMainRitualContentSemantics,
                onTap: handleMainTap,
                swipeToKeptEnabled: _homeSwipeToKeptEligible,
                onSwipeStart: _handleHomeSwipeStart,
                onSwipeUpdate: _handleHomeSwipeUpdate,
                onSwipeEnd: _handleHomeSwipeEnd,
                content: _HomeRitualContent(
                  screenStep: screenStep,
                  currentText: currentText,
                  textOpacity: textOpacity,
                  textScale: textScale,
                  pauseFeelOpacity: pauseFeelOpacity,
                  pulseController: pulseController,
                  askFadeAnimation: askFadeAnimation,
                  wisdomRevealAnimation: wisdomRevealAnimation,
                  reduceMotion: _reduceMotion,
                  onPauseScreen: onPauseScreen,
                  onHeartScreen: onHeartScreen,
                  wisdomRevealed: wisdomRevealed,
                  onLockedCountdown: onLockedCountdown,
                  wisdomShareEnabled: wisdomRevealed &&
                      !transitionInProgress &&
                      !_transitionLock &&
                      !_isInBlackSilence &&
                      !_revealPersistenceNeedsRetry &&
                      wisdomRevealController.value >= 1.0,
                  wisdomShareOriginKey: _wisdomShareOriginKey,
                  onWisdomLongPress: shareCurrentWisdom,
                ),
              ),
            ),
            if (_isInBlackSilence)
              const Positioned.fill(
                child: ColoredBox(
                  key: ValueKey('black-silence'),
                  color: Colors.black,
                ),
              ),
            if (screenStep != 0) ...[
              _HomeSettingsMenuControl(onPressed: openSettings),
              _HomeTopNavigation(
                onObjectsPressed: openObjects,
                onKeptPressed: openFavorites,
                keptEmphasized: _keptIconEmphasized,
              ),
            ],
            if (wisdomRevealed)
              _HomeSaveControl(
                opacity: saveControlOpacity,
                interactionEnabled: saveInteractionEnabled,
                isCurrentFavorite: isCurrentFavorite(),
                onPressed: toggleFavorite,
                showBreath: _keptDiscoveryBreathActive,
                onFullyVisible: () {
                  if (!mounted ||
                      saveInteractionEnabled ||
                      saveControlOpacity < 1.0 ||
                      !wisdomRevealed) {
                    return;
                  }

                  setState(() {
                    saveInteractionEnabled = true;
                  });
                  _maybeOfferKeptDiscoveryHint();
                },
              ),
            if (wisdomRevealed)
              _HomePostRevealMessage(
                opacity: postRevealMessageOpacity,
                message: nextWisdomMessage,
              ),
            if (wisdomRevealed && _keptDiscoveryHintOpacity > 0.0)
              _HomeKeptDiscoveryHint(
                opacity: _keptDiscoveryHintOpacity,
                text: _keptDiscoveryHintText,
              ),
          ],
        ),
      ),
    );
  }
}
