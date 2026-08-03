/// Build 26 Phase 4D-2: the categorical, content-safe outcome of exactly
/// one [SyncOrchestrator.runSyncPass] call.
///
/// Every field here is either a symbolic status, a plain count, a boolean,
/// or an already-validated sync-domain projection -- never a raw platform
/// payload, a raw exception message, a token, a fingerprint, a mutation id,
/// a record name, or any wisdom/Reflection text. [toString]/
/// [toLogSafeSummary] never render more than that (see their own doc
/// comments) -- this satisfies the same structural privacy rule
/// `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md` §13.10 already established
/// for the persistence layer, extended here to the orchestration layer.
library;

import 'pending_incoming_sync_batch.dart';

/// The overall categorical result of one sync pass.
enum SyncPassStatus {
  /// The pass completed: account resolution, zone configuration (when
  /// attempted), outbox upload (when there was anything to upload), and a
  /// private-zone fetch all completed without a retryable/permanent
  /// failure. Does not imply any outbox mutation or incoming change
  /// actually existed -- an account with an empty outbox and no remote
  /// changes still completes.
  completed,

  /// No iCloud account is signed in. No persistence mutation and no
  /// transport call beyond the initial account snapshot occurred.
  noAccount,

  /// iCloud is restricted (e.g. parental controls, MDM policy). No
  /// persistence mutation and no transport call beyond the initial account
  /// snapshot occurred.
  restricted,

  /// The account status could not be determined, is temporarily
  /// unavailable, the private database is not usable, or the account
  /// fingerprint could not be resolved. Treated identically to [noAccount]/
  /// [restricted] for this phase's purposes: no upload, no fetch, no
  /// persistence mutation.
  unavailable,

  /// A retryable failure occurred (zone configuration, upload, or fetch) --
  /// see `lib/sync/sync_error_classification.dart`'s
  /// `SyncErrorCategory.retryable`. The outbox and server token are left
  /// exactly as they were; a future pass may simply be retried.
  retryableFailure,

  /// A permanent failure occurred -- see `SyncErrorCategory.permanent`, an
  /// `unexpectedPhysicalDeletion` fetch outcome, an unrecognized
  /// (`unknown`) transport result, or a detected account-identity change
  /// mid-pass. Retrying the identical operation will not help without some
  /// other change.
  permanentFailure,

  /// Upload outcomes (or a fetched server token) were received from the
  /// transport but this pass could not durably persist them
  /// (`SyncPersistenceStoreException`). The pass stops immediately -- no
  /// fetch is attempted if this occurs during upload -- so already-durable
  /// local state is never assumed to have advanced past what could
  /// actually be recorded.
  persistenceFailure,

  /// `fetchPrivateZoneChanges` reported
  /// `CloudKitZoneChangesOutcome.tokenExpired`. Only the server change
  /// token was cleared; `dataEpoch`, the outbox, and every stored
  /// record-system-fields value are untouched. A caller must issue a fresh
  /// full-zone fetch (`previousServerToken: null`) in a future pass -- this
  /// pass does not loop to retry it immediately.
  tokenExpiredNeedsRefetch,
}

/// The full, content-safe result of one [SyncOrchestrator.runSyncPass] call.
final class SyncPassResult {
  const SyncPassResult._({
    required this.status,
    this.uploadedRecordCount = 0,
    this.acknowledgedMutationCount = 0,
    this.permanentlyFailedMutationCount = 0,
    this.conflictedMutationCount = 0,
    this.pendingIncomingBatch,
    this.cause,
  });

  factory SyncPassResult.completed({
    int uploadedRecordCount = 0,
    int acknowledgedMutationCount = 0,
    int permanentlyFailedMutationCount = 0,
    int conflictedMutationCount = 0,
    PendingIncomingSyncBatch? pendingIncomingBatch,
  }) =>
      SyncPassResult._(
        status: SyncPassStatus.completed,
        uploadedRecordCount: uploadedRecordCount,
        acknowledgedMutationCount: acknowledgedMutationCount,
        permanentlyFailedMutationCount: permanentlyFailedMutationCount,
        conflictedMutationCount: conflictedMutationCount,
        pendingIncomingBatch: pendingIncomingBatch,
      );

  factory SyncPassResult.noAccount() =>
      const SyncPassResult._(status: SyncPassStatus.noAccount);

  factory SyncPassResult.restricted() =>
      const SyncPassResult._(status: SyncPassStatus.restricted);

  factory SyncPassResult.unavailable() =>
      const SyncPassResult._(status: SyncPassStatus.unavailable);

  factory SyncPassResult.retryableFailure({Object? cause}) =>
      SyncPassResult._(status: SyncPassStatus.retryableFailure, cause: cause);

  factory SyncPassResult.permanentFailure({Object? cause}) =>
      SyncPassResult._(status: SyncPassStatus.permanentFailure, cause: cause);

  factory SyncPassResult.persistenceFailure({Object? cause}) =>
      SyncPassResult._(
        status: SyncPassStatus.persistenceFailure,
        cause: cause,
      );

