import '../models/daily_wisdom_record.dart';
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

class DailyWisdomAccessService {
  DailyWisdomAccessService({
    required StorageService storageService,
    WisdomClock? clock,
    this.lockDuration = const Duration(hours: 24),
  })  : _storageService = storageService,
        _clock = clock ?? DateTime.now;

  final StorageService _storageService;
  final WisdomClock _clock;
  final Duration lockDuration;

  Future<DailyWisdomAccess>? _revealInProgress;

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
    final record = await _storageService.loadDailyWisdomRecord(
      lockDuration: lockDuration,
    );
    final now = _clock();

    if (record != null &&
        _effectiveNow(now, record).isBefore(record.unlockAt)) {
      return DailyWisdomAccess(
        text: record.text,
        isNew: false,
        unlockAt: record.unlockAt,
      );
    }

    final text = selectWisdom();
    final nextRecord = DailyWisdomRecord(
      text: text,
      revealedAt: now,
      unlockAt: now.add(lockDuration),
    );

    await _storageService.saveDailyWisdomRecord(nextRecord);

    return DailyWisdomAccess(
      text: text,
      isNew: true,
      unlockAt: nextRecord.unlockAt,
    );
  }

  Future<DailyWisdomStatus> status() async {
    final record = await _storageService.loadDailyWisdomRecord(
      lockDuration: lockDuration,
    );
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

  DateTime _effectiveNow(DateTime now, DailyWisdomRecord record) {
    // A clock rollback must never shorten or clear an active lock.
    return now.isBefore(record.revealedAt) ? record.revealedAt : now;
  }
}
