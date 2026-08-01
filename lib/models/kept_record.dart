import 'dart:convert';

/// Canonical RFC 4122 UUID shape, restricted to the two versions Build 26
/// actually produces: version 4 (`Uuid().v4()`, minted for every native
/// Build 26 reveal/mutation) and version 5 (deterministic, namespace-derived
/// identities produced only during Build 25 legacy migration). Any other
/// version, an invalid variant nibble, braces, surrounding whitespace,
/// missing hyphens, or any other malformed shape is rejected.
final RegExp _canonicalUuidV4OrV5Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[45][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

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
    DateTime? reflectedAt,
    required DateTime updatedAt,
    required this.mutationId,
  })  : revealedAt = revealedAt.toUtc(),
        keptAt = keptAt.toUtc(),
        reflectedAt = reflectedAt?.toUtc(),
        updatedAt = updatedAt.toUtc() {
    _validate(
      id: id,
      revealId: revealId,
      wisdomText: wisdomText,
      keptAt: this.keptAt,
      reflectionText: reflectionText,
      reflectedAt: this.reflectedAt,
      updatedAt: this.updatedAt,
      mutationId: mutationId,
    );
  }

  /// Schema version for the encoded JSON shape. Not an instance field —
  /// every constructed [KeptRecord] is schema 3; only [decode] needs to
  /// know what version a stored payload claims to be.
  static const int currentSchemaVersion = 3;

  /// Maximum accepted [reflectionText] length, in Unicode code points
  /// (not UTF-16 code units), matching the current product limit.
  static const int maximumReflectionLength = 250;

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
  /// trimmed — up to [maximumReflectionLength] Unicode code points.
  final String? reflectionText;

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

  Map<String, dynamic> encode() => {
        'schemaVersion': currentSchemaVersion,
        'id': id,
        'revealId': revealId,
        'wisdomText': wisdomText,
        'revealedAtMs': revealedAt.millisecondsSinceEpoch,
        'keptAtMs': keptAt.millisecondsSinceEpoch,
        if (reflectionText != null) 'reflectionText': reflectionText,
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
      revealedAt:
          DateTime.fromMillisecondsSinceEpoch(revealedAtMs, isUtc: true),
      keptAt: DateTime.fromMillisecondsSinceEpoch(keptAtMs, isUtc: true),
      reflectionText: reflectionText,
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
      updatedAt: updatedAt ?? this.updatedAt,
      mutationId: mutationId ?? this.mutationId,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is KeptRecord &&
        other.id == id &&
        other.revealId == revealId &&
        other.wisdomText == wisdomText &&
        other.revealedAt.isAtSameMomentAs(revealedAt) &&
        other.keptAt.isAtSameMomentAs(keptAt) &&
        other.reflectionText == reflectionText &&
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
        revealedAt.millisecondsSinceEpoch,
        keptAt.millisecondsSinceEpoch,
        reflectionText,
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

    if (reflectionText != null) {
      if (reflectionText.trim().isEmpty) {
        throw const FormatException(
          'Kept record reflection text cannot be blank.',
        );
      }
      if (reflectionText.runes.length > maximumReflectionLength) {
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

  static bool _isCanonicalUuidV4OrV5(String value) {
    return _canonicalUuidV4OrV5Pattern.hasMatch(value);
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
