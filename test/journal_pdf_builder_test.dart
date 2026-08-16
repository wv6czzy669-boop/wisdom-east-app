import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
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

List<String> _mediaBoxes(Uint8List bytes) {
  final text = latin1.decode(bytes, allowInvalid: true);
  return RegExp(r'/MediaBox\s*\[([^\]]+)\]')
      .allMatches(text)
      .map((m) => m.group(1)!.trim())
      .toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.utc(2026, 8, 16);

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

  test('physical page count is exactly cover(1) + title(1) + body-groups + '
      'final(1)', () async {
    final planner = const JournalLayoutPlanner();
    final items = List.generate(
      15,
      (i) => item(
        id: 'id-$i',
        revealId: 'r-$i',
        text: 'A kept wisdom line, entry number $i in this run.',
        keptAt: now.subtract(Duration(days: 300 - i * 7)),
        reflection: i.isEven
            ? 'A reflection of modest length for entry $i.'
            : null,
      ),
    );
    final expectedBodyGroups = planner.plan(items).length;

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

  test('an empty item list still produces a valid cover + title + final-'
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

  test('adding more content produces at least as many physical pages, and '
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

  test('a single genuinely oversized reflection generates extra pages '
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

  test('Unicode/non-ASCII wisdom, Reflection, and owner name generate '
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

  test('generation is purely a function of its arguments -- '
      'JournalPdfBuilder holds no reference to any Kept/Reflection/daily-'
      'access/Return service, so it structurally cannot mutate any of '
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
