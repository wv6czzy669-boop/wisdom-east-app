/// Build 26 Phase 4D-2 (incoming-batch scope binding): the durable scope
/// metadata a successful fetch's incoming batch must carry so a future
/// Phase 4E can prove -- before ever applying that batch or committing its
/// checkpoint -- that the batch still belongs to the exact account and
/// local sync baseline it was fetched against.
///
/// This corrects a remaining integration-boundary gap: `SyncPassResult`
/// already returns incoming projections and a proposed
/// (not-yet-committed) server change token, but neither carried the
/// account fingerprint, the bucket's `dataEpoch` at fetch time, or the
/// exact previous token the fetch was performed against. Without that
/// scope metadata, Phase 4E cannot reliably reject a batch fetched for one
/// account after the device has switched to another, a batch built from a
/// stale `dataEpoch`, a batch built from an older server-token baseline, or
/// two repeated pre-commit fetch results being committed out of order.
///
/// [PendingIncomingSyncBatch] is never persisted, never applied to any
/// repository, and never used to commit anything by this phase -- it is a
/// pure in-memory carrier returned once, through
/// `SyncPassResult.pendingIncomingBatch`, for a future Phase 4E to consume.
library;

import '../sync/cloud_east_sync_state_projection.dart';
import '../sync/cloud_kept_wisdom_projection.dart';
import '../sync/data_epoch.dart';

/// A pending (not-yet-applied, not-yet-committed) incoming CloudKit batch,
/// durably scoped to the exact account and local sync baseline it was
/// fetched against.
///
/// A future Phase 4E must validate all of the following *before* applying
/// this batch or committing [pendingServerChangeToken]:
///
/// 1. the current opaque account fingerprint equals [accountFingerprint];
/// 2. the current bucket's `dataEpoch` equals [baseDataEpoch] -- or, when
///    [baseDataEpoch] is `null` (no bucket existed at fetch time), the
///    no-bucket bootstrap rules explicitly permit establishing one from an
///    incoming sync-state record;
/// 3. the currently persisted server change token equals
///    [previousServerChangeToken];
/// 4. [incomingKeptWisdomProjections]/[incomingSyncStateProjections] pass
///    account/dataEpoch/domain validation;
/// 5. the records are durably and idempotently applied;
/// 6. only then may [pendingServerChangeToken] ever be committed.
///
/// A stale or account-mismatched batch must fail closed: Phase 4E must
/// never apply it and must never advance the token from it. This phase
/// (Phase 4D-2) performs none of that validation, application, or commit
/// itself -- it only constructs and returns this value.
final class PendingIncomingSyncBatch {
  PendingIncomingSyncBatch({
    required this.accountFingerprint,
    required this.baseDataEpoch,
    required this.previousServerChangeToken,
    required this.pendingServerChangeToken,
    required List<CloudKeptWisdomProjection> incomingKeptWisdomProjections,
    required List<CloudEastSyncStateProjection> incomingSyncStateProjections,
  })  : incomingKeptWisdomProjections =
            List.unmodifiable(incomingKeptWisdomProjections),
        incomingSyncStateProjections =
            List.unmodifiable(incomingSyncStateProjections);

  /// The opaque SHA-256 account fingerprint resolved at the start of the
  /// pass that produced this batch -- the existing opaque fingerprint
  /// only, never a raw CloudKit user identifier. **Never** rendered by
  /// [toString]/[toLogSafeSummary].
  final String accountFingerprint;

  /// The account bucket's exact `dataEpoch` at fetch time, or `null` when
  /// no bucket existed. Never a fabricated/default epoch: a `null` bucket
  /// at fetch time always yields a `null` [baseDataEpoch] here, never a
  /// guessed value. **Never** rendered by [toString]/[toLogSafeSummary]
  /// beyond the `hasBaseDataEpoch` boolean.
  final DataEpoch? baseDataEpoch;

  /// The exact opaque token this batch's fetch was performed against --
  /// the same value passed as
  /// `CloudKitZoneChangesRequest.previousServerToken` -- or `null` for an
  /// initial/bootstrap fetch. Opaque and uninterpreted. **Never** rendered
  /// beyond a presence boolean.
  final String? previousServerChangeToken;

  /// The opaque next server change token CloudKit returned for this
  /// successful fetch -- a *proposed* checkpoint only, not yet durably
  /// committed by anything in this codebase. Opaque and uninterpreted.
  /// **Never** rendered beyond a presence boolean. See
  /// `SyncOrchestrator`'s own doc comment for why this phase never commits
  /// it.
  final String? pendingServerChangeToken;

  /// Validated, already-decoded incoming active/tombstone projections this
  /// batch's fetch returned. Never applied to any repository by this
  /// phase.
  final List<CloudKeptWisdomProjection> incomingKeptWisdomProjections;

  /// Validated, already-decoded incoming `CKEastSyncState` projections, if
  /// any. Same non-application rule as [incomingKeptWisdomProjections].
  final List<CloudEastSyncStateProjection> incomingSyncStateProjections;

  /// A privacy-safe summary suitable for logs/diagnostics: counts and
  /// booleans only -- never [accountFingerprint], never [baseDataEpoch]'s
  /// value, never either token's value, and never any projection's record
  /// name, revealId, wisdom text, Reflection text, or record-system-fields.
  Map<String, Object?> toLogSafeSummary() => {
        'incomingKeptCount': incomingKeptWisdomProjections.length,
        'incomingSyncStateCount': incomingSyncStateProjections.length,
        'hasBaseDataEpoch': baseDataEpoch != null,
        'hasPreviousCheckpoint': previousServerChangeToken != null,
        'hasPendingCheckpoint': pendingServerChangeToken != null,
      };

  @override
  String toString() => 'PendingIncomingSyncBatch(${toLogSafeSummary()})';
}
