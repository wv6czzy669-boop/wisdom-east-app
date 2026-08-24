import '../services/daily_wisdom_access_service.dart';
import '../utils/countdown_formatter.dart';

enum RitualAccessAvailability { unresolved, ready, locked }

/// The identity-bearing wisdom attached to a locked daily occurrence.
///
/// A locked occurrence may legitimately have no displayable wisdom when the
/// persisted record is corrupt. In that case [RitualAccessViewState.locked]
/// still carries the countdown while [wisdom] is `null`.
class LockedWisdomReference {
  const LockedWisdomReference({
    required this.text,
    this.revealId,
    this.revealedAt,
    this.wisdomId,
  });

  final String text;
  final String? revealId;
  final DateTime? revealedAt;
  final String? wisdomId;
}

/// Home's presentation-only view of the authoritative daily-access status.
///
/// The daily access service remains the source of truth. This value simply
/// keeps its mutually exclusive UI outcomes together so Home cannot observe
/// combinations such as "unresolved and locked" or a countdown without a
/// locked state.
class RitualAccessViewState {
  const RitualAccessViewState._({
    required this.availability,
    required this.showReadyMessage,
    this.countdownDuration,
    this.wisdom,
  });

  const RitualAccessViewState.unresolved()
      : this._(
          availability: RitualAccessAvailability.unresolved,
          showReadyMessage: false,
        );

  const RitualAccessViewState.ready({required bool showReadyMessage})
      : this._(
          availability: RitualAccessAvailability.ready,
          showReadyMessage: showReadyMessage,
        );

  const RitualAccessViewState.locked({
    required CountdownDuration countdownDuration,
    LockedWisdomReference? wisdom,
  }) : this._(
          availability: RitualAccessAvailability.locked,
          showReadyMessage: false,
          countdownDuration: countdownDuration,
          wisdom: wisdom,
        );

  factory RitualAccessViewState.fromStatus(DailyWisdomStatus status) {
    if (status.isReady) {
      return RitualAccessViewState.ready(
        showReadyMessage: status.unlockAt != null,
      );
    }

    LockedWisdomReference? wisdom;
    final trimmedText = status.lockedText?.trim();
    if (trimmedText != null &&
        trimmedText.isNotEmpty &&
        trimmedText != DailyWisdomAccessService.corruptRecordRecoveryText) {
      wisdom = LockedWisdomReference(
        text: status.lockedText!,
        revealId: status.revealId,
        revealedAt: status.revealedAt,
        wisdomId: status.wisdomId,
      );
    }

    return RitualAccessViewState.locked(
      countdownDuration: CountdownFormatter.resolve(status.remaining!),
      wisdom: wisdom,
    );
  }

  final RitualAccessAvailability availability;
  final bool showReadyMessage;
  final CountdownDuration? countdownDuration;
  final LockedWisdomReference? wisdom;

  bool get isResolved => availability != RitualAccessAvailability.unresolved;
  bool get isLocked => availability == RitualAccessAvailability.locked;
}
