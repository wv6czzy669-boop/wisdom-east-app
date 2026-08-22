import '../models/kept_record.dart';
import '../data/wisdoms.dart';
import '../utils/canonical_uuid.dart';
import '../utils/kept_timestamp_canonicalizer.dart';
import 'data_epoch.dart';
import 'sync_record_identity.dart';
import 'sync_tombstone.dart';

/// Build 26 Phase 4A: the CloudKit-safe projection of a saved reveal
/// occurrence — either its active form or its tombstone form — described in
/// `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md` §2.3/§2.4.
///
/// This is a **projection**, never a second competing domain model:
/// [CloudKeptWisdomProjection.active] can only be built from an existing
/// [KeptRecord], and [CloudKeptWisdomProjection.tombstone] can only be built
/// from an existing [SyncTombstone] — there is no way to construct one from
/// raw, untyped local data, and no constructor accepts the local daily
/// ritual/access record or any other daily-access-shaped type (this file
/// imports nothing from the daily-access domain at all — see
/// `test/sync/sync_domain_privacy_test.dart` for the enforced proof).
final class CloudKeptWisdomProjection {
  const CloudKeptWisdomProjection._({
    required this.recordName,
    required this.isTombstone,
    required this.updatedAtMs,
    required this.mutationId,
    required this.dataEpoch,
    required this.schemaVersion,
    this.revealId,
    this.wisdomText,
    this.wisdomId,
    this.revealedAtMs,
    this.keptAtMs,
    this.reflectionText,
    this.reflectedAtMs,
    this.deletedAtMs,
  });

  /// Defensive, sync-domain-only guard on [wisdomText] length (Unicode code
  /// points) — independent of, and materially smaller than, CloudKit's own
  /// per-field size limits. Never a change to [KeptRecord]'s own validation,
  /// which places no upper bound on `wisdomText` today.
  static const int maximumWisdomTextLength = 10000;

  /// The CloudKit record type every projection of this class uses. See
  /// `sync_record_identity.dart`.
  static const String recordType = keptWisdomRecordType;

  /// The CloudKit custom zone every projection of this class belongs to.
  static const String zoneName = keptRecordZoneName;

  /// Deterministically derived from the occurrence's `revealId` — see
  /// `deriveKeptWisdomRecordName`. Identical for the active and tombstone
  /// forms of the same occurrence; never changes across that transition.
  final String recordName;

  /// `false` for the active form, `true` for the tombstone form.
  final bool isTombstone;

  /// Present only on the active form. `null` here always means this is (or,
  /// for a remote projection, claims to be) a tombstone-form record.
  final String? revealId;

  /// Present only on the active form.
  final String? wisdomText;
  final String? wisdomId;

  /// Present only on the active form. Milliseconds since epoch, UTC,
  /// canonicalized to whole-millisecond precision.
  final int? revealedAtMs;

  /// Present only on the active form. Milliseconds since epoch, UTC.
  final int? keptAtMs;

  /// Present only on the active form, and only when a Reflection exists.
  final String? reflectionText;

  /// Present only on the active form, and only when [reflectionText] is
  /// present.
  final int? reflectedAtMs;

  /// Present only on the tombstone form.
  final int? deletedAtMs;

  /// The client modification timestamp for this projection — drives
  /// conflict resolution (`conflict_resolution.dart`). Present on both
  /// forms. Milliseconds since epoch, UTC.
  final int updatedAtMs;

  /// Deterministic tie-breaker only — never a record identity.
  final String mutationId;

  /// The data epoch this projection was written under.
  final DataEpoch dataEpoch;

  /// `KeptRecord.currentSchemaVersion` (`3`) for the active form,
  /// `SyncTombstone.currentSchemaVersion` (`1`) for the tombstone form —
  /// read from the single existing constant in each case, never a second,
  /// independently-maintained literal.
  final int schemaVersion;

