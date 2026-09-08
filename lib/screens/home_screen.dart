import '../controllers/ritual_sound_preference_controller.dart';
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/appearance_preference_controller.dart';
import '../controllers/home_kept_controller.dart';
import '../controllers/home_swipe_to_kept_tracker.dart';
import '../controllers/locale_preference_controller.dart';
import '../controllers/notification_offer_gate.dart';
import '../controllers/ritual_access_coordinator.dart';
import '../controllers/ritual_access_view_state.dart';
import '../controllers/ritual_commit_coordinator.dart';
import '../controllers/ritual_completion_coordinator.dart';
import '../controllers/ritual_flow_controller.dart';
import '../models/favorite_item.dart';
import '../models/daily_wisdom_selection.dart';
import '../l10n/east_localizations.dart';
import '../models/pending_daily_wisdom_reveal.dart';
import '../services/analytics_service.dart';
import '../services/app_services.dart' as app_services;
import '../services/audio_service.dart';
import '../services/daily_wisdom_access_service.dart';
import '../services/daily_ritual_authority.dart';
import '../services/first_ritual_guidance_service.dart';
import '../services/kept_discovery_hint_service.dart';
import '../services/keeper_ritual_widget_coordinator.dart';
import '../services/rating_request_service.dart';
import '../services/ritual_audio_policy.dart';
import '../services/saved_reflections_service.dart';
import '../services/widget_presentation_sync_coordinator.dart';
import '../services/wisdom_notification_service.dart';
import '../services/wisdom_selector.dart';
import '../services/wisdom_share_service.dart';
import '../services/wisdom_localization_resolver.dart';
import '../theme/east_design.dart';
import '../theme/muted_text_color.dart';
import '../utils/countdown_formatter.dart';
import '../utils/date_formatter.dart';
import '../widgets/east_word_safe_text.dart';
import '../widgets/home/top_nav_ring.dart';
import 'keeper_screen.dart';
import 'saved_reflections_screen.dart';
import 'settings_screen.dart';

part '../widgets/home/home_ritual_widgets.dart';
part 'home_screen_kept.dart';

