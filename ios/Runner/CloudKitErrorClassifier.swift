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
  static let limitExceeded = "limitExceeded"

  /// Build 26 Phase 4B-2: `CKError.Code.serverRejectedRequest` (raw code
  /// 15), confirmed on a physical device as the error `EASTKeptZone`'s
  /// initial fetch returns before the zone exists (CloudKit Console:
  /// ZoneFetch / SERVER_ERROR / INTERNAL_ERROR), even though directly
  /// saving the same zone succeeds. Handled by
  /// `CloudKitPrivateZoneCoordinator`'s guarded create-fallback -- this
  /// symbolic code is reported only when that fallback (or the create
  /// operation itself) still fails. Not retried by this classifier or by
  /// `lib/sync/sync_error_classification.dart`'s `classifySyncErrorCode`
  /// (an unrecognized-by-name code there defaults to
  /// `SyncErrorCategory.permanent`, i.e. non-retryable) -- there is no
  /// existing authoritative rule making a rejected request retryable.
  static let serverRejectedRequest = "serverRejectedRequest"

  /// Build 26 Phase 4C-2: five additional stable symbolic codes, needed
  /// because the record-transport operations (`CKModifyRecordsOperation`/
  /// `CKFetchRecordZoneChangesOperation`) can surface `CKError` codes the
  /// zone-configuration-only Phase 4B-1/4B-2 classifier never had to name.
  /// Each mirrors a literal string this classifier's own convention already
  /// establishes (the bare, lowerCamelCase `CKError.Code` case name) --
  /// consistent with every existing constant above, not a new naming
  /// scheme. None of these five is added to
  /// `lib/sync/sync_error_classification.dart`'s explicit lookup table:
  /// that function already defaults any code it does not recognize by name
  /// to `SyncErrorCategory.permanent` (fail closed), which is the correct,
  /// intended category for all five (none is safely retryable without a
  /// change in circumstance a blind retry cannot produce) -- exactly the
  /// same reasoning already applied to `serverRejectedRequest` above.
  static let permissionFailure = "permissionFailure"
  static let zoneNotFound = "zoneNotFound"
  static let badContainer = "badContainer"
  static let badDatabase = "badDatabase"

  /// `CKError.Code.changeTokenExpired` -- `CloudKitRecordTransportCoordinator`
  /// intercepts this *before* it would ever reach this classifier for a
  /// zone-changes fetch (surfaced instead as a dedicated
  /// `CloudKitZoneChangesOutcome.tokenExpired`, never a generic errorCode,
  /// since its correct handling -- discard the token, resync from `nil` --
  /// is categorically different from an ordinary retryable/permanent
  /// failure). This constant exists so the symbolic vocabulary still has a
  /// name for the underlying `CKError` case if it is ever encountered
  /// somewhere other than that one dedicated fetch path (e.g. a defensive
  /// catch-all), and so native tests can assert on it directly.
  static let changeTokenExpired = "changeTokenExpired"

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
    case .limitExceeded:
      return limitExceeded
    case .serverRejectedRequest:
      return serverRejectedRequest
    case .permissionFailure:
      return permissionFailure
    case .zoneNotFound:
      return zoneNotFound
    case .badContainer:
      return badContainer
    case .badDatabase:
      return badDatabase
    case .changeTokenExpired:
      return changeTokenExpired
    default:
      if #available(iOS 15.0, *), ckError.code == .accountTemporarilyUnavailable {
        return accountTemporarilyUnavailable
      }
      return unrecognizedNativeError
    }
  }
}
