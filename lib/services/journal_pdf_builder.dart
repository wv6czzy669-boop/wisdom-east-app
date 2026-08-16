import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/favorite_item.dart';
import 'journal_layout.dart';

/// EAST. Phase 10 — builds the on-device A4 Journal PDF.
///
/// Entirely local: no network call, no server, no upload of Kept or
/// Reflection content anywhere. Read-only over [FavoriteItem] data — never
/// mutates a Kept record, a Reflection, daily-access state, or Return
/// state, and never touches CloudKit.
class JournalPdfBuilder {
  JournalPdfBuilder({JournalLayoutPlanner? planner})
      : _planner = planner ?? const JournalLayoutPlanner();

  final JournalLayoutPlanner _planner;

  // EAST. app visual system — see lib/theme/muted_text_color.dart and the
  // black/warm-white constants already used throughout every screen.
  static const PdfColor _black = PdfColor.fromInt(0xFF040404);
  static const PdfColor _warmWhite = PdfColor.fromInt(0xFFF4F0E8);
  static const PdfColor _muted = PdfColor.fromInt(0xFFA29B8C);
  // A quieter, still highly-legible warm tone for Reflection text --
  // distinct from the wisdom's full warm-white without resorting to
  // italics. See the class doc comment on why this is a fixed blend
  // rather than relying on alpha compositing.
  static const PdfColor _reflectionTone = PdfColor.fromInt(0xFFCAC6C0);

  static const double _mm = PdfPageFormat.mm;
  static const double _bodyMarginTop = 34 * _mm;
  static const double _bodyMarginBottom = 32 * _mm;
  static const double _bodyMarginLeft = 24 * _mm;
  static const double _bodyMarginRight = 26 * _mm;
  static const double _dateColumnWidth = 26 * _mm;
  static const double _dateColumnGap = 8 * _mm;

  static const List<String> _months = [
    'JANUARY',
    'FEBRUARY',
    'MARCH',
    'APRIL',
    'MAY',
    'JUNE',
    'JULY',
    'AUGUST',
    'SEPTEMBER',
    'OCTOBER',
    'NOVEMBER',
    'DECEMBER',
  ];

