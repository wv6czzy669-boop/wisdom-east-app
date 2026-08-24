import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/favorite_item.dart';

typedef JournalDateFormatter = String Function(FavoriteItem item);

/// The Journal body's single source of truth for the dimensions, typography,
/// and widgets used both to measure an entry and to paint it in the PDF.
class JournalBodyLayout {
  const JournalBodyLayout._();

  static const double marginLeft = 59.53;
  static const double marginRight = 59.53;
  static const double marginTop = 98.05;
  static const double marginBottom = 78.0;
  static const double entryGap = 46.0;
  static const double entryLineGap = 14.5;
  static const double reflectionIndent = 29.0;
  static const double dateFontSize = 12.5;
  static const double dateLetterSpacing = 3.2;
  static const double wisdomFontSize = 24.0;
  static const double reflectionFontSize = 18.5;
  static const double folioFontSize = 15.76;
  static const double folioLetterSpacing = 3.78;
  static const double folioTopGap = 14;

  static const PdfColor dateMuted = PdfColor.fromInt(0xFF625D54);
  static const PdfColor ink = PdfColor.fromInt(0xFF2C2924);
  static const PdfColor reflectionTone = PdfColor.fromInt(0xFF625D54);
  static const PdfColor folioTone = PdfColor.fromInt(0xFFB5AFA4);

  static const pw.Alignment folioAlignment = pw.Alignment.centerRight;

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

  static double get contentWidth =>
      PdfPageFormat.a4.width - marginLeft - marginRight;

  static String marginalDate(FavoriteItem item) {
    final raw = item.keptAt;
    final parsed = raw == null ? null : DateTime.tryParse(raw);
    if (parsed == null) return item.date.toUpperCase();
    final local = parsed.toLocal();
    return '${local.day} ${_shortMonths[local.month - 1]} ${local.year}';
  }

