/// Build 26 Phase 4E-3b: the typed request/result contract for
/// [SyncPersistenceStore.retireOutboxMutationIfCurrent].
///
/// This is deliberately **not** a reuse of
/// [SyncPersistenceStore.applyMutationOutcomes]: that method's
/// `acknowledgedMutationIds` semantics mean "CloudKit's own transport
/// explicitly confirmed this exact local upload succeeded" -- a remote
/// conflict *loss* (this local mutation lost a conflict-resolution decision
/// to an incoming remote winner during Phase 4E-3b incoming apply) is a
/// categorically different event: CloudKit never acknowledged an upload of
/// this content at all. Conflating the two would make a future push-outcome
/// diagnostic (or a future retry-classification rule keyed off
/// "acknowledged") silently misrepresent a conflict loss as a successful
/// push. This file exists so that distinction is structurally impossible to
/// blur.
///
/// Every value type here follows this codebase's existing privacy
/// discipline: no `toString()`/`toLogSafeSummary()` anywhere in this file
/// ever renders an account fingerprint, a `dataEpoch` value, a record name,
/// or a mutation id -- only categorical status.
library;

import '../sync/data_epoch.dart';

/// One request to retire (permanently remove) exactly one outbox mutation,
/// only if the outbox's *current* entry for [recordName] still exactly
/// matches [mutationId] -- never a blind "delete whatever is queued for this
/// record" operation.
final class RetireOutboxMutationRequest {
  const RetireOutboxMutationRequest({
    required this.accountFingerprint,
    required this.expectedDataEpoch,
    required this.recordName,
    required this.mutationId,
  });

  /// The opaque CloudKit account fingerprint whose bucket this request
  /// targets. Never rendered by any `toString()`/`toLogSafeSummary()` in
  /// this file.
  final String accountFingerprint;

  /// The bucket's `dataEpoch` the caller expects to still be current. A
  /// mismatch (an epoch reset happened since this mutation was queued) fails
  /// this request closed -- never retires a mutation queued under a
  /// since-superseded epoch by mistake.
  final DataEpoch expectedDataEpoch;

  /// The deterministic CloudKit record identity this retirement targets.
  /// Never wisdom text, never a display date.
  final String recordName;

  /// The exact `mutationId` the caller expects the current outbox entry for
  /// [recordName] to carry. A newer, different `mutationId` currently queued
  /// for the same [recordName] (the record was superseded by a later local
  /// edit after this stale retirement request was computed) is never
  /// removed -- this guard is what makes that structurally impossible.
  final String mutationId;
}

/// The categorical, content-safe outcome of one
/// [SyncPersistenceStore.retireOutboxMutationIfCurrent] call.
enum RetireOutboxMutationStatus {
  /// The current outbox entry for [RetireOutboxMutationRequest.recordName]
  /// matched [RetireOutboxMutationRequest.mutationId] exactly and was
  /// durably removed.
  retired,

  /// No bucket exists yet for
  /// [RetireOutboxMutationRequest.accountFingerprint]. A no-op -- never
  /// creates a bucket merely to discover it has nothing to retire.
  accountMissing,

  /// The bucket's current `dataEpoch` does not equal
  /// [RetireOutboxMutationRequest.expectedDataEpoch].
  dataEpochMismatch,

  /// No outbox entry currently exists for
  /// [RetireOutboxMutationRequest.recordName]. A no-op -- it may already
  /// have been retired by an earlier, possibly-retried call, or already
  /// acknowledged via [SyncPersistenceStore.applyMutationOutcomes].
  recordNotFound,

  /// An outbox entry exists for
  /// [RetireOutboxMutationRequest.recordName], but its current `mutationId`
  /// does not equal [RetireOutboxMutationRequest.mutationId] -- a newer
  /// mutation has superseded the one this request targeted. Never removed.
  mutationIdMismatch,
}

/// The full, content-safe result of one
/// [SyncPersistenceStore.retireOutboxMutationIfCurrent] call.
final class RetireOutboxMutationResult {
  const RetireOutboxMutationResult(this.status);

  final RetireOutboxMutationStatus status;

  bool get isRetired => status == RetireOutboxMutationStatus.retired;

  /// A privacy-safe summary: status only -- never an account fingerprint, a
  /// `dataEpoch`, a record name, or a mutation id.
  Map<String, Object?> toLogSafeSummary() => {'status': status.name};

  @override
  String toString() => 'RetireOutboxMutationResult(${toLogSafeSummary()})';
}
