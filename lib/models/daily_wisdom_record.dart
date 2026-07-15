import 'dart:convert';

class DailyWisdomRecord {
  const DailyWisdomRecord({
    required this.text,
    required this.revealedAt,
    required this.unlockAt,
  });

  final String text;
  final DateTime revealedAt;
  final DateTime unlockAt;

  String encode() => jsonEncode({
        'text': text,
        'revealedAtMs': revealedAt.millisecondsSinceEpoch,
        'unlockAtMs': unlockAt.millisecondsSinceEpoch,
      });

  static DailyWisdomRecord decode(String value) {
    final data = jsonDecode(value) as Map<String, dynamic>;
    final text = data['text'] as String;
    final revealedAtMs = data['revealedAtMs'] as int;
    final unlockAtMs = data['unlockAtMs'] as int;

    if (text.trim().isEmpty || unlockAtMs <= revealedAtMs) {
      throw const FormatException('Invalid daily wisdom record.');
    }

    return DailyWisdomRecord(
      text: text,
      revealedAt: DateTime.fromMillisecondsSinceEpoch(revealedAtMs),
      unlockAt: DateTime.fromMillisecondsSinceEpoch(unlockAtMs),
    );
  }
}
