/// Build 26 Phase 5 (slice 3, safety repair): the local "finalize" half of
/// the "Remove from iCloud" deletion transaction.
///
/// Scope. This is the ONLY code in this slice that mutates durable state. It
/// runs strictly after `CloudKitRemoteDeletionRunner` has driven a
/// transaction to [DeletionTransactionStage.localFinalizePending] -- by that
/// point, the replacement remote `dataEpoch` barrier has already been
/// established, every `CKKeptWisdom` record under the old epoch has already
/// been purged, and zero remaining `CKKeptWisdom` records have already been
/// independently verified. This finalizer performs no CloudKit operation of
/// any kind -- it only clears local sync *metadata* for the transaction's
/// target account. See the library doc comments on
/// `pending_deletion_transaction.dart` and
/// `cloud_kit_remote_deletion_runner.dart` for the stages this slice does
/// not own.
///
/// **Never touches user content.** [KeptRepository]/`SavedReflectionsService`
/// state, `revealId` occurrence identity, Kept ordering/content, daily
/// wisdom access state, `unlockAt`, and Keeper purchase/entitlement are
/// completely out of this finalizer's reach -- it is never constructed with,
/// and never calls, anything from those layers. Only [SyncPersistenceStore]
/// (the target account's [AccountSyncState] bucket and the durable
/// associated-account marker) and [LocalSyncIntentStore] (pending intents)
/// are touched.
///
/// **Safety repair -- account mismatch is now a pre-flight check, before ANY
/// mutation.** The prior revision of this file checked the associated-account
/// marker only when attempting to clear it, *after* pending intents and the
/// target [AccountSyncState] bucket had already been mutated. That is not
/// sufficiently fail-closed: [LocalSyncIntentStore] is device-wide, never
/// fingerprint-scoped (see its own doc comment), so if the durable marker
/// currently names a *different* account than this transaction's own
/// [PendingDeletionTransaction.accountFingerprint] -- for example, the user
/// signed into a different iCloud account on this device between Slice 2's
/// remote verification and this finalize call -- clearing device-wide
/// intents before that mismatch is even detected could discard sync intents
/// that in fact belong to the *other*, currently-associated account. [finalize]
/// therefore performs, in order:
///
///  1. Load the transaction; if none exists or its stage is not
///     [DeletionTransactionStage.localFinalizePending], do nothing.
///  2. **Pre-flight account check** -- a pure read, before any mutation:
///     [SyncPersistenceStore.loadAssociatedAccountFingerprint]. If it is
///     non-null and differs from the transaction's own target fingerprint,
///     return [LocalDeletionFinalizeOutcome.accountMismatch] immediately --
///     zero [LocalSyncIntent] removal, zero [AccountSyncState] mutation, zero
///     association-marker mutation, zero transaction mutation. A `null`
///     marker is explicitly allowed to proceed (see "Crash-resume" below --
///     a prior finalize attempt may already have durably cleared it before a
///     crash interrupted a later step).
///  3. Clear every currently-pending [LocalSyncIntent] (device-wide -- see
///     [LocalSyncIntentStore]'s own doc comment). Sync *intent* only -- never
///     the underlying Kept/Reflection content those intents referenced.
///  4. [SyncPersistenceStore.clearAccountState] the transaction's target
///     fingerprint -- the single, already-atomic "smallest correct
///     operation" that removes that bucket's `dataEpoch`, server change
///     token, every stored record-system-fields value, the entire outbox
///     (which also represents tombstones -- see `sync_change.dart`; there is
///     no separate tombstone store), and `bootstrapState` all at once. Never
///     field-by-field duplicated here.
///  5. [SyncPersistenceStore.clearAssociatedAccountFingerprintIfCurrent],
///     passing the transaction's own target fingerprint as
///     `expectedCurrent` -- an idempotent no-op if the marker is already
///     `null` (see "Crash-resume").
///  6. **Hard runtime verification gate -- not Dart's `assert` construct.**
///     Ordinary,
///     always-executed (including in release builds) control flow reads,
///     independently: [SyncPersistenceStore.loadAccountState] for the target
///     (must be `null`), [SyncPersistenceStore
///     .loadAssociatedAccountFingerprint] (must be `null`),
///     and [LocalSyncIntentStore.loadIntents] (must be empty). If any of
///     these three reads disagrees, or if any of them throws, [finalize]
///     returns [LocalDeletionFinalizeOutcome.verificationFailed] and **does
///     not** proceed to step 7 -- the deletion transaction is left
///     completely durable, so normal sync remains blocked and a future
///     retry can re-attempt safely (steps 3-5 are all independently
///     idempotent). Dart's `assert` construct is deliberately not used for
///     this gate: an `assert` is stripped in release builds, which would
///     silently turn
///     this into a no-op check with no effect on whether step 7 runs --
///     unacceptable for a correctness-critical gate that decides whether the
///     transaction is safe to durably remove.
///  7. [SyncPersistenceStore.clearDeletionTransaction] LAST, only once every
///     prior step is durably confirmed complete by step 6's real runtime
///     checks.
///
/// Every mutating step above (3-5) is independently idempotent, so a crash
/// at any point and a subsequent repeat call converges to the same final
/// state -- re-running [finalize] against a transaction still at
/// [DeletionTransactionStage.localFinalizePending] simply re-attempts
/// whatever step was interrupted; every already-completed step is a safe
/// no-op the second time, and step 2's pre-flight check is re-evaluated
/// fresh on every call (never cached across calls).
///
/// **Crash-resume.** A crash between step 5 (marker cleared) and step 7
/// (transaction cleared) leaves the durable marker `null`. A resuming call's
/// own step 2 pre-flight check explicitly allows a `null` marker to proceed
/// (it is not "non-null and different") -- this is exactly what makes
/// resumption after that particular crash point safe, rather than
/// permanently stuck reporting a false mismatch.
///
/// **Account safety.** This finalizer contacts CloudKit for nothing. A
/// durable marker naming a different account than this transaction's target
/// is never touched, never cleared, and never retargeted -- detected and
/// refused at step 2, before any other mutation, not merely at the
/// marker-clear call site itself.
///
/// **Privacy.** [LocalDeletionFinalizeResult.toLogSafeSummary]/[toString]
/// expose only [LocalDeletionFinalizeOutcome] -- never an account
/// fingerprint, a `revealId`, a `localId`, a `mutationId`, an `intentId`, a
/// record name, a server token, CloudKit system fields, wisdom text,
/// Reflection content, or a filesystem path.
library;

