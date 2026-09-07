/// Build 26 Phase 4E-1: the durable, account-free local sync-intent model --
/// enough protected local information to recover, after a crash, exactly
/// which Kept/Reflection mutation still needs to become a durable
/// account-scoped `SyncChange` (`lib/sync/sync_change.dart`), even when the
/// originating local Kept record has since been removed (the tombstone
/// case).
///
/// This is deliberately **not** a `SyncChange`/`CloudKeptWisdomProjection`:
/// those require an already-known `DataEpoch`, which does not exist yet at
/// the moment a purely local Kept/Reflection action happens (see
/// `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md`'s Phase 4E-1 section). A
/// future Phase 4E-2 conversion step is what binds a [LocalSyncIntent]'s
/// [LocalSyncIntentPayload] to an account's `DataEpoch` and turns it into a
/// real `SyncChange` for `SyncPersistenceStore.enqueueMutation` -- this file
/// does not perform that conversion and does not import `sync_persistence`
/// for it.
///
/// Every field name below deliberately mirrors
/// `CloudKeptWisdomProjection`'s own field split (`lib/sync/
/// cloud_kept_wisdom_projection.dart`) so that future conversion step is a
/// pure reshuffle of already-validated values, never a second, competing
/// validation model of `revealId`/`mutationId`/timestamp shape.
library;

import '../sync/cloud_kept_wisdom_projection.dart';
import '../models/reflection_history.dart';
import '../sync/sync_record_identity.dart';
import '../utils/canonical_uuid.dart';

/// Mirrors `SyncChangeKind` (`lib/sync/sync_change.dart`) one-to-one, but is
/// a deliberately separate enum: this is the *local, not-yet-account-bound*
/// precursor kind, never a competing definition of the sync-domain's own
/// vocabulary. A future Phase 4E-2 conversion step maps [create]/[update] to
/// `SyncChangeKind.create`/`.update` and [delete] to `SyncChangeKind.delete`.
enum LocalSyncIntentKind { create, update, delete }

/// Build 26 Phase 4E-2: the *local* user-operation category a durable
/// [LocalSyncIntent] represents -- i.e. which `KeptRepository` method must be
/// replayed to complete this intent. Deliberately **not** the same concept
/// as [LocalSyncIntentKind] (which mirrors the sync domain's own
/// create/update/delete vocabulary) or `SyncChangeKind` (the eventual wire
/// operation) -- this enum exists purely so replay dispatch is an explicit,
/// exhaustive `switch` over a closed local vocabulary, never an inference
/// from payload shape (wisdom text, a displayed date, or reflection-text
/// presence alone can never disambiguate which operation produced a given
/// payload; see `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md`'s Phase 4E-2
/// section for the full rationale).
///
/// Every value here maps to exactly one active/tombstone shape and exactly
/// one [LocalSyncIntentKind] -- enforced in [LocalSyncIntent]'s own
/// constructor, never left to a caller's discipline alone:
/// [keep] <-> active-form payload, [LocalSyncIntentKind.create];
/// [reflectionSave] <-> active-form payload (with `reflectionText` present),
/// [LocalSyncIntentKind.update]; [reflectionDelete] <-> active-form payload
/// (with `reflectionText` absent), [LocalSyncIntentKind.update]; [remove] <->
/// tombstone-form payload, [LocalSyncIntentKind.delete].
enum LocalSyncIntentOperation { keep, reflectionSave, reflectionDelete, remove }

/// The minimum two recovery stages a durable [LocalSyncIntent] needs to
/// distinguish -- see the class doc comment on [LocalSyncIntent] for the
/// exact crash-window each one exists to close. There is no third
/// "complete" stage: once a durable outbox enqueue is confirmed, the intent
/// is removed entirely (`LocalSyncIntentStore.removeIntent`), never
/// transitioned to a terminal stage that would just sit there unused.
enum LocalSyncIntentStage {
  /// This intent is durable, but the corresponding local Kept/Reflection
  /// write has not yet been confirmed committed. Written *before* the local
  /// write specifically so a crash between this write and the local write
  /// leaves a durable, recoverable record of the intended action.
  pendingLocalApplication,

  /// The local Kept/Reflection write is confirmed committed; the
  /// corresponding durable outbox enqueue (`SyncPersistenceStore
  /// .enqueueMutation`, via a future Phase 4E-2 conversion) has not yet been
  /// confirmed committed.
  localCommittedOutboxPending,
}

