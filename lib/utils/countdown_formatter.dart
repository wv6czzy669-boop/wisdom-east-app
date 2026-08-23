class CountdownFormatter {
  const CountdownFormatter._();

  /// [returnWhenSilenceOpensAgain] is the caller's already-localized
  /// `AppLocalizations.returnWhenSilenceOpensAgain` for the current EAST.
  /// locale -- this formatter has no `BuildContext`/locale of its own, and
  /// never did. The duration math below (which never changes: the rolling
  /// 24-hour lock, `unlockAt`, and the exact hour/minute arithmetic) is
  /// completely unaffected by locale.
  static String silenceMessage(
    Duration remaining,
    String returnWhenSilenceOpensAgain,
  ) {
    final safeRemaining = remaining.isNegative ? Duration.zero : remaining;
    final hours = safeRemaining.inHours;
    final minutes = safeRemaining.inMinutes % 60;

    if (hours <= 0) {
      return "$returnWhenSilenceOpensAgain\n${minutes + 1} min";
    }

    return "$returnWhenSilenceOpensAgain\n${hours}h ${minutes}m";
  }
}
