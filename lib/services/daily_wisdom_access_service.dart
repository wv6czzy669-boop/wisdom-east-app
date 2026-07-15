import '../models/daily_wisdom_record.dart';
import '../models/pending_daily_wisdom_reveal.dart';
import 'storage_service.dart';

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
  });

  final bool isReady;
  final DateTime? unlockAt;
  final Duration? remaining;
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

class DailyWisdomAccessService {
  DailyWisdomAccessService({
    required StorageService storageService,
    WisdomClock? clock,
    this.lockDuration = const Duration(hours: 24),
    this.operationTimeout = const Duration(seconds: 8),
  })  : _storageService = storageService,
        _clock = clock ?? DateTime.now;

  final StorageService _storageService;
  final WisdomClock _clock;
  final Duration lockDuration;
  final Duration operationTimeout;

  static const String corruptRecordRecoveryText = 'Silence is still available.';

  Future<DailyWisdomAccess>? _revealInProgress;
  Future<DailyWisdomPreparedReveal>? _prepareInProgress;
  Future<DailyWisdomAccess>? _finalizeInProgress;
  String? _finalizeInProgressText;

  Future<DailyWisdomAccess> reveal({
    required WisdomSelector selectWisdom,
  }) {
    final inProgress = _revealInProgress;
    if (inProgress != null) return inProgress;

    final request = _revealLockedWisdom(selectWisdom);
    _revealInProgress = request;

    return request.whenComplete(() {
      if (identical(_revealInProgress, request)) {
        _revealInProgress = null;
      }
    });
  }

