import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/daily_access_snapshot.dart';
import '../models/daily_wisdom_record.dart';
import '../models/pending_daily_wisdom_reveal.dart';
import '../persistence/persistence_operation_coordinator.dart';
import '../persistence/storage_preferences_adapter.dart';

typedef WisdomSelector = String Function();

class CorruptDailyWisdomRecordException implements Exception {
  const CorruptDailyWisdomRecordException([this.encodedRecord]);

  final String? encodedRecord;
}

class DailyAccessRepository {
  DailyAccessRepository({
    required StoragePreferencesAdapter preferencesAdapter,
    required PersistenceOperationCoordinator operationCoordinator,
    Future<void> Function(SharedPreferences prefs, String key)?
        obsoleteKeyRemover,
    Future<void> Function(SharedPreferences prefs, String key)?
        pendingRevealRemover,
  })  : _preferencesAdapter = preferencesAdapter,
        _operationCoordinator = operationCoordinator,
        _obsoleteKeyRemover = obsoleteKeyRemover,
        _pendingRevealRemover = pendingRevealRemover;

  static const String resourceKey = 'daily_access';
  static const String dailyWisdomAccessKey = 'daily_wisdom_access';
  static const String pendingDailyWisdomRevealKey =
      'pending_daily_wisdom_reveal';
  static const String legacyDailyWisdomTextKey = 'daily_wisdom_text';
  static const String legacyWisdomUnlockTimeKey = 'wisdom_unlock_time_ms';
  static const String obsoleteKeeperDailyWisdomKey =
      'keeper_daily_wisdom_state';
  static const List<String> obsoleteAccessKeys = [
    legacyDailyWisdomTextKey,
    legacyWisdomUnlockTimeKey,
    obsoleteKeeperDailyWisdomKey,
  ];

  final StoragePreferencesAdapter _preferencesAdapter;
  final PersistenceOperationCoordinator _operationCoordinator;
  final Future<void> Function(SharedPreferences prefs, String key)?
      _obsoleteKeyRemover;
  final Future<void> Function(SharedPreferences prefs, String key)?
      _pendingRevealRemover;
  static const Uuid _uuid = Uuid();

  Future<DailyAccessSnapshot> snapshot({required DateTime now}) async {
    return _operationCoordinator.runRead<DailyAccessSnapshot>(
      resourceKey: resourceKey,
      operation: () => _readSnapshot(now: now),
    );
  }

  Future<T> observeWithUiTimeout<T>({
    required Future<T> operation,
    required Duration timeout,
  }) {
    return _operationCoordinator.observeWithUiTimeout(
      operation: operation,
      timeout: timeout,
    );
  }

  Future<void> waitForIdle() {
    return _operationCoordinator.waitForIdle(resourceKey);
  }

  Future<PreparedDailyAccess> prepareReveal({
    required WisdomSelector selectWisdom,
    required DateTime preparedAt,
    required DateTime now,
  }) {
    return _operationCoordinator.runMutation<PreparedDailyAccess>(
      resourceKey: resourceKey,
      operationKey: 'prepare',
      operation: () => _prepareReveal(
        selectWisdom: selectWisdom,
        preparedAt: preparedAt,
        now: now,
      ),
    );
  }

  Future<DailyWisdomRecord?> recoverIncompleteReveal({
    required DateTime now,
  }) {
    return _operationCoordinator.runMutation<DailyWisdomRecord?>(
      resourceKey: resourceKey,
      operationKey: 'recover',
      operation: () => _recoverIncompleteReveal(now: now),
    );
  }

  Future<DailyWisdomRecord> finalizeVisualReveal({
    required String text,
    required DateTime revealBoundary,
    required DateTime now,
  }) {
    return _operationCoordinator.runMutation<DailyWisdomRecord>(
      resourceKey: resourceKey,
      operationKey: 'finalize:$text',
      operation: () => _finalizeVisualReveal(
        text: text,
        revealBoundary: revealBoundary,
        now: now,
      ),
    );
  }

  Future<DailyWisdomRecord?> loadDailyWisdomRecord() async {
    return _operationCoordinator.runRead<DailyWisdomRecord?>(
      resourceKey: resourceKey,
      operation: _loadRecordRecoveringCorruption,
    );
  }

  Future<void> saveDailyWisdomRecord(DailyWisdomRecord record) {
    return _operationCoordinator.runMutation<void>(
      resourceKey: resourceKey,
      operationKey: 'save-daily',
      operation: () async {
        await _saveDailyWisdomRecord(record);
      },
    );
  }

  Future<void> clearDailyWisdomRecordBestEffort() async {
    await _operationCoordinator.runMutation<void>(
      resourceKey: resourceKey,
      operationKey: 'clear-daily',
      operation: () async {
        await _preferencesAdapter.remove(dailyWisdomAccessKey);
      },
    );
  }

