import 'daily_wisdom_record.dart';
import 'pending_daily_wisdom_reveal.dart';

sealed class DailyAccessSnapshot {
  const DailyAccessSnapshot();
}

final class DailyAccessReady extends DailyAccessSnapshot {
  const DailyAccessReady({this.pending});

  final PendingDailyWisdomReveal? pending;
}

final class DailyAccessLocked extends DailyAccessSnapshot {
  const DailyAccessLocked(this.record);

  final DailyWisdomRecord record;
}

final class DailyAccessPendingCommit extends DailyAccessSnapshot {
  const DailyAccessPendingCommit(this.pending);

  final PendingDailyWisdomReveal pending;
}

final class PreparedDailyAccess {
  PreparedDailyAccess({
    required this.text,
    required this.hasAuthoritativeRecord,
    this.unlockAt,
    this.confirmedRevealBoundary,
    this.phase = PendingDailyWisdomRevealPhase.prepared,
    this.revealId,
    this.revealedAt,
    this.wisdomId,
  }) {
    _validate(
      hasAuthoritativeRecord: hasAuthoritativeRecord,
      revealId: revealId,
      revealedAt: revealedAt,
    );
  }

  final String text;
  final bool hasAuthoritativeRecord;
  final DateTime? unlockAt;
  final DateTime? confirmedRevealBoundary;
  final PendingDailyWisdomRevealPhase phase;

  /// Identity of the authoritative reveal this prepared access refers to.
  /// Truthfully copied from an existing authoritative [DailyWisdomRecord]
  /// only — never minted here. Always `null` when [hasAuthoritativeRecord]
  /// is false (a genuinely fresh, pre-commit prepared reveal never has one
  /// yet). May still be `null` even when [hasAuthoritativeRecord] is true,
  /// for an old Build 25 authoritative record whose one-time `revealId`
  /// backfill has not (yet) completed.
  final String? revealId;

  /// When the authoritative reveal actually happened. Always populated
  /// when [hasAuthoritativeRecord] is true (every authoritative
  /// [DailyWisdomRecord] carries a non-null `revealedAt`); always `null`
  /// otherwise.
  final DateTime? revealedAt;
  final String? wisdomId;

  static void _validate({
    required bool hasAuthoritativeRecord,
    required String? revealId,
    required DateTime? revealedAt,
  }) {
    if (!hasAuthoritativeRecord) {
      if (revealId != null || revealedAt != null) {
        throw ArgumentError(
          'A non-authoritative PreparedDailyAccess cannot carry a revealId '
          'or revealedAt: neither value may exist before an authoritative '
          'commit.',
        );
      }
      return;
    }

    if (revealedAt == null) {
      throw ArgumentError(
        "An authoritative PreparedDailyAccess must carry the record's "
        'revealedAt.',
      );
    }
  }
}
