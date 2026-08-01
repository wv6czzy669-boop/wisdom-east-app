import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/utils/favorite_date_codec.dart';

void main() {
  group('real production display-date shape ("MMMM d, yyyy")', () {
    test('1. "August 1, 2026" parses successfully', () {
      final parsed = FavoriteDateCodec.parseFavoriteDateToUtc('August 1, 2026');

      expect(parsed, DateTime.utc(2026, 8, 1, 12));
    });

    test('2. "June 20, 2026" parses successfully', () {
      final parsed = FavoriteDateCodec.parseFavoriteDateToUtc('June 20, 2026');

      expect(parsed, DateTime.utc(2026, 6, 20, 12));
    });

    test('3. "December 31, 2025" parses successfully', () {
      final parsed =
          FavoriteDateCodec.parseFavoriteDateToUtc('December 31, 2025');

      expect(parsed, DateTime.utc(2025, 12, 31, 12));
    });

    test('4. leap-day "February 29, 2028" succeeds', () {
      final parsed =
          FavoriteDateCodec.parseFavoriteDateToUtc('February 29, 2028');

      expect(parsed, DateTime.utc(2028, 2, 29, 12));
    });

    test('5. "February 29, 2027" fails (2027 is not a leap year)', () {
      expect(
        () => FavoriteDateCodec.parseFavoriteDateToUtc('February 29, 2027'),
        throwsA(isA<FavoriteDateParseException>()),
      );
    });

    test('6. "February 30, 2026" fails (no such day in any year)', () {
      expect(
        () => FavoriteDateCodec.parseFavoriteDateToUtc('February 30, 2026'),
        throwsA(isA<FavoriteDateParseException>()),
      );
    });

    test('7. an unknown month name fails', () {
      expect(
        () => FavoriteDateCodec.parseFavoriteDateToUtc('Blorptober 1, 2026'),
        throwsA(isA<FavoriteDateParseException>()),
      );
    });

    test('8. trailing arbitrary content after a valid display date fails', () {
      expect(
        () => FavoriteDateCodec.parseFavoriteDateToUtc(
          'August 1, 2026 and then some',
        ),
        throwsA(isA<FavoriteDateParseException>()),
      );
    });

    test('9. outer whitespace is accepted', () {
      final parsed =
          FavoriteDateCodec.parseFavoriteDateToUtc('   August 1, 2026   ');

      expect(parsed, DateTime.utc(2026, 8, 1, 12));
    });

    test('13. a display date maps exactly to UTC noon, not midnight', () {
      final parsed = FavoriteDateCodec.parseFavoriteDateToUtc('August 1, 2026');

      expect(parsed.hour, 12);
      expect(parsed.minute, 0);
      expect(parsed.second, 0);
      expect(parsed.isUtc, isTrue);
      expect(parsed, isNot(DateTime.utc(2026, 8, 1)));
    });

    test(
        'a one-digit day is accepted identically to the padded form '
        '("June 1, 2026")', () {
      final parsed = FavoriteDateCodec.parseFavoriteDateToUtc('June 1, 2026');

      expect(parsed, DateTime.utc(2026, 6, 1, 12));
    });
  });

  group('ISO-8601 compatibility (existing Phase 3C fixtures/data)', () {
    test('10. an explicit-Z ISO value preserves its instant', () {
      final parsed = FavoriteDateCodec.parseFavoriteDateToUtc(
        '2026-01-01T09:00:00.000Z',
      );

      expect(parsed, DateTime.utc(2026, 1, 1, 9));
      expect(parsed.isUtc, isTrue);
    });

    test('11. an explicit-offset ISO value preserves its instant', () {
      final parsed = FavoriteDateCodec.parseFavoriteDateToUtc(
        '2026-01-01T09:00:00.000+02:00',
      );

      // 09:00 at +02:00 is 07:00 UTC — the represented instant, not the
      // literal wall-clock digits, must be preserved.
      expect(parsed, DateTime.utc(2026, 1, 1, 7));
      expect(parsed.isUtc, isTrue);
    });

    test('an unparseable, non-display, non-ISO value throws', () {
      expect(
        () => FavoriteDateCodec.parseFavoriteDateToUtc('not a date at all'),
        throwsA(isA<FavoriteDateParseException>()),
      );
    });

    test('an empty value throws', () {
      expect(
        () => FavoriteDateCodec.parseFavoriteDateToUtc(''),
        throwsA(isA<FavoriteDateParseException>()),
      );
    });
  });

  group('determinism', () {
    test(
        '12. repeated parsing of the same display date produces the '
        'identical UTC DateTime', () {
      final first = FavoriteDateCodec.parseFavoriteDateToUtc('August 1, 2026');
      final second = FavoriteDateCodec.parseFavoriteDateToUtc('August 1, 2026');

      expect(first, second);
      expect(first.millisecondsSinceEpoch, second.millisecondsSinceEpoch);
    });

    test(
        '12b. repeated parsing of the same ISO value produces the '
        'identical UTC DateTime', () {
      final first = FavoriteDateCodec.parseFavoriteDateToUtc(
        '2026-01-01T09:00:00.000Z',
      );
      final second = FavoriteDateCodec.parseFavoriteDateToUtc(
        '2026-01-01T09:00:00.000Z',
      );

      expect(first, second);
    });
  });

  group('year must be exactly four digits (strictness correction)', () {
    test('1. "August 1, 2026" (four-digit year) succeeds', () {
      final parsed = FavoriteDateCodec.parseFavoriteDateToUtc('August 1, 2026');

      expect(parsed, DateTime.utc(2026, 8, 1, 12));
    });

    test('2. "August 1, 26" (two-digit year) fails', () {
      expect(
        () => FavoriteDateCodec.parseFavoriteDateToUtc('August 1, 26'),
        throwsA(isA<FavoriteDateParseException>()),
      );
    });

    test('3. "August 1, 202" (three-digit year) fails', () {
      expect(
        () => FavoriteDateCodec.parseFavoriteDateToUtc('August 1, 202'),
        throwsA(isA<FavoriteDateParseException>()),
      );
    });

    test('4. "August 1, 02026" (five-digit year) fails', () {
      expect(
        () => FavoriteDateCodec.parseFavoriteDateToUtc('August 1, 02026'),
        throwsA(isA<FavoriteDateParseException>()),
      );
    });

    test('5. "August 1, 0000" (year zero) fails', () {
      expect(
        () => FavoriteDateCodec.parseFavoriteDateToUtc('August 1, 0000'),
        throwsA(isA<FavoriteDateParseException>()),
      );
    });

    test('6. "August 1, 2026" with outer whitespace succeeds', () {
      final parsed =
          FavoriteDateCodec.parseFavoriteDateToUtc('   August 1, 2026   ');

      expect(parsed, DateTime.utc(2026, 8, 1, 12));
    });

    test('7. ISO-8601 values continue behaving exactly as before', () {
      final explicitZ = FavoriteDateCodec.parseFavoriteDateToUtc(
        '2026-01-01T09:00:00.000Z',
      );
      expect(explicitZ, DateTime.utc(2026, 1, 1, 9));

      final explicitOffset = FavoriteDateCodec.parseFavoriteDateToUtc(
        '2026-01-01T09:00:00.000+02:00',
      );
      expect(explicitOffset, DateTime.utc(2026, 1, 1, 7));
    });
  });

  group('exception content safety', () {
    test('the exception toString() never includes the original date string',
        () {
      const secretLookingValue = 'Not a real date, contains SECRET_MARKER';

      Object? caught;
      try {
        FavoriteDateCodec.parseFavoriteDateToUtc(secretLookingValue);
      } catch (error) {
        caught = error;
      }

      expect(caught, isNotNull);
      expect(caught.toString().contains('SECRET_MARKER'), isFalse);
    });
  });
}
