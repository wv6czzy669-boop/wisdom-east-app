import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'dart:io';

import 'services/audio_service.dart';
import 'services/rewarded_ad_service.dart';
import 'services/storage_service.dart';
import 'models/favorite_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:app_tracking_transparency/app_tracking_transparency.dart';

import 'data/wisdoms.dart';
import 'screens/premium_screen.dart';
import 'screens/settings_screen.dart';
import 'services/purchase_service.dart';

final PurchaseService purchaseService = PurchaseService();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const MyApp());

  Future.microtask(() async {
    if (Platform.isIOS) {
      final status = await AppTrackingTransparency.trackingAuthorizationStatus;

      if (status == TrackingStatus.notDetermined) {
        await Future.delayed(const Duration(seconds: 2));
        await AppTrackingTransparency.requestTrackingAuthorization();
      }
    }

    MobileAds.instance.initialize();
    purchaseService.init();
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const WisdomApp();
  }
}

class WisdomApp extends StatelessWidget {
  const WisdomApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Daily Wisdom: East',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF030303),
        textTheme: ThemeData.dark().textTheme.apply(
              fontFamily: 'CormorantGaramond',
            ),
      ),
      home: const HomeScreen(),
    );
  }
}

String formattedToday() {
  final now = DateTime.now();

  const months = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
  ];

  return "${months[now.month - 1]} ${now.day}, ${now.year}";
}

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
  double premiumPromptOpacity = 0.0;
  double textScale = 0.985;
  double revealGlowOpacity = 0.0;
  double backgroundDepth = 0.0;
  double ritualHintOpacity = 0.0;
  double openingSubtitleOpacity = 0.0;
  double pauseFeelOpacity = 0.0;

  bool adReturnInProgress = false;
  bool transitionInProgress = false;
  bool _transitionLock = false;
  int flowSessionId = 0;
  bool navigationInProgress = false;
  bool introFinished = false;

  List<FavoriteItem> favorites = [];

  bool isPremium = false;

  final int freeFavoriteLimit = 3;
  final Duration wisdomLockDuration = const Duration(hours: 24);

  late AnimationController pulseController;
  late Animation<double> pulseAnimation;

  Timer? countdownTimer;

  final AudioService audioService = AudioService();
  final RewardedAdService adService = RewardedAdService();
  final StorageService storageService = StorageService();

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

  Future<SharedPreferences> getPrefs() => storageService.getPrefs();

  String nextWisdomMessage = "";

  final List<String> recentWisdoms = [];
  final List<String> recentTags = [];
  final List<String> recentTones = [];

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    purchaseService.addListener(_syncPremiumStatus);

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

    loadInitialState().then((_) {
      if (!mounted) return;

      if (!isPremium) {
        final startupAdSessionId = adService.adRetrySessionId;

        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;
          if (!adService.isCurrentRetrySession(startupAdSessionId)) return;
          if (isPremium) return;
          if (adService.isLoadingRewardedAd || adService.isRewardedAdReady) {
            return;
          }

          loadRewardedAd();
        });
      }
    });

    runOpeningIntro();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    purchaseService.removeListener(_syncPremiumStatus);
    stopCountdownTimer();
    pulseController.dispose();
    audioService.dispose();
    adService.dispose();
    super.dispose();
  }

  Future<void> _syncPremiumStatus() async {
    if (!mounted) return;
    await loadPremiumStatus();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      audioService.stop();
      stopCountdownTimer();
      return;
    }

    if (state == AppLifecycleState.resumed) {
      startCountdownTimer();
      updateNextWisdomMessage();
    }
  }

  bool get onPauseScreen => screenStep == 1;
  bool get onHeartScreen => screenStep == 2;
  bool get onRevealScreen => screenStep == 3;
  bool get wisdomRevealed => screenStep == 4;
  bool get onPostAdBlackScreen => screenStep == 5;

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
    await loadPremiumStatus();
    await updateNextWisdomMessage();
  }

  Future<void> loadPremiumStatus() async {
    final prefs = await getPrefs();

    if (!mounted) return;

    final premiumValue = prefs.getBool("is_premium") ?? false;

    setState(() {
      isPremium = premiumValue;
    });

    if (premiumValue) {
      adService.dispose();
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
          style: wisdomStyle(17),
        ),
      ),
    );
  }

  void loadRewardedAd() {
    adService.loadRewardedAd(
      isPremium: isPremium,
      isMounted: () => mounted,
      onStateChanged: () {
        if (!mounted) {
          return;
        }

        setState(() {});
      },
      onRetry: loadRewardedAd,
    );
  }

  Future<void> saveDailyArchive(String text) async {
    await storageService.saveDailyArchive(
      text: text,
      today: formattedToday(),
    );
  }

  Future<void> prepareRewardedWisdom() async {
    final selectedWisdom = chooseSmartRandomWisdom();
    final selectedText = selectedWisdom["text"] as String;

    await storageService.saveRewardedWisdom(
      text: selectedText,
      unlockTime: DateTime.now().add(wisdomLockDuration),
    );

    await saveDailyArchive(selectedText);
    await updateNextWisdomMessage();
  }

  void resetRewardedAdState() => adService.resetRewardedAdState();

  Future<void> returnToBlackAfterAd() async {
    if (!mounted) return;

    setState(() {
      adReturnInProgress = false;
      currentText = "";
      screenStep = 5;
      textOpacity = 0.0;
      heartOpacity = 0.0;
      premiumPromptOpacity = 0.0;
      ritualHintOpacity = 0.0;
      pauseFeelOpacity = 0.0;
      revealGlowOpacity = 0.0;
      backgroundDepth = 0.0;
      textScale = 0.985;
    });
  }

  void showRewardedAdThenReveal() {
    if (isPremium) {
      revealWisdom(bypassLock: true);
      return;
    }

    adService.showRewardedAd(
      onAdNotReady: () {
        showEastSnack(
          adService.shouldShowPreparingMessage
              ? "Ad is preparing. Please try again."
              : "Ad is not ready yet. Please try again.",
        );

        loadRewardedAd();
      },
      onAdMissing: () {
        loadRewardedAd();
      },
      onAdDismissedAfterRewardCheck: () async {
        if (!mounted) {
          return;
        }

        if (adService.adRewardEarned && !isPremium) {
          await prepareRewardedWisdom();

          if (!mounted) {
            return;
          }
        } else if (!adService.adRewardEarned) {
          showEastSnack("The wisdom opens after the ad is completed.");
        }

        await returnToBlackAfterAd();

        if (!mounted) {
          return;
        }

        loadRewardedAd();
      },
      onAdFailedToShow: () async {
        if (!mounted) {
          return;
        }

        showEastSnack("Ad could not open. Please try again.");

        await returnToBlackAfterAd();

        if (!mounted) {
          return;
        }

        loadRewardedAd();
      },
    );
  }

  Future<void> handleMainTap() async {
    if (adReturnInProgress || transitionInProgress) return;

    if (screenStep == 5) {
      HapticFeedback.selectionClick();
      Future.delayed(
        const Duration(milliseconds: 1200),
        () {
          if (!mounted) return;
          audioService.playPauseSound();
        },
      );

      await transitionToText(
        "Pause.",
        nextStep: 1,
      );

      return;
    }

    if (screenStep == 0) {
      HapticFeedback.selectionClick();
      Future.delayed(
        const Duration(milliseconds: 1200),
        () {
          if (!mounted) return;
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
        Future.delayed(
          const Duration(milliseconds: 200),
          () {
            if (!mounted) return;
            audioService.playFeelSound();
          },
        );
        await revealFeelBesidePause();
      } else {
        Future.delayed(
          const Duration(milliseconds: 1100),
          () {
            if (!mounted) return;
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

    transitionInProgress = true;

    setState(() {
      ritualHintOpacity = 0.0;
      pauseFeelOpacity = 1.0;
    });

    await Future.delayed(const Duration(milliseconds: 1250));

    if (!mounted) {
      transitionInProgress = false;
      return;
    }

    setState(() {
      ritualHintOpacity = 1.0;
    });

    transitionInProgress = false;
  }

  Future<void> transitionToText(
    String newText, {
    required int nextStep,
  }) async {
    if (transitionInProgress) return;

    transitionInProgress = true;

    setState(() {
      textOpacity = 0.0;
      heartOpacity = 0.0;
      premiumPromptOpacity = 0.0;
      ritualHintOpacity = 0.0;
      revealGlowOpacity = 0.0;
      backgroundDepth = nextStep == 1 ? 0.14 : 0.0;
      textScale = 0.985;
      openingSubtitleOpacity = 0.0;
    });

    await Future.delayed(
      Duration(milliseconds: nextStep == 3 ? 980 : 820),
    );

    if (!mounted) {
      transitionInProgress = false;
      return;
    }

    setState(() {
      currentText = newText;
      screenStep = nextStep;
      if (nextStep != 1) {
        pauseFeelOpacity = 0.0;
      }
    });

    await Future.delayed(const Duration(milliseconds: 220));

    if (!mounted) {
      transitionInProgress = false;
      return;
    }

    setState(() {
      textOpacity = 1.0;
      textScale = 1.0;
    });

    if (nextStep == 1) {
      await Future.delayed(const Duration(milliseconds: 820));
    } else {
      await Future.delayed(const Duration(milliseconds: 560));
    }

    if (!mounted) {
      transitionInProgress = false;
      return;
    }

    if (nextStep == 1) {
      setState(() {
        ritualHintOpacity = 1.0;
      });
    }

    transitionInProgress = false;
  }

  Future<void> updateNextWisdomMessage() async {
    final savedTime = await storageService.getWisdomUnlockTimeMs();

    if (savedTime == null) {
      if (mounted) {
        setState(() {
          nextWisdomMessage = "";
        });
      }
      return;
    }

    final unlockTime = DateTime.fromMillisecondsSinceEpoch(savedTime);
    final now = DateTime.now();

    if (now.isAfter(unlockTime)) {
      if (mounted) {
        setState(() {
          nextWisdomMessage = "A new wisdom is ready.";
        });
      }
      return;
    }

    final remaining = unlockTime.difference(now);
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

  Future<String> getLockedOrNewWisdom({
    bool bypassLock = false,
  }) async {
    final savedText = await storageService.getDailyWisdomText();
    final unlockTimeMs = await storageService.getWisdomUnlockTimeMs();

    final now = DateTime.now();

    if (!isPremium &&
        !bypassLock &&
        savedText != null &&
        unlockTimeMs != null) {
      final unlockTime = DateTime.fromMillisecondsSinceEpoch(unlockTimeMs);

      if (now.isBefore(unlockTime)) {
        return savedText;
      }
    }

    final selectedWisdom = chooseSmartRandomWisdom();
    final selectedText = selectedWisdom["text"] as String;

    if (!isPremium) {
      final nextUnlock = now.add(wisdomLockDuration);

      await storageService.saveDailyWisdom(
        text: selectedText,
        unlockTime: nextUnlock,
      );

      await saveDailyArchive(selectedText);
    }

    await updateNextWisdomMessage();

    return selectedText;
  }

  Map<String, dynamic> chooseSmartRandomWisdom() {
    final random = Random();

    if (wisdoms.isEmpty) {
      return {
        "text": "Silence is still available.",
        "tags": ["silence"],
        "tone": "calm",
      };
    }

    final candidates = wisdoms.where((wisdom) {
      final text = wisdom["text"] as String;
      return !recentWisdoms.contains(text);
    }).toList();

    if (candidates.isEmpty) {
      recentWisdoms.clear();
      candidates.addAll(wisdoms);
    }

    final scoredCandidates = candidates.map((wisdom) {
      int score = 100;

      final tags = List<String>.from(wisdom["tags"] ?? []);
      final tone = wisdom["tone"] as String? ?? "neutral";
      final text = wisdom["text"] as String;

      for (final tag in tags) {
        if (recentTags.contains(tag)) {
          score -= 18;
        }
      }

      if (recentTones.contains(tone)) {
        score -= 25;
      }

      if (recentWisdoms.contains(text)) {
        score -= 50;
      }

      score += random.nextInt(35);

      if (score < 5) {
        score = 5;
      }

      return {
        "wisdom": wisdom,
        "score": score,
      };
    }).toList();

    scoredCandidates.sort(
      (a, b) => (b["score"] as int).compareTo(a["score"] as int),
    );

    final topPoolSize = min(12, scoredCandidates.length);
    final topPool = scoredCandidates.take(topPoolSize).toList();

    final selected = topPool[random.nextInt(topPool.length)]["wisdom"]
        as Map<String, dynamic>;

    rememberWisdomPattern(selected);

    return selected;
  }

  void rememberWisdomPattern(Map<String, dynamic> selected) {
    final text = selected["text"] as String;
    final tags = List<String>.from(selected["tags"] ?? []);
    final tone = selected["tone"] as String? ?? "neutral";

    recentWisdoms.add(text);

    if (recentWisdoms.length > 20) {
      recentWisdoms.removeAt(0);
    }

    recentTags.addAll(tags);

    while (recentTags.length > 12) {
      recentTags.removeAt(0);
    }

    recentTones.add(tone);

    while (recentTones.length > 5) {
      recentTones.removeAt(0);
    }
  }

  Future<void> revealWisdom({
    bool bypassLock = false,
  }) async {
    if (_transitionLock && !bypassLock) return;

    _transitionLock = true;

    if (transitionInProgress) {
      _transitionLock = false;
      return;
    }

    transitionInProgress = true;

    final currentFlow = ++flowSessionId;

    HapticFeedback.lightImpact();

    setState(() {
      textOpacity = 0.0;
      heartOpacity = 0.0;
      premiumPromptOpacity = 0.0;
      ritualHintOpacity = 0.0;
      pauseFeelOpacity = 0.0;
      revealGlowOpacity = 0.0;
      backgroundDepth = 0.82;
      textScale = 0.975;
    });

    await Future.delayed(const Duration(milliseconds: 880));

    if (!mounted || currentFlow != flowSessionId) {
      transitionInProgress = false;
      _transitionLock = false;
      return;
    }

    final selectedText = await getLockedOrNewWisdom(
      bypassLock: bypassLock,
    );

    setState(() {
      currentText = selectedText;
      screenStep = 4;
      revealGlowOpacity = 0.16;
    });

    await Future.delayed(const Duration(milliseconds: 260));

    if (!mounted || currentFlow != flowSessionId) {
      transitionInProgress = false;
      _transitionLock = false;
      return;
    }

    setState(() {
      textOpacity = 1.0;
      textScale = 1.0;
      backgroundDepth = 0.30;
    });

    await Future.delayed(const Duration(milliseconds: 280));

    if (!mounted || currentFlow != flowSessionId) {
      transitionInProgress = false;
      _transitionLock = false;
      return;
    }

    audioService.playRevealSound();
    HapticFeedback.selectionClick();

    await Future.delayed(const Duration(milliseconds: 900));

    if (!mounted || currentFlow != flowSessionId) {
      transitionInProgress = false;
      _transitionLock = false;
      return;
    }

    setState(() {
      heartOpacity = 1.0;
      revealGlowOpacity = 0.10;
    });

    await Future.delayed(const Duration(milliseconds: 520));

    if (!mounted || currentFlow != flowSessionId) {
      transitionInProgress = false;
      _transitionLock = false;
      return;
    }

    setState(() {
      premiumPromptOpacity = 1.0;
    });

    transitionInProgress = false;
    _transitionLock = false;
  }

  void resetToRevealScreen() async {
    HapticFeedback.selectionClick();

    await transitionToText(
      "Tap to Reveal",
      nextStep: 3,
    );
  }

  void copyCurrentWisdom() async {
    if (!wisdomRevealed) return;

    await Clipboard.setData(
      ClipboardData(text: currentText),
    );

    if (!mounted) return;

    HapticFeedback.selectionClick();
    showEastSnack("Copied quietly.");
  }

  Future<void> openPremiumScreen() async {
    if (navigationInProgress) return;

    navigationInProgress = true;
    HapticFeedback.selectionClick();

    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const PremiumScreen(),
        ),
      );

      if (!mounted) return;
      await loadPremiumStatus();
    } finally {
      if (mounted) {
        navigationInProgress = false;
      }
    }
  }

  Future<void> openSettings() async {
    if (navigationInProgress) return;

    navigationInProgress = true;
    HapticFeedback.selectionClick();

    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const SettingsScreen(),
        ),
      );

      if (!mounted) return;
      await loadPremiumStatus();
    } finally {
      if (mounted) {
        navigationInProgress = false;
      }
    }
  }

  void showRevealAnotherOptions() {
    HapticFeedback.selectionClick();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF111111),
          title: Text(
            "Ask Again",
            style: wisdomStyle(23),
          ),
          content: Text(
            "The ritual remains.\nThis path simply opens another door.",
            style: wisdomStyle(
              18,
              color: Colors.white70,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                showRewardedAdThenReveal();
              },
              child: Text(
                "Watch Ad",
                style: wisdomStyle(17),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                openPremiumScreen();
              },
              child: Text(
                "Go Premium",
                style: wisdomStyle(17),
              ),
            ),
          ],
        );
      },
    );
  }

  bool isCurrentFavorite() {
    return favorites.any(
      (item) => item.text == currentText,
    );
  }

  void showFavoriteLimitDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF111111),
          title: Text(
            "Favorite Limit Reached",
            style: wisdomStyle(22),
          ),
          content: Text(
            "Free users can save up to 3 wisdoms.",
            style: wisdomStyle(18),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                openPremiumScreen();
              },
              child: Text(
                "Unlock Premium",
                style: wisdomStyle(17),
              ),
            ),
          ],
        );
      },
    );
  }

  void toggleFavorite() async {
    if (!wisdomRevealed) return;

    HapticFeedback.selectionClick();

    if (isCurrentFavorite()) {
      favorites.removeWhere(
        (item) => item.text == currentText,
      );
    } else {
      if (!isPremium && favorites.length >= freeFavoriteLimit) {
        showFavoriteLimitDialog();
        return;
      }

      favorites.add(
        FavoriteItem(
          text: currentText,
          date: formattedToday(),
        ),
      );
    }

    setState(() {});
    await saveFavorites();
  }

  Future<void> saveFavorites() async {
    await storageService.saveFavorites(favorites);
  }

  Future<void> loadFavorites() async {
    final loadedFavorites = await storageService.loadFavorites(
      fallbackDate: formattedToday(),
    );

    if (!mounted) return;

    setState(() {
      favorites = loadedFavorites;
    });
  }

  Future<void> openFavorites() async {
    if (navigationInProgress) return;

    navigationInProgress = true;
    HapticFeedback.selectionClick();

    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FavoritesScreen(
            favorites: favorites,
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
    final textSize = screenStep == 0
        ? 42.0
        : wisdomRevealed
            ? 33.0
            : adReturnInProgress
                ? 24.0
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
            if (wisdomRevealed || adReturnInProgress || onPauseScreen)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 1400),
                    opacity: adReturnInProgress
                        ? 0.045
                        : onPauseScreen
                            ? 0.045
                            : revealGlowOpacity,
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
                onTap: handleMainTap,
                onLongPress: null,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 34,
                    ),
                    child: SizedBox(
                      height: 250,
                      child: Center(
                        child: AnimatedBuilder(
                          animation: pulseController,
                          builder: (context, child) {
                            final floatingY = wisdomRevealed
                                ? sin(pulseController.value * pi * 2) * 0.8
                                : adReturnInProgress || onPauseScreen
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
                              duration: const Duration(
                                milliseconds: 1250,
                              ),
                              curve: Curves.easeInOutCubic,
                              opacity: textOpacity,
                              child: AnimatedBuilder(
                                animation: pulseAnimation,
                                builder: (context, child) {
                                  return Opacity(
                                    opacity:
                                        onRevealScreen && !adReturnInProgress
                                            ? pulseAnimation.value
                                            : 1.0,
                                    child: child,
                                  );
                                },
                                child: screenStep == 0
                                    ? Column(
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
                                      )
                                    : onPauseScreen
                                        ? Row(
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
                                          )
                                        : Text(
                                            currentText,
                                            textAlign: TextAlign.center,
                                            style: wisdomStyle(
                                              textSize,
                                              color: wisdomRevealed
                                                  ? animatedTextColor
                                                  : finalColor,
                                              glow: wisdomRevealed ||
                                                  adReturnInProgress ||
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
            if (true)
              Positioned(
                top: 4,
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
                top: 4,
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
                  child: AnimatedOpacity(
                    duration: const Duration(
                      milliseconds: 1000,
                    ),
                    opacity: heartOpacity,
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
            if (wisdomRevealed)
              Positioned(
                left: 0,
                right: 0,
                top: MediaQuery.of(context).size.height / 2 + 124,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 900),
                  opacity: premiumPromptOpacity,
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: isPremium
                            ? () => revealWisdom(bypassLock: true)
                            : showRevealAnotherOptions,
                        child: Text(
                          "Ask Again",
                          textAlign: TextAlign.center,
                          style: wisdomStyle(
                            18,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isPremium ? "Premium Active" : "Curiosity Mode",
                        textAlign: TextAlign.center,
                        style: wisdomStyle(
                          14,
                          color: Colors.white38,
                        ),
                      ),
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

class FavoritesScreen extends StatelessWidget {
  final List<FavoriteItem> favorites;

  const FavoritesScreen({
    super.key,
    required this.favorites,
  });

  TextStyle favoriteStyle(double size) {
    return TextStyle(
      color: const Color(0xFFF4F0E8),
      fontSize: size,
      fontWeight: FontWeight.w300,
      fontFamily: 'CormorantGaramond',
      height: 1.35,
      letterSpacing: 0.3,
    );
  }

  TextStyle dateStyle() {
    return TextStyle(
      color: Colors.white54,
      fontSize: 15,
      fontWeight: FontWeight.w300,
      fontFamily: 'CormorantGaramond',
      letterSpacing: 0.4,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030303),
      appBar: AppBar(
        backgroundColor: const Color(0xFF030303),
        foregroundColor: const Color(0xFFF4F0E8),
        elevation: 0,
        title: Text(
          "Saved Reflections",
          style: favoriteStyle(24),
        ),
      ),
      body: favorites.isEmpty
          ? Center(
              child: Text(
                "No wisdom saved yet.",
                style: favoriteStyle(21).copyWith(
                  color: Colors.white54,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                24,
                18,
                24,
                32,
              ),
              itemCount: favorites.length,
              separatorBuilder: (context, index) {
                return const Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: 18,
                  ),
                  child: Divider(
                    color: Colors.white24,
                    thickness: 0.5,
                  ),
                );
              },
              itemBuilder: (context, index) {
                final item = favorites[index];

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.date,
                      style: dateStyle(),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.text,
                      style: favoriteStyle(24),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class GrainPainter extends CustomPainter {
  final double movement;
  final double intensity;

  const GrainPainter({
    required this.movement,
    required this.intensity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(7);
    final thinPoints = <Offset>[];
    final thickPoints = <Offset>[];

    for (int i = 0; i < 500; i++) {
      final baseX = random.nextDouble() * size.width;
      final baseY = random.nextDouble() * size.height;

      final driftX = sin(movement * pi * 2 + i) * 0.85;
      final driftY = cos(movement * pi * 2 + i * 0.71) * 0.85;

      final point = Offset(
        baseX + driftX,
        baseY + driftY,
      );

      if (random.nextDouble() > 0.72) {
        thickPoints.add(point);
      } else {
        thinPoints.add(point);
      }
    }

    final alpha = intensity * 0.72;

    canvas.drawPoints(
      PointMode.points,
      thinPoints,
      Paint()
        ..color = Colors.white.withValues(alpha: alpha)
        ..strokeWidth = 0.55,
    );

    canvas.drawPoints(
      PointMode.points,
      thickPoints,
      Paint()
        ..color = Colors.white.withValues(alpha: alpha)
        ..strokeWidth = 0.85,
    );
  }

  @override
  bool shouldRepaint(covariant GrainPainter oldDelegate) {
    return oldDelegate.movement != movement ||
        oldDelegate.intensity != intensity;
  }
}
