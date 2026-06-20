import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/ritual_flow_controller.dart';
import '../models/favorite_item.dart';
import '../services/app_services.dart';
import '../services/audio_service.dart';
import '../services/daily_wisdom_access_service.dart';
import '../services/saved_reflections_service.dart';
import '../services/storage_service.dart';
import '../services/wisdom_selector.dart';
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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  int screenStep = 0;

  String currentText = "East";

  double textOpacity = 0.0;
  double heartOpacity = 0.0;
  double keeperPromptOpacity = 0.0;
  double textScale = 0.985;
  double revealGlowOpacity = 0.0;
  double backgroundDepth = 0.0;
  double ritualHintOpacity = 0.0;
  double openingSubtitleOpacity = 0.0;
  double pauseFeelOpacity = 0.0;

  bool transitionInProgress = false;
  bool _transitionLock = false;
  int flowSessionId = 0;
  bool navigationInProgress = false;
  bool introFinished = false;
  bool heartInteractionEnabled = false;

  final ritualFlowController = const RitualFlowController();

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
    audioService.stop();
    transitionInProgress = false;
    _transitionLock = false;
  }

  void restoreStableRitualState() {
    if (!mounted) return;

    setState(() {
      transitionInProgress = false;
      _transitionLock = false;
      textOpacity = 1.0;
      textScale = 1.0;

      if (screenStep == 0) {
        openingSubtitleOpacity = 1.0;
        backgroundDepth = 0.06;
      } else {
        openingSubtitleOpacity = 0.0;
        backgroundDepth = wisdomRevealed ? 0.30 : 0.0;
      }

      if (!onPauseScreen) {
        pauseFeelOpacity = 0.0;
      }

      if (wisdomRevealed) {
        heartOpacity = 1.0;
        keeperPromptOpacity = 1.0;
        revealGlowOpacity = 0.10;
      } else {
        heartOpacity = 0.0;
        heartInteractionEnabled = false;
        keeperPromptOpacity = 0.0;
        revealGlowOpacity = 0.0;
      }
    });
  }

  List<FavoriteItem> favorites = [];

  bool isKeeper = false;

  late AnimationController pulseController;
  late Animation<double> pulseAnimation;

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

    pulseAnimation = Tween<double>(
      begin: 0.70,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: pulseController,
        curve: Curves.easeInOut,
      ),
    );

    loadInitialState().catchError((_) {
      if (!mounted) return;
      startCountdownTimer();
    });

    runOpeningIntro();
  }

  @override
  void dispose() {
    flowSessionId++;
    invalidateDelayedCallbacks();

    WidgetsBinding.instance.removeObserver(this);
    purchaseService.removeListener(_syncKeeperStatus);
    stopCountdownTimer();
    pulseController.dispose();
    audioService.dispose();
    super.dispose();
  }

  Future<void> _syncKeeperStatus() async {
    if (!mounted) return;
    await loadKeeperStatus();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      flowSessionId++;
      invalidateDelayedCallbacks();
      audioService.stop();
      stopCountdownTimer();

      if (pulseController.isAnimating) {
        pulseController.stop();
      }

      restoreStableRitualState();
      return;
    }

    if (state == AppLifecycleState.resumed) {
      if (!mounted) return;

      if (!pulseController.isAnimating) {
        pulseController.repeat(reverse: true);
      }

      startCountdownTimer();
      updateNextWisdomMessage();
    }
  }

  bool get onPauseScreen => ritualFlowController.isPauseScreen(screenStep);
  bool get onHeartScreen => ritualFlowController.isHeartScreen(screenStep);
  bool get onRevealScreen => ritualFlowController.isRevealScreen(screenStep);
  bool get wisdomRevealed => ritualFlowController.isWisdomRevealed(screenStep);
  Future<void> runOpeningIntro() async {
    final currentFlow = ++flowSessionId;

    await Future.delayed(const Duration(milliseconds: 420));

    if (!mounted || currentFlow != flowSessionId) return;

    setState(() {
      textOpacity = 1.0;
      textScale = 1.0;
      backgroundDepth = 0.06;
    });

    await Future.delayed(const Duration(milliseconds: 900));

    if (!mounted || currentFlow != flowSessionId) return;

    setState(() {
      openingSubtitleOpacity = 1.0;
    });

    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted || currentFlow != flowSessionId) return;

    setState(() {
      introFinished = true;
    });

    startCountdownTimer();
  }

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
      HapticFeedback.selectionClick();

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
      HapticFeedback.selectionClick();

      await transitionToText(
        "Tap to Reveal",
        nextStep: 3,
      );

      return;
    }

    if (screenStep == 3) {
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
        ritualHintOpacity = 0.0;
        pauseFeelOpacity = 1.0;
      });

      await Future.delayed(const Duration(milliseconds: 1250));

      if (!isCurrentFlow(currentFlow)) return;

      setState(() {
        ritualHintOpacity = 1.0;
      });
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
        heartOpacity = 0.0;
        heartInteractionEnabled = false;
        keeperPromptOpacity = 0.0;
        ritualHintOpacity = 0.0;
        revealGlowOpacity = 0.0;
        backgroundDepth =
            ritualFlowController.transitionBackgroundDepth(nextStep);
        textScale = 0.985;
        openingSubtitleOpacity = 0.0;
      });

      await Future.delayed(
        ritualFlowController.transitionFadeOutDuration(nextStep),
      );

      if (!isCurrentFlow(currentFlow)) return;

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

      if (nextStep == 1) {
        setState(() {
          ritualHintOpacity = 1.0;
        });
      }
    } finally {
      if (currentFlow == flowSessionId) {
        transitionInProgress = false;
      }
    }
  }

  Future<void> updateNextWisdomMessage() async {
    final DailyWisdomStatus status;

    try {
      status = await dailyWisdomAccessService.status();
    } catch (_) {
      if (mounted) {
        setState(() {
          nextWisdomMessage = "";
        });
      }
      return;
    }

    if (status.isReady) {
      if (mounted) {
        setState(() {
          nextWisdomMessage =
              status.unlockAt == null ? "" : "A new wisdom is ready.";
        });
      }
      return;
    }

    final remaining = status.remaining!;
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes % 60;

    String message;

    if (hours <= 0) {
      message = "The next wisdom opens in ${minutes + 1} min.";
    } else {
      message = "The next wisdom opens in ${hours}h ${minutes}m.";
    }

    if (mounted) {
      setState(() {
        nextWisdomMessage = message;
      });
    }
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
      HapticFeedback.lightImpact();

      if (!mounted) return;

      setState(() {
        textOpacity = 0.0;
        heartOpacity = 0.0;
        heartInteractionEnabled = false;
        keeperPromptOpacity = 0.0;
        ritualHintOpacity = 0.0;
        pauseFeelOpacity = 0.0;
        revealGlowOpacity = 0.0;
        backgroundDepth = 0.82;
        textScale = 0.975;
      });

      await Future.delayed(const Duration(milliseconds: 880));

      if (!mounted || currentFlow != flowSessionId) return;

      String selectedText;

      try {
        selectedText = await getLockedOrNewWisdom();
      } catch (_) {
        selectedText = "Silence is still available.";
      }

      if (!mounted || currentFlow != flowSessionId) return;

      setState(() {
        currentText = selectedText;
        screenStep = 4;
        revealGlowOpacity = 0.16;
      });

      await Future.delayed(const Duration(milliseconds: 260));

      if (!mounted || currentFlow != flowSessionId) return;

      setState(() {
        textOpacity = 1.0;
        textScale = 1.0;
        backgroundDepth = 0.30;
      });

      await Future.delayed(const Duration(milliseconds: 280));

      if (!mounted || currentFlow != flowSessionId) return;

      audioService.playRevealSound();
      HapticFeedback.selectionClick();

      await Future.delayed(const Duration(milliseconds: 900));

      if (!mounted || currentFlow != flowSessionId) return;

      setState(() {
        heartOpacity = 1.0;
        revealGlowOpacity = 0.10;
      });

      await Future.delayed(const Duration(milliseconds: 520));

      if (!mounted || currentFlow != flowSessionId) return;

      setState(() {
        keeperPromptOpacity = 1.0;
      });
    } finally {
      if (currentFlow == flowSessionId) {
        transitionInProgress = false;
        _transitionLock = false;
      }
    }
  }

  Future<void> resetToRevealScreen() async {
    HapticFeedback.selectionClick();

    await transitionToText(
      "Tap to Reveal",
      nextStep: 3,
    );
  }

  Future<void> copyCurrentWisdom() async {
    if (!wisdomRevealed) return;

    await Clipboard.setData(
      ClipboardData(text: currentText),
    );

    if (!mounted) return;

    HapticFeedback.selectionClick();
    showEastSnack("Copied quietly.");
  }

  Future<void> openKeeperScreen() async {
    if (navigationInProgress || transitionInProgress || _transitionLock) return;

    navigationInProgress = true;
    interruptRitualForNavigation();
    HapticFeedback.selectionClick();

    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const KeeperScreen(),
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

  Future<void> openSettings() async {
    if (navigationInProgress || transitionInProgress || _transitionLock) return;

    navigationInProgress = true;
    interruptRitualForNavigation();
    HapticFeedback.selectionClick();

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
            "Saved Reflection Limit",
            style: wisdomStyle(22),
          ),
          content: Text(
            "Free users can save up to 3 reflections.",
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
    if (!wisdomRevealed) return;

    HapticFeedback.selectionClick();

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
      showEastSnack("Reflection could not be saved. Please try again.");
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
    HapticFeedback.selectionClick();

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
  }) {
    return TextStyle(
      color: color,
      fontSize: size,
      fontWeight: FontWeight.w300,
      fontFamily: 'CormorantGaramond',
      height: 1.28,
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

  @override
  Widget build(BuildContext context) {
    final ritualTextWidth = max(
      1.0,
      MediaQuery.sizeOf(context).width - 68,
    );
    final textSize = screenStep == 0
        ? 42.0
        : wisdomRevealed
            ? 33.0
            : onPauseScreen
                ? 31.0
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

    return Scaffold(
      backgroundColor: const Color(0xFF030303),
      body: SafeArea(
        child: Stack(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeInOutCubic,
              color: Color.lerp(
                const Color(0xFF030303),
                const Color(0xFF000000),
                backgroundDepth,
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: pulseController,
                    builder: (context, child) {
                      final pulse = pulseController.value;

                      return CustomPaint(
                        painter: GrainPainter(
                          movement: pulse,
                          intensity: wisdomRevealed ? 0.025 : 0.019,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            if (wisdomRevealed || onPauseScreen)
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
                onTap: navigationInProgress ? null : handleMainTap,
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
                            final floatingY = wisdomRevealed
                                ? sin(pulseController.value * pi * 2) * 0.8
                                : onPauseScreen
                                    ? sin(pulseController.value * pi * 2) * 0.5
                                    : 0.0;

                            final liftedY = wisdomRevealed ? -18.0 : 0.0;

                            return Transform.translate(
                              offset: Offset(0, floatingY + liftedY),
                              child: child,
                            );
                          },
                          child: AnimatedScale(
                            scale: textScale,
                            duration: const Duration(
                              milliseconds: 1000,
                            ),
                            curve: Curves.easeInOutCubic,
                            child: AnimatedOpacity(
                              key: const ValueKey('ritual-content-opacity'),
                              duration: const Duration(
                                milliseconds: 1250,
                              ),
                              curve: Curves.easeInOutCubic,
                              opacity: textOpacity,
                              child: AnimatedBuilder(
                                animation: pulseAnimation,
                                builder: (context, child) {
                                  return Opacity(
                                    opacity: onRevealScreen
                                        ? pulseAnimation.value
                                        : 1.0,
                                    child: child,
                                  );
                                },
                                child: screenStep == 0
                                    ? FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: SizedBox(
                                          width: ritualTextWidth,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                "East",
                                                textAlign: TextAlign.center,
                                                style: wisdomStyle(
                                                  44,
                                                  color: finalColor,
                                                  glow: true,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              AnimatedOpacity(
                                                duration: const Duration(
                                                  milliseconds: 1200,
                                                ),
                                                opacity: openingSubtitleOpacity,
                                                child: Text(
                                                  "where silence speaks",
                                                  textAlign: TextAlign.center,
                                                  style: wisdomStyle(
                                                    20,
                                                    color: Colors.white54,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
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
                                                  curve: Curves.easeInOutCubic,
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
                                        : FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: SizedBox(
                                              width: ritualTextWidth,
                                              child: Text(
                                                currentText,
                                                textAlign: TextAlign.center,
                                                style: wisdomStyle(
                                                  textSize,
                                                  color: wisdomRevealed
                                                      ? animatedTextColor
                                                      : finalColor,
                                                  glow: wisdomRevealed ||
                                                      onHeartScreen,
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
                ),
              ),
            ),
            if (true)
              Positioned(
                top: 10,
                right: 8,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.settings_outlined,
                        color: Colors.white70,
                        size: 27,
                      ),
                      onPressed: openSettings,
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.star_border,
                        color: Colors.white70,
                        size: 29,
                      ),
                      onPressed: openFavorites,
                    ),
                  ],
                ),
              ),
            if (wisdomRevealed)
              Positioned(
                top: 10,
                left: 8,
                child: IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new,
                    color: Colors.white70,
                    size: 23,
                  ),
                  onPressed: resetToRevealScreen,
                ),
              ),
            if (wisdomRevealed)
              Positioned(
                left: 0,
                right: 0,
                top: MediaQuery.of(context).size.height / 2 + 72,
                child: Center(
                  child: IgnorePointer(
                    key: const ValueKey('favorite-interaction-guard'),
                    ignoring: !heartInteractionEnabled,
                    child: AnimatedOpacity(
                      duration: const Duration(
                        milliseconds: 1000,
                      ),
                      opacity: heartOpacity,
                      onEnd: () {
                        if (!mounted ||
                            heartInteractionEnabled ||
                            heartOpacity < 1.0 ||
                            !wisdomRevealed) {
                          return;
                        }

                        setState(() {
                          heartInteractionEnabled = true;
                        });
                      },
                      child: IconButton(
                        icon: Icon(
                          isCurrentFavorite()
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: const Color(0xFFF4F0E8),
                          size: 28,
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
                top: MediaQuery.of(context).size.height / 2 + 124,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 900),
                  opacity: keeperPromptOpacity,
                  child: Column(
                    children: [
                      if (nextWisdomMessage.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          nextWisdomMessage,
                          textAlign: TextAlign.center,
                          style: wisdomStyle(
                            15,
                            color: Colors.white38,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
