import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/services/journal_layout.dart';

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

  test('body uses the compact EAST editorial hierarchy', () {
    expect(JournalBodyLayout.marginLeft, 59.53);
    expect(JournalBodyLayout.marginRight, 59.53);
    expect(JournalBodyLayout.entryGap, 46.0);
    expect(JournalBodyLayout.entryLineGap, 14.5);
    expect(JournalBodyLayout.reflectionIndent, 29.0);
    expect(JournalBodyLayout.dateFontSize, 12.5);
    expect(JournalBodyLayout.dateLetterSpacing, 3.2);
    expect(JournalBodyLayout.wisdomFontSize, 24.0);
    expect(JournalBodyLayout.reflectionFontSize, 18.5);
    expect(
      JournalBodyLayout.dateFontSize,
      lessThan(JournalBodyLayout.reflectionFontSize),
    );
    expect(
      JournalBodyLayout.reflectionFontSize,
      lessThan(JournalBodyLayout.wisdomFontSize),
    );
    expect(JournalBodyLayout.reflectionTone.toInt(), 0xFF625D54);
  });

  group('ordering', () {
    test('orders oldest to newest by keptAt, never by wisdom text', () {
      const planner = JournalLayoutPlanner();
      final items = [
        item(
          id: 'z',
          revealId: 'r-z',
          text: 'zzz newest text',
          keptAt: now.subtract(const Duration(days: 1)),
        ),
        item(
          id: 'a',
          revealId: 'r-a',
          text: 'aaa oldest text',
          keptAt: now.subtract(const Duration(days: 30)),
        ),
        item(
          id: 'm',
          revealId: 'r-m',
          text: 'mmm middle text',
          keptAt: now.subtract(const Duration(days: 15)),
        ),
      ];

      final groups = planner.plan(items, font: font);
      final ordered = groups.expand((g) => g.entries).map((e) => e.id).toList();

      expect(ordered, ['a', 'm', 'z']);
    });

    test('items without a revealId are excluded entirely', () {
      const planner = JournalLayoutPlanner();
      final items = [
        item(
          id: 'has-reveal',
          revealId: 'r-1',
          text: 'Included',
          keptAt: now.subtract(const Duration(days: 5)),
        ),
        FavoriteItem(
          id: 'no-reveal',
          text: 'Excluded (legacy, no revealId)',
          date: 'display date',
          keptAt: now.subtract(const Duration(days: 5)).toIso8601String(),
        ),
      ];

      final groups = planner.plan(items, font: font);
      final ids = groups.expand((g) => g.entries).map((e) => e.id).toList();

      expect(ids, ['has-reveal']);
    });

    test(
        'duplicate wisdom text with distinct revealIds both remain, '
        'ordered independently by their own keptAt', () {
      const planner = JournalLayoutPlanner();
      const sharedText = 'The exact same wisdom, twice.';
      final items = [
        item(
          id: 'first',
          revealId: 'r-first',
          text: sharedText,
          keptAt: now.subtract(const Duration(days: 40)),
        ),
        item(
          id: 'second',
          revealId: 'r-second',
          text: sharedText,
          keptAt: now.subtract(const Duration(days: 10)),
        ),
      ];

      final groups = planner.plan(items, font: font);
      final entries = groups.expand((g) => g.entries).toList();

      expect(entries, hasLength(2));
      expect(entries[0].id, 'first');
      expect(entries[1].id, 'second');
      expect(entries[0].revealId, isNot(entries[1].revealId));
    });
  });

  group('adaptive pagination', () {
    test('entry count has no artificial cap when every measured item fits', () {
      const planner = JournalLayoutPlanner(
        pageContentHeightOverridePt: 10000,
      );
      final items = List.generate(
        10,
        (i) => item(
          id: 'id-$i',
          revealId: 'r-$i',
          text: 'Short line $i',
          keptAt: now.subtract(Duration(days: 100 - i)),
        ),
      );

      final groups = planner.plan(items, font: font);

      expect(groups, hasLength(1));
      expect(groups.single.entries, hasLength(10));
    });

    test('four short entries share a real A4 page when they fit', () {
      const planner = JournalLayoutPlanner();
      final items = List.generate(
        4,
        (i) => item(
          id: 'id-$i',
          revealId: 'r-$i',
          text: 'A short kept line.',
          keptAt: now.subtract(Duration(days: 10 - i)),
        ),
      );

      final groups = planner.plan(items, font: font);

      expect(groups, hasLength(1));
      expect(groups.single.entries, hasLength(4));
    });

    test('moves the third complete entry to the next page when it will not fit',
        () {
      const measuringPlanner = JournalLayoutPlanner();
      final items = List.generate(
        3,
        (i) => item(
          id: 'id-$i',
          revealId: 'r-$i',
          text: 'A measured editorial entry with enough text to wrap once.',
          keptAt: now.add(Duration(days: i)),
        ),
      );
      final entryHeight =
          measuringPlanner.measureEntry(items.first, font: font);
      final pageHeight =
          3 * entryHeight + 2 * JournalBodyLayout.entryGap - 0.01;
      final planner = JournalLayoutPlanner(
        pageContentHeightOverridePt: pageHeight,
      );

      final groups = planner.plan(items, font: font);

      expect(groups, hasLength(2));
      expect(groups.first.entries, hasLength(2));
      expect(groups.last.entries.map((entry) => entry.id), ['id-2']);
    });

    test(
        'keeps two long complete entries together when their rendered heights fit',
        () {
      const measuringPlanner = JournalLayoutPlanner();
      final items = List.generate(
        2,
        (i) => item(
          id: 'long-$i',
          revealId: 'r-long-$i',
          text: 'A wisdom that has a reflective companion.',
          reflection: List.filled(18, 'Measured reflection text').join(' '),
          keptAt: now.add(Duration(days: i)),
        ),
      );
      final entryHeight =
          measuringPlanner.measureEntry(items.first, font: font);
      final planner = JournalLayoutPlanner(
        pageContentHeightOverridePt:
            2 * entryHeight + JournalBodyLayout.entryGap + 0.01,
      );

      final groups = planner.plan(items, font: font);

      expect(groups, hasLength(1));
      expect(groups.single.entries, hasLength(2));
      expect(groups.single.isOverflowing, isFalse);
    });

    test('uses real glyph wrapping rather than a character-count threshold',
        () {
      const measuringPlanner = JournalLayoutPlanner();
      final narrow = item(
        id: 'narrow',
        revealId: 'r-narrow',
        text: List.filled(40, 'i').join(' '),
        keptAt: now,
      );
      final wide = item(
        id: 'wide',
        revealId: 'r-wide',
        text: List.filled(40, 'W').join(' '),
        keptAt: now.add(const Duration(days: 1)),
      );
      final narrowHeight = measuringPlanner.measureEntry(narrow, font: font);
      final wideHeight = measuringPlanner.measureEntry(wide, font: font);
      final planner = JournalLayoutPlanner(
        pageContentHeightOverridePt:
            2 * narrowHeight + JournalBodyLayout.entryGap + 0.01,
      );

      expect(wide.text.length, narrow.text.length);
      expect(wideHeight, greaterThan(narrowHeight));
      expect(planner.plan([narrow, narrow], font: font).single.entries,
          hasLength(2));
      expect(
          planner.plan([narrow, wide], font: font).first.entries, hasLength(1));
    });

    test(
        'a genuinely oversized single entry is flagged isOverflowing and '
        'placed alone, never bundled with a neighbor', () {
      const planner = JournalLayoutPlanner(pageContentHeightOverridePt: 400);
      final hugeReflection = List.filled(400, 'word').join(' ');
      final items = [
        item(
          id: 'before',
          revealId: 'r-before',
          text: 'A short entry before.',
          keptAt: now.subtract(const Duration(days: 20)),
        ),
        item(
          id: 'huge',
          revealId: 'r-huge',
          text: 'A wisdom with an enormous reflection.',
          keptAt: now.subtract(const Duration(days: 15)),
          reflection: hugeReflection,
        ),
        item(
          id: 'after',
          revealId: 'r-after',
          text: 'A short entry after.',
          keptAt: now.subtract(const Duration(days: 10)),
        ),
      ];

      final groups = planner.plan(items, font: font);
      final hugeGroup =
          groups.firstWhere((g) => g.entries.any((e) => e.id == 'huge'));

      expect(hugeGroup.entries, hasLength(1));
      expect(hugeGroup.isOverflowing, isTrue);
      // Its neighbors are not swallowed into the oversized entry's group.
      expect(
        groups
            .where((g) => !g.isOverflowing)
            .expand((g) => g.entries)
            .map((e) => e.id),
        containsAll(['before', 'after']),
      );
    });

    test(
        'every item with a revealId appears in exactly one group -- '
        'nothing is ever silently dropped, regardless of content length', () {
      const planner = JournalLayoutPlanner(pageContentHeightOverridePt: 300);
      final items = [
        for (var i = 0; i < 12; i++)
          item(
            id: 'id-$i',
            revealId: 'r-$i',
            text: 'Wisdom number $i, of moderate length for this test.',
            keptAt: now.subtract(Duration(days: 200 - i * 3)),
            reflection:
                i.isOdd ? List.filled(30 + i * 20, 'x').join(' ') : null,
          ),
      ];

      final groups = planner.plan(items, font: font);
      final ids = groups.expand((g) => g.entries).map((e) => e.id).toSet();

      expect(ids, items.map((i) => i.id).toSet());
    });

    test(
        'planning the same input twice yields identical, deterministic '
        'grouping', () {
      const planner = JournalLayoutPlanner();
      final items = List.generate(
        9,
        (i) => item(
          id: 'id-$i',
          revealId: 'r-$i',
          text: 'Entry number $i with a little more text than the last.',
          keptAt: now.subtract(Duration(days: 90 - i * 5)),
          reflection: i.isEven ? 'A reflection for entry $i.' : null,
        ),
      );

      List<List<String>> shapeOf(List<JournalPageGroup> groups) =>
          groups.map((g) => g.entries.map((e) => e.id).toList()).toList();

      final first = shapeOf(planner.plan(items, font: font));
      final second = shapeOf(planner.plan(List.of(items), font: font));

      expect(first, second);
    });

    test(
        'reflection-less entries take less estimated space than reflected '
        'ones', () {
      const planner = JournalLayoutPlanner();
      final bare = item(
        id: 'bare',
        revealId: 'r-bare',
        text: 'A short wisdom line.',
        keptAt: now,
      );
      final reflected = item(
        id: 'reflected',
        revealId: 'r-reflected',
        text: 'A short wisdom line.',
        keptAt: now,
        reflection: 'A short reflection to go with it.',
      );

      expect(
        planner.measureEntry(bare, font: font),
        lessThan(planner.measureEntry(reflected, font: font)),
      );
    });
  });
}
