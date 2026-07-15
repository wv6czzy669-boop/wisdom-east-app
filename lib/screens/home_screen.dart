import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/latest_request_guard.dart';
import '../controllers/ritual_flow_controller.dart';
import '../models/favorite_item.dart';
import '../services/app_services.dart';
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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

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
  final StorageService storageService = StorageService();
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
    purchaseService.addListener(_syncKeeperStatus);
    dailyWisdomAccessService = DailyWisdomAccessService(
      storageService: storageService,
    );
    savedReflectionsService = SavedReflectionsService(
      storageService: storageService,
    );

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
    purchaseService.removeListener(_syncKeeperStatus);
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
  Future<void> loadInitialState() async {
    await loadFavorites();
    await loadKeeperStatus();
    await updateNextWisdomMessage();
  }

  Future<void> loadKeeperStatus() async {
    final keeperValue = await storageService.getKeeperStatus();

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
          style: wisdomStyle(17),
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
      if (currentFlow == flowSessionId) {
        transitionInProgress = false;
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
      if (currentFlow == flowSessionId) {
        transitionInProgress = false;
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
      if (currentFlow == flowSessionId) {
        transitionInProgress = false;
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
    try {
      final record = await storageService.loadDailyWisdomRecord(
        lockDuration: dailyWisdomAccessService.lockDuration,
      );
      final text = record?.text.trim();
      if (text != null &&
          text.isNotEmpty &&
          text != DailyWisdomAccessService.corruptRecordRecoveryText) {
        lockedWisdomText = record!.text;
      }
    } catch (_) {
      // Without a trustworthy stored wisdom, remain on the countdown.
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

  Future<String> getLockedOrNewWisdom() async {
    final access = await dailyWisdomAccessService.reveal(
      selectWisdom: () => wisdomSelector.select()["text"] as String,
    );

    if (access.isNew) {
      try {
        await saveDailyArchive(access.text);
      } catch (_) {
        // Archiving is best-effort and must never hide a persisted wisdom.
      }
    }

    try {
      await updateNextWisdomMessage();
    } catch (_) {
      // Countdown copy is noncritical after the daily wisdom is persisted.
    }

    return access.text;
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

      setState(() {
        textOpacity = 1.0;
        saveControlOpacity = 0.0;
        saveInteractionEnabled = false;
        postRevealMessageOpacity = 0.0;
        pauseFeelOpacity = 0.0;
        revealGlowOpacity = 0.0;
        backgroundDepth = 1.0;
        textScale = 1.0;
      });

      final silenceComplete =
          Future<void>.delayed(const Duration(milliseconds: 1800));
      final askFadeComplete =
          Future<void>.delayed(const Duration(milliseconds: 1250));

      String selectedText;

      try {
        selectedText = await getLockedOrNewWisdom();
      } catch (_) {
        selectedText = "Silence is still available.";
      }

      await askFadeComplete;

      if (!mounted || currentFlow != flowSessionId) return;

      setState(() {
        _isInBlackSilence = true;
      });

      await silenceComplete;

      if (!mounted || currentFlow != flowSessionId) return;

      setState(() {
        _isInBlackSilence = false;
        currentText = selectedText;
        screenStep = 4;
        _showingLockedWisdom = false;
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

      await Future.delayed(const Duration(milliseconds: 900));

      if (!mounted || currentFlow != flowSessionId) return;

      setState(() {
        saveControlOpacity = 1.0;
        revealGlowOpacity = 0.10;
      });

      await Future.delayed(const Duration(milliseconds: 520));

      if (!mounted || currentFlow != flowSessionId) return;

      setState(() {
        postRevealMessageOpacity = 1.0;
      });
    } finally {
      if (currentFlow == flowSessionId) {
        transitionInProgress = false;
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
    return favorites.any(
      (item) => item.text == currentText,
    );
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
            style: wisdomStyle(22),
          ),
          content: Text(
            "Free users can keep up to 3 reflections.",
            style: wisdomStyle(18),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                openKeeperScreen();
              },
              child: Text(
                "Become a Keeper",
                style: wisdomStyle(17),
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
      final result = await savedReflectionsService.toggle(
        currentItems: favorites,
        text: currentText,
        date: formattedToday(),
        isKeeper: isKeeper,
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
      loadedFavorites = await savedReflectionsService.load(
        fallbackDate: formattedToday(),
      );
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

  TextStyle wisdomStyle(
    double size, {
    Color color = const Color(0xFFF4F0E8),
    bool glow = false,
    double height = 1.28,
  }) {
    return TextStyle(
      color: color,
      fontSize: size,
      fontWeight: FontWeight.w300,
      fontFamily: 'CormorantGaramond',
      height: height,
      letterSpacing: 0.5,
      shadows: glow
          ? [
              Shadow(
                color: const Color(0xFFF4F0E8).withValues(alpha: 0.12),
                blurRadius: 14,
              ),
              Shadow(
                color: const Color(0xFFD9B86F).withValues(alpha: 0.045),
                blurRadius: 24,
              ),
            ]
          : null,
    );
  }

  Widget buildLaunchMark(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final diameter = min(
          MediaQuery.sizeOf(context).width * 0.585,
          constraints.maxHeight,
        );

        return Semantics(
          label: 'EAST.',
          child: ExcludeSemantics(
            child: Container(
              key: const ValueKey('launch-ritual-mark'),
              width: diameter,
              height: diameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFF4F0E8).withValues(alpha: 0.70),
                  width: 0.85,
                ),
              ),
              alignment: Alignment.center,
              child: Transform.translate(
                offset: const Offset(0, -2.5),
                child: Text(
                  'EAST.',
                  textAlign: TextAlign.center,
                  style: wisdomStyle(
                    21.5,
                    color: const Color(0xFFF4F0E8),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final ritualTextWidth = max(
      1.0,
      MediaQuery.sizeOf(context).width - 68,
    );
    final revealedWisdomWidth = max(
      1.0,
      MediaQuery.sizeOf(context).width * 0.60,
    );
    final textSize = screenStep == 0
        ? 42.0
        : wisdomRevealed
            ? 32.0
            : onLockedCountdown
                ? 22.0
                : onPauseScreen
                    ? 33.0
                    : onHeartScreen
                        ? 29.0
                        : 34.0;

    final finalColor = const Color(0xFFF4F0E8);
    final darkColor = const Color(0xFF111111);

    final animatedTextColor = Color.lerp(
      darkColor,
      finalColor,
      textOpacity,
    )!;
    final currentRitualText = Text(
      currentText,
      textAlign: TextAlign.center,
      style: wisdomStyle(
        textSize,
        color: wisdomRevealed ? animatedTextColor : finalColor,
        glow: wisdomRevealed || onHeartScreen,
        height: wisdomRevealed
            ? 1.48
            : onLockedCountdown
                ? 1.5
                : 1.28,
      ),
    );

    return Scaffold(
      backgroundColor:
          _isInBlackSilence ? Colors.black : const Color(0xFF040404),
      body: SafeArea(
        child: Stack(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeInOutCubic,
              color: Color.lerp(
                const Color(0xFF040404),
                const Color(0xFF000000),
                backgroundDepth,
              ),
            ),
            if (screenStep != 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: pulseController,
                      builder: (context, child) {
                        final pulse = pulseController.value;

                        return CustomPaint(
                          painter: GrainPainter(
                            movement: _reduceMotion ? 0.0 : pulse,
                            intensity: wisdomRevealed ? 0.01625 : 0.01235,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            if (wisdomRevealed || onPauseScreen || _transitionLock)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 1400),
                    opacity: onPauseScreen ? 0.045 : revealGlowOpacity,
                    child: Center(
                      child: Container(
                        width: 285,
                        height: 285,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFD9B86F)
                                  .withValues(alpha: 0.085),
                              blurRadius: 85,
                              spreadRadius: 1,
                            ),
                            BoxShadow(
                              color: const Color(0xFFF4F0E8)
                                  .withValues(alpha: 0.035),
                              blurRadius: 55,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: navigationInProgress || _transitionLock
                    ? null
                    : handleMainTap,
                onLongPress: null,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 34,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: 180,
                        maxHeight: MediaQuery.of(context).size.height * 0.38,
                      ),
                      child: Center(
                        child: AnimatedBuilder(
                          animation: pulseController,
                          builder: (context, child) {
                            final floatingY = _reduceMotion
                                ? 0.0
                                : wisdomRevealed
                                    ? sin(pulseController.value * pi * 2) * 0.8
                                    : onPauseScreen
                                        ? sin(pulseController.value * pi * 2) *
                                            0.5
                                        : 0.0;

                            final liftedY = wisdomRevealed ? -18.0 : 0.0;

                            return Transform.translate(
                              offset: Offset(0, floatingY + liftedY),
                              child: child,
                            );
                          },
                          child: _RitualScaleTransition(
                            enabled: !onHeartScreen,
                            scale: screenStep == 0 ? 1.0 : textScale,
                            duration: const Duration(
                              milliseconds: 1000,
                            ),
                            curve: Curves.easeInOutCubic,
                            child: AnimatedOpacity(
                              key: const ValueKey('ritual-content-opacity'),
                              duration: Duration(
                                milliseconds: screenStep == 0
                                    ? 750
                                    : wisdomRevealed
                                        ? 0
                                        : 1250,
                              ),
                              curve: Curves.easeOutCubic,
                              opacity: textOpacity,
                              child: screenStep == 0
                                  ? buildLaunchMark(context)
                                  : onPauseScreen
                                      ? FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                "Pause.",
                                                textAlign: TextAlign.center,
                                                style: wisdomStyle(
                                                  textSize,
                                                  color: finalColor,
                                                  glow: true,
                                                ),
                                              ),
                                              const SizedBox(width: 28),
                                              AnimatedOpacity(
                                                duration: const Duration(
                                                  milliseconds: 1250,
                                                ),
                                                curve: Curves.easeOutCubic,
                                                opacity: pauseFeelOpacity,
                                                child: Text(
                                                  "Feel.",
                                                  textAlign: TextAlign.center,
                                                  style: wisdomStyle(
                                                    textSize,
                                                    color: finalColor,
                                                    glow: true,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      : onHeartScreen
                                          ? SizedBox(
                                              width: ritualTextWidth,
                                              child: FadeTransition(
                                                key: const ValueKey(
                                                  'ask-fade',
                                                ),
                                                opacity: askFadeAnimation,
                                                child: currentRitualText,
                                              ),
                                            )
                                          : FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: SizedBox(
                                                key: wisdomRevealed
                                                    ? const ValueKey(
                                                        'revealed-wisdom-layout',
                                                      )
                                                    : null,
                                                width: wisdomRevealed
                                                    ? revealedWisdomWidth
                                                    : ritualTextWidth,
                                                child: wisdomRevealed
                                                    ? FadeTransition(
                                                        key: const ValueKey(
                                                          'wisdom-reveal-fade',
                                                        ),
                                                        opacity:
                                                            wisdomRevealAnimation,
                                                        child:
                                                            currentRitualText,
                                                      )
                                                    : currentRitualText,
                                              ),
                                            ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
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
              Positioned(
                key: const ValueKey('top-navigation'),
                top: 0,
                right: 8,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: 48,
                      child: IconButton(
                        tooltip: 'Settings',
                        icon: Transform.translate(
                          offset: const Offset(0, -4),
                          child: const Text(
                            '◎',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 29,
                              fontWeight: FontWeight.w300,
                              fontFamily: 'CormorantGaramond',
                              height: 1,
                            ),
                          ),
                        ),
                        onPressed: openSettings,
                      ),
                    ),
                    SizedBox.square(
                      dimension: 48,
                      child: IconButton(
                        tooltip: 'Kept',
                        icon: Transform.translate(
                          offset: const Offset(0, -4),
                          child: const Text(
                            '○',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 36,
                              fontWeight: FontWeight.w300,
                              fontFamily: 'CormorantGaramond',
                              height: 1,
                            ),
                          ),
                        ),
                        onPressed: openFavorites,
                      ),
                    ),
                  ],
                ),
              ),
            if (wisdomRevealed)
              Positioned(
                left: 0,
                right: 0,
                top: MediaQuery.of(context).size.height / 2 + 72,
                child: Center(
                  child: IgnorePointer(
                    key: const ValueKey('kept-interaction-guard'),
                    ignoring: !saveInteractionEnabled,
                    child: AnimatedOpacity(
                      duration: const Duration(
                        milliseconds: 1000,
                      ),
                      curve: Curves.easeOutCubic,
                      opacity: saveControlOpacity,
                      onEnd: () {
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
                      child: IconButton(
                        tooltip: isCurrentFavorite()
                            ? 'Remove kept reflection'
                            : 'Keep reflection',
                        icon: Text(
                          isCurrentFavorite() ? '●' : '○',
                          style: const TextStyle(
                            color: Color(0xFFF4F0E8),
                            fontSize: 31,
                            fontWeight: FontWeight.w300,
                            fontFamily: 'CormorantGaramond',
                            height: 1,
                          ),
                        ),
                        onPressed: toggleFavorite,
                      ),
                    ),
                  ),
                ),
              ),
            if (wisdomRevealed)
              Positioned(
                left: 0,
                right: 0,
                top: MediaQuery.of(context).size.height / 2 + 156,
                child: IgnorePointer(
                  ignoring: postRevealMessageOpacity < 1.0,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeOutCubic,
                    opacity: postRevealMessageOpacity,
                    child: Column(
                      children: [
                        if (nextWisdomMessage.isNotEmpty) ...[
                          Text(
                            nextWisdomMessage,
                            textAlign: TextAlign.center,
                            style: wisdomStyle(
                              15,
                              color: const Color(0x91FFFFFF),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RitualScaleTransition extends StatelessWidget {
  const _RitualScaleTransition({
    required this.enabled,
    required this.scale,
    required this.duration,
    required this.curve,
    required this.child,
  });

  final bool enabled;
  final double scale;
  final Duration duration;
  final Curve curve;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    return AnimatedScale(
      scale: scale,
      duration: duration,
      curve: curve,
      child: child,
    );
  }
}
