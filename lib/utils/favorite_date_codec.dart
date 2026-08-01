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
}
