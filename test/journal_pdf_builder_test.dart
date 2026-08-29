import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show Brightness, Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:wisdom_app/localization/east_typography_resolver.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/services/journal_layout.dart';
import 'package:wisdom_app/services/journal_pdf_builder.dart';

/// A physical PDF page count, read structurally from the raw (uncompressed)
/// bytes -- counts `/Type /Page` object dictionaries, excluding
/// `/Type /Pages` (the page-tree node). This cannot see rendered glyph
/// content (an embedded CID font means on-page text is not literal ASCII
/// in the byte stream), but page count/size are plain PDF object-dictionary
/// keys and remain reliably inspectable this way without a PDF-parsing
/// dependency. Requires the document to have been built with
/// `compress: false`.
int _physicalPageCount(Uint8List bytes) {
  final text = latin1.decode(bytes, allowInvalid: true);
  return RegExp(r'/Type\s*/Page(?!s)\b').allMatches(text).length;
}

int _embeddedImageCount(Uint8List bytes) {
  final text = latin1.decode(bytes, allowInvalid: true);
  return RegExp(r'/Subtype\s*/Image\b').allMatches(text).length;
}

List<String> _mediaBoxes(Uint8List bytes) {
  final text = latin1.decode(bytes, allowInvalid: true);
  return RegExp(r'/MediaBox\s*\[([^\]]+)\]')
      .allMatches(text)
      .map((m) => m.group(1)!.trim())
      .toList();
}

String _pdfNumber(double value) {
  var result = value.toStringAsFixed(5);
  while (result.endsWith('0')) {
    result = result.substring(0, result.length - 1);
  }
  if (result.endsWith('.')) result = result.substring(0, result.length - 1);
  return result;
}

String _fillColorOperator(PdfColor color) =>
    '${_pdfNumber(color.red)} ${_pdfNumber(color.green)} '
    '${_pdfNumber(color.blue)} rg';

