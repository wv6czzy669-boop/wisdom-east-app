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
  let wisdomId: String?
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
  ///
  /// Build 26 Phase 4H-5 (sibling of the Phase 4H-4 tombstone
  /// field-retention fix): when no Reflection exists, `reflectionText`/
  /// `reflectedAtMs` are now explicitly assigned `nil` here, not merely
  /// left unmentioned. This matters for exactly the same reason
  /// `encodeTombstone` had to change: a save of this record that reuses an
  /// already-synced record's system-fields-only baseline (see
  /// `CloudKitRecordTransportCoordinator.modifyRecords`'s baseline-merge
  /// step) only propagates a field removal onto the server for a key
  /// present in *this* record's own `changedKeys()` -- a field this
  /// function simply never touched would never appear there, so removing
  /// an existing Reflection from an already-synced active occurrence
  /// (Reflection present at last sync, absent now) would otherwise leave
  /// the old `reflectionText`/`reflectedAtMs` stranded on the server. This
  /// is a pure no-op for the already-correct paths: a brand-new record
  /// that never had a Reflection has nothing to remove, and a record that
  /// does have one is unaffected (this only fires in the `nil` branch).
  static func encodeActive(
    revealId: String,
    wisdomText: String,
    wisdomId: String?,
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
    record[CloudKitRecordSchema.KeptWisdomField.wisdomId] = wisdomId as CKRecordValue?
    record[CloudKitRecordSchema.KeptWisdomField.revealedAtMs] = revealedAtMs as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.keptAtMs] = keptAtMs as CKRecordValue
    if let reflectionText = reflectionText {
      record[CloudKitRecordSchema.KeptWisdomField.reflectionText] = reflectionText as CKRecordValue
    } else {
      record[CloudKitRecordSchema.KeptWisdomField.reflectionText] = nil
    }
    if let reflectedAtMs = reflectedAtMs {
      record[CloudKitRecordSchema.KeptWisdomField.reflectedAtMs] = reflectedAtMs as CKRecordValue
    } else {
      record[CloudKitRecordSchema.KeptWisdomField.reflectedAtMs] = nil
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
  ///
  /// Build 26 Phase 4H-4 (real-device + CloudKit-dashboard investigation):
  /// every forbidden-on-tombstone field is now explicitly assigned `nil`
  /// here, not merely left untouched. This matters because
  /// `CloudKitRecordTransportCoordinator.modifyRecords` saves a tombstone
  /// *update* to an already-synced occurrence by reconstructing a baseline
  /// `CKRecord` from that occurrence's own previously-archived system
  /// fields alone (`CloudKitOpaqueArchive.unarchiveSystemFields` -- "no
  /// user field values -- there were none to restore") and then copying
  /// this record's own *changed* keys onto it. A forbidden field this
  /// function merely never mentioned would never become part of that
  /// baseline's own changed-key set at all, so CloudKit's partial-update
  /// save would leave whatever value the server already had for that field
  /// completely untouched -- proven, via the real-device/dashboard
  /// evidence this phase investigated, to be exactly how an already-synced
  /// active record's `revealId`/`wisdomText`/`revealedAtMs`/`keptAtMs`
  /// (and `reflectionText`/`reflectedAtMs`, if a Reflection existed at
  /// deletion time) survived, unwanted, on its tombstone. Explicitly
  /// assigning `nil` registers each of these keys in *this* record's own
  /// `changedKeys()` (distinct from `allKeys()`, which excludes a nil'd
  /// key) as a real removal, which
  /// `CloudKitRecordTransportCoordinator.modifyRecords`'s baseline-merge
  /// loop (fixed in the same change) now correctly copies onto the saved
  /// baseline, so the removal is actually sent to and applied by CloudKit.
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

    // Explicit removals -- see this function's own doc comment above for
    // why "never set" is not equivalent to "explicitly cleared" once a
    // save reuses a system-fields-only baseline.
    for field in CloudKitRecordSchema.KeptWisdomField.forbiddenOnTombstone {
      record[field] = nil
    }

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

    // Build 26 Phase 4H-4 real-device + CloudKit-dashboard investigation
    // superseded the earlier, narrower Phase 4H-3 "redundant revealId only"
    // compatibility rule: the actual already-stored Development tombstone
    // retains its *entire* historical active-form payload (`revealId`,
    // `wisdomText`, `revealedAtMs`, `keptAtMs`; `reflectionText`/
    // `reflectedAtMs` too, if a Reflection existed at deletion time) --
    // proven to be a live writer bug in
    // `CloudKitRecordTransportCoordinator.modifyRecords`'s baseline-merge
    // step (fixed below, in this same change, via `changedKeys()`), never
    // an isolated single-field artifact. See `legacyActivePayloadShape`
    // for the exact, narrow coherence rule this decoder now applies.
    switch legacyActivePayloadShape(on: record, recordName: recordName) {
    case .absent, .coherent:
      break
    case .incoherent(let field):
      return .failure(.forbiddenFieldOnTombstone(field))
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
        wisdomId: nil,
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

  /// Build 26 Phase 4H-4: classifies a tombstone-shaped `CKRecord`'s
  /// `forbiddenOnTombstone` fields as either genuinely absent (the
  /// canonical shape every current write path now produces), a single
  /// known-coherent "legacy full-form tombstone" historical snapshot (the
  /// shape the pre-fix writer bug could leave behind), or anything else
  /// (`.incoherent` -- fails closed, naming the first offending field).
  ///
  /// The proven writer bug retains fields in exactly two possible groups,
  /// never an arbitrary subset: the four fields `encodeActive`
  /// unconditionally sets together (`revealId`, `wisdomText`,
  /// `revealedAtMs`, `keptAtMs`), and, independently, the optional
  /// Reflection pair (`reflectionText`, `reflectedAtMs`) if -- and only
  /// if -- a Reflection existed on the occurrence at the moment it was
  /// deleted. So a coherent legacy snapshot is: all four core fields
  /// present and individually valid, *plus* the Reflection pair either
  /// both absent or both present and valid. Any partial subset of the
  /// four core fields, or an unpaired Reflection field, indicates
  /// corruption or tampering, not this known bug, and is rejected.
  ///
  /// Every field this function accepts is validated with the exact same
  /// per-field rule `decodeActive` below already applies to that field --
  /// never a looser, bespoke legacy check -- and, regardless of outcome,
  /// none of these values are ever returned to a caller: `decodeTombstone`
  /// always constructs its `.success` envelope with every active-form
  /// field hardcoded to `nil`, so a coherent legacy snapshot can never
  /// reach Dart as active content, and can never resurrect the deleted
  /// occurrence or its Reflection.
  private enum LegacyActivePayloadShape {
    case absent
    case coherent
    case incoherent(String)
  }

  private static func legacyActivePayloadShape(
    on record: CKRecord, recordName: String
  ) -> LegacyActivePayloadShape {
    let revealIdValue = record[CloudKitRecordSchema.KeptWisdomField.revealId]
    let wisdomTextValue = record[CloudKitRecordSchema.KeptWisdomField.wisdomText]
    let revealedAtMsValue = record[CloudKitRecordSchema.KeptWisdomField.revealedAtMs]
    let keptAtMsValue = record[CloudKitRecordSchema.KeptWisdomField.keptAtMs]
    let reflectionTextValue = record[CloudKitRecordSchema.KeptWisdomField.reflectionText]
    let reflectedAtMsValue = record[CloudKitRecordSchema.KeptWisdomField.reflectedAtMs]

    if revealIdValue == nil, wisdomTextValue == nil, revealedAtMsValue == nil, keptAtMsValue == nil,
      reflectionTextValue == nil, reflectedAtMsValue == nil
    {
      return .absent
    }

    guard let revealId = revealIdValue as? String,
      CloudKitRecordIdentity.recordName(recordName, matchesRevealId: revealId)
    else {
      return .incoherent(CloudKitRecordSchema.KeptWisdomField.revealId)
    }
    guard wisdomTextValue as? String != nil else {
      return .incoherent(CloudKitRecordSchema.KeptWisdomField.wisdomText)
    }
    guard revealedAtMsValue as? Int64 != nil else {
      return .incoherent(CloudKitRecordSchema.KeptWisdomField.revealedAtMs)
    }
    guard keptAtMsValue as? Int64 != nil else {
      return .incoherent(CloudKitRecordSchema.KeptWisdomField.keptAtMs)
    }

    switch (reflectionTextValue, reflectedAtMsValue) {
    case (nil, nil):
      return .coherent
    case (.some, .some):
      guard reflectionTextValue as? String != nil, reflectedAtMsValue as? Int64 != nil else {
        return .incoherent(CloudKitRecordSchema.KeptWisdomField.reflectionText)
      }
      return .coherent
    default:
      // Exactly one of the paired Reflection fields is present -- never a
      // shape the proven writer bug (or a valid active record) could
      // produce.
      return .incoherent(CloudKitRecordSchema.KeptWisdomField.reflectionText)
    }
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
    let wisdomId = record[CloudKitRecordSchema.KeptWisdomField.wisdomId] as? String

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
        wisdomId: wisdomId,
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
