import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/services/journal_layout.dart';

void main() {
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

      final groups = planner.plan(items);
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

      final groups = planner.plan(items);
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

      final groups = planner.plan(items);
      final entries = groups.expand((g) => g.entries).toList();

      expect(entries, hasLength(2));
      expect(entries[0].id, 'first');
      expect(entries[1].id, 'second');
      expect(entries[0].revealId, isNot(entries[1].revealId));
    });
  });

  group('adaptive pagination', () {
    test('no group ever exceeds the configured max entries per page', () {
      const planner = JournalLayoutPlanner(
        maxEntriesPerPage: 3,
        pageContentHeightPt: 10000, // effectively unlimited height budget
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

      final groups = planner.plan(items);

      for (final group in groups) {
        expect(group.entries.length, lessThanOrEqualTo(3));
      }
      expect(groups.expand((g) => g.entries), hasLength(10));
    });

    test('short entries share a page rather than being forced one-per-page',
        () {
      const planner = JournalLayoutPlanner();
      final items = List.generate(
        3,
        (i) => item(
          id: 'id-$i',
          revealId: 'r-$i',
          text: 'A short kept line.',
          keptAt: now.subtract(Duration(days: 10 - i)),
        ),
      );

      final groups = planner.plan(items);

      expect(groups, hasLength(1));
      expect(groups.single.entries, hasLength(3));
    });

    test(
        'a genuinely oversized single entry is flagged isOverflowing and '
        'placed alone, never bundled with a neighbor', () {
      const planner = JournalLayoutPlanner(pageContentHeightPt: 400);
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

      final groups = planner.plan(items);
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
      const planner = JournalLayoutPlanner(pageContentHeightPt: 300);
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

      final groups = planner.plan(items);
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

      final first = shapeOf(planner.plan(items));
      final second = shapeOf(planner.plan(List.of(items)));

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
        planner.estimateEntryHeight(bare),
        lessThan(planner.estimateEntryHeight(reflected)),
      );
    });
  });
}
