import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import '../localization/east_locale_registry.dart';

/// Loads CLDR symbols for the future target catalog before any localized date
/// is rendered. English's legacy formatter remains synchronous and unchanged.
Future<void> initializeEastDateFormatting() async {
  await Future.wait(
    EastLocaleRegistry.targets.map(
      (definition) => initializeDateFormatting(definition.tag),
    ),
  );
}

/// Produces the exact `"MMMM d, yyyy"` display shape used for every stored
/// Kept-wisdom date (`FavoriteItem.date`, and the shape
/// `FavoriteDateCodec.parseFavoriteDateToUtc` parses back) and for today's
/// on-screen date.
///
/// Pure: uses [value] exactly as supplied. Never reads the system clock —
/// callers wanting "today" call [formattedToday] instead, or (for Kept
/// compatibility mapping) pass an already-computed local `DateTime`
/// explicitly.
String formatFavoriteDisplayDate(DateTime value, {String? localeTag}) {
  // Preserve Build 26's persisted English representation byte-for-byte.
  // New localized views derive fresh display text from a reliable timestamp.
  if (localeTag != null && localeTag != 'en') {
    return DateFormat.yMMMMd(localeTag).format(value);
  }
  const months = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
  ];

  return "${months[value.month - 1]} ${value.day}, ${value.year}";
}

/// Today's date in the same `"MMMM d, yyyy"` shape as [formatFavoriteDisplayDate],
/// or [date]'s date when explicitly supplied. Output is byte-for-byte
/// unchanged from before [formatFavoriteDisplayDate] was extracted — this
/// is the same month table and format, just delegated to the new pure
/// function instead of duplicating it.
String formattedToday([DateTime? date]) {
  return formatFavoriteDisplayDate(date ?? DateTime.now());
}

/// Uses CLDR formatting only when a current timestamp is available; callers
/// retain legacy human display text when old records have no timestamp.
String formatLocalizedDateOrLegacy({
  required DateTime? timestamp,
  required String legacyDisplay,
  required String localeTag,
}) {
  if (timestamp == null) return legacyDisplay;
  return formatFavoriteDisplayDate(timestamp.toLocal(), localeTag: localeTag);
}

String localeTagForDate(Locale locale) =>
    EastLocaleRegistry.canonicalTag(locale);
