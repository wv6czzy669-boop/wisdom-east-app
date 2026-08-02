import CloudKit
import Foundation

/// Build 26 Phase 4C-1: a content-safe, native-side mirror of
/// `CloudEastSyncStateProjection`
/// (`lib/sync/cloud_east_sync_state_projection.dart`) -- exactly the
/// fields `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md` §2.5 defines.
/// Carries no custom `description`/`debugDescription` override; nothing in
/// this codec ever logs one of its instances or any of its fields (this
/// record type carries no wisdom/Reflection content at all, but the same
/// no-logging discipline is followed for consistency and so a future field
/// addition to this type never has to remember to add one).
struct CloudKitSyncStateWireEnvelope: Equatable {
  let dataEpoch: String
  let resetAtMs: Int64?
  let mutationId: String
  let schemaVersion: Int
}

/// Build 26 Phase 4C-1: strict, transport-free encode/decode between
/// validated values and `CKRecord` for the `CKEastSyncState` singleton
/// record type. Never performs a `CKDatabase` operation of any kind.
enum CloudKitSyncStateCodec {
  enum DecodeError: Error, Equatable {
    case wrongRecordType
    case wrongZone
    case recordNameMismatch
    case missingRequiredField(String)
    case malformedField(String)
    case unrecognizedSchemaVersion
  }

  /// Encodes the one `CKEastSyncState` singleton record. Always uses the
  /// fixed singleton identity (`CloudKitRecordIdentity.syncStateRecordID()`)
  /// -- there is no `revealId`-style parameter because this record type has
  /// no per-occurrence identity to derive from.
  static func encode(
    dataEpoch: String,
    resetAtMs: Int64?,
    mutationId: String,
    schemaVersion: Int = CloudKitRecordSchema.syncStateSchemaVersion
  ) -> CKRecord {
    let recordID = CloudKitRecordIdentity.syncStateRecordID()
    let record = CKRecord(recordType: CloudKitRecordSchema.syncStateRecordType, recordID: recordID)

    record[CloudKitRecordSchema.SyncStateField.dataEpoch] = dataEpoch as CKRecordValue
    if let resetAtMs = resetAtMs {
      record[CloudKitRecordSchema.SyncStateField.resetAtMs] = resetAtMs as CKRecordValue
    }
    record[CloudKitRecordSchema.SyncStateField.mutationId] = mutationId as CKRecordValue
    record[CloudKitRecordSchema.SyncStateField.schemaVersion] = schemaVersion as CKRecordValue

    return record
  }

  /// Decodes `record` into a content-safe, validated
  /// `CloudKitSyncStateWireEnvelope`. Fails closed for any malformed,
  /// wrong-zone, wrong-type, or wrong-`recordName` input -- there is
  /// exactly one legitimate `recordName` for this record type
  /// (`CloudKitRecordSchema.syncStateRecordName`), so any other name is
  /// rejected outright, never treated as "a different sync-state record."
  static func decode(_ record: CKRecord) -> Result<CloudKitSyncStateWireEnvelope, DecodeError> {
    guard record.recordType == CloudKitRecordSchema.syncStateRecordType else {
      return .failure(.wrongRecordType)
    }
    guard record.recordID.zoneID.zoneName == CloudKitRecordSchema.zoneName else {
      return .failure(.wrongZone)
    }
    guard record.recordID.recordName == CloudKitRecordSchema.syncStateRecordName else {
      return .failure(.recordNameMismatch)
    }

    guard let schemaVersion = record[CloudKitRecordSchema.SyncStateField.schemaVersion] as? Int else {
      return .failure(
        record[CloudKitRecordSchema.SyncStateField.schemaVersion] == nil
          ? .missingRequiredField(CloudKitRecordSchema.SyncStateField.schemaVersion)
          : .malformedField(CloudKitRecordSchema.SyncStateField.schemaVersion))
    }
    guard schemaVersion == CloudKitRecordSchema.syncStateSchemaVersion else {
      return .failure(.unrecognizedSchemaVersion)
    }

    guard let dataEpoch = record[CloudKitRecordSchema.SyncStateField.dataEpoch] as? String else {
      return .failure(
        record[CloudKitRecordSchema.SyncStateField.dataEpoch] == nil
          ? .missingRequiredField(CloudKitRecordSchema.SyncStateField.dataEpoch)
          : .malformedField(CloudKitRecordSchema.SyncStateField.dataEpoch))
    }

    guard let mutationId = record[CloudKitRecordSchema.SyncStateField.mutationId] as? String else {
      return .failure(
        record[CloudKitRecordSchema.SyncStateField.mutationId] == nil
          ? .missingRequiredField(CloudKitRecordSchema.SyncStateField.mutationId)
          : .malformedField(CloudKitRecordSchema.SyncStateField.mutationId))
    }

    var resetAtMs: Int64?
    if let resetAtValue = record[CloudKitRecordSchema.SyncStateField.resetAtMs] {
      guard let value = resetAtValue as? Int64 else {
        return .failure(.malformedField(CloudKitRecordSchema.SyncStateField.resetAtMs))
      }
      resetAtMs = value
    }

    return .success(
      CloudKitSyncStateWireEnvelope(
        dataEpoch: dataEpoch,
        resetAtMs: resetAtMs,
        mutationId: mutationId,
        schemaVersion: schemaVersion
      ))
  }
}
