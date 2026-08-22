import CloudKit
import Foundation

/// Build 26 Phase 4C-2: the native-side mirror of
/// `lib/sync_platform/cloud_kept_wisdom_wire_envelope.dart`/
/// `cloud_east_sync_state_wire_envelope.dart` -- but in the opposite
/// direction. Those two Dart files turn a validated projection into the
/// wire `Map` shape a `MethodChannel` call carries; this file turns that
/// same wire `Map` shape (received here as `[String: Any]`, exactly as
/// `FlutterMethodCall.arguments` delivers it) back into a validated
/// `CKRecord`, via the existing Phase 4C-1
/// `CloudKitKeptWisdomCodec`/`CloudKitSyncStateCodec` encode functions --
/// never a second, competing validation path. This is the concrete
/// implementation of the phase's own requirement that "all incoming record
/// envelopes must pass the Phase 4C-1 codecs before network use."
///
/// No force unwrap, no force cast anywhere below -- every extraction uses
/// `guard let ... as? ...`, and any missing/malformed/wrong-zone/wrong-type
/// field fails the whole record closed before a `CKModifyRecordsOperation`
/// is ever constructed (native test: "invalid codec payload rejected
/// before operation creation").
enum CloudKitRecordEnvelopeArgumentParser {
  enum BuildError: Error, Equatable {
    case unsupportedRecordType
    case wrongZone
    case missingRequiredField(String)
    case malformedField(String)
    case recordNameMismatch
    case invalidRevealId
    case inconsistentReflectionFields
  }

  /// Builds a `CKRecord` from one entry of the `records` array a
  /// `modifyPrivateRecords` call carries -- `entry` is expected to be a
  /// `[String: Any]` with a `recordType` key and a nested `fields` key
  /// (the same allowlisted wire shape
  /// `CloudKeptWisdomWireEnvelope.encode`/`CloudEastSyncStateWireEnvelope
  /// .encode` produce on the Dart side).
  static func buildRecord(fromChannelEntry entry: [String: Any]) -> Result<CKRecord, BuildError> {
    guard let recordType = entry["recordType"] as? String else {
      return .failure(.missingRequiredField("recordType"))
    }
    guard let fields = entry["fields"] as? [String: Any] else {
      return .failure(.missingRequiredField("fields"))
    }

    switch recordType {
    case CloudKitRecordSchema.keptWisdomRecordType:
      return buildKeptWisdomRecord(fields: fields)
    case CloudKitRecordSchema.syncStateRecordType:
      return buildSyncStateRecord(fields: fields)
    default:
      return .failure(.unsupportedRecordType)
    }
  }