  factory SyncPassResult.tokenExpiredNeedsRefetch() =>
      const SyncPassResult._(status: SyncPassStatus.tokenExpiredNeedsRefetch);

  final SyncPassStatus status;

  /// Number of records this pass attempted to upload (0 when the outbox was
  /// empty or no bucket existed).
  final int uploadedRecordCount;

  /// Number of outbox mutations acknowledged (removed) this pass.
  final int acknowledgedMutationCount;

  /// Number of outbox mutations newly marked
  /// `PersistedOutboxMutationStatus.failed` this pass.
  final int permanentlyFailedMutationCount;

  /// Number of outbox mutations newly marked
  /// `PersistedOutboxMutationStatus.conflicted` this pass.
  final int conflictedMutationCount;

  /// The pending, not-yet-applied, not-yet-committed incoming CloudKit
  /// batch this pass's successful fetch produced -- durably scoped
  /// internally to the exact account fingerprint, `dataEpoch`, and
  /// previous/proposed server-change-token baseline it was fetched
  /// against. See [PendingIncomingSyncBatch]'s own doc comment for the
  /// full Phase 4E validation contract this scope metadata exists to
  /// support (account-match, epoch-match, token-match, then apply, then
  /// commit).
  ///
  /// Phase 4D-2 deliberately does not durably apply this batch's
  /// projections to any repository and does not commit its proposed
  /// token, so advancing the persisted server change token immediately
  /// would create a crash window: if the token were committed before a
  /// future Phase 4E durably applied the incoming batch, and the app
  /// terminated in between, those changes could never be fetched again.
  ///
  /// `null` whenever this pass did not reach a successful fetch outcome
  /// (`tokenExpiredNeedsRefetch`, any failure status, etc. never carry a
  /// batch). **Never** rendered by [toString]/[toLogSafeSummary] beyond
  /// the safe booleans/counts [toLogSafeSummary] surfaces -- and
  /// [PendingIncomingSyncBatch]'s own [PendingIncomingSyncBatch.toString]/
  /// [PendingIncomingSyncBatch.toLogSafeSummary] never render its scope
  /// values either.
  final PendingIncomingSyncBatch? pendingIncomingBatch;

  /// Always `false` in this phase: `fetchPrivateZoneChanges` itself
  /// aggregates every page before returning once (see
  /// `lib/sync_platform/cloud_kit_zone_changes_contract.dart`'s own doc
  /// comment) -- there is no orchestrator-level pagination cursor to carry
  /// forward. Retained as an explicit field, rather than omitted, so a
  /// future phase that introduces real multi-call pagination has a
  /// pre-existing, already-tested place to report it in, instead of a
  /// silently-added field later.
  ///
  /// Fixed at declaration rather than as a constructor parameter: no
  /// factory or call site ever needs a value other than `false` yet, so a
  /// settable parameter here would be dead weight (and was flagged by the
  /// analyzer as such). If a future phase needs to report `true`, add the
  /// parameter back then, with a real caller that supplies it.
  final bool hasMoreWorkRemaining = false;

  /// The original underlying failure (a `CloudKitPlatformException`, a
  /// `SyncPersistenceStoreException`, a non-`success`
  /// `CloudKitModifyRecordsResult`/`CloudKitZoneChangesResult`, etc.),
  /// retained for programmatic inspection and tests only. **Never**
  /// rendered by [toString]/[toLogSafeSummary].
  final Object? cause;

  /// A privacy-safe summary suitable for logs/diagnostics: status, counts,
  /// and booleans only -- never [cause], never [pendingIncomingBatch]'s
  /// account fingerprint, `dataEpoch`, or token values, and never the
  /// contents of its incoming projections, only their lengths (via
  /// [pendingIncomingBatch]'s own [PendingIncomingSyncBatch
  /// .toLogSafeSummary], flattened here).
  Map<String, Object?> toLogSafeSummary() => {
        'status': status.name,
        'uploadedRecordCount': uploadedRecordCount,
        'acknowledgedMutationCount': acknowledgedMutationCount,
        'permanentlyFailedMutationCount': permanentlyFailedMutationCount,
        'conflictedMutationCount': conflictedMutationCount,
        'hasMoreWorkRemaining': hasMoreWorkRemaining,
        'hasPendingBatch': pendingIncomingBatch != null,
        'incomingKeptCount':
            pendingIncomingBatch?.incomingKeptWisdomProjections.length ?? 0,
        'incomingSyncStateCount':
            pendingIncomingBatch?.incomingSyncStateProjections.length ?? 0,
        'hasBaseDataEpoch': pendingIncomingBatch?.baseDataEpoch != null,
        'hasPreviousCheckpoint':
            pendingIncomingBatch?.previousServerChangeToken != null,
        'hasPendingCheckpoint':
            pendingIncomingBatch?.pendingServerChangeToken != null,
        'hasCause': cause != null,
      };

  @override
  String toString() => 'SyncPassResult(${toLogSafeSummary()})';
}
