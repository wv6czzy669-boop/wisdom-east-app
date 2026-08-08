import CloudKit
import Foundation

/// Build 26 Phase 4C-1: a content-safe, native-side mirror of
/// `CloudKeptWisdomProjection` (`lib/sync/cloud_kept_wisdom_projection.dart`)
/// -- exactly the fields `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md`
/// §2.3/§2.4 define, nothing more. This struct carries no custom
/// `description`/`debugDescription` override; nothing in this codec ever
/// logs one of its instances or any of its fields.
///
/// **Build 26 Phase 4E-3a addition:** [systemFields] is opaque CloudKit
/// transport metadata (this record's archived identity + change tag, via
/// `CloudKitOpaqueArchive.archiveSystemFields(of:)` -- the same mechanism
/// `CloudKitRecordTransportCoordinator`'s modify/save path already uses),
/// never occurrence identity, content, or conflict-resolution metadata. It
/// is populated only by [decode] -- this struct is never produced on the
/// outgoing/save path at all (that path builds a `CKRecord` directly via
/// [encodeActive]/[encodeTombstone] plus
/// `CloudKitRecordEnvelopeArgumentParser`, never this wire envelope type),
/// so there is no competing "encoded, systemFields-less" shape of this
/// struct to reconcile. Present, non-empty, and required on both the
/// active and soft-tombstone forms alike -- a soft tombstone is still a
/// real, addressable `CKRecord` with its own identity and change tag. See
/// `CloudKitRecordTransportCoordinator.fetchZoneChanges`, the only call
/// site that archives and supplies this value to [decode].
struct CloudKitKeptWisdomWireEnvelope: Equatable {
  let recordName: String
  let isTombstone: Bool

  // Active-form-only fields (§2.3). `nil` on a tombstone-form envelope.
  let revealId: String?
  let wisdomText: String?
  let revealedAtMs: Int64?
  let keptAtMs: Int64?
  let reflectionText: String?
  let reflectedAtMs: Int64?

  // Tombstone-form-only field (§2.4). `nil` on an active-form envelope.
  let deletedAtMs: Int64?

  // Present on both forms.
  let updatedAtMs: Int64
  let mutationId: String
  let dataEpoch: String
  let schemaVersion: Int

  /// Build 26 Phase 4E-3a: opaque, archived CloudKit system fields for the
  /// exact `CKRecord` this envelope was decoded from. Always non-empty for
  /// a value produced by [CloudKitKeptWisdomCodec.decode] from a genuinely
  /// fetched changed record. Never logged, never printed, never compared
  /// for equality against decoded content.
  let systemFields: String
}

/// Build 26 Phase 4C-1: strict, transport-free encode/decode between
/// validated values and `CKRecord` for the `CKKeptWisdom` record type.
///
/// Never performs a `CKDatabase` operation of any kind -- this file has no
/// dependency on `CKDatabase` at all, only on plain, locally-constructible
/// `CKRecord`/`CKRecordZone.ID` values, so every function here is testable
/// with synthetic values and never contacts real CloudKit.
enum CloudKitKeptWisdomCodec {
  enum EncodeError: Error {
    case invalidRevealId
    case inconsistentReflectionFields
  }

  enum DecodeError: Error, Equatable {
    case wrongRecordType
    case wrongZone
    case recordNameMismatch
    case missingRequiredField(String)
    case malformedField(String)
    case unrecognizedSchemaVersion
    case forbiddenFieldOnTombstone(String)
    case inconsistentReflectionFields
  }

