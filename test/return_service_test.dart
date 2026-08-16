import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/services/return_service.dart';

void main() {
  late DateTime now;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    now = DateTime.utc(2026, 8, 15, 12);
  });

  ReturnService service({DateTime Function()? clock}) {
    return ReturnService(clock: clock ?? () => now);
  }

  FavoriteItem item({
    required String revealId,
    required String text,
    required DateTime keptAt,
    String? reflection,
  }) {
    return FavoriteItem(
      id: 'id-$revealId',
      revealId: revealId,
      text: text,
      date: 'display date',
      reflection: reflection,
      keptAt: keptAt.toIso8601String(),
    );
  }

  const revealA = 'a5f3c111-1111-4111-8111-000000000001';
  const revealB = 'a5f3c111-1111-4111-8111-000000000002';

  group('eligibility (14 days)', () {
    test('no Return is selected when nothing is at least 14 days old',
        () async {
      final items = [
        item(revealId: revealA, text: 'Too new', keptAt: now.subtract(const Duration(days: 13))),
      ];

      final resolved = await service().resolveCurrentReturn(items);

      expect(resolved, isNull);
    });

    test('an occurrence becomes eligible exactly at the 14-day boundary',
        () async {
      final justUnder = [
        item(
          revealId: revealA,
          text: 'Just under',
          keptAt: now.subtract(const Duration(days: 14) - const Duration(seconds: 1)),
        ),
      ];
      expect(await service().resolveCurrentReturn(justUnder), isNull);

      final exactlyAt = [
        item(
          revealId: revealA,
          text: 'Exactly 14',
          keptAt: now.subtract(const Duration(days: 14)),
        ),
      ];
      final resolved = await service().resolveCurrentReturn(exactlyAt);
      expect(resolved?.revealId, revealA);
    });
  });

  group('identity (revealId, never wisdom text)', () {
    test('selection is keyed by revealId, and duplicate wisdom text across '
        'different revealIds remains independently eligible', () async {
      const sharedText = 'The exact same wisdom text twice';
      final items = [
        item(
          revealId: revealA,
          text: sharedText,
          keptAt: now.subtract(const Duration(days: 30)),
        ),
        item(
          revealId: revealB,
          text: sharedText,
          keptAt: now.subtract(const Duration(days: 20)),
        ),
      ];

      final resolved = await service().resolveCurrentReturn(items);

      // Oldest never-returned candidate wins -- revealId A (30 days) over
      // B (20 days) -- proving selection actually distinguishes the two
      // identical-text occurrences via revealId, not text.
      expect(resolved?.revealId, revealA);
      expect(resolved?.text, sharedText);
    });
  });

  group('7-day new-selection cadence', () {
    test('a second resolve within 7 days returns the same occurrence, even '
        'when a newer eligible occurrence has since appeared', () async {
      final svc = service();
      final initialItems = [
        item(revealId: revealA, text: 'First', keptAt: now.subtract(const Duration(days: 20))),
      ];
      final first = await svc.resolveCurrentReturn(initialItems);
      expect(first?.revealId, revealA);

      now = now.add(const Duration(days: 3));
      final laterItems = [
        ...initialItems,
        item(revealId: revealB, text: 'Second, also eligible now', keptAt: now.subtract(const Duration(days: 15))),
      ];
      final second = await svc.resolveCurrentReturn(laterItems);

      expect(second?.revealId, revealA);
    });

    test('reopening repeatedly during the same window always reopens the '
        'same selected occurrence', () async {
      final svc = service();
      final items = [
        item(revealId: revealA, text: 'First', keptAt: now.subtract(const Duration(days: 20))),
        item(revealId: revealB, text: 'Second', keptAt: now.subtract(const Duration(days: 20))),
      ];
      final first = await svc.resolveCurrentReturn(items);

      for (var i = 0; i < 5; i++) {
        final again = await svc.resolveCurrentReturn(items);
        expect(again?.revealId, first?.revealId);
      }
    });

    test('rebuild/relaunch/background/resume never rerolls -- a fresh '
        'ReturnService instance backed by the same persisted store resolves '
        'to the exact same pinned occurrence', () async {
      final items = [
        item(revealId: revealA, text: 'First', keptAt: now.subtract(const Duration(days: 20))),
        item(revealId: revealB, text: 'Second', keptAt: now.subtract(const Duration(days: 20))),
      ];
      final first = await service().resolveCurrentReturn(items);

      // A brand-new instance -- simulating relaunch -- with no in-memory
      // state carried over, backed only by the same mocked SharedPreferences.
      final relaunched = service();
      final again = await relaunched.resolveCurrentReturn(items);

      expect(again?.revealId, first?.revealId);
    });

    test('a new Return may be selected once 7 days have elapsed', () async {
      final svc = service();
      final items = [
        item(revealId: revealA, text: 'First', keptAt: now.subtract(const Duration(days: 20))),
      ];
      final first = await svc.resolveCurrentReturn(items);
      expect(first?.revealId, revealA);

      now = now.add(const Duration(days: 7));
      final laterItems = [
        ...items,
        item(revealId: revealB, text: 'Second', keptAt: now.subtract(const Duration(days: 15))),
      ];
      final second = await svc.resolveCurrentReturn(laterItems);

      // B has never been returned; A already has -- A is no longer
      // preferred once a never-returned candidate exists.
      expect(second?.revealId, revealB);
    });
  });

  group('selection priority', () {
    test('never-returned eligible occurrences are preferred over '
        'previously-returned ones', () async {
      final svc = service();
      final firstRoundItems = [
        item(revealId: revealA, text: 'Already returned', keptAt: now.subtract(const Duration(days: 40))),
      ];
      final firstSelection = await svc.resolveCurrentReturn(firstRoundItems);
      expect(firstSelection?.revealId, revealA);

      now = now.add(const Duration(days: 7));
      final secondRoundItems = [
        ...firstRoundItems,
        item(revealId: revealB, text: 'Never returned', keptAt: now.subtract(const Duration(days: 14))),
      ];
      final secondSelection = await svc.resolveCurrentReturn(secondRoundItems);

      expect(secondSelection?.revealId, revealB);
    });
  });

  group('90-day repeat protection', () {
    test('the same occurrence cannot be selected again within 90 days',
        () async {
      final svc = service();
      final items = [
        item(revealId: revealA, text: 'Only candidate', keptAt: now.subtract(const Duration(days: 100))),
      ];
      final first = await svc.resolveCurrentReturn(items);
      expect(first?.revealId, revealA);

      // 7-day cadence elapsed, but A is the only eligible occurrence and it
      // was just returned -- must not be reselected this soon.
      now = now.add(const Duration(days: 7));
      final second = await svc.resolveCurrentReturn(items);
      // No valid new candidate: the previous current Return remains
      // accessible rather than manufacturing a repeat.
      expect(second?.revealId, revealA);

      now = now.add(const Duration(days: 82)); // total 89 days since first
      final third = await svc.resolveCurrentReturn(items);
      expect(third?.revealId, revealA);
    });

    test('once 90 days have passed, the same occurrence may be selected '
        'again', () async {
      final svc = service();
      final items = [
        item(revealId: revealA, text: 'Only candidate', keptAt: now.subtract(const Duration(days: 100))),
      ];
      await svc.resolveCurrentReturn(items);

      now = now.add(const Duration(days: 90));
      // A fresh instance too, to also prove the 90-day gap survives
      // relaunch, not just in-memory continuity.
      final relaunched = service();
      final resolved = await relaunched.resolveCurrentReturn(items);

      expect(resolved?.revealId, revealA);
    });

    test('if the 7-day cadence elapsed but every eligible candidate is '
        'still within its own 90-day gap, the 90-day protection is not '
        'bypassed and no repeat is manufactured', () async {
      final svc = service();
      final items = [
        item(revealId: revealA, text: 'A', keptAt: now.subtract(const Duration(days: 100))),
        item(revealId: revealB, text: 'B', keptAt: now.subtract(const Duration(days: 100))),
      ];
      final first = await svc.resolveCurrentReturn(items);
      final firstRevealId = first!.revealId;

      // Return the other one too, exhausting the never-returned pool.
      now = now.add(const Duration(days: 7));
      final second = await svc.resolveCurrentReturn(items);
      final secondRevealId = second!.revealId;
      expect({firstRevealId, secondRevealId}, {revealA, revealB});

      // Both A and B have now been returned recently; neither's 90-day gap
      // has expired, so no valid new candidate exists.
      now = now.add(const Duration(days: 7));
      final third = await svc.resolveCurrentReturn(items);

      expect(third?.revealId, secondRevealId);
    });
  });

  // Visual-polish repair: `cadenceRemaining` is a read-only presentation
  // derivation over the same persisted state -- these tests prove it never
  // influences, and is unaffected by, the selection algorithm proven above.
  group('cadenceRemaining (presentation only)', () {
    test('returns null when nothing has ever been selected', () async {
      final resolved = await service().cadenceRemaining();
      expect(resolved, isNull);
    });

    test('reports the full 7-day cadence immediately after a fresh '
        'selection', () async {
      final svc = service();
      final items = [
        item(revealId: revealA, text: 'First', keptAt: now.subtract(const Duration(days: 20))),
      ];
      await svc.resolveCurrentReturn(items);

      final remaining = await svc.cadenceRemaining();
      expect(remaining, const Duration(days: 7));
    });

    test('decreases as time passes without any resolve call', () async {
      final svc = service();
      final items = [
        item(revealId: revealA, text: 'First', keptAt: now.subtract(const Duration(days: 20))),
      ];
      await svc.resolveCurrentReturn(items);

      now = now.add(const Duration(days: 2));
      final remaining = await svc.cadenceRemaining();
      expect(remaining, const Duration(days: 5));
    });

    test('never negative -- reports Duration.zero once the cadence window '
        'has fully elapsed', () async {
      final svc = service();
      final items = [
        item(revealId: revealA, text: 'Only candidate', keptAt: now.subtract(const Duration(days: 100))),
      ];
      await svc.resolveCurrentReturn(items);

      // 7-day cadence elapsed, but no valid new candidate exists (90-day
      // repeat protection) -- `currentSelectedAt` is left in the past.
      now = now.add(const Duration(days: 7));
      await svc.resolveCurrentReturn(items);

      final remaining = await svc.cadenceRemaining();
      expect(remaining, Duration.zero);
      expect(remaining!.isNegative, isFalse);
    });

    test('never mutates or influences selection -- resolveCurrentReturn '
        'behaves identically whether or not cadenceRemaining was ever '
        'called in between', () async {
      final withoutQuery = service();
      final withQuery = service();
      final items = [
        item(revealId: revealA, text: 'First', keptAt: now.subtract(const Duration(days: 20))),
      ];

      final first = await withoutQuery.resolveCurrentReturn(items);
      final firstAgain = await withQuery.resolveCurrentReturn(items);
      await withQuery.cadenceRemaining();
      await withQuery.cadenceRemaining();

      now = now.add(const Duration(days: 3));
      final second = await withoutQuery.resolveCurrentReturn(items);
      final secondAgain = await withQuery.resolveCurrentReturn(items);

      expect(first?.revealId, firstAgain?.revealId);
      expect(second?.revealId, secondAgain?.revealId);
    });
  });

  // Return enhancement: one-year (and beyond) anniversary priority. Local
  // (non-UTC) DateTimes are used throughout this group so calendar-day
  // comparisons are never at the mercy of the test machine's timezone
  // offset relative to a fixed UTC instant.
  group('anniversary priority', () {
    test('a genuine one-year-earlier same month/day occurrence is '
        'recognized and selected as the anniversary candidate', () async {
      final svc = service();
      now = DateTime(2026, 8, 16, 12);
      final items = [
        item(
          revealId: revealA,
          text: 'Anniversary wisdom',
          keptAt: DateTime(2025, 8, 16, 9),
        ),
      ];

      final resolved = await svc.resolveCurrentReturn(items);

      expect(resolved?.revealId, revealA);
      // This occurrence also happens to be old enough for ordinary
      // rotation eligibility -- the decisive proof this went through the
      // anniversary short-circuit (never the normal path, which would
      // write a fresh 7-day cadence) is that no cadence was ever started.
      expect(await svc.cadenceRemaining(), isNull);
    });

    test('a different calendar day is not an anniversary', () async {
      now = DateTime(2026, 8, 17, 12);
      final items = [
        item(
          revealId: revealA,
          text: 'Not today, and too recent for the ordinary rule too',
          // Only 5 days old: not the anniversary's own date, and also not
          // yet eligible under the ordinary 14-day rule -- isolates this
          // test to prove the anniversary path specifically never fires
          // for a mismatched calendar day (a false positive here would
          // surface this item despite being nowhere near 14 days old).
          keptAt: DateTime(2026, 8, 12, 9),
        ),
      ];

      final resolved = await service().resolveCurrentReturn(items);

      expect(resolved, isNull);
    });

    test('an occurrence from multiple years earlier also qualifies',
        () async {
      final svc = service();
      now = DateTime(2026, 8, 16, 12);
      final items = [
        item(
          revealId: revealA,
          text: 'Many years ago',
          keptAt: DateTime(2019, 8, 16, 9),
        ),
      ];

      final resolved = await svc.resolveCurrentReturn(items);

      expect(resolved?.revealId, revealA);
      expect(await svc.cadenceRemaining(), isNull);
    });

    test('identical wisdom text across different revealIds remains '
        'independently identifiable -- only the matching revealId '
        'occurrence is selected', () async {
      now = DateTime(2026, 8, 16, 12);
      const sharedText = 'The exact same wisdom text twice';
      final items = [
        item(
          revealId: revealA,
          text: sharedText,
          // Not an anniversary today.
          keptAt: DateTime(2025, 8, 17, 9),
        ),
        item(
          revealId: revealB,
          text: sharedText,
          // Is an anniversary today.
          keptAt: DateTime(2025, 8, 16, 9),
        ),
      ];

      final resolved = await service().resolveCurrentReturn(items);

      expect(resolved?.revealId, revealB);
      expect(resolved?.text, sharedText);
    });

    test('a legacy occurrence with no trustworthy original date (no '
        'keptAt) is never guessed into an anniversary', () async {
      now = DateTime(2026, 8, 16, 12);
      final items = [
        const FavoriteItem(
          id: 'legacy-1',
          revealId: revealA,
          text: 'No keptAt at all',
          date: 'August 16, 2025',
          // keptAt intentionally omitted -- exactly the pre-Phase-9E-3
          // legacy shape.
        ),
      ];

      final resolved = await service().resolveCurrentReturn(items);

      expect(resolved, isNull);
    });

    test('anniversary priority can surface even when the normal 7-day '
        'cadence has not elapsed, and does not reset or consume that '
        'cadence', () async {
      final svc = service();
      now = DateTime(2026, 8, 10, 12);
      final rotationOnly = item(
        revealId: revealB,
        text: 'Normal rotation candidate',
        keptAt: DateTime(2026, 7, 1, 9),
      );
      final normalFirst = await svc.resolveCurrentReturn([rotationOnly]);
      expect(normalFirst?.revealId, revealB);
      final cadenceBefore = await svc.cadenceRemaining();
      expect(cadenceBefore, const Duration(days: 7));

      // Two days later -- well within the still-active 7-day cadence --
      // today is also a genuine anniversary for a different occurrence.
      now = now.add(const Duration(days: 2));
      final anniversary = item(
        revealId: revealA,
        text: 'Anniversary today',
        keptAt: DateTime(2025, 8, 12, 9),
      );
      final resolved =
          await svc.resolveCurrentReturn([rotationOnly, anniversary]);
      expect(resolved?.revealId, revealA);

      // The normal cadence must read exactly as if the anniversary had
      // never been surfaced: still counting down from the original
      // selection, unaffected by the two elapsed days, never reset.
      final cadenceAfter = await svc.cadenceRemaining();
      expect(cadenceAfter, const Duration(days: 5));
    });

    test('the existing normal current Return is preserved underneath an '
        'anniversary priority, and remains correctly available once the '
        'anniversary date passes', () async {
      final svc = service();
      now = DateTime(2026, 8, 10, 12);
      final rotationOnly = item(
        revealId: revealB,
        text: 'Normal rotation candidate',
        keptAt: DateTime(2026, 7, 1, 9),
      );
      await svc.resolveCurrentReturn([rotationOnly]);

      now = now.add(const Duration(days: 2)); // Aug 12 -- anniversary day
      final anniversary = item(
        revealId: revealA,
        text: 'Anniversary today',
        keptAt: DateTime(2025, 8, 12, 9),
      );
      final duringAnniversary =
          await svc.resolveCurrentReturn([rotationOnly, anniversary]);
      expect(duringAnniversary?.revealId, revealA);

      // The next day: no longer an anniversary for anything -- the normal
      // pinned Return (still well within its own 7-day window) is exactly
      // what reappears, completely unaffected by yesterday's priority.
      now = now.add(const Duration(days: 1));
      final afterAnniversary =
          await svc.resolveCurrentReturn([rotationOnly, anniversary]);
      expect(afterAnniversary?.revealId, revealB);
    });

    test('an anniversary occurrence already returned within the last 90 '
        'days is never forced -- normal Return behavior selects a '
        'different, never-returned occurrence instead', () async {
      final svc = service();
      now = DateTime(2026, 7, 17, 12); // 30 days before its own anniversary
      final anniversaryItem = item(
        revealId: revealA,
        text: 'Selected 30 days before its own anniversary',
        keptAt: DateTime(2025, 8, 16, 9),
      );
      final firstSelection =
          await svc.resolveCurrentReturn([anniversaryItem]);
      expect(firstSelection?.revealId, revealA);

      // 30 days later: today is genuinely revealA's anniversary, but it
      // was already returned only 30 days ago -- well inside the 90-day
      // gap. A second, never-returned occurrence is also available.
      now = DateTime(2026, 8, 16, 12);
      final freshCandidate = item(
        revealId: revealB,
        text: 'A different, never-returned occurrence',
        keptAt: DateTime(2026, 1, 1, 9),
      );
      final resolved = await svc
          .resolveCurrentReturn([anniversaryItem, freshCandidate]);

      // The anniversary is blocked by the 90-day rule -- ordinary Return
      // behavior takes over, and the fresh never-returned candidate wins,
      // proving revealA's anniversary was never forced.
      expect(resolved?.revealId, revealB);
    });

    test('multiple anniversary candidates deterministically prefer the '
        'most recent original year', () async {
      now = DateTime(2026, 8, 16, 12);
      final older = item(
        revealId: revealB,
        text: 'Two years ago',
        keptAt: DateTime(2024, 8, 16, 9),
      );
      final newer = item(
        revealId: revealA,
        text: 'One year ago',
        keptAt: DateTime(2025, 8, 16, 9),
      );

      final resolved = await service().resolveCurrentReturn([older, newer]);

      expect(resolved?.revealId, revealA);
    });

    test('reopening/rebuilding on the same anniversary day never rerolls',
        () async {
      now = DateTime(2026, 8, 16, 12);
      final items = [
        item(
          revealId: revealA,
          text: 'Anniversary today',
          keptAt: DateTime(2025, 8, 16, 9),
        ),
      ];

      final svc = service();
      final first = await svc.resolveCurrentReturn(items);
      expect(await svc.cadenceRemaining(), isNull);

      for (var i = 0; i < 4; i++) {
        final again = await svc.resolveCurrentReturn(items);
        expect(again?.revealId, first?.revealId);
      }

      // A fresh instance too -- simulating relaunch -- backed by the same
      // persisted store.
      final relaunched = service();
      final afterRelaunch = await relaunched.resolveCurrentReturn(items);
      expect(afterRelaunch?.revealId, first?.revealId);
    });

    test('a February 29 occurrence maps to February 28 in a non-leap '
        'anniversary year', () async {
      final svc = service();
      now = DateTime(2025, 2, 28, 12); // 2025 is not a leap year.
      final items = [
        item(
          revealId: revealA,
          text: 'Leap day wisdom',
          keptAt: DateTime(2024, 2, 29, 9), // 2024 is a leap year.
        ),
      ];

      final resolved = await svc.resolveCurrentReturn(items);

      expect(resolved?.revealId, revealA);
      // Proves this matched via the Feb 28 mapping specifically (the
      // anniversary short-circuit), not merely ordinary rotation eligibility
      // (this occurrence is also old enough for that).
      expect(await svc.cadenceRemaining(), isNull);
    });

    test('February 29 handling never also produces a duplicate March 1 '
        'anniversary -- the occurrence is old enough to be an ordinary '
        'eligible Return regardless, but must only ever be selected via '
        'normal rotation, never forced as an anniversary', () async {
      final svc = service();
      now = DateTime(2025, 3, 1, 12);
      final items = [
        item(
          revealId: revealA,
          text: 'Leap day wisdom',
          keptAt: DateTime(2024, 2, 29, 9),
        ),
      ];

      final resolved = await svc.resolveCurrentReturn(items);

      expect(resolved?.revealId, revealA);
      // The decisive proof: the anniversary short-circuit never writes
      // `currentSelectedAt` (see `_resolveAnniversaryPriority`), so a full
      // fresh 7-day cadence here proves this went through the NORMAL
      // rotation path -- not a (wrongly) matched March 1 anniversary.
      final cadenceRemaining = await svc.cadenceRemaining();
      expect(cadenceRemaining, const Duration(days: 7));
    });

    test('a February 29 occurrence matches exactly on February 29 again '
        'in a later leap year', () async {
      final svc = service();
      now = DateTime(2028, 2, 29, 12); // 2028 is a leap year.
      final items = [
        item(
          revealId: revealA,
          text: 'Leap day wisdom',
          keptAt: DateTime(2024, 2, 29, 9),
        ),
      ];

      final resolved = await svc.resolveCurrentReturn(items);
      expect(await svc.cadenceRemaining(), isNull);

      expect(resolved?.revealId, revealA);
    });
  });
}
