import 'dart:convert';

/// Canonical UUID v4 shape: 8-4-4-4-12 hex digits, version nibble `4`,
/// variant nibble one of `8`/`9`/`a`/`b`.
///
/// The installed `uuid` 4.5.3 package's public validation surface could not
/// be confirmed in this environment to check the version-4-specific nibble
/// (as opposed to general RFC4122 structure across any UUID version), so a
/// small local canonical-v4 check is used instead of assuming that
/// capability. This mirrors the exact shape `Uuid().v4()` already produces.
final RegExp _canonicalUuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

class DailyWisdomRecord {
  const DailyWisdomRecord({
    required this.text,
    required this.revealedAt,
    required this.unlockAt,
    this.revealId,
  });

  final String text;
  final DateTime revealedAt;
  final DateTime unlockAt;

  /// Stable identity of this specific reveal occurrence.
  ///
  /// Always a client-generated random UUID, never derived from [text] or
  /// from [revealedAt]/[unlockAt]. Introduced in Build 26; a Build 25
  /// record decoded before backfill will have `revealId == null`.
  ///
  /// This [DailyWisdomRecord] and the `daily_wisdom_access` state it
  /// belongs to remain device-local and are never synced. A later phase
  /// may copy this value into a separate Kept record, and only that
  /// copied Kept-record field may then participate in sync — this field,
  /// on this record, never does. `revealId` is never analytics data.
  final String? revealId;

  static const Duration lockDuration = Duration(hours: 24);

  DailyWisdomRecord copyWith({String? revealId}) => DailyWisdomRecord(
        text: text,
        revealedAt: revealedAt,
        unlockAt: unlockAt,
        revealId: revealId ?? this.revealId,
      );

  String encode() => jsonEncode({
        'text': text,
        'revealedAtMs': revealedAt.millisecondsSinceEpoch,
        'unlockAtMs': unlockAt.millisecondsSinceEpoch,
        if (revealId != null) 'revealId': revealId,
      });

  static DailyWisdomRecord decode(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid daily wisdom record.');
    }

    final text = _readString(decoded, 'text');
    final revealedAtMs = _readInt(decoded, 'revealedAtMs');
    final unlockAtMs = _readInt(decoded, 'unlockAtMs');
    final revealId = _readOptionalRevealId(decoded, 'revealId');

    if (text.trim().isEmpty || revealedAtMs < 0 || unlockAtMs <= revealedAtMs) {
      throw const FormatException('Invalid daily wisdom record.');
    }

    final revealedAt = _readDate(revealedAtMs);
    final unlockAt = _readDate(unlockAtMs);
    if (unlockAt.difference(revealedAt) != lockDuration) {
      throw const FormatException('Invalid daily wisdom record.');
    }

    return DailyWisdomRecord(
      text: text,
      revealedAt: revealedAt,
      unlockAt: unlockAt,
      revealId: revealId,
    );
  }

  static String _readString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is String) return value;
    throw const FormatException('Invalid daily wisdom record.');
  }

  /// Returns `null` when [key] is absent, preserving backward
  /// compatibility with Build 25 records that predate `revealId`.
  ///
  /// When present, the value must be an exact, canonical UUID v4 string:
  /// no surrounding whitespace, no wrong-version or wrong-variant nibble,
  /// no non-string value. Anything else is treated as corruption,
  /// consistent with the strict validation of every other field in this
  /// decoder — a revealId is an occurrence identity, not free text, so it
  /// is never trimmed or coerced into shape.
  static String? _readOptionalRevealId(Map<String, dynamic> data, String key) {
    if (!data.containsKey(key)) return null;
    final value = data[key];
    if (value is String && _canonicalUuidV4Pattern.hasMatch(value)) {
      return value;
    }
    throw const FormatException('Invalid daily wisdom record.');
  }

  static int _readInt(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is int) return value;
    throw const FormatException('Invalid daily wisdom record.');
  }

  static DateTime _readDate(int millisecondsSinceEpoch) {
    try {
      return DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch);
    } catch (_) {
      throw const FormatException('Invalid daily wisdom record.');
    }
  }
}
