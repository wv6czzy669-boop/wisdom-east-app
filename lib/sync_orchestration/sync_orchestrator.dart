/// Build 26 Phase 4D-2: the isolated CloudKit sync orchestrator.
///
/// Connects three existing, independently-tested layers -- the Phase 4A
/// sync-domain contracts (`lib/sync/`), the Phase 4C CloudKit transport
/// (`lib/sync_platform/`), and the Phase 4D-1 durable local sync
/// persistence (`lib/sync_persistence/`) -- through injected abstractions
/// only. This file invents no new record shape, no new codec, and no new
/// conflict/classification rule of its own: every translation below builds
/// directly on types those three layers already define and validate.
///
/// **Nothing in this file is wired to live application code.** No
/// `KeptRepository`, `SavedReflectionsService`, home screen, `lib/main.dart`,
/// lifecycle observer, account-change listener, or network observer imports
/// or calls anything here -- see
/// `test/sync_orchestration/sync_orchestration_layering_test.dart`. That
/// integration is explicitly Phase 4E's responsibility, not this phase's.
///
/// [SyncOrchestrator.runSyncPass] coordinates exactly one explicit sync
/// pass and never starts automatically, never schedules itself, and never
/// subscribes to `CloudKitPlatformBridge.accountChangeEvents`. A caller
/// (Phase 4E, out of this phase's scope) decides if/when/how often to call
/// it.
///
/// **Crash-consistency correction:** a successful fetch's new server change
/// token is never durably persisted by this phase -- only returned as part
/// of [SyncPassResult.pendingIncomingBatch]. Committing it here, before any
/// future phase durably applies the incoming batch it came with, would
/// create a crash window in which the local checkpoint had advanced past
/// content that was never actually saved -- see [SyncPassResult
/// .pendingIncomingBatch]'s own doc comment. Until a future Phase 4E
/// commits that token (only after durably applying the batch), a repeated
/// pass simply refetches the same, still-unadvanced range from the
/// account's last *committed* token -- redundant, but always safe, and
/// never lossy. The same "durable local effect before durable checkpoint
/// advance" ordering is also applied to this phase's own upload path: a
/// successful save's returned system fields are persisted before that
/// mutation's own acknowledgment is committed (see the upload-outcome
/// handling inside [_runSyncPassOnce] below), so an acknowledgment can never
/// race ahead of the system-fields value a future conflict-safe retry would
/// need.
///
/// **Incoming-batch scope binding:** every incoming batch this phase
/// returns is durably scoped, internally, to the exact account fingerprint,
/// `dataEpoch`, and previous/proposed server-change-token baseline it was
/// fetched against -- see [PendingIncomingSyncBatch]'s own doc comment.
/// This exists so a future Phase 4E can prove a batch still belongs to the
/// account and local sync baseline it came from before ever applying it or
/// committing its checkpoint, and can fail closed on a stale or
/// account-mismatched batch instead of guessing.
///
/// **Build 26 Phase 4E-3a (transport hardening only):** a successful
/// fetch's [CloudKitZoneChangesResult.keptWisdomRecordSystemFields] is now
/// also plumbed straight through into the returned
/// [PendingIncomingSyncBatch.incomingKeptWisdomRecordSystemFields], with no
/// other change to this class's own behavior -- this orchestrator still
/// never applies a record, never checkpoints anything, and still commits
/// nothing beyond what it already committed before this phase.
library;

import '../sync/sync_error_classification.dart';
import '../sync_persistence/account_sync_state.dart';
import '../sync_persistence/persisted_outbox_mutation.dart';
import '../sync_persistence/sync_persistence_store.dart';
import '../sync_platform/cloud_kit_account_snapshot.dart';
import '../sync_platform/cloud_kit_modify_records_contract.dart';
import '../sync_platform/cloud_kit_platform_bridge.dart';
import '../sync_platform/cloud_kit_platform_error.dart';
import '../sync_platform/cloud_kit_zone_changes_contract.dart';
import '../sync_platform/cloud_kit_zone_configuration_result.dart';
import '../utils/kept_diagnostics.dart';
import 'pending_incoming_sync_batch.dart';
import 'sync_pass_result.dart';

/// Coordinates exactly one CloudKit sync pass per [runSyncPass] call, using
/// only injected collaborators.
///
/// Every dependency is provided by the caller -- this class never
/// constructs a `MethodChannelCloudKitPlatformBridge` or a
/// `ProtectedSyncPersistenceStore` itself, and operates only through the
/// [CloudKitPlatformBridge]/[SyncPersistenceStore] abstractions, so it is
/// fully testable with fakes and never touches a real `MethodChannel` or a
/// real CloudKit container.
final class SyncOrchestrator {
  SyncOrchestrator({
    required CloudKitPlatformBridge bridge,
    required SyncPersistenceStore persistenceStore,
  })  : _bridge = bridge,
        _store = persistenceStore;

