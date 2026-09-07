import 'dart:async';

import '../models/daily_access_snapshot.dart';
import '../models/daily_wisdom_record.dart';
import '../models/daily_wisdom_selection.dart';
import '../models/pending_daily_wisdom_reveal.dart';
import '../repositories/daily_access_repository.dart' hide WisdomSelector;
import 'daily_ritual_authority.dart';
import 'keeper_ritual_widget_service.dart';

typedef WisdomSelector = FutureOr<String> Function();
typedef WisdomSelectionSelector = FutureOr<DailyWisdomSelection> Function();
typedef WisdomClock = DateTime Function();

class DailyWisdomAccess {
  const DailyWisdomAccess({
    required this.text,
    required this.isNew,
    this.unlockAt,
    this.revealId,
    this.revealedAt,
    this.wisdomId,
  });

  final String text;
  final bool isNew;
  final DateTime? unlockAt;

  /// The authoritative reveal's identity, copied verbatim from the
  /// [DailyWisdomRecord] this access came from — never minted here. Every
  /// newly committed Build 26 reveal carries a non-null value; this remains
  /// nullable only for safe compatibility with an old authoritative record
  /// whose best-effort `revealId` backfill has not (yet) succeeded.
  final String? revealId;

  /// When the authoritative reveal actually happened, copied verbatim from
  /// the same [DailyWisdomRecord]. Nullable for the same compatibility
  /// reason as [revealId].
  final DateTime? revealedAt;
  final String? wisdomId;
}

class DailyWisdomStatus {
  const DailyWisdomStatus({
    required this.isReady,
    this.unlockAt,
    this.remaining,
    this.lockedText,
    this.revealId,
    this.revealedAt,
    this.wisdomId,
  });

  final bool isReady;
  final DateTime? unlockAt;
  final Duration? remaining;
  final String? lockedText;

  /// The authoritative reveal's identity, populated only when this status
  /// reflects a real, currently-locked [DailyWisdomRecord] — copied
  /// verbatim, never fabricated. `null` for a ready status, and `null` for
  /// a locked status whose record predates backfill.
  final String? revealId;

  /// When the authoritative reveal actually happened, populated under the
  /// same rule as [revealId].
  final DateTime? revealedAt;
  final String? wisdomId;
}

class DailyWisdomPreparedReveal {
  const DailyWisdomPreparedReveal({
    required this.text,
    required this.hasAuthoritativeRecord,
    this.unlockAt,
    this.confirmedRevealBoundary,
    this.phase = PendingDailyWisdomRevealPhase.prepared,
    this.revealId,
    this.revealedAt,
    this.wisdomId,
  });

  final String text;
  final bool hasAuthoritativeRecord;
  final DateTime? unlockAt;
  final DateTime? confirmedRevealBoundary;
  final PendingDailyWisdomRevealPhase phase;

  /// Passed through verbatim from [PreparedDailyAccess.revealId] — never
  /// generated here. `null` for a genuinely fresh pre-commit prepared
  /// reveal.
  final String? revealId;

