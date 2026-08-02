import Foundation

/// Build 26 Phase 4B-1: constants for the native CloudKit bridge
/// foundation. See `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md`'s
/// Phase 4B-1 section for the full channel contract this mirrors on the
/// Dart side (`lib/sync_platform/method_channel_cloud_kit_platform_bridge.dart`).
///
/// The custom zone name and record-type names below are the exact Phase 4A
/// values already defined in `lib/sync/sync_record_identity.dart` -- this
/// file never invents a competing name; it is this project's one
/// authoritative *native-side* copy of those same literal values, since
/// Swift and Dart cannot share a single source file.
enum CloudKitSyncBridgeConstants {
  static let methodChannelName = "com.dogukan.dailywisdom/cloudkit_sync"
  static let eventChannelName = "com.dogukan.dailywisdom/cloudkit_sync_events"

  static let methodGetAccountSnapshot = "getAccountSnapshot"
  static let methodConfigurePrivateZone = "configurePrivateZone"
  static let methodGetBridgeInfo = "getBridgeInfo"

  /// Bumped whenever the wire shape of any method's result changes.
  static let bridgeVersion = 1

  /// Phase 4A's one custom CloudKit zone -- mirrors
  /// `lib/sync/sync_record_identity.dart`'s `keptRecordZoneName`.
  static let expectedZoneName = "EASTKeptZone"

  /// Phase 4A's record types -- mirrors
  /// `lib/sync/sync_record_identity.dart`'s `keptWisdomRecordType` and
  /// `syncStateRecordType`.
  static let expectedRecordTypes = ["CKKeptWisdom", "CKEastSyncState"]

  /// Documented, proposed default container identifier for Phase 4B-2
  /// (`docs/architecture/EAST_CLOUDKIT_SYNC_V1.md`'s Phase 4B-1 section) --
  /// deliberately **not referenced anywhere else in this bridge's code**.
  /// Production code always uses `CKContainer.default()` so Xcode-managed
  /// entitlements remain the single source of truth for which container is
  /// actually used; this string exists only so the proposed identifier is
  /// written down before Phase 4B-2 registers it for real.
  static let proposedContainerIdentifierForPhase4B2 = "iCloud.com.dogukan.dailywisdom"

  /// Content-free account-change event payload key/value -- mirrors
  /// `CloudKitAccountChangeEventKind.accountChanged` on the Dart side.
  static let eventPayloadKey = "event"
  static let accountChangedEventName = "accountChanged"
}
