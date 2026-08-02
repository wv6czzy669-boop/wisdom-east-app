/// Deterministic, content-safe parsing of `FavoriteItem.date` values into a
/// UTC [DateTime], for migration purposes only.
///
/// `FavoriteItem.date` (`lib/models/favorite_item.dart`) is an opaque
/// display string with exactly two shapes actually seen in this codebase:
///
/// - The real, live production shape written by `formattedToday()`
///   (`lib/utils/date_formatter.dart`): an English `"MMMM d, yyyy"` display
///   string, e.g. `"August 1, 2026"`. This is what `HomeScreen.toggleFavorite`
///   writes for every real Kept wisdom, and it is never `DateTime.parse`-safe
///   on its own — Dart's `DateTime.parse` only accepts ISO 8601-shaped input.
/// - ISO-8601, accepted for backward compatibility with existing Phase 3C
///   test fixtures and any manually-authored/test data that already uses it.
///
/// This codec exists as one narrow, shared utility specifically so that
/// migration code has exactly one place to reason about `FavoriteItem.date`
/// parsing, rather than duplicating ad-hoc parsing logic per call site.
library;

import 'kept_timestamp_canonicalizer.dart';

/// Thrown by [FavoriteDateCodec.parseFavoriteDateToUtc] on any unparseable
/// input. Deliberately narrow and content-free: [stage] is a stable,
/// diagnostic-only code — [toString] never includes the original date
/// string, since `FavoriteItem.date` values (and the wisdom/reflection data
/// they are associated with) must never appear in exception output.
class FavoriteDateParseException implements Exception {
  const FavoriteDateParseException(this.stage);

  final String stage;

  @override
  String toString() => 'FavoriteDateParseException[$stage]';
}

/// Parses a `FavoriteItem.date` value into a UTC [DateTime].
abstract final class FavoriteDateCodec {
  static const List<String> _monthNames = [
    'january',
    'february',
    'march',
    'april',
    'may',
    'june',
    'july',
    'august',
    'september',
    'october',
    'november',
    'december',
  ];

  /// Matches exactly `"<Month name> <day>, <year>"` — one or two digit day,
  /// exactly four digit year (matching the real production formatter,
  /// `formattedToday()`, which always writes a 4-digit year), no
  /// leading/trailing content beyond the outer whitespace already stripped
  /// by the caller. Deliberately anchored with `^`/`$` so trailing arbitrary
  /// content — and non-4-digit year widths — are rejected rather than
  /// accepted or silently passed through to the ISO parser.
  static final RegExp _displayDatePattern = RegExp(
    r'^([A-Za-z]+) (\d{1,2}), (\d{4})$',
  );

  /// Parses [value] (a raw `FavoriteItem.date` string) into a UTC
  /// [DateTime].
  ///
  /// Accepts two shapes:
  ///
  /// 1. The real production display shape (`"MMMM d, yyyy"`, e.g.
  ///    `"August 1, 2026"`) produced by `formattedToday()`. Mapped
  ///    deterministically to `DateTime.utc(year, month, day, 12)` — UTC
  ///    noon, deliberately, not UTC midnight and not the device's local
  ///    midnight (see the constant's own doc comment below for why).
  /// 2. ISO-8601, preserved via the same `DateTime.parse(value).toUtc()`
  ///    behavior Phase 3C already used — including its existing handling of
  ///    values with an explicit UTC/offset marker (instant preserved
  ///    exactly) and values without one (Dart's own local-time
  ///    interpretation before the `.toUtc()` conversion, unchanged from
  ///    Phase 3C's original behavior — no existing fixture in this
  ///    repository exercises that shape, so it is deliberately left as-is
  ///    rather than silently reinterpreted).
  ///
  /// Throws [FavoriteDateParseException] for anything else — including a
  /// well-formed-looking display date with an impossible day (e.g.
  /// `"February 30, 2026"`), an unknown month name, or trailing content
  /// after an otherwise valid display date.
  static DateTime parseFavoriteDateToUtc(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw const FavoriteDateParseException('empty');
    }

    final displayMatch = _displayDatePattern.firstMatch(trimmed);
    if (displayMatch != null) {
      return _parseDisplayDate(displayMatch);
    }