  /// The ordinary inseparable occurrence block. This exact widget is also
  /// measured by [JournalLayoutPlanner], so pagination follows real PDF
  /// wrapping rather than a text-length estimate.
  static pw.Widget buildEntry(
    pw.Font font,
    FavoriteItem item, {
    List<pw.Font> fontFallback = const <pw.Font>[],
    pw.TextDirection textDirection = pw.TextDirection.ltr,
    JournalDateFormatter? dateFormatter,
    PdfColor dateColor = dateMuted,
    PdfColor wisdomColor = ink,
    PdfColor reflectionColor = reflectionTone,
  }) {
    final header = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          dateFormatter?.call(item) ?? marginalDate(item),
          textDirection: textDirection,
          style: pw.TextStyle(
            font: font,
            fontFallback: fontFallback,
            fontSize: dateFontSize,
            color: dateColor,
            letterSpacing: dateLetterSpacing,
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: entryLineGap),
          child: pw.Text(
            item.text,
            textDirection: textDirection,
            style: pw.TextStyle(
              font: font,
              fontFallback: fontFallback,
              fontSize: wisdomFontSize,
              color: wisdomColor,
              height: 1.5,
            ),
          ),
        ),
      ],
    );

    final reflection = item.reflection;
    if (reflection == null || reflection.trim().isEmpty) {
      return pw.Column(children: [header]);
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        header,
        pw.Padding(
          padding: const pw.EdgeInsetsDirectional.only(
            top: entryLineGap,
            start: reflectionIndent,
          ),
          child: pw.Text(
            reflection,
            textDirection: textDirection,
            style: pw.TextStyle(
              font: font,
              fontFallback: fontFallback,
              fontSize: reflectionFontSize,
              color: reflectionColor,
              height: 1.55,
            ),
          ),
        ),
      ],
    );
  }

  /// The safe exceptional rendering path for an entry taller than a normal
  /// body page. The date and wisdom stay paired; the reflection can span
  /// following pages rather than clipping or being discarded.
  static List<pw.Widget> buildOverflowingEntry(
    pw.Font font,
    FavoriteItem item, {
    List<pw.Font> fontFallback = const <pw.Font>[],
    pw.TextDirection textDirection = pw.TextDirection.ltr,
    JournalDateFormatter? dateFormatter,
    PdfColor dateColor = dateMuted,
    PdfColor wisdomColor = ink,
    PdfColor reflectionColor = reflectionTone,
  }) {
    final header = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          dateFormatter?.call(item) ?? marginalDate(item),
          textDirection: textDirection,
          style: pw.TextStyle(
            font: font,
            fontFallback: fontFallback,
            fontSize: dateFontSize,
            color: dateColor,
            letterSpacing: dateLetterSpacing,
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: entryLineGap),
          child: pw.Text(
            item.text,
            textDirection: textDirection,
            style: pw.TextStyle(
              font: font,
              fontFallback: fontFallback,
              fontSize: wisdomFontSize,
              color: wisdomColor,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
    final reflection = item.reflection;
    if (reflection == null || reflection.trim().isEmpty) return [header];

    return [
      header,
      pw.SizedBox(height: entryLineGap),
      pw.Text(
        reflection,
        textDirection: textDirection,
        style: pw.TextStyle(
          font: font,
          fontFallback: fontFallback,
          fontSize: reflectionFontSize,
          color: reflectionColor,
          height: 1.55,
        ),
        overflow: pw.TextOverflow.span,
      ),
    ];
  }

  static pw.Widget buildFolio(
    pw.Font font,
    int pageNumber, {
    PdfColor color = folioTone,
  }) {
    return pw.Container(
      alignment: folioAlignment,
      margin: const pw.EdgeInsets.only(top: folioTopGap),
      child: pw.Text(
        '$pageNumber',
        style: pw.TextStyle(
          font: font,
          fontSize: folioFontSize,
          color: color,
          letterSpacing: folioLetterSpacing,
        ),
      ),
    );
  }
}

/// Plans Journal body pages from actual PDF layout measurements.
class JournalLayoutPlanner {
  const JournalLayoutPlanner({
    this.pageContentHeightOverridePt,
  });

  /// Test-only deterministic override. Production always uses the measured
  /// A4 body area, including reserved footer space.
  final double? pageContentHeightOverridePt;

  List<JournalPageGroup> plan(
    List<FavoriteItem> items, {
    required pw.Font font,
    List<pw.Font> fontFallback = const <pw.Font>[],
    pw.TextDirection textDirection = pw.TextDirection.ltr,
    JournalDateFormatter? dateFormatter,
  }) {
    final context = _measurementContext(font, fontFallback, textDirection);
    final availableHeight =
        pageContentHeightOverridePt ?? _availableContentHeight(context, font);
    final ordered = _orderedOldestFirst(items);
    final groups = <JournalPageGroup>[];

    var index = 0;
    while (index < ordered.length) {
      final item = ordered[index];
      final height = _measureEntry(
        item,
        font: font,
        fontFallback: fontFallback,
        textDirection: textDirection,
        dateFormatter: dateFormatter,
        context: context,
      );

      if (height > availableHeight) {
        groups.add(JournalPageGroup(entries: [item], isOverflowing: true));
        index += 1;
        continue;
      }

      final entries = <FavoriteItem>[item];
      var usedHeight = height;
      index += 1;

      while (index < ordered.length) {
        final next = ordered[index];
        final nextHeight = _measureEntry(
          next,
          font: font,
          fontFallback: fontFallback,
          textDirection: textDirection,
          dateFormatter: dateFormatter,
          context: context,
        );
        if (nextHeight > availableHeight ||
            usedHeight + JournalBodyLayout.entryGap + nextHeight >
                availableHeight) {
          break;
        }
        entries.add(next);
        usedHeight += JournalBodyLayout.entryGap + nextHeight;
        index += 1;
      }

      groups.add(JournalPageGroup(entries: entries));
    }
    return groups;
  }

  double measureEntry(
    FavoriteItem item, {
    required pw.Font font,
    List<pw.Font> fontFallback = const <pw.Font>[],
    pw.TextDirection textDirection = pw.TextDirection.ltr,
  }) {
    final context = _measurementContext(font, fontFallback, textDirection);
    return _measureEntry(
      item,
      font: font,
      fontFallback: fontFallback,
      textDirection: textDirection,
      context: context,
    );
  }

  pw.Context _measurementContext(
    pw.Font font,
    List<pw.Font> fontFallback,
    pw.TextDirection textDirection,
  ) {
    return pw.Context(document: PdfDocument()).inheritFromAll(<pw.Inherited>[
      pw.ThemeData.withFont(
        base: font,
        bold: font,
        italic: font,
        fontFallback: fontFallback,
      ),
      pw.InheritedDirectionality(textDirection),
    ]);
  }

  double _availableContentHeight(pw.Context context, pw.Font font) {
    final footerHeight = pw.Widget.measure(
      JournalBodyLayout.buildFolio(font, 1),
      context: context,
      constraints: pw.BoxConstraints(maxWidth: JournalBodyLayout.contentWidth),
    ).y;
    return PdfPageFormat.a4.height -
        JournalBodyLayout.marginTop -
        JournalBodyLayout.marginBottom -
        footerHeight;
  }

  double _measureEntry(
    FavoriteItem item, {
    required pw.Font font,
    required List<pw.Font> fontFallback,
    required pw.TextDirection textDirection,
    JournalDateFormatter? dateFormatter,
    required pw.Context context,
  }) {
    return pw.Widget.measure(
      JournalBodyLayout.buildEntry(
        font,
        item,
        fontFallback: fontFallback,
        textDirection: textDirection,
        dateFormatter: dateFormatter,
      ),
      context: context,
      constraints: pw.BoxConstraints(maxWidth: JournalBodyLayout.contentWidth),
    ).y;
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
        return aKeptAt == null ? -1 : 1;
      }
      final byOriginalOrder = a.key.compareTo(b.key);
      return byOriginalOrder != 0
          ? byOriginalOrder
          : a.value.revealId!.compareTo(b.value.revealId!);
    });
    return withRevealId.map((entry) => entry.value).toList(growable: false);
  }

  DateTime? _parseKeptAt(FavoriteItem item) {
    final raw = item.keptAt;
    return raw == null ? null : DateTime.tryParse(raw);
  }
}

class JournalPageGroup {
  const JournalPageGroup({
    required this.entries,
    this.isOverflowing = false,
  });

  final List<FavoriteItem> entries;
  final bool isOverflowing;
}
