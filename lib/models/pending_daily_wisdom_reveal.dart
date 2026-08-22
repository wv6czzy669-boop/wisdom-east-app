import 'dart:convert';
import '../data/wisdoms.dart';

enum PendingDailyWisdomRevealPhase {
  prepared('prepared'),
  revealedPendingCommit('revealedPendingCommit');

  const PendingDailyWisdomRevealPhase(this.value);

  final String value;

  static PendingDailyWisdomRevealPhase decode(String value) {
    for (final phase in PendingDailyWisdomRevealPhase.values) {
      if (phase.value == value) return phase;
    }
    throw const FormatException('Invalid pending daily wisdom reveal phase.');
  }
}

class PendingDailyWisdomReveal {
  PendingDailyWisdomReveal({
    required this.text,
    required this.preparedAt,
    this.confirmedRevealBoundary,
    this.phase = PendingDailyWisdomRevealPhase.prepared,
    this.wisdomId,
  }) {
    _validate(
      text: text,
      preparedAt: preparedAt,
      confirmedRevealBoundary: confirmedRevealBoundary,
      phase: phase,
      wisdomId: wisdomId ?? resolveUniqueWisdomIdForEnglishSnapshot(text),
    );
  }

  static const int schemaVersion = 1;

  final String text;
  final DateTime preparedAt;
  final DateTime? confirmedRevealBoundary;
  final PendingDailyWisdomRevealPhase phase;
  final String? wisdomId;

  bool get isRevealedPendingCommit =>
      phase == PendingDailyWisdomRevealPhase.revealedPendingCommit;

  String encode() => jsonEncode({
        'schemaVersion': schemaVersion,
        'text': text,
        'preparedAtMs': preparedAt.millisecondsSinceEpoch,
        'phase': phase.value,
        if (wisdomId != null) 'wisdomId': wisdomId,
        if (confirmedRevealBoundary != null)
          'confirmedRevealBoundaryMs':
              confirmedRevealBoundary!.millisecondsSinceEpoch,
      });

  static PendingDailyWisdomReveal decode(String value) {
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid pending daily wisdom reveal.');
    }

    final version = _readInt(decoded, 'schemaVersion');
    final text = _readString(decoded, 'text');
    final preparedAtMs = _readInt(decoded, 'preparedAtMs');
    if (preparedAtMs < 0) {
      throw const FormatException('Invalid pending reveal timestamp.');
    }
    final phase = PendingDailyWisdomRevealPhase.decode(
      _readString(decoded, 'phase'),
    );
    final confirmedRevealBoundaryMs = _readOptionalInt(
      decoded,
      'confirmedRevealBoundaryMs',
    );
    final wisdomId = _readOptionalWisdomId(decoded, 'wisdomId');
    if (decoded.containsKey('reservedBoundaryMs')) {
      throw const FormatException(
          'Reserved reveal boundaries are unsupported.');
    }
    if (confirmedRevealBoundaryMs != null && confirmedRevealBoundaryMs < 0) {
      throw const FormatException('Invalid confirmed reveal timestamp.');
    }
    final confirmedRevealBoundary = confirmedRevealBoundaryMs == null
        ? null
        : _readDate(confirmedRevealBoundaryMs);
    final preparedAt = _readDate(preparedAtMs);

    if (version != schemaVersion) {
      throw const FormatException('Invalid pending daily wisdom reveal.');
    }
    _validate(
      text: text,
      preparedAt: preparedAt,
      confirmedRevealBoundary: confirmedRevealBoundary,
      phase: phase,
      wisdomId: wisdomId,
    );

    return PendingDailyWisdomReveal(
      text: text,
      preparedAt: preparedAt,
      confirmedRevealBoundary: confirmedRevealBoundary,
      phase: phase,
    );
  }

  PendingDailyWisdomReveal copyWith({
    String? text,
    DateTime? preparedAt,
    DateTime? confirmedRevealBoundary,
    PendingDailyWisdomRevealPhase? phase,
    String? wisdomId,
  }) {
    return PendingDailyWisdomReveal(
      text: text ?? this.text,
      preparedAt: preparedAt ?? this.preparedAt,
      confirmedRevealBoundary:
          confirmedRevealBoundary ?? this.confirmedRevealBoundary,
      phase: phase ?? this.phase,
      wisdomId: wisdomId ?? this.wisdomId,
    );
  }

  static void _validate({
    required String text,
    required DateTime preparedAt,
    required DateTime? confirmedRevealBoundary,
    required PendingDailyWisdomRevealPhase phase,
    required String? wisdomId,
  }) {
    if (text.trim().isEmpty || preparedAt.millisecondsSinceEpoch < 0) {
      throw const FormatException('Invalid pending daily wisdom reveal.');
    }
    if (wisdomId != null && !isCanonicalWisdomId(wisdomId)) {
      throw const FormatException('Invalid pending daily wisdom reveal.');
    }

    if (phase == PendingDailyWisdomRevealPhase.prepared &&
        confirmedRevealBoundary != null) {
      throw const FormatException(
        'Prepared reveal cannot already have a confirmed boundary.',
      );
    }

    if (phase == PendingDailyWisdomRevealPhase.revealedPendingCommit &&
        confirmedRevealBoundary == null) {
      throw const FormatException(
        'Confirmed reveal boundary is required before commit.',
      );
    }

    if (confirmedRevealBoundary != null &&
        (confirmedRevealBoundary.millisecondsSinceEpoch < 0 ||
            confirmedRevealBoundary.isBefore(preparedAt))) {
      throw const FormatException(
        'Confirmed reveal boundary cannot be before preparation.',
      );
    }
  }

  static String _readString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is String) return value;
    throw const FormatException('Invalid pending daily wisdom reveal.');
  }

  static int _readInt(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is int) return value;
    throw const FormatException('Invalid pending daily wisdom reveal.');
  }

  static int? _readOptionalInt(Map<String, dynamic> data, String key) {
    if (!data.containsKey(key)) return null;

    final value = data[key];
    if (value is int) return value;
    throw const FormatException('Invalid pending daily wisdom reveal.');
  }

  static String? _readOptionalWisdomId(Map<String, dynamic> data, String key) {
    if (!data.containsKey(key)) return null;
    final value = data[key];
    if (value is String && isCanonicalWisdomId(value)) return value;
    throw const FormatException('Invalid pending daily wisdom reveal.');
  }

  static DateTime _readDate(int millisecondsSinceEpoch) {
    try {
      return DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch);
    } catch (_) {
      throw const FormatException('Invalid pending daily wisdom reveal.');
    }
  }
}