  /// Builds the active-form projection of [record].
  ///
  /// Throws [FormatException] if [record.wisdomText] exceeds
  /// [maximumWisdomTextLength] — an over-limit record can never be enqueued
  /// for sync. ([record.reflectionText] is already bounded by
  /// [KeptRecord.maximumReflectionLength] at construction time, so no
  /// separate check is duplicated here.)
  factory CloudKeptWisdomProjection.active(
    KeptRecord record, {
    required DataEpoch dataEpoch,
  }) {
    if (record.wisdomText.runes.length > maximumWisdomTextLength) {
      throw const FormatException(
        'Wisdom text exceeds the maximum sync payload length.',
      );
    }

    final reflectedAt = record.reflectedAt;
    return CloudKeptWisdomProjection._(
      recordName: deriveKeptWisdomRecordName(record.revealId),
      isTombstone: false,
      revealId: record.revealId,
      wisdomText: record.wisdomText,
      wisdomId: record.wisdomId,
      revealedAtMs:
          canonicalizeKeptTimestamp(record.revealedAt).millisecondsSinceEpoch,
      keptAtMs: canonicalizeKeptTimestamp(record.keptAt).millisecondsSinceEpoch,
      reflectionText: record.reflectionText,
      reflectedAtMs: reflectedAt == null
          ? null
          : canonicalizeKeptTimestamp(reflectedAt).millisecondsSinceEpoch,
      updatedAtMs:
          canonicalizeKeptTimestamp(record.updatedAt).millisecondsSinceEpoch,
      mutationId: record.mutationId,
      dataEpoch: dataEpoch,
      schemaVersion: KeptRecord.currentSchemaVersion,
    );
  }

  /// Builds the tombstone-form projection of [tombstone]. `revealId` is
  /// deliberately not carried as a separate wire field here (see
  /// `sync_tombstone.dart`'s doc comment) — it is already recoverable from
  /// [recordName] itself, derived once at construction time.
  factory CloudKeptWisdomProjection.tombstone(SyncTombstone tombstone) {
    return CloudKeptWisdomProjection._(
      recordName: deriveKeptWisdomRecordName(tombstone.revealId),
      isTombstone: true,
      deletedAtMs:
          canonicalizeKeptTimestamp(tombstone.deletedAt).millisecondsSinceEpoch,
      updatedAtMs:
          canonicalizeKeptTimestamp(tombstone.updatedAt).millisecondsSinceEpoch,
      mutationId: tombstone.mutationId,
      dataEpoch: tombstone.dataEpoch,
      schemaVersion: SyncTombstone.currentSchemaVersion,
    );
  }