  /// Encodes the active form (§2.3) of a saved reveal occurrence into a
  /// freshly-constructed `CKRecord`. `reflectionText`/`reflectedAtMs` must
  /// be either both `nil` or both non-`nil` -- an occurrence with a
  /// Reflection timestamp but no Reflection text (or vice versa) is a
  /// programmer error, never silently coerced into a valid shape.
  static func encodeActive(
    revealId: String,
    wisdomText: String,
    revealedAtMs: Int64,
    keptAtMs: Int64,
    reflectionText: String?,
    reflectedAtMs: Int64?,
    updatedAtMs: Int64,
    mutationId: String,
    dataEpoch: String,
    schemaVersion: Int = CloudKitRecordSchema.keptWisdomActiveSchemaVersion
  ) throws -> CKRecord {
    guard CloudKitRecordIdentity.isCanonicalRevealId(revealId) else {
      throw EncodeError.invalidRevealId
    }
    guard (reflectionText == nil) == (reflectedAtMs == nil) else {
      throw EncodeError.inconsistentReflectionFields
    }

    let recordID = try CloudKitRecordIdentity.keptWisdomRecordID(revealId: revealId)
    let record = CKRecord(recordType: CloudKitRecordSchema.keptWisdomRecordType, recordID: recordID)

    record[CloudKitRecordSchema.KeptWisdomField.revealId] = revealId as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.wisdomText] = wisdomText as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.revealedAtMs] = revealedAtMs as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.keptAtMs] = keptAtMs as CKRecordValue
    if let reflectionText = reflectionText {
      record[CloudKitRecordSchema.KeptWisdomField.reflectionText] = reflectionText as CKRecordValue
    }
    if let reflectedAtMs = reflectedAtMs {
      record[CloudKitRecordSchema.KeptWisdomField.reflectedAtMs] = reflectedAtMs as CKRecordValue
    }
    record[CloudKitRecordSchema.KeptWisdomField.updatedAtMs] = updatedAtMs as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.mutationId] = mutationId as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.dataEpoch] = dataEpoch as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.schemaVersion] = schemaVersion as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.isTombstone] = false as CKRecordValue

    return record
  }

  /// Encodes the tombstone form (§2.4) of a saved reveal occurrence.
  /// Carries no `revealId`, `wisdomText`, `reflectionText`, `revealedAtMs`,
  /// `keptAtMs`, or `reflectedAtMs` field at all -- cleared entirely, never
  /// merely blanked, matching ADR-007.
  static func encodeTombstone(
    revealId: String,
    deletedAtMs: Int64,
    updatedAtMs: Int64,
    mutationId: String,
    dataEpoch: String,
    schemaVersion: Int = CloudKitRecordSchema.keptWisdomTombstoneSchemaVersion
  ) throws -> CKRecord {
    guard CloudKitRecordIdentity.isCanonicalRevealId(revealId) else {
      throw EncodeError.invalidRevealId
    }

    let recordID = try CloudKitRecordIdentity.keptWisdomRecordID(revealId: revealId)
    let record = CKRecord(recordType: CloudKitRecordSchema.keptWisdomRecordType, recordID: recordID)

    record[CloudKitRecordSchema.KeptWisdomField.isTombstone] = true as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.deletedAtMs] = deletedAtMs as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.updatedAtMs] = updatedAtMs as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.mutationId] = mutationId as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.dataEpoch] = dataEpoch as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.schemaVersion] = schemaVersion as CKRecordValue

    return record
  }

  /// Decodes `record` into a content-safe, validated
  /// `CloudKitKeptWisdomWireEnvelope`. Fails closed (returns `.failure`,
  /// never throws, never force-unwraps, never force-casts) for any
  /// malformed, wrong-zone, wrong-type, or record-name-mismatched input --
  /// mirroring `CloudKeptWisdomProjection.tryParseRemote`'s Dart-side
  /// contract exactly (§2.6/§2.8).
  ///
  /// Build 26 Phase 4E-3a: `systemFields` is `record`'s own already-archived
  /// opaque CloudKit system fields (via
  /// `CloudKitOpaqueArchive.archiveSystemFields(of:)`), archived by the
  /// caller *before* calling this function -- this codec never archives it
  /// itself and never validates its shape beyond requiring it to be
  /// non-empty, since archiving/validity is `CloudKitRecordTransportCoordinator`'s
  /// own responsibility (including failing the whole fetch closed if
  /// archiving itself ever fails). Passed straight through onto the
  /// returned envelope's own `systemFields` field, on both the active and
  /// tombstone decode paths, with no other effect on this function's
  /// existing content/identity validation.
  static func decode(
    _ record: CKRecord, systemFields: String
  ) -> Result<CloudKitKeptWisdomWireEnvelope, DecodeError> {
    guard record.recordType == CloudKitRecordSchema.keptWisdomRecordType else {
      return .failure(.wrongRecordType)
    }
    // Rejects both the default zone and any zone other than EASTKeptZone --
    // there is no separate "reject default zone" branch because the
    // default zone's name ("_defaultZone") is never equal to
    // CloudKitRecordSchema.zoneName.
    guard record.recordID.zoneID.zoneName == CloudKitRecordSchema.zoneName else {
      return .failure(.wrongZone)
    }

    let recordName = record.recordID.recordName

    guard let schemaVersion = record[CloudKitRecordSchema.KeptWisdomField.schemaVersion] as? Int else {
      return .failure(
        record[CloudKitRecordSchema.KeptWisdomField.schemaVersion] == nil
          ? .missingRequiredField(CloudKitRecordSchema.KeptWisdomField.schemaVersion)
          : .malformedField(CloudKitRecordSchema.KeptWisdomField.schemaVersion))
    }

    guard let isTombstone = record[CloudKitRecordSchema.KeptWisdomField.isTombstone] as? Bool else {
      return .failure(
        record[CloudKitRecordSchema.KeptWisdomField.isTombstone] == nil
          ? .missingRequiredField(CloudKitRecordSchema.KeptWisdomField.isTombstone)
          : .malformedField(CloudKitRecordSchema.KeptWisdomField.isTombstone))
    }

    guard let updatedAtMs = record[CloudKitRecordSchema.KeptWisdomField.updatedAtMs] as? Int64 else {
      return .failure(
        record[CloudKitRecordSchema.KeptWisdomField.updatedAtMs] == nil
          ? .missingRequiredField(CloudKitRecordSchema.KeptWisdomField.updatedAtMs)
          : .malformedField(CloudKitRecordSchema.KeptWisdomField.updatedAtMs))
    }

    guard let mutationId = record[CloudKitRecordSchema.KeptWisdomField.mutationId] as? String else {
      return .failure(
        record[CloudKitRecordSchema.KeptWisdomField.mutationId] == nil
          ? .missingRequiredField(CloudKitRecordSchema.KeptWisdomField.mutationId)
          : .malformedField(CloudKitRecordSchema.KeptWisdomField.mutationId))
    }

    guard let dataEpoch = record[CloudKitRecordSchema.KeptWisdomField.dataEpoch] as? String else {
      return .failure(
        record[CloudKitRecordSchema.KeptWisdomField.dataEpoch] == nil
          ? .missingRequiredField(CloudKitRecordSchema.KeptWisdomField.dataEpoch)
          : .malformedField(CloudKitRecordSchema.KeptWisdomField.dataEpoch))
    }

    if isTombstone {
      return decodeTombstone(
        record: record,
        recordName: recordName,
        schemaVersion: schemaVersion,
        updatedAtMs: updatedAtMs,
        mutationId: mutationId,
        dataEpoch: dataEpoch,
        systemFields: systemFields
      )
    }

    return decodeActive(
      record: record,
      recordName: recordName,
      schemaVersion: schemaVersion,
      updatedAtMs: updatedAtMs,
      mutationId: mutationId,
      dataEpoch: dataEpoch,
      systemFields: systemFields
    )
  }

  private static func decodeTombstone(
    record: CKRecord,
    recordName: String,
    schemaVersion: Int,
    updatedAtMs: Int64,
    mutationId: String,
    dataEpoch: String,
    systemFields: String
  ) -> Result<CloudKitKeptWisdomWireEnvelope, DecodeError> {
    guard schemaVersion == CloudKitRecordSchema.keptWisdomTombstoneSchemaVersion else {
      return .failure(.unrecognizedSchemaVersion)
    }

    for field in CloudKitRecordSchema.KeptWisdomField.forbiddenOnTombstone {
      if record[field] != nil {
        return .failure(.forbiddenFieldOnTombstone(field))
      }
    }

    guard let deletedAtMs = record[CloudKitRecordSchema.KeptWisdomField.deletedAtMs] as? Int64 else {
      return .failure(
        record[CloudKitRecordSchema.KeptWisdomField.deletedAtMs] == nil
          ? .missingRequiredField(CloudKitRecordSchema.KeptWisdomField.deletedAtMs)
          : .malformedField(CloudKitRecordSchema.KeptWisdomField.deletedAtMs))
    }

    return .success(
      CloudKitKeptWisdomWireEnvelope(
        recordName: recordName,
        isTombstone: true,
        revealId: nil,
        wisdomText: nil,
        revealedAtMs: nil,
        keptAtMs: nil,
        reflectionText: nil,
        reflectedAtMs: nil,
        deletedAtMs: deletedAtMs,
        updatedAtMs: updatedAtMs,
        mutationId: mutationId,
        dataEpoch: dataEpoch,
        schemaVersion: schemaVersion,
        systemFields: systemFields
      ))
  }

  private static func decodeActive(
    record: CKRecord,
    recordName: String,
    schemaVersion: Int,
    updatedAtMs: Int64,
    mutationId: String,
    dataEpoch: String,
    systemFields: String
  ) -> Result<CloudKitKeptWisdomWireEnvelope, DecodeError> {
    guard schemaVersion == CloudKitRecordSchema.keptWisdomActiveSchemaVersion else {
      return .failure(.unrecognizedSchemaVersion)
    }

    guard let revealId = record[CloudKitRecordSchema.KeptWisdomField.revealId] as? String,
      CloudKitRecordIdentity.isCanonicalRevealId(revealId)
    else {
      return .failure(
        record[CloudKitRecordSchema.KeptWisdomField.revealId] == nil
          ? .missingRequiredField(CloudKitRecordSchema.KeptWisdomField.revealId)
          : .malformedField(CloudKitRecordSchema.KeptWisdomField.revealId))
    }

    guard CloudKitRecordIdentity.recordName(recordName, matchesRevealId: revealId) else {
      return .failure(.recordNameMismatch)
    }

    guard let wisdomText = record[CloudKitRecordSchema.KeptWisdomField.wisdomText] as? String else {
      return .failure(
        record[CloudKitRecordSchema.KeptWisdomField.wisdomText] == nil
          ? .missingRequiredField(CloudKitRecordSchema.KeptWisdomField.wisdomText)
          : .malformedField(CloudKitRecordSchema.KeptWisdomField.wisdomText))
    }

    guard let revealedAtMs = record[CloudKitRecordSchema.KeptWisdomField.revealedAtMs] as? Int64 else {
      return .failure(
        record[CloudKitRecordSchema.KeptWisdomField.revealedAtMs] == nil
          ? .missingRequiredField(CloudKitRecordSchema.KeptWisdomField.revealedAtMs)
          : .malformedField(CloudKitRecordSchema.KeptWisdomField.revealedAtMs))
    }

    guard let keptAtMs = record[CloudKitRecordSchema.KeptWisdomField.keptAtMs] as? Int64 else {
      return .failure(
        record[CloudKitRecordSchema.KeptWisdomField.keptAtMs] == nil
          ? .missingRequiredField(CloudKitRecordSchema.KeptWisdomField.keptAtMs)
          : .malformedField(CloudKitRecordSchema.KeptWisdomField.keptAtMs))
    }

    var reflectionText: String?
    if let reflectionTextValue = record[CloudKitRecordSchema.KeptWisdomField.reflectionText] {
      guard let text = reflectionTextValue as? String else {
        return .failure(.malformedField(CloudKitRecordSchema.KeptWisdomField.reflectionText))
      }
      reflectionText = text
    }

    var reflectedAtMs: Int64?
    if let reflectedAtValue = record[CloudKitRecordSchema.KeptWisdomField.reflectedAtMs] {
      guard let value = reflectedAtValue as? Int64 else {
        return .failure(.malformedField(CloudKitRecordSchema.KeptWisdomField.reflectedAtMs))
      }
      reflectedAtMs = value
    }

    guard (reflectionText == nil) == (reflectedAtMs == nil) else {
      return .failure(.inconsistentReflectionFields)
    }

    return .success(
      CloudKitKeptWisdomWireEnvelope(
        recordName: recordName,
        isTombstone: false,
        revealId: revealId,
        wisdomText: wisdomText,
        revealedAtMs: revealedAtMs,
        keptAtMs: keptAtMs,
        reflectionText: reflectionText,
        reflectedAtMs: reflectedAtMs,
        deletedAtMs: nil,
        updatedAtMs: updatedAtMs,
        mutationId: mutationId,
        dataEpoch: dataEpoch,
        schemaVersion: schemaVersion,
        systemFields: systemFields
      ))
  }
}