  /// Build 25 upgrade path: gives the existing authoritative daily record a
  /// stable [DailyWisdomRecord.revealId] if it does not already have one.
  ///
  /// Safe to call on every app launch: a no-op when there is no record, or
  /// the record already has a revealId. Never regenerates an already
  /// persisted revealId, never rewrites revealedAt/unlockAt/text, never
  /// extends or resets the rolling 24-hour lock, and never invalidates the
  /// previously valid Build 25 record on write or verification failure.
  Future<void> backfillRevealIdIfNeeded() {
    return _operationCoordinator.runMutation<void>(
      resourceKey: resourceKey,
      operationKey: 'backfill-revealId',
      operation: _backfillRevealIdIfNeeded,
    );
  }

  Future<PendingDailyWisdomReveal?> loadPendingDailyWisdomReveal() {
    return _operationCoordinator.runRead<PendingDailyWisdomReveal?>(
      resourceKey: resourceKey,
      operation: _loadPendingDailyWisdomReveal,
    );
  }

  Future<void> savePendingDailyWisdomReveal(
    PendingDailyWisdomReveal reveal,
  ) {
    return _operationCoordinator.runMutation<void>(
      resourceKey: resourceKey,
      operationKey: 'save-pending',
      operation: () async {
        await _savePendingDailyWisdomReveal(reveal);
      },
    );
  }

  Future<void> clearPendingDailyWisdomReveal() async {
    return _operationCoordinator.runMutation<void>(
      resourceKey: resourceKey,
      operationKey: 'clear-pending',
      operation: _clearPendingDailyWisdomReveal,
    );
  }

  Future<void> _clearPendingDailyWisdomReveal() async {
    final remover = _pendingRevealRemover;
    if (remover == null) {
      await _preferencesAdapter.remove(pendingDailyWisdomRevealKey);
    } else {
      await remover(
        await _preferencesAdapter.preferences,
        pendingDailyWisdomRevealKey,
      );
    }
  }

  Future<DailyAccessSnapshot> _readSnapshot({required DateTime now}) async {
    final record = await _loadRecordRecoveringCorruption();
    if (_isActive(record, now)) {
      return DailyAccessLocked(record!);
    }

    final pending = await _loadUsablePendingReveal(record);
    if (pending == null) {
      return const DailyAccessReady();
    }

    if (pending.isRevealedPendingCommit) {
      return DailyAccessPendingCommit(pending);
    }

    return DailyAccessReady(pending: pending);
  }

  Future<PreparedDailyAccess> _prepareReveal({
    required WisdomSelector selectWisdom,
    required DateTime preparedAt,
    required DateTime now,
  }) async {
    final snapshot = await _readSnapshot(now: now);
    switch (snapshot) {
      case DailyAccessLocked(:final record):
        return PreparedDailyAccess(
          text: record.text,
          hasAuthoritativeRecord: true,
          unlockAt: record.unlockAt,
          // Copied verbatim from the already-authoritative record — never
          // generated here. `revealId` may still be null for an
          // old, not-yet-backfilled Build 25 record.
          revealId: record.revealId,
          revealedAt: record.revealedAt,
        );
      case DailyAccessPendingCommit(:final pending):
        return PreparedDailyAccess(
          text: pending.text,
          hasAuthoritativeRecord: false,
          confirmedRevealBoundary: pending.confirmedRevealBoundary,
          phase: pending.phase,
        );
      case DailyAccessReady(:final pending):
        if (pending != null) {
          return PreparedDailyAccess(
            text: pending.text,
            hasAuthoritativeRecord: false,
            confirmedRevealBoundary: pending.confirmedRevealBoundary,
            phase: pending.phase,
          );
        }

        final text = selectWisdom();
        if (text.trim().isEmpty) {
          throw StateError('Selected daily wisdom text cannot be empty.');
        }

        final nextPending = PendingDailyWisdomReveal(
          text: text,
          preparedAt: preparedAt,
        );
        await _savePendingDailyWisdomReveal(nextPending);
        return PreparedDailyAccess(
          text: text,
          hasAuthoritativeRecord: false,
        );
    }
  }

  Future<DailyWisdomRecord?> _recoverIncompleteReveal({
    required DateTime now,
  }) async {
    final record = await _loadRecordRecoveringCorruption();
    if (_isActive(record, now)) {
      return record;
    }

    final pending = await _loadUsablePendingReveal(record);
    if (pending == null || !pending.isRevealedPendingCommit) {
      return null;
    }

    return _writePendingRevealAsDaily(
      pendingReveal: pending,
      confirmedBoundary: pending.confirmedRevealBoundary!,
    );
  }

