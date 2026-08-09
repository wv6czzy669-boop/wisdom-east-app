/// Build 26 Phase 4F: wires the already-built, already-tested (Phases
/// 4A-4E-5) CloudKit sync system into the real app runtime -- startup,
/// foreground, iCloud account-change, and bounded-retry triggers, plus the
/// single-flight/coalescing policy that keeps at most one runtime pipeline
/// active at a time.
///
/// **This file contains zero sync domain rules.** Every actual decision
/// (association, conflict resolution, epoch handling, outbox mutation,
/// checkpoint persistence) remains exactly where Phases 4A-4E-5 already put
/// it -- [KeptSyncBootstrapCoordinator], [KeptSyncIntegrationCoordinator],
/// [SyncOrchestrator], and [IncomingKeptSyncCoordinator]. This coordinator
/// only decides *when* to call them and *what to do next* based on their own
/// already-typed, already-safe result values -- never by re-deriving an
/// account fingerprint, a `dataEpoch`, or a conflict winner itself, and never
/// by parsing a raw error string.
///
/// **The runtime pipeline** (see [_runOnce]) is exactly:
///
/// 1. [KeptSyncBootstrapCoordinator.runBootstrap] -- already internally
///    performs the complete, already-audited association decision (including
///    safe auto-authorization for a clean first device, and fail-closed
///    `associationRequired` for every device with existing local history or a
///    mismatched marker). This coordinator never calls
///    `evaluateAssociation`/`authorizeAssociation`/
///    `repairLegacyAssociationMarker` itself -- doing so would duplicate a
///    decision [runBootstrap] already makes correctly.
/// 2. Only if bootstrap reported [BootstrapRunStatus.completed] or
///    [BootstrapRunStatus.alreadyComplete]: read the durable association
///    marker ([SyncPersistenceStore.loadAssociatedAccountFingerprint]) --
///    never re-resolved from a fresh account snapshot, since the marker is
///    exactly what [runBootstrap] itself just confirmed matches the current
///    account -- and call
///    [KeptSyncIntegrationCoordinator.reconcileForAssociatedAccount] with it.
/// 3. [SyncOrchestrator.runSyncPass] -- resolves its own account snapshot,
///    uploads the outbox, fetches incoming changes. Takes no argument from
///    this coordinator.
/// 4. Only if step 3 completed and returned a non-null
///    `pendingIncomingBatch`: [IncomingKeptSyncCoordinator.applyIncomingBatch].
///
/// Every non-continuing status at every step stops the pass immediately --
/// no upload, no reassociation, no marker overwrite, no deletion, no
/// automatic epoch recovery ever happens on any path through this file (see
/// [_classifyBootstrapStopStatus]/[_classifySyncPassStopStatus]/
/// [_classifyIncomingApplyStatus]'s own doc comments for the exact
/// retryable/terminal/wait-for-trigger classification and why).
///
/// **Single-flight.** [requestSync] is the one entry point every trigger
/// (startup, foreground, account-change, retry timer) calls. At most one
/// [_runOnce] pipeline is ever active; a trigger that arrives while one is
/// already running sets a single boolean follow-up flag (never a queue) and
/// is guaranteed exactly one more pass once the active one finishes. This is
/// a *different* lock from `kept_sync_integration_v1`
/// ([PersistenceOperationCoordinator]) -- that lock remains the sole
/// authority serializing actual local-state mutations; this one only
/// prevents two full runtime *pipelines* from running concurrently.
///
/// **Retry.** Bounded exponential backoff (30s, 60s, 120s, 240s, ... capped
/// at 30 minutes, no jitter) scheduled only for genuinely transient
/// failures, through the small injectable [SyncRetryScheduler] seam so tests
/// never need a real `Timer` or a sleep. Reset to zero after any fully
/// [SyncRuntimeOutcome.completed] pass. At most one retry timer ever exists;
/// an iCloud account-change event always cancels it and resets the count
/// before requesting a fresh pass.
///
/// **Lifecycle.** This class does not implement `WidgetsBindingObserver`
/// itself (this file imports nothing from `package:flutter/widgets.dart` --
/// see the layering test) -- `lib/main.dart` owns the actual
/// `AppLifecycleState` subscription and calls [requestSync] only on
/// `resumed`, exactly like it already calls this coordinator on startup.
///
/// **Privacy.** [status] and [CloudKitSyncRuntimeStatus.toLogSafeSummary]
/// expose only a stage/outcome enum name, small integers, and booleans --
/// never an account fingerprint, `dataEpoch`, server token, `systemFields`,
/// `recordName`, `revealId`, `localId`, `intentId`, `mutationId`, wisdom
/// text, Reflection text, or a timestamp.
///
/// **No local-mutation nudge in this phase.** [requestSync] is never called
/// from `SavedReflectionsService`/`KeptRepository`/any Keep/Reflection/Remove
/// call site in this phase -- see `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md`
/// Phase 4F's own scope note. A future fast-follow may wire one; this file's
/// public API already supports it (a fire-and-forget [requestSync] call)
/// without any redesign.
///
/// **Daily access.** This file imports nothing from
/// `lib/repositories/daily_access_repository.dart` or
/// `lib/services/daily_wisdom_access_service.dart`, and never reads or
/// writes `daily_wisdom_access`/`unlockAt` -- the rolling 24-hour ritual
/// remains entirely device-local and untouched by this phase.
library;

