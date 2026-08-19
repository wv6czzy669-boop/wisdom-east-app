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
///
/// Visual fidelity repair: every constant below is derived from
/// "EAST Journal - Direction.dc.html" → the "The publication" section
/// (five 340×481px page figures, each a proportional preview of a real A4
/// page). Position offsets are page-relative fractions of that figure box,
/// applied to the real A4 page height/width so they hold regardless of the
/// figure's own display scale; literal sizes (font size, ring diameter,
/// margins, gaps, indent) are the figure's own px values scaled uniformly
/// by 595.27559/340 ≈ 1.7508 -- the ratio between the figure's width and a
/// true A4 page's width -- onto real PDF points.
class JournalPdfBuilder {
  JournalPdfBuilder({JournalLayoutPlanner? planner})
      : _planner = planner ?? const JournalLayoutPlanner();

  final JournalLayoutPlanner _planner;

  // EAST.'s printed-page visual system, matching the Flutter surfaces.
  static const PdfColor _background = PdfColor.fromInt(0xFFE2E0D9);
  static const PdfColor _ink = PdfColor.fromInt(0xFF2C2924);

  // Design's own muted hierarchy (Journal rules #10, #12): date/metadata is
  // the dimmest tier; the title page's month and owner sit in their own two
  // quiet tiers; reflection sits mid-muted beneath the wisdom's full
  // ink. Fixed tones (never alpha) keep the printed result predictable.
  static const PdfColor _dateMuted = PdfColor.fromInt(0xFF625D54);
  static const PdfColor _monthMuted = PdfColor.fromInt(0xFF777167);
  static const PdfColor _ownerMuted = PdfColor.fromInt(0xFF807A70);
  static const PdfColor _reflectionTone = PdfColor.fromInt(0xFF5D584F);
  // The cover ring is a quiet hairline; the final ring and body folio are
  // gentler still, echoing the opening mark.
  static const PdfColor _coverRingTone = PdfColor.fromInt(0xFF9C9589);
  static const PdfColor _faintTone = PdfColor.fromInt(0xFFB5AFA4);

  // ---- Cover (physical page 1) ----
  static const double _coverRingDiameter = 154.07;
  static const double _coverRingBorder = 1.2;
  static const double _coverRingCenterYFraction = 221 / 481;
  static const double _coverEastFontSize = 19.26;
  static const double _coverEastLetterSpacing = 7.32;
  // Empirically measured residual: even after the full-letterSpacing left
  // padding below, rasterizing the actual generated PDF and comparing the
  // ring's measured center against the ink bounds of "EAST." (not just its
  // theoretical layout box) showed the ink still sitting ~4pt left of ring
  // center -- real glyph advance widths (E/A/S/T/. are not uniform) aren't
  // fully captured by the Tc-only box/ink algebra alone. This constant is
  // that measured gap, applied as additional left padding.
  static const double _coverEastOpticalNudge = 8.0;

  // ---- Title page (physical page 2) ----
  static const double _titleMargin = 70.03;
  static const double _titleFontSize = 59.53;
  static const double _titleTopFraction = 183 / 481;
  static const double _monthFontSize = 17.51;
  static const double _monthLetterSpacing = 5.95;
  static const double _monthTopFraction = 243 / 481;
  static const double _ownerFontSize = 24.51;
  static const double _ownerTopFraction = 279 / 481;

  // ---- Body (physical page 3 onward) ----
  static const double _bodyMarginLeft = 70.03;
  static const double _bodyMarginRight = 70.03;
  static const double _bodyMarginTop = 98.05;
  static const double _bodyMarginBottom = 78.0;
  static const double _entryGap = 59.53;
  static const double _entryLineGap = 17.51;
  static const double _reflectionIndent = 38.52;
  static const double _dateFontSize = 14.01;
  static const double _dateLetterSpacing = 3.64;
  static const double _wisdomFontSize = 26.26;
  static const double _reflectionFontSize = 21.01;
  static const double _folioFontSize = 15.76;
  static const double _folioLetterSpacing = 3.78;

  // ---- Final page ----
  static const double _finalRingDiameter = 70.03;
  static const double _finalRingBorder = 0.9;
  static const double _finalRingCenterYFraction = 221 / 481; // same as cover

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
      'assets/fonts/EBGaramond-Variable.ttf',
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

