import CloudKit
import Foundation

/// Build 26 Phase 4C-2: the one place this codebase archives/unarchives an
/// opaque CloudKit value (`CKServerChangeToken`, or a `CKRecord`'s own
/// "system fields" -- its identity plus change tag, no user field values)
/// for transport across the Dart bridge as a Base64 string.
///
/// Every archive/unarchive here uses `NSKeyedArchiver`/`NSKeyedUnarchiver`
/// with `requiresSecureCoding = true` and an explicit, narrow
/// `allowedClasses` set -- never the insecure, deprecated
/// `NSKeyedUnarchiver.unarchiveObject(with:)`, and never a decode that
/// accepts an arbitrary archived class. A corrupt or foreign archive fails
/// closed (`nil`), never throws, never crashes. Nothing in this file
/// interprets, logs, or persists the value it archives/unarchives -- it is
/// treated as opaque bytes both ways, exactly as
/// `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md`'s "opaque change-token
/// representation" rule requires, extended by this phase to a per-record
/// system-fields blob for the same reason (never interpreted, never
/// compared, only round-tripped).
enum CloudKitOpaqueArchive {
  /// Archives `token` securely, returning it Base64-encoded. `token` is
  /// never `nil`-coalesced away or substituted -- callers only ever archive
  /// a token CloudKit itself just handed back.
  static func archiveServerChangeToken(_ token: CKServerChangeToken) -> String? {
    guard
      let data = try? NSKeyedArchiver.archivedData(
        withRootObject: token, requiringSecureCoding: true)
    else {
      return nil
    }
    return data.base64EncodedString()
  }

  /// Unarchives a Base64 string produced by
  /// `archiveServerChangeToken(_:)`. Returns `nil` for anything malformed,
  /// non-Base64, or not actually an archived `CKServerChangeToken` --
  /// never throws, never force-unwraps.
  static func unarchiveServerChangeToken(_ base64: String) -> CKServerChangeToken? {
    guard let data = Data(base64Encoded: base64) else { return nil }
    guard
      let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data)
    else { return nil }
    unarchiver.requiresSecureCoding = true
    defer { unarchiver.finishDecoding() }
    return unarchiver.decodeObject(
      of: CKServerChangeToken.self, forKey: NSKeyedArchiveRootObjectKey)
  }

  /// Archives `record`'s own system fields (identity + change tag; never
  /// any of its user-defined field values) via `CKRecord`'s own
  /// `NSSecureCoding` conformance, returning it Base64-encoded. This is the
  /// mechanism `CloudKitRecordTransportCoordinator` uses to let a future
  /// save present the exact server version it last observed, enabling
  /// CloudKit's own `.ifServerRecordUnchanged` conflict detection rather
  /// than an unconditional overwrite.
  static func archiveSystemFields(of record: CKRecord) -> String? {
    let archiver = NSKeyedArchiver(requiringSecureCoding: true)
    record.encodeSystemFields(with: archiver)
    archiver.finishEncoding()
    return archiver.encodedData.base64EncodedString()
  }

  /// Unarchives a Base64 system-fields blob produced by
  /// `archiveSystemFields(of:)` back into a `CKRecord` carrying only its
  /// original identity and change tag (no user field values -- there were
  /// none to restore). Returns `nil` for anything malformed, non-Base64, or
  /// not actually an archived `CKRecord`.
  static func unarchiveSystemFields(_ base64: String) -> CKRecord? {
    guard let data = Data(base64Encoded: base64) else { return nil }
    guard
      let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data)
    else { return nil }
    unarchiver.requiresSecureCoding = true
    defer { unarchiver.finishDecoding() }
    return CKRecord(coder: unarchiver)
  }
}