import 'dart:async';

import '../sync_integration/incoming_kept_sync_coordinator.dart';
import '../sync_integration/kept_sync_bootstrap_coordinator.dart';
import '../sync_integration/kept_sync_integration_coordinator.dart';
import '../sync_orchestration/sync_orchestrator.dart';
import '../sync_orchestration/sync_pass_result.dart';
import '../sync_persistence/sync_persistence_store.dart';
import '../sync_platform/cloud_kit_account_change_event.dart';
import '../sync_platform/cloud_kit_platform_bridge.dart';

/// Why one runtime pass was requested. Privacy-safe by construction -- an
/// enum, never anything more.
enum SyncRuntimeTrigger {
  /// The very first request after app launch.
  startup,

  /// `AppLifecycleState.resumed`.
  foreground,

  /// [CloudKitPlatformBridge.accountChangeEvents] fired.
  accountChanged,

  /// The bounded-backoff retry timer fired.
  retry,

  /// A trigger arrived while a pass was already active and was coalesced
  /// into the single guaranteed follow-up pass -- see [requestSync].
  coalescedFollowUp,
}

/// The categorical, content-safe outcome of one completed [_runOnce] pass.
enum SyncRuntimeOutcome {
  /// The full pipeline reached the end with nothing left to do (whether or
  /// not there was actually any work this pass) -- resets retry state.
  completed,

  /// A transient failure occurred at some step -- schedules exactly one
  /// bounded-backoff retry.
  retryableFailure,

  /// A failure requires a real state change (an explicit association
  /// decision, a detected corruption, a fail-closed conflict abort, a
  /// detected remote epoch change) before retrying could possibly help --
  /// never automatically retried by a timer. A future foreground/startup/
  /// account-change trigger may still try again; only the *timer* is
  /// withheld.
  terminalFailure,

  /// The account is temporarily not usable (no account signed in,
  /// restricted, or otherwise unavailable) -- not a bug to retry away on a
  /// timer; wait for a foreground/startup/account-change trigger instead.
  waitingForAccountAvailability,
}

/// A privacy-safe, immutable snapshot of this coordinator's current state.
/// See the library doc comment's "Privacy" section for the exact allowed
/// field set.
final class CloudKitSyncRuntimeStatus {
  const CloudKitSyncRuntimeStatus({
    required this.isRunning,
    required this.followUpRequested,
    required this.retryScheduled,
    required this.retryAttempt,
    this.lastOutcome,
  });

  final bool isRunning;
  final bool followUpRequested;
  final bool retryScheduled;

  /// `0` whenever no retryable failure has occurred since the last
  /// successful [SyncRuntimeOutcome.completed] pass (or since this
  /// coordinator was constructed).
  final int retryAttempt;

  /// `null` until the first pass ever finishes.
  final SyncRuntimeOutcome? lastOutcome;

  Map<String, Object?> toLogSafeSummary() => {
        'isRunning': isRunning,
        'followUpRequested': followUpRequested,
        'retryScheduled': retryScheduled,
        'retryAttempt': retryAttempt,
        'lastOutcome': lastOutcome?.name,
      };

