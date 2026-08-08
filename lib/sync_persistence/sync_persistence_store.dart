/// Build 26 Phase 4D-1: the durable local sync-state and outbox persistence
/// boundary -- the storage counterpart of ADR-007's Local state envelope
/// (`syncMetadata`, `outbox`) and
/// `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md` §6/§12, scoped per opaque
/// CloudKit account fingerprint.
///
/// Deliberately narrow, mirroring `lib/persistence/kept_state_store.dart`'s
/// own precedent: this is not a general sync engine and it never calls
/// CloudKit itself. Every method here only reads or atomically replaces
/// already-validated local state that a future orchestrator (out of this
/// phase's scope) is responsible for deciding when to call.
///
/// No method on this interface returns a mutable collection -- every
/// [AccountSyncState]/[PersistedOutboxMutation] and every `List`/`Map` it
/// exposes is unmodifiable, consistent with this codebase's existing
/// envelope value types.
library;

import '../sync/sync_change.dart';

import 'account_sync_state.dart';
import 'incoming_batch_checkpoint.dart';
import 'outbox_mutation_retirement.dart';
import 'persisted_outbox_mutation.dart';

/// Thrown by [SyncPersistenceStore] implementations on any failure to load,
/// replace, or otherwise safely mutate the protected sync-state envelope.
///
/// Narrow, mirroring `KeptStateStoreException`: [stage] identifies which
/// step failed (safe diagnostic metadata) and [message] is always a static,
/// content-safe string authored at the throw site -- never built from, or
/// including, envelope JSON, a server token, a record name, a mutation id,
/// an account fingerprint, or a filesystem path.
///
/// [cause] retains the original underlying exception (a bridge exception, a
/// filesystem exception, a decode `FormatException`, etc.) for programmatic
/// inspection and testing only. **It is deliberately excluded from
/// [toString]**: an underlying platform/filesystem exception's own message
/// can itself carry an absolute path (for example, a `PathNotFoundException`
/// renders `path = '/Users/.../east_sync_state/...'`) or other
/// implementation detail this store must never surface. Rendering this
/// exception must therefore only ever combine [stage] and [message] -- both
/// fixed, content-safe, authored strings -- never [cause].
class SyncPersistenceStoreException implements Exception {
  const SyncPersistenceStoreException(this.stage, this.message, [this.cause]);

  final String stage;
  final String message;

  /// The original underlying exception, retained for programmatic
  /// inspection (and tests) only. Never rendered by [toString].
  final Object? cause;

  @override
  String toString() => 'SyncPersistenceStoreException[$stage]: $message';
}

/// Thrown when a caller attempts to enqueue a mutation whose `mutationId`
/// already exists in the outbox with genuinely different content -- an
/// impossible identity collision this store refuses to silently resolve
/// either way.
class ConflictingMutationIdentityException implements Exception {
  const ConflictingMutationIdentityException();

  @override
  String toString() => 'ConflictingMutationIdentityException: an outbox '
      'entry with this mutationId already exists with different content.';
}

/// Thrown when a caller attempts to enqueue a mutation whose `dataEpoch`
/// does not match the `dataEpoch` already established for that account
/// bucket.
///
/// This is a stable, content-safe, fail-closed signal -- it carries no
/// epoch value, no record identity, and no account fingerprint. No
/// automatic epoch reset or reconciliation happens here or anywhere else in
/// this phase; a future orchestrator decides how to react (for example, by
/// discarding a genuinely stale-epoch local mutation per
/// `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md` §4.1/ADR-007's Epoch-aware
/// push).
class MutationEpochMismatchException implements Exception {
  const MutationEpochMismatchException();

  @override
  String toString() => 'MutationEpochMismatchException: this mutation\'s '
      'dataEpoch does not match the account\'s current dataEpoch.';
}

/// The durable local sync-state and outbox persistence boundary.
///
/// See the library doc comment above for scope. Every method is scoped by
/// [accountFingerprint] -- the opaque CloudKit account fingerprint
/// (`CloudKitAccountSnapshot.accountFingerprint`) -- and every
/// implementation must serialize all operations for a given fingerprint (and
/// indeed across fingerprints, since they share one physical envelope file)
/// through a single coordinator path, exactly as
/// `ProtectedFileKeptStateStore` already does for the unrelated Kept-state
/// envelope.
abstract interface class SyncPersistenceStore {
  /// Returns [accountFingerprint]'s current durable sync state, or `null` if
  /// no state has ever been recorded for this fingerprint (a brand-new
  /// account, or one that was previously [clearAccountState]d).
  ///
  /// Returns `null` -- never a synthesized or partial state -- for a
  /// fingerprint that exists only in the quarantined bucket
  /// ([quarantineAccountState]); a quarantined account's state is not
  /// visible through this method until a future layer explicitly restores
  /// it.
  Future<AccountSyncState?> loadAccountState(String accountFingerprint);

