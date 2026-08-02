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

  /// Build 26 Phase 4C-2: the two record-transport methods. Names chosen to
  /// match the Phase 4C-2 instruction's own suggested naming exactly.
  static let methodModifyPrivateRecords = "modifyPrivateRecords"
  static let methodFetchPrivateZoneChanges = "fetchPrivateZoneChanges"

  /// Bumped whenever the wire shape of any method's result changes.
  static let bridgeVersion = 1

  /// Phase 4A's one custom CloudKit zone -- mirrors
  /// `lib/sync/sync_record_identity.dart`'s `keptRecordZoneName`.
  static let expectedZoneName = "EASTKeptZone"

  /// Phase 4A's record types -- mirrors
  /// `lib/sync/sync_record_identity.dart`'s `keptWisdomRecordType` and
  /// `syncStateRecordType`.
  static let expectedRecordTypes = ["CKKeptWisdom", "CKEastSyncState"]

  /// The container identifier Phase 4B-2 registered in
  /// `ios/Runner/Runner.entitlements`
  /// (`com.apple.developer.icloud-container-identifiers`). Phase 4B-1's
  /// account-status/zone-configuration bridge (`getAccountSnapshot`,
  /// `configurePrivateZone`) still resolves `CKContainer.default()`,
  /// unmodified by this correction, per the standing rule against touching
  /// pre-Phase-4C-2 account/zone code without necessity.
  ///
  /// Build 26 Phase 4C-2 correction: the private record transport
  /// (`modifyPrivateRecords`/`fetchPrivateZoneChanges`) does **not** use
  /// `CKContainer.default()` -- it constructs `CKContainer(identifier:
  /// containerIdentifier)` explicitly (see `CloudKitSyncBridge
  /// .transportContainer`), so the transport's container is never left to
  /// depend on which entitlement Xcode happens to resolve `.default()` to.
  static let containerIdentifier = "iCloud.com.dogukan.dailywisdom"

  /// Content-free account-change event payload key/value -- mirrors
  /// `CloudKitAccountChangeEventKind.accountChanged` on the Dart side.
  static let eventPayloadKey = "event"
  static let accountChangedEventName = "accountChanged"
}
