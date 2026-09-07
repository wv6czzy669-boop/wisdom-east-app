/// Build 26 Phase 4E-4: existing-user remote-first bootstrap, explicit
/// account association, and legacy local-history backfill.
///
/// Deliberately a **separate** class from [KeptSyncIntegrationCoordinator]
/// (the outgoing local-mutation -> durable-intent -> outbox path) and from
/// [IncomingKeptSyncCoordinator] (the incoming fetched-batch -> resolved Kept
/// envelope -> checkpoint path, which requires `bootstrapState == complete`
/// and must never have that guard weakened). This class owns the one-time
/// first-association transaction shape: resolve account, decide whether this
/// device may associate automatically or requires an explicit decision,
/// fetch the full remote baseline, merge it with any existing local history,
/// backfill genuinely local-only legacy records into durable intents, and
/// promote every outstanding local mutation into the durable outbox before
/// ever marking bootstrap `complete`.
///
/// **Locking.** Every durable local-state transition here acquires the
/// *same* production [PersistenceOperationCoordinator] instance and the
/// exact same [resourceKey] string (`kept_sync_integration_v1`) that
/// [KeptSyncIntegrationCoordinator] and [IncomingKeptSyncCoordinator] already
/// use -- see `lib/services/app_services.dart`'s wiring. [resourceKey] is
/// **not** imported from either of those classes (to keep this file's own
/// dependency list narrow); a dedicated test proves all three string
/// constants stay equal. Network calls (`CloudKitPlatformBridge`) always run
/// **outside** any lock acquisition -- see [runBootstrap]'s own doc comment
/// for the exact acquire/release/fetch/reacquire sequence. This is enforced
/// with **zero exceptions**, including [CloudKitPlatformBridge
/// .getAccountSnapshot] calls (every call site resolves the snapshot before
/// acquiring the lock, then carries the already-resolved value into it by
/// value) and the one-time empty-remote `CKEastSyncState` creation-and-
/// verification round trip (Build 26 Phase 4E-4 lock correction; see
/// [_createAndVerifyControlRecordOutsideLock]).
///
/// **Association model.** Let `M` be the durable
/// `SyncPersistenceStore.loadAssociatedAccountFingerprint()` marker and `F`
/// be the currently-resolved CloudKit account fingerprint:
///
/// - `M` absent, no local Kept history exists -> `autoAssociable`.
/// - `M` absent, local Kept history exists -> `associationRequired` (no
///   fetch, no marker write, no bucket creation, no upload).
/// - `M == F` -> `resumeAssociation`.
/// - `M != F` -> `associationRequired` (the previous association's local
///   history is never uploaded automatically).
///
/// Backward compatibility: if `M` is absent, this device may already have
/// completed bootstrap progress from before this marker concept existed. In
/// that case exactly one account bucket whose `bootstrapState` is not
/// `notStarted` is treated as an unresolved legacy association
/// (`unresolvedLegacyAssociation`) -- repairable only via
/// [repairLegacyAssociationMarker], never by [evaluateAssociation] itself.
/// More than one such bucket is `ambiguousLegacyState` -- fail-closed, no
/// automatic choice.
///
/// **Scope.** This phase never automatically recovers from a changed remote
/// `dataEpoch` on an already-`complete` association (`runBootstrap` detects
/// and reports `remoteEpochChangedRecoveryRequired`, then stops -- no Kept
/// mutation, no outbox upload, no bootstrap-state transition); never
/// reauthorizes an association to a different fingerprint once one already
/// exists; and is never called automatically by any production code path --
/// [evaluateAssociation]/[authorizeAssociation]/
/// [repairLegacyAssociationMarker]/[runBootstrap] are callable but uncalled,
/// exactly like [KeptSyncIntegrationCoordinator.reconcileForAssociatedAccount]
/// and [IncomingKeptSyncCoordinator.applyIncomingBatch] were before their own
/// callers existed. Phase 4F owns wiring an automatic trigger.
///
/// **Dependencies are deliberately narrow:** [CloudKitPlatformBridge],
/// [PersistenceOperationCoordinator] (shared instance), [KeptRepository]
/// (via its Phase 4E-3b [KeptRepository.loadAllRecords]/
/// [KeptRepository.replaceAllRecords] surface only -- never its
/// user-mutation methods, never the Phase 4E-2 privileged replay
/// parameters), [LocalSyncIntentStore], [SyncPersistenceStore], and the
/// existing sync-domain/conflict/transport types. This file imports no UI,
/// screen, widget, `SavedReflectionsService`, or lifecycle/network/startup
/// code.
library;

import 'package:uuid/uuid.dart';

import '../models/kept_record.dart';
import '../persistence/persistence_operation_coordinator.dart';
import '../repositories/kept_repository.dart';
import '../sync/cloud_east_sync_state_projection.dart';
import '../sync/cloud_kept_wisdom_projection.dart';
import '../sync/conflict_resolution.dart';
import '../sync/data_epoch.dart';
import '../sync/sync_change.dart';
import '../sync/sync_record_identity.dart';
import '../sync/sync_tombstone.dart';
import '../sync_persistence/account_sync_state.dart';
import '../sync_persistence/associated_account_fingerprint_commit.dart';
import '../sync_persistence/incoming_batch_checkpoint.dart';
import '../sync_persistence/outbox_mutation_retirement.dart';
import '../sync_persistence/persisted_outbox_mutation.dart';
import '../sync_persistence/sync_persistence_envelope.dart'
    show looksLikeAccountFingerprint;
import '../sync_persistence/sync_persistence_store.dart';
import '../sync_platform/cloud_kit_account_snapshot.dart';
import '../sync_platform/cloud_kit_modify_records_contract.dart';
import '../sync_platform/cloud_kit_platform_bridge.dart';
import '../sync_platform/cloud_kit_platform_error.dart';
import '../sync_platform/cloud_kit_sync_state_epoch_contract.dart';
import '../sync_platform/cloud_kit_zone_changes_contract.dart';
import '../utils/kept_timestamp_canonicalizer.dart';
import '../utils/remote_kept_identity.dart';
import 'local_sync_intent.dart';
import 'local_sync_intent_store.dart';

// ---------------------------------------------------------------------------
// Association evaluation.
// ---------------------------------------------------------------------------

/// The categorical, content-safe result of one
/// [KeptSyncBootstrapCoordinator.evaluateAssociation] call.
enum AssociationEvaluationStatus {
  /// No prior association marker, and this device has no local Kept
  /// history -- safe to associate/restore automatically.
  autoAssociable,

  /// Either no prior association marker with existing local Kept history,
  /// or a durable marker that names a different fingerprint than the one
  /// currently resolved. An explicit association decision is required
  /// before any fetch, bucket creation, or upload may occur.
  associationRequired,

  /// The durable marker already names the currently-resolved fingerprint --
  /// resume whatever bootstrap progress this account bucket already has.
  resumeAssociation,

  /// No durable marker exists, but exactly one account bucket already has
  /// meaningful (non-`notStarted`) bootstrap progress -- a device that
  /// completed some bootstrap work before this marker concept existed.
  /// Resolvable only via [KeptSyncBootstrapCoordinator
  /// .repairLegacyAssociationMarker].
  unresolvedLegacyAssociation,

  /// No durable marker exists, and more than one account bucket already has
  /// meaningful bootstrap progress. Fail-closed -- no automatic choice is
  /// safe.
  ambiguousLegacyState,

  /// The CloudKit account is not available (no account, restricted,
  /// undetermined, or temporarily unavailable).
  accountUnavailable,

  /// The account is available but its private database is not usable or its
  /// fingerprint could not be resolved.
  fingerprintUnresolved,
}

/// The full result of one [KeptSyncBootstrapCoordinator.evaluateAssociation]
/// call. May carry a fingerprint internally (needed by
/// [KeptSyncBootstrapCoordinator.runBootstrap] to proceed), but never
/// renders one.
final class AssociationEvaluation {
  const AssociationEvaluation._({
    required this.status,
    this.currentFingerprint,
    this.legacyCandidateFingerprint,
  });

  final AssociationEvaluationStatus status;

  /// Internal execution use only -- **never** rendered by [toString]/
  /// [toLogSafeSummary].
  final String? currentFingerprint;

  /// Internal execution use only, populated only for
  /// [AssociationEvaluationStatus.unresolvedLegacyAssociation]. **Never**
  /// rendered by [toString]/[toLogSafeSummary].
  final String? legacyCandidateFingerprint;

  /// A privacy-safe summary: status only -- never a fingerprint value.
  Map<String, Object?> toLogSafeSummary() => {'status': status.name};

  @override
  String toString() => 'AssociationEvaluation(${toLogSafeSummary()})';
}

