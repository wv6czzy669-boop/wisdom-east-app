import 'dart:convert';

import '../utils/canonical_uuid.dart';
import '../data/wisdoms.dart';

class DailyWisdomRecord {
  const DailyWisdomRecord({
    required this.text,
    required this.revealedAt,
    required this.unlockAt,
    this.revealId,
    this.wisdomId,
    this.authorityAccountScope,
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
  /// The local record caches the CloudKit account authority's occurrence.
  /// New grants share this ID and their public catalog ID across devices;
  /// private questions and writing are excluded from that authority. Older
  /// local occurrences retain their existing ID during migration.
  /// `revealId` is never analytics data.
  final String? revealId;

  /// Optional canonical catalog identity. Older records retain their exact
  /// text snapshot and decode without this field.
  final String? wisdomId;

  /// Local provenance for a CloudKit-authorized occurrence. Never uploaded,
  /// logged, or used as a public identifier; absent on pre-authority records.
  final String? authorityAccountScope;

  static const Duration lockDuration = Duration(hours: 24);

  DailyWisdomRecord copyWith({String? revealId, String? wisdomId}) =>
      DailyWisdomRecord(
        text: text,
        revealedAt: revealedAt,
        unlockAt: unlockAt,
        revealId: revealId ?? this.revealId,
        wisdomId: wisdomId ?? this.wisdomId,
        authorityAccountScope: authorityAccountScope,
      );

  String encode() => jsonEncode({
        'text': text,
        'revealedAtMs': revealedAt.millisecondsSinceEpoch,
        'unlockAtMs': unlockAt.millisecondsSinceEpoch,
        if (revealId != null) 'revealId': revealId,
        if (wisdomId != null) 'wisdomId': wisdomId,
        if (authorityAccountScope != null)
          'authorityAccountScope': authorityAccountScope,
      });

  static DailyWisdomRecord decode(String value) {
    final decoded = jsonDecode(value);
    return decodeMap(decoded);
  }

  static DailyWisdomRecord decodeMap(Object? decoded) {
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid daily wisdom record.');
    }

    final text = _readString(decoded, 'text');
    final revealedAtMs = _readInt(decoded, 'revealedAtMs');
    final unlockAtMs = _readInt(decoded, 'unlockAtMs');
    final revealId = _readOptionalRevealId(decoded, 'revealId');
    final wisdomId = _readOptionalWisdomId(decoded, 'wisdomId');
    final authorityAccountScope = decoded['authorityAccountScope'];
    if (authorityAccountScope != null &&
        (authorityAccountScope is! String ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(authorityAccountScope))) {
      throw const FormatException('Invalid daily authority scope.');
    }

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
      wisdomId: wisdomId ?? resolveUniqueWisdomIdForEnglishSnapshot(text),
      authorityAccountScope: authorityAccountScope as String?,
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

  static String? _readOptionalWisdomId(Map<String, dynamic> data, String key) {
    if (!data.containsKey(key)) return null;
    final value = data[key];
    if (value is String && isCanonicalWisdomId(value)) return value;
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
