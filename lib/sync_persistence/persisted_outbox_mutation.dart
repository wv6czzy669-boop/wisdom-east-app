/// Build 26 Phase 4D-1: the durable, on-disk shape of one outbox entry.
///
/// Deliberately not a new business-rule model: every mutation this store
/// persists is an already-validated `lib/sync/sync_change.dart` `SyncChange`
/// (kind + `CloudKeptWisdomProjection` + enqueued-at timestamp) -- the exact
/// pending-outbox-mutation shape `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md`
/// §8 item 5 and ADR-007's Local state envelope/`syncMetadata` already
/// define. This file only adds the one piece of bookkeeping ADR-007 assigns
/// to `syncMetadata` that `SyncChange` itself has no reason to carry -- a
/// per-mutation outcome status -- plus the wire (JSON-map) encode/decode for
/// the whole thing.
///
/// **Layering correction:** this file previously imported the platform-
/// bridge wire envelope (under the sibling "sync platform" source
/// directory, `cloud_kept_wisdom_wire_envelope.dart`) to reuse its
/// `encode`/`tryDecode` for the nested record fields. That was a genuine
/// layer-boundary violation -- that envelope type is explicitly "the
/// platform-channel wire boundary... the shape of what would cross a
/// MethodChannel/EventChannel to or from the native CloudKit bridge", and
/// Phase 4D-1's own architecture is explicit that this persistence layer
/// must depend only on the pure Dart sync domain (`lib/sync/`), never on
/// the sync-platform layer -- Phase 4D-2's future orchestrator is what
/// eventually translates persisted domain state into a platform transport
/// call, not this store. A dedicated structural test enforces this
/// generically (no production file outside that layer's own directory may
/// import it).
///
/// This file now encodes/decodes [CloudKeptWisdomProjection] itself, using
/// only that domain type's own public fields and
/// [CloudKeptWisdomProjection.tryParseRemote] (already the one authoritative,
/// transport-neutral parser for this record's fields, per
/// `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md` §2.6/§2.8) -- never the
/// platform wire envelope's encoder, and never a second, competing
/// projection/validation model of its own. The persisted shape below
/// deliberately omits the wire envelope's `recordType`/`zoneName` tags: those
/// exist only to disambiguate a payload crossing a single shared
/// MethodChannel boundary that carries multiple CloudKit record types: this
/// store is a single-purpose local file for one record type, so tagging
/// every entry with a value that never varies would add nothing.
library;

import '../sync/cloud_kept_wisdom_projection.dart';
import '../sync/sync_change.dart';

/// The current disposition of one durable outbox entry.
///
/// An entry that has been confirmed successful by CloudKit is never
/// represented by a status here -- it is removed from the outbox entirely
/// (see `SyncPersistenceStore.applyMutationOutcomes`). Every status below
/// describes a mutation that is still, deliberately, sitting in the queue.
enum PersistedOutboxMutationStatus {
  /// Not yet attempted, or a previous attempt failed with a *retryable*
  /// transport error -- per ADR-007/§3, a retryable failure must never
  /// mutate queue content, so this status is also what a retryable failure
  /// leaves an entry as (unchanged from whatever it already was).
  pending,

  /// A previous attempt failed with a *permanent* error. Retained, never
  /// silently dropped -- a future orchestrator decides what to do with a
  /// permanently-failed mutation; this store only remembers that it happened.
  failed,

  /// A previous attempt surfaced `CKError.serverRecordChanged` (or an
  /// equivalent server-conflict signal). Kept distinguishable from an
  /// ordinary [failed] entry so a future orchestrator can route it through
  /// conflict resolution (`lib/sync/conflict_resolution.dart`) instead of a
  /// plain retry.
  conflicted,
}

PersistedOutboxMutationStatus? _tryParseStatus(Object? raw) {
  if (raw is! String) return null;
  for (final value in PersistedOutboxMutationStatus.values) {
    if (value.name == raw) return value;
  }
  return null;
}

