import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/utils/countdown_formatter.dart';

void main() {
  group('CountdownFormatter.resolve -- microsecond-precision ceiling', () {
    test('zero and negative durations resolve to 00:00', () {
      expect(CountdownFormatter.resolve(Duration.zero).hhmm, '00:00');
      expect(
        CountdownFormatter.resolve(const Duration(seconds: -1)).hhmm,
        '00:00',
      );
      expect(
        CountdownFormatter.resolve(const Duration(hours: -1)).hhmm,
        '00:00',
      );
    });

    test('1 microsecond ceils to 00:01', () {
      final duration =
          CountdownFormatter.resolve(const Duration(microseconds: 1));
      expect(duration.hours, 0);
      expect(duration.minutes, 1);
      expect(duration.hhmm, '00:01');
    });

    test('999 milliseconds ceils to 00:01', () {
      expect(
        CountdownFormatter.resolve(const Duration(milliseconds: 999)).hhmm,
        '00:01',
      );
    });

    test('exactly 1 minute (no ceiling needed) resolves to 00:01', () {
      expect(
        CountdownFormatter.resolve(const Duration(minutes: 1)).hhmm,
        '00:01',
      );
    });

    test('1 minute + 1 microsecond ceils to 00:02', () {
      expect(
        CountdownFormatter.resolve(
          const Duration(minutes: 1, microseconds: 1),
        ).hhmm,
        '00:02',
      );
    });

    test('59m30s ceils to 01:00 (the historical 60-minute rollover bug)', () {
      final duration = CountdownFormatter.resolve(
        const Duration(minutes: 59, seconds: 30),
      );
      expect(duration.hours, 1);
      expect(duration.minutes, 0);
      expect(duration.hhmm, '01:00');
    });

    test('19h04m59s ceils to 19:05', () {
      expect(
        CountdownFormatter.resolve(
          const Duration(hours: 19, minutes: 4, seconds: 59),
        ).hhmm,
        '19:05',
      );
    });

    test('19h04m00s (exact, no ceiling needed) resolves to 19:04', () {
      expect(
        CountdownFormatter.resolve(
          const Duration(hours: 19, minutes: 4),
        ).hhmm,
        '19:04',
      );
    });

    test('exactly 24h00m00s resolves to 24:00', () {
      expect(
        CountdownFormatter.resolve(const Duration(hours: 24)).hhmm,
        '24:00',
      );
    });

    test(
        'every hhmm in the supported real countdown domain (0-24h) matches '
        'the fixed HH:MM shape', () {
      for (var totalMinutes = 1; totalMinutes <= 24 * 60; totalMinutes++) {
        final duration = CountdownFormatter.resolve(
          Duration(minutes: totalMinutes),
        );
        expect(
          duration.hhmm,
          matches(RegExp(r'^\d{2}:\d{2}$')),
          reason: 'totalMinutes=$totalMinutes',
        );
      }
    });
  });

  group('CountdownPresentation', () {
    test('plainText is compatibility-only, composed from sentence + hhmm', () {
      const presentation = CountdownPresentation(
        sentence: 'Return when the silence opens again.',
        duration: CountdownDuration(hours: 19, minutes: 5),
      );
      expect(
        presentation.plainText,
        'Return when the silence opens again.\n19:05',
      );
      expect(presentation.hhmm, '19:05');
    });
  });
}
