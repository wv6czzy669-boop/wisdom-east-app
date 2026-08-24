import 'dart:async';

import 'package:flutter/widgets.dart';

import '../controllers/appearance_preference_controller.dart';
import '../controllers/latest_request_guard.dart';
import '../controllers/locale_preference_controller.dart';
import '../localization/east_locale_registry.dart';
import 'daily_wisdom_access_service.dart';
import 'widget_snapshot_service.dart';
import 'wisdom_localization_resolver.dart';

/// EAST. 1.2 Slice 3 -- the single owner of Medium Widget presentation
/// publication, using generation-guarded newest-wins ordering (not a
/// general-purpose serialization framework -- see [_guard]'s own doc
/// comment for the exact mechanism). Owned and disposed by
/// `_WisdomAppState` (`lib/app.dart`), entirely outside `HomeScreen` --
/// `HomeScreen` may only call [notifyFreshReveal] with its own
/// already-authoritative inputs; it never constructs a presentation
/// payload, resolves a locale, reads preferences, or touches
/// `WidgetSnapshotService` directly.
///
/// Public surface is deliberately minimal: the constructor, [start],
/// [dispose], and [notifyFreshReveal] only. Every injected collaborator is
/// stored privately -- nothing about how presentation is resolved or
/// published is part of this class's public contract.
///
/// `DailyWisdomAccessService` remains the sole authority on what wisdom
/// exists and when it unlocks -- this coordinator never selects, generates,
/// or reveals anything, and never identifies an occurrence by its displayed
/// text or a timestamp. `wisdomId` is always the lookup key passed to
/// [WisdomLocalizationResolver.resolve]; a persisted/status text is used
/// only as that resolver's final fallback *value*, never as a search key.
///
/// Every publish attempt is generation-guarded via the existing
/// [LatestRequestGuard] (already used for exactly this class of async race
/// elsewhere, e.g. `HomeScreen.accessRefreshGuard`): a slower, earlier
/// reconciliation can never overwrite a newer preference selection or a
/// fresh reveal, and no publish is ever attempted after [dispose]. All
/// failures are contained here -- a widget-sync failure must never affect
/// the ritual.
class WidgetPresentationSyncCoordinator {
  WidgetPresentationSyncCoordinator({
    required AppearancePreferenceController appearanceController,
    required LocalePreferenceController localeController,
    required DailyWisdomAccessService dailyWisdomAccessService,
    required WidgetSnapshotService widgetSnapshotService,
    WisdomLocalizationResolver wisdomPresentation =
        const WisdomLocalizationResolver(),
  })  : _appearanceController = appearanceController,
        _localeController = localeController,
        _dailyWisdomAccessService = dailyWisdomAccessService,
        _widgetSnapshotService = widgetSnapshotService,
        _wisdomPresentation = wisdomPresentation;

  final AppearancePreferenceController _appearanceController;
  final LocalePreferenceController _localeController;
  final DailyWisdomAccessService _dailyWisdomAccessService;
  final WidgetSnapshotService _widgetSnapshotService;
  final WisdomLocalizationResolver _wisdomPresentation;

  final LatestRequestGuard _guard = LatestRequestGuard();

  /// A private `WidgetsBindingObserver` delegate, never exposed on this
  /// class's own public surface -- extending `WidgetsBindingObserver`
  /// directly would make `didChangeAppLifecycleState` a public method of
  /// this coordinator, which is not part of its intended contract. Forwards
  /// only [AppLifecycleState.resumed] to [_scheduleReconciliation].
  late final _ResumeObserver _resumeObserver =
      _ResumeObserver(_scheduleReconciliation);

  bool _started = false;
  bool _disposed = false;

