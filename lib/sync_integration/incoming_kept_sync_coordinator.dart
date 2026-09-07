/// Build 26 Phase 4E-3b: the incoming-CloudKit-merge, conflict-cleanup, and
/// crash-safe-checkpoint transaction a [PendingIncomingSyncBatch] (Phase
/// 4D-2's own return value, never yet consumed by any production code path)
/// is durably applied through.
///
/// Deliberately a **separate** class from [KeptSyncIntegrationCoordinator]
/// -- that class owns the *outgoing* local-mutation -> durable-intent ->
/// outbox path; this class owns the *incoming* fetched-batch -> resolved
/// Kept envelope -> loser-cleanup -> checkpoint path. Composing two focused
/// coordinators over the same shared lock (see [resourceKey] below) is
/// preferred here to bloating [KeptSyncIntegrationCoordinator] with a second,
/// unrelated transaction shape.
///
/// **Locking.** [applyIncomingBatch] acquires the *same* production
/// [PersistenceOperationCoordinator] instance and the exact same
/// [resourceKey] string (`kept_sync_integration_v1`) that
/// [KeptSyncIntegrationCoordinator] already uses -- see
/// `lib/services/app_services.dart`'s wiring. This is what serializes an
/// incoming apply against every outgoing user mutation, every
/// [KeptSyncIntegrationCoordinator.reconcileForAssociatedAccount] step, and
/// every other concurrent incoming apply, with zero risk of the two
/// coordinator types racing each other over the same durable Kept/intent/
/// outbox state. [resourceKey] is **not** imported from
/// [KeptSyncIntegrationCoordinator] (to keep this file's own dependency list
/// narrow -- see below); a dedicated test instead proves the two string
/// constants stay equal.
///
/// **Dependencies are deliberately narrow:** [PersistenceOperationCoordinator]
/// (shared instance), [KeptRepository] (via its Phase 4E-3b
/// [KeptRepository.loadAllRecords]/[KeptRepository.replaceAllRecords]
/// surface only -- never its user-mutation methods), [LocalSyncIntentStore],
/// [SyncPersistenceStore], the existing sync-domain/conflict types
/// ([CloudKeptWisdomProjection], [resolveKeptWisdomConflict],
/// [SyncTombstone], [DataEpoch]), [deriveIncomingKeptLocalId], and
/// [PendingIncomingSyncBatch] itself. This file imports no UI, screen,
/// widget, `SavedReflectionsService`, native CloudKit bridge, or lifecycle/
/// network/startup code -- see
/// `test/sync_integration/incoming_kept_sync_coordinator_layering_test.dart`.
///
/// **Scope.** This phase performs no account bootstrap transition (Phase
/// 4E-4's own responsibility -- an incomplete bucket is simply rejected,
/// untouched), and is never called automatically by any production code
/// path -- [applyIncomingBatch] is callable but uncalled, exactly like
/// [KeptSyncIntegrationCoordinator.reconcileForAssociatedAccount] and
/// `SyncOrchestrator.runSyncPass` were before their own callers existed.
library;

import '../models/kept_record.dart';
import '../persistence/persistence_operation_coordinator.dart';
import '../repositories/kept_repository.dart';
import '../sync/cloud_kept_wisdom_projection.dart';
import '../sync/conflict_resolution.dart';
import '../sync/data_epoch.dart';
import '../sync/sync_record_identity.dart';
import '../sync/sync_change.dart';
import '../sync/sync_tombstone.dart';
import '../sync_orchestration/pending_incoming_sync_batch.dart';
import '../sync_persistence/account_sync_state.dart';
import '../sync_persistence/incoming_batch_checkpoint.dart';
import '../sync_persistence/outbox_mutation_retirement.dart';
import '../sync_persistence/sync_persistence_store.dart';
import '../utils/remote_kept_identity.dart';
import 'local_sync_intent.dart';
import 'local_sync_intent_store.dart';

/// The categorical, content-safe outcome of one
/// [IncomingKeptSyncCoordinator.applyIncomingBatch] call.
enum IncomingApplyStatus {
  /// The batch was durably applied: the complete Kept envelope was
  /// replaced, every losing/converged local intent and outbox mutation was
  /// retired, and the checkpoint (system fields + pending server token)
  /// committed.
  applied,

  /// The persisted server change token already equals
  /// [PendingIncomingSyncBatch.pendingServerChangeToken] -- this exact batch
  /// was already durably applied by a prior attempt. Nothing was read
  /// beyond the account bucket itself, and nothing was touched.
  alreadyApplied,

