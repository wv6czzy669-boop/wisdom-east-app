import 'package:characters/characters.dart';

/// One narrow policy for the optional Journal owner name.
///
/// The value is device-local and never required. Limiting it by grapheme
/// cluster (rather than UTF-16 code units) keeps composed names and emoji
/// intact while guaranteeing the fixed Journal title-page composition can
/// never be pushed outside its reserved area by an unbounded legacy value.
abstract final class JournalOwnerNamePolicy {
  static const int maximumGraphemeLength = 80;

  static String? normalize(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;

    final graphemes = trimmed.characters;
    if (graphemes.length <= maximumGraphemeLength) return trimmed;
    return graphemes.take(maximumGraphemeLength).toString().trimRight();
  }
}
