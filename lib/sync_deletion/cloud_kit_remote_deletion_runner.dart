/// Build 26 Phase 5 (slice 2): the remote CloudKit deletion runner for
/// "Remove from iCloud". Resumes the durable [PendingDeletionTransaction]
/// Slice 1 established, and performs -- exactly as far as it can safely go
/// in one call -- the sequence: fresh remote `dataEpoch` barrier, physical
/// `CKKeptWisdom` purge, zero-record verification. Stops durably at
/// [DeletionTransactionStage.localFinalizePending]; never clears the
/// transaction, never touches local Kept/Reflection storage, never detaches
/// the local iCloud association -- all three are a future slice's scope.
///
/// **This file is not `SyncOrchestrator` and is never merged into it.**
/// `SyncOrchestrator.runSyncPass` performs Phase 4's ordinary upload/
/// download sync pass; this runner performs a categorically different,
/// one-directional, destructive remote purge that must never run
/// concurrently with -- and must never be confused with -- normal sync.
/// The existing `CloudKitSyncRuntimeCoordinator` gate already ensures normal
/// bootstrap/sync never runs while a deletion transaction exists (Slice 1);
/// this runner is this transaction's own, entirely separate pipeline, with
/// its own caller (a future slice's scope, not this one).
///
/// **Idempotency/crash-safety.** Every durable stage transition happens only
/// after its own remote step is independently confirmed (by a fresh read,
/// never an assumption) -- see the per-stage handlers below for the exact
/// crash-recovery reasoning at each step. Calling [run] repeatedly,
/// including immediately after a mid-stage crash, is always safe: it either
/// makes forward progress or safely reports why it could not, and never
/// performs a remote mutation whose safety it cannot prove from durable
/// state and a fresh remote read alone.
///
/// **No polling, no timers.** [run] performs a small, bounded amount of
/// internal work (see [_maxVerificationIterationsPerRun]) and returns --
/// exactly like every other coordinator in this codebase, this runner never
/// schedules itself. A future slice's own trigger decides if/when to call
/// [run] again.
library;

import 'package:uuid/uuid.dart';

import '../sync/cloud_east_sync_state_projection.dart';
import '../sync/sync_error_classification.dart';
import '../sync_persistence/deletion_transaction_result.dart';
import '../sync_persistence/pending_deletion_transaction.dart';
import '../sync_persistence/sync_persistence_store.dart';
import '../sync_platform/cloud_kit_account_snapshot.dart';
import '../sync_platform/cloud_kit_delete_records_contract.dart';
import '../sync_platform/cloud_kit_kept_wisdom_record_names_contract.dart';
import '../sync_platform/cloud_kit_modify_records_contract.dart';
import '../sync_platform/cloud_kit_platform_bridge.dart';
import '../sync_platform/cloud_kit_platform_error.dart';
import '../sync_platform/cloud_kit_sync_state_epoch_contract.dart';
import 'remote_deletion_run_result.dart';

/// Internal, private "did this stage step advance, or fail" result --
/// never exposed outside this file.
class _StageStepOutcome {
  const _StageStepOutcome._({this.advancedTransaction, this.failureOutcome});

  factory _StageStepOutcome.advanced(PendingDeletionTransaction transaction) =>
      _StageStepOutcome._(advancedTransaction: transaction);

  factory _StageStepOutcome.failure(RemoteDeletionRunOutcome outcome) =>
      _StageStepOutcome._(failureOutcome: outcome);

  final PendingDeletionTransaction? advancedTransaction;
  final RemoteDeletionRunOutcome? failureOutcome;
}

final class CloudKitRemoteDeletionRunner {
  CloudKitRemoteDeletionRunner({
    required CloudKitPlatformBridge bridge,
    required SyncPersistenceStore persistenceStore,
    String Function()? mutationIdFactory,
  })  : _bridge = bridge,
        _store = persistenceStore,
        _mutationIdFactory = mutationIdFactory ?? (() => const Uuid().v4());

  final CloudKitPlatformBridge _bridge;
  final SyncPersistenceStore _store;
  final String Function() _mutationIdFactory;

  /// CloudKit's own per-operation record-count ceiling is 400; this batches
  /// well under that with headroom, matching this codebase's convention of
  /// never relying on the exact platform limit.
  static const int _maxRecordNamesPerDeleteBatch = 300;