// ---------------------------------------------------------------------------
// Explicit association authorization.
// ---------------------------------------------------------------------------

enum AssociationAuthorizationStatus {
  /// The marker was absent and is now durably set to the requested
  /// fingerprint.
  authorized,

  /// The marker already named exactly the requested fingerprint -- an
  /// idempotent no-op repeat.
  alreadyAuthorized,

  /// The currently-resolved CloudKit account fingerprint no longer equals
  /// the requested fingerprint (the account changed between evaluation and
  /// this call, or the account is no longer available) -- refused.
  accountMismatch,

  /// A different fingerprint is already durably associated. This method
  /// never replaces an existing, different association -- see the class
  /// doc comment.
  differentAssociationExists,

  /// The requested fingerprint does not look like an opaque account
  /// fingerprint.
  invalidFingerprint,
}

final class AssociationAuthorizationResult {
  const AssociationAuthorizationResult(this.status);

  final AssociationAuthorizationStatus status;

  bool get isAuthorized =>
      status == AssociationAuthorizationStatus.authorized ||
      status == AssociationAuthorizationStatus.alreadyAuthorized;

  Map<String, Object?> toLogSafeSummary() => {'status': status.name};

  @override
  String toString() => 'AssociationAuthorizationResult(${toLogSafeSummary()})';
}

// ---------------------------------------------------------------------------
// Legacy marker repair.
// ---------------------------------------------------------------------------

enum LegacyAssociationRepairStatus {
  /// The marker was absent, exactly one legacy candidate existed and
  /// matched the current fingerprint, and the marker is now durably set.
  repaired,

  /// No meaningful legacy bucket exists -- nothing to repair.
  noCandidates,

  /// More than one meaningful legacy bucket exists -- fail-closed, no
  /// automatic choice.
  ambiguousCandidates,

  /// Exactly one legacy candidate exists, but it does not equal the
  /// fingerprint this call expected to repair.
  candidateMismatch,

  /// The currently-resolved fingerprint no longer equals the expected
  /// candidate (the account changed, or is no longer available).
  accountChanged,

  /// A marker already exists -- this method only ever repairs a genuinely
  /// absent marker.
  markerAlreadyPresent,
}

final class LegacyAssociationRepairResult {
  const LegacyAssociationRepairResult(this.status);

  final LegacyAssociationRepairStatus status;

  bool get isResolved => status == LegacyAssociationRepairStatus.repaired;

  Map<String, Object?> toLogSafeSummary() => {'status': status.name};

  @override
  String toString() => 'LegacyAssociationRepairResult(${toLogSafeSummary()})';
}

// ---------------------------------------------------------------------------
// runBootstrap() result.
// ---------------------------------------------------------------------------

enum BootstrapRunStatus {
  /// Bootstrap reached (or was newly transitioned into) `complete` this
  /// call, with every required promotion durably represented in the
  /// outbox.
  completed,

  /// The association bucket was already `complete` and the remote epoch
  /// still matches -- nothing to do.
  alreadyComplete,

  /// An explicit association decision is required before bootstrap may
  /// proceed. No fetch, no marker write, no bucket creation, no upload
  /// occurred.
  associationRequired,

  /// More than one meaningful legacy bucket exists with no durable marker
  /// -- fail-closed.
  ambiguousLegacyState,

  /// The CloudKit account is not available.
  accountUnavailable,

  /// The account's fingerprint could not be resolved.
  fingerprintUnresolved,

  /// The account fingerprint changed between the pre-fetch read and the
  /// post-fetch reacquire-and-revalidate step. Nothing was mutated.
  accountChangedDuringFetch,

  /// More than one `CKEastSyncState` control record was present in a single
  /// fetch batch -- an invalid/ambiguous control-record shape. Nothing was
  /// mutated.
  controlRecordInvalid,

  /// Build 26 Phase 4E-4 lock correction: a brand-new `CKEastSyncState`
  /// control record was uploaded for a genuinely empty remote, but the
  /// mandatory post-upload verification re-fetch could not unambiguously
  /// confirm which epoch is now authoritative (transport failure, expired
  /// token, or an ambiguous/empty re-fetch result). The generated epoch is
  /// never trusted on this path -- nothing was committed, and a future
  /// retry starts over from a fresh initial fetch, which will observe
  /// whatever control record actually exists remotely by then.
  controlRecordCreationUnverified,

  /// The remote fetch itself failed (transport failure, permanent error, or
  /// an unrecognized result). Nothing was mutated.
  fetchFailed,

  /// A durable read/write failed. Nothing beyond what already landed before
  /// the failure was mutated.
  persistenceFailure,

  /// The persisted account bucket is in a shape that this coordinator's own
  /// checkpoint transitions can never produce -- specifically, a bucket at
  /// `remoteBaselinePending` or `localReconciliationPending` with no
  /// `serverChangeToken`, even though `commitIncomingBatchCheckpoint`'s
  /// `pendingServerChangeToken` is a non-nullable, always-real, already-
  /// fetched token on every legitimate transition into either state. This
  /// can only mean externally-corrupted or hand-edited persisted state, not
  /// an ordinary runtime failure safe to retry blindly. Detected and
  /// reported *before* any backfill, promotion, or checkpoint write for
  /// this attempt -- zero local mutation occurs on this path.
  corruptedBucketState,

  /// Resolving one or more incoming records against local candidates
  /// produced a fail-closed conflict-resolution rejection -- the entire
  /// baseline application was aborted before any Kept write.
  conflictAborted,

  /// The association bucket is already `complete`, the current fingerprint
  /// still matches the durable marker, but the freshly-fetched authoritative
  /// `CKEastSyncState.dataEpoch` differs from the bucket's own persisted
  /// `dataEpoch`. Out of scope for this phase: no Kept mutation, no outbox
  /// upload, no `dataEpoch` replacement, and no bootstrap-state transition
  /// occurred. A future phase owns recovery.
  remoteEpochChangedRecoveryRequired,
}

final class BootstrapRunResult {
  const BootstrapRunResult({
    required this.status,
    this.appliedProjectionCount = 0,
    this.backfilledIntentCount = 0,
    this.promotedIntentCount = 0,
  });

  final BootstrapRunStatus status;

  /// Number of incoming Kept projections resolved and written into the Kept
  /// envelope this call (0 unless a baseline fetch/merge actually ran).
  final int appliedProjectionCount;

  /// Number of genuinely local-only legacy [KeptRecord]s backfilled into a
  /// fresh durable [LocalSyncIntent] this call.
  final int backfilledIntentCount;

  /// Number of durable [LocalSyncIntent]s promoted into the account outbox
  /// this call.
  final int promotedIntentCount;

  bool get isSuccessful =>
      status == BootstrapRunStatus.completed ||
      status == BootstrapRunStatus.alreadyComplete;

  /// A privacy-safe summary: status and counts only.
  Map<String, Object?> toLogSafeSummary() => {
        'status': status.name,
        'appliedProjectionCount': appliedProjectionCount,
        'backfilledIntentCount': backfilledIntentCount,
        'promotedIntentCount': promotedIntentCount,
      };

  @override
  String toString() => 'BootstrapRunResult(${toLogSafeSummary()})';
}

// ---------------------------------------------------------------------------
// Internal merge-fold bookkeeping -- independent mirror of
// IncomingKeptSyncCoordinator's own private shapes (never a shared import).
// ---------------------------------------------------------------------------

enum _CandidateSource { physical, intent, outbox }

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
  final String? recoveryId;
  final String? intentId;
  final String? mutationId;
}

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

/// Build 26 Phase 4E-4 lock correction: the result of
/// [KeptSyncBootstrapCoordinator._createAndVerifyControlRecordOutsideLock].
/// Either a verified `(epoch, serverToken)` pair -- never the merely-
/// generated epoch on its own -- or a specific [BootstrapRunStatus] failure
/// to propagate verbatim. Deliberately not a nullable-fields tuple: the two
/// constructors make "success xor failure" structurally exhaustive.
final class _ControlRecordCreationOutcome {
  const _ControlRecordCreationOutcome.success({
    required DataEpoch this.epoch,
    required String this.serverToken,
  }) : failure = null;

  const _ControlRecordCreationOutcome.failure(BootstrapRunStatus status)
      : epoch = null,
        serverToken = null,
        failure = status;

  final DataEpoch? epoch;
  final String? serverToken;
  final BootstrapRunStatus? failure;

  bool get isSuccess => failure == null;
}