import '../sync_integration/local_sync_intent_store.dart';
import '../sync_persistence/associated_account_fingerprint_commit.dart';
import '../sync_persistence/pending_deletion_transaction.dart';
import '../sync_persistence/sync_persistence_store.dart';

/// The categorical, content-safe result of one [LocalDeletionFinalizer
/// .finalize] call. Mirrors this codebase's established precedent
/// (`RemoteDeletionRunOutcome`, `SyncRuntimeOutcome`,
/// `AdvanceDeletionTransactionStatus`) of a small, closed status enum rather
/// than a thrown exception for every ordinary business-rule outcome.
enum LocalDeletionFinalizeOutcome {
  /// No [PendingDeletionTransaction] exists. Zero mutation was attempted.
  noPendingTransaction,

  /// A transaction exists but its stage is not
  /// [DeletionTransactionStage.localFinalizePending] -- not this
  /// finalizer's turn yet. Zero mutation was attempted.
  notYetAtLocalFinalizeStage,

  /// Build 26 Phase 5 (slice 3, safety repair): the durable
  /// associated-account marker is non-null and names a *different* account
  /// than this transaction's own target. Detected at the very first,
  /// pre-flight step -- zero [LocalSyncIntent] removal, zero
  /// [AccountSyncState] mutation, zero association-marker mutation, and zero
  /// transaction mutation occurred. Never automatically retried by a timer
  /// (see `SyncRuntimeOutcome.terminalFailure`'s own reasoning) -- this
  /// requires a real state change (the device's iCloud account changing
  /// back, or a future explicit product decision), not a blind retry.
  accountMismatch,

