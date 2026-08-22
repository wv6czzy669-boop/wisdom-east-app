/// Build 26 Phase 4C-1: the platform-channel wire boundary for
/// `CKKeptWisdom`. Deliberately lives under `lib/sync_platform/`, separate
/// from the pure Phase 4A sync domain (`lib/sync/`) -- this is the shape of
/// what would cross a `MethodChannel`/`EventChannel` to or from the native
/// CloudKit bridge, not a second copy of the record's own business rules.
///
/// This class never re-implements field-level validation:
/// [CloudKeptWisdomProjection.tryParseRemote] already does that exactly,
/// per `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md` §2.6/§2.8, and remains
/// this codebase's one authoritative parser for the record's own fields.
/// [tryDecode] only adds the checks that only make sense *at* a wire
/// boundary crossing multiple record types -- rejecting a payload that
/// does not even claim to be a `CKKeptWisdom` in `EASTKeptZone`, and
/// refusing to decode a payload carrying any key outside [allowedKeys] --
/// before delegating to the existing parser.
///
/// Unknown keys (including any daily-access-shaped field a caller might
/// smuggle in) are rejected **generically**, by allowlist membership, never
/// by naming a specific forbidden field: this file never spells out a
/// daily-access field/type name anywhere in its own source, so there is
/// nothing here for a structural daily-access-identifier scan (see
/// `test/sync_platform/cloud_kit_platform_privacy_test.dart`) to ever flag,
/// today or for any daily-access field name introduced in the future.
///
/// This phase is transport-free: no method here performs a `MethodChannel`
/// call, reads a `CKRecord`, or touches CloudKit in any way. It only
/// prepares/parses the `Map` shape such a call would eventually carry.
///
/// **Build 26 Phase 4E-3a addition:** the wire-level `systemFields` key
/// carries opaque, fetch-only CloudKit transport metadata (a record's
/// archived identity + change tag, produced natively by
/// `CloudKitOpaqueArchive.archiveSystemFields(of:)`) -- never occurrence
/// identity, content, or conflict-resolution metadata, and never a field
/// [CloudKeptWisdomProjection] itself carries (see that class's own doc
/// comment on what it is and is not). [encode] never emits this key at all
/// (there is no outgoing/save-side concept of "this record's own system
/// fields" -- an outgoing save's precondition is `previousSystemFields`, a
/// wholly separate sibling field on `CloudKitRecordChangeInput`, never part
/// of this envelope's own encoded content). [tryDecode] tolerates but
/// ignores its presence, preserving that method's existing
/// encode/decode-round-trip contract unchanged for every existing caller.
/// [tryDecodeIncoming] is the new, separate entry point genuinely fetched
/// records must go through: it requires and separately exposes a valid,
/// non-empty `systemFields` value alongside (never merged into) the
/// ordinary projection.
library;

import '../sync/cloud_kept_wisdom_projection.dart';

/// Build 26 Phase 4E-3a: one incoming, fetched changed `CKKeptWisdom`
/// record -- its ordinary occurrence/conflict-domain projection, plus its
/// opaque CloudKit system-fields transport metadata, kept as two separate
/// fields (never merged) so system fields can never accidentally
/// participate in occurrence identity, content, or conflict resolution.
///
/// Never logs, prints, or otherwise renders [systemFields] -- this class
/// carries no `toString()`/`toLogSafeSummary()` override at all, so there
/// is nothing here for a future accidental `Object.toString()`-style log
/// call to expose beyond Dart's own default (address-based) rendering,
/// which never includes field values.
final class IncomingKeptWisdomWireRecord {
  const IncomingKeptWisdomWireRecord({
    required this.projection,
    required this.systemFields,
  });

  final CloudKeptWisdomProjection projection;

  /// Opaque, transport-only CloudKit system fields for [projection]'s
  /// record, exactly as archived by the native
  /// `CloudKitOpaqueArchive.archiveSystemFields(of:)` mechanism. Always
  /// non-empty. Never decoded, interpreted, or compared here -- carried
  /// through unchanged. Never rendered by any log/diagnostic call.
  final String systemFields;
}

/// A conservative, defensive shape check for a fetch-only `systemFields`
/// transport value -- deliberately shallow and deliberately local to this
/// file (never imported from `lib/sync_persistence/`, which independently
/// defines its own equivalent `looksLikeOpaqueBase64` for its own,
/// unrelated persisted-storage boundary): `lib/sync_platform/` must not
/// depend on `lib/sync_persistence/` (see
/// `test/sync_orchestration/sync_orchestration_layering_test.dart`'s
/// existing layering boundary), so this is an intentional, narrow
/// duplication of the same shape check at a different boundary, not a
/// second, competing definition of what "opaque Base64" means.
bool _looksLikeOpaqueSystemFields(String value) {
  if (value.isEmpty) return false;
  return RegExp(r'^[A-Za-z0-9+/]+={0,2}$').hasMatch(value);
}

final class CloudKeptWisdomWireEnvelope {
  const CloudKeptWisdomWireEnvelope._();

