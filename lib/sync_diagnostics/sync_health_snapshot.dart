/// Build 26: Sync Diagnostics / Safe Recovery core -- the one authoritative,
/// content-free snapshot of "what is the actual state of EAST private
/// CloudKit sync right now."
///
/// **Not a debug screen's data model.** Nothing in this file is ever shown
/// to the user directly (see `lib/sync_diagnostics/sync_health_evaluator
/// .dart`'s own library doc comment for the full product framing). Every
/// field here is either a small categorical enum, a boolean, or a plain
/// count -- never wisdom text, Reflection text, a CloudKit account
/// identifier, a `dataEpoch`, a server token, a record name, or a
/// filesystem path. [SyncHealthSnapshot.toLogSafeSummary]/[toString] expose
/// only that same safe shape.
///
/// **Never derived from the rolling 24-hour daily-ritual-access domain.**
/// This file imports nothing from `lib/repositories/daily_access_repository
/// .dart` or `lib/services/daily_wisdom_access_service.dart`, and computing
/// or reading a [SyncHealthSnapshot] never touches `daily_wisdom_access`/
/// `unlockAt` state -- the rolling 24-hour ritual remains entirely
/// device-local, exactly as every other CloudKit-sync layer in this
/// codebase already guarantees.
library;

import '../sync_persistence/pending_deletion_transaction.dart'
    show DeletionTransactionStage;
import '../sync_platform/cloud_kit_account_snapshot.dart'
    show CloudKitAccountAvailability;
import '../sync_runtime/cloud_kit_sync_runtime_coordinator.dart'
    show CloudKitSyncRuntimeStatus;

/// The smallest coherent set of states that distinguishes every materially
/// different answer to "is EAST private CloudKit sync healthy right now,"
/// derived deterministically by [SyncHealthEvaluator] (see that file's own
/// doc comment for the full precedence contract) -- never invented ad hoc by
/// a caller.
enum SyncHealthState {
  /// The user has not enabled iCloud Sync on this device (no durable
  /// association marker exists yet, or it exists only as a not-yet-consented
  /// legacy candidate). Nothing else about durable/live sync state is
  /// evaluated once this is true -- see [SyncHealthEvaluator]'s own
  /// precedence doc comment.
  disabled,

  /// Sync is enabled, the currently-resolved iCloud account matches the
  /// durable association, bootstrap is durably complete, the outbox is
  /// empty, no "Remove from iCloud" transaction is pending, and no live
  /// runtime signal (an active pass, a scheduled retry, or the most recent
  /// pass's own terminal outcome) says otherwise.
  healthy,

  /// Valid local and/or remote synchronization work is known to remain (an
  /// unfinished bootstrap stage, a non-empty outbox with nothing yet
  /// permanently failed or conflicted, or a pass is actively running right
  /// now) and should complete through the normal, already-existing
  /// orchestrator/runtime pipeline with no special action required.
  pending,

  /// Sync is enabled, but the currently-resolved CloudKit account is not
  /// usable right now (no account signed in, restricted, temporarily
  /// unavailable, undetermined, or its private database/fingerprint could
  /// not be resolved). Local Kept/Reflection data is never touched by this
  /// state; it resolves itself the moment a foreground/startup/
  /// account-change trigger observes a usable account again.
  iCloudUnavailable,

  /// A known, existing, safe resume/retry state machine (most notably a
  /// "Remove from iCloud" deletion transaction, or a bounded-backoff retry
  /// already scheduled after a retryable failure) is actively converging on
  /// its own, through mechanisms this phase reuses rather than reinvents.
  recovering,

  /// The durable/live state cannot honestly be called healthy or a routine
  /// pending/recovering condition -- it requires an existing, narrowly-scoped
  /// safe recovery action (or, in some cases, a genuine external state
  /// change such as the user reassociating a changed iCloud account) before
  /// normal convergence can resume. Never resolved by a blind timer retry.
  recoveryRequired,

  /// The most recent completed runtime pass ended in a classified-retryable
  /// transport/persistence condition and a bounded-backoff retry is
  /// currently scheduled to resume it automatically.
  temporaryFailure,
}

