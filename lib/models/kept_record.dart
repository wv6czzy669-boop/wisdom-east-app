import 'dart:convert';

import 'reflection_history.dart';

import '../utils/canonical_uuid.dart';
import '../data/wisdoms.dart';
import '../utils/reflection_text_policy.dart';

/// An active, user-visible Kept wisdom (and its optional Reflection).
///
/// Successor to the Build 25 `FavoriteItem`. A [KeptRecord] never
/// represents a deletion — that is a separate, later concern (see
/// ADR-007's `SyncTombstone`), not modeled here.
///
/// Identity is deliberately split across two independent fields: [id] is
/// this record's own identity (migrated verbatim from `FavoriteItem.id`
/// where applicable), while [revealId] identifies the reveal occurrence
/// this record was kept from. The two are never derived from one another,
/// and neither is ever derived from [wisdomText] or from a date/timestamp
/// alone — duplicate [wisdomText] across distinct [revealId] values is
/// expected and valid.
class KeptRecord {
  KeptRecord({
    required this.id,
    required this.revealId,
    required this.wisdomText,
    required DateTime revealedAt,
    required DateTime keptAt,
    this.reflectionText,
    this.reflectionHistoryJson,
    DateTime? reflectedAt,
    required DateTime updatedAt,
    required this.mutationId,
    String? wisdomId,
  })  : revealedAt = revealedAt.toUtc(),
        keptAt = keptAt.toUtc(),
        reflectedAt = reflectedAt?.toUtc(),
        updatedAt = updatedAt.toUtc(),
        // Historical/previous-install recovery (Build 33): a record decoded
        // with no persisted wisdomId is re-resolved, on every construction,
        // against the exact-unique-English-match catalog index. This is a
        // pure function of the immutable wisdomText snapshot below, so it is
        // safe to recompute unconditionally on every load/decode -- it never
        // writes anything back and never changes what it resolves to for a
        // given snapshot. Ambiguous (zero or multiple canonical matches)
        // text correctly stays null; see resolveUniqueWisdomIdForEnglishSnapshot.
        wisdomId =
            wisdomId ?? resolveUniqueWisdomIdForEnglishSnapshot(wisdomText) {
    final history = reflectionHistory;
    if (reflectionText == null && history.thoughts.isNotEmpty) {
      throw const FormatException(
          'Reflection history requires an original reflection.');
    }
    _validate(
      id: id,
      revealId: revealId,
      wisdomText: wisdomText,
      keptAt: this.keptAt,
      reflectionText: reflectionText,
      reflectedAt: this.reflectedAt,
      updatedAt: this.updatedAt,
      mutationId: mutationId,
      wisdomId: this.wisdomId,
    );
  }

  /// Schema version for the encoded JSON shape. Not an instance field —
  /// every constructed [KeptRecord] is schema 3; only [decode] needs to
  /// know what version a stored payload claims to be.
  static const int currentSchemaVersion = 3;

  /// Maximum accepted [reflectionText] length in user-perceived characters.
  static const int maximumReflectionLength = ReflectionTextPolicy.maximumLength;

  /// Identity of this Kept record itself. Preserved verbatim from
  /// `FavoriteItem.id` on migration. Not required to be a UUID — existing
  /// Build 25 IDs may use legacy deterministic formats (e.g.
  /// `legacy-v1-...`, `sr-v1-...`) that are not UUIDs at all.
  final String id;

  /// Identity of the reveal occurrence this record was kept from. Always a
  /// canonical UUID: version 4 for a genuine Build 26 reveal, version 5 for
  /// a deterministic identity reconstructed during Build 25 migration.
  final String revealId;

  /// Snapshot of the wisdom text at the time it was kept. Duplicates
  /// across records (under different [revealId] values) are valid.
  final String wisdomText;

  /// Historical: when the wisdom was originally revealed. Always UTC.
  final DateTime revealedAt;

  /// Historical: when the user chose to keep it. Always UTC.
  final DateTime keptAt;

  /// Optional reflection text. When non-null, contains non-whitespace
  /// content and is preserved exactly as accepted — never silently
  /// trimmed — up to [maximumReflectionLength] grapheme clusters.
  final String? reflectionText;

  final String? reflectionHistoryJson;
  ReflectionHistory get reflectionHistory =>
      ReflectionHistory.decode(reflectionHistoryJson);

