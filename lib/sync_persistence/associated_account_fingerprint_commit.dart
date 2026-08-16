/// Build 26 Phase 4E-4: the typed, content-safe result of one
/// [SyncPersistenceStore.commitAssociatedAccountFingerprint] compare-and-swap
/// attempt.
///
/// This is deliberately a narrow, single-purpose CAS primitive -- never a
/// generic "set any envelope field" API, mirroring
/// `outbox_mutation_retirement.dart`'s own precedent for a small, dedicated
/// typed-result file per narrow persistence operation.
/// [SyncPersistenceStore.commitAssociatedAccountFingerprint] never creates
/// or touches an [AccountSyncState][], never fabricates a `DataEpoch`, and
/// never silently replaces a different, already-durable marker -- see that
/// method's own doc comment for the full contract.
///
/// Every value type here follows this codebase's existing privacy
/// discipline: [CommitAssociatedAccountFingerprintResult.toLogSafeSummary]
/// never renders the fingerprint value being committed or the fingerprint
/// already on file -- only categorical status.
library;

/// The categorical, content-safe outcome of one
/// [SyncPersistenceStore.commitAssociatedAccountFingerprint] call.
enum AssociatedAccountFingerprintCommitStatus {
  /// The marker's current value exactly equalled the caller's
  /// `expectedCurrent` and is now durably set to the requested fingerprint.
  committed,

  /// The marker already held exactly the requested fingerprint before this
  /// call -- an idempotent no-op repeat. No envelope write occurred.
  alreadyCommitted,

  /// The marker's actual current value did not equal the caller's
  /// `expectedCurrent` -- a different fingerprint is already durably
  /// associated (or the marker was unexpectedly absent/present relative to
  /// what the caller expected). Never overwritten.
  expectedCurrentMismatch,
}

/// The full, content-safe result of one
/// [SyncPersistenceStore.commitAssociatedAccountFingerprint] call.
final class CommitAssociatedAccountFingerprintResult {
  const CommitAssociatedAccountFingerprintResult(this.status);

  final AssociatedAccountFingerprintCommitStatus status;

  bool get isCommitted =>
      status == AssociatedAccountFingerprintCommitStatus.committed ||
      status == AssociatedAccountFingerprintCommitStatus.alreadyCommitted;

  /// A privacy-safe summary: status only -- never a fingerprint value.
  Map<String, Object?> toLogSafeSummary() => {'status': status.name};

  @override
  String toString() =>
      'CommitAssociatedAccountFingerprintResult(${toLogSafeSummary()})';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CommitAssociatedAccountFingerprintResult &&
        other.status == status;
  }

  @override
  int get hashCode => status.hashCode;
}

/// Build 26 Phase 5 (slice 3): the categorical, content-safe outcome of one
/// [SyncPersistenceStore.clearAssociatedAccountFingerprintIfCurrent] call --
/// the durable marker's *only* clearing path (there was previously no way to
/// null it out at all; [SyncPersistenceEnvelope.withAssociatedAccountFingerprintCleared]
/// is the corresponding narrow, unconditional envelope-level primitive this
/// method's own compare-and-swap guard sits in front of).
///
/// This is deliberately a fail-closed compare-and-swap, mirroring
/// [AssociatedAccountFingerprintCommitStatus]'s own shape exactly: a marker
/// that currently names a *different* fingerprint than the caller's
/// `expectedCurrent` is never cleared, never overwritten, and never silently
/// retargeted -- see the local-finalize "ACCOUNT SAFETY" contract this exists
/// to support (a device that associated a genuinely new account after a
/// "Remove from iCloud" transaction began must never have that new
/// association silently torn down by a finalizer still cleaning up the old
/// one).
enum AssociatedAccountFingerprintClearStatus {
  /// The marker held exactly [expectedCurrent] and is now durably cleared to
  /// `null`.
  cleared,

  /// The marker was already `null` before this call -- an idempotent no-op
  /// repeat. No envelope write occurred.
  alreadyClear,

  /// The marker's actual current value is a *different*, non-null
  /// fingerprint than the caller's `expectedCurrent` -- fail-closed. Never
  /// cleared, never overwritten.
  expectedCurrentMismatch,
}

/// The full, content-safe result of one
/// [SyncPersistenceStore.clearAssociatedAccountFingerprintIfCurrent] call.
final class ClearAssociatedAccountFingerprintResult {
  const ClearAssociatedAccountFingerprintResult(this.status);

  final AssociatedAccountFingerprintClearStatus status;

  bool get isClear =>
      status == AssociatedAccountFingerprintClearStatus.cleared ||
      status == AssociatedAccountFingerprintClearStatus.alreadyClear;

  /// A privacy-safe summary: status only -- never a fingerprint value.
  Map<String, Object?> toLogSafeSummary() => {'status': status.name};

  @override
  String toString() =>
      'ClearAssociatedAccountFingerprintResult(${toLogSafeSummary()})';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ClearAssociatedAccountFingerprintResult &&
        other.status == status;
  }

  @override
  int get hashCode => status.hashCode;
}
