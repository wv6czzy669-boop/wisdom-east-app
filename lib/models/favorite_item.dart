import 'dart:convert';

class FavoriteItem {
  final String id;
  final String text;
  final String date;
  final String? reflection;
  final String? reflectedAt;

  const FavoriteItem({
    required this.id,
    required this.text,
    required this.date,
    this.reflection,
    this.reflectedAt,
  });

  static const int currentSchemaVersion = 2;

  bool get hasReflection => reflection != null;

  FavoriteItem copyWith({
    String? id,
    String? text,
    String? date,
    String? reflection,
    String? reflectedAt,
    bool clearReflection = false,
  }) {
    return FavoriteItem(
      id: id ?? this.id,
      text: text ?? this.text,
      date: date ?? this.date,
      reflection: clearReflection ? null : reflection ?? this.reflection,
      reflectedAt: clearReflection ? null : reflectedAt ?? this.reflectedAt,
    );
  }

  String encode() {
    return jsonEncode({
      'schemaVersion': currentSchemaVersion,
      'id': id,
      'date': date,
      'text': text,
      if (reflection != null) 'reflection': reflection,
      if (reflectedAt != null) 'reflectedAt': reflectedAt,
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
    if (schemaVersion != null &&
        schemaVersion != 1 &&
        schemaVersion != currentSchemaVersion) {
      throw const FormatException('Unsupported saved reflection schema.');
    }

    final storedId = decoded['id'];
    final date = decoded['date'];
    final text = decoded['text'];
    final reflection = decoded['reflection'];
    final reflectedAt = decoded['reflectedAt'];
    if (date is! String || text is! String) {
      throw const FormatException('Invalid saved reflection fields.');
    }
    if (reflection != null && reflection is! String) {
      throw const FormatException('Invalid reflection field.');
    }
    if (reflectedAt != null && reflectedAt is! String) {
      throw const FormatException('Invalid reflection timestamp.');
    }

    final id = switch (storedId) {
      final String value => value,
      null when fallbackId != null => fallbackId,
      _ => throw const FormatException('Invalid saved reflection ID.'),
    };

    final normalizedReflection =
        reflection is String ? reflection.trim() : null;
    final normalizedReflectedAt = reflectedAt is String ? reflectedAt : null;
    if (id.trim().isEmpty ||
        date.trim().isEmpty ||
        text.trim().isEmpty ||
        (reflection != null && normalizedReflection!.isEmpty) ||
        (normalizedReflection != null && normalizedReflection.length > 250)) {
      throw const FormatException('Invalid saved reflection.');
    }

    return FavoriteItem(
      id: id,
      date: date,
      text: text,
      reflection: normalizedReflection,
      reflectedAt: normalizedReflection == null ? null : normalizedReflectedAt,
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
