class FavoriteItem {
  final String text;
  final String date;

  FavoriteItem({
    required this.text,
    required this.date,
  });

  String encode() => "$date|||$text";

  static FavoriteItem decode(String value, {required String fallbackDate}) {
    final parts = value.split("|||");

    if (parts.length >= 2) {
      return FavoriteItem(
        date: parts.first,
        text: parts.sublist(1).join("|||"),
      );
    }

    return FavoriteItem(
      date: fallbackDate,
      text: value,
    );
  }
}