/// Build 26 Phase 4E-4: the real bootstrap coordinator. See the library doc
/// comment for the full model/locking/scope contract.
final class KeptSyncBootstrapCoordinator {
  KeptSyncBootstrapCoordinator({
    required CloudKitPlatformBridge bridge,
    required KeptRepository keptRepository,
    required LocalSyncIntentStore intentStore,
    required SyncPersistenceStore syncPersistenceStore,
    PersistenceOperationCoordinator? integrationCoordinator,
    String Function()? idFactory,
    DateTime Function()? clock,
  })  : _bridge = bridge,
        _keptRepository = keptRepository,
        _intentStore = intentStore,
        _syncPersistenceStore = syncPersistenceStore,
        _integrationCoordinator =
            integrationCoordinator ?? PersistenceOperationCoordinator(),
        _idFactory = idFactory ?? (() => const Uuid().v4()),
        _clock = clock ?? DateTime.now;

  /// Must equal `KeptSyncIntegrationCoordinator.resourceKey` and
  /// `IncomingKeptSyncCoordinator.resourceKey` exactly. Restated as its own
  /// literal (never imported from either class) to keep this file's own
  /// dependency list narrow; a dedicated test proves all three constants
  /// stay equal.
  static const String resourceKey = 'kept_sync_integration_v1';

  final CloudKitPlatformBridge _bridge;
  final KeptRepository _keptRepository;
  final LocalSyncIntentStore _intentStore;
  final SyncPersistenceStore _syncPersistenceStore;
  final PersistenceOperationCoordinator _integrationCoordinator;
  final String Function() _idFactory;
  final DateTime Function() _clock;

  Future<BootstrapRunResult>? _inFlight;

  // -------------------------------------------------------------------
  // 1. evaluateAssociation() -- genuinely read-only. No write of any kind.
  // -------------------------------------------------------------------

  /// Resolves the current association status. Performs only reads: the
  /// current CloudKit account snapshot, the durable association marker, (on
  /// marker absence) the meaningful-legacy-bucket set, and (only when
  /// genuinely needed to distinguish autoAssociable/associationRequired) the
  /// local Kept record count. Never writes the marker, never creates a
  /// bucket, never fetches a CloudKit baseline, never enqueues anything.
  Future<AssociationEvaluation> evaluateAssociation() async {
    final CloudKitAccountSnapshot snapshot;
    try {
      snapshot = await _bridge.getAccountSnapshot();
    } on CloudKitPlatformException {
      return const AssociationEvaluation._(
        status: AssociationEvaluationStatus.accountUnavailable,
      );
    }

    final gate = _evaluateAccountAvailability(snapshot);
    if (gate != null) return gate;
    final fingerprint = snapshot.accountFingerprint!;

    final marker =
        await _syncPersistenceStore.loadAssociatedAccountFingerprint();
    if (marker != null) {
      if (marker == fingerprint) {
        return AssociationEvaluation._(
          status: AssociationEvaluationStatus.resumeAssociation,
          currentFingerprint: fingerprint,
        );
      }
      return AssociationEvaluation._(
        status: AssociationEvaluationStatus.associationRequired,
        currentFingerprint: fingerprint,
      );
    }

    // Marker absent -- backward-compatible legacy-bucket derivation.
    final legacyCandidates =
        await _syncPersistenceStore.loadMeaningfulAccountFingerprints();
    if (legacyCandidates.length > 1) {
      return const AssociationEvaluation._(
        status: AssociationEvaluationStatus.ambiguousLegacyState,
      );
    }
    if (legacyCandidates.length == 1) {
      return AssociationEvaluation._(
        status: AssociationEvaluationStatus.unresolvedLegacyAssociation,
        currentFingerprint: fingerprint,
        legacyCandidateFingerprint: legacyCandidates.single,
      );
    }

    // Genuinely no marker, no legacy bucket -- ordinary A/B decision, keyed
    // on whether local Kept history already exists.
    final List<KeptRecord> records;
    try {
      records = await _keptRepository.loadAllRecords();
    } on KeptRepositoryException {
      return AssociationEvaluation._(
        status: AssociationEvaluationStatus.associationRequired,
        currentFingerprint: fingerprint,
      );
    }
    if (records.isEmpty) {
      return AssociationEvaluation._(
        status: AssociationEvaluationStatus.autoAssociable,
        currentFingerprint: fingerprint,
      );
    }
    return AssociationEvaluation._(
      status: AssociationEvaluationStatus.associationRequired,
      currentFingerprint: fingerprint,
    );
  }

  AssociationEvaluation? _evaluateAccountAvailability(
    CloudKitAccountSnapshot snapshot,
  ) {
    switch (snapshot.availability) {
      case CloudKitAccountAvailability.noAccount:
      case CloudKitAccountAvailability.restricted:
      case CloudKitAccountAvailability.couldNotDetermine:
      case CloudKitAccountAvailability.temporarilyUnavailable:
      case CloudKitAccountAvailability.unknown:
        return const AssociationEvaluation._(
          status: AssociationEvaluationStatus.accountUnavailable,
        );
      case CloudKitAccountAvailability.available:
        if (!snapshot.isPrivateDatabaseUsable ||
            !snapshot.fingerprintResolved ||
            snapshot.accountFingerprint == null ||
            snapshot.accountFingerprint!.isEmpty) {
          return const AssociationEvaluation._(
            status: AssociationEvaluationStatus.fingerprintUnresolved,
          );
        }
        return null;
    }
  }

  // -------------------------------------------------------------------
  // 2. authorizeAssociation() -- the only method that ever writes the
  //    marker for a genuinely new (or resuming) association.
  // -------------------------------------------------------------------

  /// Authorizes [fingerprint] as this device's durable association. Runs
  /// under [resourceKey]. Re-resolves the current CloudKit fingerprint
  /// fresh and refuses unless it exactly equals [fingerprint]; refuses to
  /// silently overwrite an existing, different marker. Performs no
  /// CloudKit network fetch, no bucket creation, no Kept mutation, no
  /// upload, and no bootstrap transition -- purely the association-marker
  /// write.
  Future<AssociationAuthorizationResult> authorizeAssociation({
    required String fingerprint,
  }) async {
    if (!looksLikeAccountFingerprint(fingerprint)) {
      return const AssociationAuthorizationResult(
        AssociationAuthorizationStatus.invalidFingerprint,
      );
    }

    // Build 26 Phase 4E-4 lock correction: `getAccountSnapshot()` is a
    // CloudKit bridge network call like any other -- it must never run
    // while `resourceKey` is held (see the class doc comment). It is
    // resolved here, entirely outside the lock, and its value is carried
    // by reference into the lock below purely for comparison against
    // freshly-read *local* durable state; it is never re-invoked once the
    // lock is held.
    final CloudKitAccountSnapshot snapshot;
    try {
      snapshot = await _bridge.getAccountSnapshot();
    } on CloudKitPlatformException {
      return const AssociationAuthorizationResult(
        AssociationAuthorizationStatus.accountMismatch,
      );
    }
    if (snapshot.availability != CloudKitAccountAvailability.available ||
        !snapshot.fingerprintResolved ||
        snapshot.accountFingerprint != fingerprint) {
      return const AssociationAuthorizationResult(
        AssociationAuthorizationStatus.accountMismatch,
      );
    }

    return _integrationCoordinator.runExclusive<AssociationAuthorizationResult>(
      resourceKey: resourceKey,
      operation: () async {
        // No CloudKit bridge call anywhere in this callback -- only durable
        // local reads/writes, using the `fingerprint` value already
        // confirmed fresh immediately above.
        final currentMarker =
            await _syncPersistenceStore.loadAssociatedAccountFingerprint();
        if (currentMarker != null && currentMarker != fingerprint) {
          return const AssociationAuthorizationResult(
            AssociationAuthorizationStatus.differentAssociationExists,
          );
        }

        final commit =
            await _syncPersistenceStore.commitAssociatedAccountFingerprint(
          fingerprint: fingerprint,
          expectedCurrent: currentMarker,
        );
        switch (commit.status) {
          case AssociatedAccountFingerprintCommitStatus.committed:
            return const AssociationAuthorizationResult(
              AssociationAuthorizationStatus.authorized,
            );
          case AssociatedAccountFingerprintCommitStatus.alreadyCommitted:
            return const AssociationAuthorizationResult(
              AssociationAuthorizationStatus.alreadyAuthorized,
            );
          case AssociatedAccountFingerprintCommitStatus.expectedCurrentMismatch:
            return const AssociationAuthorizationResult(
              AssociationAuthorizationStatus.differentAssociationExists,
            );
        }
      },
    );
  }

  // -------------------------------------------------------------------
  // 3. repairLegacyAssociationMarker() -- a separate, explicit,
  //    guarded write. Never hidden inside evaluateAssociation().
  // -------------------------------------------------------------------