  /// Atomically replaces [accountFingerprint]'s entire active durable sync
  /// state with [state]. Always a complete replacement, never a partial
  /// merge -- the caller is responsible for computing the full next state
  /// (mirroring `KeptStateStore.replace`).
  Future<void> replaceAccountState(
    String accountFingerprint,
    AccountSyncState state,
  );

  /// Durably enqueues one outbound mutation for [accountFingerprint].
  ///
  /// If no bucket exists yet for this fingerprint, one is created using
  /// exactly [change]'s own `dataEpoch` -- an explicit, non-fabricated
  /// epoch source, never a default. If a bucket already exists, [change]'s
  /// `dataEpoch` must equal it exactly, or this throws
  /// [MutationEpochMismatchException].
  ///
  /// Outbox identity/coalescing policy, keyed by
  /// `(change.projection.mutationId, change.projection.recordName)`:
  /// - **Same `mutationId`, byte-identical content:** idempotent no-op.
  /// - **Same `mutationId`, different content:** an impossible identity
  ///   collision -- throws [ConflictingMutationIdentityException].
  /// - **Different `mutationId`, different `recordName`:** appended to the
  ///   outbox in deterministic order.
  /// - **Different `mutationId`, same `recordName`:** the newer mutation
  ///   **atomically supersedes** the existing not-yet-sent one for that
  ///   record, in the same envelope write, preserving that record's
  ///   original position in the outbox (the slot is overwritten in place,
  ///   never removed and re-appended) -- see
  ///   `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md` §13.6 for the full,
  ///   frozen rule (active-over-active, tombstone-over-active, and
  ///   active-over-tombstone are all valid supersessions; identity is
  ///   always `recordName`, never wisdom text or a display date).
  Future<void> enqueueMutation(String accountFingerprint, SyncChange change);

  /// Atomically applies the outcome of one push attempt to
  /// [accountFingerprint]'s outbox, in a single envelope write:
  /// [acknowledgedMutationIds] are removed entirely (CloudKit confirmed
  /// them), and every mutation id in [updatedStatusByMutationId] has its
  /// [PersistedOutboxMutationStatus] updated to the given value. A
  /// mutation id that appears in neither collection is left completely
  /// unchanged -- this is how a retryable transport failure (§3) is
  /// represented: the caller simply omits that mutation from both
  /// collections, and this store never mutates it.
  ///
  /// A mutation id that does not exist in the current outbox is silently
  /// ignored (it may have already been acknowledged by a previous,
  /// possibly-retried call, or superseded by [enqueueMutation] -- see its
  /// doc comment) -- this keeps acknowledgment itself idempotent.
  /// **Acknowledgment is always `mutationId`-specific, never
  /// `recordName`-specific:** if a record's pending mutation was superseded
  /// (a newer local edit replaced it with a new `mutationId` before the
  /// older one synced), acknowledging the *old*, no-longer-queued
  /// `mutationId` removes nothing -- the current, replacement mutation is
  /// untouched and remains queued exactly as `enqueueMutation` left it.
  /// This never changes [AccountSyncState.dataEpoch].
  Future<void> applyMutationOutcomes(
    String accountFingerprint, {
    Set<String> acknowledgedMutationIds = const {},
    Map<String, PersistedOutboxMutationStatus> updatedStatusByMutationId =
        const {},
  });

  /// Returns every mutation currently in [accountFingerprint]'s outbox --
  /// pending, failed, and conflicted alike -- in the exact order they occupy
  /// in the stored outbox list. A brand-new mutation is appended at the end;
  /// a mutation that supersedes an existing pending one for the same record
  /// (see [enqueueMutation]) occupies that same, original list position
  /// rather than moving to the end -- this is precisely what keeps a
  /// repeatedly-edited record from perpetually pushing itself (and nothing
  /// else) to the back of the queue. Returns an empty list for a
  /// fingerprint with no recorded state.
  Future<List<PersistedOutboxMutation>> readPendingMutations(
    String accountFingerprint,
  );

  /// Atomically records [systemFields] (Phase 4C-2's opaque, per-record
  /// CloudKit system-fields blob) for [recordName], after a caller has
  /// confirmed that record's save succeeded. Replaces any previously-stored
  /// value for the same [recordName]; never merges or appends. Preserves
  /// [AccountSyncState.dataEpoch] unchanged. Throws
  /// [SyncPersistenceStoreException] if no bucket exists yet for
  /// [accountFingerprint] -- this method never fabricates an epoch to create
  /// one; a bucket must first exist via [enqueueMutation] or
  /// [replaceAccountState].
  Future<void> replaceRecordSystemFields(
    String accountFingerprint,
    String recordName,
    String systemFields,
  );

