import '../data/wisdoms.dart';

/// One catalog choice before it becomes a persisted daily occurrence.
///
/// The text remains an immutable user-visible snapshot; [wisdomId] is the
/// canonical catalog identity and may be absent only for legacy/fallback
/// content.
class DailyWisdomSelection {
  DailyWisdomSelection({required this.text, this.wisdomId}) {
    final id = wisdomId;
    if (text.trim().isEmpty || (id != null && !isCanonicalWisdomId(id))) {
      throw FormatException('Invalid daily wisdom selection.');
    }
  }

  final String text;
  final String? wisdomId;
}
