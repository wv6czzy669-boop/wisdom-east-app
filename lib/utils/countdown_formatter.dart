/// One resolved duration shared by display and accessibility.
class CountdownDuration {
  const CountdownDuration(
      {required this.hours, required this.minutes, this.seconds = 0});
  final int hours;
  final int minutes;
  final int seconds;
  String get hhmmss => '${_pad(hours)}:${_pad(minutes)}:${_pad(seconds)}';
  static String _pad(int n) => n.toString().padLeft(2, '0');
}

class CountdownPresentation {
  const CountdownPresentation({required this.sentence, required this.duration});
  final String sentence;
  final CountdownDuration duration;
  String get hhmmss => duration.hhmmss;
  String get plainText => '$sentence\n${duration.hhmmss}';
}

class CountdownFormatter {
  const CountdownFormatter._();

  /// Round a positive fraction up to a second. Only an expired interval
  /// displays zero; formatting never grants or consumes a daily wisdom.
  static CountdownDuration resolve(Duration remaining) {
    if (remaining <= Duration.zero) {
      return const CountdownDuration(hours: 0, minutes: 0);
    }
    final seconds =
        (remaining.inMicroseconds + Duration.microsecondsPerSecond - 1) ~/
            Duration.microsecondsPerSecond;
    return CountdownDuration(
        hours: seconds ~/ 3600,
        minutes: (seconds ~/ 60) % 60,
        seconds: seconds % 60);
  }
}
