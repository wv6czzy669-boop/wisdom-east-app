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

  static const Duration lockDuration = Duration(hours: 24);

  String encode() => jsonEncode({
        'text': text,
        'revealedAtMs': revealedAt.millisecondsSinceEpoch,
        'unlockAtMs': unlockAt.millisecondsSinceEpoch,
      });

  static DailyWisdomRecord decode(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid daily wisdom record.');
    }

    final text = _readString(decoded, 'text');
    final revealedAtMs = _readInt(decoded, 'revealedAtMs');
    final unlockAtMs = _readInt(decoded, 'unlockAtMs');

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
    );
  }

  static String _readString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is String) return value;
    throw const FormatException('Invalid daily wisdom record.');
  }

  static int _readInt(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is int) return value;
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