  static const List<String> _shortMonths = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];

  /// A quiet, compact marginal-date treatment -- "2 JAN 2026" -- derived
  /// from [FavoriteItem.keptAt] when available (a real instant, never
  /// re-parsed from the lossy, human-formatted [FavoriteItem.date]).
  /// Falls back to the already-formatted [FavoriteItem.date] verbatim for
  /// the rare pre-Phase-9 record with no [FavoriteItem.keptAt].
  String _marginalDate(FavoriteItem item) {
    final raw = item.keptAt;
    final parsed = raw == null ? null : DateTime.tryParse(raw);
    if (parsed == null) return item.date.toUpperCase();
    final local = parsed.toLocal();
    return '${local.day} ${_shortMonths[local.month - 1]} ${local.year}';
  }

  /// Builds the full Journal PDF for [items] (any order; sorted internally
  /// oldest → newest by [FavoriteItem.keptAt], never by wisdom text) and
  /// returns the encoded bytes. [ownerName], if non-null and non-blank,
  /// appears once, on the title page only.
  ///
  /// [now] determines the "MONTH YEAR" printed on the title page — the
  /// Journal's own generation moment, never a content filter over which
  /// occurrences are included. Injectable for deterministic tests;
  /// production always uses the real current time.
  ///
  /// [compress] defaults to `true` (smaller files, appropriate for
  /// sharing/printing). Tests that need to inspect the raw PDF structure
  /// may pass `false`.
  Future<Uint8List> build({
    required List<FavoriteItem> items,
    String? ownerName,
    DateTime? now,
    bool compress = true,
  }) async {
    final generatedAt = now ?? DateTime.now();
    final fontData = await rootBundle.load(
      'assets/fonts/CormorantGaramond-Light.ttf',
    );
    final font = pw.Font.ttf(fontData);

    final document = pw.Document(
      compress: compress,
      title: 'Journal.',
      theme: pw.ThemeData.withFont(base: font, bold: font, italic: font),
    );

    document.addPage(_buildCoverPage(font));
    document.addPage(
      _buildTitlePage(font, ownerName: ownerName, generatedAt: generatedAt),
    );

    final groups = _planner.plan(items);
    if (groups.isNotEmpty) {
      document.addPage(_buildBody(font, groups));
    }

    document.addPage(_buildFinalPage(font));

    return document.save();
  }

  // ---------------------------------------------------------------------
  // Physical page 1 — cover. The EAST mark alone; nothing else. Mirrors
  // `_HomeLaunchMark` (lib/widgets/home/home_ritual_widgets.dart): a thin
  // circular ring with "EAST." centered inside it, the app's own real
  // entrance composition, recreated at book-cover scale rather than an
  // invented replacement mark.
  // ---------------------------------------------------------------------
  pw.Page _buildCoverPage(pw.Font font) {
    const diameter = 78 * _mm;

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (context) {
        return pw.Container(
          color: _black,
          width: double.infinity,
          height: double.infinity,
          alignment: const pw.FractionalOffset(0.5, 0.44),
          child: pw.Container(
            width: diameter,
            height: diameter,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              shape: pw.BoxShape.circle,
              border: pw.Border.all(color: _warmWhite, width: 0.9),
            ),
            child: pw.Text(
              'EAST.',
              style: pw.TextStyle(
                font: font,
                fontSize: 27,
                color: _warmWhite,
                letterSpacing: 0.8,
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------
  // Physical page 2 — title page. "Journal.", the generation MONTH YEAR,
  // and the optional owner name -- nothing else, no page number.
  // ---------------------------------------------------------------------
  pw.Page _buildTitlePage(
    pw.Font font, {
    required String? ownerName,
    required DateTime generatedAt,
  }) {
    final monthYear = '${_months[generatedAt.month - 1]} ${generatedAt.year}';
    final trimmedOwnerName = ownerName?.trim();

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (context) {
        return pw.Container(
          color: _black,
          width: double.infinity,
          height: double.infinity,
          alignment: const pw.FractionalOffset(0.5, 0.4),
          child: pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(
                'Journal.',
                style: pw.TextStyle(
                  font: font,
                  fontSize: 36,
                  color: _warmWhite,
                  letterSpacing: 0.6,
                ),
              ),
              pw.SizedBox(height: 26 * _mm),
              pw.Text(
                monthYear,
                style: pw.TextStyle(
                  font: font,
                  fontSize: 12.5,
                  color: _muted,
                  letterSpacing: 2.4,
                ),
              ),
              if (trimmedOwnerName != null && trimmedOwnerName.isNotEmpty) ...[
                pw.SizedBox(height: 14 * _mm),
                pw.Text(
                  trimmedOwnerName,
                  style: pw.TextStyle(
                    font: font,
                    fontSize: 14,
                    color: _reflectionTone,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------
  // Physical pages 3+ — the Journal body. One `pw.MultiPage` so the `pdf`
  // package's own layout engine places each occurrence, gracefully
  // overflowing whatever does not fit to the next page -- see
  // `JournalLayoutPlanner` for why grouping already keeps this adaptive
  // and within the 1–3-per-page ceiling without squeezing content.
  // ---------------------------------------------------------------------
  pw.Page _buildBody(pw.Font font, List<JournalPageGroup> groups) {
    return pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(
          _bodyMarginLeft,
          _bodyMarginTop,
          _bodyMarginRight,
          _bodyMarginBottom,
        ),
        theme: pw.ThemeData.withFont(base: font, bold: font, italic: font),
        // The entire PDF is dark -- every body page's own black background,
        // painted full-bleed behind the margin area too, exactly like the
        // cover/title/final pages.
        buildBackground: (context) =>
            pw.FullPage(ignoreMargins: true, child: pw.Container(color: _black)),
      ),
      maxPages: 20000,
      footer: (context) => _buildFooter(font, context),
      build: (context) {
        final widgets = <pw.Widget>[];
        for (var i = 0; i < groups.length; i++) {
          if (i > 0) widgets.add(pw.NewPage());
          widgets.addAll(_buildGroup(font, groups[i]));
        }
        return widgets;
      },
    );
  }

  List<pw.Widget> _buildGroup(pw.Font font, JournalPageGroup group) {
    if (group.isOverflowing) {
      // The rare, genuinely-too-long-for-one-page occurrence: emitted as
      // loose, independently-flowing widgets (never wrapped in one rigid
      // block) so the Reflection text itself -- a spanning widget in the
      // `pdf` layout engine -- can continue naturally onto further pages.
      // Nothing is clipped or truncated.
      return _buildEntryWidgets(font, group.entries.single, keepTogether: false);
    }

    final widgets = <pw.Widget>[];
    for (var i = 0; i < group.entries.length; i++) {
      if (i > 0) widgets.add(pw.SizedBox(height: 30));
      widgets.addAll(
        _buildEntryWidgets(font, group.entries[i], keepTogether: true),
      );
    }
    return widgets;
  }

  /// One occurrence: a quiet marginal date beside the wisdom, then (if
  /// present) its Reflection, visually distinguished from the wisdom by
  /// scale/tone/spacing alone -- no "Wisdom"/"Reflection" label anywhere.
  /// When [keepTogether] is true, the whole entry is one non-splitting
  /// unit (the ordinary case); when false, only the date+wisdom stay
  /// paired and the Reflection is free to flow across a page boundary.
  List<pw.Widget> _buildEntryWidgets(
    pw.Font font,
    FavoriteItem item, {
    required bool keepTogether,
  }) {
    final header = pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: _dateColumnWidth,
          child: pw.Text(
            _marginalDate(item),
            style: pw.TextStyle(
              font: font,
              fontSize: 8,
              color: _muted,
              letterSpacing: 0.7,
              height: 1.3,
            ),
          ),
        ),
        pw.SizedBox(width: _dateColumnGap),
        pw.Expanded(
          child: pw.Text(
            item.text,
            style: pw.TextStyle(
              font: font,
              fontSize: 15,
              color: _warmWhite,
              letterSpacing: 0.3,
              height: 1.5,
            ),
          ),
        ),
      ],
    );

    final reflection = item.reflection;
    final hasReflection = reflection != null && reflection.trim().isNotEmpty;

    if (!hasReflection) {
      return [keepTogether ? pw.Column(children: [header]) : header];
    }

    final reflectionStyle = pw.TextStyle(
      font: font,
      fontSize: 10.5,
      color: _reflectionTone,
      letterSpacing: 0.25,
      height: 1.48,
    );

    if (!keepTogether) {
      // The rare oversized-entry path: `pw.Text` only actually flows across
      // page boundaries when `overflow: TextOverflow.span` is set (its
      // `canSpan` getter is literally `overflow == TextOverflow.span` --
      // otherwise `MultiPage` throws rather than split it) *and* it is a
      // *direct* item in `MultiPage`'s widget list -- wrapping it in
      // `Padding`/`Container` (as the ordinary indented case below does)
      // hides that capability from the layout engine entirely. This is why
      // the exceptional case's Reflection starts flush at the body margin
      // rather than indented under the date column: never clipped or
      // truncated is the requirement that matters here, not pixel-perfect
      // indentation.
      return [
        header,
        pw.SizedBox(height: 16),
        pw.Text(
          reflection,
          style: reflectionStyle,
          overflow: pw.TextOverflow.span,
        ),
      ];
    }

    return [
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          header,
          pw.Padding(
            padding: const pw.EdgeInsets.only(
              top: 16,
              left: _dateColumnWidth + _dateColumnGap,
            ),
            child: pw.Text(reflection, style: reflectionStyle),
          ),
        ],
      ),
    ];
  }

  pw.Widget _buildFooter(pw.Font font, pw.Context context) {
    // `context.pageNumber` is 1-indexed across the *entire* `pw.Document`
    // (cover + title page + this body) -- see the class doc comment on
    // `JournalPdfBuilder.build` for why physical pages 1–2 always precede
    // this MultiPage, making the offset exactly 2 for every printed body
    // page number.
    final printedPageNumber = context.pageNumber - 2;
    if (printedPageNumber < 1) return pw.SizedBox();

    return pw.Container(
      alignment: pw.Alignment.center,
      margin: const pw.EdgeInsets.only(top: 12),
      child: pw.Text(
        '$printedPageNumber',
        style: pw.TextStyle(
          font: font,
          fontSize: 8,
          color: _muted,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Final closing page — black, almost empty, never counted in body
  // numbering (it is a plain `pw.Page`, outside the body `MultiPage`, so
  // it has no footer at all).
  // ---------------------------------------------------------------------
  pw.Page _buildFinalPage(pw.Font font) {
    const diameter = 40 * _mm;

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (context) {
        return pw.Container(
          color: _black,
          width: double.infinity,
          height: double.infinity,
          alignment: pw.Alignment.center,
          child: pw.Container(
            width: diameter,
            height: diameter,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              shape: pw.BoxShape.circle,
              border: pw.Border.all(color: _warmWhite, width: 0.7),
            ),
            child: pw.Text(
              'EAST.',
              style: pw.TextStyle(
                font: font,
                fontSize: 14,
                color: _warmWhite,
                letterSpacing: 0.6,
              ),
            ),
          ),
        );
      },
    );
  }
}
