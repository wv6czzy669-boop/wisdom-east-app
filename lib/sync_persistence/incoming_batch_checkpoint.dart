/// Build 26 Phase 4E-1: the atomic incoming-checkpoint request/result
/// contract for [SyncPersistenceStore.commitIncomingBatchCheckpoint].
///
/// This file adds no CloudKit knowledge, no record shape, and no conflict
/// rule of its own -- it only describes, as plain value types, what a
/// future Phase 4E-3 incoming-apply transaction needs to durably commit in
/// one atomic sync-envelope write: a batch's system-fields updates and its
/// proposed next server change token, plus (optionally) an
/// [AccountBootstrapState] transition. Phase 4E-1 implements this operation;
/// it does not call it from anywhere, and it does not apply any incoming
/// record to Kept/Reflection storage (that remains Phase 4E-3's own,
/// separate responsibility -- see
/// `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md`'s Phase 4E-1 section).
///
/// Every value type here follows this codebase's existing privacy
/// discipline: no `toString()`/`toLogSafeSummary()` anywhere in this file
/// ever renders an account fingerprint, a `dataEpoch` value, a token value,
/// a record name, or a raw exception cause -- only categorical status,
/// counts, and booleans (see [CommitIncomingBatchCheckpointResult
/// .toLogSafeSummary]).
library;

import '../sync/data_epoch.dart';
import 'account_sync_state.dart';

/// Which of the two supported checkpoint shapes a
/// [CommitIncomingBatchCheckpointRequest] represents.
enum IncomingCheckpointMode {
  /// Commit against an account bucket that already exists -- the ordinary,
  /// expected case for every checkpoint after the very first one.
  existingBucket,

  /// Create a brand-new account bucket, from a null base epoch/token,
  /// using exactly one explicitly-supplied [DataEpoch] -- the one-time
  /// remote-bootstrap case (design doc §"Bootstrap order" step 3/5). Never
  /// inferred implicitly from null fields alone; a caller must opt into
  /// this mode explicitly, and every one of
  /// [CommitIncomingBatchCheckpointRequest]'s own bootstrap-path
  /// preconditions is still independently checked even when this mode is
  /// selected.
  bootstrapCreate,
}

/// One incoming record's opaque CloudKit system-fields value to durably
/// store, keyed by its deterministic record name.
///
/// A plain, narrow pair -- deliberately not a `Map<String, String>` on the
/// request itself, so a request carrying the same [recordName] twice (a
/// caller-side construction mistake, not a real duplicate-record scenario)
/// can be detected and rejected explicitly, rather than one entry silently
/// overwriting the other the way a `Map` literal would.
final class IncomingRecordSystemFieldsUpdate {
  const IncomingRecordSystemFieldsUpdate({
    required this.recordName,
    required this.systemFields,
  });

  /// The deterministic `east-kept-<revealId>` record name this system-fields
  /// value belongs to (`lib/sync/sync_record_identity.dart`).
  final String recordName;

  /// Opaque, transport-produced system-fields Base64 string. Never decoded
  /// or interpreted by this layer.
  final String systemFields;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is IncomingRecordSystemFieldsUpdate &&
        other.recordName == recordName &&
        other.systemFields == systemFields;
  }

  @override
  int get hashCode => Object.hash(recordName, systemFields);
}

/// One atomic incoming-checkpoint request.
///
/// Every field below is validated by
/// [SyncPersistenceStore.commitIncomingBatchCheckpoint] itself (never
/// trusted as already-correct) -- see that method's own doc comment for the
/// exact fail-closed rule each field participates in.
final class CommitIncomingBatchCheckpointRequest {
  const CommitIncomingBatchCheckpointRequest({
    required this.accountFingerprint,
    required this.mode,
    required this.pendingServerChangeToken,
    this.expectedCurrentDataEpoch,
    this.expectedPreviousServerToken,
    this.recordSystemFieldsUpdates = const [],
    this.expectedBootstrapState,
    this.nextBootstrapState,
    this.bootstrapTargetDataEpoch,
  });

  /// The opaque CloudKit account fingerprint this checkpoint targets.
  final String accountFingerprint;

  /// [IncomingCheckpointMode.existingBucket] or
  /// [IncomingCheckpointMode.bootstrapCreate].
  final IncomingCheckpointMode mode;

  /// The proposed next server change token to commit -- required in both
  /// modes. This is always the exact opaque value a successful
  /// `fetchPrivateZoneChanges` returned; never fabricated by this layer.
  final String pendingServerChangeToken;

  /// [IncomingCheckpointMode.existingBucket]: required -- the epoch the
  /// caller expects the current bucket to already have.
  /// [IncomingCheckpointMode.bootstrapCreate]: must be `null` -- there is no
  /// "current" epoch yet when creating a bucket for the first time.
  final DataEpoch? expectedCurrentDataEpoch;

  /// [IncomingCheckpointMode.existingBucket]: the token the caller expects
  /// is currently persisted (`null` means "expect no token yet").
  /// [IncomingCheckpointMode.bootstrapCreate]: must be `null`.
  final String? expectedPreviousServerToken;