  /// Build 26 Phase 5 (slice 3, safety repair): after every cleanup step
  /// ran, the hard runtime verification gate (never Dart's `assert`
  /// construct, always
  /// evaluated) found the target [AccountSyncState] bucket still present,
  /// the associated-account marker still non-null, pending
  /// [LocalSyncIntent]s still present, or one of those three reads itself
  /// threw. The deletion transaction was **not** cleared -- it remains fully
  /// durable, normal sync remains blocked, and a future retry may safely
  /// re-attempt (every cleanup step is independently idempotent).
  verificationFailed,

  /// Local finalize completed: pending intents were cleared, the target
  /// account's [AccountSyncState] bucket is gone, the associated-account
  /// marker no longer names the target fingerprint, the hard runtime
  /// verification gate confirmed all three independently, and the deletion
  /// transaction itself has been durably removed, last.
  finalized,
}

/// A privacy-safe, immutable result of one [LocalDeletionFinalizer.finalize]
/// call.
final class LocalDeletionFinalizeResult {
  const LocalDeletionFinalizeResult({
    required this.outcome,
    this.clearedIntentCount = 0,
    this.markerCleared = false,
  });

  final LocalDeletionFinalizeOutcome outcome;

  /// The number of pending [LocalSyncIntent]s removed by this call. Always
  /// `0` for [LocalDeletionFinalizeOutcome.noPendingTransaction],
  /// [LocalDeletionFinalizeOutcome.notYetAtLocalFinalizeStage], and
  /// [LocalDeletionFinalizeOutcome.accountMismatch] (all three attempt zero
  /// mutation). May be nonzero for
  /// [LocalDeletionFinalizeOutcome.verificationFailed] -- intent clearing
  /// itself is idempotent and safe to have already happened before
  /// verification caught a different problem. A count only -- never an
  /// `intentId`.
  final int clearedIntentCount;

  /// Whether this call itself durably cleared the associated-account marker
  /// (`true`), as opposed to the marker already being clear before this call
  /// ever ran (`false`). Only meaningful for
  /// [LocalDeletionFinalizeOutcome.finalized].
  final bool markerCleared;

  /// A privacy-safe summary: outcome, a count, and a boolean only -- never
  /// an account fingerprint or any identifier.
  Map<String, Object?> toLogSafeSummary() => {
        'outcome': outcome.name,
        'clearedIntentCount': clearedIntentCount,
        'markerCleared': markerCleared,
      };

  @override
  String toString() => 'LocalDeletionFinalizeResult(${toLogSafeSummary()})';
}

/// Drives one pending "Remove from iCloud" deletion transaction's LOCAL
/// finalize step. See the library doc comment for the full contract.
final class LocalDeletionFinalizer {
  const LocalDeletionFinalizer({
    required SyncPersistenceStore syncPersistenceStore,
    required LocalSyncIntentStore localSyncIntentStore,
  })  : _syncPersistenceStore = syncPersistenceStore,
        _localSyncIntentStore = localSyncIntentStore;

  final SyncPersistenceStore _syncPersistenceStore;
  final LocalSyncIntentStore _localSyncIntentStore;