/// The content-carrying payload of one [LocalSyncIntent] -- deliberately a
/// complete, self-sufficient snapshot (never a reference back to a live
/// Kept record) so a tombstone intent remains fully recoverable even after
/// its originating `KeptRecord` has already been removed from
/// `KeptStateEnvelope`.
///
/// Exactly one of the active-form field group ([wisdomText], [revealedAtMs],
/// [keptAtMs]) or the tombstone-form field group ([deletedAtMs]) is
/// populated, mirroring [CloudKeptWisdomProjection]'s own active/tombstone
/// split exactly -- never a third, partially-populated shape.
final class LocalSyncIntentPayload {
  LocalSyncIntentPayload._({
    required this.revealId,
    required this.isTombstone,
    required this.operation,
    required this.updatedAtMs,
    required this.mutationId,
    this.localId,
    this.wisdomText,
    this.wisdomId,
    this.revealedAtMs,
    this.keptAtMs,
    this.reflectionText,
    this.reflectionHistoryJson,
    this.reflectedAtMs,
    this.deletedAtMs,
  }) {
    _validate(
      revealId: revealId,
      mutationId: mutationId,
      isTombstone: isTombstone,
      operation: operation,
      wisdomText: wisdomText,
      wisdomId: wisdomId,
      revealedAtMs: revealedAtMs,
      keptAtMs: keptAtMs,
      reflectionText: reflectionText,
      reflectionHistoryJson: reflectionHistoryJson,
      reflectedAtMs: reflectedAtMs,
      deletedAtMs: deletedAtMs,
      updatedAtMs: updatedAtMs,
    );
  }

  /// Builds the active-form payload for a new Keep
  /// ([LocalSyncIntentOperation.keep]), a Reflection add/edit
  /// ([LocalSyncIntentOperation.reflectionSave]), a Reflection deletion
  /// ([LocalSyncIntentOperation.reflectionDelete], pass `reflectionText:
  /// null`), or a re-Keep after a prior tombstone (also [
  /// LocalSyncIntentOperation.keep]) -- every scenario that produces an
  /// active-form `CloudKeptWisdomProjection` eventually. [operation] must be
  /// one of [LocalSyncIntentOperation.keep],
  /// [LocalSyncIntentOperation.reflectionSave], or
  /// [LocalSyncIntentOperation.reflectionDelete] -- never
  /// [LocalSyncIntentOperation.remove], which only ever pairs with
  /// [tombstone]. [localId] may be populated for every one of these
  /// operations (including [LocalSyncIntentOperation.keep], once the
  /// coordinator has already pre-minted the target `KeptRecord.id` before
  /// the physical write) -- this payload does not constrain its
  /// nullability by [operation].
  factory LocalSyncIntentPayload.active({
    required String revealId,
    required LocalSyncIntentOperation operation,
    required String wisdomText,
    String? wisdomId,
    required int revealedAtMs,
    required int keptAtMs,
    required int updatedAtMs,
    required String mutationId,
    String? reflectionText,
    String? reflectionHistoryJson,
    int? reflectedAtMs,
    String? localId,
  }) {
    return LocalSyncIntentPayload._(
      revealId: revealId,
      isTombstone: false,
      operation: operation,
      wisdomText: wisdomText,
      wisdomId: wisdomId,
      revealedAtMs: revealedAtMs,
      keptAtMs: keptAtMs,
      reflectionText: reflectionText,
      reflectionHistoryJson: reflectionHistoryJson,
      reflectedAtMs: reflectedAtMs,
      updatedAtMs: updatedAtMs,
      mutationId: mutationId,
      localId: localId,
    );
  }

  /// Builds the tombstone-form payload for a Kept removal -- carries no
  /// content field at all, mirroring `SyncTombstone`/
  /// `CloudKeptWisdomProjection.tombstone`'s own minimal shape. Always
  /// [LocalSyncIntentOperation.remove] -- there is no other operation a
  /// tombstone-form payload can represent, so this factory does not expose
  /// an `operation` parameter at all.
  factory LocalSyncIntentPayload.tombstone({
    required String revealId,
    required int deletedAtMs,
    required int updatedAtMs,
    required String mutationId,
    String? localId,
  }) {
    return LocalSyncIntentPayload._(
      revealId: revealId,
      isTombstone: true,
      operation: LocalSyncIntentOperation.remove,
      deletedAtMs: deletedAtMs,
      updatedAtMs: updatedAtMs,
      mutationId: mutationId,
      localId: localId,
    );
  }