    return _parseIso(trimmed);
  }

  static DateTime _parseDisplayDate(RegExpMatch match) {
    final monthName = match.group(1)!.toLowerCase();
    final monthIndex = _monthNames.indexOf(monthName);
    if (monthIndex == -1) {
      throw const FavoriteDateParseException('unknown-month');
    }
    final month = monthIndex + 1;

    final day = int.tryParse(match.group(2)!);
    final year = int.tryParse(match.group(3)!);
    if (day == null || year == null) {
      throw const FavoriteDateParseException('invalid-number');
    }
    if (year == 0) {
      // The regex already constrains the year to exactly four digits, so
      // "0000" is the only value that can reach this branch — never a real
      // production year, rejected explicitly rather than silently accepted
      // as year 0.
      throw const FavoriteDateParseException('invalid-year');
    }
    if (day < 1 || day > _daysInMonth(month: month, year: year)) {
      throw const FavoriteDateParseException('invalid-day');
    }

    // UTC noon, deliberately, not `DateTime.utc(year, month, day)`
    // (midnight) and not `DateTime(year, month, day)` (device-local
    // midnight):
    // - Deterministic across migration retries: the same display date
    //   always maps to the exact same instant, regardless of when or on
    //   what device a retry happens to run.
    // - Independent of the device timezone at migration execution time —
    //   `DateTime(year, month, day)` would silently produce a different
    //   authoritative envelope if a retry happened after the device's
    //   timezone changed.
    // - Noon, rather than UTC midnight, is deliberately far from the
    //   day boundary in either direction, so a later `.toLocal()` for
    //   display purposes is very unlikely to roll over into the adjacent
    //   calendar day even in common negative-offset (e.g. US) timezones.
    return DateTime.utc(year, month, day, 12);
  }

  static int _daysInMonth({required int month, required int year}) {
    const daysPerMonth = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    if (month == 2 && _isLeapYear(year)) return 29;
    return daysPerMonth[month - 1];
  }

  static bool _isLeapYear(int year) {
    if (year % 4 != 0) return false;
    if (year % 100 != 0) return true;
    return year % 400 == 0;
  }

  static DateTime _parseIso(String trimmed) {
    try {
      return DateTime.parse(trimmed).toUtc();
    } catch (_) {
      throw const FavoriteDateParseException('unparseable');
    }
  }

  /// Matches the naive (no offset/`Z` marker) ISO-8601-shaped legacy
  /// `FavoriteItem.reflectedAt` value Build 25 always wrote, via a bare
  /// `DateTime.now().toIso8601String()` call on a non-UTC `DateTime`
  /// (`toIso8601String()` never appends a zone suffix for a local/non-UTC
  /// instance) — e.g. `"2026-08-02T01:13:07.484133"`. Fractional seconds are
  /// optional and, when present, 1-6 digits.
  static final RegExp _naiveReflectedAtPattern = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(\.\d{1,6})?$',
  );

  /// Parses a legacy `FavoriteItem.reflectedAt` value for Build 25 -> 26
  /// migration into a UTC [DateTime], truncated to millisecond precision.
  ///
  /// Build 25 always wrote this value with a bare, offset-free
  /// `DateTime.now().toIso8601String()` call — so the value is a wall-clock
  /// reading with no reliable record of which device timezone it was
  /// written in. Reinterpreting those naive numbers through whichever
  /// timezone happens to be current on the *migrating* device (as a bare
  /// `DateTime.parse(value).toUtc()` call would) is non-deterministic
  /// across devices/retries and can silently shift the value onto a
  /// different calendar day than the one the user actually experienced.
  /// Instead, for a naive value, the wall-clock numbers exactly as written
  /// are preserved by tagging them UTC directly — deterministic,
  /// device-independent, and the only genuinely honest reading of a
  /// timestamp with no reliable offset, mirroring the same reasoning
  /// [parseFavoriteDateToUtc]'s noon anchor already uses.
  ///
  /// A value that *does* carry an explicit UTC/offset marker (`Z` or
  /// `+HH:MM`/`-HH:MM`) is unambiguous — its real instant is preserved
  /// exactly via `DateTime.parse(value).toUtc()`, exactly as before this
  /// method existed.
  ///
  /// Either way, the result is canonicalized to millisecond precision (via
  /// the shared `canonicalizeKeptTimestamp`,
  /// `kept_timestamp_canonicalizer.dart`) before it is returned.
  /// [KeptRecord]'s own wire format (`encode()`/`decode()`) stores only
  /// `millisecondsSinceEpoch` for every timestamp field; a genuinely
  /// sub-millisecond-precision source value (real device timestamps from
  /// `DateTime.now()` routinely carry one) would otherwise survive into the
  /// in-memory migrated `KeptRecord` but not into its encoded-then-decoded
  /// read-back, making `KeptRecord.operator==`'s exact (`isAtSameMomentAs`)
  /// comparison spuriously fail the protected store's own mandatory
  /// post-write read-back verification for perfectly valid data — the
  /// confirmed real-device migration failure this fix addresses.
  /// Canonicalizing once, here, via the same helper [KeptRepository] uses
  /// for its own normal-runtime writes, is the smallest fix that respects
  /// that existing storage contract without touching it, and avoids two
  /// slightly different private truncation implementations.
  ///
  /// Throws [FavoriteDateParseException] for anything unparseable.
  static DateTime parseLegacyReflectedAtToUtc(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw const FavoriteDateParseException('reflected-at-empty');
    }

    final DateTime parsed;
    final naiveMatch = _naiveReflectedAtPattern.firstMatch(trimmed);
    if (naiveMatch != null) {
      parsed = _parseNaiveReflectedAt(naiveMatch);
    } else {
      try {
        parsed = DateTime.parse(trimmed).toUtc();
      } catch (_) {
        throw const FavoriteDateParseException('reflected-at-unparseable');
      }
    }

    // Canonicalize to millisecond precision via the one shared helper both
    // this codec and KeptRepository use — see the doc comment above and
    // kept_timestamp_canonicalizer.dart for why this must happen regardless
    // of which branch produced [parsed].
    return canonicalizeKeptTimestamp(parsed);
  }

  static DateTime _parseNaiveReflectedAt(RegExpMatch match) {
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final hour = int.parse(match.group(4)!);
    final minute = int.parse(match.group(5)!);
    final second = int.parse(match.group(6)!);

    var millisecond = 0;
    var microsecond = 0;
    final fraction = match.group(7);
    if (fraction != null) {
      final digits = fraction.substring(1).padRight(6, '0');
      millisecond = int.parse(digits.substring(0, 3));
      microsecond = int.parse(digits.substring(3, 6));
    }

    if (month < 1 || month > 12) {
      throw const FavoriteDateParseException('reflected-at-invalid-month');
    }
    if (day < 1 || day > _daysInMonth(month: month, year: year)) {
      throw const FavoriteDateParseException('reflected-at-invalid-day');
    }
    if (hour > 23 || minute > 59 || second > 59) {
      throw const FavoriteDateParseException('reflected-at-invalid-time');
    }

    return DateTime.utc(
      year,
      month,
      day,
      hour,
      minute,
      second,
      millisecond,
      microsecond,
    );
  }
}
