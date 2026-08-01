/// Produces the exact `"MMMM d, yyyy"` display shape used for every stored
/// Kept-wisdom date (`FavoriteItem.date`, and the shape
/// `FavoriteDateCodec.parseFavoriteDateToUtc` parses back) and for today's
/// on-screen date.
///
/// Pure: uses [value] exactly as supplied. Never reads the system clock —
/// callers wanting "today" call [formattedToday] instead, or (for Kept
/// compatibility mapping) pass an already-computed local `DateTime`
/// explicitly.
String formatFavoriteDisplayDate(DateTime value) {
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