  /// The stable occurrence identity -- same contract as `KeptRecord
  /// .revealId`/`CloudKeptWisdomProjection.revealId`. Present on both forms
  /// (unlike the wire-level `CloudKeptWisdomProjection`, which omits it from
  /// the tombstone form because it is recoverable from `recordName` there --
  /// this payload keeps it directly so [LocalSyncIntent.recordName] never
  /// needs a live Kept record to compute).
  final String revealId;

  /// `false` for the active form, `true` for the tombstone form.
  final bool isTombstone;

  /// Which local `KeptRepository` operation this payload represents --
  /// always [LocalSyncIntentOperation.remove] when [isTombstone] is `true`,
  /// and always one of [LocalSyncIntentOperation.keep],
  /// [LocalSyncIntentOperation.reflectionSave], or
  /// [LocalSyncIntentOperation.reflectionDelete] when [isTombstone] is
  /// `false` -- enforced by [_validate], never left ambiguous.
  final LocalSyncIntentOperation operation;

  /// The deleted `KeptRecord.id`, retained only for local bookkeeping
  /// continuity -- never sent anywhere beyond this local store, mirroring
  /// `SyncTombstone.localId`'s own contract exactly.
  final String? localId;

  final String? wisdomText;
  final String? wisdomId;
  final int? revealedAtMs;
  final int? keptAtMs;
  final String? reflectionText;
  final String? reflectionHistoryJson;
  final int? reflectedAtMs;
  final int? deletedAtMs;

  /// The local mutation timestamp this intent captures -- becomes the
  /// eventual projection's `updatedAtMs` once converted.
  final int updatedAtMs;

  /// Becomes the eventual `SyncChange`'s projection `mutationId` once
  /// converted -- deliberately distinct from [LocalSyncIntent.intentId],
  /// which identifies this *local recovery record*, not the eventual synced
  /// mutation.
  final String mutationId;

  Map<String, Object?> encode() => {
        'revealId': revealId,
        'isTombstone': isTombstone,
        'operation': operation.name,
        if (localId != null) 'localId': localId,
        if (wisdomText != null) 'wisdomText': wisdomText,
        if (wisdomId != null) 'wisdomId': wisdomId,
        if (revealedAtMs != null) 'revealedAtMs': revealedAtMs,
        if (keptAtMs != null) 'keptAtMs': keptAtMs,
        if (reflectionText != null) 'reflectionText': reflectionText,
        if (reflectionHistoryJson != null)
          'reflectionHistoryJson': reflectionHistoryJson,
        if (reflectedAtMs != null) 'reflectedAtMs': reflectedAtMs,
        if (deletedAtMs != null) 'deletedAtMs': deletedAtMs,
        'updatedAtMs': updatedAtMs,
        'mutationId': mutationId,
      };

  /// Strictly parses one persisted payload map. Returns `null` for anything
  /// malformed or internally inconsistent -- never throws, matching every
  /// other `tryDecode` in this codebase's sync layers.
  static LocalSyncIntentPayload? tryDecode(Map<Object?, Object?> raw) {
    const allowedKeys = {
      'revealId',
      'isTombstone',
      'operation',
      'localId',
      'wisdomText',
      'wisdomId',
      'revealedAtMs',
      'keptAtMs',
      'reflectionText',
      'reflectionHistoryJson',
      'reflectedAtMs',
      'deletedAtMs',
      'updatedAtMs',
      'mutationId',
    };
    for (final key in raw.keys) {
      if (key is! String || !allowedKeys.contains(key)) return null;
    }

    final revealId = raw['revealId'];
    if (revealId is! String) return null;

    final isTombstone = raw['isTombstone'];
    if (isTombstone is! bool) return null;

    // Build 26 Phase 4E-2: strictly required -- no Phase 4E-2 production
    // intent has ever existed before this field was introduced, so there is
    // no legacy payload to silently default. A missing or unrecognized value
    // fails decode entirely, exactly like every other field here.
    final operationValue = raw['operation'];
    if (operationValue is! String) return null;
    LocalSyncIntentOperation? operation;
    for (final candidate in LocalSyncIntentOperation.values) {
      if (candidate.name == operationValue) operation = candidate;
    }
    if (operation == null) return null;

    final updatedAtMs = raw['updatedAtMs'];
    if (updatedAtMs is! int) return null;

    final mutationId = raw['mutationId'];
    if (mutationId is! String) return null;

    final localId = raw['localId'];
    if (localId != null && localId is! String) return null;

    final wisdomText = raw['wisdomText'];
    if (wisdomText != null && wisdomText is! String) return null;
    final wisdomId = raw['wisdomId'];
    if (wisdomId != null &&
        (wisdomId is! String || !isCanonicalEastWisdomId(wisdomId))) {
      return null;
    }

    final revealedAtMs = raw['revealedAtMs'];
    if (revealedAtMs != null && revealedAtMs is! int) return null;

    final keptAtMs = raw['keptAtMs'];
    if (keptAtMs != null && keptAtMs is! int) return null;

    final historyJson = raw['reflectionHistoryJson'];
    if (historyJson != null && historyJson is! String) return null;
    final reflectionText = raw['reflectionText'];
    if (reflectionText != null && reflectionText is! String) return null;

    final reflectedAtMs = raw['reflectedAtMs'];
    if (reflectedAtMs != null && reflectedAtMs is! int) return null;

    final deletedAtMs = raw['deletedAtMs'];
    if (deletedAtMs != null && deletedAtMs is! int) return null;

    try {
      return LocalSyncIntentPayload._(
        revealId: revealId,
        isTombstone: isTombstone,
        operation: operation,
        localId: localId as String?,
        wisdomText: wisdomText as String?,
        wisdomId: wisdomId as String?,
        revealedAtMs: revealedAtMs as int?,
        keptAtMs: keptAtMs as int?,
        reflectionText: reflectionText as String?,
        reflectionHistoryJson: historyJson as String?,
        reflectedAtMs: reflectedAtMs as int?,
        deletedAtMs: deletedAtMs as int?,
        updatedAtMs: updatedAtMs,
        mutationId: mutationId,
      );
    } on FormatException {
      return null;
    }
  }

