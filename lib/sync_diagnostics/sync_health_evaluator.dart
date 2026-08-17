/// Build 26: Sync Diagnostics / Safe Recovery core.
///
/// **Product framing (read this first).** "Sync Diagnostics" in EAST is NOT
/// a technical diagnostics screen, a sync log, a CloudKit record dump, or
/// account-identifier display -- it is a background core that answers one
/// question: "is EAST private iCloud sync healthy, pending, unavailable,
/// recovering, or does it genuinely require attention right now?" Nothing in
/// this file is wired to any Settings screen, debug UI, or analytics event
/// in this phase -- see `lib/sync_diagnostics/sync_health_snapshot.dart`'s
/// own doc comment for the exact content-free shape every answer takes.
///
/// **This file invents no new sync state, no new persisted field, and no
/// new sync rule.** [SyncHealthEvaluator.evaluate] is a pure composition
/// over four already-canonical, already-tested sources of truth, each owned
/// entirely elsewhere:
///
///  1. [SyncPersistenceStore.loadAssociatedAccountFingerprint] -- whether
///     this device has ever completed the explicit "Enable iCloud Sync?"
///     association (`lib/controllers/sync_association_controller.dart`'s own
///     `enabled`/`notEnabled` distinction, reused here rather than
///     redefined).
///  2. [SyncPersistenceStore.loadPendingDeletionTransaction] and
///     [SyncPersistenceStore.loadAccountState] -- the durable "Remove from
///     iCloud" transaction stage and the associated account's
///     [AccountBootstrapState]/outbox, exactly as `lib/sync_deletion/` and
///     `lib/sync_integration/kept_sync_bootstrap_coordinator.dart` already
///     define and drive them.
///  3. [CloudKitPlatformBridge.getAccountSnapshot] -- the live CloudKit
///     account-availability read every other sync layer
///     (`SyncOrchestrator`, `CloudKitRemoteDeletionRunner`) already performs
///     the exact same way, for the exact same purpose.
///  4. [CloudKitSyncRuntimeCoordinator.status] -- the live, in-memory
///     "is a pass running / is a retry scheduled / what did the most recent
///     pass conclude" signal only the runtime coordinator itself can answer,
///     since none of that is durably persisted anywhere (a retryable
///     transport failure deliberately leaves no durable trace -- see
///     `SyncPassResult.retryableFailure`'s own doc comment).
///
/// **Observational only -- computing health is itself always safe.** Every
/// read this class performs is already documented, elsewhere, as read-only:
/// [SyncPersistenceStore]'s load methods never mutate; [CloudKitPlatformBridge
/// .getAccountSnapshot] never mutates (`SyncOrchestrator`/
/// `CloudKitRemoteDeletionRunner` both already call it freely, every pass,
/// for exactly this reason); and [CloudKitSyncRuntimeCoordinator.status] is a
/// plain getter over already-in-memory fields. [evaluate] therefore never
/// deletes anything, uploads anything, modifies a CloudKit record, clears a
/// tombstone, advances a server token, alters a `dataEpoch`, detaches an
/// account association, or discards pending work -- calling it as often as a
/// caller likes is always safe. Recovery (a distinct, explicit operation) is
/// `lib/sync_diagnostics/sync_recovery_coordinator.dart`'s job, never this
/// file's.
///
/// **Deterministic precedence -- the exact rule this file exists to get
/// right.** [evaluate] never reports [SyncHealthState.healthy] merely
/// because the CloudKit account is available; it resolves to exactly one
/// [SyncHealthState] via a fixed, most-urgent-first precedence:
///
///  1. The pending-deletion-transaction read itself throws (a corrupted
///     durable record, mirroring `CloudKitRemoteDeletionRunner.run`'s own
///     fail-closed first check) -- always [SyncHealthState.recoveryRequired],
///     before any other read is even attempted.
///  2. A "Remove from iCloud" deletion transaction is currently pending --
///     see [_evaluateDeletionInProgress]. Dominates every other signal below,
///     mirroring `CloudKitSyncRuntimeCoordinator._runOnce`'s own unconditional
///     "the deletion runner goes first, every trigger" rule -- normal sync
///     and deletion recovery never race, and this evaluator never reports
///     [SyncHealthState.healthy] while a deletion transaction still exists.
///  3. No durable association marker exists -- [SyncHealthState.disabled].
///  4. Otherwise, a durable baseline is derived from account
///     availability/identity, [AccountBootstrapState], and outbox contents
///     (see [_deriveBaselineForAssociatedAccount]), then the live runtime
///     coordinator status is applied as a strictly-worsening overlay (see
///     [_applyRuntimeOverlay]) -- a live signal can only ever make the
///     reported state *more* cautious than the durable baseline alone would
///     say, never less. This is the deliberate, safety-first bias: this
///     evaluator would rather report a transient false [SyncHealthState
///     .recoveryRequired]/[SyncHealthState.pending] than ever report
///     [SyncHealthState.healthy] while meaningful work might still remain
///     (see the phase's own "two dangerous outcomes" framing -- reporting
///     healthy too early is the one this evaluator refuses to risk).
///
/// **Never touches the rolling 24-hour daily-ritual-access domain.** This
/// file imports nothing from `lib/repositories/daily_access_repository.dart`
/// or `lib/services/daily_wisdom_access_service.dart` -- see
/// `sync_health_snapshot.dart`'s own doc comment for the same guarantee
/// restated on the data side.
library;

