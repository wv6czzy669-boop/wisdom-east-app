import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/date_symbol_data_local.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/favorite_item.dart';
import '../utils/journal_pdf_text.dart';
export '../utils/journal_pdf_text.dart' show normalizeJournalPdfText;
import '../services/wisdom_localization_resolver.dart';
import '../utils/date_formatter.dart';
import '../l10n/app_localizations.dart';
import '../l10n/app_localizations_en.dart';
import '../localization/east_locale_registry.dart';
import '../localization/east_typography_resolver.dart';
import '../utils/journal_owner_name_policy.dart';
import 'journal_layout.dart';

/// Explicit future presentation input for PDF generation. It deliberately
/// carries no app state and never changes Journal pagination or source data.
class JournalPdfPresentation {
  const JournalPdfPresentation({
    this.locale = const Locale('en'),
    this.textDirection,
    this.brightness = Brightness.light,
  });

  final Locale locale;
  final TextDirection? textDirection;
  final Brightness brightness;

  JournalPdfPalette get palette => brightness == Brightness.dark
      ? JournalPdfPalette.dark
      : JournalPdfPalette.light;
}

/// PDF-native equivalents of EAST.'s Light and Dark appearance tokens.
/// Both follow the app's warm editorial field and ink hierarchy.
class JournalPdfPalette {
  const JournalPdfPalette({
    required this.background,
    required this.ink,
    required this.yearMuted,
    required this.ownerMuted,
    required this.coverRingTone,
    required this.finalRingTone,
    required this.dateMuted,
    required this.reflectionTone,
    required this.folioTone,
  });

  final PdfColor background;
  final PdfColor ink;
  final PdfColor yearMuted;
  final PdfColor ownerMuted;
  final PdfColor coverRingTone;
  final PdfColor finalRingTone;
  final PdfColor dateMuted;
  final PdfColor reflectionTone;
  final PdfColor folioTone;

  static const light = JournalPdfPalette(
    background: PdfColor.fromInt(0xFFE2E0D9),
    ink: PdfColor.fromInt(0xFF2C2924),
    yearMuted: PdfColor.fromInt(0xFF777167),
    ownerMuted: PdfColor.fromInt(0xFF807A70),
    coverRingTone: PdfColor.fromInt(0xFF9C9589),
    finalRingTone: PdfColor.fromInt(0xFF807A70),
    dateMuted: PdfColor.fromInt(0xFF625D54),
    reflectionTone: PdfColor.fromInt(0xFF625D54),
    folioTone: PdfColor.fromInt(0xFFB5AFA4),
  );

  static const dark = JournalPdfPalette(
    background: PdfColor.fromInt(0xFF1C1B18),
    ink: PdfColor.fromInt(0xFFD8D4CB),
    yearMuted: PdfColor.fromInt(0xFFA9A49B),
    ownerMuted: PdfColor.fromInt(0xFFCAC6BD),
    coverRingTone: PdfColor.fromInt(0xFF6F6B63),
    finalRingTone: PdfColor.fromInt(0xFF8D8981),
    dateMuted: PdfColor.fromInt(0xFFA9A49B),
    reflectionTone: PdfColor.fromInt(0xFFA9A49B),
    folioTone: PdfColor.fromInt(0xFF6F6B63),
  );
}

class _JournalPdfFonts {
  const _JournalPdfFonts({
    required this.primary,
    required this.brand,
    required this.fallback,
  });

  final pw.Font primary;
  final pw.Font brand;
  final List<pw.Font> fallback;
}

class _JournalYearSection {
  const _JournalYearSection({required this.year, required this.items});

  final int? year;
  final List<FavoriteItem> items;
}

/// Exact spoken representation of every physical publication page.
///
/// Preview pages are images, so their text is otherwise invisible to
/// VoiceOver. The builder records labels after each `MultiPage` has performed
/// real pagination; there is no estimated page-to-entry mapping.
class JournalPdfAccessibility {
  const JournalPdfAccessibility({
    required this.pageLabels,
  });

  final List<String> pageLabels;

