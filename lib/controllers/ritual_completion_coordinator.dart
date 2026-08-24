import 'dart:async';

import '../services/daily_wisdom_access_service.dart';

typedef RecordCompletedRitual = Future<int?> Function();
typedef TrackRitualCompletion = void Function();
typedef PublishFreshWidgetReveal = void Function({
  required String wisdomId,
  required String text,
  required DateTime unlockAt,
});
typedef RefreshDailyAccessPresentation = Future<void> Function();
typedef ScheduleWisdomUnlock = Future<void> Function(DateTime unlockAt);

class RitualCompletionResult {
  const RitualCompletionResult({this.notificationOfferUnlockAt});

  /// Non-null only for a genuinely new reveal with an authoritative unlock.
  final DateTime? notificationOfferUnlockAt;
}

/// Runs the independent, best-effort effects of a committed daily wisdom.
///
/// This coordinator owns no ritual state and never decides whether a reveal
/// is valid. It receives an already-authoritative [DailyWisdomAccess], keeps
/// the established effect order, and returns only the value Home needs for
/// its existing delayed notification/discovery UI.
class RitualCompletionCoordinator {
  const RitualCompletionCoordinator({
    required RecordCompletedRitual recordCompletedRitual,
    required TrackRitualCompletion trackRitualCompletion,
    required RefreshDailyAccessPresentation refreshDailyAccessPresentation,
    required ScheduleWisdomUnlock scheduleWisdomUnlock,
    PublishFreshWidgetReveal? publishFreshWidgetReveal,
  })  : _recordCompletedRitual = recordCompletedRitual,
        _trackRitualCompletion = trackRitualCompletion,
        _publishFreshWidgetReveal = publishFreshWidgetReveal,
        _refreshDailyAccessPresentation = refreshDailyAccessPresentation,
        _scheduleWisdomUnlock = scheduleWisdomUnlock;

  final RecordCompletedRitual _recordCompletedRitual;
  final TrackRitualCompletion _trackRitualCompletion;
  final PublishFreshWidgetReveal? _publishFreshWidgetReveal;
  final RefreshDailyAccessPresentation _refreshDailyAccessPresentation;
  final ScheduleWisdomUnlock _scheduleWisdomUnlock;

  RitualCompletionResult finish(
    DailyWisdomAccess access, {
    required void Function(int? ordinal) onRitualOrdinalResolved,
  }) {
    if (access.isNew) {
      unawaited(
        _recordCompletedRitual().then(onRitualOrdinalResolved),
      );

      _trackRitualCompletion();

      final unlockAt = access.unlockAt;
      final wisdomId = access.wisdomId;
      if (unlockAt != null && wisdomId != null) {
        _publishFreshWidgetReveal?.call(
          wisdomId: wisdomId,
          text: access.text,
          unlockAt: unlockAt,
        );
      }
    }

    unawaited(
      _refreshDailyAccessPresentation().catchError((_) {
        // Countdown copy is noncritical after the wisdom is persisted.
      }),
    );

    final unlockAt = access.unlockAt;
    if (unlockAt != null) {
      unawaited(_scheduleWisdomUnlock(unlockAt));
    }

    return RitualCompletionResult(
      notificationOfferUnlockAt: access.isNew ? access.unlockAt : null,
    );
  }
}
