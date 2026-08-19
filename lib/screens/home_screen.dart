import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/latest_request_guard.dart';
import '../controllers/ritual_flow_controller.dart';
import '../models/favorite_item.dart';
import '../models/pending_daily_wisdom_reveal.dart';
import '../services/analytics_service.dart';
import '../services/app_services.dart' as app_services;
import '../services/audio_service.dart';
import '../services/daily_wisdom_access_service.dart';
import '../services/kept_discovery_hint_service.dart';
import '../services/rating_request_service.dart';
import '../services/saved_reflections_service.dart';
import '../services/storage_service.dart';
import '../services/widget_snapshot_service.dart';
import '../services/wisdom_notification_service.dart';
import '../services/wisdom_selector.dart';
import '../services/wisdom_share_service.dart';
import '../theme/east_design.dart';
import '../theme/muted_text_color.dart';
import '../utils/countdown_formatter.dart';
import '../utils/date_formatter.dart';
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
    this.ratingRequestService,
    this.analyticsService,
    this.widgetSnapshotService,
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
  final RatingRequestService? ratingRequestService;
  final AnalyticsService? analyticsService;
  final WidgetSnapshotService? widgetSnapshotService;
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
  double pauseFeelOpacity = 0.0;

  bool transitionInProgress = false;
  bool _transitionLock = false;
  int flowSessionId = 0;
  bool navigationInProgress = false;
  bool saveInteractionEnabled = false;
  bool _reduceMotion = false;
  bool _isInRitualSilence = false;
  bool _dailyStatusResolved = false;
  bool _dailyLockActive = false;
  bool _showingLockedWisdom = false;
  bool _saveOperationInProgress = false;
  bool _favoriteLimitOverlayVisible = false;
  bool _shareInProgress = false;
  bool _notificationPermissionOfferShowing = false;
  bool _notificationPermissionOfferScheduled = false;
  bool _revealPersistenceNeedsRetry = false;
  DateTime? _pendingRevealBoundaryForRetry;
  DateTime? _pendingNotificationUnlockAt;
  String? _lockedWisdomText;
  // Build 26 Phase 3D-C: the authoritative reveal identity for whatever
  // wisdom `currentText` currently displays, copied verbatim from the
  // `DailyWisdomRecord` an authoritative `DailyWisdomStatus`/
  // `DailyWisdomAccess`/`DailyWisdomPreparedReveal` carries it from — never
  // minted here. Both are null whenever `currentText` is not a genuinely
  // authoritative, identity-bearing reveal (e.g. "EAST.", ritual copy, or a
  // fresh reveal whose commit has not yet resolved), which is exactly the
  // condition `toggleFavorite()` and `currentFavorite()` gate on.
  String? currentRevealId;
  DateTime? currentRevealedAt;
  // Mirrors `_lockedWisdomText`: the reveal identity of the locked wisdom a
  // tap on the locked countdown would re-display via
  // `transitionToExistingWisdom`.
  String? _lockedWisdomRevealId;
  DateTime? _lockedWisdomRevealedAt;

  // Item 5 — Home left-swipe opens Kept. Cumulative drag offset for the
  // current gesture, reset on every swipe start; `_homeSwipeHandled` makes
  // sure a single gesture can only trigger navigation once.
  double _homeSwipeDx = 0;
  double _homeSwipeDy = 0;
  bool _homeSwipeHandled = false;

  // Item 6 / P13 — Save -> Kept micro-guidance.
  //
  // P13: the central "Keep this wisdom." discovery is now shown at most
  // once, ever -- on the device's first genuinely completed ritual only
  // (see `_pendingRitualOrdinal`/`_beginFirstUseKeepDiscovery` below) --
  // and, unlike the old twice-shown/auto-timeout hint this replaces, never
  // times out: it remains visible (and the ring keeps calmly breathing)
  // until the user actually taps the Keep ring. `_firstUseKeepDiscoveryActive`
  // is the persistent (survives navigation-away/backgrounding, cleared only
  // by an actual save) marker that this discovery is still owed to the
  // user; it is never reset merely because the app was backgrounded or the
  // user briefly navigated elsewhere (see `_resumePendingDiscoveryIfNeeded`).
  bool _firstUseKeepDiscoveryActive = false;
  String _keptDiscoveryHintText = '';
  double _keptDiscoveryHintOpacity = 0.0;
  bool _keptDiscoveryBreathActive = false;
  bool _keptIconEmphasized = false;
  Timer? _keptDiscoverySavedTextTimer;
  // P13: true from the moment the first-ever successful save completes the
  // central discovery until the user actually opens Kept via the top-right
  // control -- drives the (also no-timeout) top-right Kept-icon teaching
  // breath, and survives navigation/backgrounding exactly like
  // `_firstUseKeepDiscoveryActive` above (see `KeptDiscoveryHintService`'s
  // `keptNavDiscoveryPendingKey`).
  bool _keptNavDiscoveryActive = false;
  // The top-right Kept teaching breath chain's own timer (start delay, each
  // breath's own duration, and the pause between breaths).
  Timer? _keptIconEmphasisTimer;
  // The center save-ring breath chain's own timer (first-breath delay,
  // each breath's own duration, and the pause between breaths).
  Timer? _keptDiscoveryBreathResetTimer;
  int _keptDiscoverySessionId = 0;

  // P13: the ritual ordinal (1-based) of the reveal currently in flight,
  // set once `finishCommittedDailyWisdom` learns it from
  // `RatingRequestService.recordCompletedRitual` -- EAST's one
  // authoritative "genuinely completed ritual" counter, never a second,
  // competing one. `null` until known (or if it could not be determined --
  // see that method's own doc comment), and reset to `null` at the start
  // of every fresh reveal so a stale value from an earlier reveal can never
  // leak into the next one's notification/discovery decision.
  int? _pendingRitualOrdinal;

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

  /// Build 26 Phase 4H-6: guards the silent background `favorites` reload
  /// triggered by [app_services.keptStateRevisionNotifier] (an incoming
  /// CloudKit sync applying new/changed Kept or Reflection data while Home
  /// is already mounted) -- a dedicated instance, never shared with
  /// [accessRefreshGuard] (which guards an unrelated async operation,
  /// [updateNextWisdomMessage]), so the two can never cross-invalidate each
  /// other.
  final keptStateRefreshGuard = LatestRequestGuard();

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
    _isInRitualSilence = false;
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
      _isInRitualSilence = false;
      textOpacity = 1.0;
      textScale = 1.0;

      if (!onPauseScreen) {
        pauseFeelOpacity = 0.0;
      }

      if (wisdomRevealed) {
        saveControlOpacity = 1.0;
        postRevealMessageOpacity = 1.0;
      } else {
        saveControlOpacity = 0.0;
        saveInteractionEnabled = false;
        postRevealMessageOpacity = 0.0;
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
  late final RatingRequestService ratingRequestService;
  late final AnalyticsService analyticsService;
  late final WidgetSnapshotService widgetSnapshotService;
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
    // Build 26 Phase 4H-6: subscribe to the neutral incoming-Kept-state
    // signal for as long as Home stays mounted.
    app_services.keptStateRevisionNotifier.addListener(_onKeptStateChanged);
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
    ratingRequestService =
        widget.ratingRequestService ?? app_services.ratingRequestService;
    analyticsService = widget.analyticsService ?? app_services.analyticsService;
    widgetSnapshotService =
        widget.widgetSnapshotService ?? app_services.widgetSnapshotService;

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
    keptStateRefreshGuard.invalidate();

    WidgetsBinding.instance.removeObserver(this);
    app_services.purchaseService.removeListener(_syncKeeperStatus);
    app_services.keptStateRevisionNotifier.removeListener(_onKeptStateChanged);
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

  // Approved Ritual direction: the hamburger + two-circle chrome is absent
  // for every ritual beat (entrance through the ask) and returns only once
  // the wisdom is revealed (or the locked countdown, which is the same
  // settled, already-resolved state as the wisdom having been revealed
  // earlier today) — never before.
  bool get _chromeVisible => wisdomRevealed || onLockedCountdown;
  bool get mainRitualActionSemanticsEnabled {
    if (navigationInProgress || transitionInProgress || _transitionLock) {
      return false;
    }
    if (screenStep == 0) return _dailyStatusResolved;
    if (screenStep == 1 || screenStep == 2) return true;
    return wisdomRevealed && _revealPersistenceNeedsRetry;
  }

  bool get hideMainRitualContentSemantics {
    return _isInRitualSilence || textOpacity <= 0.01;
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
    // Build 26 Phase 3D-E (safety-gap correction, round 3 — direction
    // inversion): a single atomic startup sequence, run before
    // loadFavorites() below so the very first `favorites` read and the
    // first stable rendered Keep ring already reflect the corrected
    // identity — never an interactive empty-ring frame first.
    //
    // 1. Read the currently committed Daily Wisdom occurrence.
    // 2. Ask the read-only Kept resolver
    //    (SavedReflectionsService.resolveLegacyMigratedRevealIdForOccurrence)
    //    for a migrated Kept revealId candidate for that exact occurrence —
    //    never mutates Kept storage.
    // 3. Atomically reconcile/backfill the Daily Wisdom revealId for that
    //    same occurrence
    //    (DailyWisdomAccessService.reconcileRevealIdForOccurrence) — the
    //    only place either revealId is ever written.
    //
    // See KeptRepository.resolveLegacyMigratedRevealIdForOccurrence's and
    // DailyAccessRepository.reconcileRevealIdForOccurrence's doc comments
    // for the full rationale and safety rules. A migrated KeptRecord itself
    // is never touched here or anywhere else post-migration.
    await _reconcileDailyWisdomIdentity();
    await loadFavorites();
    await loadKeeperStatus();
    await updateNextWisdomMessage();
    await synchronizeUnlockNotification();
    await _resumePersistedDiscoveryStateIfNeeded();
    _maybeRequestAppRating();
  }

  // P13: recovers both first-use discovery phases from persisted state on
  // a cold start (a killed-and-relaunched app, not merely backgrounded --
  // see `_resumePendingDiscoveryIfNeeded` for the backgrounded/navigated-
  // away case, which uses the in-memory flags directly since the process
  // never died). Read only, never marks anything completed merely because
  // this ran; completion only ever happens via an actual save
  // (`_onWisdomSuccessfullyKept`) or an actual Kept-open (`openFavorites`).
  Future<void> _resumePersistedDiscoveryStateIfNeeded() async {
    try {
      final centralCompleted = await keptDiscoveryHintService.isCompleted();
      if (!centralCompleted &&
          await keptDiscoveryHintService.isCentralDiscoveryPending()) {
        _firstUseKeepDiscoveryActive = true;
      }

      final navCompleted =
          await keptDiscoveryHintService.isNavDiscoveryCompleted();
      if (!navCompleted &&
          await keptDiscoveryHintService.isNavDiscoveryPending()) {
        _keptNavDiscoveryActive = true;
      }
    } catch (_) {
      return;
    }
    _resumePendingDiscoveryIfNeeded();
  }

  // EAST. Phase 6 — App Store rating request.
  //
  // Deliberately gated on the idle `screenStep == 0` state alone (never on
  // `wisdomRevealed`/screen 4, the reveal itself): screen 0 is the one state
  // that is never mid-ritual, mid-reveal, mid-Keep, or mid-Reflection --
  // both the pre-ritual idle screen and the post-ritual locked-countdown
  // screen sit here (see `updateNextWisdomMessage`'s own reset-to-0 logic).
  // `screenStep` is in-memory-only and always starts at `0`, so this fires
  // at the two natural, always-settled entry points -- cold start
  // (`loadInitialState`) and foreground resume (`_resumeAccessState`) --
  // and is a safe no-op if the app happens to resume mid-ritual.
  // `RatingRequestService.maybeRequestReview` itself is the sole source of
  // truth for eligibility (4th completed ritual) and the "already
  // attempted" guard, so repeated calls here across rebuilds/resumes never
  // repeat the native request.
  void _maybeRequestAppRating() {
    if (!mounted) return;
    if (screenStep != 0) return;
    if (transitionInProgress || _transitionLock || navigationInProgress) {
      return;
    }
    unawaited(ratingRequestService.maybeRequestReview());
  }

  Future<void> _reconcileDailyWisdomIdentity() async {
    try {
      final status = await dailyWisdomAccessService.status();
      final text = status.lockedText;
      final revealedAt = status.revealedAt;
      final unlockAt = status.unlockAt;
      if (text == null || revealedAt == null || unlockAt == null) return;
      if (text == DailyWisdomAccessService.corruptRecordRecoveryText) return;

      // Step 2: read-only Kept-side lookup. Never mutates Kept storage —
      // a failure here must never block the Daily Access side backfill in
      // step 3, so it is caught independently.
      String? resolvedLegacyRevealId;
      try {
        resolvedLegacyRevealId = await savedReflectionsService
            .resolveLegacyMigratedRevealIdForOccurrence(
          wisdomText: text,
          committedRevealedAt: revealedAt,
          committedUnlockAt: unlockAt,
        );
      } catch (_) {
        resolvedLegacyRevealId = null;
      }

      // Step 3: atomic Daily Access side reconcile-or-backfill for the same
      // occurrence. Re-checks the persisted record against the expected
      // occurrence before applying anything — never applied to a different
      // occurrence than the one just read above.
      await dailyWisdomAccessService.reconcileRevealIdForOccurrence(
        expectedText: text,
        expectedRevealedAt: revealedAt,
        expectedUnlockAt: unlockAt,
        resolvedLegacyRevealId: resolvedLegacyRevealId,
      );
    } catch (_) {
      // Best-effort, one-time migration aid only — existing daily-access
      // and membership behavior remain usable if this fails for any
      // reason.
    }
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
    // P13: a foreground resume never killed the process, so the in-memory
    // `_firstUseKeepDiscoveryActive`/`_keptNavDiscoveryActive` flags (never
    // cleared by backgrounding -- only by an actual save/Kept-open) are
    // still authoritative; just re-present whichever is still owed.
    _resumePendingDiscoveryIfNeeded();
    _maybeRequestAppRating();
  }

  void showEastSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: EastColors.surface,
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
          await transitionToExistingWisdom(
            lockedWisdomText,
            revealId: _lockedWisdomRevealId,
            revealedAt: _lockedWisdomRevealedAt,
          );
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

  Future<void> transitionToExistingWisdom(
    String text, {
    String? revealId,
    DateTime? revealedAt,
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
        currentRevealId = revealId;
        currentRevealedAt = revealedAt;
        screenStep = 4;
        _showingLockedWisdom = true;
        textOpacity = 1.0;
        textScale = 1.0;
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
          _lockedWisdomRevealId = null;
          _lockedWisdomRevealedAt = null;
          nextWisdomMessage =
              status.unlockAt == null ? "" : "A new wisdom is ready.";

          if (onLockedCountdown || _showingLockedWisdom) {
            screenStep = 0;
            _showingLockedWisdom = false;
            currentText = "EAST.";
            currentRevealId = null;
            currentRevealedAt = null;
            textOpacity = 1.0;
            textScale = 1.0;
          }
        });
      }
      return;
    }

    String? lockedWisdomText;
    String? lockedRevealId;
    DateTime? lockedRevealedAt;
    final text = status.lockedText?.trim();
    if (text != null &&
        text.isNotEmpty &&
        text != DailyWisdomAccessService.corruptRecordRecoveryText) {
      lockedWisdomText = status.lockedText;
      lockedRevealId = status.revealId;
      lockedRevealedAt = status.revealedAt;
    }

    final message = CountdownFormatter.silenceMessage(status.remaining!);

    if (_canCommitAccessRefresh(refreshGeneration)) {
      setState(() {
        _dailyStatusResolved = true;
        _dailyLockActive = true;
        _lockedWisdomText = lockedWisdomText;
        _lockedWisdomRevealId = lockedRevealId;
        _lockedWisdomRevealedAt = lockedRevealedAt;
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

      // EAST. Phase 6: a durably committed, genuinely new reveal is the one
      // authoritative "ritual successfully completed" moment -- never an
      // interrupted or still-retrying reveal (those never reach here).
      // Recording is fire-and-forget local bookkeeping only; the actual
      // native rating request happens later, at a safe idle moment (see
      // `_maybeRequestAppRating`), never here mid-reveal.
      //
      // P13: this call's return value doubles as the ritual ordinal
      // (`_pendingRitualOrdinal`) the notification/discovery timing branch
      // reads once its own Timer fires, several seconds later -- ample
      // time for this single SharedPreferences round trip to resolve.
      // `_pendingRitualOrdinal` was already reset to `null` at the start of
      // this reveal (see the reveal-transition method above), so a stale
      // value can never leak in.
      unawaited(
        ratingRequestService.recordCompletedRitual().then((ordinal) {
          if (!mounted) return;
          _pendingRitualOrdinal = ordinal;
        }),
      );

      // EAST. Phase 7: the same authoritative "ritual successfully
      // completed" moment as the rating-eligibility bookkeeping directly
      // above. No parameter: `access.text`/`revealId`/`revealedAt` never
      // travel through this call.
      analyticsService.ritualCompleted();

      // EAST. Phase 11: the one authoritative "durably committed, genuinely
      // new reveal" moment the Medium Widget is allowed to mirror -- never
      // an interrupted or still-retrying reveal (those never reach here,
      // exactly like the rating/analytics calls directly above). The widget
      // never selects or reveals wisdom itself; this is the only place that
      // publishes a fresh occurrence to it.
      final freshUnlockAt = access.unlockAt;
      if (freshUnlockAt != null) {
        unawaited(
          widgetSnapshotService.publishRevealed(
            text: access.text,
            unlockAt: freshUnlockAt,
          ),
        );
      }
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
      // EAST. Phase 11: fire-and-forget, like every other widget-snapshot
      // publish call site -- this must never delay or gate the notification
      // synchronization (or anything awaiting this method, e.g. the rating
      // request that follows it at the idle entry points) on a platform
      // channel round trip. `_synchronizeWidgetSnapshot` never throws (both
      // `WidgetSnapshotService` methods already fail closed internally).
      unawaited(_synchronizeWidgetSnapshot(status));
    } catch (_) {
      // Notification synchronization must not affect daily access.
    }
  }

  /// EAST. Phase 11: reconciles the Medium Widget's snapshot against the
  /// current authoritative status -- called only from cold start and
  /// foreground resume (via [synchronizeUnlockNotification]'s own call
  /// sites), never from the 60-second countdown timer tick or any other
  /// per-frame/per-rebuild path. `publishRevealed`/`publishSilence` are
  /// themselves idempotent (`EastWidgetSnapshotStore` only asks WidgetKit to
  /// reload when the persisted snapshot actually changes), so a repeated
  /// reconciliation that finds nothing new is always a safe no-op.
  Future<void> _synchronizeWidgetSnapshot(DailyWisdomStatus status) async {
    final unlockAt = status.unlockAt;
    final lockedText = status.lockedText;
    if (!status.isReady && lockedText != null && unlockAt != null) {
      await widgetSnapshotService.publishRevealed(
        text: lockedText,
        unlockAt: unlockAt,
      );
    } else {
      await widgetSnapshotService.publishSilence();
    }
  }

  // P13: the exact same existing delay/trigger-timing infrastructure that
  // previously ALWAYS led to the native notification-permission prompt.
  // What happens once the Timer below fires now branches on
  // `_pendingRitualOrdinal` via an explicit, closed switch (see
  // `_runQueuedNotificationPermissionOffer`): ritual 1 begins the
  // first-use Keep discovery; ritual 2 alone reaches the native prompt;
  // every other ordinal (3+, or one that could not be determined) offers
  // neither, automatically -- it never falls through to the native prompt
  // "by default". The scheduling mechanism itself -- delay, guard flags,
  // single-flight behavior -- is unchanged from the pre-P13
  // implementation.
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
        // was still genuinely in flight.
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
        // which branch is taken.
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
          _isInRitualSilence) {
        return;
      }
      // P13 (locked contract): an explicit, closed three-way switch on the
      // ritual ordinal -- never an `!= 1`/`else` fallthrough. Ritual 1
      // begins the first-use Keep discovery and never reaches the native
      // prompt. Ritual 2 alone reaches the existing, unmodified
      // native-prompt path. Every other ordinal -- 3+, or undetermined
      // (`null`, e.g. a rating request already attempted, or a read/write
      // failure) -- does neither: the automatic offer fails closed rather
      // than falling through to the native prompt "by default". This also
      // means a missed ritual-2 timing window (app killed/backgrounded
      // before its own offer fired) is never silently deferred to ritual
      // 3 -- ordinal 3 simply matches neither case below.
      if (_pendingRitualOrdinal == 1) {
        _pendingNotificationUnlockAt = null;
        await _beginFirstUseKeepDiscovery();
        return;
      }
      if (_pendingRitualOrdinal == 2) {
        await _showNotificationPermissionOffer(unlockAt);
        return;
      }
      _pendingNotificationUnlockAt = null;
    } finally {
      _notificationPermissionOfferScheduled = false;
      _notificationPermissionOfferShowing = false;
    }
  }

  Future<void> _showNotificationPermissionOffer(DateTime unlockAt) async {
    if (!mounted) return;
    if (!await wisdomNotificationService.shouldOfferPermission()) {
      _pendingNotificationUnlockAt = null;
      // No native prompt is coming after all — the caller's own `finally`
      // (in `_runQueuedNotificationPermissionOffer`) clears both guard
      // flags.
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
    // Flag clearing happens exactly once, in the caller's own `finally`
    // block (`_runQueuedNotificationPermissionOffer`), regardless of which
    // path above was taken.
  }

  // P13 — the central "Keep this wisdom." first-use discovery. Reached
  // only once, ever, per device: from `_runQueuedNotificationPermissionOffer`
  // at the exact timing slot the native notification prompt would
  // otherwise have appeared, and only when `_pendingRitualOrdinal == 1`
  // (this device's first genuinely completed ritual -- see
  // `RatingRequestService.recordCompletedRitual`). Unlike the discovery
  // hint this replaces, there is deliberately no hide/timeout timer
  // anywhere in this method or in the breath chain it starts: the text and
  // the ring's calm breathing both remain until the user actually taps the
  // Keep ring (`_onWisdomSuccessfullyKept` is what ends it), or resume
  // identically after a navigation/backgrounding interruption (see
  // `_resumePendingDiscoveryIfNeeded`).
  Future<void> _beginFirstUseKeepDiscovery() async {
    if (!mounted || !wisdomRevealed) return;
    if (transitionInProgress || _transitionLock || _isInRitualSilence) return;
    if (_revealPersistenceNeedsRetry) return;
    if (navigationInProgress) return;
    if (_shareInProgress || _saveOperationInProgress) return;
    // Already kept (e.g. the user tapped the ring before this timing slot
    // even arrived) -- nothing left to teach for this reveal.
    if (isCurrentFavorite()) return;

    final reduceMotion = _reduceMotion;
    final session = ++_keptDiscoverySessionId;
    setState(() {
      _firstUseKeepDiscoveryActive = true;
      _keptDiscoveryHintText = 'Keep this wisdom.';
      _keptDiscoveryHintOpacity = 1.0;
      _keptDiscoveryBreathActive = false;
    });
    // Best-effort persisted bookkeeping (see `KeptDiscoveryHintService`'s
    // own doc comments): `recordDisplayShown` for continuity with the
    // service's existing display-count bookkeeping, and
    // `markCentralDiscoveryPending` so a killed/relaunched app can resume
    // showing this against the same still-revealed, still-unkept wisdom
    // (see `_resumePersistedDiscoveryStateIfNeeded`).
    unawaited(keptDiscoveryHintService.recordDisplayShown());
    unawaited(keptDiscoveryHintService.markCentralDiscoveryPending());

    if (!reduceMotion) {
      _keptDiscoveryBreathResetTimer?.cancel();
      _keptDiscoveryBreathResetTimer = Timer(
        _keptDiscoveryBreathFirstDelay,
        () => _startKeptDiscoveryBreath(session),
      );
    }
    // Deliberately no hide timer: this discovery never times out (see
    // this method's own doc comment).
  }

  // Re-presents the central discovery (text + breathing) after a
  // navigation-away/backgrounding interruption paused it, or after a cold
  // relaunch recovers it from persisted state -- never re-evaluates
  // eligibility/ordinal, since `_firstUseKeepDiscoveryActive` being true
  // already proves this device owes the user this discovery. Also resumes
  // the top-right Kept-navigation teaching breath under the same
  // circumstances. A no-op whenever neither is currently owed, or the
  // current screen state cannot show them (already kept, mid-transition,
  // navigating, etc).
  void _resumePendingDiscoveryIfNeeded() {
    if (!mounted) return;

    // The central discovery needs a stable, fully-revealed ritual view to
    // render text next to the ring, so it stays guarded on ritual
    // transition/navigation state.
    if (!transitionInProgress &&
        !_transitionLock &&
        !navigationInProgress &&
        _firstUseKeepDiscoveryActive &&
        wisdomRevealed &&
        !_isInRitualSilence &&
        !isCurrentFavorite() &&
        _keptDiscoveryHintOpacity <= 0.0) {
      final session = ++_keptDiscoverySessionId;
      setState(() {
        _keptDiscoveryHintText = 'Keep this wisdom.';
        _keptDiscoveryHintOpacity = 1.0;
        _keptDiscoveryBreathActive = false;
      });
      if (!_reduceMotion) {
        _keptDiscoveryBreathResetTimer?.cancel();
        _keptDiscoveryBreathResetTimer = Timer(
          _keptDiscoveryBreathFirstDelay,
          () => _startKeptDiscoveryBreath(session),
        );
      }
    }

    // The top-right nav breath deliberately is NOT gated on
    // transition/navigation state: unlike the central discovery, it does
    // not depend on a settled ritual view -- the icon it decorates is only
    // ever rendered in the tree when chrome is actually visible (see
    // `_chromeVisible`), which already self-gates its visual appearance.
    // Gating this on ritual-transition state too would create a real race
    // on cold start: `loadInitialState()`'s own call here can land while
    // the user's own tap has already kicked off
    // `transitionToExistingWisdom` (which holds `transitionInProgress`
    // true for over a second), and nothing would ever retry afterward --
    // silently losing the resumed animation for the rest of the session.
    if (_keptNavDiscoveryActive &&
        !_keptIconEmphasized &&
        _keptIconEmphasisTimer == null &&
        !_reduceMotion) {
      _scheduleKeptTopNavBreaths();
    }
  }

  // Loops for as long as `_firstUseKeepDiscoveryActive` is true -- there is
  // no fixed breath count under P13's no-timeout contract; the ring simply
  // keeps breathing, calmly, for as long as the discovery remains owed.
  // Guarded by the same `session` id every other discovery timer uses, so
  // a stale chain from a dismissed/replaced reveal can never touch a later
  // reveal's state.
  void _startKeptDiscoveryBreath(int session) {
    if (!mounted || session != _keptDiscoverySessionId) return;
    setState(() => _keptDiscoveryBreathActive = true);
    _keptDiscoveryBreathResetTimer = Timer(
      _keptDiscoveryBreathDuration,
      () => _endKeptDiscoveryBreath(session),
    );
  }

  void _endKeptDiscoveryBreath(int session) {
    if (!mounted || session != _keptDiscoverySessionId) return;
    setState(() => _keptDiscoveryBreathActive = false);
    if (!_firstUseKeepDiscoveryActive) return;
    _keptDiscoveryBreathResetTimer = Timer(
      _keptDiscoveryBreathPause,
      () => _startKeptDiscoveryBreath(session),
    );
  }

  // Correction: single central cancellation point for every discovery-hint
  // UI timer (breath reset, "Kept." dismissal, Kept-icon emphasis reset).
  // Called from `dispose`, navigation interruption and lifecycle
  // pause/inactive (both via `_dismissKeptDiscoveryHint` below), a
  // successful save, and the start of a replacement wisdom reveal — so no
  // discovery timer can ever outlive the state it was scheduled for. Never
  // clears `_firstUseKeepDiscoveryActive`/`_keptNavDiscoveryActive`
  // themselves -- those persist across interruption by design (see
  // `_resumePendingDiscoveryIfNeeded`).
  void _cancelAllDiscoveryTimers() {
    _keptDiscoverySavedTextTimer?.cancel();
    _keptDiscoverySavedTextTimer = null;
    _keptIconEmphasisTimer?.cancel();
    _keptIconEmphasisTimer = null;
    _keptDiscoveryBreathResetTimer?.cancel();
    _keptDiscoveryBreathResetTimer = null;
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
  // Every successful save permanently completes the central Kept
  // discovery — in-memory immediately, persisted best-effort — no matter
  // whether the discovery hint happened to be visible for this save. Only
  // the *visual* "Kept." transition is gated on the hint having actually
  // been showing; an ordinary save (hint not visible) still completes
  // discovery, it just shows no new "Kept." feedback for it.
  //
  // P13: the top-right Kept-navigation discovery begins ONLY on
  // `justCompletedDiscovery` — whether *this* save is the one that changes
  // central discovery from incomplete to completed (checked below via
  // `keptDiscoveryHintService.isCompleted()` *before* calling
  // `markCompleted()`). `hintWasShowing` must never gate it: a save made
  // before "Keep this wisdom." ever became visible still completes central
  // discovery for the first time, and still owes the user the "where Kept
  // lives" teaching. `hintWasShowing` is used below only to gate the
  // separate "Kept." text transition, which is a distinct concern.
  Future<void> _onWisdomSuccessfullyKept() async {
    final hintWasShowing = _keptDiscoveryHintOpacity > 0.0;

    // Cancels every pending discovery timer (breath chains, any stale
    // hint state) before deciding what — if anything — to show next, so
    // nothing from the pre-save state can fire later.
    _cancelAllDiscoveryTimers();
    _keptDiscoverySessionId++;
    _firstUseKeepDiscoveryActive = false;

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
    } else {
      setState(() {
        _keptDiscoveryHintOpacity = 0.0;
        _keptDiscoveryBreathActive = false;
      });
    }

    // P13: the top-right Kept-navigation discovery begins only once — on
    // the first successful save that completes central discovery,
    // regardless of whether the hint text was visible for it — and never
    // again on any later save. It has no fixed breath count and no
    // timeout: it stays pending (in memory and persisted) until the user
    // actually opens Kept via that control (see `openFavorites`).
    if (justCompletedDiscovery) {
      _keptNavDiscoveryActive = true;
      unawaited(keptDiscoveryHintService.markNavDiscoveryPending());
      if (!_reduceMotion) {
        _scheduleKeptTopNavBreaths();
      }
    }
  }

  // Starts the top-right Kept-navigation teaching breath chain. Not tied
  // to `_keptDiscoverySessionId` (that id belongs to the reveal-scoped
  // discovery-hint text/center-breath flow, which this emphasis is
  // deliberately independent of); guarded only by `mounted` and
  // `_keptNavDiscoveryActive`, and cancelled the same way every other
  // discovery timer is — via `_cancelAllDiscoveryTimers()` on dispose,
  // navigation, lifecycle change, or a new wisdom reveal (see
  // `_resumePendingDiscoveryIfNeeded` for how it resumes afterward).
  void _scheduleKeptTopNavBreaths() {
    _keptIconEmphasisTimer?.cancel();
    _keptIconEmphasisTimer = Timer(
      _keptTopNavBreathStartDelay,
      _startKeptTopNavBreath,
    );
  }

  void _startKeptTopNavBreath() {
    if (!mounted || !_keptNavDiscoveryActive) return;
    setState(() => _keptIconEmphasized = true);
    _keptIconEmphasisTimer = Timer(
      _keptTopNavBreathDuration,
      _endKeptTopNavBreath,
    );
  }

  void _endKeptTopNavBreath() {
    if (!mounted) return;
    setState(() => _keptIconEmphasized = false);
    if (!_keptNavDiscoveryActive) return;
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
        _isInRitualSilence ||
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
      _isInRitualSilence = false;
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

      // A replacement wisdom reveal (a new daily reveal in the same
      // session) must not inherit any of the previous wisdom's pending
      // discovery timers. `_pendingRitualOrdinal` is reset here too, so a
      // stale ordinal from an earlier reveal can never leak into this new
      // reveal's notification/discovery decision — `finishCommittedDailyWisdom`
      // (reached once this reveal's own commit resolves, well before its
      // notification/discovery timing slot fires) sets the real value.
      _cancelAllDiscoveryTimers();
      _pendingRitualOrdinal = null;

      setState(() {
        textOpacity = 1.0;
        saveControlOpacity = 0.0;
        saveInteractionEnabled = false;
        postRevealMessageOpacity = 0.0;
        pauseFeelOpacity = 0.0;
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
          Future<void>.delayed(const Duration(milliseconds: 1250));
      final askFadeComplete =
          Future<void>.delayed(const Duration(milliseconds: 1250));

      await askFadeComplete;

      if (!mounted || currentFlow != flowSessionId) return;

      setState(() {
        _isInRitualSilence = true;
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
              revealId: revealReady.revealId,
              revealedAt: revealReady.revealedAt,
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
        _isInRitualSilence = false;
        currentText = revealedAccess.text;
        currentRevealId = revealedAccess.revealId;
        currentRevealedAt = revealedAccess.revealedAt;
        screenStep = 4;
        _showingLockedWisdom = !revealedAccess.isNew;
        textOpacity = 1.0;
        textScale = 1.0;
      });

      // Correction: the notification-offer "scheduled" guard
      // (`_notificationPermissionOfferScheduled`) must become active in
      // the same synchronous turn the reveal itself becomes visible — not
      // deferred to a post-frame callback, closing a race window a real
      // Mac run once exposed. Queueing the offer here — synchronously,
      // before anything in this method yields control again — closes that
      // window entirely. This is only a reordering: the offer's own
      // delay/Timer, its guard conditions, and `wisdomRevealController.forward`
      // (still correctly deferred to the next frame below) are all
      // unchanged.
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
                currentRevealId = lateAccess.revealId;
                currentRevealedAt = lateAccess.revealedAt;
                saveControlOpacity = 1.0;
                saveInteractionEnabled = true;
                postRevealMessageOpacity = 1.0;
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
        });
        return;
      }

      if (!mounted || currentFlow != flowSessionId) return;

      finishCommittedDailyWisdom(committedAccess);
      _pendingRevealBoundaryForRetry = null;

      setState(() {
        currentRevealId = committedAccess.revealId;
        currentRevealedAt = committedAccess.revealedAt;
      });

      await Future.delayed(const Duration(milliseconds: 900));

      if (!mounted || currentFlow != flowSessionId) return;

      setState(() {
        _revealPersistenceNeedsRetry = false;
        saveControlOpacity = 1.0;
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
        currentRevealId = committedAccess.revealId;
        currentRevealedAt = committedAccess.revealedAt;
        saveControlOpacity = 1.0;
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
              currentRevealId = lateAccess.revealId;
              currentRevealedAt = lateAccess.revealedAt;
              saveControlOpacity = 1.0;
              saveInteractionEnabled = true;
              postRevealMessageOpacity = 1.0;
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
        // P13: still-pending first-use discovery (central or top-right
        // Kept-nav) resumes on return, exactly as it would after a
        // lifecycle resume -- neither phase was cleared by navigating
        // away, only paused visually.
        _resumePendingDiscoveryIfNeeded();
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
        _resumePendingDiscoveryIfNeeded();
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
        _resumePendingDiscoveryIfNeeded();
      }
    }
  }

  bool isCurrentFavorite() {
    return currentFavorite() != null;
  }

  /// Build 26 Phase 3D-C: identity, not text, is what determines whether
  /// the wisdom currently on screen is already Kept. Two different daily
  /// reveals can carry identical wisdom text (the wisdom pool repeats), so
  /// matching on `item.text == currentText` could wrongly report an
  /// unrelated occurrence as already kept. `currentRevealId` is only ever
  /// non-null once a reveal is genuinely authoritative (see
  /// `updateNextWisdomMessage`, `revealWisdom`, `retryRevealedWisdomCommit`,
  /// `transitionToExistingWisdom`), so a `null` here always means "not yet
  /// identified" rather than "not kept" — `toggleFavorite` gates on that
  /// distinction separately.
  FavoriteItem? currentFavorite() {
    final revealId = currentRevealId;
    if (revealId == null) return null;

    for (final item in favorites) {
      if (item.revealId == revealId) {
        return item;
      }
    }

    return null;
  }

  void showFavoriteLimitDialog() {
    if (!mounted) return;
    setState(() {
      _favoriteLimitOverlayVisible = true;
    });
  }

  void _dismissFavoriteLimitOverlay() {
    if (!mounted) return;
    setState(() {
      _favoriteLimitOverlayVisible = false;
    });
  }

  void _becomeKeeperFromLimitOverlay() {
    _dismissFavoriteLimitOverlay();
    unawaited(openKeeperScreen());
  }

  Widget _favoriteLimitDecisionLabel(
    String label, {
    required VoidCallback onTap,
    required Color color,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                  fontFamily: EastTypography.fontFamily,
                  fontFamilyFallback: EastTypography.fontFamilyFallback,
                  letterSpacing: 3.0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The approved full-field EAST decision takeover -- same visual system
  /// as Reflection's Delete Reflection (`reflection_screen.dart`'s
  /// `_deleteDecisionOverlay`), Journal Name
  /// (`journal_screen.dart`'s `_nameDecisionOverlay`), and Settings'
  /// Restore Purchases result (`settings_screen.dart`'s
  /// `_restoreResultOverlay`): the screen beneath stays mounted and
  /// strongly dimmed, no `AlertDialog`, no card, no rounded rectangle, no
  /// border, no shadow. Replaces the previous `AlertDialog`-based
  /// `showFavoriteLimitDialog`; the limit/entitlement logic that decides
  /// *when* this is shown is unchanged, only the presentation.
  Widget _favoriteLimitOverlay() {
    if (!_favoriteLimitOverlayVisible) return const SizedBox.shrink();

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !_favoriteLimitOverlayVisible,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          opacity: _favoriteLimitOverlayVisible ? 1.0 : 0.0,
          child: Container(
            key: const ValueKey('home-favorite-limit-overlay'),
            color: EastColors.overlay,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 34),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "Kept Limit",
                  textAlign: TextAlign.center,
                  style: _homeWisdomStyle(28),
                ),
                const SizedBox(height: 16),
                Text(
                  "Free users can keep up to 3 wisdoms.",
                  textAlign: TextAlign.center,
                  style: _homeWisdomStyle(
                    15,
                    color: EastColors.secondary,
                  ),
                ),
                const SizedBox(height: 44),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _favoriteLimitDecisionLabel(
                      'CANCEL',
                      onTap: _dismissFavoriteLimitOverlay,
                      color: EastColors.secondary,
                    ),
                    const SizedBox(width: 56),
                    _favoriteLimitDecisionLabel(
                      'BECOME A KEEPER',
                      onTap: _becomeKeeperFromLimitOverlay,
                      color: EastColors.ink,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
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

    // Build 26 Phase 3D-C: keeping a wisdom now requires its authoritative
    // reveal identity. A reveal that has not yet committed (or whose commit
    // is still pending after a timeout) has neither, and must never be
    // keepable — there is no genuine occurrence identity to keep yet.
    final revealId = currentRevealId;
    final revealedAt = currentRevealedAt;
    if (revealId == null || revealedAt == null) {
      showEastSnack("Wisdom could not be kept. Please try again.");
      return;
    }

    _saveOperationInProgress = true;

    try {
      // Build 26 Phase 3D-C compatibility contract (locked): `text`/`date`
      // are accepted for source/API compatibility only. `date` is never
      // parsed and never used to derive `revealedAt` — the authoritative
      // timestamp passed below is `revealedAt` (from `currentRevealedAt`)
      // alone, and identity remains `revealId` alone.
      final result = await savedReflectionsService.toggle(
        text: currentText,
        date: formattedToday(),
        isKeeper: isKeeper,
        revealId: revealId,
        revealedAt: revealedAt,
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
    final List<FavoriteItem> loadedFavorites;

    try {
      loadedFavorites = await savedReflectionsService.load();
    } catch (_) {
      // Build 26 Phase 3D-C: a load failure (e.g. protected storage
      // temporarily unavailable) must never be interpreted as "there are no
      // Kept wisdoms" — silently collapsing to `[]` here would visibly wipe
      // the Kept list for a transient failure. Leave `favorites` exactly as
      // it already was.
      return;
    }

    if (!mounted) return;

    setState(() {
      favorites = loadedFavorites;
    });
  }

  /// Build 26 Phase 4H-6: invoked synchronously by
  /// [app_services.keptStateRevisionNotifier] only after an incoming
  /// CloudKit sync has durably applied a Kept/Reflection content change
  /// while Home is mounted. Never shows a spinner or dialog, never resets
  /// scroll/navigation/ritual state, and never touches
  /// [loadKeeperStatus]/[updateNextWisdomMessage] or any Keeper-purchase
  /// refresh path -- this signal is scoped to `favorites` alone.
  void _onKeptStateChanged() {
    if (!mounted) return;
    final generation = keptStateRefreshGuard.begin();
    unawaited(_reloadFavoritesForIncomingStateChange(generation));
  }

  Future<void> _reloadFavoritesForIncomingStateChange(int generation) async {
    final List<FavoriteItem> loadedFavorites;
    try {
      loadedFavorites = await savedReflectionsService.load();
    } catch (_) {
      // A failed silent background refresh must never interrupt the
      // ritual UI with a dialog/snackbar -- leave `favorites` exactly as
      // it already was. A future incoming batch will retry.
      return;
    }
    // Both checks matter: `mounted` guards against a dispose that happened
    // while `load()` was in flight; `isCurrent` guards against a newer
    // incoming notification's own reload having already started (and
    // possibly already finished) after this one began.
    if (!mounted || !keptStateRefreshGuard.isCurrent(generation)) return;
    setState(() {
      favorites = loadedFavorites;
    });
  }

  Future<void> openFavorites() async {
    if (navigationInProgress || transitionInProgress || _transitionLock) return;

    // P13: opening Kept (via this control or the equivalent swipe gesture
    // -- both funnel through here) is the one authoritative "the user
    // found where Kept lives" moment. Stop the top-right teaching breath
    // and permanently mark this first-use discovery complete -- it never
    // automatically replays after this, on this device. A no-op (no
    // write) when the discovery was never pending in the first place.
    if (_keptNavDiscoveryActive) {
      _keptIconEmphasisTimer?.cancel();
      _keptIconEmphasisTimer = null;
      _keptNavDiscoveryActive = false;
      setState(() {
        _keptIconEmphasized = false;
      });
      unawaited(keptDiscoveryHintService.markNavDiscoveryCompleted());
    }

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
        _resumePendingDiscoveryIfNeeded();
      }
    }
  }

  // Item 5 — Home left-swipe opens Kept.
  //
  // Deliberately more restrictive than `openFavorites()`'s own guard: the
  // gesture must stay silent during Pause/Feel/Ask-from-your-heart, active
  // transitions, ritual silence, a pending persistence retry, the native
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
    if (_isInRitualSilence) return false;
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
      backgroundColor: EastColors.background,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const Positioned.fill(
              child: ColoredBox(color: EastColors.background),
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
                      !_isInRitualSilence &&
                      !_revealPersistenceNeedsRetry &&
                      wisdomRevealController.value >= 1.0,
                  wisdomShareOriginKey: _wisdomShareOriginKey,
                  onWisdomLongPress: shareCurrentWisdom,
                ),
              ),
            ),
            if (_chromeVisible) ...[
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
            _favoriteLimitOverlay(),
          ],
        ),
      ),
    );
  }
}