  /// Every incoming record's system-fields value to durably store in this
  /// same atomic write. May be empty.
  final List<IncomingRecordSystemFieldsUpdate> recordSystemFieldsUpdates;

  /// Optional compare-and-swap guard: if supplied, the current bucket's
  /// [AccountSyncState.bootstrapState] must equal this value or the whole
  /// checkpoint fails closed. Required (non-null) whenever [nextBootstrapState]
  /// is supplied -- an unconditional "set to X" with no current-state check
  /// is never allowed.
  final AccountBootstrapState? expectedBootstrapState;

  /// Optional bootstrap-state transition to apply in the same atomic write.
  /// Validated against a fixed, explicit transition allowlist -- see
  /// `isValidBootstrapTransition` in `protected_sync_persistence_store.dart`.
  final AccountBootstrapState? nextBootstrapState;

  /// [IncomingCheckpointMode.bootstrapCreate]: required -- the exact epoch
  /// the newly-created bucket will use. Never fabricated by this layer; the
  /// caller must supply an already-resolved [DataEpoch].
  /// [IncomingCheckpointMode.existingBucket]: must be `null`.
  final DataEpoch? bootstrapTargetDataEpoch;
}

/// The categorical, content-safe outcome of one
/// [SyncPersistenceStore.commitIncomingBatchCheckpoint] call.
enum IncomingCheckpointStatus {
  /// The checkpoint committed successfully: every requested system-fields
  /// update and the new server change token are now durable in one atomic
  /// write, and any requested bootstrap-state transition was applied.
  committed,

  /// [IncomingCheckpointMode.existingBucket] was requested but no bucket
  /// exists yet for this account fingerprint.
  bucketMissing,

  /// [IncomingCheckpointMode.bootstrapCreate] was requested but a bucket
  /// already exists for this account fingerprint -- this checkpoint never
  /// overwrites an unexpectedly-existing bucket.
  bucketAlreadyExists,

  /// The current bucket's [AccountSyncState.dataEpoch] does not equal
  /// [CommitIncomingBatchCheckpointRequest.expectedCurrentDataEpoch].
  dataEpochMismatch,

  /// The current bucket's [AccountSyncState.serverChangeToken] does not
  /// equal [CommitIncomingBatchCheckpointRequest.expectedPreviousServerToken].
  previousTokenMismatch,

  /// The current bucket's [AccountSyncState.bootstrapState] does not equal
  /// [CommitIncomingBatchCheckpointRequest.expectedBootstrapState].
  bootstrapStateMismatch,

  /// The requested [CommitIncomingBatchCheckpointRequest.nextBootstrapState]
  /// transition is not on the explicit valid-transition allowlist.
  invalidBootstrapTransition,

  /// [CommitIncomingBatchCheckpointRequest.recordSystemFieldsUpdates]
  /// contains the same record name more than once.
  duplicateRecordName,

  /// A record-system-fields entry's record name or value does not look like
  /// a genuine deterministic record name / opaque Base64 value.
  invalidRecordSystemFields,

  /// The request itself is structurally invalid for its declared [mode]
  /// (e.g. a `bootstrapCreate` request supplying a non-null
  /// [CommitIncomingBatchCheckpointRequest.expectedCurrentDataEpoch], or an
  /// `existingBucket` request with no
  /// [CommitIncomingBatchCheckpointRequest.expectedCurrentDataEpoch] at
  /// all) -- caught before any state is ever read.
  invalidRequest,
}

/// The full, content-safe result of one
/// [SyncPersistenceStore.commitIncomingBatchCheckpoint] call.
final class CommitIncomingBatchCheckpointResult {
  const CommitIncomingBatchCheckpointResult({
    required this.status,
    this.systemFieldCount = 0,
    this.bootstrapStateChanged = false,
    this.tokenChanged = false,
  });

  final IncomingCheckpointStatus status;

  /// Number of record-system-fields entries durably committed this call.
  /// Always `0` on a non-[IncomingCheckpointStatus.committed] result.
  final int systemFieldCount;

  /// Whether the bucket's [AccountSyncState.bootstrapState] actually changed
  /// as part of this call. Always `false` on a non-[IncomingCheckpointStatus
  /// .committed] result.
  final bool bootstrapStateChanged;

  /// Whether the bucket's [AccountSyncState.serverChangeToken] actually
  /// changed as part of this call. Always `false` on a
  /// non-[IncomingCheckpointStatus.committed] result.
  final bool tokenChanged;

  bool get isCommitted => status == IncomingCheckpointStatus.committed;

  /// A privacy-safe summary: status, counts, and booleans only -- never an
  /// account fingerprint, a `dataEpoch`, a token, or a record name.
  Map<String, Object?> toLogSafeSummary() => {
        'status': status.name,
        'systemFieldCount': systemFieldCount,
        'bootstrapStateChanged': bootstrapStateChanged,
        'tokenChanged': tokenChanged,
      };

  @override
  String toString() =>
      'CommitIncomingBatchCheckpointResult(${toLogSafeSummary()})';
}
