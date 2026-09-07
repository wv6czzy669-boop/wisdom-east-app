/// Removes invisible emoji sequence controls that package:pdf would
/// otherwise paint as missing-glyph boxes. The visible base emoji remains and
/// is rendered by the bundled monochrome Noto Emoji fallback. Stored
/// Reflection text is never changed.
String normalizeJournalPdfText(String text) {
  final output = StringBuffer();
  for (final rune in text.runes) {
    final isVariationSelector = rune == 0xFE0E || rune == 0xFE0F;
    final isJoiner = rune == 0x200D;
    final isKeycapCombiner = rune == 0x20E3;
    final isSkinToneModifier = rune >= 0x1F3FB && rune <= 0x1F3FF;
    final isEmojiTag = rune >= 0xE0020 && rune <= 0xE007F;
    if (isVariationSelector ||
        isJoiner ||
        isKeycapCombiner ||
        isSkinToneModifier ||
        isEmojiTag) {
      continue;
    }
    output.writeCharCode(rune);
  }
  return output.toString();
}
