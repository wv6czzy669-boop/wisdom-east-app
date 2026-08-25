part of '../../screens/home_screen.dart';

TextStyle _homeWisdomStyle(
  BuildContext context,
  double size, {
  Color? color,
  bool glow = false,
  bool brand = false,
  double height = 1.28,
}) {
  final typography = EastTypography.planFor(context);
  final palette = EastColors.of(context);
  return TextStyle(
    color: color ?? palette.ink,
    fontSize: size,
    fontWeight: FontWeight.w400,
    fontFamily: brand ? EastTypography.fontFamily : typography.family,
    fontFamilyFallback:
        brand ? EastTypography.fontFamilyFallback : typography.fallbacks,
    height: height,
    letterSpacing: 0.5,
    shadows: glow
        ? [
            Shadow(
              color: palette.ink.withValues(alpha: 0.12),
              blurRadius: 14,
            ),
            Shadow(
              color: palette.accent.withValues(alpha: 0.045),
              blurRadius: 24,
            ),
          ]
        : null,
  );
}

class _HomeMainRitualGesture extends StatelessWidget {
  const _HomeMainRitualGesture({
    required this.navigationDisabled,
    required this.semanticLabel,
    required this.semanticHint,
    required this.semanticActionEnabled,
    required this.hideContentSemantics,
    required this.onTap,
    required this.content,
    this.swipeToKeptEnabled = false,
    this.onSwipeStart,
    this.onSwipeUpdate,
    this.onSwipeEnd,
  });

  final bool navigationDisabled;
  final String? semanticLabel;
  final String? semanticHint;
  final bool semanticActionEnabled;
  final bool hideContentSemantics;
  final VoidCallback onTap;
  final Widget content;

  /// Item 5: when false, no pan recognizer is attached at all, so the
  /// leftward-swipe-to-Kept gesture cannot contest the arena against the
  /// main tap/long-press recognizers during states where it must be a
  /// complete no-op (Pause/Feel/Ask-from-your-heart/transitions/etc.).
  final bool swipeToKeptEnabled;
  final GestureDragStartCallback? onSwipeStart;
  final GestureDragUpdateCallback? onSwipeUpdate;
  final GestureDragEndCallback? onSwipeEnd;

  @override
  Widget build(BuildContext context) {
    final label = semanticLabel;
    final gesture = GestureDetector(
      // A stable key directly on the actual pan/tap/long-press-owning
      // surface, so tests can start a gesture exactly here rather than on
      // an interior descendant that may sit under a `FittedBox` transform
      // or other layout indirection.
      key: const ValueKey('home-ritual-gesture-surface'),
      excludeFromSemantics: true,
      behavior: HitTestBehavior.opaque,
      onTap: navigationDisabled ? null : onTap,
      onLongPress: () {},
      onPanStart: swipeToKeptEnabled ? onSwipeStart : null,
      onPanUpdate: swipeToKeptEnabled ? onSwipeUpdate : null,
      onPanEnd: swipeToKeptEnabled ? onSwipeEnd : null,
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
              child: content,
            ),
          ),
        ),
      ),
    );

    final semanticsChild = ExcludeSemantics(
      excluding: hideContentSemantics || label != null,
      child: gesture,
    );

    return Semantics(
      container: label != null,
      excludeSemantics: label != null,
      button: label == null ? null : semanticActionEnabled,
      enabled: label == null ? null : semanticActionEnabled,
      label: label,
      hint: semanticHint,
      onTap: semanticActionEnabled ? onTap : null,
      child: semanticsChild,
    );
  }
}

/// A quiet, first-use-only instruction. It is deliberately outside the
/// centered ritual composition, never participates in hit testing, and is
/// excluded from semantics because the main ritual action owns the same
/// text as its accessibility hint.
class _HomeFirstRitualGuidance extends StatelessWidget {
  const _HomeFirstRitualGuidance({
    required this.text,
    required this.visible,
    required this.reduceMotion,
  });

