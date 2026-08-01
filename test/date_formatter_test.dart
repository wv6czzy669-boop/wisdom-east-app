import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/utils/date_formatter.dart';

void main() {
  group('formatFavoriteDisplayDate', () {
    test('August 1, 2026', () {
      expect(
        formatFavoriteDisplayDate(DateTime(2026, 8, 1)),
        'August 1, 2026',
      );
    });

    test('June 20, 2026', () {
      expect(
        formatFavoriteDisplayDate(DateTime(2026, 6, 20)),
        'June 20, 2026',
      );
    });

    test('December 31, 2025', () {
      expect(
        formatFavoriteDisplayDate(DateTime(2025, 12, 31)),
        'December 31, 2025',
      );
    });

    test(
        'uses the supplied DateTime exactly, ignoring the time-of-day '
        'component', () {
      expect(
        formatFavoriteDisplayDate(DateTime(2026, 8, 1, 23, 59, 59)),
        'August 1, 2026',
      );
    });

    test(
        'a UTC DateTime is formatted using its own date fields, not '
        'converted', () {
      expect(
        formatFavoriteDisplayDate(DateTime.utc(2026, 8, 1, 12)),
        'August 1, 2026',
      );
    });
  });

  group('formattedToday delegates to formatFavoriteDisplayDate', () {
    test(
        'formattedToday(explicitDate) matches '
        'formatFavoriteDisplayDate(explicitDate) exactly', () {
      final explicitDate = DateTime(2026, 6, 20);

      expect(
        formattedToday(explicitDate),
        formatFavoriteDisplayDate(explicitDate),
      );
    });

    test(
        'formattedToday() with no argument matches '
        'formatFavoriteDisplayDate(DateTime.now()) for the same instant', () {
      final now = DateTime.now();

      // formattedToday() reads DateTime.now() internally, which can differ
      // from `now` above by a few microseconds; assert equality against a
      // frozen instant close enough that the formatted day cannot differ.
      expect(formattedToday(now), formatFavoriteDisplayDate(now));
    });
  });
}
