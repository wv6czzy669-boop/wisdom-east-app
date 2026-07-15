class FavoriteItem {
  final String text;
  final String date;

  FavoriteItem({
    required this.text,
    required this.date,
  });

  String encode() => "$date|||$text";

  static FavoriteItem decode(String value, {required String fallbackDate}) {
    if (value.trim().isEmpty) {
      throw const FormatException('Saved reflection cannot be empty.');
    }

    final parts = value.split("|||");

    if (parts.length >= 2) {
      final date = parts.first;
      final text = parts.sublist(1).join("|||");
      if (date.trim().isEmpty || text.trim().isEmpty) {
        throw const FormatException('Invalid saved reflection.');
      }

      return FavoriteItem(
        date: date,
        text: text,
      );
    }

    if (fallbackDate.trim().isEmpty) {
      throw const FormatException('Invalid saved reflection fallback date.');
    }

    return FavoriteItem(
      date: fallbackDate,
      text: value,
    );
  }
}
