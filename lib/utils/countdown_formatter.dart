class CountdownFormatter {
  const CountdownFormatter._();

  static String silenceMessage(Duration remaining) {
    final safeRemaining = remaining.isNegative ? Duration.zero : remaining;
    final hours = safeRemaining.inHours;
    final minutes = safeRemaining.inMinutes % 60;

    if (hours <= 0) {
      return "Return when the silence opens again.\n${minutes + 1} min";
    }

    return "Return when the silence opens again.\n${hours}h ${minutes}m";
  }
}