/// A privacy-safe, immutable snapshot of EAST's current CloudKit sync
/// health, as computed by one [SyncHealthEvaluator.evaluate] call. See that
/// class's own doc comment for exactly which canonical, already-existing
/// sources of truth this snapshot's fields are read from -- this type itself
/// owns no durable storage and defines no new persisted state.
final class SyncHealthSnapshot {
  const SyncHealthSnapshot({
    required this.state,
    required this.syncEnabled,
    required this.accountAvailability,
    required this.outboxPendingCount,
    required this.hasUnresolvedOutboxEntries,
    required this.deletionRecoveryPending,
    this.deletionRecoveryStage,
    required this.runtimeStatus,
  });

  /// The single deterministic answer this snapshot exists to provide. See
  /// [SyncHealthState]'s own doc comments.
  final SyncHealthState state;

  /// Whether this device is durably associated with an iCloud account for
  /// sync purposes (mirrors `SyncPersistenceStore
  /// .loadAssociatedAccountFingerprint() != null` -- never the fingerprint
  /// value itself).
  final bool syncEnabled;

  /// The currently-resolved CloudKit account's own availability category, as
  /// last observed by this evaluation (a fresh read every call -- never
  /// cached across calls). Mirrors the platform's own `CKAccountStatus`,
  /// exactly as every other sync layer in this codebase already reports it.
  final CloudKitAccountAvailability accountAvailability;

  /// The number of mutations currently queued in the associated account's
  /// outbox -- a plain count only, never a `recordName`, `mutationId`, or any
  /// content.
  final int outboxPendingCount;

  /// Whether at least one queued outbox mutation has already been marked
  /// `failed` or `conflicted` by a prior pass -- i.e. work a blind retry
  /// cannot resolve on its own, distinct from an ordinary not-yet-attempted
  /// entry.
  final bool hasUnresolvedOutboxEntries;

  /// Whether a "Remove from iCloud" deletion transaction is currently
  /// durably pending for this device's associated account (see
  /// `lib/sync_deletion/`'s own state machine) -- never bypassed or resumed
  /// by anything other than that existing state machine.
  final bool deletionRecoveryPending;

  /// The pending deletion transaction's own current stage, when
  /// [deletionRecoveryPending] is `true`; `null` otherwise. Purely
  /// operational metadata -- an enum name only, never an account
  /// fingerprint, `dataEpoch`, or CloudKit identifier (mirrors
  /// `PendingDeletionTransaction.toLogSafeSummary`'s own allowed field set
  /// exactly).
  final DeletionTransactionStage? deletionRecoveryStage;

  /// The live, in-memory runtime coordinator status this evaluation observed
  /// -- reused directly, never duplicated, from
  /// `CloudKitSyncRuntimeCoordinator.status`. Ephemeral: resets to a fresh
  /// coordinator's defaults on every app relaunch, exactly as that type's
  /// own doc comment already documents; this snapshot's [state] never treats
  /// it as more authoritative than the durable reads above.
  final CloudKitSyncRuntimeStatus runtimeStatus;

  /// A privacy-safe summary suitable for logs/diagnostics -- every value
  /// here is a small enum name, a boolean, or a plain count. Never a
  /// fingerprint, `dataEpoch`, server token, record name, `revealId`,
  /// `localId`, `mutationId`, wisdom text, or Reflection text.
  Map<String, Object?> toLogSafeSummary() => {
        'state': state.name,
        'syncEnabled': syncEnabled,
        'accountAvailability': accountAvailability.name,
        'outboxPendingCount': outboxPendingCount,
        'hasUnresolvedOutboxEntries': hasUnresolvedOutboxEntries,
        'deletionRecoveryPending': deletionRecoveryPending,
        'deletionRecoveryStage': deletionRecoveryStage?.name,
        'runtimeStatus': runtimeStatus.toLogSafeSummary(),
      };

  @override
  String toString() => 'SyncHealthSnapshot(${toLogSafeSummary()})';
}