  @override
  String toString() => 'CloudKitSyncRuntimeStatus(${toLogSafeSummary()})';
}

/// The smallest possible injectable scheduling seam: production uses a real
/// `Timer`; tests inject a fake that records the requested delay/callback
/// and lets the test fire it deterministically, with no real waiting.
abstract interface class SyncRetryScheduler {
  /// Schedules [callback] to run after [delay]. Must never invoke
  /// [callback] synchronously/immediately, even for `Duration.zero` --
  /// callers rely on this to observe "a retry was scheduled" before it
  /// fires. Returns an opaque handle [cancel] accepts.
  Object schedule(Duration delay, void Function() callback);

  /// Cancels a previously-[schedule]d callback. A no-op if [handle] already
  /// fired or was already canceled.
  void cancel(Object handle);
}

/// Production [SyncRetryScheduler], backed by a real [Timer].
final class TimerSyncRetryScheduler implements SyncRetryScheduler {
  const TimerSyncRetryScheduler();

  @override
  Object schedule(Duration delay, void Function() callback) =>
      Timer(delay, callback);

  @override
  void cancel(Object handle) {
    (handle as Timer).cancel();
  }
}

/// Build 26 Phase 4F: the one production runtime coordinator. See the
/// library doc comment for the full pipeline/single-flight/retry/privacy
/// contract.
final class CloudKitSyncRuntimeCoordinator {
  CloudKitSyncRuntimeCoordinator({
    required KeptSyncBootstrapCoordinator bootstrapCoordinator,
    required KeptSyncIntegrationCoordinator integrationCoordinator,
    required IncomingKeptSyncCoordinator incomingCoordinator,
    required SyncOrchestrator orchestrator,
    required SyncPersistenceStore syncPersistenceStore,
    required CloudKitPlatformBridge bridge,
    SyncRetryScheduler? scheduler,
    Duration Function(int attempt)? backoffForAttempt,
  })  : _bootstrapCoordinator = bootstrapCoordinator,
        _integrationCoordinator = integrationCoordinator,
        _incomingCoordinator = incomingCoordinator,
        _orchestrator = orchestrator,
        _syncPersistenceStore = syncPersistenceStore,
        _scheduler = scheduler ?? const TimerSyncRetryScheduler(),
        _backoffForAttempt = backoffForAttempt ?? defaultBackoffForAttempt {
    _accountChangeSubscription =
        bridge.accountChangeEvents.listen(_onAccountChanged);
  }

  static const Duration _minBackoff = Duration(seconds: 30);
  static const Duration _maxBackoff = Duration(minutes: 30);

  /// The locked-decision bounded exponential backoff: 30s, 60s, 120s, 240s,
  /// ... doubling per consecutive attempt, capped at 30 minutes, no jitter.
  /// [attempt] is 1-based -- the first retryable failure since the last
  /// success/construction is attempt `1`.
  static Duration defaultBackoffForAttempt(int attempt) {
    final normalizedAttempt = attempt < 1 ? 1 : attempt;
    // Cap the shift itself (not just the final duration) so an
    // unreasonably large attempt count can never overflow the
    // multiplication before the cap comparison below runs.
    final shift = normalizedAttempt - 1 > 20 ? 20 : normalizedAttempt - 1;
    final scaled = _minBackoff * (1 << shift);
    return scaled > _maxBackoff ? _maxBackoff : scaled;
  }

  final KeptSyncBootstrapCoordinator _bootstrapCoordinator;
  final KeptSyncIntegrationCoordinator _integrationCoordinator;
  final IncomingKeptSyncCoordinator _incomingCoordinator;
  final SyncOrchestrator _orchestrator;
  final SyncPersistenceStore _syncPersistenceStore;
  final SyncRetryScheduler _scheduler;
  final Duration Function(int attempt) _backoffForAttempt;

  late final StreamSubscription<CloudKitAccountChangeEvent>
      _accountChangeSubscription;

  Future<void>? _activeRun;
  bool _followUpRequested = false;
  Completer<void>? _followUpCompleter;
  Object? _pendingRetryHandle;
  int _retryAttempt = 0;
  SyncRuntimeOutcome? _lastOutcome;
  bool _disposed = false;