  /// Repairs a genuinely absent marker for a device that already completed
  /// some bootstrap progress before this marker concept existed. Runs under
  /// [resourceKey]; re-resolves the current fingerprint fresh, re-derives
  /// the meaningful-legacy-bucket set fresh, and requires the fresh set to
  /// be exactly `{expectedCandidateFingerprint}` and the fresh fingerprint
  /// to equal it, before ever writing. Fails closed on any mismatch.
  Future<LegacyAssociationRepairResult> repairLegacyAssociationMarker({
    required String expectedCandidateFingerprint,
  }) async {
    // Build 26 Phase 4E-4 lock correction: resolved entirely outside the
    // integration lock -- see [authorizeAssociation]'s identical rationale.
    final CloudKitAccountSnapshot snapshot;
    try {
      snapshot = await _bridge.getAccountSnapshot();
    } on CloudKitPlatformException {
      return const LegacyAssociationRepairResult(
        LegacyAssociationRepairStatus.accountChanged,
      );
    }
    if (snapshot.availability != CloudKitAccountAvailability.available ||
        !snapshot.fingerprintResolved ||
        snapshot.accountFingerprint != expectedCandidateFingerprint) {
      return const LegacyAssociationRepairResult(
        LegacyAssociationRepairStatus.accountChanged,
      );
    }

    return _integrationCoordinator.runExclusive<LegacyAssociationRepairResult>(
      resourceKey: resourceKey,
      operation: () async {
        // No CloudKit bridge call anywhere in this callback.
        final currentMarker =
            await _syncPersistenceStore.loadAssociatedAccountFingerprint();
        if (currentMarker != null) {
          return const LegacyAssociationRepairResult(
            LegacyAssociationRepairStatus.markerAlreadyPresent,
          );
        }

        final candidates =
            await _syncPersistenceStore.loadMeaningfulAccountFingerprints();
        if (candidates.isEmpty) {
          return const LegacyAssociationRepairResult(
            LegacyAssociationRepairStatus.noCandidates,
          );
        }
        if (candidates.length > 1) {
          return const LegacyAssociationRepairResult(
            LegacyAssociationRepairStatus.ambiguousCandidates,
          );
        }
        if (candidates.single != expectedCandidateFingerprint) {
          return const LegacyAssociationRepairResult(
            LegacyAssociationRepairStatus.candidateMismatch,
          );
        }

        final commit =
            await _syncPersistenceStore.commitAssociatedAccountFingerprint(
          fingerprint: expectedCandidateFingerprint,
          expectedCurrent: null,
        );
        if (!commit.isCommitted) {
          return const LegacyAssociationRepairResult(
            LegacyAssociationRepairStatus.markerAlreadyPresent,
          );
        }
        return const LegacyAssociationRepairResult(
          LegacyAssociationRepairStatus.repaired,
        );
      },
    );
  }

  // -------------------------------------------------------------------
  // 4. runBootstrap() -- single-flight; the full remote-first sequence.
  // -------------------------------------------------------------------

  /// Runs (or resumes) bootstrap for whichever account is currently
  /// evaluated. Single-flight per instance -- a call made while a run is
  /// already in flight returns that exact same [Future].
  ///
  /// Broad shape: acquire the lock only for short, fresh reads; release it
  /// before any CloudKit network call (including, for a genuinely empty
  /// remote, the one-time control-record creation-and-verification round
  /// trip -- see [_createAndVerifyControlRecordOutsideLock]); reacquire it
  /// to revalidate everything fresh (association marker, bucket state)
  /// against the already-resolved account fingerprint and epoch before any
  /// write; perform the merge/backfill/promotion/completion sequence inside
  /// that one reacquired, continuously-held lock.
  Future<BootstrapRunResult> runBootstrap() {
    final existing = _inFlight;
    if (existing != null) return existing;
    final future = _runBootstrapOnce();
    _inFlight = future;
    future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
    return future;
  }

  Future<BootstrapRunResult> _runBootstrapOnce() async {
    final evaluation = await evaluateAssociation();
    switch (evaluation.status) {
      case AssociationEvaluationStatus.accountUnavailable:
        return const BootstrapRunResult(
          status: BootstrapRunStatus.accountUnavailable,
        );
      case AssociationEvaluationStatus.fingerprintUnresolved:
        return const BootstrapRunResult(
          status: BootstrapRunStatus.fingerprintUnresolved,
        );
      case AssociationEvaluationStatus.associationRequired:
        return const BootstrapRunResult(
          status: BootstrapRunStatus.associationRequired,
        );
      case AssociationEvaluationStatus.ambiguousLegacyState:
        return const BootstrapRunResult(
          status: BootstrapRunStatus.ambiguousLegacyState,
        );
      case AssociationEvaluationStatus.unresolvedLegacyAssociation:
        final repair = await repairLegacyAssociationMarker(
          expectedCandidateFingerprint: evaluation.legacyCandidateFingerprint!,
        );
        if (!repair.isResolved) {
          // Fail closed -- never proceed as though associated on an
          // unresolved repair attempt.
          return const BootstrapRunResult(
            status: BootstrapRunStatus.associationRequired,
          );
        }
        // Re-evaluate fresh rather than assuming -- the repaired marker now
        // resolves to resumeAssociation on a fresh read.
        return _proceedWithAuthorizedAssociation(
          evaluation.legacyCandidateFingerprint!,
        );
      case AssociationEvaluationStatus.autoAssociable:
        final fingerprint = evaluation.currentFingerprint!;
        final authorization =
            await authorizeAssociation(fingerprint: fingerprint);
        if (!authorization.isAuthorized) {
          return const BootstrapRunResult(
            status: BootstrapRunStatus.associationRequired,
          );
        }
        return _proceedWithAuthorizedAssociation(fingerprint);
      case AssociationEvaluationStatus.resumeAssociation:
        return _proceedWithAuthorizedAssociation(
          evaluation.currentFingerprint!,
        );
    }
  }

  Future<BootstrapRunResult> _proceedWithAuthorizedAssociation(
    String fingerprint,
  ) async {
    final bucket =
        await _integrationCoordinator.runExclusive<AccountSyncState?>(
      resourceKey: resourceKey,
      operation: () => _syncPersistenceStore.loadAccountState(fingerprint),
    );

    if (bucket == null ||
        bucket.bootstrapState == AccountBootstrapState.notStarted) {
      return _fetchAndMergeBaseline(fingerprint, bucket);
    }

    switch (bucket.bootstrapState) {
      case AccountBootstrapState.remoteBaselinePending:
      case AccountBootstrapState.localReconciliationPending:
        return _integrationCoordinator.runExclusive<BootstrapRunResult>(
          resourceKey: resourceKey,
          operation: () async {
            final fresh = await _syncPersistenceStore.loadAccountState(
              fingerprint,
            );
            if (fresh == null) {
              return const BootstrapRunResult(
                status: BootstrapRunStatus.persistenceFailure,
              );
            }
            return _advanceToLocalReconciliation(fingerprint, fresh);
          },
        );
      case AccountBootstrapState.complete:
        return _checkAlreadyCompleteForEpochChange(fingerprint, bucket);
      case AccountBootstrapState.notStarted:
      case AccountBootstrapState.associationRequired:
        // This coordinator never sets a bucket's own bootstrapState to
        // associationRequired (association is tracked at the marker level,
        // never fabricated as a bucket state) -- an unexpected value here
        // fails closed rather than guessing.
        return const BootstrapRunResult(
          status: BootstrapRunStatus.associationRequired,
        );
    }
  }