  /// Registers preference listeners and this coordinator's private resume
  /// observer, then runs the initial reconciliation (covering app launch).
  /// Safe to call more than once -- only the first call has any effect.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _appearanceController.addListener(_scheduleReconciliation);
    _localeController.addListener(_scheduleReconciliation);
    WidgetsBinding.instance.addObserver(_resumeObserver);
    _scheduleReconciliation();
  }

  /// Removes every listener/observer this coordinator registered and
  /// invalidates any in-flight reconciliation, so a delayed status lookup
  /// that resolves after this call can never publish. Safe to call more
  /// than once -- only the first call has any effect.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _guard.invalidate();
    _appearanceController.removeListener(_scheduleReconciliation);
    _localeController.removeListener(_scheduleReconciliation);
    WidgetsBinding.instance.removeObserver(_resumeObserver);
  }

  /// The one call `HomeScreen` is authorized to make -- an authoritative
  /// "fresh reveal committed" event, never a payload `HomeScreen` itself
  /// constructs. [text] is used only as [WisdomLocalizationResolver]'s
  /// resolution input/fallback, never as a lookup key; [wisdomId] is the
  /// only identity ever used to resolve presentation text. Supersedes any
  /// in-flight preference-driven reconciliation and never calls
  /// `DailyWisdomAccessService.status()` -- every input this needs is
  /// already authoritative.
  void notifyFreshReveal({
    required String wisdomId,
    required String text,
    required DateTime unlockAt,
  }) {
    if (_disposed) return;
    // Invalidates any in-flight preference-driven reconciliation so a
    // slower, earlier `status()` lookup can never overwrite this
    // authoritative reveal once it publishes.
    _guard.begin();

    final appearanceMode = _appearanceController.mode;
    final explicitLocale = _localeController.explicitLocale;
    final resolvedText = _wisdomPresentation.resolve(
          wisdomId: wisdomId,
          locale: _effectiveLocale(explicitLocale),
          persistedSnapshot: text,
        ) ??
        text;

    unawaited(
      _publishRevealed(
        text: resolvedText,
        unlockAt: unlockAt,
        appearanceMode: appearanceMode,
        localeOverrideTag: _localeOverrideTag(explicitLocale),
      ),
    );
  }

  void _scheduleReconciliation() {
    if (_disposed) return;
    unawaited(_reconcile());
  }

  Future<void> _reconcile() async {
    final generation = _guard.begin();

    // Captured synchronously, together, before the only await below -- a
    // later preference change during the `status()` await starts its own
    // newer generation and is never mixed with these already-captured
    // values.
    final appearanceMode = _appearanceController.mode;
    final explicitLocale = _localeController.explicitLocale;

    DailyWisdomStatus status;
    try {
      status = await _dailyWisdomAccessService.status();
    } catch (_) {
      // Contained -- a failed status lookup must never affect the ritual,
      // and must never be retried aggressively here; the next natural
      // trigger (a preference change, resume, or fresh reveal) tries again.
      return;
    }

    if (_disposed || !_guard.isCurrent(generation)) return;

    final localeOverrideTag = _localeOverrideTag(explicitLocale);
    final effectiveLocale = _effectiveLocale(explicitLocale);
    final lockedText = status.lockedText;
    final unlockAt = status.unlockAt;

    if (!status.isReady && lockedText != null && unlockAt != null) {
      final resolvedText = _wisdomPresentation.resolve(
            wisdomId: status.wisdomId,
            locale: effectiveLocale,
            persistedSnapshot: lockedText,
          ) ??
          lockedText;
      await _publishRevealed(
        text: resolvedText,
        unlockAt: unlockAt,
        appearanceMode: appearanceMode,
        localeOverrideTag: localeOverrideTag,
      );
    } else {
      await _publishSilence(
        appearanceMode: appearanceMode,
        localeOverrideTag: localeOverrideTag,
      );
    }
  }

  Future<void> _publishRevealed({
    required String text,
    required DateTime unlockAt,
    required EastAppearanceMode appearanceMode,
    required String? localeOverrideTag,
  }) async {
    if (_disposed) return;
    try {
      await _widgetSnapshotService.publishRevealed(
        text: text,
        unlockAt: unlockAt,
        appearanceMode: appearanceMode,
        localeOverrideTag: localeOverrideTag,
      );
    } catch (_) {
      // Contained -- WidgetSnapshotService already fails closed internally;
      // this is an extra backstop only.
    }
  }

  Future<void> _publishSilence({
    required EastAppearanceMode appearanceMode,
    required String? localeOverrideTag,
  }) async {
    if (_disposed) return;
    try {
      await _widgetSnapshotService.publishSilence(
        appearanceMode: appearanceMode,
        localeOverrideTag: localeOverrideTag,
      );
    } catch (_) {
      // Contained, matching _publishRevealed above.
    }
  }

  /// `null` (System Default) sends `null` across the channel; an explicit
  /// selection is always already one of `EastLocaleRegistry`'s 15 canonical
  /// product locales (`LocalePreferenceController` never stores anything
  /// else), so its BCP-47 tag is always one the native allowlist accepts.
  String? _localeOverrideTag(Locale? explicitLocale) {
    if (explicitLocale == null) return null;
    return LocalePreferenceController.toBcp47Tag(explicitLocale);
  }

  /// Mirrors `_WisdomAppState`'s own `effectiveThemeLocale` computation in
  /// `lib/app.dart` exactly: an explicit override wins outright; System
  /// Default resolves the current platform locale through EAST.'s approved
  /// product mapping, read live (never a value frozen at an earlier point).
  Locale _effectiveLocale(Locale? explicitLocale) {
    return explicitLocale ??
        EastLocaleRegistry.resolveProductLocale(
          WidgetsBinding.instance.platformDispatcher.locale,
        );
  }
}

/// Private lifecycle-observer delegate for
/// [WidgetPresentationSyncCoordinator] -- exists solely so the coordinator
/// itself never has to `extend WidgetsBindingObserver`, which would put
/// `didChangeAppLifecycleState` on the coordinator's own public surface.
/// Forwards only [AppLifecycleState.resumed]; every other lifecycle state
/// change is ignored, exactly matching the coordinator's previous inline
/// behavior.
class _ResumeObserver extends WidgetsBindingObserver {
  _ResumeObserver(this._onResumed);

  final VoidCallback _onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onResumed();
    }
  }
}
