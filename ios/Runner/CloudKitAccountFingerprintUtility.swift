import CloudKit
import CryptoKit
import Foundation

/// Build 26 Phase 4B-1: derives a deterministic, opaque, app-scoped
/// fingerprint from the current CloudKit user record ID -- never the raw
/// record name/ID itself (see the design doc §5's "opaque per-account
/// scope token" requirement, and Phase 4B-1's "never return the raw
/// CloudKit record name or raw user record ID to Dart").
///
/// The fingerprint is namespaced with a fixed, app-specific string before
/// hashing so the same underlying CloudKit identifier would never produce
/// the same fingerprint value as some other, unrelated use of that
/// identifier elsewhere -- this hash has exactly one purpose (local
/// same-account/different-account detection for this app) and is not
/// designed to be, or usable as, a general-purpose identifier.
///
/// Never persisted or logged by this file -- callers must not persist or
/// log it either in this phase (Phase 4B-1 explicitly does not persist an
/// account fingerprint anywhere).
enum CloudKitAccountFingerprintUtility {
  private static let fingerprintNamespace = "com.dogukan.dailywisdom.cloudkit.account.v1"

  /// Deterministically derives an opaque, hex-encoded SHA-256 fingerprint
  /// from `recordID`'s `recordName`. The same underlying record always
  /// produces the same fingerprint; two different records always produce
  /// different fingerprints (subject to SHA-256 collision resistance).
  static func fingerprint(for recordID: CKRecord.ID) -> String {
    let namespaced = "\(fingerprintNamespace):\(recordID.recordName)"
    let digest = SHA256.hash(data: Data(namespaced.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }
}
