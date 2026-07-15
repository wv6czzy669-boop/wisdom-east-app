import 'dart:convert';

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
  }) {
    _validate(
      text: text,
      preparedAt: preparedAt,
      confirmedRevealBoundary: confirmedRevealBoundary,
      phase: phase,
    );
  }

  static const int schemaVersion = 1;

  final String text;
  final DateTime preparedAt;
  final DateTime? confirmedRevealBoundary;
  final PendingDailyWisdomRevealPhase phase;

  bool get isRevealedPendingCommit =>
      phase == PendingDailyWisdomRevealPhase.revealedPendingCommit;

  String encode() => jsonEncode({
        'schemaVersion': schemaVersion,
        'text': text,
        'preparedAtMs': preparedAt.millisecondsSinceEpoch,
        'phase': phase.value,
        if (confirmedRevealBoundary != null)
          'confirmedRevealBoundaryMs':
              confirmedRevealBoundary!.millisecondsSinceEpoch,
      });

  static PendingDailyWisdomReveal decode(String value) {
    final data = jsonDecode(value) as Map<String, dynamic>;
    final version = data['schemaVersion'] as int;
    final text = data['text'] as String;
    final preparedAtMs = data['preparedAtMs'] as int;
    if (preparedAtMs < 0) {
      throw const FormatException('Invalid pending reveal timestamp.');
    }
    final phase = PendingDailyWisdomRevealPhase.decode(
      data['phase'] as String? ?? PendingDailyWisdomRevealPhase.prepared.value,
    );
    final confirmedRevealBoundaryMs = data['confirmedRevealBoundaryMs'] as int?;
    if (data.containsKey('reservedBoundaryMs')) {
      throw const FormatException(
          'Reserved reveal boundaries are unsupported.');
    }
    if (confirmedRevealBoundaryMs != null && confirmedRevealBoundaryMs < 0) {
      throw const FormatException('Invalid confirmed reveal timestamp.');
    }
    final confirmedRevealBoundary = confirmedRevealBoundaryMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(confirmedRevealBoundaryMs);
    final preparedAt = DateTime.fromMillisecondsSinceEpoch(preparedAtMs);

    if (version != schemaVersion) {
      throw const FormatException('Invalid pending daily wisdom reveal.');
    }
    _validate(
      text: text,
      preparedAt: preparedAt,
      confirmedRevealBoundary: confirmedRevealBoundary,
      phase: phase,
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
  }) {
    return PendingDailyWisdomReveal(
      text: text ?? this.text,
      preparedAt: preparedAt ?? this.preparedAt,
      confirmedRevealBoundary:
          confirmedRevealBoundary ?? this.confirmedRevealBoundary,
      phase: phase ?? this.phase,
    );
  }

  static void _validate({
    required String text,
    required DateTime preparedAt,
    required DateTime? confirmedRevealBoundary,
    required PendingDailyWisdomRevealPhase phase,
  }) {
    if (text.trim().isEmpty || preparedAt.millisecondsSinceEpoch < 0) {
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
}