    document.addPage(_buildFinalPage());

    return document.save();
  }

  // ---------------------------------------------------------------------
  // Physical page 1 — cover. The EAST mark alone, at the Design's own
  // ring scale and optical center (46% down the page, not dead center),
  // with a dimmed 42%-tone ring rather than a solid ink one.
  // ---------------------------------------------------------------------
  pw.Page _buildCoverPage(pw.Font font) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (context) {
        return pw.Container(
          color: _background,
          width: double.infinity,
          height: double.infinity,
          alignment: pw.FractionalOffset(0.5, _coverRingCenterYFraction),
          child: pw.Container(
            width: _coverRingDiameter,
            height: _coverRingDiameter,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              shape: pw.BoxShape.circle,
              border:
                  pw.Border.all(color: _coverRingTone, width: _coverRingBorder),
            ),
            // Optical-centering correction: the PDF character-spacing
            // operator this text's `letterSpacing` compiles to (`Tc`) adds
            // its gap *after* every glyph, including the last one -- so the
            // text's own measured layout box is one `letterSpacing` wider
            // than its visible ink, entirely on the right. Centering that
            // box (as a plain `Text` child would) therefore visibly shifts
            // the ink left of true center by exactly `letterSpacing / 2`.
            // Adding an equal amount of left padding restores symmetry:
            // provably (by the same box-vs-ink algebra), it re-centers the
            // ink exactly, regardless of ring size or font metrics -- never
            // a hand-tuned pixel offset.
            child: pw.Padding(
              padding: const pw.EdgeInsets.only(
                left: _coverEastLetterSpacing + _coverEastOpticalNudge,
              ),
              child: pw.Text(
                'EAST.',
                style: pw.TextStyle(
                  font: font,
                  fontSize: _coverEastFontSize,
                  color: _ink,
                  letterSpacing: _coverEastLetterSpacing,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------
  // Physical page 2 — title page. "Journal.", the generation MONTH YEAR,
  // and the optional owner name -- three tiers anchored from the top at
  // the Design's own fractional offsets (title at 38% of page height),
  // never a loosely centered block, so the composition holds identically
  // whether or not the owner name exists.
  // ---------------------------------------------------------------------
  pw.Page _buildTitlePage(
    pw.Font font, {
    required String? ownerName,
    required DateTime generatedAt,
  }) {
    final monthYear = '${_months[generatedAt.month - 1]} ${generatedAt.year}';
    final trimmedOwnerName = ownerName?.trim();
    final pageHeight = PdfPageFormat.a4.height;

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (context) {
        return pw.Container(
          color: _background,
          width: double.infinity,
          height: double.infinity,
          child: pw.Stack(
            children: [
              pw.Positioned(
                top: _titleTopFraction * pageHeight,
                left: _titleMargin,
                right: _titleMargin,
                child: pw.Text(
                  'Journal.',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    font: font,
                    fontSize: _titleFontSize,
                    color: _ink,
                  ),
                ),
              ),
              pw.Positioned(
                top: _monthTopFraction * pageHeight,
                left: _titleMargin,
                right: _titleMargin,
                child: pw.Text(
                  monthYear,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    font: font,
                    fontSize: _monthFontSize,
                    color: _monthMuted,
                    letterSpacing: _monthLetterSpacing,
                  ),
                ),
              ),
              if (trimmedOwnerName != null && trimmedOwnerName.isNotEmpty)
                pw.Positioned(
                  top: _ownerTopFraction * pageHeight,
                  left: _titleMargin,
                  right: _titleMargin,
                  child: pw.Text(
                    trimmedOwnerName,
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      font: font,
                      fontSize: _ownerFontSize,
                      color: _ownerMuted,
                    ),
                  ),
                ),
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
        // The entire PDF uses the warm-stone field -- every body page's own stone background,
        // painted full-bleed behind the margin area too, exactly like the
        // cover/title/final pages.
        buildBackground: (context) => pw.FullPage(
            ignoreMargins: true, child: pw.Container(color: _background)),
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
      return _buildEntryWidgets(font, group.entries.single,
          keepTogether: false);
    }

    final widgets = <pw.Widget>[];
    for (var i = 0; i < group.entries.length; i++) {
      if (i > 0) widgets.add(pw.SizedBox(height: _entryGap));
      widgets.addAll(
        _buildEntryWidgets(font, group.entries[i], keepTogether: true),
      );
    }
    return widgets;
  }

  /// One occurrence: a tracked, dimmed date on its own line, the wisdom
  /// beneath it at full ink (the Design's "primary published
  /// text"), then -- if present -- its Reflection, indented and dimmed
  /// beneath its own line. No "Wisdom"/"Reflection" label anywhere;
  /// hierarchy is entirely typographic (size/tone/indent), matching
  /// "EAST Journal - Direction.dc.html" rule #10. When [keepTogether] is
  /// true, the whole entry is one non-splitting unit (the ordinary case);
  /// when false, only the date+wisdom stay paired and the Reflection is
  /// free to flow across a page boundary.
  List<pw.Widget> _buildEntryWidgets(
    pw.Font font,
    FavoriteItem item, {
    required bool keepTogether,
  }) {
    final header = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          _marginalDate(item),
          style: pw.TextStyle(
            font: font,
            fontSize: _dateFontSize,
            color: _dateMuted,
            letterSpacing: _dateLetterSpacing,
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: _entryLineGap),
          child: pw.Text(
            item.text,
            style: pw.TextStyle(
              font: font,
              fontSize: _wisdomFontSize,
              color: _ink,
              height: 1.5,
            ),
          ),
        ),
      ],
    );

    final reflection = item.reflection;
    final hasReflection = reflection != null && reflection.trim().isNotEmpty;

    if (!hasReflection) {
      return [
        keepTogether ? pw.Column(children: [header]) : header
      ];
    }

    final reflectionStyle = pw.TextStyle(
      font: font,
      fontSize: _reflectionFontSize,
      color: _reflectionTone,
      height: 1.6,
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
      // rather than indented -- never clipped or truncated is the
      // requirement that matters here, not pixel-perfect indentation.
      return [
        header,
        pw.SizedBox(height: _entryLineGap),
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
              top: _entryLineGap,
              left: _reflectionIndent,
            ),
            child: pw.Text(reflection, style: reflectionStyle),
          ),
        ],
      ),
    ];
  }

  /// Folios alternate to the outer edge -- odd printed pages (recto) on the
  /// right margin, even printed pages (verso) on the left -- exactly as
  /// "EAST Journal - Direction.dc.html" specifies, so a printed spread
  /// breathes correctly. `context.pageNumber` is 1-indexed across the
  /// *entire* `pw.Document` (cover + title page + this body) -- see the
  /// class doc comment on `JournalPdfBuilder.build` for why physical pages
  /// 1–2 always precede this MultiPage, making the offset exactly 2 for
  /// every printed body page number.
  pw.Widget _buildFooter(pw.Font font, pw.Context context) {
    final printedPageNumber = context.pageNumber - 2;
    if (printedPageNumber < 1) return pw.SizedBox();

    return pw.Container(
      alignment: printedPageNumber.isOdd
          ? pw.Alignment.centerRight
          : pw.Alignment.centerLeft,
      margin: const pw.EdgeInsets.only(top: 14),
      child: pw.Text(
        '$printedPageNumber',
        style: pw.TextStyle(
          font: font,
          fontSize: _folioFontSize,
          color: _faintTone,
          letterSpacing: _folioLetterSpacing,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Final closing page — the ring alone, at the Design's reduced scale,
  // same optical center as the cover, no wordmark, no number, no
  // colophon. Never counted in body numbering (it is a plain `pw.Page`,
  // outside the body `MultiPage`, so it has no footer at all).
  // ---------------------------------------------------------------------
  pw.Page _buildFinalPage() {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (context) {
        return pw.Container(
          color: _background,
          width: double.infinity,
          height: double.infinity,
          alignment: pw.FractionalOffset(0.5, _finalRingCenterYFraction),
          child: pw.Container(
            width: _finalRingDiameter,
            height: _finalRingDiameter,
            decoration: pw.BoxDecoration(
              shape: pw.BoxShape.circle,
              border: pw.Border.all(color: _faintTone, width: _finalRingBorder),
            ),
          ),
        );
      },
    );
  }
}
