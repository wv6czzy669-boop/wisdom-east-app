import 'dart:convert';

class FavoriteItem {
  final String id;
  final String text;
  final String date;

  const FavoriteItem({
    required this.id,
    required this.text,
    required this.date,
  });

  static const int currentSchemaVersion = 1;

  FavoriteItem copyWith({
    String? id,
    String? text,
    String? date,
  }) {
    return FavoriteItem(
      id: id ?? this.id,
      text: text ?? this.text,
      date: date ?? this.date,
    );
  }

  String encode() {
    return jsonEncode({
      'schemaVersion': currentSchemaVersion,
      'id': id,
      'date': date,
      'text': text,
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
    if (schemaVersion != null && schemaVersion != currentSchemaVersion) {
      throw const FormatException('Unsupported saved reflection schema.');
    }

    final storedId = decoded['id'];
    final date = decoded['date'];
    final text = decoded['text'];
    if (date is! String || text is! String) {
      throw const FormatException('Invalid saved reflection fields.');
    }

    final id = switch (storedId) {
      final String value => value,
      null when fallbackId != null => fallbackId,
      _ => throw const FormatException('Invalid saved reflection ID.'),
    };

    if (id.trim().isEmpty || date.trim().isEmpty || text.trim().isEmpty) {
      throw const FormatException('Invalid saved reflection.');
    }

    return FavoriteItem(
      id: id,
      date: date,
      text: text,
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