  /// No account bucket exists yet for
  /// [PendingIncomingSyncBatch.accountFingerprint]. Rejected untouched --
  /// Phase 4E-4 owns bucket creation.
  bucketMissing,

  /// The bucket exists but its [AccountSyncState.bootstrapState] is not
  /// [AccountBootstrapState.complete]. Rejected untouched -- Phase 4E-4 owns
  /// every bootstrap transition.
  bootstrapNotComplete,

  /// The bucket's current [AccountSyncState.dataEpoch] does not equal
  /// [PendingIncomingSyncBatch.baseDataEpoch]. Rejected untouched.
  dataEpochMismatch,

  /// The persisted server change token matches neither
  /// [PendingIncomingSyncBatch.previousServerChangeToken] nor
  /// [PendingIncomingSyncBatch.pendingServerChangeToken] -- a stale batch,
  /// fetched against a baseline this account has already moved past (or
  /// never had). Rejected untouched; never invents or advances a token.
  staleBatch,

  /// [PendingIncomingSyncBatch.pendingServerChangeToken] is `null` or empty.
  /// Rejected untouched.
  missingPendingToken,

  /// [PendingIncomingSyncBatch.incomingSyncStateProjections] is non-empty.
  /// Phase 4E-3b never processes `CKEastSyncState` control records --
  /// epoch/reset handling is Phase 4E-4+ work. The entire batch is rejected
  /// untouched, never partially applied.
  controlRecordsRejected,

  /// Two incoming Kept projections in the same batch share a `recordName`.
  /// Rejected untouched.
  duplicateRecordName,

  /// Two incoming active-form Kept projections in the same batch share a
  /// `revealId`. Rejected untouched.
  duplicateRevealId,

  /// [PendingIncomingSyncBatch.incomingKeptWisdomRecordSystemFields] is not
  /// in exact 1:1 correspondence with
  /// [PendingIncomingSyncBatch.incomingKeptWisdomProjections] (a missing
  /// entry, an orphaned extra entry, or an empty value). Rejected untouched.
  systemFieldsMismatch,

  /// Resolving one or more incoming records against their local candidates
  /// produced [ConflictReason.bothEpochsStale] or
  /// [ConflictReason.immutableFieldMismatch] -- the entire batch is aborted
  /// before any Kept write, never partially applied.
  conflictAborted,

  /// The Kept envelope replace, an intent/outbox read, or the checkpoint
  /// call itself threw an underlying storage exception.
  persistenceFailure,

  /// The Kept envelope replace and loser cleanup completed, but the final
  /// [SyncPersistenceStore.commitIncomingBatchCheckpoint] call did not
  /// report [IncomingCheckpointStatus.committed] (or threw). The persisted
  /// token remains whatever it was before this call -- a future retry
  /// reloads everything fresh and safely completes the remaining cleanup/
  /// checkpoint (see the library doc comment on crash-safe ordering).
  checkpointFailed,
}

/// The full, content-safe result of one
/// [IncomingKeptSyncCoordinator.applyIncomingBatch] call.
final class IncomingApplyResult {
  const IncomingApplyResult({
    required this.status,
    this.appliedProjectionCount = 0,
    this.retiredIntentCount = 0,
    this.retiredOutboxCount = 0,
    this.systemFieldCount = 0,
  });

  final IncomingApplyStatus status;

  /// Number of incoming Kept projections this call resolved and wrote into
  /// the Kept envelope (or evaluated as a tombstone no-op). Always `0` for
  /// every non-[IncomingApplyStatus.applied] status.
  final int appliedProjectionCount;

  /// Number of [LocalSyncIntent]s retired this call.
  final int retiredIntentCount;

  /// Number of outbox mutations retired this call.
  final int retiredOutboxCount;

  /// Number of record-system-fields entries durably committed this call.
  final int systemFieldCount;

  bool get isApplied =>
      status == IncomingApplyStatus.applied ||
      status == IncomingApplyStatus.alreadyApplied;

  /// A privacy-safe summary: status and counts only -- never an account
  /// fingerprint, a `dataEpoch`, a token, a record name, a `revealId`, an
  /// `intentId`, a `mutationId`, wisdom text, Reflection text, or opaque
  /// system fields.
  Map<String, Object?> toLogSafeSummary() => {
        'status': status.name,
        'appliedProjectionCount': appliedProjectionCount,
        'retiredIntentCount': retiredIntentCount,
        'retiredOutboxCount': retiredOutboxCount,
        'systemFieldCount': systemFieldCount,
      };

  @override
  String toString() => 'IncomingApplyResult(${toLogSafeSummary()})';
}