  final CloudKitPlatformBridge _bridge;
  final SyncPersistenceStore _store;

  Future<SyncPassResult>? _inFlight;

  /// Runs exactly one sync pass: resolve account, configure the private
  /// zone, load local sync state, upload the pending outbox, durably apply
  /// upload outcomes, then fetch private-zone changes -- in that order. See
  /// the class doc comment for what this method never does on its own
  /// (start automatically, subscribe to account-change events, apply
  /// incoming records to a repository).
  ///
  /// **Concurrency:** exactly one pass may be actually running per
  /// [SyncOrchestrator] instance at a time. A call made while a pass is
  /// already in flight returns that exact same [Future] rather than
  /// starting a second, concurrent upload/fetch sequence against the same
  /// persistence state -- consistent with this codebase's existing
  /// single-resource-key serialization precedent
  /// (`PersistenceOperationCoordinator`), applied here at the orchestrator
  /// level instead of the file level.
  Future<SyncPassResult> runSyncPass() {
    final existing = _inFlight;
    if (existing != null) return existing;

    final future = _runSyncPassOnce();
    _inFlight = future;
    future.whenComplete(() {
      // Only clear the marker if it is still this exact pass -- avoids a
      // pathological reset if a future refactor ever reassigns _inFlight
      // from elsewhere.
      if (identical(_inFlight, future)) {
        _inFlight = null;
      }
    });
    return future;
  }

