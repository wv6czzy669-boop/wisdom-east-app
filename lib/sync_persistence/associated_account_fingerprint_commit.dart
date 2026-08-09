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