  /// Bounded per-invocation verification retry -- query, purge any newly
  /// discovered stale records, query again -- so a single call can never
  /// loop unboundedly. After this many iterations without reaching zero
  /// records, this call returns [RemoteDeletionRunOutcome.progressed]; a
  /// future trigger calls [run] again.
  static const int _maxVerificationIterationsPerRun = 3;

  /// Runs exactly as far as it safely can, once, and returns. Never throws:
  /// every failure mode -- persistence corruption, account unavailability,
  /// account mismatch, or any CloudKit transport failure -- is reported as a
  /// typed, content-safe [RemoteDeletionRunResult].
  Future<RemoteDeletionRunResult> run() async {
    final PendingDeletionTransaction? transaction;
    try {
      transaction = await _store.loadPendingDeletionTransaction();
    } catch (_) {
      // Mirrors `SyncRuntimeOutcome.deletionStateCorrupted`'s own reasoning
      // (see cloud_kit_sync_runtime_coordinator.dart): a persisted record
      // that exists but cannot be safely decoded/validated must never be
      // treated as "no transaction" -- it is reported distinctly, and
      // nothing below this point ever runs.
      return const RemoteDeletionRunResult(
        outcome: RemoteDeletionRunOutcome.deletionStateCorrupted,
      );
    }

    if (transaction == null) {
      return const RemoteDeletionRunResult(
        outcome: RemoteDeletionRunOutcome.noPendingTransaction,
      );
    }

    if (transaction.stage == DeletionTransactionStage.localFinalizePending) {
      // Nothing left for this slice's runner to do. Deliberately zero
      // CloudKit calls -- not even an account-snapshot read -- and the
      // transaction is left completely untouched (clearing it is a future
      // slice's scope).
      return RemoteDeletionRunResult(
        outcome: RemoteDeletionRunOutcome.alreadyAtLocalFinalizePending,
        stage: transaction.stage,
      );
    }

    // Account safety: resolved fresh, before any remote work below, for
    // every trigger of this call. Never retargets the transaction --  a
    // mismatch or unavailable account is reported and the transaction is
    // left exactly as it was.
    final CloudKitAccountSnapshot snapshot;
    try {
      snapshot = await _bridge.getAccountSnapshot();
    } on CloudKitPlatformException catch (error) {
      return RemoteDeletionRunResult(
        outcome: _classify(error),
        stage: transaction.stage,
      );
    }
    if (snapshot.availability != CloudKitAccountAvailability.available ||
        !snapshot.fingerprintResolved) {
      return RemoteDeletionRunResult(
        outcome: RemoteDeletionRunOutcome.waitingForAccount,
        stage: transaction.stage,
      );
    }
    if (snapshot.accountFingerprint != transaction.accountFingerprint) {
      return RemoteDeletionRunResult(
        outcome: RemoteDeletionRunOutcome.accountMismatch,
        stage: transaction.stage,
      );
    }

    // Ensure the private zone exists -- idempotent, exactly like every
    // other caller of this same bridge method.
    try {
      final zoneResult = await _bridge.configurePrivateZone();
      if (!zoneResult.success) {
        return RemoteDeletionRunResult(
          outcome: RemoteDeletionRunOutcome.retryableFailure,
          stage: transaction.stage,
        );
      }
    } on CloudKitPlatformException catch (error) {
      return RemoteDeletionRunResult(
        outcome: _classify(error),
        stage: transaction.stage,
      );
    }

    var currentTransaction = transaction;
    while (true) {
      switch (currentTransaction.stage) {
        case DeletionTransactionStage.prepared:
          // The intention to begin the remote barrier phase must be durable
          // before any remote mutation is attempted -- no destructive
          // CloudKit call has happened yet at this point.
          final step = await _advanceTo(
            currentTransaction,
            DeletionTransactionStage.epochBarrierPending,
          );
          if (step.advancedTransaction == null) {
            return RemoteDeletionRunResult(
              outcome: step.failureOutcome!,
              stage: currentTransaction.stage,
            );
          }
          currentTransaction = step.advancedTransaction!;
          continue;

        case DeletionTransactionStage.epochBarrierPending:
          final step = await _runEpochBarrier(currentTransaction);
          if (step.advancedTransaction == null) {
            return RemoteDeletionRunResult(
              outcome: step.failureOutcome!,
              stage: currentTransaction.stage,
            );
          }
          currentTransaction = step.advancedTransaction!;
          continue;

        case DeletionTransactionStage.cloudPurgePending:
          final step = await _runPurge(currentTransaction);
          if (step.advancedTransaction == null) {
            return RemoteDeletionRunResult(
              outcome: step.failureOutcome!,
              stage: currentTransaction.stage,
            );
          }
          currentTransaction = step.advancedTransaction!;
          continue;

        case DeletionTransactionStage.verificationPending:
          return _runVerification(currentTransaction);

        case DeletionTransactionStage.localFinalizePending:
          // Reached this pass, this call -- report success once, here.
          return RemoteDeletionRunResult(
            outcome: RemoteDeletionRunOutcome.reachedLocalFinalizePending,
            stage: currentTransaction.stage,
          );
      }
    }
  }