/// Shared by both countdown render sites' accessibility composition (Site
/// A's outer ritual `Semantics` label, Site B's post-reveal countdown
/// `Semantics` node) -- always built from the same integers the visible
/// `HH:MM:SS` token renders from, never by parsing a display string.
String _naturalCountdownDuration(
  BuildContext context,
  CountdownDuration duration,
) {
  final l10n = eastLocalizations(context);
  if (duration.seconds != 0) {
    if (duration.hours == 0 && duration.minutes == 0) {
      return l10n.remainingDurationSecondsOnly(duration.seconds);
    }
    return l10n.remainingDurationHoursMinutesSeconds(
        duration.hours, duration.minutes, duration.seconds);
  }
  if (duration.hours == 0) {
    return l10n.remainingDurationMinutesOnly(duration.minutes);
  }
  if (duration.minutes == 0) {
    return l10n.remainingDurationHoursOnly(duration.hours);
  }
  return l10n.remainingDurationHoursMinutes(duration.hours, duration.minutes);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.clock,
    this.audioService,
    this.dailyWisdomAccessService,
    this.savedReflectionsService,
    this.wisdomShareService,
    this.wisdomNotificationService,
    this.firstRitualGuidanceService,
    this.keptDiscoveryHintService,
    this.ratingRequestService,
    this.analyticsService,
    this.widgetPresentationSyncCoordinator,
    this.keeperRitualWidgetCoordinator,
    this.wisdomSelectorService,
    this.localePreferenceController,
    this.appearancePreferenceController,
    this.ritualSoundPreferenceController,
    this.dailyWisdomOperationTimeout = const Duration(seconds: 8),
    this.dailyWisdomStatusTimeout =
        DailyWisdomAccessService.defaultStatusTimeout,
  });

  final WisdomClock? clock;
  final AudioService? audioService;
  final DailyWisdomAccessService? dailyWisdomAccessService;
  final SavedReflectionsService? savedReflectionsService;
  final WisdomShareHandler? wisdomShareService;
  final WisdomNotificationService? wisdomNotificationService;
  final FirstRitualGuidanceService? firstRitualGuidanceService;
  final KeptDiscoveryHintService? keptDiscoveryHintService;
  final RatingRequestService? ratingRequestService;
  final AnalyticsService? analyticsService;

  /// EAST. 1.2 Slice 3 -- test-only injection seam. Production `WisdomApp`
  /// always supplies its one real coordinator (`lib/app.dart`); an isolated
  /// test that mounts `HomeScreen` directly and doesn't care about widget
  /// sync may safely leave this `null` -- `notifyFreshReveal` is only ever
  /// called through this field, never through an `app_services` fallback,
  /// since no such fallback singleton exists (ownership stays in
  /// `_WisdomAppState` only).
  final WidgetPresentationSyncCoordinator? widgetPresentationSyncCoordinator;
  final KeeperRitualWidgetCoordinator? keeperRitualWidgetCoordinator;
  final WisdomSelectorService? wisdomSelectorService;
  final LocalePreferenceController? localePreferenceController;
  final AppearancePreferenceController? appearancePreferenceController;
  final RitualSoundPreferenceController? ritualSoundPreferenceController;
  final Duration dailyWisdomOperationTimeout;
  final Duration dailyWisdomStatusTimeout;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const _wisdomPresentation = WisdomLocalizationResolver();
  final RitualFlowController ritualFlowController = RitualFlowController();

  RitualPhase get _phase => ritualFlowController.phase;

  /// Temporary black-box test/diagnostic compatibility. Ritual behavior is
  /// now driven exclusively by [_phase], never by numeric step values.
  int get screenStep => _phase.legacyStep;

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
  // Phase 5G: last-seen effective locale, so `didChangeDependencies` can
  // detect a genuine language change (explicit override or a resolved
  // System Default change) and refresh the two pieces of EAST.-authored
  // presentation that are otherwise only ever computed once and cached in
  // state -- the daily-lock/countdown message and the scheduled
  // notification's copy -- instead of leaving stale-locale text to sit
  // until the next unrelated trigger (60-second timer tick, resume, etc.).
  // `null` only before the very first `didChangeDependencies` call.
  Locale? _lastKnownLocale;
  bool _isInRitualSilence = false;
  RitualAccessViewState _accessViewState =
      const RitualAccessViewState.unresolved();
  bool _showingLockedWisdom = false;
  bool _readingPreviousWisdom = false;
  bool _saveOperationInProgress = false;
  bool _favoriteLimitOverlayVisible = false;
  bool _shareInProgress = false;
  late final FirstRitualGuidanceService firstRitualGuidanceService;
  Timer? _firstRitualGuidanceTimer;
  bool _firstRitualGuidanceEligible = false;
  bool _firstRitualGuidanceVisible = false;
  final NotificationOfferGate _notificationOfferGate = NotificationOfferGate();
  bool _revealPersistenceNeedsRetry = false;
  DateTime? _pendingRevealBoundaryForRetry;
  DateTime? _pendingNotificationUnlockAt;
  // Build 26 Phase 3D-C: the authoritative reveal identity for whatever
  // wisdom `currentText` currently displays, copied verbatim from the
  // `DailyWisdomRecord` an authoritative `DailyWisdomStatus`/
  // `DailyWisdomAccess`/`DailyWisdomPreparedReveal` carries it from — never
  // minted here. Both are null whenever `currentText` is not a genuinely
  // authoritative, identity-bearing reveal (e.g. "EAST.", ritual copy, or a
  // fresh reveal whose commit has not yet resolved), which is exactly the
  // condition `toggleFavorite()` and `currentFavorite()` gate on.
  String? currentRevealId;
  String? currentWisdomId;
  DateTime? currentRevealedAt;

  // Item 5 — Home left-swipe opens Kept. Navigation and ritual eligibility
  // stay here; the gesture geometry and one-trigger guard are isolated.
  final HomeSwipeToKeptTracker _swipeToKeptTracker = HomeSwipeToKeptTracker();

  // First-use text may remain until saved, but decorative motion never loops.
  bool _firstUseKeepDiscoveryActive = false;
  String _keptDiscoveryHintText = '';
  double _keptDiscoveryHintOpacity = 0.0;
  bool _keptDiscoveryBreathActive = false;
  bool _saveBreathPlayedForPresentation = false;
  static const _ringBreathDuration = Duration(seconds: 3);
  static const _saveFeedbackDuration = Duration(seconds: 2);
  late final AnimationController _saveRingBreathController;
  late final AnimationController _saveFeedbackController;
  late final AnimationController _keptFeedbackController;
  bool _saveFeedbackVisible = false;
  bool _keptFeedbackVisible = false;
  bool _saveHelpVisible = false;
  bool _keptHelpVisible = false;
  // Retain existing first-use completion bookkeeping across upgrades. It no
  // longer starts a repeating animation on launch or resume.
  bool _keptNavDiscoveryActive = false;

  // P13: the ritual ordinal (1-based) of the reveal currently in flight,
  // set once `finishCommittedDailyWisdom` learns it from
  // `RatingRequestService.recordCompletedRitual` -- EAST's one
  // authoritative "genuinely completed ritual" counter, never a second,
  // competing one. `null` until known (or if it could not be determined --
  // see that method's own doc comment), and reset to `null` at the start
  // of every fresh reveal so a stale value from an earlier reveal can never
  // leak into the next one's notification/discovery decision.
  int? _pendingRitualOrdinal;

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

  bool isKeeper = false;

  late AnimationController pulseController;
  late final AnimationController wisdomRevealController;
  late final Animation<double> wisdomRevealAnimation;
  late final AnimationController askFadeController;
  late final Animation<double> askFadeAnimation;

  Timer? countdownTimer;
  DateTime? _countdownResolvedAt;
  bool _countdownExpiryChecked = false;

  CountdownDuration? get _liveCountdownDuration {
    final duration = _accessViewState.countdownDuration;
    if (duration == null) return null;
    final elapsed = _countdownResolvedAt == null
        ? Duration.zero
        : revealBoundaryNow().difference(_countdownResolvedAt!);
    return CountdownFormatter.resolve(Duration(
            hours: duration.hours,
            minutes: duration.minutes,
            seconds: duration.seconds) -
        (elapsed.isNegative ? Duration.zero : elapsed));
  }

  late final AudioService audioService = widget.audioService ?? AudioService();
  late final _ritualSound = widget.ritualSoundPreferenceController ??
      app_services.ritualSoundPreferenceController;

  void _soundPreferenceChanged() {
    if (!_ritualSound.canPlay) unawaited(audioService.stop());
  }

  RitualAudioPolicy get _audioPolicy =>
      RitualAudioPolicy.forLocale(Localizations.localeOf(context),
          mode: _ritualSound.canPlay
              ? RitualSoundMode.sound
              : RitualSoundMode.silent);

  late final DailyWisdomAccessService dailyWisdomAccessService;
  late final SavedReflectionsService savedReflectionsService;
  late final WisdomShareHandler wisdomShareService;
  late final WisdomNotificationService wisdomNotificationService;
  late final KeptDiscoveryHintService keptDiscoveryHintService;
  late final RatingRequestService ratingRequestService;
  late final AnalyticsService analyticsService;
  late final RitualAccessCoordinator ritualAccessCoordinator;
  late final RitualCommitCoordinator ritualCommitCoordinator;
  late final RitualCompletionCoordinator ritualCompletionCoordinator;
  late final HomeKeptController homeKeptController;
  List<FavoriteItem> get favorites => homeKeptController.items;
  final GlobalKey _wisdomShareOriginKey = GlobalKey();

  void startCountdownTimer() {
    if (countdownTimer?.isActive ?? false) return;

    countdownTimer?.cancel();
    countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        if (!mounted) return;
        final duration = _liveCountdownDuration;
        final expired = duration != null &&
            duration.hours == 0 &&
            duration.minutes == 0 &&
            duration.seconds == 0;
        if (timer.tick % 60 == 0 || (expired && !_countdownExpiryChecked)) {
          _countdownExpiryChecked = expired;
          unawaited(updateNextWisdomMessage());
        } else if (duration != null && !navigationInProgress) {
          // Presentation tick only; authority and storage keep their existing
          // minute refresh, with an additional check at the actual boundary.
          setState(() {});
        }
      },
    );
  }

  void stopCountdownTimer() {
    countdownTimer?.cancel();
    countdownTimer = null;
  }

  /// A [CountdownPresentation] (sentence + the duration stored in
  /// [_accessViewState]) is built fresh from this and the live
  /// `eastLocalizations(context)` at build/semantics time, never cached, so
  /// an explicit or System Default locale change updates the visible
  /// sentence and accessibility phrase immediately -- never a stale,
  /// previously-localized presentation frozen at an earlier build.
  ///
  /// Builds the current [CountdownPresentation] from [_accessViewState]
  /// and the live locale, or `null` when no countdown is active. Never
  /// cached in state.
  CountdownPresentation? _currentCountdownPresentation(BuildContext context) {
    final duration = _liveCountdownDuration;
    if (duration == null) return null;
    return CountdownPresentation(
      sentence: eastLocalizations(context).returnWhenSilenceOpensAgain,
      duration: duration,
    );
  }

  late final WisdomSelectorService wisdomSelector =
      widget.wisdomSelectorService ?? WisdomSelectorService();

  @override
  void initState() {
    super.initState();
    _ritualSound.addListener(_soundPreferenceChanged);
    unawaited(_ritualSound.load());

    WidgetsBinding.instance.addObserver(this);
    app_services.purchaseService.addListener(_syncKeeperStatus);
    // Build 26 Phase 4H-6: subscribe to the neutral incoming-Kept-state
    // signal for as long as Home stays mounted.
    app_services.keptStateRevisionNotifier.addListener(_onKeptStateChanged);
    dailyWisdomAccessService = widget.dailyWisdomAccessService ??
        app_services.createDailyWisdomAccessService(
          clock: widget.clock,
          statusTimeout: widget.dailyWisdomStatusTimeout,
        );
    savedReflectionsService =
        widget.savedReflectionsService ?? app_services.savedReflectionsService;
    homeKeptController = HomeKeptController(
      loadItems: savedReflectionsService.load,
      keepWisdom: (request) async {
        final result = await savedReflectionsService.toggle(
          text: request.text,
          date: request.date,
          isKeeper: request.isKeeper,
          revealId: request.revealId,
          revealedAt: request.revealedAt,
          wisdomId: request.wisdomId,
        );
        return HomeKeptWriteResult(
          items: result.items,
          limitReached: result.limitReached,
        );
      },
    );
    wisdomShareService =
        widget.wisdomShareService ?? app_services.wisdomShareService;
    wisdomNotificationService = widget.wisdomNotificationService ??
        app_services.wisdomNotificationService;
    firstRitualGuidanceService =
        widget.firstRitualGuidanceService ?? FirstRitualGuidanceService();
    keptDiscoveryHintService = widget.keptDiscoveryHintService ??
        app_services.keptDiscoveryHintService;
    ratingRequestService =
        widget.ratingRequestService ?? app_services.ratingRequestService;
    analyticsService = widget.analyticsService ?? app_services.analyticsService;
    ritualAccessCoordinator = RitualAccessCoordinator(
      loadStatus: dailyWisdomAccessService.status,
    );
    ritualCommitCoordinator = RitualCommitCoordinator(
      timeout: widget.dailyWisdomOperationTimeout,
    );
    ritualCompletionCoordinator = RitualCompletionCoordinator(
      recordCompletedRitual: ratingRequestService.recordCompletedRitual,
      trackRitualCompletion: analyticsService.ritualCompleted,
      publishFreshWidgetReveal:
          widget.widgetPresentationSyncCoordinator?.notifyFreshReveal,
      refreshDailyAccessPresentation: updateNextWisdomMessage,
      scheduleWisdomUnlock:
          wisdomNotificationService.scheduleFromAuthoritativeUnlock,
    );

    pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
    )..repeat(reverse: true);

    _saveRingBreathController = AnimationController(
      vsync: this,
      duration: _ringBreathDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _keptDiscoveryBreathActive = false);
        }
      });
    _keptFeedbackController = AnimationController(
      vsync: this,
      duration: _ringBreathDuration,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _keptFeedbackVisible = false);
        }
      });
    _saveFeedbackController = AnimationController(
      vsync: this,
      duration: _saveFeedbackDuration,
      // Keep the acknowledgement readable with system Reduce Motion. The
      // decorative ring is suppressed separately; this text only fades.
      animationBehavior: AnimationBehavior.preserve,
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() {
            _saveFeedbackVisible = false;
            _keptFeedbackVisible =
                !_reduceMotion && wisdomRevealed && !navigationInProgress;
          });
          if (_keptFeedbackVisible) {
            _keptFeedbackController.forward(from: 0);
          }
        }
      });

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

    unawaited(
      loadInitialState().then<void>((_) {
        if (mounted) _scheduleFirstRitualGuidance();
      }).catchError((_) {}),
    );
    unawaited(_initializeFirstRitualGuidance());
    startCountdownTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (_reduceMotion != reduceMotion) {
      _reduceMotion = reduceMotion;
      if (_reduceMotion) {
        pulseController.stop();
        pulseController.value = 0.5;
        _saveRingBreathController.stop();
        _keptFeedbackController.stop();
        _keptDiscoveryBreathActive = false;
        _keptFeedbackVisible = false;
      } else if (WidgetsBinding.instance.lifecycleState ==
              AppLifecycleState.resumed &&
          !pulseController.isAnimating) {
        pulseController.repeat(reverse: true);
      }
    }

    final locale = Localizations.localeOf(context);
    if (_lastKnownLocale != locale) {
      final isFirstCall = _lastKnownLocale == null;
      _lastKnownLocale = locale;

      // Always kept in sync with the current locale -- including the very
      // first call, since `WisdomNotificationService`'s own default (used
      // by the app-wide singleton, which has no `BuildContext` of its own
      // to resolve a locale from) is English regardless of which locale
      // the app actually launches into.
      wisdomNotificationService.updateCopy(
        WisdomNotificationCopy(eastLocalizations(context)),
      );

      if (!isFirstCall) {
        // Presentation-only refresh: recomputes the daily-lock/countdown
        // message (`currentText` while that surface is active) in the newly
        // language, without touching `unlockAt`, the daily lock, or any
        // persisted wisdom/notification-trigger state. The initial value is
        // already computed by the normal startup load path, so this only
        // needs to fire on a genuine subsequent change.
        unawaited(updateNextWisdomMessage());
        // `synchronizeUnlockNotification` -> `WisdomNotificationService
        // .synchronizeWithStatus` is the exact same reconciliation already
        // used at resume/launch/Settings-return: it only ever touches an
        // *already-authorized* pending reminder (never schedules for a
        // user who never opted in, never re-enables a denied one), and
        // replaces it at the identical `unlockAt` -- the copy update above
        // is the only reason this particular call changes its title/body.
        unawaited(synchronizeUnlockNotification());
      }
    }
  }

  @override
  void dispose() {
    flowSessionId++;
    invalidateDelayedCallbacks();
    ritualAccessCoordinator.dispose();
    homeKeptController.dispose();

    WidgetsBinding.instance.removeObserver(this);
    app_services.purchaseService.removeListener(_syncKeeperStatus);
    app_services.keptStateRevisionNotifier.removeListener(_onKeptStateChanged);
    stopCountdownTimer();
    _notificationOfferGate.dispose();
    _firstRitualGuidanceTimer?.cancel();
    _saveRingBreathController.dispose();
    _keptFeedbackController.dispose();
    _saveFeedbackController.dispose();
    pulseController.dispose();
    wisdomRevealController.dispose();
    askFadeController.dispose();
    _ritualSound.removeListener(_soundPreferenceChanged);
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
      _hideFirstRitualGuidance();

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
      _scheduleFirstRitualGuidance();
    }
  }

  bool get onPauseScreen => _phase.isPause;
  bool get onHeartScreen => _phase.isHeart;
  bool get wisdomRevealed => _phase.isRevealed;
  bool get onLockedCountdown => _phase.isLockedCountdown;

  // Approved Ritual direction: the hamburger + Kept chrome is absent
  // for every ritual beat (entrance through the ask) and returns only once
  // the wisdom is revealed (or the locked countdown, which is the same
  // settled, already-resolved state as the wisdom having been revealed
  // earlier today) — never before.
  bool get _chromeVisible => wisdomRevealed || onLockedCountdown;
  bool get mainRitualActionSemanticsEnabled {
    if (navigationInProgress || transitionInProgress || _transitionLock) {
      return false;
    }
    if (_phase == RitualPhase.launch) return _accessViewState.isResolved;
    if (_phase == RitualPhase.pause || _phase == RitualPhase.heart) return true;
    return wisdomRevealed && _revealPersistenceNeedsRetry;
  }

  bool get hideMainRitualContentSemantics {
    return _isInRitualSilence || textOpacity <= 0.01;
  }

  String? mainRitualSemanticLabel(BuildContext context) {
    final l10n = eastLocalizations(context);
    if (hideMainRitualContentSemantics) return null;
    if (_phase == RitualPhase.launch) return 'EAST.';
    if (onPauseScreen) {
      return pauseFeelOpacity < 1.0 ? l10n.pause : '${l10n.pause} ${l10n.feel}';
    }
    if (onHeartScreen) return l10n.askFromYourHeart;
    // Site A is the sole owner of the countdown announcement here: composed
    // from the same `CountdownDuration` integers the visible `HH:MM:SS` token
    // renders from, never from a parsed display string, and never the raw
    // `HH:MM:SS` token itself. Returning a non-null label here makes the outer
    // Semantics own the announcement and (via `excludeSemantics: label !=
    // null` below) suppresses the inner Text's own duplicate node.
    if (onLockedCountdown) {
      final presentation = _currentCountdownPresentation(context);
      if (presentation == null) return null;
      return '${presentation.sentence} '
          '${_naturalCountdownDuration(context, presentation.duration)}';
    }
    if (wisdomRevealed && _revealPersistenceNeedsRetry) {
      return l10n.wisdomCouldNotBeKept;
    }
    return null;
  }

  String? mainRitualSemanticHint(BuildContext context) {
    if (!_firstRitualGuidanceEligible ||
        hideMainRitualContentSemantics ||
        !mainRitualActionSemanticsEnabled) {
      return null;
    }
    if (_phase == RitualPhase.launch) {
      return eastLocalizations(context).tapAnywhereToBegin;
    }
    if (_phase == RitualPhase.pause && pauseFeelOpacity < 1.0) {
      return eastLocalizations(context).tapWhenReady;
    }
    return null;
  }

  String _firstRitualGuidanceText(BuildContext context) {
    if (_phase == RitualPhase.pause) {
      return eastLocalizations(context).tapWhenReady;
    }
    return eastLocalizations(context).tapAnywhereToBegin;
  }

  Future<void> _initializeFirstRitualGuidance() async {
    final shouldShow = await firstRitualGuidanceService.shouldShow();
    if (!mounted || !shouldShow) return;
    setState(() {
      _firstRitualGuidanceEligible = true;
    });
    _scheduleFirstRitualGuidance();
  }

  void _scheduleFirstRitualGuidance() {
    _firstRitualGuidanceTimer?.cancel();
    if (!_firstRitualGuidanceEligible ||
        (_phase == RitualPhase.launch && !_accessViewState.isResolved) ||
        (_phase != RitualPhase.launch &&
            !(_phase == RitualPhase.pause && pauseFeelOpacity < 1.0))) {
      return;
    }

    final expectedPhase = _phase;
    final delay = expectedPhase == RitualPhase.launch
        ? const Duration(milliseconds: 650)
        : const Duration(milliseconds: 850);
    _firstRitualGuidanceTimer = Timer(delay, () {
      if (!mounted ||
          !_firstRitualGuidanceEligible ||
          _phase != expectedPhase ||
          (expectedPhase == RitualPhase.launch &&
              !_accessViewState.isResolved) ||
          (expectedPhase == RitualPhase.pause && pauseFeelOpacity >= 1.0)) {
        return;
      }
      setState(() {
        _firstRitualGuidanceVisible = true;
      });
    });
  }

  void _hideFirstRitualGuidance() {
    _firstRitualGuidanceTimer?.cancel();
    if (!mounted || !_firstRitualGuidanceVisible) return;
    setState(() {
      _firstRitualGuidanceVisible = false;
    });
  }

  void _completeFirstRitualGuidance() {
    _firstRitualGuidanceTimer?.cancel();
    if (!_firstRitualGuidanceEligible) return;
    if (mounted) {
      setState(() {
        _firstRitualGuidanceEligible = false;
        _firstRitualGuidanceVisible = false;
      });
    } else {
      _firstRitualGuidanceEligible = false;
      _firstRitualGuidanceVisible = false;
    }
    unawaited(firstRitualGuidanceService.markCompleted());
  }

  Future<void> loadInitialState() async {
    await dailyWisdomAccessService.reconcileAccountAuthority();
    // A Keeper widget can complete the ritual while Flutter is terminated.
    // Commit that provisional reveal before Home performs its first status
    // read, so the app enters the same locked occurrence rather than
    // offering a second ritual.
    await widget.keeperRitualWidgetCoordinator?.reconcileBeforeHome();
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
    if (_phase != RitualPhase.launch) return;
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
    final keeperValue = app_services.purchaseService.resolveKeeperAccess();

    if (!mounted) return;

    setState(() {
      isKeeper = keeperValue;
    });
  }

  Future<void> _resumeAccessState() async {
    await dailyWisdomAccessService.reconcileAccountAuthority();
    await widget.keeperRitualWidgetCoordinator?.reconcileBeforeHome();
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
        backgroundColor: EastColors.of(context).surface,
        duration: const Duration(milliseconds: 1400),
        content: Text(
          message,
          style: _homeWisdomStyle(context, 17),
        ),
      ),
    );
  }

  Future<void> _showDailyAuthorizationFailure(Object error, int flow) async {
    DailyWisdomAccess? cached;
    try {
      cached = await dailyWisdomAccessService.lastOpenedWisdom();
    } catch (_) {}
    if (!mounted || !isCurrentFlow(flow)) return;
    final l10n = eastLocalizations(context);
    final reason = error is DailyRitualAuthorityException
        ? error.reason
        : error is TimeoutException
            ? DailyRitualAuthorityFailure.connectionRequired
            : DailyRitualAuthorityFailure.unavailable;
    final message = switch (reason) {
      DailyRitualAuthorityFailure.iCloudRequired =>
        l10n.dailyRitualICloudRequired,
      DailyRitualAuthorityFailure.connectionRequired =>
        l10n.dailyRitualConnectionRequired,
      DailyRitualAuthorityFailure.unavailable => l10n.dailyRitualUnavailable,
    };
    final previous = cached;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: EastColors.of(context).surface,
      duration: const Duration(seconds: 8),
      content: Text(message, style: _homeWisdomStyle(context, 17)),
      action: previous == null
          ? null
          : SnackBarAction(
              label: l10n.dailyRitualPreviousWisdom,
              textColor: EastColors.of(context).ink,
              onPressed: () {
                if (!isCurrentFlow(flow)) return;
                unawaited(transitionToExistingWisdom(previous.text,
                    revealId: previous.revealId,
                    revealedAt: previous.revealedAt,
                    wisdomId: previous.wisdomId,
                    keepVisibleAfterExpiry: true));
              },
            ),
    ));
  }

  void _handleWisdomRevealStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted || !wisdomRevealed) {
      return;
    }
    _startSaveRingBreathIfReady();
    setState(() {});
  }

  void _startSaveRingBreathIfReady() {
    if (!mounted ||
        !wisdomRevealed ||
        navigationInProgress ||
        _saveBreathPlayedForPresentation ||
        _reduceMotion ||
        !wisdomRevealController.isCompleted ||
        saveControlOpacity < 1 ||
        _revealPersistenceNeedsRetry ||
        _saveOperationInProgress ||
        isCurrentFavorite()) {
      return;
    }
    _saveBreathPlayedForPresentation = true;
    setState(() => _keptDiscoveryBreathActive = true);
    _saveRingBreathController.forward(from: 0);
  }

  Future<void> handleMainTap() async {
    if (transitionInProgress || _transitionLock) return;

    invalidateDelayedCallbacks();

    if (_phase == RitualPhase.launch) {
      _hideFirstRitualGuidance();
      if (_ritualSound.canPlay) HapticFeedback.selectionClick();

      final launchFlowSession = flowSessionId;
      transitionInProgress = true;
      await updateNextWisdomMessage();

      if (!mounted || launchFlowSession != flowSessionId) return;

      transitionInProgress = false;

      if (!_accessViewState.isResolved) {
        _scheduleFirstRitualGuidance();
        return;
      }

      if (_accessViewState.isLocked) {
        _completeFirstRitualGuidance();
        final lockedWisdom = _accessViewState.wisdom;
        if (lockedWisdom == null) {
          final countdown = _currentCountdownPresentation(context);
          if (countdown == null) return;
          await transitionToText(
            countdown.plainText,
            nextPhase: RitualPhase.lockedCountdown,
          );
        } else {
          await transitionToExistingWisdom(
            lockedWisdom.text,
            revealId: lockedWisdom.revealId,
            revealedAt: lockedWisdom.revealedAt,
            wisdomId: lockedWisdom.wisdomId,
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
          _playVoiceCue(audioService.playPauseSound);
        },
      );

      await transitionToText(
        eastLocalizations(context).pause,
        nextPhase: RitualPhase.pause,
      );
      _scheduleFirstRitualGuidance();

      return;
    }

    if (_phase == RitualPhase.pause) {
      _completeFirstRitualGuidance();
      if (_ritualSound.canPlay) HapticFeedback.lightImpact();

      if (pauseFeelOpacity < 1.0) {
        final callbackSession = delayedCallbackSession;
        final callbackFlowSession = flowSessionId + 1;

        Future.delayed(
          const Duration(milliseconds: 200),
          () {
            if (!mounted) return;
            if (callbackSession != delayedCallbackSession) return;
            if (callbackFlowSession != flowSessionId) return;
            _playVoiceCue(audioService.playFeelSound);
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
            _playVoiceCue(audioService.playHeartSound);
          },
        );
        await transitionToText(
          eastLocalizations(context).askFromYourHeart,
          nextPhase: RitualPhase.heart,
        );
      }

      return;
    }

    if (_phase == RitualPhase.heart) {
      await revealWisdom();
      return;
    }

    if (wisdomRevealed && _revealPersistenceNeedsRetry) {
      await retryRevealedWisdomCommit();
      return;
    }
  }

  void _playVoiceCue(Future<void> Function() play) {
    if (!_audioPolicy.playsVoiceCues) {
      return;
    }
    unawaited(play());
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
    required RitualPhase nextPhase,
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

      final fadeOutDuration = onPauseScreen && nextPhase == RitualPhase.heart
          ? const Duration(milliseconds: 1250)
          : ritualFlowController.transitionFadeOutDuration(nextPhase);

      await Future.delayed(fadeOutDuration);

      if (!isCurrentFlow(currentFlow)) return;

      if (nextPhase == RitualPhase.heart) {
        askFadeController.stop();
        askFadeController.value = 1.0;
      }

      setState(() {
        currentText = newText;
        ritualFlowController.transitionTo(nextPhase);
        if (nextPhase != RitualPhase.pause) {
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
        ritualFlowController.transitionSettleDuration(nextPhase),
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
    String? wisdomId,
    bool keepVisibleAfterExpiry = false,
  }) async {
    if (transitionInProgress) return;

    final currentFlow = ++flowSessionId;
    transitionInProgress = true;
    _stopKeepFeedback();
    _saveBreathPlayedForPresentation = false;

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
        ritualFlowController.transitionFadeOutDuration(RitualPhase.revealed),
      );

      if (!isCurrentFlow(currentFlow)) return;

      wisdomRevealController.stop();
      wisdomRevealController.value = 0.0;

      setState(() {
        currentText = text;
        currentRevealId = revealId;
        currentRevealedAt = revealedAt;
        currentWisdomId = wisdomId;
        ritualFlowController.transitionTo(RitualPhase.revealed);
        _showingLockedWisdom = !keepVisibleAfterExpiry;
        _readingPreviousWisdom = keepVisibleAfterExpiry;
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
      _startSaveRingBreathIfReady();

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

  Future<void> _returnFromPreviousWisdom() async {
    if (!_readingPreviousWisdom ||
        !wisdomRevealed ||
        transitionInProgress ||
        _transitionLock ||
        navigationInProgress ||
        _saveOperationInProgress ||
        _shareInProgress) {
      return;
    }
    invalidateDelayedCallbacks();
    _dismissKeptDiscoveryHint();
    final expectedFlow = flowSessionId + 1;
    await transitionToText(
      eastLocalizations(context).askFromYourHeart,
      nextPhase: RitualPhase.heart,
    );
    if (!isCurrentFlow(expectedFlow) || !onHeartScreen) return;
    setState(() {
      _readingPreviousWisdom = false;
      currentRevealId = null;
      currentRevealedAt = null;
      currentWisdomId = null;
    });
  }

  Future<void> updateNextWisdomMessage() async {
    final nextAccessViewState = await ritualAccessCoordinator.refresh();
    if (!mounted || nextAccessViewState == null) return;
    _countdownResolvedAt = revealBoundaryNow();
    _countdownExpiryChecked = false;

    if (!nextAccessViewState.isLocked) {
      setState(() {
        _accessViewState = nextAccessViewState;

        if (nextAccessViewState.isResolved &&
            (onLockedCountdown || _showingLockedWisdom)) {
          ritualFlowController.transitionTo(RitualPhase.launch);
          _showingLockedWisdom = false;
          currentText = "EAST.";
          currentRevealId = null;
          currentRevealedAt = null;
          currentWisdomId = null;
          textOpacity = 1.0;
          textScale = 1.0;
        }
      });
      if (!_firstRitualGuidanceVisible) _scheduleFirstRitualGuidance();
      return;
    }

    // The duration in `_accessViewState` is the source of truth from this
    // point on. `presentation.plainText` below only updates `currentText`
    // while the large locked-countdown surface is already visible.
    final duration = nextAccessViewState.countdownDuration!;
    final presentation = CountdownPresentation(
      sentence: eastLocalizations(context).returnWhenSilenceOpensAgain,
      duration: duration,
    );

    setState(() {
      _accessViewState = nextAccessViewState;
      if (onLockedCountdown) {
        currentText = presentation.plainText;
      }
    });
    if (!_firstRitualGuidanceVisible) _scheduleFirstRitualGuidance();
  }

  Future<DailyWisdomPreparedReveal> prepareDailyWisdomReveal() {
    return dailyWisdomAccessService.prepareReveal(
      selectWisdom: () async =>
          (await wisdomSelector.select())['text'] as String,
      selectWisdomWithIdentity: () async {
        final wisdom = await wisdomSelector.select();
        return DailyWisdomSelection(
          text: wisdom['text'] as String,
          wisdomId: wisdom['id'] as String?,
        );
      },
    );
  }

  void finishCommittedDailyWisdom(DailyWisdomAccess access) {
    final result = ritualCompletionCoordinator.finish(
      access,
      onRitualOrdinalResolved: (ordinal) {
        if (!mounted) return;
        _pendingRitualOrdinal = ordinal;
      },
    );
    final notificationOfferUnlockAt = result.notificationOfferUnlockAt;
    if (notificationOfferUnlockAt != null) {
      _pendingNotificationUnlockAt = notificationOfferUnlockAt;
    }
    widget.keeperRitualWidgetCoordinator?.notifyAuthoritativeReveal();
  }

  Future<void> synchronizeUnlockNotification() async {
    try {
      final status = await dailyWisdomAccessService.status();
      await wisdomNotificationService.synchronizeWithStatus(status);
      // EAST. 1.2 Slice 3: widget-snapshot reconciliation is no longer
      // triggered from here -- `WidgetPresentationSyncCoordinator`
      // (`lib/app.dart`) owns its own independent launch/resume
      // reconciliation, fully decoupled from notification synchronization.
    } catch (_) {
      // Notification synchronization must not affect daily access.
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
  // "by default". The first-use Keep discovery uses a three-second
  // post-reveal delay; ritual 2 retains the original six-second native
  // permission timing through the second guarded wait below.
  void _queueNotificationPermissionOffer(
    DateTime unlockAt, {
    Duration delay = const Duration(seconds: 3),
  }) {
    final offerFlow = flowSessionId;
    _notificationOfferGate.schedule(
      delay: delay,
      runOffer: () =>
          _runQueuedNotificationPermissionOffer(offerFlow, unlockAt),
    );
  }

  Future<void> _runQueuedNotificationPermissionOffer(
    int offerFlow,
    DateTime unlockAt,
  ) async {
    if (!_canRunQueuedNotificationPermissionOffer(offerFlow, unlockAt)) {
      return;
    }
    // P13 (locked contract): an explicit, closed three-way switch on the
    // ritual ordinal -- never an `!= 1`/`else` fallthrough. Ritual 1
    // begins the first-use Keep discovery and never reaches the native
    // prompt. Ritual 2 alone reaches the existing, unmodified
    // native-prompt path. Every other ordinal -- 3+, or undetermined
    // (`null`, e.g. a rating request already attempted, or a read/write
    // failure) -- does neither: the automatic offer fails closed rather
    // than falling through to the native prompt "by default".
    if (_pendingRitualOrdinal == 1) {
      _pendingNotificationUnlockAt = null;
      await _beginFirstUseKeepDiscovery();
      return;
    }
    if (_pendingRitualOrdinal == 2) {
      // The first-use Keep discovery now appears three seconds after the
      // wisdom has fully revealed. Keep ritual 2's native notification
      // permission request at its established six-second timing by waiting
      // for the remaining half of that shared post-reveal slot here.
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!_canRunQueuedNotificationPermissionOffer(offerFlow, unlockAt)) {
        return;
      }
      await _showNotificationPermissionOffer(unlockAt);
      return;
    }
    _pendingNotificationUnlockAt = null;
  }

  bool _canRunQueuedNotificationPermissionOffer(
    int offerFlow,
    DateTime unlockAt,
  ) {
    return mounted &&
        offerFlow == flowSessionId &&
        _pendingNotificationUnlockAt == unlockAt &&
        wisdomRevealed &&
        !transitionInProgress &&
        !navigationInProgress &&
        !_isInRitualSilence;
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

  // The first-use explanation keeps its existing eligibility and timing.
  // Its text remains actionable; the ring's one breath belongs to the reveal.
  Future<void> _beginFirstUseKeepDiscovery() async {
    if (!mounted || !wisdomRevealed) return;
    if (transitionInProgress || _transitionLock || _isInRitualSilence) return;
    if (_revealPersistenceNeedsRetry) return;
    if (navigationInProgress) return;
    if (_shareInProgress || _saveOperationInProgress) return;
    // Already kept (e.g. the user tapped the ring before this timing slot
    // even arrived) -- nothing left to teach for this reveal.
    if (isCurrentFavorite()) return;

    setState(() {
      _firstUseKeepDiscoveryActive = true;
      _keptDiscoveryHintText = 'keep';
      _keptDiscoveryHintOpacity = 1.0;
    });
    // Best-effort persisted bookkeeping (see `KeptDiscoveryHintService`'s
    // own doc comments): `recordDisplayShown` for continuity with the
    // service's existing display-count bookkeeping, and
    // `markCentralDiscoveryPending` so a killed/relaunched app can resume
    // showing this against the same still-revealed, still-unkept wisdom
    // (see `_resumePersistedDiscoveryStateIfNeeded`).
    unawaited(keptDiscoveryHintService.recordDisplayShown());
    unawaited(keptDiscoveryHintService.markCentralDiscoveryPending());

    // Deliberately no hide timer: this discovery never times out (see
    // this method's own doc comment).
  }

  // Restore only the first-use explanation after navigation. Finished or
  // interrupted decorative feedback does not replay on return.
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
      setState(() {
        _keptDiscoveryHintText = 'keep';
        _keptDiscoveryHintOpacity = 1.0;
      });
    }
  }

  // Stop all three independent animations on navigation, backgrounding,
  // a successful save, or replacement wisdom. No delayed halo can leak out.
  void _stopKeepFeedback() {
    _saveRingBreathController.stop();
    _keptFeedbackController.stop();
    _keptDiscoveryBreathActive = false;
    _keptFeedbackVisible = false;
    _saveFeedbackController.stop();
    _saveFeedbackVisible = false;
    _saveHelpVisible = false;
    _keptHelpVisible = false;
  }

  void _dismissKeptDiscoveryHint() {
    _stopKeepFeedback();
    _keptDiscoveryHintOpacity = 0.0;
  }

  // Durable saves acknowledge every occurrence. First-use discovery remains
  // pending until Kept is opened; later visits receive a single quiet breath.
  Future<void> _onWisdomSuccessfullyKept({
    required int saveFlow,
    required String revealId,
  }) async {
    _stopKeepFeedback();
    _firstUseKeepDiscoveryActive = false;

    bool wasCompletedBefore;
    try {
      wasCompletedBefore = await keptDiscoveryHintService.isCompleted();
    } catch (_) {
      wasCompletedBefore = false;
    }
    unawaited(keptDiscoveryHintService.markCompleted());
    if (!mounted) return;

    if (!wasCompletedBefore) {
      _keptNavDiscoveryActive = true;
      unawaited(keptDiscoveryHintService.markNavDiscoveryPending());
    }

    // A write may finish after leaving Home, backgrounding, or revealing a
    // replacement wisdom. Keep the data, but do not replay stale feedback.
    if (saveFlow != flowSessionId ||
        revealId != currentRevealId ||
        !wisdomRevealed ||
        navigationInProgress) {
      return;
    }

    setState(() {
      _keptDiscoveryHintText = '';
      _keptDiscoveryHintOpacity = 0;
      _keptDiscoveryBreathActive = false;
      _saveFeedbackVisible = true;
    });
    _saveFeedbackController.forward(from: 0);
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
    if (_ritualSound.canPlay) HapticFeedback.mediumImpact();
    try {
      final locale = Localizations.localeOf(context);
      final presentedWisdom = _presentedWisdom(locale);
      final shareScheme = EastColors.of(context);
      if (wisdomShareService case WisdomShareService service) {
        await service.shareWisdomForLocale(
          wisdom: presentedWisdom,
          sharePositionOrigin: shareOrigin,
          locale: locale,
          scheme: shareScheme,
        );
      } else {
        await wisdomShareService.shareWisdom(
          wisdom: presentedWisdom,
          sharePositionOrigin: shareOrigin,
        );
      }
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
      currentText = eastLocalizations(context).askFromYourHeart;
      ritualFlowController.transitionTo(RitualPhase.heart);
      _showingLockedWisdom = false;
      _readingPreviousWisdom = false;
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

  /// Resolves only the visible copy for the existing occurrence. The stored
  /// snapshot remains the persistence fallback and is never rewritten when a
  /// user switches languages.
  String _presentedWisdom(Locale locale) =>
      _wisdomPresentation.resolve(
        wisdomId: currentWisdomId,
        locale: locale,
        persistedSnapshot: currentText,
      ) ??
      currentText;

  DateTime revealBoundaryNow() {
    return widget.clock?.call() ?? DateTime.now();
  }

  void _showRevealCommitRetryState() {
    if (!mounted) return;
    setState(() {
      _revealPersistenceNeedsRetry = true;
      saveControlOpacity = 0.0;
      saveInteractionEnabled = false;
      postRevealMessageOpacity = 0.0;
    });
  }

  void _applyCommittedAccess(
    DailyWisdomAccess access, {
    required double nextSaveControlOpacity,
    required bool nextSaveInteractionEnabled,
    required double nextPostRevealMessageOpacity,
  }) {
    finishCommittedDailyWisdom(access);
    _pendingRevealBoundaryForRetry = null;
    setState(() {
      _revealPersistenceNeedsRetry = false;
      _showingLockedWisdom = !access.isNew;
      currentRevealId = access.revealId;
      currentRevealedAt = access.revealedAt;
      currentWisdomId = access.wisdomId;
      saveControlOpacity = nextSaveControlOpacity;
      saveInteractionEnabled = nextSaveInteractionEnabled;
      postRevealMessageOpacity = nextPostRevealMessageOpacity;
    });
    _startSaveRingBreathIfReady();
  }

  void _observeLateRevealCommit(
    Future<RitualCommitResolution> eventualResolution,
    int currentFlow,
  ) {
    unawaited(
      eventualResolution.then((resolution) {
        if (!mounted || currentFlow != flowSessionId) return;
        if (resolution is RitualCommitSucceeded) {
          _applyCommittedAccess(
            resolution.access,
            nextSaveControlOpacity: 1.0,
            nextSaveInteractionEnabled: true,
            nextPostRevealMessageOpacity: 1.0,
          );
          return;
        }
        _showRevealCommitRetryState();
      }),
    );
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
      if (_ritualSound.canPlay) HapticFeedback.mediumImpact();

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
      _stopKeepFeedback();
      _saveBreathPlayedForPresentation = false;
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
      DailyWisdomAccess? accountAuthorizedAccess;
      if (dailyWisdomAccessService.requiresAccountAuthorization &&
          !revealReady.hasAuthoritativeRecord) {
        try {
          accountAuthorizedAccess = await dailyWisdomAccessService
              .authorizePreparedReveal(revealReady)
              .timeout(widget.dailyWisdomOperationTimeout);
        } catch (error) {
          if (mounted && isCurrentFlow(currentFlow)) {
            restoreAskAfterRevealPersistenceFailure();
            unawaited(_showDailyAuthorizationFailure(error, currentFlow));
          }
          return;
        }
        if (!mounted || !isCurrentFlow(currentFlow)) return;
      }
      if (!mounted || !isCurrentFlow(currentFlow)) return;
      final revealBoundary = revealReady.phase ==
              PendingDailyWisdomRevealPhase.revealedPendingCommit
          ? revealReady.confirmedRevealBoundary!
          : revealBoundaryNow();

      final revealedAccess = accountAuthorizedAccess ??
          (revealReady.hasAuthoritativeRecord
              ? DailyWisdomAccess(
                  text: revealReady.text,
                  isNew: false,
                  unlockAt: revealReady.unlockAt,
                  revealId: revealReady.revealId,
                  revealedAt: revealReady.revealedAt,
                  wisdomId: revealReady.wisdomId,
                )
              : DailyWisdomAccess(
                  text: revealReady.text,
                  isNew: true,
                  unlockAt: revealBoundary.add(
                    dailyWisdomAccessService.lockDuration,
                  ),
                ));

      if (!revealReady.hasAuthoritativeRecord &&
          accountAuthorizedAccess == null) {
        _pendingRevealBoundaryForRetry = revealBoundary;
      }

      setState(() {
        _isInRitualSilence = false;
        currentText = revealedAccess.text;
        currentRevealId = revealedAccess.revealId;
        currentRevealedAt = revealedAccess.revealedAt;
        currentWisdomId = revealedAccess.wisdomId;
        ritualFlowController.transitionTo(RitualPhase.revealed);
        _showingLockedWisdom = !revealedAccess.isNew;
        textOpacity = 1.0;
        textScale = 1.0;
      });

      // The notification-offer gate must become busy in the same synchronous
      // turn the reveal itself becomes visible — not deferred to a post-frame
      // callback. Queueing it here closes that race window. This is only a
      // reordering: the offer's delay, guard conditions, and
      // `wisdomRevealController.forward` (still deferred to the next frame
      // below) are unchanged.
      final unlockAt = revealedAccess.unlockAt;
      if (revealedAccess.isNew && unlockAt != null) {
        _queueNotificationPermissionOffer(
          unlockAt,
          delay: wisdomRevealController.duration! + const Duration(seconds: 3),
        );
      }

      if (_audioPolicy.playsRevealSound) {
        unawaited(audioService.playRevealSound());
      }
      if (_ritualSound.canPlay) HapticFeedback.selectionClick();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isCurrentFlow(currentFlow) || !wisdomRevealed) return;
        wisdomRevealController.forward(from: 0.0);
      });

      final commitFuture =
          revealReady.hasAuthoritativeRecord || accountAuthorizedAccess != null
              ? Future<DailyWisdomAccess>.value(revealedAccess)
              : dailyWisdomAccessService.finalizeVisualReveal(
                  text: revealReady.text,
                  revealBoundary: revealBoundary,
                );
      final commitAttempt = await ritualCommitCoordinator.run(commitFuture);

      if (!mounted || currentFlow != flowSessionId) return;

      if (commitAttempt is RitualCommitTimedOut) {
        _showRevealCommitRetryState();
        _observeLateRevealCommit(
          commitAttempt.eventualResolution,
          currentFlow,
        );
        return;
      }

      final commitResolution =
          (commitAttempt as RitualCommitCompleted).resolution;
      if (commitResolution is RitualCommitFailed) {
        _showRevealCommitRetryState();
        return;
      }
      final committedAccess =
          (commitResolution as RitualCommitSucceeded).access;
      _applyCommittedAccess(
        committedAccess,
        nextSaveControlOpacity: 0.0,
        nextSaveInteractionEnabled: false,
        nextPostRevealMessageOpacity: 0.0,
      );

      await Future.delayed(const Duration(milliseconds: 900));

      if (!mounted || currentFlow != flowSessionId) return;

      setState(() {
        saveControlOpacity = 1.0;
      });
      _startSaveRingBreathIfReady();

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

    try {
      final retryBoundary = _pendingRevealBoundaryForRetry;
      if (retryBoundary == null) {
        _showRevealCommitRetryState();
        return;
      }
      final finalization = dailyWisdomAccessService.finalizeVisualReveal(
        text: currentText,
        revealBoundary: retryBoundary,
      );
      final commitAttempt = await ritualCommitCoordinator.run(finalization);

      if (!mounted || currentFlow != flowSessionId) return;

      if (commitAttempt is RitualCommitTimedOut) {
        _showRevealCommitRetryState();
        _observeLateRevealCommit(
          commitAttempt.eventualResolution,
          currentFlow,
        );
        return;
      }

      final commitResolution =
          (commitAttempt as RitualCommitCompleted).resolution;
      if (commitResolution is RitualCommitFailed) {
        _showRevealCommitRetryState();
        return;
      }
      _applyCommittedAccess(
        (commitResolution as RitualCommitSucceeded).access,
        nextSaveControlOpacity: 1.0,
        nextSaveInteractionEnabled: false,
        nextPostRevealMessageOpacity: 0.0,
      );
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

  Future<void> openSettings() async {
    if (navigationInProgress || transitionInProgress || _transitionLock) return;

    navigationInProgress = true;
    interruptRitualForNavigation();

    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SettingsScreen(
            ritualSoundPreferenceController: _ritualSound,
            localePreferenceController: widget.localePreferenceController,
            appearancePreferenceController:
                widget.appearancePreferenceController,
          ),
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

  /// Narrow identity diagnostic retained on the concrete State object for
  /// Home's black-box regression coverage. Matching remains controller-owned.
  FavoriteItem? currentFavorite() {
    return homeKeptController.currentFavorite(currentRevealId);
  }

  /// Kept-limit presentation entry point retained on the concrete State so
  /// accessibility/large-text widget tests can open the overlay directly.
  void showFavoriteLimitDialog() {
    _updateHomePresentation(() {
      _favoriteLimitOverlayVisible = true;
    });
  }

  /// The one state-update seam used by Home's part-file presentation
  /// extensions. Keeping the protected [setState] call on the actual
  /// [State] subclass preserves Flutter's lifecycle contract while feature
  /// slices remain separately readable.
  void _updateHomePresentation(VoidCallback update) {
    if (!mounted) return;
    setState(update);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = eastLocalizations(context);
    final presentedText = wisdomRevealed
        ? _presentedWisdom(Localizations.localeOf(context))
        : currentText;
    // Built fresh every build from `_accessViewState` and the live
    // locale (see `_currentCountdownPresentation`'s own doc comment) --
    // shared by both countdown render sites below so they always show the
    // identical HH:MM:SS token for the identical underlying duration.
    final countdownPresentation = _currentCountdownPresentation(context);
    final saveLabelText = _saveFeedbackVisible || isCurrentFavorite()
        ? l10n.reflectionSaved
        : l10n.keepThisWisdom;
    final saveLabelUsesStatusPosition =
        (_saveFeedbackVisible || _saveHelpVisible) &&
            !_homeSaveLabelFitsBesideRing(context, saveLabelText);
    final wisdomShareAvailable = wisdomRevealed &&
        !transitionInProgress &&
        !_transitionLock &&
        !_isInRitualSilence &&
        !_revealPersistenceNeedsRetry &&
        wisdomRevealController.value >= 1.0;
    return Scaffold(
      backgroundColor: EastColors.of(context).background,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Build 33 accessibility repair: when the favorite-limit overlay
            // is visible, the ritual/top-nav/save-control content beneath it
            // must be neither touchable nor VoiceOver-reachable -- matching
            // the IgnorePointer+ExcludeSemantics pattern already used by
            // Settings/Reflection/Journal's own full-field decision
            // overlays. Nesting this content in its own Stack (rather than
            // wrapping each child individually) preserves every existing
            // Positioned/Positioned.fill placement unchanged.
            Positioned.fill(
              child: IgnorePointer(
                ignoring: _favoriteLimitOverlayVisible,
                child: ExcludeSemantics(
                  excluding: _favoriteLimitOverlayVisible,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(
                        child: ColoredBox(
                          color: EastColors.of(context).background,
                        ),
                      ),
                      Positioned.fill(
                        child: _HomeMainRitualGesture(
                          navigationDisabled:
                              navigationInProgress || _transitionLock,
                          semanticLabel: mainRitualSemanticLabel(context),
                          semanticHint: mainRitualSemanticHint(context),
                          semanticActionEnabled:
                              mainRitualActionSemanticsEnabled,
                          hideContentSemantics: hideMainRitualContentSemantics,
                          onTap: handleMainTap,
                          swipeToKeptEnabled: _homeSwipeToKeptEligible,
                          onSwipeStart: _handleHomeSwipeStart,
                          onSwipeUpdate: _handleHomeSwipeUpdate,
                          onSwipeEnd: _handleHomeSwipeEnd,
                          content: _HomeRitualContent(
                            phase: _phase,
                            currentText: presentedText,
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
                            countdownPresentation: countdownPresentation,
                            wisdomShareEnabled: wisdomShareAvailable,
                            wisdomShareOriginKey: _wisdomShareOriginKey,
                            onWisdomLongPress: shareCurrentWisdom,
                          ),
                        ),
                      ),
                      _HomeFirstRitualGuidance(
                        text: _firstRitualGuidanceText(context),
                        visible: _firstRitualGuidanceEligible &&
                            _firstRitualGuidanceVisible &&
                            (_phase == RitualPhase.launch ||
                                (_phase == RitualPhase.pause &&
                                    pauseFeelOpacity < 1.0)),
                        reduceMotion: _reduceMotion,
                      ),
                      if (_chromeVisible) ...[
                        _HomeSettingsMenuControl(onPressed: openSettings),
                        _HomeTopNavigation(
                          onKeptPressed: openFavorites,
                          saveFeedback: _keptFeedbackVisible
                              ? _keptFeedbackController
                              : null,
                          onHelpStart: () =>
                              setState(() => _keptHelpVisible = true),
                          onHelpEnd: () =>
                              setState(() => _keptHelpVisible = false),
                        ),
                      ],
                      if (wisdomRevealed)
                        _HomeSaveControl(
                          opacity: saveControlOpacity,
                          interactionEnabled: saveInteractionEnabled,
                          isCurrentFavorite: isCurrentFavorite(),
                          onPressed: toggleFavorite,
                          breathProgress: _keptDiscoveryBreathActive
                              ? _saveRingBreathController
                              : null,
                          onHelpStart: () =>
                              setState(() => _saveHelpVisible = true),
                          onHelpEnd: () =>
                              setState(() => _saveHelpVisible = false),
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
                            _startSaveRingBreathIfReady();
                          },
                        ),
                      if (wisdomRevealed && !saveLabelUsesStatusPosition)
                        _HomePostRevealMessage(
                          opacity: postRevealMessageOpacity,
                          message: _readingPreviousWisdom
                              ? l10n.retry
                              : _accessViewState.showReadyMessage
                                  ? l10n.dailyWisdomReady
                                  : countdownPresentation?.plainText ?? '',
                          countdownPresentation: _readingPreviousWisdom
                              ? null
                              : countdownPresentation,
                          onPressed: _readingPreviousWisdom
                              ? _returnFromPreviousWisdom
                              : null,
                        ),
                      if (_keptHelpVisible && _chromeVisible)
                        _HomeKeptControlHelp(text: l10n.kept),
                      if (wisdomRevealed &&
                          (_saveFeedbackVisible || _saveHelpVisible))
                        _HomeSaveLabel(
                          text: saveLabelText,
                          progress: _saveFeedbackVisible
                              ? _saveFeedbackController
                              : null,
                          useStatusPosition: saveLabelUsesStatusPosition,
                        ),
                      if (wisdomRevealed &&
                          _keptDiscoveryHintOpacity > 0.0 &&
                          !_saveHelpVisible)
                        _HomeKeptDiscoveryHint(
                          opacity: _keptDiscoveryHintOpacity,
                          text: _keptDiscoveryHintText == 'kept'
                              ? l10n.kept
                              : _keptDiscoveryHintText.isEmpty
                                  ? ''
                                  : l10n.keepThisWisdom,
                          onPressed: _keptDiscoveryHintText == 'keep'
                              ? toggleFavorite
                              : null,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            _favoriteLimitOverlay(),
          ],
        ),
      ),
    );
  }
}
