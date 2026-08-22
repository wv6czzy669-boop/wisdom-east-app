import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/favorite_item.dart';
import '../l10n/app_localizations.dart';
import '../l10n/app_localizations_en.dart';
import '../localization/east_locale_registry.dart';
import '../localization/east_typography_resolver.dart';
import 'journal_layout.dart';

/// Explicit future presentation input for PDF generation. It deliberately
/// carries no app state and never changes Journal pagination or source data.
class JournalPdfPresentation {
  const JournalPdfPresentation({
    this.locale = const Locale('en'),
    this.textDirection = TextDirection.ltr,
  });

  final Locale locale;
  final TextDirection textDirection;
}

/// EAST. Phase 10 — builds the on-device A4 Journal PDF.
///
/// Entirely local: no network call, no server, no upload of Kept or
/// Reflection content anywhere. Read-only over [FavoriteItem] data — never
/// mutates a Kept record, a Reflection, daily-access state, or CloudKit.
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
  JournalPdfBuilder({
    JournalLayoutPlanner? planner,
    AppLocalizations? localizations,
    JournalPdfPresentation presentation = const JournalPdfPresentation(),
  })  : _planner = planner ?? const JournalLayoutPlanner(),
        _localizations = localizations ?? AppLocalizationsEn(),
        _presentation = presentation;

  final JournalLayoutPlanner _planner;
  final AppLocalizations _localizations;
  final JournalPdfPresentation _presentation;

  /// The quiet title-page date is intentionally only the publication year.
  static String headerYear(DateTime generatedAt) => '${generatedAt.year}';

  // EAST.'s printed-page visual system, matching the Flutter surfaces.
  static const PdfColor _background = PdfColor.fromInt(0xFFE2E0D9);
  static const PdfColor _ink = PdfColor.fromInt(0xFF2C2924);

  // Design's own muted hierarchy: the title-page year and owner sit in
  // quiet secondary tiers. Body tones live in [JournalBodyLayout] so their
  // measurement and rendering cannot diverge.
  static const PdfColor _yearMuted = PdfColor.fromInt(0xFF777167);
  static const PdfColor _ownerMuted = PdfColor.fromInt(0xFF807A70);
  // The cover ring is a quiet hairline; the final ring is gentler still.
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
  static const double _yearFontSize = 17.51;
  static const double _yearLetterSpacing = 5.95;
  static const double _yearTopFraction = 243 / 481;
  static const double _ownerFontSize = 24.51;
  static const double _ownerTopFraction = 279 / 481;

  // ---- Final page ----
  static const double _finalRingDiameter = 70.03;
  static const double _finalRingBorder = 0.9;
  static const double _finalRingCenterYFraction = 221 / 481; // same as cover

  /// Builds the full Journal PDF for [items] (any order; sorted internally
  /// oldest → newest by [FavoriteItem.keptAt], never by wisdom text) and
  /// returns the encoded bytes. [ownerName], if non-null and non-blank,
  /// appears once, on the title page only.
  ///
  /// [now] determines the year printed on the title page — the
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
    final typography = EastTypographyResolver.forLocale(_presentation.locale);
    final fontAsset = typography.pdfFontAsset;
    if (fontAsset == null) {
      throw UnsupportedError(
        'No embedded ${EastLocaleRegistry.canonicalTag(_presentation.locale)} '
        'PDF font is bundled yet.',
      );
    }
    final fontData = await rootBundle.load(fontAsset);
    final font = pw.Font.ttf(fontData);

    final document = pw.Document(
      compress: compress,
      title: _localizations.journalPdfTitle,
      theme: pw.ThemeData.withFont(base: font, bold: font, italic: font),
    );

    document.addPage(_buildCoverPage(font));
    document.addPage(
      _buildTitlePage(font, ownerName: ownerName, generatedAt: generatedAt),
    );

    final groups = _planner.plan(items, font: font);
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
  // Physical page 2 — title page. "Journal.", the generation year,
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
    final year = headerYear(generatedAt);
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
                  _localizations.journalPdfTitle,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    font: font,
                    fontSize: _titleFontSize,
                    color: _ink,
                  ),
                ),
              ),
              pw.Positioned(
                top: _yearTopFraction * pageHeight,
                left: _titleMargin,
                right: _titleMargin,
                child: pw.Text(
                  year,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    font: font,
                    fontSize: _yearFontSize,
                    color: _yearMuted,
                    letterSpacing: _yearLetterSpacing,
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
  // package's own layout engine places each occurrence. The planner measures
  // these exact widgets first, keeping one to three complete entries on each
  // normal page without squeezing or splitting an entry.
  // ---------------------------------------------------------------------
  pw.Page _buildBody(pw.Font font, List<JournalPageGroup> groups) {
    return pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(
          JournalBodyLayout.marginLeft,
          JournalBodyLayout.marginTop,
          JournalBodyLayout.marginRight,
          JournalBodyLayout.marginBottom,
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
      return JournalBodyLayout.buildOverflowingEntry(
          font, group.entries.single);
    }

    final widgets = <pw.Widget>[];
    for (var i = 0; i < group.entries.length; i++) {
      if (i > 0) widgets.add(pw.SizedBox(height: JournalBodyLayout.entryGap));
      widgets.add(JournalBodyLayout.buildEntry(font, group.entries[i]));
    }
    return widgets;
  }

  /// Folios remain at the bottom-right of every Journal body page.
  /// `context.pageNumber` is 1-indexed across the
  /// *entire* `pw.Document` (cover + title page + this body) -- see the
  /// class doc comment on `JournalPdfBuilder.build` for why physical pages
  /// 1–2 always precede this MultiPage, making the offset exactly 2 for
  /// every printed body page number.
  pw.Widget _buildFooter(pw.Font font, pw.Context context) {
    final printedPageNumber = context.pageNumber - 2;
    if (printedPageNumber < 1) return pw.SizedBox();

    return JournalBodyLayout.buildFolio(font, printedPageNumber);
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