  // ---------------------------------------------------------------------
  // epochBarrierPending
  // ---------------------------------------------------------------------

  /// Establishes the transaction's already-persisted [PendingDeletionTransaction
  /// .replacementDataEpoch] as the authoritative epoch in `CKEastSyncState`.
  /// Never generates a new epoch. Handles all three documented crash cases:
  ///
  /// A. Crash before the remote save: the durable stage is still
  ///    `epochBarrierPending`, so a later call re-enters this method and
  ///    retries the exact same save (never a fresh epoch).
  /// B. The remote save already succeeded, but a prior call crashed before
  ///    its own durable stage advance: the fresh read below observes the
  ///    remote epoch already equals [PendingDeletionTransaction
  ///    .replacementDataEpoch] -- treated as an idempotent success, and this
  ///    method advances the durable stage without ever saving again.
  /// C. The remote epoch is neither the transaction's own recorded
  ///    [PendingDeletionTransaction.originalDataEpoch] nor its
  ///    [PendingDeletionTransaction.replacementDataEpoch] -- this
  ///    transaction cannot prove it still safely owns the operation. Fails
  ///    closed with [RemoteDeletionRunOutcome.epochConflict]; no remote
  ///    mutation is attempted.
  Future<_StageStepOutcome> _runEpochBarrier(
    PendingDeletionTransaction transaction,
  ) async {
    final CloudKitSyncStateEpochResult epochResult;
    try {
      epochResult = await _bridge.fetchSyncStateEpoch();
    } on CloudKitPlatformException catch (error) {
      return _StageStepOutcome.failure(_classify(error));
    }

    switch (epochResult.outcome) {
      case CloudKitSyncStateEpochOutcome.failure:
      case CloudKitSyncStateEpochOutcome.unknown:
        return _StageStepOutcome.failure(
          RemoteDeletionRunOutcome.retryableFailure,
        );

      case CloudKitSyncStateEpochOutcome.notFound:
        // No CKEastSyncState exists yet -- nothing to conflict with. Safe
        // to create it unconditionally with the replacement epoch as its
        // very first value.
        return _writeReplacementEpoch(transaction, previousSystemFields: null);

      case CloudKitSyncStateEpochOutcome.found:
        final remoteEpoch = epochResult.dataEpoch!;
        if (remoteEpoch == transaction.replacementDataEpoch) {
          // Case B: idempotent success. Never re-saves.
          return _advanceTo(
            transaction,
            DeletionTransactionStage.cloudPurgePending,
          );
        }
        final expected = transaction.originalDataEpoch;
        if (expected == null || remoteEpoch == expected) {
          return _writeReplacementEpoch(
            transaction,
            previousSystemFields: epochResult.systemFields,
          );
        }
        // Case C.
        return _StageStepOutcome.failure(
          RemoteDeletionRunOutcome.epochConflict,
        );
    }
  }

