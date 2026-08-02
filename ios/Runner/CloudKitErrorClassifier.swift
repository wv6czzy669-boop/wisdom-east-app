import CloudKit

/// Build 26 Phase 4B-1: maps a Swift `Error` (expected to usually be a
/// `CKError`, but never assumed to be) to one of the small set of symbolic
/// error codes `lib/sync/sync_error_classification.dart` already defines.
///
/// This file never computes retryability itself -- see the design doc §7:
/// "Swift only reports what happened"; Dart owns classification via the
/// existing pure `classifySyncErrorCode` function. Never reads or forwards
/// `error.localizedDescription` or any other user-facing message string.
enum CloudKitErrorClassifier {
  // Mirrors the exact string constants in
  // `lib/sync/sync_error_classification.dart` so Dart's existing
  // classifier recognizes them directly, with no separate translation
  // table needed on either side.
  static let networkUnavailable = "networkUnavailable"
  static let networkFailure = "networkFailure"
  static let serviceUnavailable = "serviceUnavailable"
  static let requestRateLimited = "requestRateLimited"
  static let zoneBusy = "zoneBusy"
  static let serverRecordChanged = "serverRecordChanged"
  static let accountTemporarilyUnavailable = "accountTemporarilyUnavailable"
  static let notAuthenticated = "notAuthenticated"
  static let invalidArguments = "invalidArguments"
  static let unknownItem = "unknownItem"
  static let incompatibleVersion = "incompatibleVersion"
  static let quotaExceeded = "quotaExceeded"

  /// Reported for any error this classifier does not recognize, including
  /// a non-`CKError` failure. Dart's `classifySyncErrorCode` already
  /// defaults any code it does not recognize to `permanent` (fail closed),
  /// so this is safe to report as-is without a matching Dart-side entry.
  static let unrecognizedNativeError = "unrecognizedNativeError"

  static func symbolicCode(for error: Error) -> String {
    guard let ckError = error as? CKError else {
      return unrecognizedNativeError
    }

    switch ckError.code {
    case .networkUnavailable:
      return networkUnavailable
    case .networkFailure:
      return networkFailure
    case .serviceUnavailable:
      return serviceUnavailable
    case .requestRateLimited:
      return requestRateLimited
    case .zoneBusy:
      return zoneBusy
    case .serverRecordChanged:
      return serverRecordChanged
    case .notAuthenticated:
      return notAuthenticated
    case .invalidArguments:
      return invalidArguments
    case .unknownItem:
      return unknownItem
    case .incompatibleVersion:
      return incompatibleVersion
    case .quotaExceeded:
      return quotaExceeded
    default:
      if #available(iOS 15.0, *), ckError.code == .accountTemporarilyUnavailable {
        return accountTemporarilyUnavailable
      }
      return unrecognizedNativeError
    }
  }
}
