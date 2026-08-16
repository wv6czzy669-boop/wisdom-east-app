/// Build 26 Phase 5 (slice 1): typed, content-safe results for
/// `SyncPersistenceStore.beginDeletionTransaction`/
/// `advanceDeletionTransactionStage`. Mirrors this codebase's established
/// precedent (`AssociatedAccountFingerprintCommitResult`,
/// `RetireOutboxMutationResult`) of a status enum plus optional payload,
/// rather than a thrown exception, for every ordinary business-rule outcome.
library;

import 'pending_deletion_transaction.dart';

/// The categorical, content-safe result of one
/// `SyncPersistenceStore.beginDeletionTransaction` call.
enum BeginDeletionTransactionStatus {
  /// No transaction existed yet for this account; one was freshly created,
  /// with a newly-generated
  /// [PendingDeletionTransaction.replacementDataEpoch], at
  /// [DeletionTransactionStage.prepared].
  started,

  /// A transaction already existed for exactly this account fingerprint --
  /// returned unchanged (its own
  /// [PendingDeletionTransaction.replacementDataEpoch] and
  /// [PendingDeletionTransaction.stage] are never regenerated or reset). An
  /// idempotent resume, never a second, competing transaction.
  resumedExisting,

  /// A transaction already exists for a *different* account fingerprint.
  /// Refused -- a deletion transaction is never silently retargeted to a
  /// different account, and this call performs zero mutation.
  accountMismatch,

  /// The `accountFingerprint` argument does not look like an opaque account
  /// fingerprint.
  invalidFingerprint,
}

final class BeginDeletionTransactionResult {
  const BeginDeletionTransactionResult({
    required this.status,
    this.transaction,
  });

  final BeginDeletionTransactionStatus status;

  /// Populated for [BeginDeletionTransactionStatus.started]/
  /// [BeginDeletionTransactionStatus.resumedExisting] only; `null` for every
  /// refusal status.
  final PendingDeletionTransaction? transaction;

  /// A privacy-safe summary: status and stage only -- never a fingerprint or
  /// an epoch value.
  Map<String, Object?> toLogSafeSummary() => {
        'status': status.name,
        if (transaction != null) 'stage': transaction!.stage.name,
      };

  @override
  String toString() => 'BeginDeletionTransactionResult(${toLogSafeSummary()})';
}

/// The categorical, content-safe result of one
/// `SyncPersistenceStore.advanceDeletionTransactionStage` call.
enum AdvanceDeletionTransactionStatus {
  /// The transaction's stage is now durably the requested next stage --
  /// whether this call itself just wrote it, or the transaction already
  /// matched exactly (an idempotent no-op repeat).
  advanced,

  /// No transaction currently exists -- nothing to advance.
  noTransaction,

  /// The existing transaction targets a different account fingerprint than
  /// the one this call named. Refused -- zero mutation.
  accountMismatch,

  /// The existing transaction's current stage does not equal the caller's
  /// expected current stage.
  stageMismatch,

  /// The requested `expectedCurrentStage -> nextStage` transition is not an
  /// allowed transition (see `isValidDeletionTransactionTransition`).
  invalidTransition,
}

final class AdvanceDeletionTransactionResult {
  const AdvanceDeletionTransactionResult({
    required this.status,
    this.transaction,
  });

  final AdvanceDeletionTransactionStatus status;

  /// Populated for [AdvanceDeletionTransactionStatus.advanced] only.
  final PendingDeletionTransaction? transaction;

  /// A privacy-safe summary: status and stage only -- never a fingerprint or
  /// an epoch value.
  Map<String, Object?> toLogSafeSummary() => {
        'status': status.name,
        if (transaction != null) 'stage': transaction!.stage.name,
      };

  @override
  String toString() =>
      'AdvanceDeletionTransactionResult(${toLogSafeSummary()})';
}