import '../sync_persistence/account_sync_state.dart';
import '../sync_persistence/pending_deletion_transaction.dart';
import '../sync_persistence/persisted_outbox_mutation.dart';
import '../sync_persistence/sync_persistence_store.dart';
import '../sync_platform/cloud_kit_account_snapshot.dart';
import '../sync_platform/cloud_kit_platform_bridge.dart';
import '../sync_platform/cloud_kit_platform_error.dart';
import '../sync_runtime/cloud_kit_sync_runtime_coordinator.dart';
import 'sync_health_snapshot.dart';

/// Relative urgency of each [SyncHealthState], used only internally by
/// [SyncHealthEvaluator._applyRuntimeOverlay] to decide whether a live
/// runtime signal should ever replace a durable-state baseline -- always
/// toward a *more* cautious report, never a less cautious one. Not exposed
/// outside this file; callers only ever see the resulting [SyncHealthState].
int _severity(SyncHealthState state) {
  switch (state) {
    case SyncHealthState.healthy:
      return 0;
    case SyncHealthState.pending:
      return 1;
    case SyncHealthState.temporaryFailure:
      return 2;
    case SyncHealthState.iCloudUnavailable:
      return 3;
    case SyncHealthState.recovering:
      return 4;
    case SyncHealthState.recoveryRequired:
      return 5;
    case SyncHealthState.disabled:
      // Never compared against another state -- [disabled] is always
      // decided on its own, before any severity-based overlay runs (see the
      // library doc comment's precedence step 3).
      return -1;
  }
}

/// Computes exactly one authoritative [SyncHealthSnapshot] per [evaluate]
/// call. See the library doc comment for the full source/precedence
/// contract. Stateless and side-effect-free: every dependency is an
/// already-existing, already-tested collaborator injected by the caller --
/// this class constructs none of them itself and persists nothing of its
/// own.
final class SyncHealthEvaluator {
  const SyncHealthEvaluator({
    required SyncPersistenceStore syncPersistenceStore,
    required CloudKitPlatformBridge bridge,
    required CloudKitSyncRuntimeStatus Function() readRuntimeStatus,
  })  : _store = syncPersistenceStore,
        _bridge = bridge,
        _readRuntimeStatus = readRuntimeStatus;

  final SyncPersistenceStore _store;
  final CloudKitPlatformBridge _bridge;

  /// A plain, injectable read of [CloudKitSyncRuntimeCoordinator.status] --
  /// never the coordinator itself. `CloudKitSyncRuntimeCoordinator` is a
  /// `final class` (deliberately unextendable/unimplementable outside its
  /// own library, per `lib/sync_runtime/`'s own design), so this narrow
  /// function seam is what lets this evaluator be exercised against a fully
  /// controlled, synthetic [CloudKitSyncRuntimeStatus] in tests -- production
  /// wiring (`lib/services/app_services.dart`) simply passes `() =>
  /// cloudKitSyncRuntimeCoordinator.status`, reading the exact same live
  /// object every other production caller already reads.
  final CloudKitSyncRuntimeStatus Function() _readRuntimeStatus;

