/// A resolved locked-countdown duration, expressed only as the two
/// integers every consumer (visible token, accessibility phrase) renders
/// from -- never a formatted string. `hours` ranges 0-24, `minutes` 0-59.
class CountdownDuration {
  const CountdownDuration({required this.hours, required this.minutes});

  final int hours;
  final int minutes;

  /// Fixed-width, language-independent `HH:MM`.
  String get hhmm => '${_pad(hours)}:${_pad(minutes)}';

  static String _pad(int n) => n.toString().padLeft(2, '0');
}

/// A structured countdown ready to render or announce. [duration] is the
/// sole source of truth for hours/minutes -- neither the visible widget nor
/// accessibility composition may parse [hhmm] or [plainText] back apart to
/// recover it.
class CountdownPresentation {
  const CountdownPresentation({
    required this.sentence,
    required this.duration,
  });

  /// The caller's already-localized
  /// `AppLocalizations.returnWhenSilenceOpensAgain`.
  final String sentence;
  final CountdownDuration duration;

  String get hhmm => duration.hhmm;

  /// Compatibility only, for `nextWisdomMessage`/`currentText`-style plain
  /// `String` consumers -- never parsed back to recover [duration].
  String get plainText => '$sentence\n${duration.hhmm}';
}

class CountdownFormatter {
  const CountdownFormatter._();

  static const int _microsecondsPerMinute = 60 * 1000 * 1000;

  /// Ceils [remaining] to the next whole minute using its full
  /// microsecond precision -- never truncates to seconds first, so even a
  /// sub-second positive duration (e.g. 1 microsecond) ceils up to a full
  /// minute rather than collapsing to zero. `remaining <= Duration.zero`
  /// (zero or negative) is the only input that resolves to zero.
  static CountdownDuration resolve(Duration remaining) {
    if (remaining <= Duration.zero) {
      return const CountdownDuration(hours: 0, minutes: 0);
    }
    final ceilMinutes =
        (remaining.inMicroseconds + _microsecondsPerMinute - 1) ~/
            _microsecondsPerMinute;
    return CountdownDuration(
      hours: ceilMinutes ~/ 60,
      minutes: ceilMinutes % 60,
    );
  }
}
