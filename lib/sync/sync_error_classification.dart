/// Build 26 Phase 4A: pure retryable-vs-permanent error classification. See
/// `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md` §3 (retry policy) and §7
/// (native bridge contract — "retryable versus permanent errors").
///
/// This file has no dependency on any real CloudKit error type (no
/// `cloudkit`/`CKError` package is added in this phase — see the design
/// doc §6). It defines a small, symbolic error-code vocabulary the future
/// native bridge is expected to report through, and a pure lookup from that
/// vocabulary to a handling category. The exact set of codes is expected to
/// be refined once Phase 4B's real native implementation exists; this is a
/// deliberately conservative starting contract, not a final one.
library;

/// How a sync engine caller should react to a given failure.
enum SyncErrorCategory {
  /// Retry using the bounded exponential backoff policy (design doc §3),
  /// honoring a server-provided retry-after hint when available.
  retryable,

  /// Retrying will not help without another change (e.g. a malformed
  /// payload, an invalid argument) — the failing operation must not be
  /// retried as-is.
  permanent,

  /// The failure is about account availability/identity, not the operation
  /// itself — handled by the account-boundary rules (design doc §5), not by
  /// ordinary retry/backoff.
  accountIssue,
}

/// Symbolic codes this design's native bridge is expected to report.
/// Deliberately not an exhaustive mirror of every real `CKError.Code` case
/// — only the ones this design's own retry/backoff and account-boundary
/// logic needs to distinguish.
const String syncErrorCodeNetworkUnavailable = 'networkUnavailable';
const String syncErrorCodeNetworkFailure = 'networkFailure';
const String syncErrorCodeServiceUnavailable = 'serviceUnavailable';
const String syncErrorCodeRequestRateLimited = 'requestRateLimited';
const String syncErrorCodeZoneBusy = 'zoneBusy';
const String syncErrorCodeServerRecordChanged = 'serverRecordChanged';
const String syncErrorCodeAccountTemporarilyUnavailable =
    'accountTemporarilyUnavailable';
const String syncErrorCodeNotAuthenticated = 'notAuthenticated';
const String syncErrorCodeInvalidArguments = 'invalidArguments';
const String syncErrorCodeUnknownItem = 'unknownItem';
const String syncErrorCodeIncompatibleVersion = 'incompatibleVersion';
const String syncErrorCodeQuotaExceeded = 'quotaExceeded';
const String syncErrorCodeLimitExceeded = 'limitExceeded';

/// Pure lookup from [code] to its handling category. An unrecognized code
/// is classified as [SyncErrorCategory.permanent] — a code this client does
/// not understand must never be silently retried forever; fail closed
/// (surface it, do not spin).
SyncErrorCategory classifySyncErrorCode(String code) {
  switch (code) {
    case syncErrorCodeNetworkUnavailable:
    case syncErrorCodeNetworkFailure:
    case syncErrorCodeServiceUnavailable:
    case syncErrorCodeRequestRateLimited:
    case syncErrorCodeZoneBusy:
    case syncErrorCodeServerRecordChanged:
    case syncErrorCodeQuotaExceeded:
    case syncErrorCodeLimitExceeded:
      return SyncErrorCategory.retryable;
    case syncErrorCodeAccountTemporarilyUnavailable:
    case syncErrorCodeNotAuthenticated:
      return SyncErrorCategory.accountIssue;
    case syncErrorCodeInvalidArguments:
    case syncErrorCodeUnknownItem:
    case syncErrorCodeIncompatibleVersion:
      return SyncErrorCategory.permanent;
    default:
      return SyncErrorCategory.permanent;
  }
}