  /// Build 26 Phase 4E-4 lock correction: every CloudKit bridge call this
  /// method makes -- the account snapshot, zone configuration, the initial
  /// baseline fetch, and (only for a genuinely empty remote) the one-time
  /// control-record creation-and-verification round trip -- happens
  /// entirely before [resourceKey] is ever acquired. The lock is acquired
  /// exactly once, at the very end, purely to revalidate local durable
  /// state fresh and apply the already-fully-resolved result. See
  /// [_createAndVerifyControlRecordOutsideLock] and [_applyFetchedBaseline].
  ///
  /// Account revalidation happens at three points, bracketing every network
  /// call on both sides: once before the baseline fetch, once more
  /// immediately before any empty-remote control-record creation (the one
  /// branch that performs a write ahead of the lock), and once more
  /// immediately before the lock is reacquired. A mismatch at any point
  /// fails closed to `accountChangedDuringFetch` with zero modify call and
  /// zero local mutation.
  Future<BootstrapRunResult> _fetchAndMergeBaseline(
    String fingerprint,
    AccountSyncState? bucketAtStart,
  ) async {
    final CloudKitAccountSnapshot snapshot;
    try {
      snapshot = await _bridge.getAccountSnapshot();
    } on CloudKitPlatformException {
      return const BootstrapRunResult(
        status: BootstrapRunStatus.accountUnavailable,
      );
    }
    if (snapshot.availability != CloudKitAccountAvailability.available ||
        !snapshot.fingerprintResolved ||
        snapshot.accountFingerprint != fingerprint) {
      return const BootstrapRunResult(
        status: BootstrapRunStatus.accountChangedDuringFetch,
      );
    }

    try {
      final zoneResult = await _bridge.configurePrivateZone();
      if (!zoneResult.success) {
        return const BootstrapRunResult(status: BootstrapRunStatus.fetchFailed);
      }
    } on CloudKitPlatformException {
      return const BootstrapRunResult(status: BootstrapRunStatus.fetchFailed);
    }

    final CloudKitZoneChangesResult fetchResult;
    try {
      // Full baseline fetch: previousServerToken is always null here --
      // never SyncOrchestrator.runSyncPass, which would upload the outbox
      // before this baseline is even durable.
      fetchResult = await _bridge.fetchPrivateZoneChanges(
        const CloudKitZoneChangesRequest(previousServerToken: null),
      );
    } on CloudKitPlatformException {
      return const BootstrapRunResult(status: BootstrapRunStatus.fetchFailed);
    }
    if (fetchResult.outcome != CloudKitZoneChangesOutcome.success) {
      return const BootstrapRunResult(status: BootstrapRunStatus.fetchFailed);
    }
    if (fetchResult.changedSyncStateRecords.length > 1) {
      return const BootstrapRunResult(
        status: BootstrapRunStatus.controlRecordInvalid,
      );
    }

    // Resolve the epoch/checkpoint-token candidate this attempt will use
    // *if* the freshly-reacquired-lock bucket read (inside
    // [_applyFetchedBaseline]) still shows no existing bucket. A legacy
    // pre-4E-1 bucket (`bucketAtStart != null`) always keeps its own
    // already-established epoch instead -- this candidate is simply never
    // used in that case.
    final DataEpoch candidateEpoch;
    final String candidateCheckpointToken;
    if (bucketAtStart != null) {
      candidateEpoch = bucketAtStart.dataEpoch;
      candidateCheckpointToken = fetchResult.serverToken!;
    } else if (fetchResult.changedSyncStateRecords.isEmpty) {
      // Locked invariant: this is the one branch that performs a WRITE
      // (`modifyPrivateRecords`, inside `_createAndVerifyControlRecord
      // OutsideLock`) before the lock is ever reacquired. A plain "no
      // network under lock" guarantee is not strong enough on its own --
      // the account could have changed during the baseline fetch itself,
      // and creating/uploading a control record under a stale fingerprint
      // assumption must never happen. Resolve the account fresh, one more
      // time, strictly between the baseline fetch and the control-record
      // creation; a mismatch fails closed here with zero modify call and
      // zero local mutation.
      final CloudKitAccountSnapshot preCreationSnapshot;
      try {
        preCreationSnapshot = await _bridge.getAccountSnapshot();
      } on CloudKitPlatformException {
        return const BootstrapRunResult(
          status: BootstrapRunStatus.accountChangedDuringFetch,
        );
      }
      if (preCreationSnapshot.availability !=
              CloudKitAccountAvailability.available ||
          !preCreationSnapshot.fingerprintResolved ||
          preCreationSnapshot.accountFingerprint != fingerprint) {
        return const BootstrapRunResult(
          status: BootstrapRunStatus.accountChangedDuringFetch,
        );
      }

      final creation = await _createAndVerifyControlRecordOutsideLock(
        preUploadServerToken: fetchResult.serverToken!,
      );
      if (!creation.isSuccess) {
        return BootstrapRunResult(status: creation.failure!);
      }
      candidateEpoch = creation.epoch!;
      candidateCheckpointToken = creation.serverToken!;
    } else {
      candidateEpoch = fetchResult.changedSyncStateRecords.single.dataEpoch;
      candidateCheckpointToken = fetchResult.serverToken!;
    }

    // "REVALIDATION AFTER NETWORK": one final account check, still entirely
    // outside the lock, immediately before acquiring it -- the narrowest
    // possible staleness window between the last network read and the
    // durable local apply. A change here means zero local bootstrap
    // mutation occurs (`accountChangedDuringFetch`).
    final CloudKitAccountSnapshot finalSnapshot;
    try {
      finalSnapshot = await _bridge.getAccountSnapshot();
    } on CloudKitPlatformException {
      return const BootstrapRunResult(
        status: BootstrapRunStatus.accountChangedDuringFetch,
      );
    }
    if (finalSnapshot.availability != CloudKitAccountAvailability.available ||
        !finalSnapshot.fingerprintResolved ||
        finalSnapshot.accountFingerprint != fingerprint) {
      return const BootstrapRunResult(
        status: BootstrapRunStatus.accountChangedDuringFetch,
      );
    }

    // Reacquire the lock purely for durable local revalidation and apply --
    // no CloudKit bridge call anywhere in `_applyFetchedBaseline` or
    // anything it transitively calls.
    return _integrationCoordinator.runExclusive<BootstrapRunResult>(
      resourceKey: resourceKey,
      operation: () => _applyFetchedBaseline(
        fingerprint,
        fetchResult,
        candidateEpoch,
        candidateCheckpointToken,
      ),
    );
  }

  /// Build 26 Phase 4E-4 lock correction: the one-time, empty-remote
  /// `CKEastSyncState` creation sequence. Acquires no lock of its own and
  /// must never be called from within one.
  ///
  /// The native transport's documented save policy for
  /// [CloudKitRecordChangeInput.previousSystemFields] `== null` is a plain,
  /// non-conflict-detecting overwrite (see that field's own doc comment:
  /// "saves unconditionally... exactly as CloudKit's own `.changedKeys`
  /// policy") -- there is no Dart-visible primitive that makes creating
  /// this fixed-`recordName` singleton conditional on "does not already
  /// exist" the way `.ifServerRecordUnchanged` would for a record whose
  /// prior system fields are known. Concretely: if a second device races to
  /// create the same singleton at the same time, whichever write physically
  /// lands second at the server silently wins, with no error surfaced to
  /// either client.
  ///
  /// This method therefore never trusts its own freshly-generated epoch as
  /// authoritative. After the upload, it performs a mandatory incremental
  /// re-fetch (using the pre-upload token) and adopts whichever `dataEpoch`
  /// that read actually reports -- its own, if its write won any race, or a
  /// concurrent device's, if theirs did. If the re-fetch cannot produce an
  /// unambiguous single control record, this method fails closed
  /// (`controlRecordCreationUnverified`/`controlRecordInvalid`) rather than
  /// ever assuming its own generated value is correct; nothing is committed
  /// on any failure path here.
  ///
  /// Crash safety: if the process crashes after the upload but before the
  /// caller durably checkpoints, the local bucket remains absent, so the
  /// next `runBootstrap()` attempt starts over from
  /// [_fetchAndMergeBaseline]'s own initial fetch -- which this time
  /// observes the already-created control record directly
  /// (`changedSyncStateRecords` non-empty) and adopts its epoch without
  /// ever attempting a second creation.
  Future<_ControlRecordCreationOutcome>
      _createAndVerifyControlRecordOutsideLock({
    required String preUploadServerToken,
  }) async {
    final generatedEpoch = DataEpoch.generate();
    final controlProjection = CloudEastSyncStateProjection.current(
      dataEpoch: generatedEpoch,
      mutationId: _idFactory(),
    );
    try {
      final uploadResult = await _bridge.modifyPrivateRecords(
        CloudKitModifyRecordsRequest(
          records: [CloudKitRecordChangeInput.syncState(controlProjection)],
        ),
      );
      if (uploadResult.overallStatus !=
          CloudKitModifyRecordsOverallStatus.allSucceeded) {
        return const _ControlRecordCreationOutcome.failure(
          BootstrapRunStatus.fetchFailed,
        );
      }
    } on CloudKitPlatformException {
      return const _ControlRecordCreationOutcome.failure(
        BootstrapRunStatus.fetchFailed,
      );
    }

    // Mandatory post-upload verification -- never assume `generatedEpoch`
    // is authoritative. See this method's own doc comment.
    final CloudKitZoneChangesResult verifyResult;
    try {
      verifyResult = await _bridge.fetchPrivateZoneChanges(
        CloudKitZoneChangesRequest(previousServerToken: preUploadServerToken),
      );
    } on CloudKitPlatformException {
      return const _ControlRecordCreationOutcome.failure(
        BootstrapRunStatus.controlRecordCreationUnverified,
      );
    }
    if (verifyResult.outcome != CloudKitZoneChangesOutcome.success) {
      // Includes `tokenExpired`: cannot safely determine the authoritative
      // control record from an incremental read whose token just expired --
      // fail closed rather than trust the generated value. Nothing was
      // committed either way; a future retry starts over with a fresh
      // initial fetch.
      return const _ControlRecordCreationOutcome.failure(
        BootstrapRunStatus.controlRecordCreationUnverified,
      );
    }
    if (verifyResult.changedSyncStateRecords.length > 1) {
      return const _ControlRecordCreationOutcome.failure(
        BootstrapRunStatus.controlRecordInvalid,
      );
    }
    if (verifyResult.changedSyncStateRecords.isEmpty) {
      // The upload just reported success, yet this immediate incremental
      // re-fetch reports no control-record change at all -- an ambiguous
      // read-after-write gap this transport does not otherwise document.
      // Never assume the generated epoch is authoritative here.
      return const _ControlRecordCreationOutcome.failure(
        BootstrapRunStatus.controlRecordCreationUnverified,
      );
    }

    return _ControlRecordCreationOutcome.success(
      epoch: verifyResult.changedSyncStateRecords.single.dataEpoch,
      serverToken: verifyResult.serverToken!,
    );
  }

