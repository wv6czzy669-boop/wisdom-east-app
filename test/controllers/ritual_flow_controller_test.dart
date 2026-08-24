import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/controllers/ritual_flow_controller.dart';

void main() {
  test('ritual phases retain the established legacy step mapping', () {
    expect(RitualPhase.launch.legacyStep, 0);
    expect(RitualPhase.pause.legacyStep, 1);
    expect(RitualPhase.heart.legacyStep, 2);
    expect(RitualPhase.revealed.legacyStep, 4);
    expect(RitualPhase.lockedCountdown.legacyStep, 5);
  });

  test('ritual phase predicates are mutually specific', () {
    expect(RitualPhase.pause.isPause, isTrue);
    expect(RitualPhase.heart.isHeart, isTrue);
    expect(RitualPhase.revealed.isRevealed, isTrue);
    expect(RitualPhase.lockedCountdown.isLockedCountdown, isTrue);

    expect(RitualPhase.launch.isPause, isFalse);
    expect(RitualPhase.pause.isHeart, isFalse);
    expect(RitualPhase.heart.isRevealed, isFalse);
    expect(RitualPhase.revealed.isLockedCountdown, isFalse);
  });

  test('transition timing policy is unchanged', () {
    final controller = RitualFlowController();

    for (final phase in RitualPhase.values) {
      expect(
        controller.transitionFadeOutDuration(phase),
        const Duration(milliseconds: 820),
      );
    }
    expect(
      controller.transitionSettleDuration(RitualPhase.pause),
      const Duration(milliseconds: 820),
    );
    expect(
      controller.transitionSettleDuration(RitualPhase.heart),
      const Duration(milliseconds: 560),
    );
    expect(
      controller.transitionBackgroundDepth(RitualPhase.pause),
      0.14,
    );
    expect(
      controller.transitionBackgroundDepth(RitualPhase.heart),
      0.0,
    );
  });

  test('controller owns the complete established ritual progression', () {
    final controller = RitualFlowController();

    expect(controller.phase, RitualPhase.launch);
    expect(controller.transitionTo(RitualPhase.pause), isTrue);
    expect(controller.transitionTo(RitualPhase.heart), isTrue);
    expect(controller.transitionTo(RitualPhase.revealed), isTrue);
    expect(controller.transitionTo(RitualPhase.launch), isTrue);
    expect(controller.transitionTo(RitualPhase.lockedCountdown), isTrue);
    expect(controller.transitionTo(RitualPhase.launch), isTrue);
    expect(controller.transitionTo(RitualPhase.revealed), isTrue);
  });

  test('same-phase transition is an idempotent no-op', () {
    final controller = RitualFlowController();

    expect(controller.transitionTo(RitualPhase.launch), isFalse);
    expect(controller.phase, RitualPhase.launch);
  });

  test('illegal phase jumps fail without mutating the current phase', () {
    final controller = RitualFlowController();

    expect(
      () => controller.transitionTo(RitualPhase.heart),
      throwsStateError,
    );
    expect(controller.phase, RitualPhase.launch);
  });
}