/// Which durable local source a resolved candidate projection came from --
/// internal bookkeeping only, never exposed on [IncomingApplyResult].
enum _CandidateSource { physical, intent, outbox }

/// One non-absent local candidate for a given incoming `recordName`,
/// normalized into the shared [CloudKeptWisdomProjection] conflict shape.
final class _Candidate {
  const _Candidate({
    required this.source,
    required this.projection,
    this.recoveryId,
    this.intentId,
    this.mutationId,
  });

  final _CandidateSource source;
  final CloudKeptWisdomProjection projection;

  /// The physical `KeptRecord.id` ([_CandidateSource.physical]) or the
  /// intent's own captured `localId` ([_CandidateSource.intent]) -- `null`
  /// for [_CandidateSource.outbox], which carries no local-id concept.
  final String? recoveryId;

  /// Populated only for [_CandidateSource.intent].
  final String? intentId;

  /// Populated only for [_CandidateSource.outbox].
  final String? mutationId;
}

/// The fully-computed, pure (no side effect yet) resolution for one incoming
/// `recordName`.
final class _RecordOutcome {
  const _RecordOutcome({
    required this.finalProjection,
    this.preservedId,
    this.intentIdToRetire,
    this.outboxMutationIdToRetire,
    this.needsMergedUpload = false,
  });

  final CloudKeptWisdomProjection finalProjection;
  final String? preservedId;
  final String? intentIdToRetire;
  final String? outboxMutationIdToRetire;
  final bool needsMergedUpload;
}

/// Build 26 Phase 4E-3b: the real incoming-apply coordinator. See the
/// library doc comment for the full transaction/locking model.
final class IncomingKeptSyncCoordinator {
  IncomingKeptSyncCoordinator({
    required KeptRepository keptRepository,
    required LocalSyncIntentStore intentStore,
    required SyncPersistenceStore syncPersistenceStore,
    PersistenceOperationCoordinator? integrationCoordinator,
    void Function()? onIncomingStateChanged,
  })  : _keptRepository = keptRepository,
        _intentStore = intentStore,
        _syncPersistenceStore = syncPersistenceStore,
        _integrationCoordinator =
            integrationCoordinator ?? PersistenceOperationCoordinator(),
        _onIncomingStateChanged = onIncomingStateChanged;

  /// Must equal `KeptSyncIntegrationCoordinator.resourceKey` exactly.
  /// Restated as its own literal (never imported from that class) to keep
  /// this file's own dependency list narrow; a dedicated test
  /// (`incoming_kept_sync_coordinator_test.dart`) proves the two constants
  /// stay equal.
  static const String resourceKey = 'kept_sync_integration_v1';

  final KeptRepository _keptRepository;
  final LocalSyncIntentStore _intentStore;
  final SyncPersistenceStore _syncPersistenceStore;
  final PersistenceOperationCoordinator _integrationCoordinator;

  /// Build 26 Phase 4H-6 (live incoming Kept UI refresh): an optional,
  /// payload-free notification invoked at most once per [applyIncomingBatch]
  /// call, and only when this call's own [KeptRepository.replaceAllRecords]
  /// just durably persisted a Kept envelope whose *content* -- keyed by the
  /// stable `revealId` occurrence identity, never by list order or object
  /// identity -- actually differs from what was persisted immediately
  /// before it (see [_keptRecordListsDiffer]). Never invoked for any
  /// rejected/no-op batch (every early `return` above happens before
  /// [KeptRepository.replaceAllRecords] is ever called), and never gated on
  /// whether the checkpoint commit that follows later succeeds --
  /// [KeptRepository.replaceAllRecords] has already durably committed by
  /// the time this fires, so a later [IncomingApplyStatus.checkpointFailed]
  /// does not make the just-applied Kept content any less real or any less
  /// something a mounted UI needs to reflect.
  ///
  /// Deliberately a plain, argument-free `void Function()` -- mirrors
  /// [KeptSyncIntegrationCoordinator]'s own `onMutationCommitted` callback
  /// exactly, for the same reason: this file must learn nothing about
  /// `Listenable`, `ChangeNotifier`, or any concrete notifier type (see
  /// `test/sync_integration/sync_integration_layering_test.dart`'s narrow
  /// import allowlist for `lib/sync_integration/`). `app_services.dart`
  /// alone decides what calling this callback actually does.
  final void Function()? _onIncomingStateChanged;

