/// Build 26 Phase 5 (slice 2): the categorical, content-safe result of one
/// [CloudKitRemoteDeletionRunner.run] call. Mirrors this codebase's
/// established precedent (`SyncRuntimeOutcome`, `BootstrapRunStatus`,
/// `AdvanceDeletionTransactionStatus`) of a small, closed status enum rather
/// than a thrown exception for every ordinary business-rule outcome.
library;

import '../sync_persistence/pending_deletion_transaction.dart';

/// The categorical outcome of one deletion-runner invocation.
enum RemoteDeletionRunOutcome {
  /// No [PendingDeletionTransaction] exists. Zero destructive work was
  /// attempted -- this call did not even resolve an account snapshot.
  noPendingTransaction,

  /// The durable deletion-transaction record exists but could not be safely
  /// decoded/validated (mirrors
  /// `SyncRuntimeOutcome.deletionStateCorrupted`'s own reasoning). Zero
  /// destructive work was attempted.
  deletionStateCorrupted,

  /// The current CloudKit account is not usable right now (no account,
  /// restricted, temporarily unavailable, or an unresolved fingerprint).
  /// Zero destructive work was attempted; the transaction is untouched.
  waitingForAccount,

  /// The current account's fingerprint does not match
  /// [PendingDeletionTransaction.accountFingerprint]. Zero destructive work
  /// was attempted; the transaction is never silently retargeted.
  accountMismatch,

  /// A transient failure occurred -- safe to call [run] again later.
  retryableFailure,

  /// A failure requires a real state change before retrying could possibly
  /// help -- never automatically retried by a timer.
  terminalFailure,

  /// The remote `CKEastSyncState` carried an epoch this transaction cannot
  /// prove it still safely owns (neither the transaction's own
  /// [PendingDeletionTransaction.originalDataEpoch] nor
  /// [PendingDeletionTransaction.replacementDataEpoch]). Fails closed: no
  /// remote mutation was attempted, the transaction is untouched.
  epochConflict,

  /// This call made forward progress (advanced a durable stage, or
  /// completed a purge/verification pass that still needs another pass) but
  /// did not reach [DeletionTransactionStage.localFinalizePending]. Safe,
  /// and expected, to call [run] again.
  progressed,

  /// This call durably reached
  /// [DeletionTransactionStage.localFinalizePending] for the first time.
  /// The transaction is deliberately left in place -- a future Phase 5
  /// slice owns clearing it and performing local detach.
  reachedLocalFinalizePending,

  /// The transaction was already at
  /// [DeletionTransactionStage.localFinalizePending] before this call --
  /// nothing left for this slice's runner to do. Zero CloudKit calls were
  /// made this invocation.
  alreadyAtLocalFinalizePending,
}

/// A privacy-safe, immutable result of one [CloudKitRemoteDeletionRunner.run]
/// call.
final class RemoteDeletionRunResult {
  const RemoteDeletionRunResult({required this.outcome, this.stage});

  final RemoteDeletionRunOutcome outcome;

  /// The transaction's durable stage as of the end of this call, if a
  /// transaction exists. `null` for [RemoteDeletionRunOutcome
  /// .noPendingTransaction] and [RemoteDeletionRunOutcome
  /// .deletionStateCorrupted] (there is nothing safely known to report).
  final DeletionTransactionStage? stage;

  /// A privacy-safe summary: outcome and stage only -- never an account
  /// fingerprint or an epoch value.
  Map<String, Object?> toLogSafeSummary() => {
        'outcome': outcome.name,
        if (stage != null) 'stage': stage!.name,
      };

  @override
  String toString() => 'RemoteDeletionRunResult(${toLogSafeSummary()})';
}