  Future<BootstrapRunResult> _applyFetchedBaseline(
    String fingerprint,
    CloudKitZoneChangesResult fetchResult,
    DataEpoch candidateEpochForNewBucket,
    String candidateCheckpointTokenForNewBucket,
  ) async {
    // No CloudKit bridge call anywhere in this method or anything it calls
    // -- the account and epoch were already fully resolved (and, for an
    // empty remote, verified) entirely outside this already-held lock.

    final marker =
        await _syncPersistenceStore.loadAssociatedAccountFingerprint();
    if (marker != fingerprint) {
      return const BootstrapRunResult(
        status: BootstrapRunStatus.associationRequired,
      );
    }

    // Idempotent-retry shortcut: another attempt (or an earlier step of this
    // same attempt, on a crash-retry, or a genuinely concurrent coordinator
    // instance sharing this same local store) may have already advanced
    // further. Never redo the merge in that case.
    final bucket = await _syncPersistenceStore.loadAccountState(fingerprint);
    if (bucket != null) {
      switch (bucket.bootstrapState) {
        case AccountBootstrapState.complete:
          // A concurrent attempt already completed bootstrap for this
          // account between this method's own outer fetch and this
          // reacquired, fresh-revalidated read. `_checkAlreadyCompleteFor
          // EpochChange` performs its own `fetchPrivateZoneChanges` network
          // call, which must never happen while `kept_sync_integration_v1`
          // is held (see the class doc comment) -- report success here and
          // let a future, independent `runBootstrap()` call make its own
          // epoch-check pass entirely outside any lock.
          return const BootstrapRunResult(
            status: BootstrapRunStatus.alreadyComplete,
          );
        case AccountBootstrapState.localReconciliationPending:
          return _promoteAndComplete(fingerprint, bucket);
        case AccountBootstrapState.remoteBaselinePending:
          return _advanceToLocalReconciliation(fingerprint, bucket);
        case AccountBootstrapState.notStarted:
        case AccountBootstrapState.associationRequired:
          break; // fall through to the genuine first-merge path below.
      }
    }

    // Genuine first-merge path. A freshly-re-read, already-existing bucket
    // (a legacy pre-4E-1 bucket at `notStarted`) always keeps its own
    // already-established epoch and never adopts the outside-lock
    // candidate computed for a hypothetically-absent bucket; only a
    // genuinely still-absent bucket uses that candidate.
    final DataEpoch epoch;
    final String checkpointToken;
    if (bucket != null) {
      epoch = bucket.dataEpoch;
      checkpointToken = fetchResult.serverToken!;
    } else {
      epoch = candidateEpochForNewBucket;
      checkpointToken = candidateCheckpointTokenForNewBucket;
    }

    final shapeFailure = _validateBatchShape(fetchResult);
    if (shapeFailure != null) return shapeFailure;

    final List<KeptRecord> physicalRecords;
    final List<LocalSyncIntent> intents;
    try {
      physicalRecords = await _keptRepository.loadAllRecords();
      intents = await _intentStore.loadIntents();
    } on KeptRepositoryException {
      return const BootstrapRunResult(
        status: BootstrapRunStatus.persistenceFailure,
      );
    } on LocalSyncIntentStoreException {
      return const BootstrapRunResult(
        status: BootstrapRunStatus.persistenceFailure,
      );
    }
    final outbox = bucket?.outbox ?? const <PersistedOutboxMutation>[];

    final outcomes = <_RecordOutcome>[];
    for (final incoming in fetchResult.changedKeptWisdomRecords) {
      final outcome = _resolveOneRecord(
        incomingRemote: incoming,
        physicalRecords: physicalRecords,
        intents: intents,
        outbox: outbox,
        epoch: epoch,
      );
      if (outcome == null) {
        return const BootstrapRunResult(
          status: BootstrapRunStatus.conflictAborted,
        );
      }
      outcomes.add(outcome);
    }

    // The merged snapshot is durable before local replacement, even when this
    // first association does not yet have an account bucket/outbox.
    for (final outcome in outcomes.where((o) => o.needsMergedUpload)) {
      final p = outcome.finalProjection;
      await _intentStore.enqueueIntent(LocalSyncIntent(
        intentId: p.mutationId,
        kind: LocalSyncIntentKind.update,
        payload: LocalSyncIntentPayload.active(
          revealId: p.revealId!,
          operation: p.reflectionText == null
              ? LocalSyncIntentOperation.reflectionDelete
              : LocalSyncIntentOperation.reflectionSave,
          wisdomText: p.wisdomText!,
          wisdomId: p.wisdomId,
          revealedAtMs: p.revealedAtMs!,
          keptAtMs: p.keptAtMs!,
          updatedAtMs: p.updatedAtMs,
          mutationId: p.mutationId,
          reflectionText: p.reflectionText,
          reflectedAtMs: p.reflectedAtMs,
          reflectionHistoryJson: p.reflectionHistoryJson,
          localId:
              outcome.preservedId ?? deriveIncomingKeptLocalId(p.revealId!),
        ),
        stage: LocalSyncIntentStage.pendingLocalApplication,
        enqueuedAt:
            DateTime.fromMillisecondsSinceEpoch(p.updatedAtMs, isUtc: true),
      ));
    }
    final nextRecords = List<KeptRecord>.of(physicalRecords);
    for (final outcome in outcomes) {
      _applyOutcomeToRecords(nextRecords, outcome);
    }
    try {
      await _keptRepository.replaceAllRecords(nextRecords);
    } on KeptRepositoryException {
      return const BootstrapRunResult(
        status: BootstrapRunStatus.persistenceFailure,
      );
    }

    for (final intent in await _intentStore.loadIntents()) {
      if (intent.stage == LocalSyncIntentStage.pendingLocalApplication &&
          outcomes.any((o) =>
              o.finalProjection ==
              _projectionFromIntentIndependentMirror(intent, epoch))) {
        await _intentStore.advanceIntentStage(
            intentId: intent.intentId,
            expectedStage: LocalSyncIntentStage.pendingLocalApplication,
            nextStage: LocalSyncIntentStage.localCommittedOutboxPending);
      }
    }
    for (final outcome in outcomes) {
      final intentId = outcome.intentIdToRetire;
      if (intentId != null) {
        await _intentStore.removeIntent(intentId);
      }
      final mutationId = outcome.outboxMutationIdToRetire;
      if (mutationId != null) {
        await _syncPersistenceStore.retireOutboxMutationIfCurrent(
          RetireOutboxMutationRequest(
            accountFingerprint: fingerprint,
            expectedDataEpoch: epoch,
            recordName: outcome.finalProjection.recordName,
            mutationId: mutationId,
          ),
        );
      }
    }

    final recordSystemFieldsUpdates = [
      for (final projection in fetchResult.changedKeptWisdomRecords)
        IncomingRecordSystemFieldsUpdate(
          recordName: projection.recordName,
          systemFields:
              fetchResult.keptWisdomRecordSystemFields[projection.recordName]!,
        ),
    ];

    final checkpointResult = bucket == null
        ? await _syncPersistenceStore.commitIncomingBatchCheckpoint(
            CommitIncomingBatchCheckpointRequest(
              accountFingerprint: fingerprint,
              mode: IncomingCheckpointMode.bootstrapCreate,
              pendingServerChangeToken: checkpointToken,
              bootstrapTargetDataEpoch: epoch,
              expectedBootstrapState: AccountBootstrapState.notStarted,
              nextBootstrapState: AccountBootstrapState.remoteBaselinePending,
              recordSystemFieldsUpdates: recordSystemFieldsUpdates,
            ),
          )
        : await _syncPersistenceStore.commitIncomingBatchCheckpoint(
            CommitIncomingBatchCheckpointRequest(
              accountFingerprint: fingerprint,
              mode: IncomingCheckpointMode.existingBucket,
              pendingServerChangeToken: checkpointToken,
              expectedCurrentDataEpoch: bucket.dataEpoch,
              expectedPreviousServerToken: bucket.serverChangeToken,
              expectedBootstrapState: AccountBootstrapState.notStarted,
              nextBootstrapState: AccountBootstrapState.remoteBaselinePending,
              recordSystemFieldsUpdates: recordSystemFieldsUpdates,
            ),
          );

    if (!checkpointResult.isCommitted) {
      return BootstrapRunResult(
        status: BootstrapRunStatus.persistenceFailure,
        appliedProjectionCount: outcomes.length,
      );
    }

    final updatedBucket = await _syncPersistenceStore.loadAccountState(
      fingerprint,
    );
    if (updatedBucket == null) {
      return BootstrapRunResult(
        status: BootstrapRunStatus.persistenceFailure,
        appliedProjectionCount: outcomes.length,
      );
    }
    return _advanceToLocalReconciliation(
      fingerprint,
      updatedBucket,
      appliedProjectionCount: outcomes.length,
    );
  }