  String get coverLabel => pageLabels.first;
  String get titlePageLabel => pageLabels.length > 1 ? pageLabels[1] : 'EAST.';
  List<String> get bodyPageLabels => pageLabels.length > 3
      ? pageLabels.sublist(2, pageLabels.length - 1)
      : const <String>[];
  String get closingPageLabel => pageLabels.last;

  String contentForPage(int pageIndex, int pageCount) {
    if (pageIndex < 0 || pageIndex >= pageLabels.length) return 'EAST.';
    return pageLabels[pageIndex];
  }
}

class JournalPdfPublication {
  const JournalPdfPublication({
    required this.bytes,
    required this.accessibility,
  });

  final Uint8List bytes;
  final JournalPdfAccessibility accessibility;
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
  static const _wisdomPresentation = WisdomLocalizationResolver();

  JournalPdfPalette get _palette => _presentation.palette;

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
  static const double _ownerFontSize = 24.51;
  static const double _ownerTopFraction = 243 / 481;
  static const double _ownerMaxHeight = 65;

  // ---- Final page ----
  static const double _finalRingDiameter = 70.03;
  static const double _finalRingBorder = 1.2;
  static const double _finalRingCenterYFraction = 221 / 481; // same as cover

  /// Builds the full Journal PDF for [items] (any order; sorted internally
  /// oldest → newest by [FavoriteItem.keptAt], never by wisdom text) and
  /// returns the encoded bytes. [ownerName], if non-null and non-blank,
  /// appears once, on the title page only.
  ///
  /// [now] is retained for source compatibility with existing callers. The
  /// title page is intentionally timeless; archive years come exclusively
  /// from the dated year-section pages.
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
    final publication = await buildPublication(
      items: items,
      ownerName: ownerName,
      now: now,
      compress: compress,
    );
    return publication.bytes;
  }

  /// Builds the PDF and its matching VoiceOver transcript atomically.
  Future<JournalPdfPublication> buildPublication({
    required List<FavoriteItem> items,
    String? ownerName,
    DateTime? now,
    bool compress = true,
  }) async {
    final normalizedOwnerName = JournalOwnerNamePolicy.normalize(ownerName);
    final typography = EastTypographyResolver.forLocale(_presentation.locale);
    final fonts = await _loadFonts(typography, items, normalizedOwnerName);

    // Tiny publications finish faster inline than they can cross an isolate
    // boundary. Larger archives do all expensive layout, pagination, font
    // subsetting, and encoding in a worker isolate so years of entries cannot
    // stall gestures or animation frames.
    Future<JournalPdfPublication> build() => _buildPublicationInWorker(
          items: items,
          ownerName: normalizedOwnerName,
          compress: compress,
          fonts: fonts,
        );
    if (!shouldBuildInBackground(items)) return build();
    return Isolate.run(build);
  }

  /// The cutoff is deliberately based on both entry count and text volume:
  /// one unusually long Reflection can be more expensive than many concise
  /// wisdoms. It is public only so the responsiveness contract can be locked
  /// without timing-sensitive tests.
  @visibleForTesting
  static bool shouldBuildInBackground(List<FavoriteItem> items) {
    if (items.length >= 24) return true;
    var textUnits = 0;
    for (final item in items) {
      textUnits += item.text.length;
      textUnits += item.reflection?.length ?? 0;
      for (final thought in item.reflectionHistory.thoughts) {
        textUnits += thought.text.length;
      }
      textUnits += item.date.length;
      if (textUnits >= 12000) return true;
    }
    return false;
  }

  Future<JournalPdfPublication> _buildPublicationInWorker({
    required List<FavoriteItem> items,
    required String? ownerName,
    required bool compress,
    required _JournalPdfFonts fonts,
  }) async {
    // Date symbols are isolate-local. The app initializes all product locales
    // on its root isolate, but a large Journal is deliberately laid out in a
    // worker and cannot inherit that static Intl state. Initialize only this
    // publication's locale here so background generation never falls back to
    // English month names.
    await initializeDateFormatting(localeTagForDate(_presentation.locale));
    final presentationDirection = _presentation.textDirection ??
        EastLocaleRegistry.textDirectionFor(_presentation.locale);
    final textDirection = presentationDirection == TextDirection.rtl
        ? pw.TextDirection.rtl
        : pw.TextDirection.ltr;

    final document = pw.Document(
      compress: compress,
      title: _localizations.journalPdfTitle,
      theme: pw.ThemeData.withFont(
        base: fonts.primary,
        bold: fonts.primary,
        italic: fonts.primary,
        fontFallback: fonts.fallback,
      ),
    );

    document.addPage(_buildCoverPage(fonts.brand));
    final pageLabels = <String>['EAST.'];
    document.addPage(
      _buildTitlePage(
        fonts,
        ownerName:
            ownerName == null ? null : normalizeJournalPdfText(ownerName),
        textDirection: textDirection,
      ),
    );
    pageLabels.add(
      <String>[
        _localizations.journalPdfTitle,
        if (ownerName != null) ownerName,
      ].join(' '),
    );

    final presentedItems = items
        .map(
          (item) => item.copyWith(
            text: _wisdomPresentation.resolveItem(item, _presentation.locale),
          ),
        )
        .toList(growable: false);
    final accessibleItemsByIdentity = <String, FavoriteItem>{
      for (final item in presentedItems) _accessibilityIdentity(item): item,
    };
    final localizedItems = presentedItems
        .map(
          (item) => item.copyWith(
            text: normalizeJournalPdfText(item.text),
            reflection: item.reflection == null
                ? null
                : normalizeJournalPdfText(item.reflection!),
          ),
        )
        .toList(growable: false);
    String dateFormatter(FavoriteItem item) => normalizeJournalPdfText(
          formatLocalizedDateOrLegacy(
            timestamp:
                item.keptAt == null ? null : DateTime.tryParse(item.keptAt!),
            legacyDisplay: item.date,
            localeTag: localeTagForDate(_presentation.locale),
          ),
        );
    var nextBodyFolio = 1;
    for (final section in _yearSections(localizedItems)) {
      if (section.year != null) {
        document.addPage(
          _buildYearPage(fonts, section.year!, textDirection),
        );
        pageLabels.add('${section.year}');
      }

      final groups = _planner.plan(
        section.items,
        font: fonts.primary,
        fontFallback: fonts.fallback,
        textDirection: textDirection,
        dateFormatter: dateFormatter,
      );
      for (final group in groups) {
        final pagesBefore = document.document.pdfPageList.pages.length;
        final groupLabel = group.entries
            .map(
              (entry) => _accessibleEntryLabel(
                accessibleItemsByIdentity[_accessibilityIdentity(entry)] ??
                    entry,
                dateFormatter,
              ),
            )
            .join('. ');
        document.addPage(
          _buildBody(
            fonts,
            <JournalPageGroup>[group],
            textDirection,
            dateFormatter,
            pagesBefore: pagesBefore,
            firstFolio: nextBodyFolio,
          ),
        );
        final pagesAfter = document.document.pdfPageList.pages.length;
        final generatedPages = pagesAfter - pagesBefore;
        pageLabels.addAll(List<String>.filled(generatedPages, groupLabel));
        nextBodyFolio += generatedPages;
      }
    }

    document.addPage(_buildFinalPage());
    pageLabels.add('EAST.');
    final bytes = await document.save();
    return JournalPdfPublication(
      bytes: bytes,
      accessibility: JournalPdfAccessibility(pageLabels: pageLabels),
    );
  }

  static String _accessibilityIdentity(FavoriteItem item) =>
      '${item.revealId}\u0000${item.id}';

  static String _accessibleEntryLabel(
    FavoriteItem item,
    JournalDateFormatter dateFormatter,
  ) {
    final parts = <String>[dateFormatter(item), item.text.trim()];
    final reflection = item.reflection?.trim();
    if (reflection != null && reflection.isNotEmpty) {
      if (item.reflectionHistory.thoughts.isNotEmpty &&
          item.reflectedAt != null) {
        parts.add(JournalBodyLayout.reflectionDate(
            item, item.reflectedAt!, dateFormatter));
      }
      parts.add(reflection);
    }
    for (final thought in item.reflectionHistory.thoughts) {
      parts.add(JournalBodyLayout.reflectionDate(
          item,
          DateTime.fromMillisecondsSinceEpoch(thought.createdAtMs, isUtc: true)
              .toIso8601String(),
          dateFormatter));
      parts.add(thought.text);
    }
    return parts.where((part) => part.isNotEmpty).join('. ');
  }

  List<_JournalYearSection> _yearSections(List<FavoriteItem> items) {
    final indexed = items.asMap().entries.toList(growable: false);
    indexed.sort((a, b) {
      final aDate = _keptAt(a.value);
      final bDate = _keptAt(b.value);
      if (aDate != null && bDate != null) {
        final compared = aDate.compareTo(bDate);
        if (compared != 0) return compared;
      } else if (aDate != bDate) {
        return aDate == null ? -1 : 1;
      }
      return a.key.compareTo(b.key);
    });

    final sections = <_JournalYearSection>[];
    for (final entry in indexed) {
      final year = _keptAt(entry.value)?.toLocal().year;
      if (sections.isEmpty || sections.last.year != year) {
        sections.add(_JournalYearSection(year: year, items: <FavoriteItem>[]));
      }
      sections.last.items.add(entry.value);
    }
    return sections;
  }

  DateTime? _keptAt(FavoriteItem item) {
    final raw = item.keptAt;
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<_JournalPdfFonts> _loadFonts(
    EastTypographyPlan typography,
    List<FavoriteItem> items,
    String? ownerName,
  ) async {
    final allText = StringBuffer(ownerName ?? '');
    for (final item in items) {
      allText
        ..write(item.text)
        ..write(item.reflection ?? '')
        ..write(item.date);
      for (final thought in item.reflectionHistory.thoughts) {
        allText.write(thought.text);
      }
    }
    final requiredFallbacks = _requiredPdfFallbackAssets(
      typography,
      allText.toString(),
    );
    final assets = <String>{
      typography.pdfFontAsset,
      EastTypographyResolver.latinFont.pdfAsset,
      ...requiredFallbacks,
    };
    final byAsset = <String, pw.Font>{};
    for (final asset in assets) {
      byAsset[asset] = pw.Font.ttf(await rootBundle.load(asset));
    }
    return _JournalPdfFonts(
      primary: byAsset[typography.pdfFontAsset]!,
      brand: byAsset[EastTypographyResolver.latinFont.pdfAsset]!,
      fallback: requiredFallbacks
          .map((asset) => byAsset[asset]!)
          .toList(growable: false),
    );
  }

  List<String> _requiredPdfFallbackAssets(
    EastTypographyPlan typography,
    String text,
  ) {
    final assets = <String>[];
    void add(String asset) {
      if (asset != typography.pdfFontAsset && !assets.contains(asset)) {
        assets.add(asset);
      }
    }

    for (final rune in text.runes) {
      if (_isEmojiRune(rune)) {
        add(EastTypographyResolver.pdfEmojiFontAsset);
      }
      if (_isArabicRune(rune)) {
        add(EastTypographyResolver.arabicFont.pdfAsset);
      }
      if (_isThaiRune(rune)) {
        add(EastTypographyResolver.thaiFont.pdfAsset);
      }
      if (_isHangulRune(rune)) {
        add(EastTypographyResolver.koreanFont.pdfAsset);
      }
      if (_isKanaRune(rune)) {
        add(EastTypographyResolver.japaneseFont.pdfAsset);
      }
      if (_isHanRune(rune)) {
        // Han text written by a user does not carry language metadata. Keep
        // both regional serif forms available unless one is already primary.
        add(EastTypographyResolver.traditionalChineseFont.pdfAsset);
        add(EastTypographyResolver.japaneseFont.pdfAsset);
      }
    }
    return assets;
  }

  bool _isArabicRune(int rune) =>
      (rune >= 0x0600 && rune <= 0x06FF) ||
      (rune >= 0x0750 && rune <= 0x077F) ||
      (rune >= 0x08A0 && rune <= 0x08FF);

  bool _isThaiRune(int rune) => rune >= 0x0E00 && rune <= 0x0E7F;

  bool _isHangulRune(int rune) =>
      (rune >= 0x1100 && rune <= 0x11FF) ||
      (rune >= 0x3130 && rune <= 0x318F) ||
      (rune >= 0xAC00 && rune <= 0xD7AF);

  bool _isKanaRune(int rune) =>
      (rune >= 0x3040 && rune <= 0x30FF) || (rune >= 0x31F0 && rune <= 0x31FF);

  bool _isHanRune(int rune) =>
      (rune >= 0x3400 && rune <= 0x4DBF) ||
      (rune >= 0x4E00 && rune <= 0x9FFF) ||
      (rune >= 0xF900 && rune <= 0xFAFF);

  bool _isEmojiRune(int rune) =>
      (rune >= 0x1F000 && rune <= 0x1FAFF) ||
      (rune >= 0x2600 && rune <= 0x27BF) ||
      (rune >= 0x1F1E6 && rune <= 0x1F1FF);

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
          color: _palette.background,
          width: double.infinity,
          height: double.infinity,
          alignment: pw.FractionalOffset(0.5, _coverRingCenterYFraction),
          child: pw.Container(
            width: _coverRingDiameter,
            height: _coverRingDiameter,
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(
              shape: pw.BoxShape.circle,
              border: pw.Border.all(
                color: _palette.coverRingTone,
                width: _coverRingBorder,
              ),
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
                  color: _palette.ink,
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
  // Physical page 2 — timeless title page. "Journal." and the optional
  // owner name are anchored from the top at the Design's own fractional
  // offsets (title at 38% of page height), never a loosely centered block.
  // ---------------------------------------------------------------------
  pw.Page _buildTitlePage(
    _JournalPdfFonts fonts, {
    required String? ownerName,
    required pw.TextDirection textDirection,
  }) {
    final trimmedOwnerName = ownerName?.trim();
    final pageHeight = PdfPageFormat.a4.height;

    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      textDirection: textDirection,
      build: (context) {
        return pw.Container(
          color: _palette.background,
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
                    font: fonts.primary,
                    fontFallback: fonts.fallback,
                    fontSize: _titleFontSize,
                    color: _palette.ink,
                  ),
                ),
              ),
              if (trimmedOwnerName != null && trimmedOwnerName.isNotEmpty)
                pw.Positioned(
                  top: _ownerTopFraction * pageHeight,
                  left: _titleMargin,
                  right: _titleMargin,
                  child: pw.Container(
                    height: _ownerMaxHeight,
                    alignment: pw.Alignment.topCenter,
                    child: pw.Text(
                      trimmedOwnerName,
                      textAlign: pw.TextAlign.center,
                      maxLines: 2,
                      overflow: pw.TextOverflow.clip,
                      style: pw.TextStyle(
                        font: fonts.primary,
                        fontFallback: fonts.fallback,
                        fontSize: _ownerFontSize,
                        lineSpacing: 2,
                        color: _palette.ownerMuted,
                      ),
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
  // Silent year divider. A multi-year archive gains one quiet threshold per
  // year without changing the typography or density of any content page.
  // ---------------------------------------------------------------------
  pw.Page _buildYearPage(
    _JournalPdfFonts fonts,
    int year,
    pw.TextDirection textDirection,
  ) {
    return pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      textDirection: textDirection,
      build: (context) => pw.Container(
        color: _palette.background,
        width: double.infinity,
        height: double.infinity,
        alignment: const pw.FractionalOffset(0.5, 0.46),
        child: pw.Text(
          '$year',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            font: fonts.primary,
            fontFallback: fonts.fallback,
            fontSize: _yearFontSize,
            color: _palette.yearMuted,
            letterSpacing: _yearLetterSpacing,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Physical pages 3+ — the Journal body. One `pw.MultiPage` so the `pdf`
  // package's own layout engine places each occurrence. The planner measures
  // these exact widgets first, keeping every complete entry that genuinely
  // fits on each normal page without squeezing or splitting an entry.
  // ---------------------------------------------------------------------
  pw.Page _buildBody(
    _JournalPdfFonts fonts,
    List<JournalPageGroup> groups,
    pw.TextDirection textDirection,
    JournalDateFormatter dateFormatter, {
    required int pagesBefore,
    required int firstFolio,
  }) {
    return pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(
          JournalBodyLayout.marginLeft,
          JournalBodyLayout.marginTop,
          JournalBodyLayout.marginRight,
          JournalBodyLayout.marginBottom,
        ),
        theme: pw.ThemeData.withFont(
          base: fonts.primary,
          bold: fonts.primary,
          italic: fonts.primary,
          fontFallback: fonts.fallback,
        ),
        textDirection: textDirection,
        // Every body page uses the active Journal appearance field,
        // painted full-bleed behind the margin area too, exactly like the
        // cover/title/final pages.
        buildBackground: (context) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Container(color: _palette.background),
        ),
      ),
      maxPages: 20000,
      footer: (context) => _buildFooter(
        fonts.brand,
        context,
        pagesBefore: pagesBefore,
        firstFolio: firstFolio,
      ),
      build: (context) {
        final widgets = <pw.Widget>[];
        for (var i = 0; i < groups.length; i++) {
          if (i > 0) widgets.add(pw.NewPage());
          widgets.addAll(
            _buildGroup(fonts, groups[i], textDirection, dateFormatter),
          );
        }
        return widgets;
      },
    );
  }

  List<pw.Widget> _buildGroup(
    _JournalPdfFonts fonts,
    JournalPageGroup group,
    pw.TextDirection textDirection,
    JournalDateFormatter dateFormatter,
  ) {
    if (group.isOverflowing) {
      // The rare, genuinely-too-long-for-one-page occurrence: emitted as
      // loose, independently-flowing widgets (never wrapped in one rigid
      // block) so the Reflection text itself -- a spanning widget in the
      // `pdf` layout engine -- can continue naturally onto further pages.
      // Nothing is clipped or truncated.
      return JournalBodyLayout.buildOverflowingEntry(
        fonts.primary,
        group.entries.single,
        fontFallback: fonts.fallback,
        textDirection: textDirection,
        dateFormatter: dateFormatter,
        dateColor: _palette.dateMuted,
        wisdomColor: _palette.ink,
        reflectionColor: _palette.reflectionTone,
      );
    }

    final widgets = <pw.Widget>[];
    for (var i = 0; i < group.entries.length; i++) {
      if (i > 0) widgets.add(pw.SizedBox(height: JournalBodyLayout.entryGap));
      widgets.add(
        JournalBodyLayout.buildEntry(
          fonts.primary,
          group.entries[i],
          fontFallback: fonts.fallback,
          textDirection: textDirection,
          dateFormatter: dateFormatter,
          dateColor: _palette.dateMuted,
          wisdomColor: _palette.ink,
          reflectionColor: _palette.reflectionTone,
        ),
      );
    }
    return widgets;
  }

  /// Folios remain continuous across content pages while intentionally
  /// ignoring cover, title, silent year dividers, and closing page.
  pw.Widget _buildFooter(
    pw.Font font,
    pw.Context context, {
    required int pagesBefore,
    required int firstFolio,
  }) {
    final localPageIndex = context.pageNumber - pagesBefore - 1;
    final printedPageNumber = firstFolio + localPageIndex;

    return JournalBodyLayout.buildFolio(
      font,
      printedPageNumber,
      color: _palette.folioTone,
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
          color: _palette.background,
          width: double.infinity,
          height: double.infinity,
          alignment: pw.FractionalOffset(0.5, _finalRingCenterYFraction),
          child: pw.Container(
            width: _finalRingDiameter,
            height: _finalRingDiameter,
            decoration: pw.BoxDecoration(
              shape: pw.BoxShape.circle,
              border: pw.Border.all(
                color: _palette.finalRingTone,
                width: _finalRingBorder,
              ),
            ),
          ),
        );
      },
    );
  }
}
