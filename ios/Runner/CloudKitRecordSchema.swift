import Foundation

/// Build 26 Phase 4C-1: record-type, zone, and field-name constants for the
/// two private CloudKit record schemas, mirroring
/// `lib/sync/sync_record_identity.dart` and
/// `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md` §2 exactly. This file is
/// this project's one authoritative *native-side* copy of these literal
/// values -- it never invents a competing name, and no other Swift file
/// under `ios/Runner/` defines its own copy of a record type, zone name, or
/// field name.
enum CloudKitRecordSchema {
  /// Phase 4A's one custom CloudKit zone. Mirrors
  /// `lib/sync/sync_record_identity.dart`'s `keptRecordZoneName`.
  static let zoneName = "EASTKeptZone"

  /// Mirrors `lib/sync/sync_record_identity.dart`'s `keptWisdomRecordType`.
  static let keptWisdomRecordType = "CKKeptWisdom"

  /// Mirrors `lib/sync/sync_record_identity.dart`'s `syncStateRecordType`.
  static let syncStateRecordType = "CKEastSyncState"

  /// Mirrors `lib/sync/sync_record_identity.dart`'s `syncStateRecordName`
  /// -- the fixed, singleton `recordName` for the one `CKEastSyncState`
  /// record that ever exists per private database.
  static let syncStateRecordName = "sync-state"

  /// Mirrors `lib/sync/sync_record_identity.dart`'s
  /// `keptWisdomRecordNamePrefix`.
  static let keptWisdomRecordNamePrefix = "east-kept-"

  /// `KeptRecord.currentSchemaVersion` -- mirrors the Dart constant
  /// `CloudKeptWisdomProjection` reads it from. Never a second,
  /// independently-maintained literal on either side of a single design
  /// document; both sides read this from their own one source of truth.
  static let keptWisdomActiveSchemaVersion = 3

  /// `SyncTombstone.currentSchemaVersion`.
  static let keptWisdomTombstoneSchemaVersion = 1

  /// `CloudEastSyncStateProjection.currentSchemaVersion`.
  static let syncStateSchemaVersion = 1

  /// Exact field names for the `CKKeptWisdom` record type (active and
  /// tombstone forms combined -- see §2.3/§2.4 for which fields apply to
  /// which form).
  enum KeptWisdomField {
    static let revealId = "revealId"
    static let wisdomText = "wisdomText"
    static let wisdomId = "wisdomId"
    static let revealedAtMs = "revealedAtMs"
    static let keptAtMs = "keptAtMs"
    static let reflectionText = "reflectionText"
    static let reflectionHistoryJson = "reflectionHistoryJson"
    static let reflectedAtMs = "reflectedAtMs"
    static let updatedAtMs = "updatedAtMs"
    static let mutationId = "mutationId"
    static let dataEpoch = "dataEpoch"
    static let schemaVersion = "schemaVersion"
    static let isTombstone = "isTombstone"
    static let deletedAtMs = "deletedAtMs"

    /// Fields a real tombstone-form record never carries (§2.4) -- seeing
    /// one indicates corruption or tampering, not a variant to tolerate.
    static let forbiddenOnTombstone: [String] = [
      revealId, wisdomText, wisdomId, revealedAtMs, keptAtMs, reflectionText, reflectedAtMs, reflectionHistoryJson,
    ]
  }

  /// Exact field names for the `CKEastSyncState` singleton record (§2.5).
  enum SyncStateField {
    static let dataEpoch = "dataEpoch"
    static let resetAtMs = "resetAtMs"
    static let mutationId = "mutationId"
    static let schemaVersion = "schemaVersion"
  }
}
