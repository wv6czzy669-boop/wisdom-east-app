import CloudKit
import Foundation

/// Build 26 Phase 4C-1: deterministic `CKRecord.ID` construction for both
/// private record types, mirroring `lib/sync/sync_record_identity.dart`'s
/// `deriveKeptWisdomRecordName` exactly -- same prefix, same input
/// validation, same zone. This is not a second, independently-derived
/// naming rule: the Dart file remains the authoritative specification
/// (`docs/architecture/EAST_CLOUDKIT_SYNC_V1.md` §2.2), and this file is
/// this project's one native-side implementation of that same algorithm.
enum CloudKitRecordIdentity {
  enum IdentityError: Error {
    case invalidRevealId
  }

  /// Mirrors `lib/utils/canonical_uuid.dart`'s `isCanonicalUuidV4OrV5`
  /// exactly -- same pattern, same accepted versions (4 and 5 only), same
  /// accepted variant nibbles (8/9/a/b). Never a looser or stricter native
  /// copy.
  private static let canonicalUuidV4OrV5Pattern =
    "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[45][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"

  /// Returns whether `value` is an exact, canonical UUID version 4 or
  /// version 5 string -- the same shape `revealId`/`mutationId` fields are
  /// validated against on the Dart side.
  static func isCanonicalRevealId(_ value: String) -> Bool {
    return value.range(of: canonicalUuidV4OrV5Pattern, options: .regularExpression) != nil
  }

  /// The one custom zone every record identity below belongs to. Never the
  /// default zone.
  static var zoneID: CKRecordZone.ID {
    return CKRecordZone.ID(zoneName: CloudKitRecordSchema.zoneName, ownerName: CKCurrentUserDefaultName)
  }

  /// Deterministically derives the `CKRecord.ID` for the saved reveal
  /// occurrence identified by `revealId`, inside `EASTKeptZone`. Pure
  /// function of `revealId` alone -- never of wisdom text, a display date,
  /// or any timestamp. The same `revealId` always produces the same
  /// record ID; two different `revealId` values always produce two
  /// different record IDs. Applies identically to a record's active form
  /// and its tombstone form -- the identity never changes when a record
  /// transitions between the two.
  ///
  /// Throws `IdentityError.invalidRevealId` when `revealId` is not a
  /// canonical UUID v4/v5 -- a noncanonical `revealId` must never silently
  /// produce a record identity.
  static func keptWisdomRecordID(revealId: String) throws -> CKRecord.ID {
    guard isCanonicalRevealId(revealId) else {
      throw IdentityError.invalidRevealId
    }
    let recordName = "\(CloudKitRecordSchema.keptWisdomRecordNamePrefix)\(revealId)"
    return CKRecord.ID(recordName: recordName, zoneID: zoneID)
  }

  /// The one, fixed identity of the `CKEastSyncState` singleton record --
  /// never derived, never varies.
  static func syncStateRecordID() -> CKRecord.ID {
    return CKRecord.ID(recordName: CloudKitRecordSchema.syncStateRecordName, zoneID: zoneID)
  }

  /// Returns whether `recordName` is exactly what `keptWisdomRecordID(revealId:)`
  /// would produce for `revealId` -- never a substring match, never
  /// case-insensitive, never accepting extra characters before or after.
  /// Mirrors `lib/sync/sync_record_identity.dart`'s
  /// `recordNameMatchesRevealId`.
  static func recordName(_ recordName: String, matchesRevealId revealId: String) -> Bool {
    guard isCanonicalRevealId(revealId) else { return false }
    return recordName == "\(CloudKitRecordSchema.keptWisdomRecordNamePrefix)\(revealId)"
  }
}