  /// A privacy-safe snapshot of this coordinator's current state -- see
  /// [CloudKitSyncRuntimeStatus].
  CloudKitSyncRuntimeStatus get status => CloudKitSyncRuntimeStatus(
        isRunning: _activeRun != null,
        followUpRequested: _followUpRequested,
        retryScheduled: _pendingRetryHandle != null,
        retryAttempt: _retryAttempt,
        lastOutcome: _lastOutcome,
      );

  /// The single entry point every trigger (startup, foreground,
  /// account-change, retry timer) calls. Never blocks on CloudKit -- safe to
  /// call without awaiting the returned [Future] (every current call site
  /// does exactly that; the return value exists only so a test, or a future
  /// nudge caller, can await completion if it chooses to).
  ///
  /// If no pipeline is currently active, starts one immediately (after
  /// canceling any still-pending retry timer, since this fresh attempt
  /// supersedes it) and returns its own completion future. If one is
  /// already active, records a single follow-up request (never more than
  /// one, however many additional calls arrive before the active pass
  /// finishes) and returns a future that completes when that one
  /// guaranteed follow-up pass finishes.
  Future<void> requestSync(SyncRuntimeTrigger trigger) {
    if (_disposed) return Future<void>.value();

    if (_activeRun != null) {
      _followUpRequested = true;
      return (_followUpCompleter ??= Completer<void>()).future;
    }

    return _startRun(trigger);
  }

  Future<void> _startRun(SyncRuntimeTrigger trigger) {
    _cancelPendingRetry();
    final run = _runOnce(trigger);
    _activeRun = run;
    run.whenComplete(() => _onRunComplete());
    return run;
  }

  void _onRunComplete() {
    _activeRun = null;
    if (!_followUpRequested) return;

    _followUpRequested = false;
    final completer = _followUpCompleter;
    _followUpCompleter = null;
    final followUp = _startRun(SyncRuntimeTrigger.coalescedFollowUp);
    if (completer != null) {
      followUp.then(completer.complete, onError: completer.completeError);
    }
  }

  /// Runs exactly the four-step pipeline described in the library doc
  /// comment, once. Never throws -- any unexpected exception from a lower
  /// coordinator (already proven durable/crash-safe by Phase 4E-5) is
  /// classified as [SyncRuntimeOutcome.retryableFailure], the same as any
  /// other transient failure, rather than escaping uncontained.
  Future<void> _runOnce(SyncRuntimeTrigger trigger) async {
    try {
      // Step 1 -- bootstrap. Never reimplements evaluateAssociation/
      // authorizeAssociation/repairLegacyAssociationMarker -- runBootstrap
      // already performs that complete, already-audited decision.
      final bootstrapResult = await _bootstrapCoordinator.runBootstrap();
      if (!_bootstrapReachedComplete(bootstrapResult.status)) {
        _finishPass(_classifyBootstrapStopStatus(bootstrapResult.status));
        return;
      }

      // Step 2 -- local durable reconciliation, using only the durable
      // marker runBootstrap itself just confirmed matches the current
      // account. Never re-derived from a fresh snapshot, and never
      // invented.
      final fingerprint =
          await _syncPersistenceStore.loadAssociatedAccountFingerprint();
      if (fingerprint == null) {
        // A complete/alreadyComplete bootstrap result requires a durable
        // marker to exist. A null read here means durable state shifted
        // out from under this pass through some path outside this
        // coordinator's own pipeline -- fail closed rather than inventing
        // a fingerprint value of its own.
        _finishPass(SyncRuntimeOutcome.terminalFailure);
        return;
      }
      await _integrationCoordinator.reconcileForAssociatedAccount(
        AssociatedSyncAccountContext(accountFingerprint: fingerprint),
      );

      // Step 3 -- transport sync. Takes no argument; resolves its own
      // account snapshot internally.
      final syncResult = await _orchestrator.runSyncPass();
      if (syncResult.status != SyncPassStatus.completed) {
        _finishPass(_classifySyncPassStopStatus(syncResult.status));
        return;
      }

      // Step 4 -- incoming application, only if a batch actually exists.
      final batch = syncResult.pendingIncomingBatch;
      if (batch == null) {
        _finishPass(SyncRuntimeOutcome.completed);
        return;
      }
      final applyResult = await _incomingCoordinator.applyIncomingBatch(batch);
      _finishPass(_classifyIncomingApplyStatus(applyResult.status));
    } catch (_) {
      _finishPass(SyncRuntimeOutcome.retryableFailure);
    }
  }