  /// When the reflection was written. Always UTC when present. Must be
  /// null whenever [reflectionText] is null. [reflectionText] may
  /// temporarily exist with [reflectedAt] still null, since older data may
  /// not always carry a usable reflected-at value.
  final DateTime? reflectedAt;

  /// Last local mutation to this record. Always UTC. Drives conflict
  /// resolution in later phases; never earlier than [keptAt].
  final DateTime updatedAt;

  /// Deterministic tie-breaker only — never a record identity. Version 4
  /// for a normal mutation, version 5 for deterministic migration state.
  final String mutationId;

  /// Optional canonical catalog identity, used by [WisdomLocalizationResolver]
  /// to present this record in the reader's current locale. When a caller
  /// (or a decoded payload) does not supply one, the constructor recovers it
  /// from [wisdomText] via `resolveUniqueWisdomIdForEnglishSnapshot` -- only
  /// when exactly one canonical wisdom shares that exact English text.
  /// Ambiguous text (zero or multiple matches) stays null and the record
  /// falls back to [wisdomText] as-is, in whatever language it was
  /// originally snapshotted. This recovery is a pure function of
  /// [wisdomText] alone, re-evaluated on every construction/decode -- it
  /// never mutates stored data.
  final String? wisdomId;

  Map<String, dynamic> encode() => {
        'schemaVersion': currentSchemaVersion,
        'id': id,
        'revealId': revealId,
        'wisdomText': wisdomText,
        if (wisdomId != null) 'wisdomId': wisdomId,
        'revealedAtMs': revealedAt.millisecondsSinceEpoch,
        'keptAtMs': keptAt.millisecondsSinceEpoch,
        if (reflectionText != null) 'reflectionText': reflectionText,
        if (reflectionHistoryJson != null)
          'reflectionHistoryJson': reflectionHistoryJson,
        if (reflectedAt != null)
          'reflectedAtMs': reflectedAt!.millisecondsSinceEpoch,
        'updatedAtMs': updatedAt.millisecondsSinceEpoch,
        'mutationId': mutationId,
      };

  String encodeString() => jsonEncode(encode());