  Future<_StageStepOutcome> _writeReplacementEpoch(
    PendingDeletionTransaction transaction, {
    required String? previousSystemFields,
  }) async {
    final projection = CloudEastSyncStateProjection.current(
      dataEpoch: transaction.replacementDataEpoch,
      mutationId: _mutationIdFactory(),
    );
    final request = CloudKitModifyRecordsRequest(
      records: [
        CloudKitRecordChangeInput.syncState(
          projection,
          previousSystemFields: previousSystemFields,
        ),
      ],
    );

    final CloudKitModifyRecordsResult result;
    try {
      result = await _bridge.modifyPrivateRecords(request);
    } on CloudKitPlatformException catch (error) {
      return _StageStepOutcome.failure(_classify(error));
    }

    switch (result.overallStatus) {
      case CloudKitModifyRecordsOverallStatus.allSucceeded:
        return _advanceTo(
          transaction,
          DeletionTransactionStage.cloudPurgePending,
        );

      case CloudKitModifyRecordsOverallStatus.partialFailure:
        final outcome = result.outcomes.isEmpty ? null : result.outcomes.first;
        if (outcome != null &&
            outcome.errorCode == syncErrorCodeServerRecordChanged) {
          // Someone else wrote the control record concurrently -- re-read
          // once before deciding anything; never blindly overwrite.
          return _reconcileAfterEpochConflict(transaction);
        }
        return _StageStepOutcome.failure(
          RemoteDeletionRunOutcome.retryableFailure,
        );

      case CloudKitModifyRecordsOverallStatus.transportFailure:
      case CloudKitModifyRecordsOverallStatus.unknown:
        return _StageStepOutcome.failure(
          RemoteDeletionRunOutcome.retryableFailure,
        );
    }
  }

  Future<_StageStepOutcome> _reconcileAfterEpochConflict(
    PendingDeletionTransaction transaction,
  ) async {
    final CloudKitSyncStateEpochResult reread;
    try {
      reread = await _bridge.fetchSyncStateEpoch();
    } on CloudKitPlatformException catch (error) {
      return _StageStepOutcome.failure(_classify(error));
    }
    if (reread.outcome == CloudKitSyncStateEpochOutcome.found &&
        reread.dataEpoch == transaction.replacementDataEpoch) {
      return _advanceTo(
        transaction,
        DeletionTransactionStage.cloudPurgePending,
      );
    }
    return _StageStepOutcome.failure(RemoteDeletionRunOutcome.epochConflict);
  }

  // ---------------------------------------------------------------------
  // cloudPurgePending
  // ---------------------------------------------------------------------

  /// Deletes every discoverable `CKKeptWisdom` record. The replacement
  /// epoch barrier is already durably confirmed by the time this stage is
  /// ever reached -- the stage machine itself is the guarantee, no
  /// redundant re-check is performed here. A partial failure leaves the
  /// durable stage unchanged (still `cloudPurgePending`), so a retry simply
  /// re-lists and re-attempts -- an already-deleted record is treated
  /// idempotently (a `syncErrorCodeUnknownItem` per-record outcome is never
  /// treated as a failure that blocks advancing).
  Future<_StageStepOutcome> _runPurge(
    PendingDeletionTransaction transaction,
  ) async {
    final CloudKitKeptWisdomRecordNamesResult listResult;
    try {
      listResult = await _bridge.listKeptWisdomRecordNames();
    } on CloudKitPlatformException catch (error) {
      return _StageStepOutcome.failure(_classify(error));
    }
    if (listResult.outcome != CloudKitKeptWisdomRecordNamesOutcome.success) {
      return _StageStepOutcome.failure(
        RemoteDeletionRunOutcome.retryableFailure,
      );
    }
    if (listResult.recordNames.isEmpty) {
      return _advanceTo(
        transaction,
        DeletionTransactionStage.verificationPending,
      );
    }

    final deleted = await _deleteAllIdempotently(listResult.recordNames);
    if (!deleted) {
      return _StageStepOutcome.failure(
        RemoteDeletionRunOutcome.retryableFailure,
      );
    }
    return _advanceTo(
      transaction,
      DeletionTransactionStage.verificationPending,
    );
  }

  /// Deletes every entry of [recordNames], in CloudKit-safe batches,
  /// treating an already-absent record (`syncErrorCodeUnknownItem`) as an
  /// idempotent non-failure. Returns `false` on the first batch that could
  /// not be fully, idempotently resolved -- never throws.
  Future<bool> _deleteAllIdempotently(List<String> recordNames) async {
    for (var offset = 0;
        offset < recordNames.length;
        offset += _maxRecordNamesPerDeleteBatch) {
      final end = offset + _maxRecordNamesPerDeleteBatch < recordNames.length
          ? offset + _maxRecordNamesPerDeleteBatch
          : recordNames.length;
      final batch = recordNames.sublist(offset, end);

      final CloudKitDeleteKeptWisdomRecordsResult result;
      try {
        result = await _bridge.deleteKeptWisdomRecords(
          CloudKitDeleteKeptWisdomRecordsRequest(recordNames: batch),
        );
      } on CloudKitPlatformException {
        return false;
      }

      switch (result.overallStatus) {
        case CloudKitDeleteRecordsOverallStatus.allSucceeded:
          continue;
        case CloudKitDeleteRecordsOverallStatus.partialFailure:
          final allIdempotent = result.outcomes.every(
            (outcome) =>
                outcome.success ||
                outcome.errorCode == syncErrorCodeUnknownItem,
          );
          if (!allIdempotent) return false;
          continue;
        case CloudKitDeleteRecordsOverallStatus.transportFailure:
        case CloudKitDeleteRecordsOverallStatus.unknown:
          return false;
      }
    }
    return true;
  }