  /// Durably applies [batch], or rejects it fail-closed, inside exactly one
  /// [resourceKey] exclusive transaction covering validation, every local
  /// read, the single complete Kept envelope replace, every loser-cleanup
  /// step, and the final checkpoint. Never starts a network fetch itself --
  /// [batch] is always already-fetched, already-decoded data.
  Future<IncomingApplyResult> applyIncomingBatch(
    PendingIncomingSyncBatch batch,
  ) {
    return _integrationCoordinator.runExclusive<IncomingApplyResult>(
      resourceKey: resourceKey,
      operation: () => _applyOnce(batch),
    );
  }

  Future<IncomingApplyResult> _applyOnce(
    PendingIncomingSyncBatch batch,
  ) async {
    // Section 5: CKEastSyncState control records are entirely out of this
    // phase's scope -- reject the whole batch untouched rather than ignore,
    // partially apply, or mutate epoch/bootstrap state.
    if (batch.incomingSyncStateProjections.isNotEmpty) {
      return const IncomingApplyResult(
        status: IncomingApplyStatus.controlRecordsRejected,
      );
    }

    final pendingToken = batch.pendingServerChangeToken;
    if (pendingToken == null || pendingToken.isEmpty) {
      return const IncomingApplyResult(
        status: IncomingApplyStatus.missingPendingToken,
      );
    }

    // Section 6: batch-shape validation, before any state is read.
    final shapeFailure = _validateBatchShape(batch);
    if (shapeFailure != null) return shapeFailure;

    // Section 3/4: reload current persisted state fresh -- never trusted
    // from any value the caller captured earlier.
    final AccountSyncState? bucket;
    try {
      bucket = await _syncPersistenceStore
          .loadAccountState(batch.accountFingerprint);
    } on SyncPersistenceStoreException {
      return const IncomingApplyResult(
        status: IncomingApplyStatus.persistenceFailure,
      );
    }
    if (bucket == null) {
      return const IncomingApplyResult(
        status: IncomingApplyStatus.bucketMissing,
      );
    }
    if (bucket.bootstrapState != AccountBootstrapState.complete) {
      return const IncomingApplyResult(
        status: IncomingApplyStatus.bootstrapNotComplete,
      );
    }
    if (bucket.dataEpoch != batch.baseDataEpoch) {
      return const IncomingApplyResult(
        status: IncomingApplyStatus.dataEpochMismatch,
      );
    }

    // Token algorithm (section 4): three mutually exclusive states.
    if (bucket.serverChangeToken == batch.previousServerChangeToken) {
      // State 1 -- normal application proceeds below.
    } else if (bucket.serverChangeToken == pendingToken) {
      // State 2 -- this exact batch is already checkpointed. Idempotent
      // success; touches nothing.
      return const IncomingApplyResult(
        status: IncomingApplyStatus.alreadyApplied,
      );
    } else {
      // State 3 -- stale batch. Never invents a token, never touches Kept.
      return const IncomingApplyResult(status: IncomingApplyStatus.staleBatch);
    }

    // Sections 7-10: pure computation. Every incoming projection is resolved
    // against its own local candidates before any write happens -- a single
    // rejected record aborts the whole batch, never a partial application.
    final List<KeptRecord> physicalRecords;
    final List<LocalSyncIntent> intents;
    try {
      physicalRecords = await _keptRepository.loadAllRecords();
      intents = await _intentStore.loadIntents();
    } on KeptRepositoryException {
      return const IncomingApplyResult(
        status: IncomingApplyStatus.persistenceFailure,
      );
    } on LocalSyncIntentStoreException {
      return const IncomingApplyResult(
        status: IncomingApplyStatus.persistenceFailure,
      );
    }

    final outcomes = <_RecordOutcome>[];
    for (final incoming in batch.incomingKeptWisdomProjections) {
      final outcome = _resolveOneRecord(
        incomingRemote: incoming,
        physicalRecords: physicalRecords,
        intents: intents,
        bucket: bucket,
      );
      if (outcome == null) {
        return const IncomingApplyResult(
          status: IncomingApplyStatus.conflictAborted,
        );
      }
      outcomes.add(outcome);
    }

    // Persist a complete union before replacing local data or checkpointing.
    // If interrupted, this outbox projection is itself a recovery candidate.
    try {
      for (final outcome in outcomes.where((o) => o.needsMergedUpload)) {
        await _syncPersistenceStore.enqueueMutation(
            batch.accountFingerprint,
            SyncChange(
                kind: SyncChangeKind.update,
                projection: outcome.finalProjection,
                enqueuedAt: DateTime.fromMillisecondsSinceEpoch(
                    outcome.finalProjection.updatedAtMs,
                    isUtc: true)));
      }
    } on SyncPersistenceStoreException {
      return const IncomingApplyResult(
          status: IncomingApplyStatus.persistenceFailure);
    }

    // Section 16/17 step 1: exactly one complete Kept envelope replace.
    final nextRecords = List<KeptRecord>.of(physicalRecords);
    for (final outcome in outcomes) {
      _applyOutcomeToRecords(nextRecords, outcome);
    }
    try {
      await _keptRepository.replaceAllRecords(nextRecords);
    } on KeptRepositoryException {
      return const IncomingApplyResult(
        status: IncomingApplyStatus.persistenceFailure,
      );
    }

    // Build 26 Phase 4H-6: the Kept envelope just durably changed. Notify
    // only when the persisted content actually differs from what was there
    // immediately before this replace -- never merely because
    // `appliedProjectionCount > 0` (Section 10's "Identical convergence"
    // can retire/replace bookkeeping for a content-identical projection,
    // which must never trigger a UI refresh).
    if (_keptRecordListsDiffer(physicalRecords, nextRecords)) {
      _notifyIncomingStateChanged();
    }

    // Step 2: retire losing/superseded local intents.
    var retiredIntentCount = 0;
    for (final outcome in outcomes) {
      final intentId = outcome.intentIdToRetire;
      if (intentId == null) continue;
      await _intentStore.removeIntent(intentId);
      retiredIntentCount += 1;
    }

    // Step 3: retire losing/converged outbox mutations -- never
    // `applyMutationOutcomes` (see `outbox_mutation_retirement.dart`).
    var retiredOutboxCount = 0;
    for (final outcome in outcomes) {
      final mutationId = outcome.outboxMutationIdToRetire;
      if (mutationId == null) continue;
      final result = await _syncPersistenceStore.retireOutboxMutationIfCurrent(
        RetireOutboxMutationRequest(
          accountFingerprint: batch.accountFingerprint,
          expectedDataEpoch: bucket.dataEpoch,
          recordName: outcome.finalProjection.recordName,
          mutationId: mutationId,
        ),
      );
      if (result.isRetired) retiredOutboxCount += 1;
    }

    // Step 4: commit the checkpoint -- every incoming record's fetched
    // system fields, regardless of which side won this record's content,
    // plus the pending server token. Never mutates outbox acknowledgements,
    // never transitions bootstrap state.
    final checkpointRequest = CommitIncomingBatchCheckpointRequest(
      accountFingerprint: batch.accountFingerprint,
      mode: IncomingCheckpointMode.existingBucket,
      pendingServerChangeToken: pendingToken,
      expectedCurrentDataEpoch: bucket.dataEpoch,
      expectedPreviousServerToken: batch.previousServerChangeToken,
      recordSystemFieldsUpdates: [
        for (final projection in batch.incomingKeptWisdomProjections)
          IncomingRecordSystemFieldsUpdate(
            recordName: projection.recordName,
            systemFields: batch
                .incomingKeptWisdomRecordSystemFields[projection.recordName]!,
          ),
      ],
    );

    final CommitIncomingBatchCheckpointResult checkpointResult;
    try {
      checkpointResult = await _syncPersistenceStore
          .commitIncomingBatchCheckpoint(checkpointRequest);
    } on SyncPersistenceStoreException {
      return IncomingApplyResult(
        status: IncomingApplyStatus.checkpointFailed,
        appliedProjectionCount: outcomes.length,
        retiredIntentCount: retiredIntentCount,
        retiredOutboxCount: retiredOutboxCount,
      );
    }
    if (!checkpointResult.isCommitted) {
      return IncomingApplyResult(
        status: IncomingApplyStatus.checkpointFailed,
        appliedProjectionCount: outcomes.length,
        retiredIntentCount: retiredIntentCount,
        retiredOutboxCount: retiredOutboxCount,
      );
    }

    // Step 5: release the integration lock -- implicit, on return, via
    // runExclusive's own completion.
    return IncomingApplyResult(
      status: IncomingApplyStatus.applied,
      appliedProjectionCount: outcomes.length,
      retiredIntentCount: retiredIntentCount,
      retiredOutboxCount: retiredOutboxCount,
      systemFieldCount: checkpointResult.systemFieldCount,
    );
  }