  /// Computes the current [SyncHealthSnapshot]. Never throws: every
  /// underlying read this method performs is already documented as either
  /// safe-to-fail-closed (a corrupted durable record) or itself
  /// exception-safe: a [CloudKitPlatformException] from [CloudKitPlatformBridge
  /// .getAccountSnapshot] is caught and treated as
  /// [CloudKitAccountAvailability.unknown], exactly how `SyncOrchestrator`'s
  /// own account-gate step already treats an unrecognized/undetermined
  /// availability value -- never coerced to [CloudKitAccountAvailability
  /// .available].
  Future<SyncHealthSnapshot> evaluate() async {
    final runtimeStatus = _readRuntimeStatus();

    // Step 1/2 of the library doc comment's precedence: the deletion
    // transaction read is attempted strictly first, and a decode/storage
    // failure there is always terminal for this evaluation -- mirrors
    // `CloudKitRemoteDeletionRunner.run`'s own first check exactly.
    PendingDeletionTransaction? deletionTransaction;
    bool deletionStateCorrupted = false;
    try {
      deletionTransaction = await _store.loadPendingDeletionTransaction();
    } catch (_) {
      deletionStateCorrupted = true;
    }

    final accountSnapshot = await _readAccountSnapshot();
    final accountUsable = accountSnapshot.availability ==
            CloudKitAccountAvailability.available &&
        accountSnapshot.isPrivateDatabaseUsable &&
        accountSnapshot.fingerprintResolved;

    if (deletionStateCorrupted) {
      return SyncHealthSnapshot(
        state: SyncHealthState.recoveryRequired,
        syncEnabled: false,
        accountAvailability: accountSnapshot.availability,
        outboxPendingCount: 0,
        hasUnresolvedOutboxEntries: false,
        deletionRecoveryPending: false,
        runtimeStatus: runtimeStatus,
      );
    }

    if (deletionTransaction != null) {
      final state = _evaluateDeletionInProgress(
        accountUsable: accountUsable,
        runtimeStatus: runtimeStatus,
      );
      return SyncHealthSnapshot(
        state: state,
        // A deletion transaction is, by definition, only ever created for an
        // account that was durably associated -- see
        // `SyncPersistenceStore.beginDeletionTransaction`'s own doc comment.
        // Reported `true` here regardless of whether the association marker
        // itself has already been cleared mid-finalize (see
        // `LocalDeletionFinalizer`'s own crash-resume section) -- from this
        // evaluator's perspective sync was, and is still being, actively
        // managed for this device.
        syncEnabled: true,
        accountAvailability: accountSnapshot.availability,
        outboxPendingCount: 0,
        hasUnresolvedOutboxEntries: false,
        deletionRecoveryPending: true,
        deletionRecoveryStage: deletionTransaction.stage,
        runtimeStatus: runtimeStatus,
      );
    }

    final fingerprint = await _store.loadAssociatedAccountFingerprint();
    if (fingerprint == null) {
      return SyncHealthSnapshot(
        state: SyncHealthState.disabled,
        syncEnabled: false,
        accountAvailability: accountSnapshot.availability,
        outboxPendingCount: 0,
        hasUnresolvedOutboxEntries: false,
        deletionRecoveryPending: false,
        runtimeStatus: runtimeStatus,
      );
    }

    AccountSyncState? bucket;
    var bucketReadFailed = false;
    try {
      bucket = await _store.loadAccountState(fingerprint);
    } catch (_) {
      bucketReadFailed = true;
    }

    final outboxPendingCount = bucket?.outbox.length ?? 0;
    final hasUnresolvedOutboxEntries = bucket?.outbox.any(
          (mutation) =>
              mutation.status == PersistedOutboxMutationStatus.failed ||
              mutation.status == PersistedOutboxMutationStatus.conflicted,
        ) ??
        false;

    final baseline = _deriveBaselineForAssociatedAccount(
      accountUsable: accountUsable,
      accountFingerprintMatches: accountUsable &&
          accountSnapshot.accountFingerprint == fingerprint,
      bucketReadFailed: bucketReadFailed,
      bucket: bucket,
      hasUnresolvedOutboxEntries: hasUnresolvedOutboxEntries,
    );
    final state = _applyRuntimeOverlay(baseline, runtimeStatus);

    return SyncHealthSnapshot(
      state: state,
      syncEnabled: true,
      accountAvailability: accountSnapshot.availability,
      outboxPendingCount: outboxPendingCount,
      hasUnresolvedOutboxEntries: hasUnresolvedOutboxEntries,
      deletionRecoveryPending: false,
      runtimeStatus: runtimeStatus,
    );
  }

  Future<CloudKitAccountSnapshot> _readAccountSnapshot() async {
    try {
      return await _bridge.getAccountSnapshot();
    } on CloudKitPlatformException {
      return const CloudKitAccountSnapshot(
        availability: CloudKitAccountAvailability.unknown,
        isPrivateDatabaseUsable: false,
        accountFingerprint: null,
        fingerprintResolved: false,
        bridgeVersion: 0,
      );
    }
  }