  /// Atomically stores [serverToken] as [accountFingerprint]'s new opaque
  /// server change token, after a caller has confirmed a
  /// `fetchPrivateZoneChanges` call completed with
  /// `CloudKitZoneChangesOutcome.success`. Never called for any other
  /// outcome. Preserves [AccountSyncState.dataEpoch] unchanged. Throws
  /// [SyncPersistenceStoreException] if no bucket exists yet for
  /// [accountFingerprint] -- see [replaceRecordSystemFields]'s doc comment
  /// for why.
  Future<void> storeServerChangeToken(
    String accountFingerprint,
    String serverToken,
  );

  /// Atomically clears only [accountFingerprint]'s server change token
  /// (e.g. after a caller observes `CloudKitZoneChangesOutcome.tokenExpired`
  /// and confirms the account it belongs to), leaving every other part of
  /// that account's state -- [AccountSyncState.dataEpoch], the outbox, and
  /// every stored system-fields value -- completely untouched. A no-op if
  /// no bucket exists yet for [accountFingerprint].
  Future<void> clearServerChangeToken(String accountFingerprint);

  /// Atomically and permanently clears [accountFingerprint]'s entire active
  /// durable sync state (token, system fields, and outbox alike), leaving
  /// it as though this fingerprint had never synced. Distinct from
  /// [quarantineAccountState]: nothing is preserved for later recovery.
  Future<void> clearAccountState(String accountFingerprint);

  /// Atomically moves [accountFingerprint]'s entire active durable sync
  /// state out of normal circulation -- [loadAccountState] returns `null`
  /// for it afterward -- without discarding it. A no-op if the fingerprint
  /// has no active state to quarantine.
  Future<void> quarantineAccountState(String accountFingerprint);

  /// Build 26 Phase 4E-1: atomically commits an incoming CloudKit batch's
  /// durable checkpoint -- every requested record's system-fields value,
  /// the new server change token, and (optionally) a validated
  /// [AccountBootstrapState] transition -- in exactly **one** sync-envelope
  /// read-modify-replace operation.
  ///
  /// This method never mutates the Kept/Reflection envelope, never applies
  /// an incoming record to any repository, and never acknowledges or
  /// otherwise touches the outbox -- it exists solely to give a future
  /// Phase 4E-3 incoming-apply transaction one atomic place to durably
  /// record "this batch's system fields and checkpoint are now safe,"
  /// after -- never before -- that transaction has already durably applied
  /// the batch's Kept/Reflection changes elsewhere.
  ///
  /// Returns a [CommitIncomingBatchCheckpointResult] describing exactly
  /// what happened; every business-rule failure this method's own doc
  /// comment on [CommitIncomingBatchCheckpointRequest]/
  /// [IncomingCheckpointStatus] describes is reported as a typed,
  /// non-[IncomingCheckpointStatus.committed] result -- never a thrown
  /// exception -- so a caller can distinguish every failure reason without
  /// a catch-cascade. Only a genuine underlying storage failure (the same
  /// class of failure every other method on this interface can throw) is
  /// still reported as a thrown [SyncPersistenceStoreException]; in that
  /// case, neither the token nor any system-fields value changes, exactly
  /// as this interface's other atomic methods already guarantee.
  Future<CommitIncomingBatchCheckpointResult> commitIncomingBatchCheckpoint(
    CommitIncomingBatchCheckpointRequest request,
  );

  /// Build 26 Phase 4E-3b: atomically retires (permanently removes) exactly
  /// one outbox mutation, but only if the outbox's *current* entry for
  /// [RetireOutboxMutationRequest.recordName] still exactly matches
  /// [RetireOutboxMutationRequest.mutationId] under
  /// [RetireOutboxMutationRequest.expectedDataEpoch] -- never a blind
  /// "remove whatever is queued for this record" operation, and never
  /// [SyncPersistenceStore.applyMutationOutcomes] (whose acknowledgment
  /// semantics mean CloudKit explicitly confirmed an upload -- see
  /// `outbox_mutation_retirement.dart`'s own doc comment for why a remote
  /// conflict loss must never be represented that way).
  ///
  /// Every failure mode is a typed, non-thrown
  /// [RetireOutboxMutationStatus] -- a missing account, a `dataEpoch`
  /// mismatch, a missing record, or a `mutationId` mismatch (a newer
  /// mutation already superseded the one this request targeted) are all
  /// safe no-ops, never a thrown exception and never a destructive
  /// best-effort removal. Only a genuine underlying storage failure is still
  /// reported as a thrown [SyncPersistenceStoreException].
  Future<RetireOutboxMutationResult> retireOutboxMutationIfCurrent(
    RetireOutboxMutationRequest request,
  );
}
