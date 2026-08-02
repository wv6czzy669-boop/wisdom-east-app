import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/utils/kept_timestamp_canonicalizer.dart';

void main() {
  group('canonicalizeKeptTimestamp', () {
    test(
        '1. truncates a non-zero microsecond remainder, keeping the '
        'millisecond value intact', () {
      final value = DateTime.utc(2026, 8, 2, 1, 13, 7, 484, 133);

      final result = canonicalizeKeptTimestamp(value);

      expect(result, DateTime.utc(2026, 8, 2, 1, 13, 7, 484));
      expect(result.microsecond, 0);
      expect(result.millisecond, 484);
    });

    test(
        '2. an already-canonical UTC millisecond value is unchanged '
        '(idempotent)', () {
      final value = DateTime.utc(2026, 8, 2, 1, 13, 7, 484);

      final result = canonicalizeKeptTimestamp(value);

      expect(result, value);
      expect(canonicalizeKeptTimestamp(result), result);
    });

    test(
        '3. a local (non-UTC) DateTime is converted to its true UTC '
        'instant before truncation, never silently reinterpreted', () {
      final localValue =
          DateTime(2026, 8, 2, 1, 13, 7, 484, 133); // local, not UTC.
      final expectedUtc = localValue.toUtc();
      final expectedTruncated = DateTime.fromMillisecondsSinceEpoch(
        expectedUtc.millisecondsSinceEpoch,
        isUtc: true,
      );

      final result = canonicalizeKeptTimestamp(localValue);

      expect(result, expectedTruncated);
      expect(result.isUtc, isTrue);
    });

    test('4. the result is always isUtc', () {
      expect(canonicalizeKeptTimestamp(DateTime.now()).isUtc, isTrue);
      expect(
        canonicalizeKeptTimestamp(DateTime.utc(2026, 1, 1)).isUtc,
        isTrue,
      );
    });

    test(
        '5. calling twice produces the exact same result as calling once '
        '(stable under repeated canonicalization)', () {
      final value = DateTime.now();

      final once = canonicalizeKeptTimestamp(value);
      final twice = canonicalizeKeptTimestamp(once);

      expect(twice, once);
    });

    test(
        '6. matches the exact documented equivalent expression '
        '(DateTime.fromMillisecondsSinceEpoch(value.toUtc()'
        '.millisecondsSinceEpoch, isUtc: true))', () {
      final value = DateTime.utc(2026, 3, 15, 6, 45, 30, 999, 999);

      final result = canonicalizeKeptTimestamp(value);
      final expected = DateTime.fromMillisecondsSinceEpoch(
        value.toUtc().millisecondsSinceEpoch,
        isUtc: true,
      );

      expect(result, expected);
    });
  });
}