  Future<DailyWisdomAccess> _revealLockedWisdom(
    WisdomSelector selectWisdom,
  ) async {
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
  }) {
    final inProgress = _prepareInProgress;
    if (inProgress != null) return inProgress;

    late final Future<DailyWisdomPreparedReveal> request;
    request = _prepareReveal(selectWisdom).whenComplete(() {
      if (identical(_prepareInProgress, request)) {
        _prepareInProgress = null;
      }
    });
    _prepareInProgress = request;
    return request;
  }

  Future<DailyWisdomPreparedReveal> _prepareReveal(
    WisdomSelector selectWisdom,
  ) async {
    final record = await _loadRecordFailClosed();
    final now = _clock();

    if (_isActive(record, now)) {
      await _clearPendingBestEffort();
      return DailyWisdomPreparedReveal(
        text: record!.text,
        unlockAt: record.unlockAt,
        hasAuthoritativeRecord: true,
      );
    }

    final pendingReveal = await _loadUsablePendingReveal(record);
    if (pendingReveal != null) {
      return DailyWisdomPreparedReveal(
        text: pendingReveal.text,
        hasAuthoritativeRecord: false,
        confirmedRevealBoundary: pendingReveal.confirmedRevealBoundary,
        phase: pendingReveal.phase,
      );
    }

    final text = selectWisdom();
    if (text.trim().isEmpty) {
      throw StateError('Selected daily wisdom text cannot be empty.');
    }

    final pending = PendingDailyWisdomReveal(
      text: text,
      preparedAt: now,
    );
    await _storageService.savePendingDailyWisdomReveal(pending);

    return DailyWisdomPreparedReveal(
      text: text,
      hasAuthoritativeRecord: false,
    );
  }

  Future<DailyWisdomAccess?> recoverIncompleteReveal() async {
    final record = await _loadRecordFailClosed();
    final now = _clock();

    if (_isActive(record, now)) {
      await _clearPendingBestEffort();
      return DailyWisdomAccess(
        text: record!.text,
        isNew: false,
        unlockAt: record.unlockAt,
      );
    }

    final pendingReveal = await _loadUsablePendingReveal(record);
    if (pendingReveal == null || !pendingReveal.isRevealedPendingCommit) {
      return null;
    }

    return finalizeVisualReveal(
      text: pendingReveal.text,
      revealBoundary: pendingReveal.confirmedRevealBoundary!,
    );
  }

  Future<DailyWisdomAccess> finalizeVisualReveal({
    required String text,
    required DateTime revealBoundary,
  }) {
    final inProgress = _finalizeInProgress;
    if (inProgress != null) {
      if (_finalizeInProgressText != text) {
        return Future<DailyWisdomAccess>.error(
          StateError('Finalized wisdom must match in-flight wisdom.'),
        );
      }
      return inProgress;
    }

    late final Future<DailyWisdomAccess> request;
    request = _finalizeVisualReveal(
      text: text,
      revealBoundary: revealBoundary,
    ).whenComplete(() {
      if (identical(_finalizeInProgress, request)) {
        _finalizeInProgress = null;
        _finalizeInProgressText = null;
      }
    });
    _finalizeInProgress = request;
    _finalizeInProgressText = text;
    return request;
  }

  Future<DailyWisdomAccess> _finalizeVisualReveal({
    required String text,
    required DateTime revealBoundary,
  }) async {
    final record = await _loadRecordFailClosed();
    final now = _clock();

    if (_isActive(record, now)) {
      await _clearPendingBestEffort();
      return DailyWisdomAccess(
        text: record!.text,
        isNew: false,
        unlockAt: record.unlockAt,
      );
    }

    final pendingReveal = await _loadUsablePendingReveal(record);
    if (pendingReveal == null) {
      throw StateError('No prepared daily wisdom reveal to finalize.');
    }
    if (pendingReveal.text != text) {
      throw StateError('Finalized wisdom must match prepared wisdom.');
    }

    final confirmedBoundary = pendingReveal.isRevealedPendingCommit
        ? pendingReveal.confirmedRevealBoundary!
        : revealBoundary;
    if (confirmedBoundary.isBefore(pendingReveal.preparedAt)) {
      throw StateError('Reveal boundary cannot be before preparation.');
    }

    if (!pendingReveal.isRevealedPendingCommit) {
      await _storageService.savePendingDailyWisdomReveal(
        pendingReveal.copyWith(
          confirmedRevealBoundary: confirmedBoundary,
          phase: PendingDailyWisdomRevealPhase.revealedPendingCommit,
        ),
      );
    }

    final unlockAt = confirmedBoundary.add(lockDuration);
    final nextRecord = DailyWisdomRecord(
      text: pendingReveal.text,
      revealedAt: confirmedBoundary,
      unlockAt: unlockAt,
    );

    await _storageService.saveDailyWisdomRecord(nextRecord);
    await _clearPendingBestEffort();

    return DailyWisdomAccess(
      text: nextRecord.text,
      isNew: true,
      unlockAt: unlockAt,
    );
  }

  Future<DailyWisdomAccess> commitPreparedRevealAt(DateTime revealedAt) async {
    final pendingReveal = await _storageService.loadPendingDailyWisdomReveal();
    if (pendingReveal == null) {
      throw StateError('No prepared daily wisdom reveal to commit.');
    }

    return finalizeVisualReveal(
      text: pendingReveal.text,
      revealBoundary: revealedAt,
    );
  }

  Future<DailyWisdomAccess> commitVisuallyRevealedPending() async {
    final pendingReveal = await _storageService.loadPendingDailyWisdomReveal();
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
    await recoverIncompleteReveal();

    final record = await _loadRecordFailClosed();
    if (record == null) {
      return const DailyWisdomStatus(isReady: true);
    }

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
    );
  }

  bool _isActive(DailyWisdomRecord? record, DateTime now) {
    return record != null &&
        _effectiveNow(now, record).isBefore(record.unlockAt);
  }

  DateTime _effectiveNow(DateTime now, DailyWisdomRecord record) {
    // A clock rollback must never shorten or clear an active lock.
    return now.isBefore(record.revealedAt) ? record.revealedAt : now;
  }

  Future<PendingDailyWisdomReveal?> _loadUsablePendingReveal(
    DailyWisdomRecord? record,
  ) async {
    final pendingReveal = await _storageService.loadPendingDailyWisdomReveal();
    if (pendingReveal == null) return null;

    if (record != null && !_pendingBelongsToNextWindow(pendingReveal, record)) {
      await _clearPendingBestEffort();
      return null;
    }

    return pendingReveal;
  }

  bool _pendingBelongsToNextWindow(
    PendingDailyWisdomReveal pendingReveal,
    DailyWisdomRecord record,
  ) {
    final pendingBoundary = pendingReveal.isRevealedPendingCommit
        ? pendingReveal.confirmedRevealBoundary!
        : pendingReveal.preparedAt;

    return !pendingBoundary.isBefore(record.unlockAt);
  }

  Future<void> _clearPendingBestEffort() async {
    try {
      await _storageService.clearPendingDailyWisdomReveal();
    } catch (_) {
      // Pending reveal cleanup is best-effort once authoritative state wins.
    }
  }

  Future<DailyWisdomRecord?> _loadRecordFailClosed() async {
    try {
      return await _storageService.loadDailyWisdomRecord(
        lockDuration: lockDuration,
      );
    } on CorruptDailyWisdomRecordException {
      final recoveredAt = _clock();
      final recoveryRecord = DailyWisdomRecord(
        text: corruptRecordRecoveryText,
        revealedAt: recoveredAt,
        unlockAt: recoveredAt.add(lockDuration),
      );

      await _storageService.saveDailyWisdomRecord(recoveryRecord);
      return recoveryRecord;
    }
  }
}