  Future<DailyWisdomRecord> _finalizeVisualReveal({
    required String text,
    required DateTime revealBoundary,
    required DateTime now,
  }) async {
    final record = await _loadRecordRecoveringCorruption();
    if (_isActive(record, now)) {
      return record!;
    }

    final pending = await _loadUsablePendingReveal(record);
    if (pending == null) {
      throw StateError('No prepared daily wisdom reveal to finalize.');
    }
    if (pending.text != text) {
      throw StateError('Finalized wisdom must match prepared wisdom.');
    }

    final confirmedBoundary = pending.isRevealedPendingCommit
        ? pending.confirmedRevealBoundary!
        : revealBoundary;
    if (confirmedBoundary.isBefore(pending.preparedAt)) {
      throw StateError('Reveal boundary cannot be before preparation.');
    }

    final committedPending = pending.isRevealedPendingCommit
        ? pending
        : pending.copyWith(
            confirmedRevealBoundary: confirmedBoundary,
            phase: PendingDailyWisdomRevealPhase.revealedPendingCommit,
          );

    if (!pending.isRevealedPendingCommit) {
      await _savePendingDailyWisdomReveal(committedPending);
    }

    return _writePendingRevealAsDaily(
      pendingReveal: committedPending,
      confirmedBoundary: confirmedBoundary,
    );
  }

  Future<DailyWisdomRecord?> _loadRecordRecoveringCorruption() async {
    try {
      return await _loadDailyWisdomRecordStrict();
    } on CorruptDailyWisdomRecordException catch (error) {
      final recoveredRecord = await _recoverRecordFromCorruptDailyRecord();
      if (recoveredRecord != null) return recoveredRecord;

      final encodedRecord = error.encodedRecord;
      if (encodedRecord != null) {
        _deferClearSpecificDailyBestEffort(encodedRecord);
      }
      return null;
    }
  }

  Future<DailyWisdomRecord?> _loadDailyWisdomRecordStrict() async {
    final String? encodedRecord;
    try {
      encodedRecord = await _preferencesAdapter.getString(dailyWisdomAccessKey);
    } catch (_) {
      throw const CorruptDailyWisdomRecordException();
    }

    if (encodedRecord != null) {
      try {
        final record = DailyWisdomRecord.decode(encodedRecord);
        _deferRemoveObsoleteAccessStateBestEffort();
        return record;
      } catch (_) {
        throw CorruptDailyWisdomRecordException(encodedRecord);
      }
    }

    _deferRemoveObsoleteAccessStateBestEffort();
    return null;
  }

  Future<DailyWisdomRecord?> _recoverRecordFromCorruptDailyRecord() async {
    final pending = await _loadPendingDailyWisdomReveal();
    if (pending != null && pending.isRevealedPendingCommit) {
      return _writePendingRevealAsDaily(
        pendingReveal: pending,
        confirmedBoundary: pending.confirmedRevealBoundary!,
      );
    }

    return null;
  }

  Future<PendingDailyWisdomReveal?> _loadPendingDailyWisdomReveal() async {
    final String? encodedReveal;
    try {
      encodedReveal =
          await _preferencesAdapter.getString(pendingDailyWisdomRevealKey);
    } catch (_) {
      return null;
    }

    if (encodedReveal == null) return null;

    try {
      return PendingDailyWisdomReveal.decode(encodedReveal);
    } catch (_) {
      _deferClearSpecificPendingBestEffort(encodedReveal);
      return null;
    }
  }

  Future<void> _savePendingDailyWisdomReveal(
    PendingDailyWisdomReveal reveal,
  ) {
    return _preferencesAdapter.setString(
      pendingDailyWisdomRevealKey,
      reveal.encode(),
    );
  }

  Future<DailyWisdomRecord> _writePendingRevealAsDaily({
    required PendingDailyWisdomReveal pendingReveal,
    required DateTime confirmedBoundary,
  }) async {
    final unlockAt = confirmedBoundary.add(DailyWisdomRecord.lockDuration);
    // Sole authoritative commit point: a revealId is minted exactly once
    // here, whether this call originates from an ordinary finalize or from
    // recovery promoting a pending reveal. Every caller of this method
    // already guards against re-entering it for an already-active record
    // (see _isActive checks in _recoverIncompleteReveal/_finalizeVisualReveal),
    // so this line can never regenerate an identity for a reveal that is
    // already authoritative.
    final nextRecord = DailyWisdomRecord(
      text: pendingReveal.text,
      revealedAt: confirmedBoundary,
      unlockAt: unlockAt,
      revealId: _generateRevealId(),
    );

    await _saveDailyWisdomRecord(nextRecord);
    _deferClearSpecificPendingBestEffort(pendingReveal.encode());
    return nextRecord;
  }

  String _generateRevealId() => _uuid.v4();

