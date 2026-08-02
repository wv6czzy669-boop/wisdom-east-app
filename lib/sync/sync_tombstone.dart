import '../utils/canonical_uuid.dart';
import '../utils/kept_timestamp_canonicalizer.dart';
import 'data_epoch.dart';

/// Build 26 Phase 4A: the local, sync-only deletion-marker model described
/// in ADR-007 (Active record and tombstone models) and
/// `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md` §2.4.
///
/// A [SyncTombstone] is never shown in the Kept UI and never carries
/// wisdom or Reflection content — it contains no `wisdomText`,
/// `reflectionText`, `revealedAt`, `keptAt`, or `reflectedAt`. Presence of a
/// tombstone for a [revealId] is itself what marks that occurrence deleted;
/// there is no separate boolean.
///
/// Deliberately a separate type from `KeptRecord`, per ADR-007's own
/// rejected-alternatives reasoning: a single record type that can represent
/// both "active" and "deleted" would force every consumer of active records
/// (UI, migration, a future Export My Data) to defensively check for a
/// tombstone-shaped record. A separate type makes that structurally
/// impossible.
///
/// **Deliberate refinement of ADR-007's original sketch** (see the design
/// doc §0/§2.4): ADR-007 originally keyed a tombstone by the deleted
/// `KeptRecord.id`, back when the CloudKit `recordName` was also derived
/// from `id`. Since the CloudKit `recordName` is now derived from `revealId`
/// (design doc §2.2), the tombstone must carry the same `revealId` so its
/// CloudKit projection can derive the identical `recordName` the active
/// form used — the record's identity must never change when it transitions
/// to tombstone form. `revealId` is an opaque UUID, never wisdom or
/// Reflection content, so carrying it here does not weaken ADR-007's
/// content-minimalism intent for tombstones in any way — it is exactly as
/// content-free as the `id` field it replaces. [localId] is retained
/// separately, optionally, purely for local bookkeeping continuity with the
/// deleted `KeptRecord.id` (e.g. correlating a tombstone back to whichever
/// local list entry it replaces) — it is never used for CloudKit identity
/// and never required to derive a `recordName`.
final class SyncTombstone {
  SyncTombstone({
    required this.revealId,
    required this.dataEpoch,
    required DateTime updatedAt,
    required DateTime deletedAt,
    required this.mutationId,
    this.localId,
  })  : updatedAt = canonicalizeKeptTimestamp(updatedAt),
        deletedAt = canonicalizeKeptTimestamp(deletedAt) {
    _validate(
      revealId: revealId,
      mutationId: mutationId,
      updatedAt: this.updatedAt,
      deletedAt: this.deletedAt,
    );
  }

  /// Schema version for this type's own encoded shape — independently
  /// versioned from `KeptRecord.currentSchemaVersion`, since a tombstone is
  /// a different shape entirely, never a partially-populated active record.
  static const int currentSchemaVersion = 1;

  /// The same `revealId` the deleted `KeptRecord` used — the CloudKit
  /// identity basis (see [deriveKeptWisdomRecordName] in
  /// `sync_record_identity.dart`). Never a new value; never regenerated.
  final String revealId;

  /// The deleted `KeptRecord.id`, retained only for local bookkeeping
  /// continuity — never sent to CloudKit, never used for record identity.
  /// Optional because a pure sync-domain tombstone (e.g. one constructed
  /// purely from a remote fetch) may not know or need the origin device's
  /// local id.
  final String? localId;

  /// The data epoch this tombstone belongs to. See
  /// `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md` §4.1.
  final DataEpoch dataEpoch;

  /// Last local mutation to this tombstone. Always UTC, millisecond-precision
  /// canonical (see `canonicalizeKeptTimestamp`). Drives conflict resolution
  /// exactly as `KeptRecord.updatedAt` does for active records.
  final DateTime updatedAt;

  /// When the deletion was finalized (after the crash-safe undo window
  /// elapsed — see ADR-007's Crash-safe undo window). Always UTC,
  /// millisecond-precision canonical.
  final DateTime deletedAt;

  /// Deterministic tie-breaker only — never a record identity. Same
  /// contract as `KeptRecord.mutationId`.
  final String mutationId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SyncTombstone &&
        other.revealId == revealId &&
        other.localId == localId &&
        other.dataEpoch == dataEpoch &&
        other.updatedAt.isAtSameMomentAs(updatedAt) &&
        other.deletedAt.isAtSameMomentAs(deletedAt) &&
        other.mutationId == mutationId;
  }

  @override
  int get hashCode => Object.hash(
        revealId,
        localId,
        dataEpoch,
        updatedAt.millisecondsSinceEpoch,
        deletedAt.millisecondsSinceEpoch,
        mutationId,
      );

  static void _validate({
    required String revealId,
    required String mutationId,
    required DateTime updatedAt,
    required DateTime deletedAt,
  }) {
    if (!isCanonicalUuidV4OrV5(revealId)) {
      throw const FormatException('Invalid sync tombstone revealId.');
    }
    if (!isCanonicalUuidV4OrV5(mutationId)) {
      throw const FormatException('Invalid sync tombstone mutationId.');
    }
    // updatedAt must never be earlier than deletedAt -- the finalized
    // deletion is itself the mutation being recorded.
    if (updatedAt.isBefore(deletedAt)) {
      throw const FormatException(
        'Sync tombstone updatedAt cannot be before deletedAt.',
      );
    }
  }
}