  static void _validate({
    required String revealId,
    required String mutationId,
    required bool isTombstone,
    required LocalSyncIntentOperation operation,
    required String? wisdomText,
    required String? wisdomId,
    required int? revealedAtMs,
    required int? keptAtMs,
    required String? reflectionText,
    required String? reflectionHistoryJson,
    required int? reflectedAtMs,
    required int? deletedAtMs,
    required int updatedAtMs,
  }) {
    final history = ReflectionHistory.decode(reflectionHistoryJson);
    if ((isTombstone && reflectionHistoryJson != null) ||
        (reflectionText == null && history.thoughts.isNotEmpty)) {
      throw const FormatException('Inconsistent reflection history.');
    }
    if (!isSupportedRevealId(revealId)) {
      throw const FormatException('Invalid local sync intent revealId.');
    }
    if (!isCanonicalUuidV4OrV5(mutationId)) {
      throw const FormatException('Invalid local sync intent mutationId.');
    }
    if (updatedAtMs < 0) {
      throw const FormatException(
        'Local sync intent updatedAtMs cannot be negative.',
      );
    }

    // Build 26 Phase 4E-2: [operation] and [isTombstone] must always agree
    // -- [LocalSyncIntentOperation.remove] is the only operation a
    // tombstone-form payload may represent, and every other operation is
    // active-form only. This is what makes "remove must be tombstone" a
    // structural guarantee rather than a caller convention.
    final operationIsRemove = operation == LocalSyncIntentOperation.remove;
    if (operationIsRemove != isTombstone) {
      throw const FormatException(
        'Local sync intent operation is inconsistent with its active/'
        'tombstone form.',
      );
    }

    if (isTombstone) {
      if (wisdomText != null ||
          revealedAtMs != null ||
          keptAtMs != null ||
          reflectionText != null ||
          reflectedAtMs != null) {
        throw const FormatException(
          'A tombstone-form local sync intent payload must carry no active '
          'content field.',
        );
      }
      if (deletedAtMs == null) {
        throw const FormatException(
          'A tombstone-form local sync intent payload requires deletedAtMs.',
        );
      }
      return;
    }

    if (deletedAtMs != null) {
      throw const FormatException(
        'An active-form local sync intent payload must not carry '
        'deletedAtMs.',
      );
    }
    if (wisdomText == null || wisdomText.trim().isEmpty) {
      throw const FormatException(
        'An active-form local sync intent payload requires non-blank '
        'wisdomText.',
      );
    }
    if (wisdomId != null && !isCanonicalEastWisdomId(wisdomId)) {
      throw const FormatException('Invalid local sync intent wisdomId.');
    }
    if (wisdomText.runes.length >
        CloudKeptWisdomProjection.maximumWisdomTextLength) {
      throw const FormatException(
        'Local sync intent wisdomText exceeds the maximum sync payload '
        'length.',
      );
    }
    if (revealedAtMs == null || keptAtMs == null) {
      throw const FormatException(
        'An active-form local sync intent payload requires revealedAtMs '
        'and keptAtMs.',
      );
    }
    if (reflectionText == null && reflectedAtMs != null) {
      throw const FormatException(
        'Local sync intent payload cannot have reflectedAtMs without '
        'reflectionText.',
      );
    }
    if (reflectionText != null && reflectionText.trim().isEmpty) {
      throw const FormatException(
        'Local sync intent reflectionText cannot be blank.',
      );
    }

    // Build 26 Phase 4E-2: within the active form, [operation] further
    // narrows which Reflection-presence shape is legal -- never inferred
    // from `reflectionText` alone (a `keep` payload's `reflectionText` may
    // legitimately be null or, for a re-Keep after a Reflection existed on a
    // prior occurrence of the same revealId, could in principle be non-null;
    // this check exists only to pin down [reflectionSave]/[reflectionDelete]
    // exactly, per the audited requirement that "reflectionDelete must
    // remain ACTIVE/update and Reflection must be absent" and
    // "reflectionSave must remain ACTIVE/update and Reflection must be
    // present").
    if (operation == LocalSyncIntentOperation.reflectionSave &&
        reflectionText == null) {
      throw const FormatException(
        'A reflectionSave local sync intent payload requires '
        'reflectionText.',
      );
    }
    if (operation == LocalSyncIntentOperation.reflectionDelete &&
        reflectionText != null) {
      throw const FormatException(
        'A reflectionDelete local sync intent payload must not carry '
        'reflectionText.',
      );
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocalSyncIntentPayload &&
        other.revealId == revealId &&
        other.isTombstone == isTombstone &&
        other.operation == operation &&
        other.localId == localId &&
        other.wisdomText == wisdomText &&
        other.wisdomId == wisdomId &&
        other.revealedAtMs == revealedAtMs &&
        other.keptAtMs == keptAtMs &&
        other.reflectionText == reflectionText &&
        other.reflectionHistoryJson == reflectionHistoryJson &&
        other.reflectedAtMs == reflectedAtMs &&
        other.deletedAtMs == deletedAtMs &&
        other.updatedAtMs == updatedAtMs &&
        other.mutationId == mutationId;
  }

  @override
  int get hashCode => Object.hash(
        revealId,
        isTombstone,
        operation,
        localId,
        wisdomText,
        wisdomId,
        revealedAtMs,
        keptAtMs,
        reflectionText,
        reflectionHistoryJson,
        reflectedAtMs,
        deletedAtMs,
        updatedAtMs,
        mutationId,
      );
}

/// One durable, account-free local sync intent.
///
/// [intentId] is this local recovery record's *own* stable identity --
/// deliberately distinct from both [LocalSyncIntentPayload.revealId] (the
/// occurrence identity) and [LocalSyncIntentPayload.mutationId] (the
/// eventual synced mutation's own tie-breaker identity). A newer intent
/// that supersedes an older one for the same record always mints a *new*
/// [intentId], never reusing the superseded one -- this is what
/// structurally guarantees a stale acknowledgment/removal by an old
/// [intentId] can never remove the replacement (`LocalSyncIntentStore
/// .removeIntent` is exact-[intentId]-specific, and the old id simply no
/// longer names any entry once superseded).
final class LocalSyncIntent {
  LocalSyncIntent({
    required this.intentId,
    required this.kind,
    required this.payload,
    required this.stage,
    required this.enqueuedAt,
  }) {
    if (!isCanonicalUuidV4OrV5(intentId)) {
      throw const FormatException('Invalid local sync intent intentId.');
    }
    if (kind == LocalSyncIntentKind.delete && !payload.isTombstone) {
      throw const FormatException(
        'A delete-kind local sync intent must carry a tombstone-form '
        'payload.',
      );
    }
    if (kind != LocalSyncIntentKind.delete && payload.isTombstone) {
      throw const FormatException(
        'A create/update-kind local sync intent must carry an active-form '
        'payload.',
      );
    }

    // Build 26 Phase 4E-2: [kind] and [payload.operation] must always agree
    // -- each [LocalSyncIntentOperation] maps to exactly one [kind], never
    // left to a caller's discipline alone. Combined with
    // [LocalSyncIntentPayload]'s own operation/isTombstone check, this is
    // what makes "keep must remain ACTIVE/create" and "reflectionSave/
    // reflectionDelete must remain ACTIVE/update" structural guarantees.
    final requiredKind = switch (payload.operation) {
      LocalSyncIntentOperation.keep => LocalSyncIntentKind.create,
      LocalSyncIntentOperation.reflectionSave => LocalSyncIntentKind.update,
      LocalSyncIntentOperation.reflectionDelete => LocalSyncIntentKind.update,
      LocalSyncIntentOperation.remove => LocalSyncIntentKind.delete,
    };
    if (kind != requiredKind) {
      throw const FormatException(
        'Local sync intent kind does not match its operation.',
      );
    }
  }