  bool _bootstrapReachedComplete(BootstrapRunStatus status) =>
      status == BootstrapRunStatus.completed ||
      status == BootstrapRunStatus.alreadyComplete;

  /// Classifies every [BootstrapRunStatus] this pipeline can stop on (every
  /// value except [BootstrapRunStatus.completed]/
  /// [BootstrapRunStatus.alreadyComplete], which never reach here).
  ///
  /// - `associationRequired`/`ambiguousLegacyState`/
  ///   `remoteEpochChangedRecoveryRequired`/`controlRecordInvalid`/
  ///   `corruptedBucketState`/`conflictAborted` -- each one requires either
  ///   an explicit association decision, evidence of corruption, or a
  ///   detected epoch change; retrying the identical operation on a timer
  ///   cannot resolve any of them. `remoteEpochChangedRecoveryRequired` in
  ///   particular must never be auto-retried -- automatic epoch recovery is
  ///   explicitly out of this phase's scope, exactly as it is out of
  ///   Phase 4E-4's.
  /// - `accountUnavailable`/`fingerprintUnresolved` -- about account
  ///   availability, not a bug; the design doc's own account-boundary rule
  ///   says to wait for a foreground/startup/account-change trigger, never
  ///   spin a timer on it.
  /// - `accountChangedDuringFetch`/`controlRecordCreationUnverified`/
  ///   `fetchFailed`/`persistenceFailure` -- each one is documented as
  ///   "nothing was mutated" / "a future retry starts over cleanly", i.e.
  ///   genuinely transient -- safe for the bounded-backoff timer.
  SyncRuntimeOutcome _classifyBootstrapStopStatus(BootstrapRunStatus status) {
    switch (status) {
      case BootstrapRunStatus.completed:
      case BootstrapRunStatus.alreadyComplete:
        // Unreachable -- callers only pass a non-continuing status here.
        return SyncRuntimeOutcome.completed;
      case BootstrapRunStatus.accountUnavailable:
      case BootstrapRunStatus.fingerprintUnresolved:
        return SyncRuntimeOutcome.waitingForAccountAvailability;
      case BootstrapRunStatus.accountChangedDuringFetch:
      case BootstrapRunStatus.controlRecordCreationUnverified:
      case BootstrapRunStatus.fetchFailed:
      case BootstrapRunStatus.persistenceFailure:
        return SyncRuntimeOutcome.retryableFailure;
      case BootstrapRunStatus.associationRequired:
      case BootstrapRunStatus.ambiguousLegacyState:
      case BootstrapRunStatus.controlRecordInvalid:
      case BootstrapRunStatus.corruptedBucketState:
      case BootstrapRunStatus.conflictAborted:
      case BootstrapRunStatus.remoteEpochChangedRecoveryRequired:
        return SyncRuntimeOutcome.terminalFailure;
    }
  }

  /// Classifies every [SyncPassStatus] other than
  /// [SyncPassStatus.completed] (which never reaches here).
  SyncRuntimeOutcome _classifySyncPassStopStatus(SyncPassStatus status) {
    switch (status) {
      case SyncPassStatus.completed:
        // Unreachable -- callers only pass a non-completed status here.
        return SyncRuntimeOutcome.completed;
      case SyncPassStatus.noAccount:
      case SyncPassStatus.restricted:
      case SyncPassStatus.unavailable:
        return SyncRuntimeOutcome.waitingForAccountAvailability;
      case SyncPassStatus.retryableFailure:
      case SyncPassStatus.persistenceFailure:
      case SyncPassStatus.tokenExpiredNeedsRefetch:
        return SyncRuntimeOutcome.retryableFailure;
      case SyncPassStatus.permanentFailure:
        return SyncRuntimeOutcome.terminalFailure;
    }
  }