/// The exact set of [CloudKeptWisdomProjection] fields this store persists --
/// deliberately the domain type's own field set only, never the platform
/// wire envelope's `recordType`/`zoneName` tags (see this file's own doc
/// comment for why). [_tryDecodeProjection] rejects any key outside this
/// set before ever reaching [CloudKeptWisdomProjection.tryParseRemote] --
/// the same allowlist discipline the platform wire envelope uses at its own
/// boundary, reimplemented locally here rather than imported from it.
const Set<String> _persistedProjectionKeys = {
  'recordName',
  'isTombstone',
  'revealId',
  'wisdomText',
  'revealedAtMs',
  'keptAtMs',
  'reflectionText',
  'reflectionHistoryJson',
  'reflectedAtMs',
  'deletedAtMs',
  'updatedAtMs',
  'mutationId',
  'dataEpoch',
  'schemaVersion',
};

/// Encodes [projection] using only its own public fields. This persistence
/// layer's own local encoder -- deliberately not the platform-bridge wire
/// envelope's `encode` (a sibling sync-platform source directory this file
/// must never import).
Map<String, Object?> _encodeProjection(CloudKeptWisdomProjection projection) {
  if (projection.isTombstone) {
    return {
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
    'recordName': projection.recordName,
    'isTombstone': false,
    'revealId': projection.revealId,
    'wisdomText': projection.wisdomText,
    'revealedAtMs': projection.revealedAtMs,
    'keptAtMs': projection.keptAtMs,
    if (projection.reflectionText != null)
      'reflectionText': projection.reflectionText,
    if (projection.reflectionHistoryJson != null)
      'reflectionHistoryJson': projection.reflectionHistoryJson,
    if (projection.reflectedAtMs != null)
      'reflectedAtMs': projection.reflectedAtMs,
    'updatedAtMs': projection.updatedAtMs,
    'mutationId': projection.mutationId,
    'dataEpoch': projection.dataEpoch.value,
    'schemaVersion': projection.schemaVersion,
  };
}

/// Strictly parses one persisted projection map. Rejects any key outside
/// [_persistedProjectionKeys], any non-`String` key, or anything
/// [CloudKeptWisdomProjection.tryParseRemote] itself rejects (malformed
/// `mutationId`/`dataEpoch`/`revealId`, an unsupported `schemaVersion`, an
/// over-length `wisdomText`/`reflectionText`, a tombstone carrying
/// content/identity fields it must never carry, etc.) -- that parser remains
/// this codebase's one authoritative, transport-neutral validator for these
/// fields; this function adds only the allowlist check a persisted map
/// (unlike a fetched `CKRecord`'s already-scoped system fields) needs at its
/// own boundary. Never throws.
CloudKeptWisdomProjection? _tryDecodeProjection(Map<Object?, Object?> raw) {
  final converted = <String, dynamic>{};
  for (final entry in raw.entries) {
    final key = entry.key;
    if (key is! String) return null;
    if (!_persistedProjectionKeys.contains(key)) return null;
    converted[key] = entry.value;
  }
  return CloudKeptWisdomProjection.tryParseRemote(converted);
}

/// One durable outbox entry: an already-validated [SyncChange] plus its
/// current [status].
///
/// Immutable -- callers replace an entry with a new [PersistedOutboxMutation]
/// (via `copyWith`) rather than mutating one in place, consistent with every
/// other value type in this codebase's persistence layer.
final class PersistedOutboxMutation {
  const PersistedOutboxMutation({
    required this.change,
    this.status = PersistedOutboxMutationStatus.pending,
  });

  final SyncChange change;
  final PersistedOutboxMutationStatus status;

  /// Stable unique mutation identity -- the projection's own `mutationId`.
  /// Because a genuine local edit always regenerates `mutationId`
  /// (`docs/architecture/EAST_CLOUDKIT_SYNC_V1.md` §2.3), the value captured
  /// in *this* entry never changes for the lifetime of this specific queued
  /// mutation, even though a later, different edit to the same occurrence
  /// would carry a different `mutationId` of its own.
  String get mutationId => change.projection.mutationId;

  /// The deterministic CloudKit record identity this mutation targets --
  /// derived solely from `revealId` (`lib/sync/sync_record_identity.dart`),
  /// never from wisdom text or a display date.
  String get recordName => change.projection.recordName;

  PersistedOutboxMutation copyWith({PersistedOutboxMutationStatus? status}) {
    return PersistedOutboxMutation(
      change: change,
      status: status ?? this.status,
    );
  }

  /// Encodes this entry into the loosely-typed `Map` shape the sync-state
  /// envelope's JSON file stores. Uses this file's own [_encodeProjection]
  /// for the nested record fields -- never the platform wire envelope's
  /// encoder.
  Map<String, Object?> encode() => {
        'kind': change.kind.name,
        'status': status.name,
        'enqueuedAtMs': change.enqueuedAt.toUtc().millisecondsSinceEpoch,
        'record': _encodeProjection(change.projection),
      };

  /// Strictly parses one raw outbox-entry map. Returns `null` for anything
  /// malformed, unrecognized, or internally inconsistent -- never throws,
  /// mirroring every other `tryParse`/`tryDecode` in this codebase's sync
  /// layers. Rejects any key outside the approved set, any wrong type, any
  /// unrecognized `kind`/`status`, and (by constructing a real [SyncChange],
  /// which validates this itself) any impossible active/tombstone
  /// combination -- a `delete` kind whose record is not tombstone-form, or a
  /// `create`/`update` kind whose record is tombstone-form.
  static PersistedOutboxMutation? tryDecode(Map<Object?, Object?> raw) {
    const allowedKeys = {'kind', 'status', 'enqueuedAtMs', 'record'};
    for (final key in raw.keys) {
      if (key is! String || !allowedKeys.contains(key)) return null;
    }

    final kindValue = raw['kind'];
    if (kindValue is! String) return null;
    SyncChangeKind? kind;
    for (final candidate in SyncChangeKind.values) {
      if (candidate.name == kindValue) kind = candidate;
    }
    if (kind == null) return null;

    final status = _tryParseStatus(raw['status']);
    if (status == null) return null;

    final enqueuedAtMs = raw['enqueuedAtMs'];
    if (enqueuedAtMs is! int || enqueuedAtMs < 0) return null;

    final recordValue = raw['record'];
    if (recordValue is! Map<Object?, Object?>) return null;
    final projection = _tryDecodeProjection(recordValue);
    if (projection == null) return null;

    try {
      final change = SyncChange(
        kind: kind,
        projection: projection,
        enqueuedAt:
            DateTime.fromMillisecondsSinceEpoch(enqueuedAtMs, isUtc: true),
      );
      return PersistedOutboxMutation(change: change, status: status);
    } on FormatException {
      // Impossible active/tombstone combination -- fail closed, never throw
      // from a `tryDecode`.
      return null;
    }
  }

  /// Privacy-safe summary: identifiers, flags, and timestamps only -- never
  /// wisdom or reflection text. Delegates to
  /// [SyncChange.toLogSafeSummary]/[CloudKeptWisdomProjection.toLogSafeSummary]
  /// for the nested change, adding only [status].
  Map<String, Object?> toLogSafeSummary() => {
        'status': status.name,
        ...change.toLogSafeSummary(),
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PersistedOutboxMutation &&
        other.status == status &&
        other.change.kind == change.kind &&
        other.change.projection == change.projection &&
        other.change.enqueuedAt.isAtSameMomentAs(change.enqueuedAt);
  }

  @override
  int get hashCode => Object.hash(
        status,
        change.kind,
        change.projection,
        change.enqueuedAt.millisecondsSinceEpoch,
      );
}