  Future<SyncPassResult> _runSyncPassOnce() async {
    keptDiagnostic('sync-orchestrator: pass-start');

    // -----------------------------------------------------------------
    // 1. Resolve account.
    // -----------------------------------------------------------------
    final CloudKitAccountSnapshot snapshot;
    try {
      snapshot = await _bridge.getAccountSnapshot();
    } on CloudKitPlatformException catch (error) {
      keptDiagnostic('sync-orchestrator: account-snapshot-threw');
      return _classifiedFailure(error.category, cause: error);
    }

    final accountGate = _evaluateAccount(snapshot);
    if (accountGate != null) {
      keptDiagnostic('sync-orchestrator: account-not-usable');
      return accountGate;
    }
    final String fingerprint = snapshot.accountFingerprint!;

    // -----------------------------------------------------------------
    // 2. Configure private zone (through the existing platform
    //    abstraction only -- never a re-implemented fetch-first/
    //    create-fallback algorithm in Dart).
    // -----------------------------------------------------------------
    final CloudKitZoneConfigurationResult zoneResult;
    try {
      zoneResult = await _bridge.configurePrivateZone();
    } on CloudKitPlatformException catch (error) {
      keptDiagnostic('sync-orchestrator: zone-configure-threw');
      return _classifiedFailure(error.category, cause: error);
    }
    if (!zoneResult.success) {
      keptDiagnostic('sync-orchestrator: zone-configure-failed');
      final category = zoneResult.errorCode == null
          ? SyncErrorCategory.permanent
          : classifySyncErrorCode(zoneResult.errorCode!);
      return _classifiedFailure(category, cause: zoneResult);
    }

    // -----------------------------------------------------------------
    // 3. Load account-scoped local sync state. Never fabricates a bucket
    //    or a dataEpoch -- a `null` bucket simply means nothing to upload
    //    and an initial (`previousServerToken: null`) fetch.
    // -----------------------------------------------------------------
    final AccountSyncState? bucket;
    try {
      bucket = await _store.loadAccountState(fingerprint);
    } on SyncPersistenceStoreException catch (error) {
      keptDiagnostic('sync-orchestrator: load-state-failed');
      return SyncPassResult.persistenceFailure(cause: error);
    }

    // -----------------------------------------------------------------
    // Account isolation: re-verify the account identity resolved in step 1
    // has not shifted before any persistence mutation. Fails closed --
    // never writes into, merges, or exposes another account's bucket.
    // -----------------------------------------------------------------
    if (!await _fingerprintStillMatches(fingerprint)) {
      keptDiagnostic('sync-orchestrator: account-changed-mid-pass');
      return SyncPassResult.permanentFailure();
    }

    // -----------------------------------------------------------------
    // 4 & 5. Upload pending outbox, then durably apply outcomes.
    // -----------------------------------------------------------------
    var uploadedRecordCount = 0;
    var acknowledgedCount = 0;
    var failedCount = 0;
    var conflictedCount = 0;

    if (bucket != null && bucket.outbox.isNotEmpty) {
      final List<PersistedOutboxMutation> pending;
      try {
        pending = await _store.readPendingMutations(fingerprint);
      } on SyncPersistenceStoreException catch (error) {
        keptDiagnostic('sync-orchestrator: read-pending-failed');
        return SyncPassResult.persistenceFailure(cause: error);
      }

      // Translate persisted sync-domain mutations into the existing Phase
      // 4C transport request shape only at this orchestration boundary --
      // never a parallel DTO. Deterministic queue order preserved exactly
      // as `readPendingMutations` returned it. No batch-size limit is
      // documented anywhere in the Phase 4C-2 transport contract
      // (`CloudKitModifyRecordsRequest`/native coordinator), so this pass
      // uses one single, deterministically-ordered batch rather than
      // inventing an undocumented limit.
      final inputs = <CloudKitRecordChangeInput>[];
      final mutationIdByRecordName = <String, String>{};
      for (final mutation in pending) {
        final projection = mutation.change.projection;
        inputs.add(
          CloudKitRecordChangeInput.keptWisdom(
            projection,
            previousSystemFields:
                bucket.recordSystemFields[projection.recordName],
          ),
        );
        mutationIdByRecordName[mutation.recordName] = mutation.mutationId;
      }
      uploadedRecordCount = inputs.length;

      final CloudKitModifyRecordsResult modifyResult;
      try {
        modifyResult = await _bridge.modifyPrivateRecords(
          CloudKitModifyRecordsRequest(records: inputs),
        );
      } on CloudKitPlatformException catch (error) {
        keptDiagnostic('sync-orchestrator: upload-threw');
        return _classifiedFailure(error.category, cause: error);
      }

      switch (modifyResult.overallStatus) {
        case CloudKitModifyRecordsOverallStatus.transportFailure:
          keptDiagnostic('sync-orchestrator: upload-transport-failure');
          // No per-record outcome was ever attempted -- the outbox is left
          // completely unchanged: no applyMutationOutcomes call at all,
          // and no fetch.
          final category = modifyResult.errorCode == null
              ? SyncErrorCategory.retryable
              : classifySyncErrorCode(modifyResult.errorCode!);
          return _classifiedFailure(category, cause: modifyResult);

        case CloudKitModifyRecordsOverallStatus.unknown:
          keptDiagnostic('sync-orchestrator: upload-unknown-result');
          return SyncPassResult.permanentFailure(cause: modifyResult);

        case CloudKitModifyRecordsOverallStatus.allSucceeded:
        case CloudKitModifyRecordsOverallStatus.partialFailure:
          final acknowledgedMutationIds = <String>{};
          final updatedStatusByMutationId =
              <String, PersistedOutboxMutationStatus>{};
          final systemFieldsToStore = <String, String>{};

          for (final outcome in modifyResult.outcomes) {
            final mutationId = mutationIdByRecordName[outcome.recordName];
            if (mutationId == null) {
              // An outcome for a record this pass never requested -- never
              // trusted, never acted on.
              continue;
            }
            if (outcome.success) {
              acknowledgedMutationIds.add(mutationId);
              acknowledgedCount += 1;
              final systemFields = outcome.systemFields;
              if (systemFields != null) {
                systemFieldsToStore[outcome.recordName] = systemFields;
              }
            } else {
              final errorCode = outcome.errorCode ?? '';
              if (errorCode == syncErrorCodeServerRecordChanged) {
                updatedStatusByMutationId[mutationId] =
                    PersistedOutboxMutationStatus.conflicted;
                conflictedCount += 1;
              } else {
                final category = classifySyncErrorCode(errorCode);
                if (category == SyncErrorCategory.retryable) {
                  // Leave this exact mutation untouched -- neither
                  // acknowledged nor marked -- the per-record retryable
                  // representation §13.6/ADR-007 already defines.
                  continue;
                }
                updatedStatusByMutationId[mutationId] =
                    PersistedOutboxMutationStatus.failed;
                failedCount += 1;
              }
            }
          }

          // Account isolation checkpoint 2: re-verify before any
          // upload-result persistence mutation, now that the transport call
          // has actually completed (and, if the account changed while that
          // call was in flight, before ever writing this fingerprint's
          // outcome into its bucket).
          if (!await _fingerprintStillMatches(fingerprint)) {
            keptDiagnostic('sync-orchestrator: account-changed-mid-pass');
            return SyncPassResult.permanentFailure();
          }

          // Durable-effect-before-checkpoint ordering: a successful save's
          // returned system fields are persisted *first*, one record at a
          // time, and only once every one of them has durably landed is the
          // corresponding mutationId acknowledged in the single
          // applyMutationOutcomes call below. If persisting a system-fields
          // value fails partway, no mutationId has yet been acknowledged or
          // marked -- every mutation this pass touched, including ones
          // whose own system-fields write already succeeded, simply remains
          // queued exactly as it was; a future pass's upload is still
          // conflict-safe and idempotent using whatever system fields did
          // land. The pass stops here and never reaches the fetch step.
          try {
            for (final entry in systemFieldsToStore.entries) {
              await _store.replaceRecordSystemFields(
                fingerprint,
                entry.key,
                entry.value,
              );
            }
          } on SyncPersistenceStoreException catch (error) {
            keptDiagnostic('sync-orchestrator: system-fields-persist-failed');
            return SyncPassResult.persistenceFailure(cause: error);
          }

          // Only after every returned system-fields value is durable does
          // this pass commit acknowledgment/marking. If this call itself
          // fails, the affected mutations remain queued -- already carrying
          // their newly-persisted system fields from the step above, so the
          // next upload attempt for them is still conflict-safe and
          // idempotent -- and this pass still never reaches the fetch step.
          try {
            await _store.applyMutationOutcomes(
              fingerprint,
              acknowledgedMutationIds: acknowledgedMutationIds,
              updatedStatusByMutationId: updatedStatusByMutationId,
            );
          } on SyncPersistenceStoreException catch (error) {
            keptDiagnostic('sync-orchestrator: apply-outcomes-failed');
            return SyncPassResult.persistenceFailure(cause: error);
          }
      }
    }

    // -----------------------------------------------------------------
    // 6 & 7. Fetch private-zone changes using the persisted opaque token,
    //    then handle success/tokenExpired/failure.
    // -----------------------------------------------------------------
    // Captured once, right at the request boundary, so the pending batch
    // below (on a `success` outcome) can carry the *exact* token this
    // fetch was actually performed against -- never re-derived later from
    // `bucket`, which this pass never mutates before this point anyway,
    // but this keeps the two definitionally identical rather than merely
    // coincidentally so.
    final previousTokenUsedForFetch = bucket?.serverChangeToken;
    final CloudKitZoneChangesResult fetchResult;
    try {
      fetchResult = await _bridge.fetchPrivateZoneChanges(
        CloudKitZoneChangesRequest(
          previousServerToken: previousTokenUsedForFetch,
        ),
      );
    } on CloudKitPlatformException catch (error) {
      keptDiagnostic('sync-orchestrator: fetch-threw');
      return _classifiedFailure(error.category, cause: error);
    }

    switch (fetchResult.outcome) {
      case CloudKitZoneChangesOutcome.success:
        // fetchPrivateZoneChanges already aggregates every page CloudKit
        // reports before returning once (see
        // cloud_kit_zone_changes_contract.dart's own doc comment) -- there
        // is no per-page loop for this orchestrator to run.
        //
        // Crash-consistency correction: this phase never durably persists
        // the new server change token here. Doing so would advance the
        // local checkpoint past an incoming batch this phase itself never
        // durably applies -- see this class's own doc comment and
        // `SyncPassResult.pendingIncomingBatch`. The account bucket
        // (token, outbox, dataEpoch, system fields) is left exactly as it
        // was, whether or not a bucket currently exists; the proposed token
        // is only ever returned to the caller.
        //
        // Incoming-batch scope binding: the returned batch durably carries
        // the fingerprint resolved at pass start, the bucket's exact
        // `dataEpoch` at fetch time (`null` when no bucket existed -- never
        // fabricated), the exact previous token this fetch was performed
        // against, and the proposed next token -- so a future Phase 4E can
        // prove this batch still belongs to the account/epoch/checkpoint
        // baseline it came from before ever applying or committing it. See
        // `PendingIncomingSyncBatch`'s own doc comment for the full
        // validation contract this scope metadata exists to support.
        final pendingBatch = PendingIncomingSyncBatch(
          accountFingerprint: fingerprint,
          baseDataEpoch: bucket?.dataEpoch,
          previousServerChangeToken: previousTokenUsedForFetch,
          pendingServerChangeToken: fetchResult.serverToken,
          incomingKeptWisdomProjections: fetchResult.changedKeptWisdomRecords,
          incomingSyncStateProjections: fetchResult.changedSyncStateRecords,
          // Build 26 Phase 4E-3a: plumbed through unchanged -- this phase
          // never validates, applies, or checkpoints it. See
          // `PendingIncomingSyncBatch.incomingKeptWisdomRecordSystemFields`'s
          // own doc comment.
          incomingKeptWisdomRecordSystemFields:
              fetchResult.keptWisdomRecordSystemFields,
        );
        keptDiagnostic('sync-orchestrator: pass-completed');
        return SyncPassResult.completed(
          uploadedRecordCount: uploadedRecordCount,
          acknowledgedMutationCount: acknowledgedCount,
          permanentlyFailedMutationCount: failedCount,
          conflictedMutationCount: conflictedCount,
          pendingIncomingBatch: pendingBatch,
        );

      case CloudKitZoneChangesOutcome.tokenExpired:
        if (bucket != null) {
          // Account isolation checkpoint 3: re-verify before the one
          // remaining token-expired persistence mutation this pass can
          // still perform.
          if (!await _fingerprintStillMatches(fingerprint)) {
            keptDiagnostic('sync-orchestrator: account-changed-mid-pass');
            return SyncPassResult.permanentFailure();
          }
          try {
            await _store.clearServerChangeToken(fingerprint);
          } on SyncPersistenceStoreException catch (error) {
            keptDiagnostic('sync-orchestrator: clear-token-failed');
            return SyncPassResult.persistenceFailure(cause: error);
          }
        }
        keptDiagnostic('sync-orchestrator: token-expired');
        return SyncPassResult.tokenExpiredNeedsRefetch();

      case CloudKitZoneChangesOutcome.unexpectedPhysicalDeletion:
        keptDiagnostic('sync-orchestrator: unexpected-physical-deletion');
        return SyncPassResult.permanentFailure(cause: fetchResult);

      case CloudKitZoneChangesOutcome.failure:
        keptDiagnostic('sync-orchestrator: fetch-failed');
        final category = fetchResult.errorCode == null
            ? SyncErrorCategory.permanent
            : classifySyncErrorCode(fetchResult.errorCode!);
        return _classifiedFailure(category, cause: fetchResult);

      case CloudKitZoneChangesOutcome.unknown:
        keptDiagnostic('sync-orchestrator: fetch-unknown-result');
        return SyncPassResult.permanentFailure(cause: fetchResult);
    }
  }

