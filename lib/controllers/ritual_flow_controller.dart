/// The five stable presentation phases in EAST.'s ritual.
///
/// The former implementation represented these with the unrelated integers
/// 0, 1, 2, 4 and 5. Keeping the meaning in a type prevents an invalid step
/// from entering the state while preserving the exact existing transitions.
enum RitualPhase {
  launch,
  pause,
  heart,
  revealed,
  lockedCountdown;

  bool get isPause => this == RitualPhase.pause;

  bool get isHeart => this == RitualPhase.heart;

  bool get isRevealed => this == RitualPhase.revealed;

  bool get isLockedCountdown => this == RitualPhase.lockedCountdown;

  /// Temporary compatibility value for existing black-box tests and
  /// diagnostics. Production flow logic must use [RitualPhase] directly.
  int get legacyStep {
    switch (this) {
      case RitualPhase.launch:
        return 0;
      case RitualPhase.pause:
        return 1;
      case RitualPhase.heart:
        return 2;
      case RitualPhase.revealed:
        return 4;
      case RitualPhase.lockedCountdown:
        return 5;
    }
  }
}

class RitualFlowController {
  RitualFlowController({RitualPhase initialPhase = RitualPhase.launch})
      : _phase = initialPhase;

  RitualPhase _phase;

  RitualPhase get phase => _phase;

  /// Moves the ritual to one of the transitions that already exists in the
  /// product state machine. Re-entering the current phase is an idempotent
  /// no-op; an impossible transition fails immediately instead of allowing
  /// Home to enter a combination the UI was never designed to represent.
  bool transitionTo(RitualPhase nextPhase) {
    if (nextPhase == _phase) return false;
    if (!canTransitionTo(nextPhase)) {
      throw StateError('Illegal ritual transition: $_phase -> $nextPhase');
    }
    _phase = nextPhase;
    return true;
  }

  bool canTransitionTo(RitualPhase nextPhase) {
    if (nextPhase == _phase) return true;
    return switch (_phase) {
      RitualPhase.launch => nextPhase == RitualPhase.pause ||
          nextPhase == RitualPhase.revealed ||
          nextPhase == RitualPhase.lockedCountdown,
      RitualPhase.pause => nextPhase == RitualPhase.heart,
      RitualPhase.heart => nextPhase == RitualPhase.revealed,
      // Offline reading can temporarily show the previous occurrence while
      // Ask is waiting for an account connection. Its explicit Retry control
      // returns to that question; it does not authorize another occurrence.
      RitualPhase.revealed =>
        nextPhase == RitualPhase.launch || nextPhase == RitualPhase.heart,
      RitualPhase.lockedCountdown => nextPhase == RitualPhase.launch,
    };
  }

  Duration transitionFadeOutDuration(RitualPhase _) =>
      const Duration(milliseconds: 820);

  Duration transitionSettleDuration(RitualPhase nextPhase) => Duration(
        milliseconds: nextPhase == RitualPhase.pause ? 820 : 560,
      );

  double transitionBackgroundDepth(RitualPhase nextPhase) =>
      nextPhase == RitualPhase.pause ? 0.14 : 0.0;
}
