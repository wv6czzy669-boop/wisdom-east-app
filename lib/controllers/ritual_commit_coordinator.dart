import 'dart:async';

import '../services/daily_wisdom_access_service.dart';

sealed class RitualCommitResolution {
  const RitualCommitResolution();
}

final class RitualCommitSucceeded extends RitualCommitResolution {
  const RitualCommitSucceeded(this.access);

  final DailyWisdomAccess access;
}

final class RitualCommitFailed extends RitualCommitResolution {
  const RitualCommitFailed();
}

sealed class RitualCommitAttempt {
  const RitualCommitAttempt();
}

final class RitualCommitCompleted extends RitualCommitAttempt {
  const RitualCommitCompleted(this.resolution);

  final RitualCommitResolution resolution;
}

final class RitualCommitTimedOut extends RitualCommitAttempt {
  const RitualCommitTimedOut(this.eventualResolution);

  /// Always resolves successfully to a typed outcome. A late persistence
  /// error is contained as [RitualCommitFailed], never left unhandled.
  final Future<RitualCommitResolution> eventualResolution;
}

/// Gives fresh and retry reveal commits one timeout/error contract.
///
/// It owns no UI state, reveal identity, persistence, or timing beyond the
/// already-configured operation timeout. Home remains responsible for the
/// established visual delays and for ignoring completions from stale flows.
final class RitualCommitCoordinator {
  const RitualCommitCoordinator({required this.timeout});

  final Duration timeout;

  Future<RitualCommitAttempt> run(
    Future<DailyWisdomAccess> operation,
  ) async {
    final eventualResolution = operation.then<RitualCommitResolution>(
      RitualCommitSucceeded.new,
      onError: (_, __) => const RitualCommitFailed(),
    );

    try {
      final resolution = await eventualResolution.timeout(timeout);
      return RitualCommitCompleted(resolution);
    } on TimeoutException {
      return RitualCommitTimedOut(eventualResolution);
    }
  }
}
