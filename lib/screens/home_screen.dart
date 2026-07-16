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
import '../services/saved_reflections_service.dart';
import '../services/storage_service.dart';
import '../services/wisdom_selector.dart';
import '../utils/countdown_formatter.dart';
import '../utils/date_formatter.dart';
import '../widgets/grain_painter.dart';
import 'keeper_screen.dart';
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
    this.dailyWisdomOperationTimeout = const Duration(seconds: 8),
    this.dailyWisdomStatusTimeout =
        DailyWisdomAccessService.defaultStatusTimeout,
  });

  final WisdomClock? clock;
  final StorageService? storageService;
  final DailyWisdomAccessService? dailyWisdomAccessService;
  final SavedReflectionsService? savedReflectionsService;
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
  bool _revealPersistenceNeedsRetry = false;
  DateTime? _pendingRevealBoundaryForRetry;
  String? _lockedWisdomText;

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
    await loadFavorites();
    await loadKeeperStatus();
    await updateNextWisdomMessage();
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
        textScale = 0.985;
      });

      await Future.delayed(
        ritualFlowController.transitionFadeOutDuration(nextStep),
      );

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

      await Future.delayed(const Duration(milliseconds: 220));

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
            "Free users can keep up to 3 reflections.",
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
    } catch (_) {
      showEastSnack("Reflection could not be kept. Please try again.");
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
          ),
        ),
      );
    } finally {
      if (mounted) {
        navigationInProgress = false;
      }
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
            if (screenStep != 0)
              _HomeTopNavigation(
                onSettingsPressed: openSettings,
                onKeptPressed: openFavorites,
              ),
            if (wisdomRevealed)
              _HomeSaveControl(
                opacity: saveControlOpacity,
                interactionEnabled: saveInteractionEnabled,
                isCurrentFavorite: isCurrentFavorite(),
                onPressed: toggleFavorite,
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
                },
              ),
            if (wisdomRevealed)
              _HomePostRevealMessage(
                opacity: postRevealMessageOpacity,
                message: nextWisdomMessage,
              ),
          ],
        ),
      ),
    );
  }
}
