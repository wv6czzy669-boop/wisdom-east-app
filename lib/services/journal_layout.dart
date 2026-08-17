import '../models/favorite_item.dart';

/// EAST. Phase 10 — Journal's own adaptive editorial pagination planner.
///
/// Pure Dart, deliberately independent of the `pdf` package: this decides
/// *which occurrences share a body page* (never how they are painted), so
/// it can be reasoned about and tested as plain data — see
/// [JournalPdfBuilder](journal_pdf_builder.dart) for the actual rendering
/// that consumes a [plan].
///
/// Uses a lightweight character-count height *estimate*
/// ([estimateEntryHeight]) — the `pdf` package's own real font metrics
/// still govern final on-page wrapping at render time, so an imperfect
/// estimate only ever affects how generously entries are grouped, never
/// whether content is lost: a normal occurrence is always kept on one page
/// as a single unbreakable block; only a genuinely oversized single
/// occurrence is ever allowed to flow across page boundaries (see
/// [JournalPageGroup.isOverflowing]).
class JournalLayoutPlanner {
  const JournalLayoutPlanner({
    this.maxEntriesPerPage = 3,
    this.pageContentHeightPt = 666,
    this.contentWidthPt = 417,
    this.dateBlockHeightPt = 36,
    this.entryGapPt = 59.53,
    this.wisdomFontSizePt = 26.26,
    this.wisdomLineHeightPt = 39.39,
    this.reflectionGapPt = 17.51,
    this.reflectionFontSizePt = 21.01,
    this.reflectionLineHeightPt = 33.62,
    this.averageCharWidthFactor = 0.46,
  });

  /// Never more than this many occurrences ever share one physical body
  /// page, regardless of how short they are.
  final int maxEntriesPerPage;

  /// The estimated usable vertical space for entry content on one A4 body
  /// page, in PDF points (margins/footer already excluded).
  final double pageContentHeightPt;

  /// The estimated usable horizontal width for wisdom/Reflection text, in
  /// PDF points (the marginal date column and gutters already excluded).
  final double contentWidthPt;

  final double dateBlockHeightPt;
  final double entryGapPt;
  final double wisdomFontSizePt;
  final double wisdomLineHeightPt;
  final double reflectionGapPt;
  final double reflectionFontSizePt;
  final double reflectionLineHeightPt;

  /// A rough, font-agnostic average character advance width, expressed as
  /// a fraction of font size -- deliberately approximate; see the class
  /// doc comment for why precision here is not load-bearing.
  final double averageCharWidthFactor;

  /// Sorts [items] oldest → newest by [FavoriteItem.keptAt] (never by
  /// wisdom text, never by list position alone) and groups them into
  /// [JournalPageGroup]s, each destined for exactly one physical body
  /// page. Items with no [FavoriteItem.revealId] (never a genuine Kept
  /// occurrence) are excluded entirely.
  List<JournalPageGroup> plan(List<FavoriteItem> items) {
    final ordered = _orderedOldestFirst(items);
    final groups = <JournalPageGroup>[];

    var index = 0;
    while (index < ordered.length) {
      final item = ordered[index];
      final height = estimateEntryHeight(item);

      if (height > pageContentHeightPt) {
        // Genuinely too long to share a page with anything, or even to fit
        // alone -- gets its own group, flagged so the renderer lets its
        // Reflection flow across as many pages as it genuinely needs
        // rather than forcing it into one unbreakable block.
        groups.add(
          JournalPageGroup(entries: [item], isOverflowing: true),
        );
        index += 1;
        continue;
      }

      final entries = <FavoriteItem>[item];
      var used = height;
      index += 1;

      while (index < ordered.length && entries.length < maxEntriesPerPage) {
        final next = ordered[index];
        final nextHeight = estimateEntryHeight(next);
        if (nextHeight > pageContentHeightPt) break;
        final withGap = used + entryGapPt + nextHeight;
        if (withGap > pageContentHeightPt) break;
        entries.add(next);
        used = withGap;
        index += 1;
      }

      groups.add(JournalPageGroup(entries: entries));
    }

    return groups;
  }

  /// A conservative estimate of the vertical space one occurrence needs:
  /// the marginal date, the wisdom (always present), and the Reflection
  /// (only if present). Never used to clip or position final content --
  /// see the class doc comment.
  double estimateEntryHeight(FavoriteItem item) {
    var height = dateBlockHeightPt;
    height += _estimateTextHeight(
      item.text,
      fontSizePt: wisdomFontSizePt,
      lineHeightPt: wisdomLineHeightPt,
    );
    final reflection = item.reflection;
    if (reflection != null && reflection.trim().isNotEmpty) {
      height += reflectionGapPt;
      height += _estimateTextHeight(
        reflection,
        fontSizePt: reflectionFontSizePt,
        lineHeightPt: reflectionLineHeightPt,
      );
    }
    return height;
  }

  double _estimateTextHeight(
    String text, {
    required double fontSizePt,
    required double lineHeightPt,
  }) {
    final averageCharWidth = fontSizePt * averageCharWidthFactor;
    final charsPerLine = (contentWidthPt / averageCharWidth).floor().clamp(
          1,
          1 << 30,
        );

    var lines = 0;
    for (final paragraph in text.split('\n')) {
      final length = paragraph.trim().length;
      lines += length == 0 ? 1 : (length / charsPerLine).ceil();
    }
    return lines * lineHeightPt;
  }

  List<FavoriteItem> _orderedOldestFirst(List<FavoriteItem> items) {
    final withRevealId = items
        .asMap()
        .entries
        .where((entry) => entry.value.revealId != null)
        .toList(growable: false);

    withRevealId.sort((a, b) {
      final aKeptAt = _parseKeptAt(a.value);
      final bKeptAt = _parseKeptAt(b.value);
      if (aKeptAt != null && bKeptAt != null) {
        final byKeptAt = aKeptAt.compareTo(bKeptAt);
        if (byKeptAt != 0) return byKeptAt;
      } else if (aKeptAt != bKeptAt) {
        // A record with no known `keptAt` (pre-Phase-9 legacy data) sorts
        // as older than any record whose `keptAt` is known.
        return aKeptAt == null ? -1 : 1;
      }
      // Stable, deterministic tiebreak -- original list order, then
      // revealId itself. Never wisdom text.
      final byOriginalOrder = a.key.compareTo(b.key);
      return byOriginalOrder != 0
          ? byOriginalOrder
          : a.value.revealId!.compareTo(b.value.revealId!);
    });

    return withRevealId.map((entry) => entry.value).toList(growable: false);
  }

  DateTime? _parseKeptAt(FavoriteItem item) {
    final raw = item.keptAt;
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }
}

/// One physical A4 body page's worth of occurrences (1–3 in the ordinary
/// case), oldest-first within the group.
class JournalPageGroup {
  const JournalPageGroup({
    required this.entries,
    this.isOverflowing = false,
  });

  /// Always exactly 1 when [isOverflowing] is true; 1–[maxEntriesPerPage]
  /// otherwise.
  final List<FavoriteItem> entries;

  /// True only for the rare occurrence whose own content is too long to
  /// fit a single A4 page even alone -- the renderer must let its
  /// Reflection flow/paginate naturally rather than forcing it onto one
  /// page or clipping it.
  final bool isOverflowing;
}
