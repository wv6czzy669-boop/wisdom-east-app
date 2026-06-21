import 'dart:async';
import 'dart:convert';

import 'storage_service.dart';

typedef KeeperWisdomSelector = String Function();
typedef KeeperWisdomClock = DateTime Function();

class KeeperDailyStatus {
  const KeeperDailyStatus({
    required this.revealCount,
    required this.resetAt,
    required this.lastWisdom,
    required this.hasPendingReveal,
  });

  final int revealCount;
  final DateTime resetAt;
  final String? lastWisdom;
  final bool hasPendingReveal;

  bool get canReveal => revealCount < KeeperDailyAccessService.maxReveals;
  Duration remaining(DateTime now) => resetAt.difference(now);
}

class KeeperDailyAccess {
  const KeeperDailyAccess({
    required this.text,
    required this.isNew,
    required this.status,
  });

  final String text;
  final bool isNew;
  final KeeperDailyStatus status;
}

class KeeperDailyAccessService {
  KeeperDailyAccessService({
    required StorageService storageService,
    KeeperWisdomClock? clock,
  })  : _storageService = storageService,
        _clock = clock ?? DateTime.now;

  static const int maxReveals = 3;
  static const String storageKey = 'keeper_daily_wisdom_state';

  final StorageService _storageService;
  final KeeperWisdomClock _clock;

  Future<void> _operationTail = Future<void>.value();
  Future<KeeperDailyAccess>? _revealInProgress;

  Future<KeeperDailyStatus> status() {
    return _serialize(() async {
      final now = _clock();
      final record = await _loadNormalizedRecord(now);
      return _statusFor(record, now);
    });
  }

  Future<void> seedFromExistingWisdomIfNeeded({
    required String text,
    required DateTime revealedAt,
  }) {
    return _serialize(() async {
      final now = _clock();
      if (_localDate(revealedAt) != _localDate(now)) return;

      final prefs = await _storageService.getPrefs();
      if (prefs.containsKey(storageKey)) return;

      await _saveRecord(
        _KeeperDailyRecord(
          localDate: _localDate(now),
          revealCount: 1,
          lastWisdom: text,
          hasPendingReveal: false,
        ),
      );
    });
  }

  Future<KeeperDailyAccess> reveal({
    required KeeperWisdomSelector selectWisdom,
  }) {
    final inProgress = _revealInProgress;
    if (inProgress != null) return inProgress;

    final request = _serialize(() => _reveal(selectWisdom));
    _revealInProgress = request;

    return request.whenComplete(() {
      if (identical(_revealInProgress, request)) {
        _revealInProgress = null;
      }
    });
  }

  Future<KeeperDailyAccess> _reveal(
    KeeperWisdomSelector selectWisdom,
  ) async {
    final now = _clock();
    final record = await _loadNormalizedRecord(now);

    if (record.hasPendingReveal) {
      final pendingWisdom = record.lastWisdom;
      if (pendingWisdom == null || pendingWisdom.trim().isEmpty) {
        throw StateError('Pending Keeper wisdom state is unavailable.');
      }

      return KeeperDailyAccess(
        text: pendingWisdom,
        isNew: false,
        status: _statusFor(record, now),
      );
    }

    if (record.revealCount >= maxReveals) {
      final lastWisdom = record.lastWisdom;
      if (lastWisdom == null || lastWisdom.trim().isEmpty) {
        throw StateError('Keeper daily wisdom state is unavailable.');
      }

      return KeeperDailyAccess(
        text: lastWisdom,
        isNew: false,
        status: _statusFor(record, now),
      );
    }

    final text = selectWisdom();
    final nextRecord = _KeeperDailyRecord(
      localDate: record.localDate,
      revealCount: record.revealCount + 1,
      lastWisdom: text,
      hasPendingReveal: true,
    );

    await _saveRecord(nextRecord);

    return KeeperDailyAccess(
      text: text,
      isNew: true,
      status: _statusFor(nextRecord, now),
    );
  }

  Future<void> markDisplayed(String text) {
    return _serialize(() async {
      final now = _clock();
      final record = await _loadNormalizedRecord(now);
      if (!record.hasPendingReveal || record.lastWisdom != text) return;

      await _saveRecord(
        _KeeperDailyRecord(
          localDate: record.localDate,
          revealCount: record.revealCount,
          lastWisdom: record.lastWisdom,
          hasPendingReveal: false,
        ),
      );
    });
  }