  Future<BootstrapRunResult> _advanceToLocalReconciliation(
    String fingerprint,
    AccountSyncState bucket, {
    int appliedProjectionCount = 0,
  }) async {
    if (bucket.bootstrapState ==
        AccountBootstrapState.localReconciliationPending) {
      return _promoteAndComplete(
        fingerprint,
        bucket,
        appliedProjectionCount: appliedProjectionCount,
      );
    }
    if (bucket.bootstrapState != AccountBootstrapState.remoteBaselinePending) {
      return BootstrapRunResult(
        status: BootstrapRunStatus.persistenceFailure,
        appliedProjectionCount: appliedProjectionCount,
      );
    }

    // A `remoteBaselinePending` bucket with no `serverChangeToken` can never
    // arise from this coordinator's own transitions -- see
    // `BootstrapRunStatus.corruptedBucketState`'s doc comment. Fail closed
    // here, before any durable write, rather than force-unwrap a value
    // safety cannot guarantee is present.
    final token = bucket.serverChangeToken;
    if (token == null) {
      return BootstrapRunResult(
        status: BootstrapRunStatus.corruptedBucketState,
        appliedProjectionCount: appliedProjectionCount,
      );
    }

    final result = await _syncPersistenceStore.commitIncomingBatchCheckpoint(
      CommitIncomingBatchCheckpointRequest(
        accountFingerprint: fingerprint,
        mode: IncomingCheckpointMode.existingBucket,
        pendingServerChangeToken: token,
        expectedCurrentDataEpoch: bucket.dataEpoch,
        expectedPreviousServerToken: bucket.serverChangeToken,
        expectedBootstrapState: AccountBootstrapState.remoteBaselinePending,
        nextBootstrapState: AccountBootstrapState.localReconciliationPending,
      ),
    );
    if (!result.isCommitted) {
      return BootstrapRunResult(
        status: BootstrapRunStatus.persistenceFailure,
        appliedProjectionCount: appliedProjectionCount,
      );
    }
    final updated = await _syncPersistenceStore.loadAccountState(fingerprint);
    if (updated == null) {
      return BootstrapRunResult(
        status: BootstrapRunStatus.persistenceFailure,
        appliedProjectionCount: appliedProjectionCount,
      );
    }
    return _promoteAndComplete(
      fingerprint,
      updated,
      appliedProjectionCount: appliedProjectionCount,
    );
  }

  /// Build 26 Phase 4E-4, section 19/20: legacy backfill, then promotion of
  /// every outstanding `localCommittedOutboxPending` intent, then -- only
  /// once none remain unpromoted -- the `localReconciliationPending ->
  /// complete` transition. All three steps happen inside the single,
  /// already-held lock this method is always called from; the outer
  /// transaction is never released between them.
  Future<BootstrapRunResult> _promoteAndComplete(
    String fingerprint,
    AccountSyncState bucket, {
    int appliedProjectionCount = 0,
  }) async {
    // A `localReconciliationPending` bucket with no `serverChangeToken` can
    // never arise from this coordinator's own transitions -- see
    // `BootstrapRunStatus.corruptedBucketState`'s doc comment. Checked
    // *before* backfill/promotion so a corrupted bucket produces zero
    // outbox mutation and zero intent backfill, not a partial write
    // followed by a crash.
    final token = bucket.serverChangeToken;
    if (token == null) {
      return BootstrapRunResult(
        status: BootstrapRunStatus.corruptedBucketState,
        appliedProjectionCount: appliedProjectionCount,
      );
    }

    final backfilledCount = await _backfillLegacyLocalOnlyRecords(bucket);
    final promotedCount = await _promotePendingIntents(fingerprint, bucket);

    final result = await _syncPersistenceStore.commitIncomingBatchCheckpoint(
      CommitIncomingBatchCheckpointRequest(
        accountFingerprint: fingerprint,
        mode: IncomingCheckpointMode.existingBucket,
        pendingServerChangeToken: token,
        expectedCurrentDataEpoch: bucket.dataEpoch,
        expectedPreviousServerToken: bucket.serverChangeToken,
        expectedBootstrapState:
            AccountBootstrapState.localReconciliationPending,
        nextBootstrapState: AccountBootstrapState.complete,
      ),
    );
    if (!result.isCommitted) {
      return BootstrapRunResult(
        status: BootstrapRunStatus.persistenceFailure,
        appliedProjectionCount: appliedProjectionCount,
        backfilledIntentCount: backfilledCount,
        promotedIntentCount: promotedCount,
      );
    }
    return BootstrapRunResult(
      status: BootstrapRunStatus.completed,
      appliedProjectionCount: appliedProjectionCount,
      backfilledIntentCount: backfilledCount,
      promotedIntentCount: promotedCount,
    );
  }

  /// Section 19: reads POST-MERGE physical records fresh. Skips any record
  /// already tracked by an existing intent, and any record already
  /// represented in the bucket's own `recordSystemFields` (proof it was
  /// part of, or reconciled against, the just-applied remote baseline --
  /// see the class doc comment). Every backfilled intent copies the
  /// existing [KeptRecord]'s fields verbatim -- never a regenerated
  /// historical field, never `KeptRepository.keepOccurrence`, never a
  /// preset-replay parameter, never a free-tier check.
  Future<int> _backfillLegacyLocalOnlyRecords(AccountSyncState bucket) async {
    final List<KeptRecord> records;
    final List<LocalSyncIntent> intents;
    try {
      records = await _keptRepository.loadAllRecords();
      intents = await _intentStore.loadIntents();
    } on KeptRepositoryException {
      return 0;
    } on LocalSyncIntentStoreException {
      return 0;
    }
    final existingIntentRecordNames = intents.map((i) => i.recordName).toSet();

    var count = 0;
    for (final record in records) {
      final recordName = deriveKeptWisdomRecordName(record.revealId);
      if (existingIntentRecordNames.contains(recordName)) continue;
      if (bucket.recordSystemFields.containsKey(recordName)) continue;

      final intent = LocalSyncIntent(
        intentId: _idFactory(),
        kind: LocalSyncIntentKind.create,
        payload: LocalSyncIntentPayload.active(
          revealId: record.revealId,
          operation: LocalSyncIntentOperation.keep,
          wisdomText: record.wisdomText,
          revealedAtMs: record.revealedAt.millisecondsSinceEpoch,
          keptAtMs: record.keptAt.millisecondsSinceEpoch,
          updatedAtMs: record.updatedAt.millisecondsSinceEpoch,
          mutationId: record.mutationId,
          reflectionText: record.reflectionText,
          reflectionHistoryJson: record.reflectionHistoryJson,
          reflectedAtMs: record.reflectedAt?.millisecondsSinceEpoch,
          localId: record.id,
        ),
        stage: LocalSyncIntentStage.localCommittedOutboxPending,
        enqueuedAt: canonicalizeKeptTimestamp(_clock()),
      );
      try {
        await _intentStore.enqueueIntent(intent);
        count += 1;
      } on LocalSyncIntentStoreException {
        // Best-effort within this sweep -- a failed enqueue leaves this
        // record un-backfilled for this attempt only; a future retry
        // re-derives the same candidate set fresh (idempotent, since
        // nothing durable changed for this record).
      }
    }
    return count;
  }