  static KeptRecord decode(Map<String, dynamic> data) {
    final schemaVersion = _readInt(data, 'schemaVersion');
    if (schemaVersion != currentSchemaVersion) {
      throw const FormatException('Unsupported kept record schema.');
    }

    final id = _readString(data, 'id');
    final revealId = _readString(data, 'revealId');
    final wisdomText = _readString(data, 'wisdomText');
    final wisdomId = _readOptionalWisdomId(data, 'wisdomId');
    final revealedAtMs = _readInt(data, 'revealedAtMs');
    final keptAtMs = _readInt(data, 'keptAtMs');
    final reflectionText = _readOptionalString(data, 'reflectionText');
    final reflectedAtMs = _readOptionalInt(data, 'reflectedAtMs');
    final updatedAtMs = _readInt(data, 'updatedAtMs');
    final mutationId = _readString(data, 'mutationId');

    return KeptRecord(
      id: id,
      revealId: revealId,
      wisdomText: wisdomText,
      wisdomId: wisdomId,
      revealedAt:
          DateTime.fromMillisecondsSinceEpoch(revealedAtMs, isUtc: true),
      keptAt: DateTime.fromMillisecondsSinceEpoch(keptAtMs, isUtc: true),
      reflectionText: reflectionText,
      reflectionHistoryJson: _readOptionalString(data, 'reflectionHistoryJson'),
      reflectedAt: reflectedAtMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(reflectedAtMs, isUtc: true),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAtMs, isUtc: true),
      mutationId: mutationId,
    );
  }

  static KeptRecord decodeString(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid kept record.');
    }
    return decode(decoded);
  }

  /// Updates only [reflectionText], [reflectedAt], [updatedAt], and
  /// [mutationId]. Every identity-bearing field ([id], [revealId],
  /// [wisdomText], [revealedAt], [keptAt]) is deliberately not a parameter
  /// here, so a copy can never accidentally change this record's identity.
  KeptRecord copyWith({
    String? reflectionText,
    String? reflectionHistoryJson,
    DateTime? reflectedAt,
    DateTime? updatedAt,
    String? mutationId,
    bool clearReflection = false,
  }) {
    return KeptRecord(
      id: id,
      revealId: revealId,
      wisdomText: wisdomText,
      revealedAt: revealedAt,
      keptAt: keptAt,
      reflectionText:
          clearReflection ? null : (reflectionText ?? this.reflectionText),
      reflectedAt: clearReflection ? null : (reflectedAt ?? this.reflectedAt),
      reflectionHistoryJson:
          reflectionHistoryJson ?? this.reflectionHistoryJson,
      updatedAt: updatedAt ?? this.updatedAt,
      mutationId: mutationId ?? this.mutationId,
      wisdomId: wisdomId,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is KeptRecord &&
        other.id == id &&
        other.revealId == revealId &&
        other.wisdomText == wisdomText &&
        other.wisdomId == wisdomId &&
        other.revealedAt.isAtSameMomentAs(revealedAt) &&
        other.keptAt.isAtSameMomentAs(keptAt) &&
        other.reflectionText == reflectionText &&
        other.reflectionHistoryJson == reflectionHistoryJson &&
        (other.reflectedAt == null && reflectedAt == null ||
            (other.reflectedAt != null &&
                reflectedAt != null &&
                other.reflectedAt!.isAtSameMomentAs(reflectedAt!))) &&
        other.updatedAt.isAtSameMomentAs(updatedAt) &&
        other.mutationId == mutationId;
  }

  @override
  int get hashCode => Object.hash(
        id,
        revealId,
        wisdomText,
        wisdomId,
        revealedAt.millisecondsSinceEpoch,
        keptAt.millisecondsSinceEpoch,
        reflectionText,
        reflectionHistoryJson,
        reflectedAt?.millisecondsSinceEpoch,
        updatedAt.millisecondsSinceEpoch,
        mutationId,
      );

  static void _validate({
    required String id,
    required String revealId,
    required String wisdomText,
    required DateTime keptAt,
    required String? reflectionText,
    required DateTime? reflectedAt,
    required DateTime updatedAt,
    required String mutationId,
    required String? wisdomId,
  }) {
    if (id.trim().isEmpty) {
      throw const FormatException('Kept record ID cannot be blank.');
    }
    if (wisdomText.trim().isEmpty) {
      throw const FormatException('Kept record wisdom text cannot be blank.');
    }
    if (!_isCanonicalUuidV4OrV5(revealId)) {
      throw const FormatException('Invalid kept record revealId.');
    }
    if (!_isCanonicalUuidV4OrV5(mutationId)) {
      throw const FormatException('Invalid kept record mutationId.');
    }
    if (wisdomId != null && !isCanonicalWisdomId(wisdomId)) {
      throw const FormatException('Invalid kept record wisdomId.');
    }

    if (reflectionText != null) {
      if (reflectionText.trim().isEmpty) {
        throw const FormatException(
          'Kept record reflection text cannot be blank.',
        );
      }
      if (ReflectionTextPolicy.exceedsMaximum(reflectionText)) {
        throw const FormatException(
          'Kept record reflection text exceeds the maximum length.',
        );
      }
    } else if (reflectedAt != null) {
      throw const FormatException(
        'Kept record cannot have reflectedAt without reflectionText.',
      );
    }

    if (updatedAt.isBefore(keptAt)) {
      throw const FormatException(
        'Kept record updatedAt cannot be before keptAt.',
      );
    }
  }

  static String? _readOptionalWisdomId(Map<String, dynamic> data, String key) {
    if (!data.containsKey(key)) return null;
    final value = data[key];
    if (value is String && isCanonicalWisdomId(value)) return value;
    throw const FormatException('Invalid kept record wisdomId.');
  }

  static bool _isCanonicalUuidV4OrV5(String value) {
    return isCanonicalUuidV4OrV5(value);
  }

  static String _readString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is String) return value;
    throw const FormatException('Invalid kept record.');
  }

  static String? _readOptionalString(Map<String, dynamic> data, String key) {
    if (!data.containsKey(key)) return null;
    final value = data[key];
    if (value is String) return value;
    throw const FormatException('Invalid kept record.');
  }

  static int _readInt(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is int) return value;
    throw const FormatException('Invalid kept record.');
  }

  static int? _readOptionalInt(Map<String, dynamic> data, String key) {
    if (!data.containsKey(key)) return null;
    final value = data[key];
    if (value is int) return value;
    throw const FormatException('Invalid kept record.');
  }
}