  final String text;
  final bool visible;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return PositionedDirectional(
      start: 30,
      end: 30,
      bottom: 42,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: AnimatedOpacity(
            key: const ValueKey('first-ritual-guidance'),
            opacity: visible ? 1.0 : 0.0,
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: EastTypography.localized(
                context,
                size: 15,
                color: EastColors.of(context).hint,
                height: 1.3,
                letterSpacing: 0.55,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The one shared visual countdown widget used at both render sites (the
/// locked-countdown main ritual state via [_HomeRitualContent], and the
/// post-reveal message beneath revealed wisdom via [_HomePostRevealMessage])
/// -- renders the localized sentence in the ambient text direction and the
/// fixed `HH:MM` token isolated to LTR, with tabular figures applied only
/// to the token. Never parses [presentation]'s `hhmm`/`plainText` -- reads
/// only its structured `duration`.
class _HomeCountdownText extends StatelessWidget {
  const _HomeCountdownText({
    required this.presentation,
    required this.style,
  });

  final CountdownPresentation presentation;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          presentation.sentence,
          textAlign: TextAlign.center,
          style: style,
        ),
        Text(
          presentation.duration.hhmm,
          key: const ValueKey('home-countdown-hhmm'),
          textAlign: TextAlign.center,
          // Isolates only this Text's paragraph direction to LTR so the
          // digits never mirror under an RTL locale (e.g. Arabic); the
          // sentence above keeps the ambient `Directionality`.
          textDirection: TextDirection.ltr,
          style: style.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _HomeRitualContent extends StatelessWidget {
  const _HomeRitualContent({
    required this.phase,
    required this.currentText,
    required this.textOpacity,
    required this.textScale,
    required this.pauseFeelOpacity,
    required this.pulseController,
    required this.askFadeAnimation,
    required this.wisdomRevealAnimation,
    required this.reduceMotion,
    required this.onPauseScreen,
    required this.onHeartScreen,
    required this.wisdomRevealed,
    required this.onLockedCountdown,
    this.countdownPresentation,
    required this.wisdomShareEnabled,
    required this.wisdomShareOriginKey,
    required this.onWisdomLongPress,
  });

  final RitualPhase phase;
  final String currentText;
  final CountdownPresentation? countdownPresentation;
  final double textOpacity;
  final double textScale;
  final double pauseFeelOpacity;
  final AnimationController pulseController;
  final Animation<double> askFadeAnimation;
  final Animation<double> wisdomRevealAnimation;
  final bool reduceMotion;
  final bool onPauseScreen;
  final bool onHeartScreen;
  final bool wisdomRevealed;
  final bool onLockedCountdown;
  final bool wisdomShareEnabled;
  final GlobalKey wisdomShareOriginKey;
  final VoidCallback onWisdomLongPress;

  @override
  Widget build(BuildContext context) {
    final ritualTextWidth = max(
      1.0,
      MediaQuery.sizeOf(context).width - 68,
    );
    // Build 33 accessibility repair (real-device Larger Text failure): the
    // revealed wisdom's approved composition is a narrow 60%-of-screen
    // column at ordinary text sizes -- deliberate, unchanged here. But that
    // fixed fraction never grew with Dynamic Type, so at high accessibility
    // scales a single long word (agglutinative Turkish especially --
    // "hikâyenin", "değildir") could no longer fit the line on its own,
    // forcing Flutter's text layout to fall back to a mid-word character
    // break rather than wrapping at the space before/after it. `FittedBox`
    // (below) only rescales the already-wrapped result afterward; it never
    // rewraps, so it could not fix this on its own.
    //
    // The fix widens the column as the ambient text scale grows, reaching
    // the same `ritualTextWidth` already used (at every scale, including
    // 200%+) for Pause/Feel/Ask/the locked countdown -- a width already
    // proven safe elsewhere in this exact widget -- by 160%, the top of
    // this task's called-out critical range. At scale 1.0 the progress
    // term is exactly 0.0, so the width is bit-for-bit the original
    // `screenWidth * 0.60` -- the approved 100% composition is unchanged.
    final wisdomWidthScaleProgress =
        ((MediaQuery.textScalerOf(context).scale(1.0) - 1.0) / 0.6)
            .clamp(0.0, 1.0);
    final narrowRevealedWisdomWidth = MediaQuery.sizeOf(context).width * 0.60;
    final revealedWisdomWidth = max(
      1.0,
      narrowRevealedWisdomWidth +
          (ritualTextWidth - narrowRevealedWisdomWidth) *
              wisdomWidthScaleProgress,
    );
    final textSize = phase == RitualPhase.launch
        ? 42.0
        : wisdomRevealed
            ? 38.0
            : onLockedCountdown
                ? 22.0
                : onPauseScreen
                    ? 60.0
                    : onHeartScreen
                        ? 60.0
                        : 34.0;

    final palette = EastColors.of(context);
    final finalColor = palette.ink;
    final darkColor = palette.surface;

    final animatedTextColor = Color.lerp(
      darkColor,
      finalColor,
      textOpacity,
    )!;
    final ritualTextStyle = _homeWisdomStyle(
      context,
      textSize,
      color: wisdomRevealed ? animatedTextColor : finalColor,
      glow: wisdomRevealed || onHeartScreen,
      height: wisdomRevealed
          ? 1.48
          : onLockedCountdown
              ? 1.5
              : 1.28,
    );
    final lockedCountdownPresentation = countdownPresentation;
    final Widget currentRitualText =
        onLockedCountdown && lockedCountdownPresentation != null
            ? _HomeCountdownText(
                presentation: lockedCountdownPresentation,
                style: ritualTextStyle,
              )
            : Text(
                currentText,
                textAlign: TextAlign.center,
                style: ritualTextStyle,
              );

    return AnimatedBuilder(
      animation: pulseController,
      builder: (context, child) {
        final floatingY = reduceMotion
            ? 0.0
            : wisdomRevealed
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
      child: _RitualScaleTransition(
        enabled: !onHeartScreen,
        // Build 33 accessibility repair: this scale/zoom transition is
        // decorative embellishment on the ritual text, not the state
        // transition itself (that's the separate opacity fade below) --
        // Reduce Motion neutralizes it to a static 1.0 while every other
        // aspect of ritual progression, timing, and copy is unaffected.
        // The decorative pulse/breath animations already gate the same way
        // (see `reduceMotion` checks elsewhere in this file).
        scale: reduceMotion
            ? 1.0
            : (phase == RitualPhase.launch ? 1.0 : textScale),
        duration: const Duration(
          milliseconds: 1000,
        ),
        curve: Curves.easeInOutCubic,
        child: AnimatedOpacity(
          key: const ValueKey('ritual-content-opacity'),
          duration: Duration(
            milliseconds: phase == RitualPhase.launch
                ? 750
                : wisdomRevealed
                    ? 0
                    : 1250,
          ),
          curve: Curves.easeOutCubic,
          opacity: textOpacity,
          child: phase == RitualPhase.launch
              ? const _HomeLaunchMark()
              : onPauseScreen
                  ? _HomePauseFeelText(
                      textSize: textSize,
                      color: finalColor,
                      pauseFeelOpacity: pauseFeelOpacity,
                    )
                  : onHeartScreen
                      ? SizedBox(
                          width: ritualTextWidth,
                          child: FadeTransition(
                            key: const ValueKey(
                              'ask-fade',
                            ),
                            opacity: askFadeAnimation,
                            // Approved Ritual direction: the ask breaks on
                            // meaning into two lines ("Ask from" / "your
                            // heart.") rather than wrapping mid-phrase — the
                            // crescendo across the ritual is one line, then
                            // two, then three. `BoxFit.scaleDown` only ever
                            // shrinks the pair to fit the bounded ritual
                            // content area (e.g. at very large accessibility
                            // text scales) — it never animates a scale-in,
                            // so the ask still fades in flat, matching every
                            // other ritual beat.
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Column(
                                key: const ValueKey('ritual-ask-text'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    eastLocalizations(context).askFrom,
                                    textAlign: TextAlign.center,
                                    style: _homeWisdomStyle(
                                      context,
                                      textSize,
                                      color: finalColor,
                                      height: 1.18,
                                    ),
                                  ),
                                  Text(
                                    eastLocalizations(context).yourHeart,
                                    textAlign: TextAlign.center,
                                    style: _homeWisdomStyle(
                                      context,
                                      textSize,
                                      color: finalColor,
                                      height: 1.18,
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
                                ? Semantics(
                                    container: true,
                                    excludeSemantics: true,
                                    label: currentText,
                                    hint: eastLocalizations(context)
                                        .longPressToShareWisdom,
                                    onLongPress: wisdomShareEnabled
                                        ? onWisdomLongPress
                                        : null,
                                    child: ExcludeSemantics(
                                      child: GestureDetector(
                                        key: wisdomShareOriginKey,
                                        behavior: HitTestBehavior.translucent,
                                        onLongPress: wisdomShareEnabled
                                            ? onWisdomLongPress
                                            : null,
                                        child: FadeTransition(
                                          key: const ValueKey(
                                            'wisdom-reveal-fade',
                                          ),
                                          opacity: wisdomRevealAnimation,
                                          child: currentRitualText,
                                        ),
                                      ),
                                    ),
                                  )
                                : currentRitualText,
                          ),
                        ),
        ),
      ),
    );
  }
}

class _HomeLaunchMark extends StatelessWidget {
  const _HomeLaunchMark();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final diameter = min(
          MediaQuery.sizeOf(context).width * 0.585,
          constraints.maxHeight,
        );

        return Semantics(
          label: eastLocalizations(context).east,
          child: ExcludeSemantics(
            child: Container(
              key: const ValueKey('launch-ritual-mark'),
              width: diameter,
              height: diameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: EastColors.of(context).ink.withValues(alpha: 0.70),
                  width: 0.85,
                ),
              ),
              alignment: Alignment.center,
              child: Transform.translate(
                offset: const Offset(0, -2.5),
                child: Text(
                  eastLocalizations(context).east,
                  textAlign: TextAlign.center,
                  style: _homeWisdomStyle(
                    context,
                    21.5,
                    brand: true,
                    color: EastColors.of(context).ink,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HomePauseFeelText extends StatelessWidget {
  const _HomePauseFeelText({
    required this.textSize,
    required this.color,
    required this.pauseFeelOpacity,
  });

  final double textSize;
  final Color color;
  final double pauseFeelOpacity;

  @override
  Widget build(BuildContext context) {
    // Approved Ritual direction: "Pause." holds its own axis and does not
    // move — it recedes toward ~26% value as "Feel." arrives beneath it, at
    // full value, 34pt below. No slot is reserved for "Feel." before it
    // appears — the beat is added by descent, not by revealing a hidden
    // second half of a pre-laid-out line.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedOpacity(
            duration: const Duration(milliseconds: 1250),
            curve: Curves.easeOutCubic,
            opacity: 1.0 - (pauseFeelOpacity * 0.74),
            child: Text(
              eastLocalizations(context).pause,
              textAlign: TextAlign.center,
              style: _homeWisdomStyle(
                context,
                textSize,
                color: color,
                glow: true,
              ),
            ),
          ),
          AnimatedOpacity(
            duration: const Duration(
              milliseconds: 1250,
            ),
            curve: Curves.easeOutCubic,
            opacity: pauseFeelOpacity,
            child: Padding(
              padding: const EdgeInsets.only(top: 34),
              child: Text(
                eastLocalizations(context).feel,
                textAlign: TextAlign.center,
                style: _homeWisdomStyle(
                  context,
                  textSize,
                  color: color,
                  glow: true,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeTopNavigation extends StatelessWidget {
  const _HomeTopNavigation({
    required this.onKeptPressed,
    this.keptEmphasized = false,
  });

  final VoidCallback onKeptPressed;

  /// Item 6: briefly true right after a successful save so the Kept icon
  /// receives a single, non-repeating emphasis pulse. Geometry, position,
  /// and size are unchanged; see `_KeptIconEmphasis` below.
  final bool keptEmphasized;

  static const ButtonStyle _noHaloStyle = ButtonStyle(
    backgroundColor: WidgetStatePropertyAll(Colors.transparent),
    overlayColor: WidgetStatePropertyAll(Colors.transparent),
    splashFactory: NoSplash.splashFactory,
  );

  @override
  Widget build(BuildContext context) {
    return PositionedDirectional(
      key: const ValueKey('top-navigation'),
      top: 0,
      end: 8,
      child: SizedBox.square(
        dimension: 48,
        // The explicit Semantics node is the single accessibility source of
        // truth. The no-op long press preserves the control's long-press-is-
        // a-no-op behavior without affecting a normal tap.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: () {},
          excludeFromSemantics: true,
          child: Semantics(
            label: eastLocalizations(context).keptWisdoms,
            button: true,
            onTap: onKeptPressed,
            child: ExcludeSemantics(
              child: IconButton(
                key: const ValueKey('home-kept-control'),
                style: _noHaloStyle,
                icon: _KeptIconEmphasis(
                  active: keptEmphasized,
                  child: const DoubleRingIcon(),
                ),
                onPressed: onKeptPressed,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wraps the Kept icon with the top-right Kept "teaching" breath (Update
/// 1D): the same approved outer-breathing-ring visual language as the
/// center save-ring breath (`_SaveRingBreath`), adapted proportionally to
/// this control's smaller geometry, rather than a whole-icon brightness
/// pulse. [child]'s own geometry and position are never touched — the
/// breath is a separate, purely decorative (`IgnorePointer`) outer ring
/// overlay. The caller (`home_screen.dart`) toggles [active] false/true in
/// a repeating chain (matching the center breath's own pattern) so this
/// plays exactly 5 times per activation, with a calm pause between each. A
/// fresh `TweenAnimationBuilder` is mounted each time [active] flips from
/// false to true, so every individual breath plays exactly once.
class _KeptIconEmphasis extends StatelessWidget {
  const _KeptIconEmphasis({
    required this.active,
    required this.child,
  });

  final bool active;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Stack(
      alignment: Alignment.center,
      children: [
        child,
        if (active && !reduceMotion)
          const _KeptTopNavBreath(
            key: ValueKey('kept-icon-emphasis-pulse'),
          ),
      ],
    );
  }
}

/// One breath of the top-right Kept teaching emphasis — the same visual
/// construction as `_SaveRingBreath` (a thin circular halo that expands
/// slightly and dissolves via a `sin` fade curve), scaled to this control's
/// `TopNavRingGeometry.outerDiameter` (22px).
///
/// Correction: the previous proportions (starting only 1px clear of the
/// icon's own edge, a maximum 0.32 opacity, and a sub-hairline 0.8px
/// stroke) read as too small/subtle to reliably notice. This keeps the
/// exact same animation *language* (a single expanding, fading ring — no
/// new shape, no flash, no color change) but gives it clearer presence:
/// a bigger resting gap from the icon, a larger breathing swing, a peak
/// opacity closer to (but still under) the center save-ring breath's own,
/// and a stroke matching the nav bar's own established
/// `TopNavRingGeometry.strokeWidth` rather than a thinner one-off value.
class _KeptTopNavBreath extends StatelessWidget {
  const _KeptTopNavBreath({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 1050),
        curve: Curves.easeOut,
        builder: (context, t, _) {
          final fade = sin(t * pi).clamp(0.0, 1.0);
          // Resting diameter 30px (4px clear of the 22px icon on every
          // side, up from 1px) breathing out to 36px (6px growth, up from
          // 3.5px) — a clearer, calmer swing rather than a barely-visible
          // flicker.
          final diameter = TopNavRingGeometry.outerDiameter + 8.0 + (t * 6.0);
          return Opacity(
            opacity: fade * 0.42,
            child: Container(
              width: diameter,
              height: diameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: EastColors.of(context).ink,
                  width: TopNavRingGeometry.strokeWidth,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HomeSettingsMenuControl extends StatelessWidget {
  const _HomeSettingsMenuControl({
    required this.onPressed,
  });

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return PositionedDirectional(
      key: const ValueKey('settings-menu-control'),
      top: 0,
      start: 8,
      child: SizedBox.square(
        dimension: 48,
        // Correction: the `Tooltip` wrapper is removed entirely — explicit,
        // stable `Semantics` is the source of truth for VoiceOver here, and
        // `home-settings-control` is a stable key directly on the actual
        // `IconButton`. The no-op `onLongPress` below restores the
        // long-press-is-a-no-op contract `Tooltip` used to provide
        // implicitly.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: () {},
          // Exclude this GestureDetector's own auto-injected `longPress` semantics
          // action so the explicit outer `Semantics(onTap: ...)` below
          // remains the sole accessibility source of truth.
          excludeFromSemantics: true,
          child: Semantics(
            label: eastLocalizations(context).settings,
            button: true,
            onTap: onPressed,
            child: ExcludeSemantics(
              child: IconButton(
                key: const ValueKey('home-settings-control'),
                style: _HomeTopNavigation._noHaloStyle,
                icon: const HomeTopNavBar(),
                onPressed: onPressed,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeSaveCirclePainter extends CustomPainter {
  const _HomeSaveCirclePainter({required this.filled, required this.color});

  static const double _strokeWidth = 1.0;
  // The previous text glyph occupied a smaller visual area than its 31px
  // layout box. Preserve that quiet visual scale while retaining the target.
  static const double _visibleDiameter = 18.5;

  final bool filled;
  final Color color;

  double get visibleDiameter => _visibleDiameter;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outerRadius = _visibleDiameter / 2;
    final paint = Paint()
      ..color = color
      ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;

    canvas.drawCircle(
      center,
      filled ? outerRadius : outerRadius - (_strokeWidth / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _HomeSaveCirclePainter oldDelegate) {
    return oldDelegate.filled != filled || oldDelegate.color != color;
  }
}

class _HomeSaveControl extends StatelessWidget {
  const _HomeSaveControl({
    required this.opacity,
    required this.interactionEnabled,
    required this.isCurrentFavorite,
    required this.onPressed,
    required this.onFullyVisible,
    this.showBreath = false,
  });

  final double opacity;
  final bool interactionEnabled;
  final bool isCurrentFavorite;
  final VoidCallback onPressed;
  final VoidCallback onFullyVisible;

  /// Item 6: true for a single ~800ms restrained breath around the ring,
  /// shown once right after the discovery hint text appears. The caller
  /// is responsible for setting this back to false after one play; this
  /// widget also defensively skips the breath under Reduce Motion.
  final bool showBreath;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    // Item 4: the save ring is one-way from Home. Unsaved wisdom exposes a
    // real "keep" action; already-kept wisdom exposes no action at all (no
    // remove/no toggle-off) — deletion only happens inside Kept.
    final l10n = eastLocalizations(context);
    final keepLabel = l10n.keepThisWisdom.replaceFirst(RegExp(r'[.!。]$'), '');
    final label = isCurrentFavorite ? l10n.kept : keepLabel;
    final value = label;
    // Let the platform provide its localized tap-action instruction instead
    // of embedding an English VoiceOver hint in the product UI.
    final hint = null;

    final palette = EastColors.of(context);
    final glyph = SizedBox.square(
      dimension: 31,
      child: CustomPaint(
        key: const ValueKey('home-save-circle-paint'),
        painter: _HomeSaveCirclePainter(
          filled: isCurrentFavorite,
          color: palette.ink,
        ),
      ),
    );

    // Correction pass (2nd revision) Item 1: `AbsorbPointer` only blocks its
    // own subtree from receiving pointer events — it registers no gesture
    // recognizer of its own, so once it removes the ring's own recognizer
    // from the arena, the ancestor full-screen ritual `GestureDetector`
    // becomes the *only* remaining tap recognizer and would actually win.
    // Instead, once kept, this wraps a *disabled* `IconButton` (identical
    // style/geometry to the unsaved branch below, `onPressed: null` so it
    // contributes no recognizer of its own) in a dedicated no-op
    // `GestureDetector` (`behavior: opaque`, `onTap: () {}`). That
    // GestureDetector is the only functioning recognizer at this position;
    // being deeper than (and therefore registered into the tap arena ahead
    // of) the ancestor full-screen ritual `GestureDetector`, it wins the
    // arena outright — the exact same "empty callback wins the arena"
    // technique `_HomeMainRitualGesture` already uses for its own
    // `onLongPress: () {}`. Reusing the *same* `IconButton` construction
    // (rather than a hand-picked `SizedBox` size) guarantees the kept
    // state's tap-target geometry is identical to the unsaved state's by
    // construction, with no assumption made about IconButton's own default
    // minimum tap target.
    // Explicit `foregroundColor`/`disabledForegroundColor`, both pinned to
    // the same token the glyph's own `TextStyle` already hardcodes: the
    // kept-state `IconButton` below is disabled (`onPressed: null`), and
    // without an explicit override `IconButton`'s own Material defaults
    // would resolve its `IconTheme` color to `ThemeData.disabledColor`
    // (a dimmed grey) for that state. The glyph itself is a `Text`, which
    // does not consult `IconTheme`, so this does not change what is
    // currently painted — it is a defensive, explicit statement of intent
    // that keeps this correct even if the glyph is ever changed to an
    // `Icon`.
    final iconButtonStyle = IconButton.styleFrom(
      foregroundColor: palette.ink,
      disabledForegroundColor: palette.ink,
      backgroundColor: Colors.transparent,
      overlayColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
    );

    final Widget ring = isCurrentFavorite
        ? GestureDetector(
            key: const ValueKey('home-save-control-kept'),
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: () {},
            child: IconButton(
              style: iconButtonStyle,
              icon: glyph,
              onPressed: null,
            ),
          )
        : IconButton(
            key: const ValueKey('home-save-control-unsaved'),
            // Force every interaction state (idle, hover, focus, pressed)
            // to render with no background/overlay/splash, so only the
            // bare symbol below is ever visible — no dark-grey circular
            // halo behind the ring. Position, symbol diameter, and
            // tap-target size are untouched.
            style: iconButtonStyle,
            icon: glyph,
            onPressed: onPressed,
          );

    return Positioned(
      left: 0,
      right: 0,
      top: MediaQuery.of(context).size.height / 2 + 72,
      child: Center(
        child: ExcludeSemantics(
          excluding: opacity <= 0.0,
          // Build 33 real-device Voice Control repair: `Semantics(onTap:)`
          // moved to wrap `IgnorePointer` from the *outside* -- it used to
          // sit *inside* `IgnorePointer(ignoring: !interactionEnabled)`.
          // `IgnorePointer`'s deprecated `ignoringSemantics` parameter
          // defaults to null, which its own `describeSemanticsConfiguration`
          // treats as `true`: whenever `ignoring: true` (the brief window
          // before the ring is "fully visible" here), it implicitly set
          // `SemanticsConfiguration.isBlockingUserActions` on its subtree,
          // which strips `SemanticsAction.tap` from what actually reaches
          // the platform (confirmed empirically -- an isolated probe with
          // this exact nesting had `hasAction(SemanticsAction.tap) ==
          // false`) even though `Semantics(onTap:)` still nominally had the
          // handler. This is exactly "label present, no real activate
          // action": Voice Control's "Show Names"/"Tap" (which invokes the
          // real semantics action) could not reach this control during
          // that window; VoiceOver's read-label-then-double-tap path
          // tolerated it. Moving `Semantics` outside `IgnorePointer`
          // removes it from that blocked subtree entirely (verified with
          // the same probe: `hasAction(SemanticsAction.tap) == true`),
          // while `IgnorePointer` keeps its exact key/`ignoring` value and
          // still guards *touch* the same way it always did --
          // `interactionEnabled` exists only to prevent an incidental
          // touch mis-tap during the fade-in; `onPressed`/`toggleFavorite`
          // are already independently guarded against being invoked
          // prematurely (see `toggleFavorite`'s own checks), so exposing
          // the accessibility action during that brief window is safe.
          child: Semantics(
            label: label,
            value: value,
            hint: hint,
            button: !isCurrentFavorite,
            onTap: isCurrentFavorite ? null : onPressed,
            child: IgnorePointer(
              key: const ValueKey('kept-interaction-guard'),
              ignoring: !interactionEnabled,
              child: AnimatedOpacity(
                duration: const Duration(
                  milliseconds: 1000,
                ),
                curve: Curves.easeOutCubic,
                opacity: opacity,
                onEnd: onFullyVisible,
                child: ExcludeSemantics(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (showBreath && !reduceMotion)
                        const _SaveRingBreath(
                          key: ValueKey('save-ring-breath'),
                        ),
                      ring,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A brief thin halo around the save ring that expands slightly and
/// dissolves. Purely decorative (`IgnorePointer`), never affects the ring's
/// own tap target, geometry, or position. A fresh instance is mounted each
/// time `showBreath` flips to true (see `_HomeSaveControl`), so it always
/// plays exactly once per mount.
///
/// Update 1B: the caller (`home_screen.dart`) now toggles `showBreath`
/// false/true in a repeating chain so this single-breath widget remounts
/// exactly 4 times (with a calm pause between each), rather than mounting
/// only once. Per the approved direction, only this widget's *duration* was
/// changed (800ms -> ~1.2s per breath, to match the new cadence); its outer
/// ring appearance, stroke style, opacity curve, expansion direction, and
/// easing character are all unchanged from the original approved design.
class _SaveRingBreath extends StatelessWidget {
  const _SaveRingBreath({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 1200),
        curve: Curves.easeOut,
        builder: (context, t, _) {
          final fade = sin(t * pi).clamp(0.0, 1.0);
          final diameter = 38.0 + (t * 6.0);
          return Opacity(
            opacity: fade * 0.32,
            child: Container(
              width: diameter,
              height: diameter,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: EastColors.of(context).ink,
                  width: 0.8,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// P13: the once-ever "Keep this wisdom." / "Kept." first-use discovery
/// text, positioned to the RIGHT of the save ring rather than above it, so
/// ring and text read as one quiet horizontal discovery unit rather than a
/// stacked label. Never a tutorial overlay — no box, border, arrow,
/// spotlight, or dimming; plain text only. Wrapped in `ExcludeSemantics` so
/// it never becomes a separately-focusable VoiceOver element or duplicates
/// the save control's own announcement (the ring itself remains the sole
/// actionable/announced control).
class _HomeKeptDiscoveryHint extends StatelessWidget {
  const _HomeKeptDiscoveryHint({
    required this.opacity,
    required this.text,
    required this.showBreath,
    this.onPressed,
  });

  final double opacity;
  final String text;
  final bool showBreath;
  final VoidCallback? onPressed;

  /// Matches `_HomeSaveControl`'s own ring geometry (the default
  /// `IconButton` minimum interactive dimension) and vertical anchor
  /// (`height / 2 + 72`) exactly, without touching that control's own
  /// position -- so this text's vertical center aligns with the ring's own
  /// vertical center purely by sharing the same `top`/height, never by a
  /// hand-tuned offset.
  static const double _ringDiameter = 48.0;
  static const double _ringGap = 16.0;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final textWidget = Text(
      text,
      textAlign: TextAlign.start,
      style: EastTypography.localized(
        context,
        size: 14.5,
        color: eastMutedTextColor(context).withValues(alpha: 0.70),
        height: 1.3,
        letterSpacing: 0.4,
      ),
    );
    final breathingText = showBreath && !reduceMotion
        ? TweenAnimationBuilder<double>(
            key: const ValueKey('keep-discovery-hint-breath'),
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 1200),
            curve: Curves.easeOut,
            builder: (context, t, child) {
              final breath = sin(t * pi).clamp(0.0, 1.0);
              return Opacity(
                opacity: 0.82 + (breath * 0.18),
                child: Transform.scale(
                  alignment: AlignmentDirectional.centerStart,
                  scale: 1.0 + (breath * 0.018),
                  child: child,
                ),
              );
            },
            child: textWidget,
          )
        : textWidget;
    return PositionedDirectional(
      top: size.height / 2 + 72,
      height: _ringDiameter,
      start: size.width / 2 + (_ringDiameter / 2) + _ringGap,
      end: 24,
      child: ExcludeSemantics(
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: GestureDetector(
            key: const ValueKey('keep-discovery-hint-action'),
            behavior: HitTestBehavior.translucent,
            excludeFromSemantics: true,
            onTap: onPressed,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _ringDiameter),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  opacity: opacity,
                  child: breathingText,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomePostRevealMessage extends StatelessWidget {
  const _HomePostRevealMessage({
    required this.opacity,
    required this.message,
    this.countdownPresentation,
  });

  final double opacity;
  final String message;
  final CountdownPresentation? countdownPresentation;

  @override
  Widget build(BuildContext context) {
    final presentation = countdownPresentation;
    final style = _homeWisdomStyle(
      context,
      15,
      color: eastMutedTextColor(context),
    );

    return Positioned(
      left: 0,
      right: 0,
      top: MediaQuery.of(context).size.height / 2 + 156,
      child: ExcludeSemantics(
        // Retains the existing opacity gate: no semantics from this
        // subtree (countdown or plain message) while invisible.
        excluding: opacity <= 0.0,
        child: IgnorePointer(
          ignoring: opacity < 1.0,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            opacity: opacity,
            child: Column(
              children: [
                if (presentation != null)
                  // Exactly one natural-language countdown semantics node
                  // here, composed from the same `CountdownDuration`
                  // integers the visible `HH:MM` token renders from --
                  // never the raw token. `excludeSemantics: true`
                  // suppresses the two inner Text children so they never
                  // contribute duplicate nodes.
                  Semantics(
                    label: '${presentation.sentence} '
                        '${_naturalCountdownDuration(context, presentation.duration)}',
                    excludeSemantics: true,
                    child: _HomeCountdownText(
                      presentation: presentation,
                      style: style,
                    ),
                  )
                else if (message.isNotEmpty) ...[
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: style,
                  ),
                ],
              ],
            ),
          ),
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
