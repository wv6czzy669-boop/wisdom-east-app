import CloudKit

/// Build 26 Phase 4B-1: pure mapping from `CKAccountStatus` to the
/// normalized, content-free wire strings the Dart side understands (see
/// `lib/sync_platform/cloud_kit_account_snapshot.dart`'s
/// `CloudKitAccountAvailability`). No CloudKit call happens here -- this is
/// a pure function over a value already obtained elsewhere, kept in its
/// own file specifically so it is a small, isolated, easily-inspected unit.
enum CloudKitAccountStatusMapper {
  static let available = "available"
  static let noAccount = "noAccount"
  static let restricted = "restricted"
  static let couldNotDetermine = "couldNotDetermine"
  static let temporarilyUnavailable = "temporarilyUnavailable"
  static let unknown = "unknown"

  /// Normalizes `status` to one of this enum's string constants. Never
  /// returns anything outside that fixed vocabulary, and never throws --
  /// an unrecognized/future `CKAccountStatus` case (one added by a newer
  /// SDK than this file was last updated against) safely normalizes to
  /// `unknown` rather than being silently coerced to `available`.
  ///
  /// Build 26 Phase 4B-1 correction: `.temporarilyUnavailable` is listed as
  /// its own explicit `case` below, not folded into `@unknown default`.
  /// `@unknown default` in Swift only excuses *genuinely future* cases the
  /// compiler cannot yet see -- for a case the current SDK already knows
  /// about (as `.temporarilyUnavailable` is, on the Xcode/SDK this project
  /// now builds with), the compiler correctly still requires it listed
  /// explicitly ("switch must be exhaustive / add missing case:
  /// .temporarilyUnavailable"), and it compiles cleanly on this project's
  /// iOS 13 deployment target: matching against an existing enum case in a
  /// `switch` never constructs a new value of that case, so no `#available`
  /// guard is required here, and the app can never actually receive
  /// `.temporarilyUnavailable` at runtime on an OS old enough to lack it in
  /// the first place. `@unknown default` is retained purely for any case
  /// added by a future SDK this file has not been updated for yet.
  static func normalize(_ status: CKAccountStatus) -> String {
    switch status {
    case .available:
      return available
    case .noAccount:
      return noAccount
    case .restricted:
      return restricted
    case .couldNotDetermine:
      return couldNotDetermine
    case .temporarilyUnavailable:
      return temporarilyUnavailable
    @unknown default:
      return unknown
    }
  }
}