  /// Section 6: rejects the whole batch closed on any duplicate
  /// `recordName`/`revealId`, or any systemFields/projection key-set
  /// mismatch. Pure -- reads only [batch], never persisted state.
  IncomingApplyResult? _validateBatchShape(PendingIncomingSyncBatch batch) {
    final seenRecordNames = <String>{};
    final seenRevealIds = <String>{};
    for (final projection in batch.incomingKeptWisdomProjections) {
      if (!seenRecordNames.add(projection.recordName)) {
        return const IncomingApplyResult(
          status: IncomingApplyStatus.duplicateRecordName,
        );
      }
      final revealId = projection.revealId;
      if (revealId != null && !seenRevealIds.add(revealId)) {
        return const IncomingApplyResult(
          status: IncomingApplyStatus.duplicateRevealId,
        );
      }
    }

    final systemFieldsKeys =
        batch.incomingKeptWisdomRecordSystemFields.keys.toSet();
    if (systemFieldsKeys.length != seenRecordNames.length ||
        !systemFieldsKeys.containsAll(seenRecordNames)) {
      return const IncomingApplyResult(
        status: IncomingApplyStatus.systemFieldsMismatch,
      );
    }
    for (final value in batch.incomingKeptWisdomRecordSystemFields.values) {
      if (value.isEmpty) {
        return const IncomingApplyResult(
          status: IncomingApplyStatus.systemFieldsMismatch,
        );
      }
    }
    return null;
  }