  /// Classifies the terminal [IncomingApplyResult.status] of the one
  /// [IncomingKeptSyncCoordinator.applyIncomingBatch] call this pipeline
  /// ever makes. Only [IncomingApplyStatus.persistenceFailure]/
  /// [IncomingApplyStatus.checkpointFailed] are genuinely transient
  /// (already-durable local state, only the final persistence step failed).
  /// Every other non-applied status reflects a batch/bucket-shape mismatch
  /// this exact batch cannot recover from by blind immediate retry -- a
  /// fresh natural trigger (foreground/startup/account-change) will
  /// naturally re-fetch a consistent batch later; this pipeline does not
  /// spin a timer on a batch it has already rejected.
  SyncRuntimeOutcome _classifyIncomingApplyStatus(IncomingApplyStatus status) {
    switch (status) {
      case IncomingApplyStatus.applied:
      case IncomingApplyStatus.alreadyApplied:
        return SyncRuntimeOutcome.completed;
      case IncomingApplyStatus.persistenceFailure:
      case IncomingApplyStatus.checkpointFailed:
        return SyncRuntimeOutcome.retryableFailure;
      case IncomingApplyStatus.bucketMissing:
      case IncomingApplyStatus.bootstrapNotComplete:
      case IncomingApplyStatus.dataEpochMismatch:
      case IncomingApplyStatus.staleBatch:
      case IncomingApplyStatus.missingPendingToken:
      case IncomingApplyStatus.controlRecordsRejected:
      case IncomingApplyStatus.duplicateRecordName:
      case IncomingApplyStatus.duplicateRevealId:
      case IncomingApplyStatus.systemFieldsMismatch:
      case IncomingApplyStatus.conflictAborted:
        return SyncRuntimeOutcome.terminalFailure;
    }
  }

  void _finishPass(SyncRuntimeOutcome outcome) {
    _lastOutcome = outcome;
    switch (outcome) {
      case SyncRuntimeOutcome.completed:
        _resetRetry();
      case SyncRuntimeOutcome.retryableFailure:
        _scheduleRetry();
      case SyncRuntimeOutcome.terminalFailure:
      case SyncRuntimeOutcome.waitingForAccountAvailability:
        // No automatic timer. Any stale pending retry from a prior pass no
        // longer applies -- this pass's own outcome is now authoritative.
        // The retry *attempt count* is deliberately left untouched here
        // (only a fully `completed` pass resets it, and only a
        // `retryableFailure` pass advances it) so an unrelated terminal/
        // waiting outcome can never silently reset backoff progress.
        _cancelPendingRetry();
    }
  }

  void _scheduleRetry() {
    _cancelPendingRetry();
    _retryAttempt += 1;
    final delay = _backoffForAttempt(_retryAttempt);
    _pendingRetryHandle = _scheduler.schedule(delay, () {
      _pendingRetryHandle = null;
      unawaited(requestSync(SyncRuntimeTrigger.retry));
    });
  }

  void _cancelPendingRetry() {
    final handle = _pendingRetryHandle;
    if (handle == null) return;
    _pendingRetryHandle = null;
    _scheduler.cancel(handle);
  }

  void _resetRetry() {
    _cancelPendingRetry();
    _retryAttempt = 0;
  }

  /// Content-free by construction ([CloudKitAccountChangeEvent] carries only
  /// an enum, never an account identity) -- this coordinator never compares
  /// or exposes an account id anywhere. Existing bootstrap association
  /// rules (step 1 of [_runOnce]) remain the sole authority on whether the
  /// now-current account differs from the associated marker; a mismatch
  /// simply surfaces as [BootstrapRunStatus.associationRequired], which
  /// [_classifyBootstrapStopStatus] already stops on safely, with no
  /// automatic reassociation.
  void _onAccountChanged(CloudKitAccountChangeEvent event) {
    if (_disposed) return;
    _cancelPendingRetry();
    _retryAttempt = 0;
    unawaited(requestSync(SyncRuntimeTrigger.accountChanged));
  }

  /// Releases the [CloudKitPlatformBridge.accountChangeEvents] subscription
  /// and cancels any pending retry timer. Safe to call once, at most; no
  /// current production call site ever calls this (this coordinator is
  /// constructed once, for the app's lifetime), but it exists for
  /// deterministic test teardown and to give a future phase a safe seam if
  /// one is ever needed.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _cancelPendingRetry();
    await _accountChangeSubscription.cancel();
  }
}
