import 'package:characters/characters.dart';

/// The single text-length contract for every Reflection boundary.
///
/// A user-perceived character (extended grapheme cluster) counts as one,
/// including composed emoji, flags, skin-tone sequences, and combining marks.
abstract final class ReflectionTextPolicy {
  static const int maximumLength = 1000;

  static int length(String value) => value.characters.length;

  static bool exceedsMaximum(String value) => length(value) > maximumLength;
}
