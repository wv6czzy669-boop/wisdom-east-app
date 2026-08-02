import '../utils/canonical_uuid.dart';
import 'data_epoch.dart';
import 'sync_record_identity.dart';

/// Build 26 Phase 4C-1: the CloudKit-safe projection of the one
/// `CKEastSyncState` singleton control record described in
/// `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md` §2.5.
///
/// This is a pure sync-domain type, not a projection *of* any local
/// Kept/Reflection model (there is no local "sync state" object to project
/// from) -- it exists purely to carry the authoritative [DataEpoch] and the
/// small amount of sync-only bookkeeping already approved by §2.5. It
/// imports nothing from the daily-access domain, and carries no field that
/// could represent one (enforced by
/// `test/sync/sync_domain_privacy_test.dart`, which scans every file under
/// `lib/sync/` including this one).
final class CloudEastSyncStateProjection {
  const CloudEastSyncStateProjection._({
    required this.dataEpoch,
    required this.mutationId,
    required this.schemaVersion,
    this.resetAtMs,
  });

  /// `SyncEastSyncStateProjection`'s own schema version -- independently
  /// versioned from `CloudKeptWisdomProjection`'s active (`3`) and
  /// tombstone (`1`) schema versions, per §2.5 ("`schemaVersion` | Int |
  /// `1`.").
  static const int currentSchemaVersion = 1;

  /// The CloudKit record type this projection uses. See
  /// `sync_record_identity.dart`.
  static const String recordType = syncStateRecordType;

  /// The CloudKit custom zone this projection belongs to.
  static const String zoneName = keptRecordZoneName;

  /// The fixed, singleton `recordName` for the one `CKEastSyncState` record
  /// that ever exists per private database. Never derived; always this
  /// exact literal (§2.1, §2.5).
  static const String recordName = syncStateRecordName;

  /// The current authoritative epoch (§4.1).
  final DataEpoch dataEpoch;

  /// Most recent epoch reset, if any. Milliseconds since epoch, UTC. `null`
  /// means no reset has ever occurred.
  final int? resetAtMs;

  /// Deterministic tie-breaker only, consistent with every other record
  /// type -- never a record identity.
  final String mutationId;

  /// `CloudEastSyncStateProjection.currentSchemaVersion` (`1`), read from
  /// the single existing constant, never a second, independently-maintained
  /// literal.
  final int schemaVersion;

  /// Builds the current projection from already-known, already-validated
  /// local values (e.g. immediately before enqueuing the singleton record
  /// for sync). Throws [FormatException] if [mutationId] is not
  /// [isCanonicalUuidV4OrV5] -- the same validation every other sync-domain
  /// mutation identity already requires.
  factory CloudEastSyncStateProjection.current({
    required DataEpoch dataEpoch,
    required String mutationId,
    DateTime? resetAt,
  }) {
    if (!isCanonicalUuidV4OrV5(mutationId)) {
      throw const FormatException(
        'Invalid CKEastSyncState mutationId.',
      );
    }
    return CloudEastSyncStateProjection._(
      dataEpoch: dataEpoch,
      mutationId: mutationId,
      schemaVersion: currentSchemaVersion,
      resetAtMs: resetAt?.toUtc().millisecondsSinceEpoch,
    );
  }

  /// Parses a projection from loosely-typed remote fields (e.g. as decoded
  /// from a fetched `CKRecord`'s system fields via a future native bridge).
  /// Returns `null` for anything malformed, mirroring
  /// `CloudKeptWisdomProjection.tryParseRemote`'s fail-closed contract
  /// (§2.6/§2.8) -- a malformed remote record must never be applied, never
  /// merged, and never block processing of anything else. Never throws.
  ///
  /// Deliberately does not accept a `recordName` field: the singleton
  /// record's identity is always the fixed literal [recordName] -- there is
  /// nothing to derive or compare it against, unlike `CKKeptWisdom`'s
  /// per-occurrence identity.
  static CloudEastSyncStateProjection? tryParseRemote(
    Map<String, dynamic> fields,
  ) {
    final schemaVersion = fields['schemaVersion'];
    if (schemaVersion is! int) return null;
    if (schemaVersion != currentSchemaVersion) return null;

    final mutationId = fields['mutationId'];
    if (mutationId is! String || !isCanonicalUuidV4OrV5(mutationId)) {
      return null;
    }

    final dataEpochValue = fields['dataEpoch'];
    if (dataEpochValue is! String || !DataEpoch.isValid(dataEpochValue)) {
      return null;
    }
    final dataEpoch = DataEpoch.parse(dataEpochValue);

    final resetAtMs = fields['resetAtMs'];
    if (resetAtMs != null && resetAtMs is! int) return null;

    return CloudEastSyncStateProjection._(
      dataEpoch: dataEpoch,
      mutationId: mutationId,
      schemaVersion: schemaVersion,
      resetAtMs: resetAtMs as int?,
    );
  }

  /// A privacy-safe summary suitable for logs/diagnostics. There is no
  /// content field on this record type to exclude (§2.5 carries no wisdom
  /// or Reflection content at all), but this method exists for parity with
  /// `CloudKeptWisdomProjection.toLogSafeSummary` and so callers never need
  /// to special-case this type when building a diagnostic trail.
  Map<String, Object?> toLogSafeSummary() => {
        'recordName': recordName,
        'recordType': recordType,
        'resetAtMs': resetAtMs,
        'mutationId': mutationId,
        'dataEpoch': dataEpoch.value,
        'schemaVersion': schemaVersion,
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CloudEastSyncStateProjection &&
        other.dataEpoch == dataEpoch &&
        other.resetAtMs == resetAtMs &&
        other.mutationId == mutationId &&
        other.schemaVersion == schemaVersion;
  }

  @override
  int get hashCode => Object.hash(
        dataEpoch,
        resetAtMs,
        mutationId,
        schemaVersion,
      );
}