  /// Runs local finalize once. Never throws for an ordinary business-rule
  /// outcome -- see [LocalDeletionFinalizeOutcome]. A genuine underlying
  /// storage failure from step 2 (the pre-flight read) or from clearing
  /// intents/the account bucket/the marker (steps 3-5) still propagates
  /// unchanged, exactly as every other method on these stores already
  /// documents. Only the three *verification* reads in step 6 are
  /// deliberately caught and turned into
  /// [LocalDeletionFinalizeOutcome.verificationFailed] rather than an
  /// escaping exception -- see that outcome's own doc comment.
  Future<LocalDeletionFinalizeResult> finalize() async {
    final transaction =
        await _syncPersistenceStore.loadPendingDeletionTransaction();
    if (transaction == null) {
      return const LocalDeletionFinalizeResult(
        outcome: LocalDeletionFinalizeOutcome.noPendingTransaction,
      );
    }
    if (transaction.stage != DeletionTransactionStage.localFinalizePending) {
      return const LocalDeletionFinalizeResult(
        outcome: LocalDeletionFinalizeOutcome.notYetAtLocalFinalizeStage,
      );
    }

    final targetFingerprint = transaction.accountFingerprint;

    // Step 2: pre-flight account check -- a pure read, strictly before any
    // mutation of any kind. A non-null marker naming a DIFFERENT account
    // fails this call closed immediately. A `null` marker is allowed
    // through -- see the library doc comment's "Crash-resume" section.
    final preflightMarker =
        await _syncPersistenceStore.loadAssociatedAccountFingerprint();
    if (preflightMarker != null && preflightMarker != targetFingerprint) {
      return const LocalDeletionFinalizeResult(
        outcome: LocalDeletionFinalizeOutcome.accountMismatch,
      );
    }

    // Step 3: clear every pending local sync intent. Device-wide, not
    // fingerprint-scoped -- see `LocalSyncIntentStore`'s own doc comment.
    // Sync *intent* only; never the underlying Kept/Reflection content.
    // Safe to reach here only because step 2 already confirmed the marker
    // is either unset or names exactly this transaction's own account.
    final pendingIntents = await _localSyncIntentStore.loadIntents();
    for (final intent in pendingIntents) {
      await _localSyncIntentStore.removeIntent(intent.intentId);
    }

    // Step 4: the single, already-atomic "smallest correct operation" that
    // removes the target account's entire AccountSyncState bucket --
    // dataEpoch, server change token, every stored record-system-fields
    // value, and the full outbox (which also represents tombstones) -- all
    // in one call. Idempotent: a no-op if no bucket exists.
    await _syncPersistenceStore.clearAccountState(targetFingerprint);

    // Step 5: clear the durable associated-account marker if it still names
    // this transaction's target. An idempotent no-op if already `null`
    // (`AssociatedAccountFingerprintClearStatus.alreadyClear`) -- exactly
    // the crash-resume case where a prior attempt already cleared it.
    final clearMarkerResult =
        await _syncPersistenceStore.clearAssociatedAccountFingerprintIfCurrent(
      expectedCurrent: targetFingerprint,
    );
    final markerCleared = clearMarkerResult.status ==
        AssociatedAccountFingerprintClearStatus.cleared;

    // Step 6: hard runtime verification gate. Ordinary control flow --
    // never Dart's `assert` construct -- so this remains the real
    // correctness gate in
    // release builds too. Any of the three reads disagreeing, or throwing,
    // means the deletion transaction is NOT cleared this call; a future
    // retry re-attempts safely (every step above is idempotent).
    var verified = false;
    try {
      final residualState =
          await _syncPersistenceStore.loadAccountState(targetFingerprint);
      final residualMarker =
          await _syncPersistenceStore.loadAssociatedAccountFingerprint();
      final residualIntents = await _localSyncIntentStore.loadIntents();
      verified = residualState == null &&
          residualMarker == null &&
          residualIntents.isEmpty;
    } catch (_) {
      verified = false;
    }
    if (!verified) {
      return LocalDeletionFinalizeResult(
        outcome: LocalDeletionFinalizeOutcome.verificationFailed,
        clearedIntentCount: pendingIntents.length,
        markerCleared: markerCleared,
      );
    }

    // Step 7: only now, with every prior step durably confirmed complete by
    // step 6's real runtime checks, remove the transaction itself -- last,
    // always.
    await _syncPersistenceStore.clearDeletionTransaction(
      accountFingerprint: targetFingerprint,
    );

    return LocalDeletionFinalizeResult(
      outcome: LocalDeletionFinalizeOutcome.finalized,
      clearedIntentCount: pendingIntents.length,
      markerCleared: markerCleared,
    );
  }
}