  /// Parses a projection from loosely-typed remote fields (e.g. as decoded
  /// from a fetched `CKRecord`'s system fields via the future native
  /// bridge). Returns `null` for anything malformed, per
  /// `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md` §2.6/§2.8 — a malformed
  /// remote record must fail closed and must never block processing of
  /// every other, valid remote record in the same fetch batch. Never
  /// throws.
  static CloudKeptWisdomProjection? tryParseRemote(
    Map<String, dynamic> fields,
  ) {
    final recordName = fields['recordName'];
    if (recordName is! String || recordName.isEmpty) return null;

    final schemaVersion = fields['schemaVersion'];
    if (schemaVersion is! int) return null;

    final isTombstone = fields['isTombstone'];
    if (isTombstone is! bool) return null;

    final updatedAtMs = fields['updatedAtMs'];
    if (updatedAtMs is! int) return null;

    final mutationId = fields['mutationId'];
    if (mutationId is! String || !isCanonicalUuidV4OrV5(mutationId)) {
      return null;
    }

    final dataEpochValue = fields['dataEpoch'];
    if (dataEpochValue is! String || !DataEpoch.isValid(dataEpochValue)) {
      return null;
    }
    final dataEpoch = DataEpoch.parse(dataEpochValue);

    if (isTombstone) {
      if (schemaVersion != SyncTombstone.currentSchemaVersion) return null;

      final deletedAtMs = fields['deletedAtMs'];
      if (deletedAtMs is! int) return null;

      // A real tombstone this client would ever write never carries
      // identity/content fields -- seeing one indicates corruption or
      // tampering, not a variant to tolerate.
      const forbiddenOnTombstone = [
        'revealId',
        'wisdomText',
        'wisdomId',
        'revealedAtMs',
        'keptAtMs',
        'reflectionText',
        'reflectedAtMs',
      ];
      for (final key in forbiddenOnTombstone) {
        if (fields.containsKey(key) && fields[key] != null) return null;
      }

      return CloudKeptWisdomProjection._(
        recordName: recordName,
        isTombstone: true,
        deletedAtMs: deletedAtMs,
        updatedAtMs: updatedAtMs,
        mutationId: mutationId,
        dataEpoch: dataEpoch,
        schemaVersion: schemaVersion,
      );
    }

    if (schemaVersion != KeptRecord.currentSchemaVersion) return null;

    final revealId = fields['revealId'];
    if (revealId is! String || !isCanonicalUuidV4OrV5(revealId)) return null;
    if (recordName != deriveKeptWisdomRecordName(revealId)) return null;

    final wisdomText = fields['wisdomText'];
    if (wisdomText is! String ||
        wisdomText.trim().isEmpty ||
        wisdomText.runes.length > maximumWisdomTextLength) {
      return null;
    }
    final wisdomId = fields['wisdomId'];
    if (wisdomId != null &&
        (wisdomId is! String || !isCanonicalWisdomId(wisdomId))) {
      return null;
    }

    final revealedAtMs = fields['revealedAtMs'];
    if (revealedAtMs is! int) return null;
    final keptAtMs = fields['keptAtMs'];
    if (keptAtMs is! int) return null;

    final reflectionText = fields['reflectionText'];
    if (reflectionText != null) {
      if (reflectionText is! String ||
          reflectionText.trim().isEmpty ||
          reflectionText.runes.length > KeptRecord.maximumReflectionLength) {
        return null;
      }
    }
    final reflectedAtMs = fields['reflectedAtMs'];
    if (reflectedAtMs != null && reflectedAtMs is! int) return null;
    if (reflectionText == null && reflectedAtMs != null) return null;

    return CloudKeptWisdomProjection._(
      recordName: recordName,
      isTombstone: false,
      revealId: revealId,
      wisdomText: wisdomText,
      wisdomId: wisdomId as String?,
      revealedAtMs: revealedAtMs,
      keptAtMs: keptAtMs,
      reflectionText: reflectionText as String?,
      reflectedAtMs: reflectedAtMs as int?,
      updatedAtMs: updatedAtMs,
      mutationId: mutationId,
      dataEpoch: dataEpoch,
      schemaVersion: schemaVersion,
    );
  }

  /// A privacy-safe summary suitable for logs/diagnostics: identifiers,
  /// flags, and timestamps only — never [wisdomText] or [reflectionText].
  /// See `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md` §2.7/§7.
  Map<String, Object?> toLogSafeSummary() => {
        'recordName': recordName,
        'recordType': recordType,
        'isTombstone': isTombstone,
        'hasReflection': reflectionText != null,
        'updatedAtMs': updatedAtMs,
        'mutationId': mutationId,
        'dataEpoch': dataEpoch.value,
        'schemaVersion': schemaVersion,
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CloudKeptWisdomProjection &&
        other.recordName == recordName &&
        other.isTombstone == isTombstone &&
        other.revealId == revealId &&
        other.wisdomText == wisdomText &&
        other.revealedAtMs == revealedAtMs &&
        other.keptAtMs == keptAtMs &&
        other.reflectionText == reflectionText &&
        other.reflectedAtMs == reflectedAtMs &&
        other.deletedAtMs == deletedAtMs &&
        other.updatedAtMs == updatedAtMs &&
        other.mutationId == mutationId &&
        other.dataEpoch == dataEpoch &&
        other.schemaVersion == schemaVersion;
  }

  @override
  int get hashCode => Object.hash(
        recordName,
        isTombstone,
        revealId,
        wisdomText,
        revealedAtMs,
        keptAtMs,
        reflectionText,
        reflectedAtMs,
        deletedAtMs,
        updatedAtMs,
        mutationId,
        dataEpoch,
        schemaVersion,
      );
}