  private static func buildKeptWisdomRecord(fields: [String: Any]) -> Result<CKRecord, BuildError> {
    guard fields["zoneName"] as? String == CloudKitRecordSchema.zoneName else {
      return .failure(.wrongZone)
    }
    guard let recordName = fields["recordName"] as? String else {
      return .failure(.missingRequiredField("recordName"))
    }
    guard let isTombstone = fields["isTombstone"] as? Bool else {
      return .failure(.missingRequiredField("isTombstone"))
    }
    guard let updatedAtMs = asInt64(fields["updatedAtMs"]) else {
      return .failure(.missingRequiredField("updatedAtMs"))
    }
    guard let mutationId = fields["mutationId"] as? String else {
      return .failure(.missingRequiredField("mutationId"))
    }
    guard let dataEpoch = fields["dataEpoch"] as? String else {
      return .failure(.missingRequiredField("dataEpoch"))
    }
    let schemaVersion = fields["schemaVersion"] as? Int

    guard let revealId = revealId(fromRecordName: recordName) else {
      return .failure(.invalidRevealId)
    }

    if isTombstone {
      do {
        guard let deletedAtMs = asInt64(fields["deletedAtMs"]) else {
          return .failure(.missingRequiredField("deletedAtMs"))
        }
        let record = try CloudKitKeptWisdomCodec.encodeTombstone(
          revealId: revealId,
          deletedAtMs: deletedAtMs,
          updatedAtMs: updatedAtMs,
          mutationId: mutationId,
          dataEpoch: dataEpoch,
          schemaVersion: schemaVersion ?? CloudKitRecordSchema.keptWisdomTombstoneSchemaVersion
        )
        return .success(record)
      } catch {
        return .failure(.invalidRevealId)
      }
    }

    guard fields["revealId"] as? String == revealId else {
      return .failure(.recordNameMismatch)
    }
    guard let wisdomText = fields["wisdomText"] as? String else {
      return .failure(.missingRequiredField("wisdomText"))
    }
    let wisdomId = fields["wisdomId"] as? String
    guard let revealedAtMs = asInt64(fields["revealedAtMs"]) else {
      return .failure(.missingRequiredField("revealedAtMs"))
    }
    guard let keptAtMs = asInt64(fields["keptAtMs"]) else {
      return .failure(.missingRequiredField("keptAtMs"))
    }

    let reflectionText = fields["reflectionText"] as? String
    let reflectedAtMs = asInt64(fields["reflectedAtMs"])
    guard (reflectionText == nil) == (reflectedAtMs == nil) else {
      return .failure(.inconsistentReflectionFields)
    }

    do {
      let record = try CloudKitKeptWisdomCodec.encodeActive(
        revealId: revealId,
        wisdomText: wisdomText,
        wisdomId: wisdomId,
        revealedAtMs: revealedAtMs,
        keptAtMs: keptAtMs,
        reflectionText: reflectionText,
        reflectedAtMs: reflectedAtMs,
        updatedAtMs: updatedAtMs,
        mutationId: mutationId,
        dataEpoch: dataEpoch,
        schemaVersion: schemaVersion ?? CloudKitRecordSchema.keptWisdomActiveSchemaVersion
      )
      return .success(record)
    } catch CloudKitKeptWisdomCodec.EncodeError.inconsistentReflectionFields {
      return .failure(.inconsistentReflectionFields)
    } catch {
      return .failure(.invalidRevealId)
    }
  }

  private static func buildSyncStateRecord(fields: [String: Any]) -> Result<CKRecord, BuildError> {
    guard fields["zoneName"] as? String == CloudKitRecordSchema.zoneName else {
      return .failure(.wrongZone)
    }
    guard fields["recordName"] as? String == CloudKitRecordSchema.syncStateRecordName else {
      return .failure(.recordNameMismatch)
    }
    guard let dataEpoch = fields["dataEpoch"] as? String else {
      return .failure(.missingRequiredField("dataEpoch"))
    }
    guard let mutationId = fields["mutationId"] as? String else {
      return .failure(.missingRequiredField("mutationId"))
    }
    let resetAtMs = asInt64(fields["resetAtMs"])
    let schemaVersion = fields["schemaVersion"] as? Int

    let record = CloudKitSyncStateCodec.encode(
      dataEpoch: dataEpoch,
      resetAtMs: resetAtMs,
      mutationId: mutationId,
      schemaVersion: schemaVersion ?? CloudKitRecordSchema.syncStateSchemaVersion
    )
    return .success(record)
  }

  /// Recovers the `revealId` a `CKKeptWisdom` `recordName` was derived
  /// from -- the tombstone-form wire shape never repeats `revealId` as its
  /// own field (mirroring `lib/sync/cloud_kept_wisdom_projection.dart`'s
  /// tombstone factory, which likewise never carries it as a separate wire
  /// field), so it is recovered from `recordName` itself, then validated
  /// exactly as strictly as if it had arrived as its own field.
  private static func revealId(fromRecordName recordName: String) -> String? {
    guard recordName.hasPrefix(CloudKitRecordSchema.keptWisdomRecordNamePrefix) else {
      return nil
    }
    let candidate = String(recordName.dropFirst(CloudKitRecordSchema.keptWisdomRecordNamePrefix.count))
    guard CloudKitRecordIdentity.isCanonicalRevealId(candidate) else { return nil }
    return candidate
  }

  /// Flutter's standard method-channel codec can deliver a Dart `int` as
  /// any of several native numeric bridging shapes depending on platform
  /// and value range -- this accepts every shape that would represent a
  /// whole 64-bit integer, and rejects (returns `nil`, never crashes) a
  /// fractional or otherwise non-integral `NSNumber`.
  private static func asInt64(_ value: Any?) -> Int64? {
    if let value = value as? Int64 { return value }
    if let value = value as? Int { return Int64(value) }
    if let value = value as? NSNumber {
      guard value.doubleValue == value.doubleValue.rounded() else { return nil }
      return value.int64Value
    }
    return nil
  }
}
