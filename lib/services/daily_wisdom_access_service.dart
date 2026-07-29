import 'dart:async';

import '../models/daily_access_snapshot.dart';
import '../models/daily_wisdom_record.dart';
import '../models/pending_daily_wisdom_reveal.dart';
import '../repositories/daily_access_repository.dart' hide WisdomSelector;

typedef WisdomSelector = String Function();
typedef WisdomClock = DateTime Function();

class DailyWisdomAccess {
  const DailyWisdomAccess({
    required this.text,
    required this.isNew,
    this.unlockAt,
  });

  final String text;
  final bool isNew;
  final DateTime? unlockAt;
}

class DailyWisdomStatus {
  const DailyWisdomStatus({
    required this.isReady,
    this.unlockAt,
    this.remaining,
    this.lockedText,
  });

  final bool isReady;
  final DateTime? unlockAt;
  final Duration? remaining;
  final String? lockedText;
}

class DailyWisdomPreparedReveal {
  const DailyWisdomPreparedReveal({
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

class DailyWisdomStatusUnavailableException implements Exception {
  const DailyWisdomStatusUnavailableException([this.cause]);

  final Object? cause;

  @override
  String toString() {
    final cause = this.cause;
    if (cause == null) return 'DailyWisdomStatusUnavailableException';
    return 'DailyWisdomStatusUnavailableException: $cause';
  }
}

class DailyWisdomAccessService {
  DailyWisdomAccessService({
    required DailyAccessRepository repository,
    WisdomClock? clock,
    this.lockDuration = DailyWisdomRecord.lockDuration,
    this.statusTimeout = defaultStatusTimeout,
  })  : _repository = repository,
        _clock = clock ?? DateTime.now;

  final DailyAccessRepository _repository;
  final WisdomClock _clock;
  final Duration lockDuration;
  final Duration statusTimeout;

  static const Duration defaultStatusTimeout = Duration(seconds: 4);
  static const String corruptRecordRecoveryText = 'Silence is still available.';

  Future<DailyWisdomAccess> reveal({
    required WisdomSelector selectWisdom,
  }) async {
    final prepared = await prepareReveal(selectWisdom: selectWisdom);
    if (prepared.hasAuthoritativeRecord) {
      return DailyWisdomAccess(
        text: prepared.text,
        isNew: false,
        unlockAt: prepared.unlockAt,
      );
    }

    return finalizeVisualReveal(
      text: prepared.text,
      revealBoundary: prepared.confirmedRevealBoundary ?? _clock(),
    );
  }

  Future<DailyWisdomPreparedReveal> prepareReveal({
    required WisdomSelector selectWisdom,
  }) async {
    final now = _clock();
    final prepared = await _repository.prepareReveal(
      selectWisdom: selectWisdom,
      preparedAt: now,
      now: now,
    );
    return DailyWisdomPreparedReveal(
      text: prepared.text,
      hasAuthoritativeRecord: prepared.hasAuthoritativeRecord,
      unlockAt: prepared.unlockAt,
      confirmedRevealBoundary: prepared.confirmedRevealBoundary,
      phase: prepared.phase,
    );
  }

  /// Delegates to [DailyAccessRepository.backfillRevealIdIfNeeded]. Safe and
  /// idempotent to call on every launch; callers should still guard the
  /// call with their own error handling since it shares the underlying
  /// corruption-recovery path, which is not guaranteed exception-free.
  Future<void> backfillRevealIdIfNeeded() {
    return _repository.backfillRevealIdIfNeeded();
  }

  Future<DailyWisdomAccess?> recoverIncompleteReveal() async {
    final now = _clock();
    final record = await _repository.recoverIncompleteReveal(now: now);
    if (record == null) {
      return null;
    }

    return DailyWisdomAccess(
      text: record.text,
      isNew: _isSameMoment(record.revealedAt, now),
      unlockAt: record.unlockAt,
    );
  }

  Future<DailyWisdomAccess> finalizeVisualReveal({
    required String text,
    required DateTime revealBoundary,
  }) async {
    final record = await _repository.finalizeVisualReveal(
      text: text,
      revealBoundary: revealBoundary,
      now: _clock(),
    );
    return DailyWisdomAccess(
      text: record.text,
      isNew: record.text == text &&
          _isSameMoment(record.revealedAt, revealBoundary),
      unlockAt: record.unlockAt,
    );
  }

  Future<DailyWisdomAccess> commitPreparedRevealAt(DateTime revealedAt) async {
    final pendingReveal = await _repository.loadPendingDailyWisdomReveal();
    if (pendingReveal == null) {
      throw StateError('No prepared daily wisdom reveal to commit.');
    }

    return finalizeVisualReveal(
      text: pendingReveal.text,
      revealBoundary: revealedAt,
    );
  }

  Future<DailyWisdomAccess> commitVisuallyRevealedPending() async {
    final pendingReveal = await _repository.loadPendingDailyWisdomReveal();
    if (pendingReveal == null || !pendingReveal.isRevealedPendingCommit) {
      throw StateError(
        'Daily wisdom cannot be committed before confirmed visual reveal.',
      );
    }

    return finalizeVisualReveal(
      text: pendingReveal.text,
      revealBoundary: pendingReveal.confirmedRevealBoundary!,
    );
  }

  Future<DailyWisdomStatus> status() async {
    try {
      await _observeForStatus(
        _repository.recoverIncompleteReveal(now: _clock()),
      );

      final snapshot = await _observeForStatus(
        _repository.snapshot(now: _clock()),
      );
      if (snapshot is! DailyAccessLocked) {
        return const DailyWisdomStatus(isReady: true);
      }

      final record = snapshot.record;
      final now = _effectiveNow(_clock(), record);
      if (!now.isBefore(record.unlockAt)) {
        return DailyWisdomStatus(
          isReady: true,
          unlockAt: record.unlockAt,
          remaining: Duration.zero,
        );
      }

      return DailyWisdomStatus(
        isReady: false,
        unlockAt: record.unlockAt,
        remaining: record.unlockAt.difference(now),
        lockedText: record.text,
      );
    } on TimeoutException catch (error) {
      throw DailyWisdomStatusUnavailableException(error);
    }
  }

  Future<T> _observeForStatus<T>(Future<T> operation) {
    return _repository.observeWithUiTimeout(
      operation: operation,
      timeout: statusTimeout,
    );
  }

  DateTime _effectiveNow(DateTime now, DailyWisdomRecord record) {
    // A clock rollback must never shorten or clear an active lock.
    return now.isBefore(record.revealedAt) ? record.revealedAt : now;
  }

  bool _isSameMoment(DateTime first, DateTime second) {
    return first.millisecondsSinceEpoch == second.millisecondsSinceEpoch;
  }
}
