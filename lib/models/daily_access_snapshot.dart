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
  const PreparedDailyAccess({
    required this.text,
    required this.hasAuthoritativeRecord,
    this.unlockAt,
    this.confirmedRevealBoundary,
    this.phase = PendingDailyWisdomRevealPhase.prepared,
  });

  final String text;
  final bool hasAuthoritativeRecord;
  final DateTime? unlockAt;
  final DateTime? confirmedRevealBoundary;
  final PendingDailyWisdomRevealPhase phase;
}