  /// Passed through verbatim from [PreparedDailyAccess.revealedAt].
  final DateTime? revealedAt;
  final String? wisdomId;
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
    this.authority,
  })  : _repository = repository,
        _clock = clock ?? DateTime.now;

  final DailyAccessRepository _repository;
  final WisdomClock _clock;
  final Duration lockDuration;
  final Duration statusTimeout;
  final DailyRitualAuthority? authority;
  Future<void>? _accountRefresh;

  bool get requiresAccountAuthorization => authority != null;

  /// Called before any newly prepared text becomes visible. A failed or
  /// uncertain request never falls back to a locally generated daily right.
  Future<DailyWisdomAccess> authorizePreparedReveal(
      DailyWisdomPreparedReveal prepared) async {
    final accountAuthority = authority;
    final wisdomId = prepared.wisdomId;
    if (accountAuthority == null || wisdomId == null) {
      throw const DailyRitualAuthorityException(
          DailyRitualAuthorityFailure.unavailable);
    }
    final legacy = await _repository.loadDailyWisdomRecord();
    final authorized =
        await accountAuthority.claim(wisdomId: wisdomId, legacyRecord: legacy);
    final record = await _repository.adoptAuthorizedRecord(authorized.record);
    return _authorizedAccess(record,
        isNew: authorized.created &&
            record.revealId == authorized.record.revealId);
  }

  /// Import a shared app/widget cache first, then refresh it opportunistically.
  /// The refresh does not acquire a daily right and cannot block offline reading.
  Future<void> reconcileAccountAuthority({bool refresh = true}) async {
    final accountAuthority = authority;
    if (accountAuthority == null) return;
    try {
      final cached = await accountAuthority.readCached();
      if (cached != null) {
        await _repository.adoptAuthorizedRecord(cached.record);
      }
    } catch (_) {}
    if (refresh && _accountRefresh == null) {
      _accountRefresh = _refreshAccount(accountAuthority).whenComplete(() {
        _accountRefresh = null;
      });
      unawaited(_accountRefresh);
    }
  }

  Future<void> _refreshAccount(DailyRitualAuthority accountAuthority) async {
    try {
      final legacy = await _repository.loadDailyWisdomRecord();
      final refreshed = await accountAuthority.refresh(legacyRecord: legacy);
      if (refreshed != null) {
        await _repository.adoptAuthorizedRecord(refreshed.record);
      }
    } catch (_) {
      // Previously opened writing remains readable when the account is offline.
    }
  }

  /// Only a pre-upgrade widget document has an already-visible occurrence
  /// without an ID. New widgets always carry the server ID and use the cache.
  Future<void> restoreLegacyWidgetReveal(
      KeeperRitualWidgetReveal reveal) async {
    if (!reveal.needsAppCommit || reveal.revealId != null) {
      throw ArgumentError('Only an already-opened legacy widget is eligible.');
    }
    final pending = await _repository.loadPendingDailyWisdomReveal();
    if (pending?.text != reveal.canonicalText ||
        pending?.wisdomId != reveal.wisdomId ||
        pending!.preparedAt.isAfter(reveal.revealedAt)) {
      return;
    }
    await _repository.finalizeVisualReveal(
      text: reveal.canonicalText,
      revealBoundary: reveal.revealedAt,
      now: reveal.revealedAt,
    );
  }

  /// Reading this occurrence never extends its interval or consumes a right.
  Future<DailyWisdomAccess?> lastOpenedWisdom() async {
    final record = await _repository.loadDailyWisdomRecord();
    if (record == null || record.text == corruptRecordRecoveryText) return null;
    return _authorizedAccess(record, isNew: false);
  }

  DailyWisdomAccess _authorizedAccess(DailyWisdomRecord record,
          {required bool isNew}) =>
      DailyWisdomAccess(
          text: record.text,
          isNew: isNew,
          unlockAt: record.unlockAt,
          revealId: record.revealId,
          revealedAt: record.revealedAt,
          wisdomId: record.wisdomId);

  static const Duration defaultStatusTimeout = Duration(seconds: 4);
  static const String corruptRecordRecoveryText = 'Silence is still available.';

  Future<DailyWisdomAccess> reveal({
    required WisdomSelector selectWisdom,
    WisdomSelectionSelector? selectWisdomWithIdentity,
  }) async {
    final prepared = await prepareReveal(
      selectWisdom: selectWisdom,
      selectWisdomWithIdentity: selectWisdomWithIdentity,
    );
    if (prepared.hasAuthoritativeRecord) {
      return DailyWisdomAccess(
        text: prepared.text,
        isNew: false,
        unlockAt: prepared.unlockAt,
        revealId: prepared.revealId,
        revealedAt: prepared.revealedAt,
        wisdomId: prepared.wisdomId,
      );
    }

    return finalizeVisualReveal(
      text: prepared.text,
      revealBoundary: prepared.confirmedRevealBoundary ?? _clock(),
    );
  }

  Future<DailyWisdomPreparedReveal> prepareReveal({
    required WisdomSelector selectWisdom,
    WisdomSelectionSelector? selectWisdomWithIdentity,
  }) async {
    final now = _clock();
    final prepared = await _repository.prepareReveal(
      selectWisdom: selectWisdom,
      selectWisdomWithIdentity: selectWisdomWithIdentity,
      preparedAt: now,
      now: now,
    );
    return DailyWisdomPreparedReveal(
      text: prepared.text,
      hasAuthoritativeRecord: prepared.hasAuthoritativeRecord,
      unlockAt: prepared.unlockAt,
      confirmedRevealBoundary: prepared.confirmedRevealBoundary,
      phase: prepared.phase,
      revealId: prepared.revealId,
      revealedAt: prepared.revealedAt,
      wisdomId: prepared.wisdomId,
    );
  }

  /// Delegates to [DailyAccessRepository.backfillRevealIdIfNeeded]. Safe and
  /// idempotent to call on every launch; callers should still guard the
  /// call with their own error handling since it shares the underlying
  /// corruption-recovery path, which is not guaranteed exception-free.
  Future<void> backfillRevealIdIfNeeded() {
    return _repository.backfillRevealIdIfNeeded();
  }

  /// Delegates to [DailyAccessRepository.reconcileRevealIdForOccurrence] —
  /// see that method's doc comment for the full behavior contract. Thin
  /// pass-through only; never mutates Kept storage, and the caller is
  /// responsible for supplying [resolvedLegacyRevealId] from a prior,
  /// separate, read-only Kept-side resolution.
  ///
  /// Build 26 Phase 3D-E (safety-gap correction, round 4): returns the
  /// [RevealIdReconciliationOutcome] so tests and diagnostics can prove
  /// exactly which case occurred. `HomeScreen`'s call site does not need to
  /// change: it may continue to simply `await` this without inspecting the
  /// result, preserving today's fail-closed, retry-next-launch behavior.
  Future<RevealIdReconciliationOutcome> reconcileRevealIdForOccurrence({
    required String expectedText,
    required DateTime expectedRevealedAt,
    required DateTime expectedUnlockAt,
    required String? resolvedLegacyRevealId,
  }) {
    return _repository.reconcileRevealIdForOccurrence(
      expectedText: expectedText,
      expectedRevealedAt: expectedRevealedAt,
      expectedUnlockAt: expectedUnlockAt,
      resolvedLegacyRevealId: resolvedLegacyRevealId,
    );
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
      revealId: record.revealId,
      revealedAt: record.revealedAt,
      wisdomId: record.wisdomId,
    );
  }

  Future<DailyWisdomAccess> finalizeVisualReveal({
    required String text,
    required DateTime revealBoundary,
  }) async {
    if (requiresAccountAuthorization) {
      final pending = await _repository.loadPendingDailyWisdomReveal();
      final current = await _repository.loadDailyWisdomRecord();
      final wisdomId =
          pending?.text == text ? pending?.wisdomId : current?.wisdomId;
      return authorizePreparedReveal(DailyWisdomPreparedReveal(
          text: text, wisdomId: wisdomId, hasAuthoritativeRecord: false));
    }
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
      revealId: record.revealId,
      revealedAt: record.revealedAt,
      wisdomId: record.wisdomId,
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
          revealId: record.revealId,
          revealedAt: record.revealedAt,
          wisdomId: record.wisdomId,
        );
      }

      return DailyWisdomStatus(
        isReady: false,
        unlockAt: record.unlockAt,
        remaining: record.unlockAt.difference(now),
        lockedText: record.text,
        revealId: record.revealId,
        revealedAt: record.revealedAt,
        wisdomId: record.wisdomId,
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