  /// Precedence step 2: a "Remove from iCloud" transaction is pending.
  /// Normal sync is never evaluated at all on this path -- mirrors
  /// `CloudKitSyncRuntimeCoordinator._runOnce`'s own unconditional
  /// deletion-first ordering exactly.
  SyncHealthState _evaluateDeletionInProgress({
    required bool accountUsable,
    required CloudKitSyncRuntimeStatus runtimeStatus,
  }) {
    if (!accountUsable) {
      // Mirrors `RemoteDeletionRunOutcome.waitingForAccount` -- the
      // transaction is left exactly as it is; local data is never touched.
      return SyncHealthState.iCloudUnavailable;
    }
    // The most recent completed pass's own outcome is the only signal that
    // can distinguish "actively, safely resuming" from "stuck on a
    // real-state-change requirement" -- neither is durably recorded on the
    // transaction itself (its `stage` alone cannot tell them apart; a
    // `deletionStateCorrupted`/`terminalFailure` outcome from either
    // `CloudKitRemoteDeletionRunner` or `LocalDeletionFinalizer`'s own
    // `accountMismatch` case never advances the durable stage at all).
    if (runtimeStatus.lastOutcome == SyncRuntimeOutcome.deletionStateCorrupted ||
        runtimeStatus.lastOutcome == SyncRuntimeOutcome.terminalFailure) {
      return SyncHealthState.recoveryRequired;
    }
    return SyncHealthState.recovering;
  }

  /// Precedence step 4's durable baseline, for an account that *is*
  /// associated (a non-null marker already confirmed by the caller). Never
  /// consults [CloudKitSyncRuntimeCoordinator.status] -- that is
  /// [_applyRuntimeOverlay]'s job, applied strictly afterward.
  SyncHealthState _deriveBaselineForAssociatedAccount({
    required bool accountUsable,
    required bool accountFingerprintMatches,
    required bool bucketReadFailed,
    required AccountSyncState? bucket,
    required bool hasUnresolvedOutboxEntries,
  }) {
    if (!accountUsable) {
      return SyncHealthState.iCloudUnavailable;
    }
    if (!accountFingerprintMatches) {
      // The currently-resolved CloudKit account no longer matches this
      // device's durable association -- mirrors
      // `AssociationEvaluationStatus.associationRequired`'s own "a durable
      // marker that names a different fingerprint than the one currently
      // resolved" case. Never auto-resolved by this evaluator or by any
      // recovery this phase performs; it requires the same explicit
      // "Enable iCloud Sync?" re-confirmation Settings already owns.
      return SyncHealthState.recoveryRequired;
    }
    if (bucketReadFailed) {
      // Mirrors `BootstrapRunStatus.corruptedBucketState`'s own
      // classification -- externally-corrupted or hand-edited persisted
      // state, never a blind-retry-safe condition.
      return SyncHealthState.recoveryRequired;
    }
    if (bucket == null) {
      // Associated, account usable, but bootstrap has not yet even created
      // this account's local sync bucket -- ordinary startup-shaped work,
      // safe to complete through the normal orchestrator on the next
      // trigger.
      return SyncHealthState.pending;
    }
    if (bucket.bootstrapState == AccountBootstrapState.associationRequired) {
      return SyncHealthState.recoveryRequired;
    }
    if (bucket.bootstrapState != AccountBootstrapState.complete) {
      return SyncHealthState.pending;
    }
    if (hasUnresolvedOutboxEntries) {
      // At least one mutation already failed permanently or conflicted with
      // the server -- a blind retry cannot resolve either on its own (see
      // `PersistedOutboxMutationStatus.failed`/`.conflicted`'s own doc
      // comments); this requires the same conflict-resolution/explicit-retry
      // path a future orchestrator already owns, never a destructive rewrite
      // here.
      return SyncHealthState.recoveryRequired;
    }
    if (bucket.outbox.isNotEmpty) {
      return SyncHealthState.pending;
    }
    return SyncHealthState.healthy;
  }

  /// Precedence step 4's overlay: the live runtime coordinator status can
  /// only ever move the reported state to a *more* cautious one than the
  /// durable baseline alone would say -- see the library doc comment's
  /// "deliberate, safety-first bias" section. Never reads durable state
  /// itself.
  SyncHealthState _applyRuntimeOverlay(
    SyncHealthState baseline,
    CloudKitSyncRuntimeStatus runtimeStatus,
  ) {
    var candidate = baseline;
    void considerAtLeast(SyncHealthState state) {
      if (_severity(state) > _severity(candidate)) candidate = state;
    }

    if (runtimeStatus.isRunning) {
      considerAtLeast(SyncHealthState.pending);
    }
    if (runtimeStatus.retryScheduled) {
      considerAtLeast(SyncHealthState.temporaryFailure);
    }
    if (runtimeStatus.lastOutcome == SyncRuntimeOutcome.terminalFailure) {
      considerAtLeast(SyncHealthState.recoveryRequired);
    }
    return candidate;
  }
}
