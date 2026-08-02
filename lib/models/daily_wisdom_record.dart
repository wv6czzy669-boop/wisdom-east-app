import 'dart:convert';

import '../utils/canonical_uuid.dart';

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
  /// Ordinarily a client-generated random UUID v4, never derived from
  /// [text] or from [revealedAt]/[unlockAt]. Introduced in Build 26; a
  /// Build 25 record decoded before backfill will have `revealId == null`.
  ///
  /// Build 26 Phase 3D-E (safety-gap correction, round 4): may also be a
  /// deterministic migrated UUID v5, but only when
  /// `DailyAccessRepository.reconcileRevealIdForOccurrence` has adopted the
  /// already-existing migrated Kept identity for a Build 25 occurrence that
  /// was already Kept before the Build 26 upgrade — see that method's doc
  /// comment. A genuinely new Build 26 reveal is always minted as v4; this
  /// field never becomes v5 through any other path. See
  /// `isSupportedRevealId` (`lib/utils/canonical_uuid.dart`) for the exact
  /// accepted shapes.
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
  /// When present, the value must satisfy [isSupportedRevealId]: an exact,
  /// canonical UUID v4 (a genuine Build 26-native reveal) or UUID v5 (a
  /// migrated Build 25 identity adopted via
  /// `DailyAccessRepository.reconcileRevealIdForOccurrence`) string — no
  /// surrounding whitespace, no unsupported version/variant nibble, no
  /// non-string value. Anything else is treated as corruption, consistent
  /// with the strict validation of every other field in this decoder — a
  /// revealId is an occurrence identity, not free text, so it is never
  /// trimmed or coerced into shape.
  ///
  /// Build 26 Phase 3D-E (safety-gap correction, round 4): this previously
  /// accepted only UUID v4, via a locally-duplicated pattern. That silently
  /// rejected a genuine, correctly-written migrated v5 revealId on the very
  /// next read-back, which `DailyAccessRepository._applyRevealIdCorrection`
  /// then (correctly, given its own contract) treated as a failed
  /// verification and reverted — the write always happened, but was always
  /// silently undone one line later. Widening this check to the same
  /// migration-aware policy already used for `KeptRecord.revealId` and
  /// `FavoriteItem.revealId` (see `isSupportedRevealId`) is the fix.
  static String? _readOptionalRevealId(Map<String, dynamic> data, String key) {
    if (!data.containsKey(key)) return null;
    final value = data[key];
    if (value is String && isSupportedRevealId(value)) {
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