  Future<_KeeperDailyRecord> _loadNormalizedRecord(DateTime now) async {
    final prefs = await _storageService.getPrefs();
    final localDate = _localDate(now);
    final String? encoded;

    try {
      encoded = prefs.getString(storageKey);
    } catch (_) {
      return _recoverFailClosed(localDate);
    }

    if (encoded == null) {
      return _KeeperDailyRecord(
        localDate: localDate,
        revealCount: 0,
        lastWisdom: null,
        hasPendingReveal: false,
      );
    }

    final _KeeperDailyRecord record;
    try {
      record = _KeeperDailyRecord.decode(encoded);
    } catch (_) {
      return _recoverFailClosed(localDate);
    }

    if (record.localDate == localDate) return record;

    // A clock rollback must not create a fresh local-calendar allowance.
    if (localDate.compareTo(record.localDate) < 0) return record;

    // A selected wisdom must be displayed before the allowance can roll over.
    // Keeping the prior date here preserves that exact wisdom across midnight;
    // the next status read resets the new day after it is acknowledged.
    if (record.hasPendingReveal) return record;

    final resetRecord = _KeeperDailyRecord(
      localDate: localDate,
      revealCount: 0,
      lastWisdom: record.lastWisdom,
      hasPendingReveal: record.hasPendingReveal,
    );
    await _saveRecord(resetRecord);
    return resetRecord;
  }

  Future<_KeeperDailyRecord> _recoverFailClosed(String localDate) async {
    final recovery = _KeeperDailyRecord(
      localDate: localDate,
      revealCount: maxReveals,
      lastWisdom: null,
      hasPendingReveal: false,
    );
    await _saveRecord(recovery);
    return recovery;
  }

  KeeperDailyStatus _statusFor(_KeeperDailyRecord record, DateTime now) {
    return KeeperDailyStatus(
      revealCount: record.revealCount,
      resetAt: DateTime(now.year, now.month, now.day + 1),
      lastWisdom: record.lastWisdom,
      hasPendingReveal: record.hasPendingReveal,
    );
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final completer = Completer<T>();

    _operationTail = _operationTail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });

    return completer.future;
  }

  Future<void> _saveRecord(_KeeperDailyRecord record) async {
    final prefs = await _storageService.getPrefs();
    final saved = await prefs.setString(storageKey, record.encode());
    if (!saved) {
      throw StateError('Keeper daily wisdom state could not be persisted.');
    }
  }

  String _localDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}

class _KeeperDailyRecord {
  const _KeeperDailyRecord({
    required this.localDate,
    required this.revealCount,
    required this.lastWisdom,
    required this.hasPendingReveal,
  });

  final String localDate;
  final int revealCount;
  final String? lastWisdom;
  final bool hasPendingReveal;

  String encode() {
    return jsonEncode({
      'localDate': localDate,
      'revealCount': revealCount,
      'lastWisdom': lastWisdom,
      'hasPendingReveal': hasPendingReveal,
    });
  }

  factory _KeeperDailyRecord.decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid Keeper daily state.');
    }

    final localDate = decoded['localDate'];
    final revealCount = decoded['revealCount'];
    final lastWisdom = decoded['lastWisdom'];
    final hasPendingReveal = decoded['hasPendingReveal'] ?? false;

    if (localDate is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(localDate) ||
        revealCount is! int ||
        revealCount < 0 ||
        revealCount > KeeperDailyAccessService.maxReveals ||
        (lastWisdom != null && lastWisdom is! String) ||
        hasPendingReveal is! bool ||
        (revealCount > 0 &&
            (lastWisdom is! String || lastWisdom.trim().isEmpty)) ||
        (hasPendingReveal &&
            (revealCount == 0 ||
                lastWisdom is! String ||
                lastWisdom.trim().isEmpty))) {
      throw const FormatException('Invalid Keeper daily state.');
    }

    return _KeeperDailyRecord(
      localDate: localDate,
      revealCount: revealCount,
      lastWisdom: lastWisdom as String?,
      hasPendingReveal: hasPendingReveal,
    );
  }
}
