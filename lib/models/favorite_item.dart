import 'dart:convert';

import '../utils/canonical_uuid.dart';
import '../data/wisdoms.dart';

class FavoriteItem {
  final String id;
  final String text;
  final String date;
  final String? reflection;
  final String? reflectedAt;

  /// Compatibility identity linking this Kept entry back to the Build 26
  /// reveal occurrence it came from. Always a canonical UUID: version 4 for
  /// a genuine Build 26 reveal, version 5 for a deterministic identity
  /// reconstructed during Build 25 legacy migration (see
  /// `KeptMigrationCoordinator`/`KeptRecord.revealId`).
  ///
  /// Always `null` for data that predates this field (every existing Build
  /// 25 current-schema entry, and every legacy pipe-format entry) — this is
  /// expected, safe, and never backfilled or fabricated here. `FavoriteItem`
  /// remains the Build 25-compatible display/storage shape; it is not
  /// itself the authoritative Kept record (see `KeptRecord`, which always
  /// requires a non-null `revealId`).
  final String? revealId;

  /// When this occurrence was added to Kept, as an ISO-8601 string —
  /// mirrors [KeptRecord.keptAt] verbatim, never derived from the
  /// human-formatted [date] string (which is display-only and already
  /// lossy: local timezone, no time-of-day). Powers Return's (Phase 9)
  /// 14-day eligibility age; never used for Kept/Reflection identity, which
  /// remains [revealId] alone. Always `null` for data that predates this
  /// field, exactly like [revealId] above — never backfilled or fabricated
  /// here.
  final String? keptAt;
  final String? wisdomId;

  const FavoriteItem({
    required this.id,
    required this.text,
    required this.date,
    this.reflection,
    this.reflectedAt,
    this.revealId,
    this.keptAt,
    this.wisdomId,
  });

  static const int currentSchemaVersion = 2;

  bool get hasReflection => reflection != null;

  FavoriteItem copyWith({
    String? id,
    String? text,
    String? date,
    String? reflection,
    String? reflectedAt,
    String? revealId,
    String? keptAt,
    String? wisdomId,
    bool clearReflection = false,
  }) {
    return FavoriteItem(
      id: id ?? this.id,
      text: text ?? this.text,
      date: date ?? this.date,
      reflection: clearReflection ? null : reflection ?? this.reflection,
      reflectedAt: clearReflection ? null : reflectedAt ?? this.reflectedAt,
      // Preserved automatically whenever a caller does not explicitly pass
      // a new value — in particular, every reflection-only edit (add/edit/
      // delete reflection, which never passes `revealId`) leaves this
      // identity untouched.
      revealId: revealId ?? this.revealId,
      keptAt: keptAt ?? this.keptAt,
      wisdomId: wisdomId ?? this.wisdomId,
    );
  }

  String encode() {
    return jsonEncode({
      'schemaVersion': currentSchemaVersion,
      'id': id,
      'date': date,
      'text': text,
      if (reflection != null) 'reflection': reflection,
      if (reflectedAt != null) 'reflectedAt': reflectedAt,
      if (revealId != null) 'revealId': revealId,
      if (wisdomId != null) 'wisdomId': wisdomId,
    });
  }

  static bool looksLikeCurrentSchema(String value) {
    final trimmed = value.trimLeft();
    return trimmed.startsWith('{') || trimmed.startsWith('[');
  }

  static FavoriteItem decodeCurrent(String value, {String? fallbackId}) {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Saved reflection must be an object.');
    }

    final schemaVersion = decoded['schemaVersion'];
    if (schemaVersion != null &&
        schemaVersion != 1 &&
        schemaVersion != currentSchemaVersion) {
      throw const FormatException('Unsupported saved reflection schema.');
    }

    final storedId = decoded['id'];
    final date = decoded['date'];
    final text = decoded['text'];
    final reflection = decoded['reflection'];
    final reflectedAt = decoded['reflectedAt'];
    if (date is! String || text is! String) {
      throw const FormatException('Invalid saved reflection fields.');
    }
    if (reflection != null && reflection is! String) {
      throw const FormatException('Invalid reflection field.');
    }
    if (reflectedAt != null && reflectedAt is! String) {
      throw const FormatException('Invalid reflection timestamp.');
    }

    // Absent (key missing, or explicit JSON null) is always valid and
    // decodes to `null` — this field postdates every Build 25 record, and
    // that data must keep decoding exactly as before this field existed.
    // When present, it must be a well-formed, canonical UUID v4/v5 — never
    // silently trimmed or rewritten into shape.
    final rawRevealId = decoded['revealId'];
    if (rawRevealId != null &&
        (rawRevealId is! String || !isCanonicalUuidV4OrV5(rawRevealId))) {
      throw const FormatException('Invalid saved reflection revealId.');
    }
    final revealId = rawRevealId as String?;
    final rawWisdomId = decoded['wisdomId'];
    if (rawWisdomId != null &&
        (rawWisdomId is! String || !isCanonicalWisdomId(rawWisdomId))) {
      throw const FormatException('Invalid saved reflection wisdomId.');
    }

    final id = switch (storedId) {
      final String value => value,
      null when fallbackId != null => fallbackId,
      _ => throw const FormatException('Invalid saved reflection ID.'),
    };

    final normalizedReflection =
        reflection is String ? reflection.trim() : null;
    final normalizedReflectedAt = reflectedAt is String ? reflectedAt : null;
    if (id.trim().isEmpty ||
        date.trim().isEmpty ||
        text.trim().isEmpty ||
        (reflection != null && normalizedReflection!.isEmpty) ||
        (normalizedReflection != null && normalizedReflection.length > 250)) {
      throw const FormatException('Invalid saved reflection.');
    }

    return FavoriteItem(
      id: id,
      date: date,
      text: text,
      reflection: normalizedReflection,
      reflectedAt: normalizedReflection == null ? null : normalizedReflectedAt,
      revealId: revealId,
      wisdomId: (rawWisdomId as String?) ??
          resolveUniqueWisdomIdForEnglishSnapshot(text),
    );
  }

  static FavoriteItem decodeLegacy(String value, {required String id}) {
    if (value.trim().isEmpty) {
      throw const FormatException('Saved reflection cannot be empty.');
    }

    final parts = value.split("|||");
    if (parts.length < 2) {
      throw const FormatException('Legacy saved reflection is missing date.');
    }

    final date = parts.first;
    final text = parts.sublist(1).join("|||");
    if (id.trim().isEmpty || date.trim().isEmpty || text.trim().isEmpty) {
      throw const FormatException('Invalid saved reflection.');
    }

    return FavoriteItem(
      id: id,
      date: date,
      text: text,
    );
  }
}