  /// The exact, approved wire-level key set for this envelope -- every key
  /// `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md` §2.1/§2.3/§2.4 defines
  /// for `CKKeptWisdom` (active and tombstone forms combined), plus this
  /// envelope's own `recordType`/`zoneName` tags, plus (Build 26 Phase
  /// 4E-3a) the fetch-only `systemFields` transport-metadata key. [tryDecode]
  /// rejects any raw payload carrying a key outside this set -- including,
  /// but not limited to, any daily-access-shaped field -- without ever
  /// needing to name a forbidden field itself. This is a strict allowlist,
  /// never a denylist: a field this codebase has never heard of is rejected
  /// exactly as surely as one this comment could have named.
  static const Set<String> allowedKeys = {
    'recordType',
    'zoneName',
    'recordName',
    'isTombstone',
    'revealId',
    'wisdomText',
    'wisdomId',
    'revealedAtMs',
    'keptAtMs',
    'reflectionText',
    'reflectedAtMs',
    'deletedAtMs',
    'updatedAtMs',
    'mutationId',
    'dataEpoch',
    'schemaVersion',
    'systemFields',
  };

  /// The wire-level `recordType` tag this envelope only ever encodes or
  /// accepts. Mirrors `CloudKeptWisdomProjection.recordType`.
  static const String recordType = CloudKeptWisdomProjection.recordType;

  /// The wire-level `zoneName` tag this envelope only ever encodes or
  /// accepts. Mirrors `CloudKeptWisdomProjection.zoneName`.
  static const String zoneName = CloudKeptWisdomProjection.zoneName;

  /// Encodes [projection] into the loosely-typed `Map` shape a
  /// `MethodChannel` call would carry. Always includes the wire-level
  /// `recordType`/`zoneName` tags [tryDecode] checks for, in addition to
  /// every field `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md` §2.3/§2.4
  /// defines for the projection's current form.
  static Map<Object?, Object?> encode(CloudKeptWisdomProjection projection) {
    if (projection.isTombstone) {
      return {
        'recordType': recordType,
        'zoneName': zoneName,
        'recordName': projection.recordName,
        'isTombstone': true,
        'deletedAtMs': projection.deletedAtMs,
        'updatedAtMs': projection.updatedAtMs,
        'mutationId': projection.mutationId,
        'dataEpoch': projection.dataEpoch.value,
        'schemaVersion': projection.schemaVersion,
      };
    }

    return {
      'recordType': recordType,
      'zoneName': zoneName,
      'recordName': projection.recordName,
      'isTombstone': false,
      'revealId': projection.revealId,
      'wisdomText': projection.wisdomText,
      if (projection.wisdomId != null) 'wisdomId': projection.wisdomId,
      'revealedAtMs': projection.revealedAtMs,
      'keptAtMs': projection.keptAtMs,
      if (projection.reflectionText != null)
        'reflectionText': projection.reflectionText,
      if (projection.reflectedAtMs != null)
        'reflectedAtMs': projection.reflectedAtMs,
      'updatedAtMs': projection.updatedAtMs,
      'mutationId': projection.mutationId,
      'dataEpoch': projection.dataEpoch.value,
      'schemaVersion': projection.schemaVersion,
    };
  }

  /// Parses a loosely-typed wire payload (as a platform channel would
  /// deliver it -- `Map<Object?, Object?>`, never Dart's own
  /// `Map<String, dynamic>`) back into a [CloudKeptWisdomProjection].
  /// Returns `null` for anything malformed, unsupported, or forbidden.
  /// Never throws.
  ///
  /// Rejects, before ever reaching [CloudKeptWisdomProjection.tryParseRemote]:
  /// - a `recordType` other than [recordType] (an unsupported/unknown
  ///   record type arriving on this envelope's boundary);
  /// - a `zoneName` other than [zoneName] (a default-zone or otherwise
  ///   wrong-zone payload);
  /// - any key outside [allowedKeys] -- generic allowlist rejection, so a
  ///   daily-access (or any other unapproved) field is refused without this
  ///   file ever naming it;
  /// - any non-`String` key (a malformed wire map, never silently coerced).
  static CloudKeptWisdomProjection? tryDecode(Map<Object?, Object?> raw) {
    final recordTypeValue = raw['recordType'];
    if (recordTypeValue != recordType) return null;

    final zoneNameValue = raw['zoneName'];
    if (zoneNameValue != zoneName) return null;

    final converted = <String, dynamic>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String) return null;
      if (!allowedKeys.contains(key)) return null;
      converted[key] = entry.value;
    }

    return CloudKeptWisdomProjection.tryParseRemote(converted);
  }

  /// Build 26 Phase 4E-3a: the fetch-only entry point for a genuinely
  /// incoming, changed `CKKeptWisdom` record. Requires everything [tryDecode]
  /// already requires, **plus** a present, non-empty, opaque-Base64-shaped
  /// `systemFields` value -- returns `null` (fails closed) if that value is
  /// missing, empty, or malformed, exactly as it would for any other
  /// malformed required field. Never fabricates or defaults a system-fields
  /// value.
  ///
  /// Deliberately a separate method from [tryDecode], never a breaking
  /// change to it: [tryDecode] remains the general envelope decoder, still
  /// used for outgoing-request verification (where no `systemFields`
  /// concept exists), while this method is the one and only place that
  /// enforces "every genuinely fetched changed record must carry valid
  /// system fields" -- enforced here, at the single, narrowest boundary
  /// where a raw wire payload is first turned into a validated Dart value,
  /// per this phase's own fail-closed design.
  static IncomingKeptWisdomWireRecord? tryDecodeIncoming(
    Map<Object?, Object?> raw,
  ) {
    final projection = tryDecode(raw);
    if (projection == null) return null;

    final systemFieldsValue = raw['systemFields'];
    if (systemFieldsValue is! String ||
        !_looksLikeOpaqueSystemFields(systemFieldsValue)) {
      return null;
    }

    return IncomingKeptWisdomWireRecord(
      projection: projection,
      systemFields: systemFieldsValue,
    );
  }
}
