part of '../../screens/home_screen.dart';

TextStyle _homeWisdomStyle(
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

class _HomeBackgroundDepth extends StatelessWidget {
  const _HomeBackgroundDepth({
    required this.depth,
  });

  final double depth;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 1000),
      curve: Curves.easeInOutCubic,
      color: Color.lerp(
        const Color(0xFF040404),
        const Color(0xFF000000),
        depth,
      ),
    );
  }
}

class _HomeGrainLayer extends StatelessWidget {
  const _HomeGrainLayer({
    required this.pulseController,
    required this.reduceMotion,
    required this.wisdomRevealed,
  });

  final AnimationController pulseController;
  final bool reduceMotion;
  final bool wisdomRevealed;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ExcludeSemantics(
        child: IgnorePointer(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: pulseController,
              builder: (context, child) {
                final pulse = pulseController.value;

                return CustomPaint(
                  painter: GrainPainter(
                    movement: reduceMotion ? 0.0 : pulse,
                    intensity: wisdomRevealed ? 0.01625 : 0.01235,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeRevealGlow extends StatelessWidget {
  const _HomeRevealGlow({
    required this.opacity,
  });

  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ExcludeSemantics(
        child: IgnorePointer(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 1400),
            opacity: opacity,
            child: Center(
              child: Container(
                width: 285,
                height: 285,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFD9B86F).withValues(alpha: 0.085),
                      blurRadius: 85,
                      spreadRadius: 1,
                    ),
                    BoxShadow(
                      color: const Color(0xFFF4F0E8).withValues(alpha: 0.035),
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
    );
  }
}

class _HomeMainRitualGesture extends StatelessWidget {
  const _HomeMainRitualGesture({
    required this.navigationDisabled,
    required this.semanticLabel,
    required this.semanticActionEnabled,
    required this.hideContentSemantics,
    required this.onTap,
    required this.content,
  });

  final bool navigationDisabled;
  final String? semanticLabel;
  final bool semanticActionEnabled;
  final bool hideContentSemantics;
  final VoidCallback onTap;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    final label = semanticLabel;
    final gesture = GestureDetector(
      excludeFromSemantics: true,
      behavior: HitTestBehavior.opaque,
      onTap: navigationDisabled ? null : onTap,
      onLongPress: () {},
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
      onTap: semanticActionEnabled ? onTap : null,
      child: semanticsChild,
    );
  }
}

class _HomeRitualContent extends StatelessWidget {
  const _HomeRitualContent({
    required this.screenStep,
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
    required this.wisdomShareEnabled,
    required this.wisdomShareOriginKey,
    required this.onWisdomLongPress,
  });

  final int screenStep;
  final String currentText;
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
      style: _homeWisdomStyle(
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
                                ? Semantics(
                                    container: true,
                                    excludeSemantics: true,
                                    label: currentText,
                                    hint: 'Long press to share this wisdom.',
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
                  style: _homeWisdomStyle(
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
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "Pause.",
            textAlign: TextAlign.center,
            style: _homeWisdomStyle(
              textSize,
              color: color,
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
              style: _homeWisdomStyle(
                textSize,
                color: color,
                glow: true,
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
    required this.onSettingsPressed,
    required this.onKeptPressed,
  });

  final VoidCallback onSettingsPressed;
  final VoidCallback onKeptPressed;

  @override
  Widget build(BuildContext context) {
    return Positioned(
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
              onPressed: onSettingsPressed,
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
              onPressed: onKeptPressed,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeSaveControl extends StatelessWidget {
  const _HomeSaveControl({
    required this.opacity,
    required this.interactionEnabled,
    required this.isCurrentFavorite,
    required this.onPressed,
    required this.onFullyVisible,
  });

  final double opacity;
  final bool interactionEnabled;
  final bool isCurrentFavorite;
  final VoidCallback onPressed;
  final VoidCallback onFullyVisible;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      top: MediaQuery.of(context).size.height / 2 + 72,
      child: Center(
        child: ExcludeSemantics(
          excluding: opacity <= 0.0,
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
              child: IconButton(
                tooltip: isCurrentFavorite
                    ? 'Remove kept reflection'
                    : 'Keep reflection',
                icon: Text(
                  isCurrentFavorite ? '●' : '○',
                  style: const TextStyle(
                    color: Color(0xFFF4F0E8),
                    fontSize: 31,
                    fontWeight: FontWeight.w300,
                    fontFamily: 'CormorantGaramond',
                    height: 1,
                  ),
                ),
                onPressed: onPressed,
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
  });

  final double opacity;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      top: MediaQuery.of(context).size.height / 2 + 156,
      child: ExcludeSemantics(
        excluding: opacity <= 0.0,
        child: IgnorePointer(
          ignoring: opacity < 1.0,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            opacity: opacity,
            child: Column(
              children: [
                if (message.isNotEmpty) ...[
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: _homeWisdomStyle(
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
    );
  }
}

class _HomeNotificationPermissionOffer extends StatelessWidget {
  const _HomeNotificationPermissionOffer({
    required this.onNotNow,
    required this.onAllow,
  });

  final VoidCallback onNotNow;
  final VoidCallback onAllow;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: const Alignment(0, -0.18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              key: const ValueKey('notification-permission-offer-surface'),
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 352),
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(
                borderRadius: BorderRadius.all(Radius.circular(28)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF181817),
                    Color(0xFF121211),
                  ],
                ),
              ),
              padding: const EdgeInsets.fromLTRB(24, 28, 16, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      'Return when the silence opens again.',
                      textAlign: TextAlign.center,
                      style: _homeWisdomStyle(19, height: 1.45),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: onNotNow,
                        child: Text(
                          'Not now',
                          style: _homeWisdomStyle(17),
                        ),
                      ),
                      TextButton(
                        onPressed: onAllow,
                        child: Text(
                          'Allow',
                          style: _homeWisdomStyle(17),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
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