  Future<void> _backfillRevealIdIfNeeded() async {
    final record = await _loadRecordRecoveringCorruption();
    if (record == null || record.revealId != null) {
      // Nothing to backfill: no authoritative record yet, or a prior
      // launch (or this same commit point above) already established one.
      return;
    }

    final backfilled = record.copyWith(revealId: _generateRevealId());

    try {
      await _saveDailyWisdomRecord(backfilled);
    } catch (_) {
      // The previously valid Build 25 record was never touched by a failed
      // write. Existing daily-access behavior remains usable; a later
      // launch will retry this same backfill.
      return;
    }

    final verified = await _loadRecordRecoveringCorruption();
    final matches = verified != null &&
        verified.revealId == backfilled.revealId &&
        verified.text == record.text &&
        verified.revealedAt.millisecondsSinceEpoch ==
            record.revealedAt.millisecondsSinceEpoch &&
        verified.unlockAt.millisecondsSinceEpoch ==
            record.unlockAt.millisecondsSinceEpoch;

    if (!matches) {
      // Read-back verification failed: do not silently accept a possibly
      // corrupted backfill. Best-effort restore of the original record so
      // the previously valid Build 25 state is not left invalid; a later
      // launch will retry the backfill from a clean read.
      try {
        await _saveDailyWisdomRecord(record);
      } catch (_) {
        // Best-effort only; a later launch retries again from whatever
        // state is actually persisted.
      }
    }
  }

  Future<void> _saveDailyWisdomRecord(DailyWisdomRecord record) async {
    await _preferencesAdapter.setString(
      dailyWisdomAccessKey,
      record.encode(),
    );
    _deferRemoveObsoleteAccessStateBestEffort();
  }

  Future<PendingDailyWisdomReveal?> _loadUsablePendingReveal(
    DailyWisdomRecord? record,
  ) async {
    final pending = await _loadPendingDailyWisdomReveal();
    if (pending == null) return null;

    if (record != null && !_pendingBelongsToNextWindow(pending, record)) {
      _deferClearSpecificPendingBestEffort(pending.encode());
      return null;
    }

    return pending;
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

  bool _isActive(DailyWisdomRecord? record, DateTime now) {
    if (record == null) return false;
    final effectiveNow =
        now.isBefore(record.revealedAt) ? record.revealedAt : now;
    return effectiveNow.isBefore(record.unlockAt);
  }

  void _deferClearSpecificPendingBestEffort(String expectedEncodedReveal) {
    _deferCleanup(
      operation: () async {
        final current =
            await _preferencesAdapter.getString(pendingDailyWisdomRevealKey);
        if (current == expectedEncodedReveal) {
          await _clearPendingDailyWisdomReveal();
        }
      },
    );
  }

  void _deferClearSpecificDailyBestEffort(String expectedEncodedRecord) {
    _deferCleanup(
      operation: () async {
        final current =
            await _preferencesAdapter.getString(dailyWisdomAccessKey);
        if (current == expectedEncodedRecord) {
          await _preferencesAdapter.remove(dailyWisdomAccessKey);
        }
      },
    );
  }

  void _deferRemoveObsoleteAccessStateBestEffort() {
    scheduleMicrotask(
      () {
        unawaited(
          _removeObsoleteAccessStateIfPresentBestEffort(),
        );
      },
    );
  }

  void _deferCleanup({
    required Future<void> Function() operation,
  }) {
    scheduleMicrotask(() {
      unawaited(
        _operationCoordinator
            .runExclusive<void>(
          resourceKey: resourceKey,
          operation: operation,
        )
            .catchError((_) {
          // Deferred cleanup is non-authoritative. Access decisions are based on
          // the already-resolved coherent read/mutation result.
        }),
      );
    });
  }

  Future<void> _removeObsoleteAccessStateBestEffort() async {
    for (final key in obsoleteAccessKeys) {
      try {
        final remover = _obsoleteKeyRemover;
        if (remover == null) {
          await _preferencesAdapter.remove(key);
        } else {
          await remover(await _preferencesAdapter.preferences, key);
        }
      } catch (_) {
        // Obsolete access state must never block authoritative access.
      }
    }
  }

  Future<void> _removeObsoleteAccessStateIfPresentBestEffort() async {
    try {
      var hasObsoleteAccessState = false;
      for (final key in obsoleteAccessKeys) {
        if (await _preferencesAdapter.containsKey(key)) {
          hasObsoleteAccessState = true;
          break;
        }
      }

      if (!hasObsoleteAccessState) return;

      await _operationCoordinator.runExclusive<void>(
        resourceKey: resourceKey,
        operation: _removeObsoleteAccessStateBestEffort,
      );
    } catch (_) {
      // Obsolete access state must never block authoritative access.
    }
  }
}
