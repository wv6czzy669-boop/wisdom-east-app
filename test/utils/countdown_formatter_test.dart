import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/utils/countdown_formatter.dart';

void main() {
  test('seconds, minute/hour boundaries, and expiry remain unambiguous', () {
    final cases = <Duration, String>{
      Duration.zero: '00:00:00',
      const Duration(seconds: -1): '00:00:00',
      const Duration(microseconds: 1): '00:00:01',
      const Duration(milliseconds: 999): '00:00:01',
      const Duration(seconds: 59): '00:00:59',
      const Duration(minutes: 1): '00:01:00',
      const Duration(minutes: 1, microseconds: 1): '00:01:01',
      const Duration(minutes: 59, seconds: 59): '00:59:59',
      const Duration(hours: 1): '01:00:00',
      const Duration(hours: 23, minutes: 59, seconds: 20): '23:59:20',
      const Duration(hours: 24): '24:00:00',
    };
    for (final entry in cases.entries) {
      expect(CountdownFormatter.resolve(entry.key).hhmmss, entry.value);
    }
  });
  test('every second within a daily lock formats without a 60-second overflow',
      () {
    for (var seconds = 0; seconds <= 86400; seconds++) {
      final d = CountdownFormatter.resolve(Duration(seconds: seconds));
      expect(d.hhmmss, matches(RegExp(r'^\d{2}:\d{2}:\d{2}$')));
      expect(d.minutes, inInclusiveRange(0, 59));
      expect(d.seconds, inInclusiveRange(0, 59));
      expect(d.hours * 3600 + d.minutes * 60 + d.seconds, seconds);
    }
  });
  test('presentation uses the same seconds for the plain text', () {
    const p = CountdownPresentation(
        sentence: 'Return.',
        duration: CountdownDuration(hours: 23, minutes: 59, seconds: 20));
    expect(p.plainText, 'Return.\n23:59:20');
  });
}