  /// Section 20: promotes every intent currently at
  /// `localCommittedOutboxPending` -- both freshly-backfilled legacy
  /// intents and ordinary user mutations that landed during the network
  /// fetch window -- into the durable outbox, retiring each only after its
  /// enqueue is confirmed durable.
  Future<int> _promotePendingIntents(
    String fingerprint,
    AccountSyncState bucket,
  ) async {
    final intents = await _intentStore.loadIntents();
    final pending = intents
        .where(
          (i) => i.stage == LocalSyncIntentStage.localCommittedOutboxPending,
        )
        .toList(growable: false);

    var promoted = 0;
    for (final intent in pending) {
      final change = _toSyncChangeIndependentMirror(intent, bucket.dataEpoch);
      try {
        await _syncPersistenceStore.enqueueMutation(fingerprint, change);
      } on SyncPersistenceStoreException {
        continue; // Leave this intent parked; a future retry re-attempts it.
      } on ConflictingMutationIdentityException {
        continue;
      } on MutationEpochMismatchException {
        continue;
      }
      try {
        await _intentStore.removeIntent(intent.intentId);
        promoted += 1;
      } on LocalSyncIntentStoreException {
        // Enqueue is already durable (idempotent on retry, per
        // enqueueMutation's own same-content dedup rule); retiring this
        // intent failed this attempt -- a future retry re-enqueues (a
        // no-op) then retries removal.
      }
    }
    return promoted;
  }

  /// Section 13: only reachable when the marker matches and the bucket is
  /// already `complete`. Reads only the singleton control record through the
  /// content-minimal epoch API, independently of the incremental change
  /// token. This keeps an expired token recoverable by [SyncOrchestrator],
  /// which owns clearing it and performing the subsequent full refetch.
  /// This path mutates nothing regardless of the result.
  Future<BootstrapRunResult> _checkAlreadyCompleteForEpochChange(
    String fingerprint,
    AccountSyncState completeBucket,
  ) async {
    final CloudKitAccountSnapshot snapshot;
    try {
      snapshot = await _bridge.getAccountSnapshot();
    } on CloudKitPlatformException {
      return const BootstrapRunResult(
        status: BootstrapRunStatus.accountUnavailable,
      );
    }
    if (snapshot.availability != CloudKitAccountAvailability.available ||
        !snapshot.fingerprintResolved ||
        snapshot.accountFingerprint != fingerprint) {
      return const BootstrapRunResult(
        status: BootstrapRunStatus.accountChangedDuringFetch,
      );
    }

    final CloudKitSyncStateEpochResult epochResult;
    try {
      epochResult = await _bridge.fetchSyncStateEpoch();
    } on CloudKitPlatformException {
      return const BootstrapRunResult(status: BootstrapRunStatus.fetchFailed);
    }

    switch (epochResult.outcome) {
      case CloudKitSyncStateEpochOutcome.found:
        if (epochResult.dataEpoch == completeBucket.dataEpoch) {
          return const BootstrapRunResult(
            status: BootstrapRunStatus.alreadyComplete,
          );
        }
        return const BootstrapRunResult(
          status: BootstrapRunStatus.remoteEpochChangedRecoveryRequired,
        );
      case CloudKitSyncStateEpochOutcome.notFound:
        // A complete local bucket cannot safely continue after its remote
        // epoch barrier disappeared. Treat this exactly like an epoch
        // rotation: fail closed without mutating local Kept state.
        return const BootstrapRunResult(
          status: BootstrapRunStatus.remoteEpochChangedRecoveryRequired,
        );
      case CloudKitSyncStateEpochOutcome.failure:
      case CloudKitSyncStateEpochOutcome.unknown:
        return const BootstrapRunResult(
          status: BootstrapRunStatus.fetchFailed,
        );
    }
  }

  // -------------------------------------------------------------------
  // Merge-fold helpers -- independent mirrors of
  // IncomingKeptSyncCoordinator's own private algorithm (never a shared
  // call into that class).
  // -------------------------------------------------------------------

  BootstrapRunResult? _validateBatchShape(
      CloudKitZoneChangesResult fetchResult) {
    final seenRecordNames = <String>{};
    final seenRevealIds = <String>{};
    for (final projection in fetchResult.changedKeptWisdomRecords) {
      if (!seenRecordNames.add(projection.recordName)) {
        return const BootstrapRunResult(
          status: BootstrapRunStatus.conflictAborted,
        );
      }
      final revealId = projection.revealId;
      if (revealId != null && !seenRevealIds.add(revealId)) {
        return const BootstrapRunResult(
          status: BootstrapRunStatus.conflictAborted,
        );
      }
    }
    final systemFieldsKeys =
        fetchResult.keptWisdomRecordSystemFields.keys.toSet();
    if (systemFieldsKeys.length != seenRecordNames.length ||
        !systemFieldsKeys.containsAll(seenRecordNames)) {
      return const BootstrapRunResult(
        status: BootstrapRunStatus.conflictAborted,
      );
    }
    for (final value in fetchResult.keptWisdomRecordSystemFields.values) {
      if (value.isEmpty) {
        return const BootstrapRunResult(
          status: BootstrapRunStatus.conflictAborted,
        );
      }
    }
    return null;
  }

  _RecordOutcome? _resolveOneRecord({
    required CloudKeptWisdomProjection incomingRemote,
    required List<KeptRecord> physicalRecords,
    required List<LocalSyncIntent> intents,
    required List<PersistedOutboxMutation> outbox,
    required DataEpoch epoch,
  }) {
    final recordName = incomingRemote.recordName;

    _Candidate? physicalCandidate;
    for (final record in physicalRecords) {
      if (deriveKeptWisdomRecordName(record.revealId) == recordName) {
        physicalCandidate = _Candidate(
          source: _CandidateSource.physical,
          projection:
              CloudKeptWisdomProjection.active(record, dataEpoch: epoch),
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
          projection: _projectionFromIntentIndependentMirror(intent, epoch),
          recoveryId: intent.payload.localId,
          intentId: intent.intentId,
        );
        break;
      }
    }

    _Candidate? outboxCandidate;
    for (final entry in outbox) {
      if (entry.recordName == recordName) {
        outboxCandidate = _Candidate(
          source: _CandidateSource.outbox,
          projection: entry.change.projection,
          mutationId: entry.mutationId,
        );
        break;
      }
    }

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
      return _RecordOutcome(finalProjection: incomingRemote);
    }

    final finalOutcome = resolveKeptWisdomConflict(
      local: current.projection,
      remote: incomingRemote,
      authoritativeEpoch: epoch,
    );
    if (finalOutcome.isRejected) return null;

    final localWon = identical(finalOutcome.winner, current.projection);
    final retireEverythingLocal =
        !localWon || finalOutcome.reason == ConflictReason.identical;

    String? intentIdToRetire;
    String? outboxMutationIdToRetire;
    if (retireEverythingLocal) {
      if (intentCandidate != null) intentIdToRetire = intentCandidate.intentId;
      if (outboxCandidate != null) {
        outboxMutationIdToRetire = outboxCandidate.mutationId;
      }
    } else {
      if (intentCandidate != null &&
          intentCandidate.projection != current.projection) {
        intentIdToRetire = intentCandidate.intentId;
      }
      if (outboxCandidate != null &&
          outboxCandidate.projection != current.projection) {
        outboxMutationIdToRetire = outboxCandidate.mutationId;
      }
    }

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

  void _applyOutcomeToRecords(
      List<KeptRecord> records, _RecordOutcome outcome) {
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

  /// Mirrors `IncomingKeptSyncCoordinator._projectionFromIntent`/
  /// `KeptSyncIntegrationCoordinator._toSyncChange`'s exact active/tombstone
  /// conversion semantics independently -- never a shared call into either
  /// class. No new ids, no new timestamps -- every value taken directly
  /// from [intent]'s own already-captured payload.
  CloudKeptWisdomProjection _projectionFromIntentIndependentMirror(
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

  SyncChange _toSyncChangeIndependentMirror(
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
      return SyncChange(
        kind: SyncChangeKind.delete,
        projection: CloudKeptWisdomProjection.tombstone(tombstone),
        enqueuedAt: canonicalizeKeptTimestamp(_clock()),
      );
    }
    final record = KeptRecord(
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
    final kind = switch (intent.kind) {
      LocalSyncIntentKind.create => SyncChangeKind.create,
      LocalSyncIntentKind.update => SyncChangeKind.update,
      LocalSyncIntentKind.delete => SyncChangeKind.delete,
    };
    return SyncChange(
      kind: kind,
      projection:
          CloudKeptWisdomProjection.active(record, dataEpoch: dataEpoch),
      enqueuedAt: canonicalizeKeptTimestamp(_clock()),
    );
  }
}