  /// Sections 7-10: resolves exactly one incoming projection against every
  /// non-absent local candidate for the same `recordName`. Returns `null`
  /// only when a genuine fail-closed conflict-resolution rejection
  /// ([ConflictReason.bothEpochsStale]/[ConflictReason.immutableFieldMismatch])
  /// occurred -- the caller aborts the entire batch in that case.
  _RecordOutcome? _resolveOneRecord({
    required CloudKeptWisdomProjection incomingRemote,
    required List<KeptRecord> physicalRecords,
    required List<LocalSyncIntent> intents,
    required AccountSyncState bucket,
  }) {
    final recordName = incomingRemote.recordName;
    final epoch = bucket.dataEpoch;

    _Candidate? physicalCandidate;
    for (final record in physicalRecords) {
      if (deriveKeptWisdomRecordName(record.revealId) == recordName) {
        physicalCandidate = _Candidate(
          source: _CandidateSource.physical,
          projection: CloudKeptWisdomProjection.active(
            record,
            dataEpoch: epoch,
          ),
          recoveryId: record.id,
        );
        break;
      }
    }

    _Candidate? intentCandidate;
    for (final intent in intents) {
      if (intent.recordName == recordName) {
        intentCandidate = _Candidate(
          source: _CandidateSource.intent,
          projection: _projectionFromIntent(intent, epoch),
          recoveryId: intent.payload.localId,
          intentId: intent.intentId,
        );
        break;
      }
    }

    _Candidate? outboxCandidate;
    for (final entry in bucket.outbox) {
      if (entry.recordName == recordName) {
        outboxCandidate = _Candidate(
          source: _CandidateSource.outbox,
          projection: entry.change.projection,
          mutationId: entry.mutationId,
        );
        break;
      }
    }

    // Section 8: local fold -- physical vs intent, then winner vs outbox.
    // Never a different source-type precedence.
    _Candidate? current = physicalCandidate;
    if (intentCandidate != null) {
      if (current == null) {
        current = intentCandidate;
      } else {
        final outcome = resolveKeptWisdomConflict(
          local: current.projection,
          remote: intentCandidate.projection,
          authoritativeEpoch: epoch,
        );
        if (outcome.isRejected) return null;
        if (!identical(outcome.winner, current.projection)) {
          current = intentCandidate;
        }
      }
    }
    if (outboxCandidate != null) {
      if (current == null) {
        current = outboxCandidate;
      } else {
        final outcome = resolveKeptWisdomConflict(
          local: current.projection,
          remote: outboxCandidate.projection,
          authoritativeEpoch: epoch,
        );
        if (outcome.isRejected) return null;
        if (!identical(outcome.winner, current.projection)) {
          current = outboxCandidate;
        }
      }
    }

    if (current == null) {
      // Section 9: genuine local absence. Remote active -> adopt; remote
      // tombstone -> local no-op (nothing local ever existed to remove or
      // retire). System fields are still checkpointed for this record by
      // the caller regardless of this branch.
      return _RecordOutcome(finalProjection: incomingRemote);
    }

    // Section 9: local winner vs incoming remote.
    final finalOutcome = resolveKeptWisdomConflict(
      local: current.projection,
      remote: incomingRemote,
      authoritativeEpoch: epoch,
    );
    if (finalOutcome.isRejected) return null;

    final localWon = identical(finalOutcome.winner, current.projection);
    // Section 10, "Identical convergence": even when the resolver's own
    // tie-break convention returns the local reference as `winner`, content-
    // identical local bookkeeping is redundant once the remote fetch has
    // independently proven the exact same content durable server-side --
    // retire it exactly as if remote had won outright.
    final retireEverythingLocal =
        !localWon || finalOutcome.reason == ConflictReason.identical;

    // Computed here (rather than after the retirement decision below) because
    // the "local wins decisively" branch now needs it to decide retirement by
    // content rather than by candidate-source bookkeeping.
    final winner = localWon ? current.projection : incomingRemote;
    final CloudKeptWisdomProjection finalProjection;
    try {
      finalProjection = winner.mergingThoughts([
        incomingRemote,
        if (physicalCandidate != null) physicalCandidate.projection,
        if (intentCandidate != null) intentCandidate.projection,
        if (outboxCandidate != null) outboxCandidate.projection,
      ]);
    } on FormatException {
      return null;
    }

    String? intentIdToRetire;
    String? outboxMutationIdToRetire;
    if (retireEverythingLocal) {
      if (intentCandidate != null) {
        intentIdToRetire = intentCandidate.intentId;
      }
      if (outboxCandidate != null) {
        outboxMutationIdToRetire = outboxCandidate.mutationId;
      }
    } else {
      // Local wins decisively over a genuinely differing remote. Retirement
      // here must be decided by CONTENT supersession, never by which
      // candidate object the local fold above happened to leave `current`
      // pointing at: when the local fold's own `identical` tie-break
      // (`resolveKeptWisdomConflict`'s `local == remote` convention) leaves
      // `current` referencing e.g. the physical candidate even though an
      // outbox (or intent) candidate is byte-for-byte the same content, that
      // outbox/intent entry is NOT stale -- it is still the only durable
      // vehicle able to carry this exact winning content back to CloudKit,
      // and must survive so a later `SyncOrchestrator` pass retries it (using
      // the fresh systemFields this same checkpoint is about to commit
      // below). Only a sibling whose own content genuinely differs from the
      // terminal winner has actually been superseded and may be retired.
      if (intentCandidate != null &&
          intentCandidate.projection != finalProjection) {
        intentIdToRetire = intentCandidate.intentId;
      }
      if (outboxCandidate != null &&
          outboxCandidate.projection != finalProjection) {
        outboxMutationIdToRetire = outboxCandidate.mutationId;
      }
    }

    // Section 13/14: id/localId preference -- an existing physical record's
    // own id always wins when this exact occurrence already has one
    // (regardless of which side's *content* ultimately won); otherwise, if
    // the terminal local winner is the intent (completing an interrupted
    // local write), its own captured localId is used; otherwise (a fresh
    // remote adoption into genuine local absence, or an outbox-only local
    // winner with no physical record at all) no id is preserved here and
    // the caller derives one deterministically from revealId.
    String? preservedId = physicalCandidate?.recoveryId;
    if (preservedId == null &&
        localWon &&
        current.source == _CandidateSource.intent) {
      preservedId = current.recoveryId;
    }

    return _RecordOutcome(
      finalProjection: finalProjection,
      needsMergedUpload: !identical(finalProjection, winner),
      preservedId: preservedId,
      intentIdToRetire: intentIdToRetire,
      outboxMutationIdToRetire: outboxMutationIdToRetire,
    );
  }