  final String intentId;
  final LocalSyncIntentKind kind;
  final LocalSyncIntentPayload payload;
  final LocalSyncIntentStage stage;

  /// When this intent was first enqueued locally -- UTC. Used for
  /// diagnostics and deterministic ordering only, mirroring `SyncChange
  /// .enqueuedAt`'s own contract exactly: never a conflict-resolution
  /// input, never compared when deciding whether a re-enqueue is an
  /// idempotent repeat.
  final DateTime enqueuedAt;

  /// The deterministic `east-kept-<revealId>` identity this intent targets
  /// -- computable directly from [payload], never from a live Kept record.
  String get recordName => deriveKeptWisdomRecordName(payload.revealId);

  LocalSyncIntent copyWith({LocalSyncIntentStage? stage}) {
    return LocalSyncIntent(
      intentId: intentId,
      kind: kind,
      payload: payload,
      stage: stage ?? this.stage,
      enqueuedAt: enqueuedAt,
    );
  }

  Map<String, Object?> encode() => {
        'intentId': intentId,
        'kind': kind.name,
        'stage': stage.name,
        'enqueuedAtMs': enqueuedAt.toUtc().millisecondsSinceEpoch,
        'payload': payload.encode(),
      };

  /// Strictly parses one persisted intent map. Returns `null` for anything
  /// malformed, unrecognized, or internally inconsistent -- never throws.
  static LocalSyncIntent? tryDecode(Map<Object?, Object?> raw) {
    const allowedKeys = {
      'intentId',
      'kind',
      'stage',
      'enqueuedAtMs',
      'payload'
    };
    for (final key in raw.keys) {
      if (key is! String || !allowedKeys.contains(key)) return null;
    }

    final intentId = raw['intentId'];
    if (intentId is! String) return null;

    final kindValue = raw['kind'];
    if (kindValue is! String) return null;
    LocalSyncIntentKind? kind;
    for (final candidate in LocalSyncIntentKind.values) {
      if (candidate.name == kindValue) kind = candidate;
    }
    if (kind == null) return null;

    final stageValue = raw['stage'];
    if (stageValue is! String) return null;
    LocalSyncIntentStage? stage;
    for (final candidate in LocalSyncIntentStage.values) {
      if (candidate.name == stageValue) stage = candidate;
    }
    if (stage == null) return null;

    final enqueuedAtMs = raw['enqueuedAtMs'];
    if (enqueuedAtMs is! int || enqueuedAtMs < 0) return null;

    final payloadValue = raw['payload'];
    if (payloadValue is! Map<Object?, Object?>) return null;
    final payload = LocalSyncIntentPayload.tryDecode(payloadValue);
    if (payload == null) return null;

    try {
      return LocalSyncIntent(
        intentId: intentId,
        kind: kind,
        payload: payload,
        stage: stage,
        enqueuedAt: DateTime.fromMillisecondsSinceEpoch(
          enqueuedAtMs,
          isUtc: true,
        ),
      );
    } on FormatException {
      return null;
    }
  }

  /// A privacy-safe summary: kind, stage, and content-free booleans only --
  /// never [payload]'s `revealId`, `mutationId`, `wisdomText`, or
  /// `reflectionText` value, and never this intent's own [intentId].
  Map<String, Object?> toLogSafeSummary() => {
        'kind': kind.name,
        'operation': payload.operation.name,
        'stage': stage.name,
        'hasPrivatePayload': true,
        'isTombstone': payload.isTombstone,
        'hasReflection': payload.reflectionText != null,
      };

  @override
  String toString() => 'LocalSyncIntent(${toLogSafeSummary()})';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocalSyncIntent &&
        other.intentId == intentId &&
        other.kind == kind &&
        other.payload == payload &&
        other.stage == stage &&
        other.enqueuedAt.isAtSameMomentAs(enqueuedAt);
  }

  @override
  int get hashCode => Object.hash(
        intentId,
        kind,
        payload,
        stage,
        enqueuedAt.millisecondsSinceEpoch,
      );
}
