part of 'home_screen.dart';

/// Home's Kept-specific presentation boundary.
///
/// Durable projection and identity behavior live in [HomeKeptController].
/// This extension intentionally retains only widget-bound feedback,
/// navigation, and gesture handling that require [_HomeScreenState].
extension _HomeKeptPresentation on _HomeScreenState {
  void _dismissFavoriteLimitOverlay() {
    if (!mounted) return;
    _updateHomePresentation(() {
      _favoriteLimitOverlayVisible = false;
    });
  }

  void _becomeKeeperFromLimitOverlay() {
    _dismissFavoriteLimitOverlay();
    unawaited(openKeeperScreen());
  }

  // Build 33 real-device Voice Control repair: the outer `Semantics` must
  // carry its own `onTap` -- see `settings_screen.dart`'s
  // `_removeFromICloudDecisionLabel` for the full explanation of this
  // repeated defect class.
  Widget _favoriteLimitDecisionLabel(
    String label, {
    required VoidCallback onTap,
    required Color color,
  }) {
    return Semantics(
      button: true,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: Center(
              child: Text(
                label,
                style: EastTypography.localized(
                  context,
                  size: 11,
                  color: color,
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
    final l10n = eastLocalizations(context);

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !_favoriteLimitOverlayVisible,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          opacity: _favoriteLimitOverlayVisible ? 1.0 : 0.0,
          child: Container(
            key: const ValueKey('home-favorite-limit-overlay'),
            color: EastColors.of(context).overlay,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 34),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.keptLimit,
                  textAlign: TextAlign.center,
                  style: _homeWisdomStyle(context, 28),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.freeUsersKeepLimit,
                  textAlign: TextAlign.center,
                  style: _homeWisdomStyle(
                    context,
                    15,
                    color: EastColors.of(context).secondary,
                  ),
                ),
                const SizedBox(height: 44),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _favoriteLimitDecisionLabel(
                      l10n.cancelUpper,
                      onTap: _dismissFavoriteLimitOverlay,
                      color: EastColors.of(context).secondary,
                    ),
                    const SizedBox(width: 56),
                    _favoriteLimitDecisionLabel(
                      l10n.becomeKeeper,
                      onTap: _becomeKeeperFromLimitOverlay,
                      color: EastColors.of(context).ink,
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
    final wisdomCouldNotBeKept =
        eastLocalizations(context).wisdomCouldNotBeKept;

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
      showEastSnack(wisdomCouldNotBeKept);
      return;
    }

    _saveOperationInProgress = true;
    final saveFlow = flowSessionId;

    try {
      // Build 26 Phase 3D-C compatibility contract (locked): `text`/`date`
      // are accepted for source/API compatibility only. `date` is never
      // parsed and never used to derive `revealedAt` — the authoritative
      // timestamp passed below is `revealedAt` (from `currentRevealedAt`)
      // alone, and identity remains `revealId` alone.
      final result = await homeKeptController.keep(HomeKeepRequest(
        text: currentText,
        date: formattedToday(),
        isKeeper: isKeeper,
        revealId: revealId,
        revealedAt: revealedAt,
        wisdomId: currentWisdomId,
      ));

      if (!mounted) return;
      if (result.status == HomeKeepStatus.limitReached) {
        showFavoriteLimitDialog();
        return;
      }
      if (result.status == HomeKeepStatus.failed) {
        showEastSnack(wisdomCouldNotBeKept);
        return;
      }

      _updateHomePresentation(() {});

      if (result.status == HomeKeepStatus.kept) {
        await _onWisdomSuccessfullyKept(saveFlow: saveFlow, revealId: revealId);
      }
    } catch (_) {
      showEastSnack(wisdomCouldNotBeKept);
    } finally {
      _saveOperationInProgress = false;
    }
  }

  Future<void> loadFavorites() async {
    final changed = await homeKeptController.load();
    if (!mounted || !changed) return;
    _updateHomePresentation(() {});
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
    unawaited(_reloadFavoritesForIncomingStateChange());
  }

  Future<void> _reloadFavoritesForIncomingStateChange() async {
    final changed = await homeKeptController.refreshAfterIncomingChange();
    if (!mounted || !changed) return;
    _updateHomePresentation(() {});
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
      _keptDiscoveryTimers.cancelNav();
      _keptNavDiscoveryActive = false;
      _updateHomePresentation(() {
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
    if (_notificationOfferGate.isShowing) return false;
    if (_saveOperationInProgress || _shareInProgress) return false;
    return _phase == RitualPhase.launch ||
        _phase == RitualPhase.revealed ||
        _phase == RitualPhase.lockedCountdown;
  }

  void _handleHomeSwipeStart(DragStartDetails details) {
    _swipeToKeptTracker.start();
  }

  void _handleHomeSwipeUpdate(DragUpdateDetails details) {
    _swipeToKeptTracker.update(
      dx: details.delta.dx,
      dy: details.delta.dy,
    );
  }

  void _handleHomeSwipeEnd(DragEndDetails details) {
    if (_swipeToKeptTracker.shouldOpenKept(
      velocityX: details.velocity.pixelsPerSecond.dx,
      isRtl: Directionality.of(context) == TextDirection.rtl,
      isEligible: _homeSwipeToKeptEligible,
    )) {
      openFavorites();
    }
  }
}