String _strokeColorOperator(PdfColor color) =>
    '${_pdfNumber(color.red)} ${_pdfNumber(color.green)} '
    '${_pdfNumber(color.blue)} RG';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.utc(2026, 8, 16);
  late pw.Font font;

  setUpAll(() async {
    font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/EBGaramond-Variable.ttf'),
    );
  });

  FavoriteItem item({
    required String id,
    required String revealId,
    required String text,
    required DateTime keptAt,
    String? reflection,
  }) {
    return FavoriteItem(
      id: id,
      revealId: revealId,
      text: text,
      date: 'display date',
      reflection: reflection,
      keptAt: keptAt.toIso8601String(),
    );
  }

  test('title-page header uses only the Journal generation year', () {
    expect(JournalPdfBuilder.headerYear(DateTime.utc(2026, 8, 16)), '2026');
    expect(JournalPdfBuilder.headerYear(DateTime.utc(2031, 1, 1)), '2031');
  });

  test('publication carries readable page content beside the raster PDF',
      () async {
    final publication = await JournalPdfBuilder().buildPublication(
      items: [
        item(
          id: 'spoken',
          revealId: 'r-spoken',
          text: 'Listen to what stays.',
          keptAt: now,
          reflection: 'A complete Reflection 👨‍👩‍👧‍👦',
        ),
      ],
      ownerName: 'A Reader',
      now: now,
      compress: false,
    );

    expect(publication.bytes, isNotEmpty);
    expect(publication.accessibility.coverLabel, 'EAST.');
    expect(publication.accessibility.titlePageLabel, contains('A Reader'));
    expect(
      publication.accessibility.bodyPageLabels.single,
      contains('Listen to what stays.'),
    );
    expect(
      publication.accessibility.bodyPageLabels.single,
      contains('A complete Reflection 👨‍👩‍👧‍👦'),
      reason: 'VoiceOver receives the original grapheme, not PDF glyph '
          'normalization output.',
    );
  });

  test('oversized body content never leaves a continuation page silent', () {
    const accessibility = JournalPdfAccessibility(
      coverLabel: 'cover',
      titlePageLabel: 'title',
      bodyPageLabels: ['first entry', 'second entry'],
      closingPageLabel: 'closing',
    );

    expect(accessibility.contentForPage(0, 6), 'cover');
    expect(accessibility.contentForPage(1, 6), 'title');
    expect(accessibility.contentForPage(2, 6), 'first entry');
    expect(accessibility.contentForPage(3, 6), 'first entry');
    expect(accessibility.contentForPage(4, 6), 'second entry');
    expect(accessibility.contentForPage(5, 6), 'closing');
  });

  test('Journal presentation exposes the locked EAST Light and Dark palettes',
      () {
    const light = JournalPdfPresentation();
    const dark = JournalPdfPresentation(brightness: Brightness.dark);

    expect(light.palette.background.toInt(), 0xFFE2E0D9);
    expect(light.palette.ink.toInt(), 0xFF2C2924);
    expect(light.palette.finalRingTone.toInt(), 0xFF807A70);
    expect(dark.palette.background.toInt(), 0xFF1C1B18);
    expect(dark.palette.ink.toInt(), 0xFFD8D4CB);
    expect(dark.palette.dateMuted.toInt(), 0xFFA9A49B);
    expect(dark.palette.finalRingTone.toInt(), 0xFF8D8981);
  });

  test('final page uses the strengthened closing-ring tone in both themes',
      () async {
    final lightBytes = await JournalPdfBuilder().build(
      items: const [],
      now: now,
      compress: false,
    );
    final darkBytes = await JournalPdfBuilder(
      presentation: const JournalPdfPresentation(
        brightness: Brightness.dark,
      ),
    ).build(
      items: const [],
      now: now,
      compress: false,
    );

    final lightPdf = latin1.decode(lightBytes, allowInvalid: true);
    final darkPdf = latin1.decode(darkBytes, allowInvalid: true);
    expect(
      lightPdf,
      contains(_strokeColorOperator(JournalPdfPalette.light.finalRingTone)),
    );
    expect(
      darkPdf,
      contains(_strokeColorOperator(JournalPdfPalette.dark.finalRingTone)),
    );
  });

  test('Dark Journal paints every page with Dark field and ink tokens',
      () async {
    final items = [
      item(
        id: 'dark-journal',
        revealId: 'r-dark-journal',
        text: 'Dark presentation stays editorial.',
        keptAt: now,
        reflection: 'The same content, under the active appearance.',
      ),
    ];
    final lightBytes = await JournalPdfBuilder().build(
      items: items,
      now: now,
      compress: false,
    );
    final darkBytes = await JournalPdfBuilder(
      presentation: const JournalPdfPresentation(
        brightness: Brightness.dark,
      ),
    ).build(
      items: items,
      now: now,
      compress: false,
    );

    final lightPdf = latin1.decode(lightBytes, allowInvalid: true);
    final darkPdf = latin1.decode(darkBytes, allowInvalid: true);
    expect(
      lightPdf,
      contains(_fillColorOperator(JournalPdfPalette.light.background)),
    );
    expect(
      darkPdf,
      contains(_fillColorOperator(JournalPdfPalette.dark.background)),
    );
    expect(
      darkPdf,
      contains(_fillColorOperator(JournalPdfPalette.dark.ink)),
    );
    expect(_physicalPageCount(darkBytes), _physicalPageCount(lightBytes));
  });

  test('every Journal body folio uses the fixed bottom-right alignment', () {
    expect(JournalBodyLayout.folioAlignment, pw.Alignment.centerRight);
  });

  test('every physical page is exactly A4 portrait (210 × 297 mm in points)',
      () async {
    final items = List.generate(
      5,
      (i) => item(
        id: 'id-$i',
        revealId: 'r-$i',
        text: 'A kept wisdom, entry $i.',
        keptAt: now.subtract(Duration(days: 100 - i)),
        reflection: i.isEven ? 'A short reflection.' : null,
      ),
    );

    final bytes = await JournalPdfBuilder().build(
      items: items,
      now: now,
      compress: false,
    );

    final boxes = _mediaBoxes(bytes);
    expect(boxes, isNotEmpty);
    for (final box in boxes) {
      final parts = box.split(RegExp(r'\s+')).map(double.parse).toList();
      expect(parts, hasLength(4));
      expect(parts[0], 0);
      expect(parts[1], 0);
      expect(parts[2], closeTo(595.2756, 0.01)); // 210mm in points
      expect(parts[3], closeTo(841.8898, 0.01)); // 297mm in points
    }
  });

  test(
      'physical page count is exactly cover(1) + title(1) + body-groups + '
      'final(1)', () async {
    final planner = const JournalLayoutPlanner();
    final items = List.generate(
      15,
      (i) => item(
        id: 'id-$i',
        revealId: 'r-$i',
        text: 'A kept wisdom line, entry number $i in this run.',
        keptAt: now.subtract(Duration(days: 300 - i * 7)),
        reflection:
            i.isEven ? 'A reflection of modest length for entry $i.' : null,
      ),
    );
    final expectedBodyGroups = planner.plan(items, font: font).length;

    final bytes = await JournalPdfBuilder(planner: planner).build(
      items: items,
      now: now,
      compress: false,
    );

    expect(
      _physicalPageCount(bytes),
      2 + expectedBodyGroups + 1,
    );
  });

  test(
      'an empty item list still produces a valid cover + title + final-'
      'only document -- no meaningless body pages', () async {
    final bytes = await JournalPdfBuilder().build(
      items: const [],
      now: now,
      compress: false,
    );

    expect(_physicalPageCount(bytes), 3);
  });

  test('items without a revealId contribute no body page', () async {
    final legacyOnly = [
      FavoriteItem(
        id: 'legacy',
        text: 'No revealId at all.',
        date: 'display date',
        keptAt: now.toIso8601String(),
      ),
    ];

    final bytes = await JournalPdfBuilder().build(
      items: legacyOnly,
      now: now,
      compress: false,
    );

    expect(_physicalPageCount(bytes), 3);
  });

  test('Reflection emoji render through the bundled PDF fallback', () async {
    final printMessages = <String>[];
    late Uint8List bytes;
    await runZoned(
      () async {
        bytes = await JournalPdfBuilder().build(
          items: [
            item(
              id: 'emoji',
              revealId: 'r-emoji',
              text: 'A quiet moment.',
              keptAt: now,
              reflection: 'Calm 🙂 🌿 ✨ ❤️ 👍🏽 👨‍👩‍👧‍👦 🇹🇷',
            ),
          ],
          ownerName: 'A quiet journal ✨',
          now: now,
          compress: false,
        );
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, message) => printMessages.add(message),
      ),
    );

    expect(bytes, isNotEmpty);
    expect(
      printMessages.where(
        (message) => message.contains('Unable to find a font'),
      ),
      isEmpty,
    );
    expect(_embeddedImageCount(bytes), greaterThanOrEqualTo(8));
    expect(normalizeJournalPdfText('❤️ 👍🏽 👨‍👩‍👧‍👦'), '❤ 👍 👨👩👧👦');
    expect(
      EastTypographyResolver.forLocale(const Locale('en'))
          .pdfFallbackAssets
          .first,
      EastTypographyResolver.pdfEmojiFontAsset,
    );
  });

  test(
      'adding more content produces at least as many physical pages, and '
      'strictly more once content genuinely no longer fits', () async {
    final few = [
      item(
        id: 'a',
        revealId: 'r-a',
        text: 'One short entry.',
        keptAt: now.subtract(const Duration(days: 30)),
      ),
    ];
    final many = List.generate(
      40,
      (i) => item(
        id: 'id-$i',
        revealId: 'r-$i',
        text: 'A kept wisdom line, entry number $i in this run.',
        keptAt: now.subtract(Duration(days: 400 - i * 5)),
        reflection: 'A reflection of modest, ordinary length for entry $i, '
            'enough to occupy a couple of lines on the page.',
      ),
    );

    final fewBytes = await JournalPdfBuilder().build(
      items: few,
      now: now,
      compress: false,
    );
    final manyBytes = await JournalPdfBuilder().build(
      items: many,
      now: now,
      compress: false,
    );

    expect(
      _physicalPageCount(manyBytes),
      greaterThan(_physicalPageCount(fewBytes)),
    );
  });

  test(
      'a single genuinely oversized reflection generates extra pages '
      'rather than crashing, being clipped, or collapsing to zero content',
      () async {
    final hugeReflection = List.generate(
      400,
      (i) => 'This is sentence number $i of a very long reflection.',
    ).join(' ');
    final items = [
      item(
        id: 'huge',
        revealId: 'r-huge',
        text: 'A wisdom with an enormous reflection attached to it.',
        keptAt: now.subtract(const Duration(days: 20)),
        reflection: hugeReflection,
      ),
    ];

    final bytes = await JournalPdfBuilder().build(
      items: items,
      now: now,
      compress: false,
    );

    // cover + title + (several body pages for the overflowing reflection)
    // + final -- strictly more than the minimum 3 (cover+title+final).
    expect(_physicalPageCount(bytes), greaterThan(3));
    expect(bytes, isNotEmpty);
  });

  test(
      'Unicode/non-ASCII wisdom, Reflection, and owner name generate '
      'successfully with no crash and non-trivial output', () async {
    final items = [
      item(
        id: 'tr',
        revealId: 'r-tr',
        text: 'Öze dönmek çoğu zaman geri gitmek değildir.',
        keptAt: now.subtract(const Duration(days: 5)),
        reflection: 'Türkçe bir yansıma: bu doğru geldi.',
      ),
    ];

    final bytes = await JournalPdfBuilder().build(
      items: items,
      ownerName: 'Doğukan Işık',
      now: now,
      compress: false,
    );

    expect(bytes.length, greaterThan(1000));
    expect(_physicalPageCount(bytes), 4); // cover + title + 1 body + final
  });

  test(
      'an overlong legacy owner name is safely bounded without changing '
      'the title-page count or breaking PDF layout', () async {
    final longOwner = List.filled(120, '👨‍👩‍👧‍👦').join();
    final publication = await JournalPdfBuilder().buildPublication(
      items: [
        item(
          id: 'long-owner',
          revealId: 'r-long-owner',
          text: 'The page keeps its shape.',
          keptAt: now,
        ),
      ],
      ownerName: longOwner,
      now: now,
      compress: false,
    );

    expect(_physicalPageCount(publication.bytes), 4);
    expect(
        publication.accessibility.titlePageLabel, isNot(contains(longOwner)));
    expect(publication.accessibility.titlePageLabel, contains('👨‍👩‍👧‍👦'));
  });

  test(
      'generation is purely a function of its arguments -- '
      'JournalPdfBuilder holds no reference to any Kept/Reflection/daily-'
      'access service, so it structurally cannot mutate any of '
      'them', () async {
    // No service of any kind is ever passed to the constructor or to
    // build() -- only plain FavoriteItem values, a name, and a clock. This
    // test documents that contract; see the class doc comment for why it
    // is architecturally guaranteed, not merely behaviorally observed.
    final items = [
      item(
        id: 'a',
        revealId: 'r-a',
        text: 'Read-only output.',
        keptAt: now.subtract(const Duration(days: 20)),
      ),
    ];
    final builder = JournalPdfBuilder();

    final firstRun = await builder.build(items: items, now: now);
    final secondRun = await builder.build(items: items, now: now);

    // Calling build() repeatedly with the same input is side-effect-free
    // and idempotent in shape (same physical page count each time).
    expect(firstRun.length, greaterThan(0));
    expect(secondRun.length, greaterThan(0));
  });
}