  // ---------------------------------------------------------------------
  // verificationPending
  // ---------------------------------------------------------------------

  /// Queries CloudKit independently. Zero remaining `CKKeptWisdom` records
  /// durably advances to `localFinalizePending` and stops. A nonzero count
  /// is purged (handles a stale second device racing a new record in after
  /// the first purge pass) and re-queried, bounded by
  /// [_maxVerificationIterationsPerRun] so a single call can never loop
  /// unboundedly -- the durable stage is never regressed to
  /// `cloudPurgePending` (the transition allowlist is forward-only by
  /// design); it remains `verificationPending` throughout every iteration
  /// of this bounded loop, and remains `verificationPending` if the bound is
  /// exhausted without reaching zero.
  Future<RemoteDeletionRunResult> _runVerification(
    PendingDeletionTransaction transaction,
  ) async {
    for (var iteration = 0;
        iteration < _maxVerificationIterationsPerRun;
        iteration++) {
      final CloudKitKeptWisdomRecordNamesResult listResult;
      try {
        listResult = await _bridge.listKeptWisdomRecordNames();
      } on CloudKitPlatformException catch (error) {
        return RemoteDeletionRunResult(
          outcome: _classify(error),
          stage: transaction.stage,
        );
      }
      if (listResult.outcome != CloudKitKeptWisdomRecordNamesOutcome.success) {
        return RemoteDeletionRunResult(
          outcome: RemoteDeletionRunOutcome.retryableFailure,
          stage: transaction.stage,
        );
      }

      if (listResult.recordNames.isEmpty) {
        final step = await _advanceTo(
          transaction,
          DeletionTransactionStage.localFinalizePending,
        );
        if (step.advancedTransaction == null) {
          return RemoteDeletionRunResult(
            outcome: step.failureOutcome!,
            stage: transaction.stage,
          );
        }
        return RemoteDeletionRunResult(
          outcome: RemoteDeletionRunOutcome.reachedLocalFinalizePending,
          stage: DeletionTransactionStage.localFinalizePending,
        );
      }

      final deleted = await _deleteAllIdempotently(listResult.recordNames);
      if (!deleted) {
        return RemoteDeletionRunResult(
          outcome: RemoteDeletionRunOutcome.retryableFailure,
          stage: transaction.stage,
        );
      }
      // Loop again to re-verify -- stage remains verificationPending.
    }

    // Bound exhausted without reaching zero. Never treated as failure or
    // success -- a future trigger will call run() again.
    return RemoteDeletionRunResult(
      outcome: RemoteDeletionRunOutcome.progressed,
      stage: transaction.stage,
    );
  }

  // ---------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------

  Future<_StageStepOutcome> _advanceTo(
    PendingDeletionTransaction transaction,
    DeletionTransactionStage nextStage,
  ) async {
    final result = await _store.advanceDeletionTransactionStage(
      accountFingerprint: transaction.accountFingerprint,
      expectedCurrentStage: transaction.stage,
      nextStage: nextStage,
    );
    if (result.status != AdvanceDeletionTransactionStatus.advanced ||
        result.transaction == null) {
      // A structural inconsistency (a concurrent mutation elsewhere) --
      // never assumed safe to proceed from. Fails closed.
      return _StageStepOutcome.failure(
          RemoteDeletionRunOutcome.terminalFailure);
    }
    return _StageStepOutcome.advanced(result.transaction!);
  }

  RemoteDeletionRunOutcome _classify(CloudKitPlatformException exception) {
    switch (exception.category) {
      case SyncErrorCategory.accountIssue:
        return RemoteDeletionRunOutcome.waitingForAccount;
      case SyncErrorCategory.retryable:
        return RemoteDeletionRunOutcome.retryableFailure;
      case SyncErrorCategory.permanent:
        return RemoteDeletionRunOutcome.terminalFailure;
    }
  }
}