  /// Step 1's account gate. Returns a terminal [SyncPassResult] when the
  /// account is not usable for private CloudKit access; returns `null` when
  /// the pass should proceed (an available account with a resolved,
  /// non-empty fingerprint and a usable private database).
  SyncPassResult? _evaluateAccount(CloudKitAccountSnapshot snapshot) {
    switch (snapshot.availability) {
      case CloudKitAccountAvailability.noAccount:
        return SyncPassResult.noAccount();
      case CloudKitAccountAvailability.restricted:
        return SyncPassResult.restricted();
      case CloudKitAccountAvailability.couldNotDetermine:
      case CloudKitAccountAvailability.temporarilyUnavailable:
      case CloudKitAccountAvailability.unknown:
        return SyncPassResult.unavailable();
      case CloudKitAccountAvailability.available:
        if (!snapshot.isPrivateDatabaseUsable ||
            !snapshot.fingerprintResolved ||
            snapshot.accountFingerprint == null ||
            snapshot.accountFingerprint!.isEmpty) {
          return SyncPassResult.unavailable();
        }
        return null;
    }
  }

  /// Account isolation guard: re-resolves the account snapshot and fails
  /// closed (`false`) unless it is still exactly [expectedFingerprint] on
  /// an available account. Never itself mutates persistence -- only gates
  /// whether the caller may proceed to do so.
  Future<bool> _fingerprintStillMatches(String expectedFingerprint) async {
    final CloudKitAccountSnapshot snapshot;
    try {
      snapshot = await _bridge.getAccountSnapshot();
    } on CloudKitPlatformException {
      return false;
    }
    if (snapshot.availability != CloudKitAccountAvailability.available) {
      return false;
    }
    if (!snapshot.fingerprintResolved) return false;
    return snapshot.accountFingerprint == expectedFingerprint;
  }

  SyncPassResult _classifiedFailure(SyncErrorCategory category,
      {Object? cause}) {
    switch (category) {
      case SyncErrorCategory.retryable:
        return SyncPassResult.retryableFailure(cause: cause);
      case SyncErrorCategory.permanent:
        return SyncPassResult.permanentFailure(cause: cause);
      case SyncErrorCategory.accountIssue:
        return SyncPassResult.unavailable();
    }
  }
}