  /// Mirrors `KeptSyncIntegrationCoordinator._toSyncChange`'s exact
  /// active/tombstone conversion semantics independently (never a shared
  /// call into that class) -- no new IDs, no new timestamps, every value
  /// taken directly from [intent]'s own already-captured payload, stamped
  /// with [dataEpoch] because a [LocalSyncIntent] itself intentionally
  /// carries no account epoch of its own.
  CloudKeptWisdomProjection _projectionFromIntent(
    LocalSyncIntent intent,
    DataEpoch dataEpoch,
  ) {
    final payload = intent.payload;

    if (payload.isTombstone) {
      final tombstone = SyncTombstone(
        revealId: payload.revealId,
        dataEpoch: dataEpoch,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          payload.updatedAtMs,
          isUtc: true,
        ),
        deletedAt: DateTime.fromMillisecondsSinceEpoch(
          payload.deletedAtMs!,
          isUtc: true,
        ),
        mutationId: payload.mutationId,
        localId: payload.localId,
      );
      return CloudKeptWisdomProjection.tombstone(tombstone);
    }

    final record = KeptRecord(
      // Purely a conversion vehicle -- KeptRecord.id never appears in a
      // CloudKeptWisdomProjection's own encoded shape, so this fallback has
      // no effect on the eventual projection's identity/content.
      id: payload.localId ?? payload.mutationId,
      revealId: payload.revealId,
      wisdomText: payload.wisdomText!,
      wisdomId: payload.wisdomId,
      revealedAt: DateTime.fromMillisecondsSinceEpoch(
        payload.revealedAtMs!,
        isUtc: true,
      ),
      keptAt: DateTime.fromMillisecondsSinceEpoch(
        payload.keptAtMs!,
        isUtc: true,
      ),
      reflectionText: payload.reflectionText,
      reflectionHistoryJson: payload.reflectionHistoryJson,
      reflectedAt: payload.reflectedAtMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              payload.reflectedAtMs!,
              isUtc: true,
            ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        payload.updatedAtMs,
        isUtc: true,
      ),
      mutationId: payload.mutationId,
    );
    return CloudKeptWisdomProjection.active(record, dataEpoch: dataEpoch);
  }

  /// Applies one already-resolved [_RecordOutcome] onto the in-progress
  /// [records] list: an active winner is upserted (never merged
  /// field-by-field -- every field comes from
  /// [_RecordOutcome.finalProjection] alone), a tombstone winner removes any
  /// matching physical record (a no-op if none exists). Every field on the
  /// constructed [KeptRecord] comes directly from the winning projection --
  /// never a freshly-minted timestamp or `mutationId` -- except [KeptRecord
  /// .id], which follows [_RecordOutcome.preservedId]'s own preference order,
  /// falling back to [deriveIncomingKeptLocalId] only for a genuine first
  /// adoption.
  void _applyOutcomeToRecords(
    List<KeptRecord> records,
    _RecordOutcome outcome,
  ) {
    final projection = outcome.finalProjection;
    final recordName = projection.recordName;
    final existingIndex = records.indexWhere(
      (record) => deriveKeptWisdomRecordName(record.revealId) == recordName,
    );

    if (projection.isTombstone) {
      if (existingIndex != -1) records.removeAt(existingIndex);
      return;
    }

    final revealId = projection.revealId!;
    final id = outcome.preservedId ?? deriveIncomingKeptLocalId(revealId);
    final record = KeptRecord(
      id: id,
      revealId: revealId,
      wisdomText: projection.wisdomText!,
      wisdomId: projection.wisdomId,
      revealedAt: DateTime.fromMillisecondsSinceEpoch(
        projection.revealedAtMs!,
        isUtc: true,
      ),
      keptAt: DateTime.fromMillisecondsSinceEpoch(
        projection.keptAtMs!,
        isUtc: true,
      ),
      reflectionText: projection.reflectionText,
      reflectionHistoryJson: projection.reflectionHistoryJson,
      reflectedAt: projection.reflectedAtMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              projection.reflectedAtMs!,
              isUtc: true,
            ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        projection.updatedAtMs,
        isUtc: true,
      ),
      mutationId: projection.mutationId,
    );

    if (existingIndex == -1) {
      records.add(record);
    } else {
      records[existingIndex] = record;
    }
  }

  /// Build 26 Phase 4H-6: content-based, order-independent comparison keyed
  /// by the stable `revealId` occurrence identity -- the same identity every
  /// other resolution step in this class already keys on. Never compares by
  /// list order or by array position: a fresh remote adoption is appended
  /// to [after], and a local-wins re-fold can leave existing entries in a
  /// different relative order than [before], neither of which alone is a
  /// real content change. Two lists of equal length whose records are
  /// otherwise `==`-equal (see [KeptRecord.operator ==]) are never reported
  /// as differing.
  bool _keptRecordListsDiffer(
    List<KeptRecord> before,
    List<KeptRecord> after,
  ) {
    if (before.length != after.length) return true;

    final beforeByRevealId = <String, KeptRecord>{
      for (final record in before) record.revealId: record,
    };
    if (beforeByRevealId.length != before.length) {
      // Defensive only: a duplicate `revealId` inside `before` should never
      // happen (KeptRepository's own invariants forbid it) -- if it ever
      // did, silently trusting a collapsed map here could hide a real
      // difference, so this fails open toward "differs" instead.
      return true;
    }

    for (final record in after) {
      final beforeRecord = beforeByRevealId[record.revealId];
      if (beforeRecord == null || beforeRecord != record) return true;
    }
    return false;
  }

  /// Synchronous, defensive containment -- mirrors
  /// `KeptSyncIntegrationCoordinator._notifyIfIntentWasWritten` exactly: a
  /// failure inside [_onIncomingStateChanged] can never affect the batch
  /// apply that already durably committed, and is never logged with any
  /// identifier or content.
  void _notifyIncomingStateChanged() {
    try {
      _onIncomingStateChanged?.call();
    } catch (_) {
      // Intentionally contained -- see the doc comment above.
    }
  }
}
