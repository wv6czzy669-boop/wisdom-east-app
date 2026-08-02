/// Build 26 Phase 4C-1: the platform-channel wire boundary for
/// `CKEastSyncState`. Deliberately lives under `lib/sync_platform/`,
/// separate from the pure Phase 4A/4C-1 sync domain (`lib/sync/`) -- this
/// is the shape of what would cross a `MethodChannel`/`EventChannel` to or
/// from the native CloudKit bridge, not a second copy of the record's own
/// business rules.
///
/// This class never re-implements field-level validation:
/// [CloudEastSyncStateProjection.tryParseRemote] already does that exactly,
/// per `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md` §2.5/§2.6. [tryDecode]
/// only adds the checks that only make sense *at* a wire boundary crossing
/// multiple record types -- rejecting a payload that does not even claim
/// to be a `CKEastSyncState` in `EASTKeptZone` with the fixed singleton
/// `recordName`, and refusing to decode a payload carrying any key outside
/// [allowedKeys] -- before delegating to the existing parser.
///
/// Unknown keys (including any daily-access-shaped field a caller might
/// smuggle in) are rejected **generically**, by allowlist membership, never
/// by naming a specific forbidden field -- see
/// `cloud_kept_wisdom_wire_envelope.dart`'s identical rationale.
///
/// This phase is transport-free: no method here performs a `MethodChannel`
/// call, reads a `CKRecord`, or touches CloudKit in any way.
library;

import '../sync/cloud_east_sync_state_projection.dart';

final class CloudEastSyncStateWireEnvelope {
  const CloudEastSyncStateWireEnvelope._();

  /// The exact, approved wire-level key set for this envelope -- every key
  /// `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md` §2.1/§2.5 defines for
  /// `CKEastSyncState`, plus this envelope's own `recordType`/`zoneName`/
  /// `recordName` tags. [tryDecode] rejects any raw payload carrying a key
  /// outside this set. Kept as a separate literal set here (never a shared
  /// mutable constant) so a future change to one record type's allowed-key
  /// set can never accidentally affect the other's.
  static const Set<String> allowedKeys = {
    'recordType',
    'zoneName',
    'recordName',
    'dataEpoch',
    'resetAtMs',
    'mutationId',
    'schemaVersion',
  };

  /// The wire-level `recordType` tag this envelope only ever encodes or
  /// accepts. Mirrors `CloudEastSyncStateProjection.recordType`.
  static const String recordType = CloudEastSyncStateProjection.recordType;

  /// The wire-level `zoneName` tag this envelope only ever encodes or
  /// accepts. Mirrors `CloudEastSyncStateProjection.zoneName`.
  static const String zoneName = CloudEastSyncStateProjection.zoneName;

  /// The wire-level `recordName` tag this envelope only ever encodes or
  /// accepts -- always the fixed singleton value, never derived.
  static const String recordName = CloudEastSyncStateProjection.recordName;

  /// Encodes [projection] into the loosely-typed `Map` shape a
  /// `MethodChannel` call would carry.
  static Map<Object?, Object?> encode(
    CloudEastSyncStateProjection projection,
  ) {
    return {
      'recordType': recordType,
      'zoneName': zoneName,
      'recordName': recordName,
      'dataEpoch': projection.dataEpoch.value,
      if (projection.resetAtMs != null) 'resetAtMs': projection.resetAtMs,
      'mutationId': projection.mutationId,
      'schemaVersion': projection.schemaVersion,
    };
  }

  /// Parses a loosely-typed wire payload (`Map<Object?, Object?>`, never
  /// Dart's own `Map<String, dynamic>`) back into a
  /// [CloudEastSyncStateProjection]. Returns `null` for anything malformed,
  /// unsupported, or forbidden. Never throws.
  ///
  /// Rejects, before ever reaching
  /// [CloudEastSyncStateProjection.tryParseRemote]:
  /// - a `recordType` other than [recordType];
  /// - a `zoneName` other than [zoneName];
  /// - a `recordName` other than the fixed singleton [recordName] -- there
  ///   is exactly one `CKEastSyncState` record per private database, and it
  ///   never has any other name;
  /// - any key outside [allowedKeys] -- generic allowlist rejection, so a
  ///   daily-access (or any other unapproved) field is refused without this
  ///   file ever naming it;
  /// - any non-`String` key.
  static CloudEastSyncStateProjection? tryDecode(Map<Object?, Object?> raw) {
    final recordTypeValue = raw['recordType'];
    if (recordTypeValue != recordType) return null;

    final zoneNameValue = raw['zoneName'];
    if (zoneNameValue != zoneName) return null;

    final recordNameValue = raw['recordName'];
    if (recordNameValue != recordName) return null;

    final converted = <String, dynamic>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String) return null;
      if (!allowedKeys.contains(key)) return null;
      converted[key] = entry.value;
    }

    return CloudEastSyncStateProjection.tryParseRemote(converted);
  }
}
