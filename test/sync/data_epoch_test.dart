// Build 26 Phase 4A: DataEpoch value type and validation. See
// docs/architecture/EAST_CLOUDKIT_SYNC_V1.md §4.1.
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/sync/data_epoch.dart';

void main() {
  test('1. generate() produces a valid, parseable epoch', () {
    final epoch = DataEpoch.generate();
    expect(DataEpoch.isValid(epoch.value), isTrue);
  });

  test('2. generate() produces different values on each call', () {
    final first = DataEpoch.generate();
    final second = DataEpoch.generate();
    expect(first, isNot(second));
  });

  test('3. parse() round-trips an already-known value', () {
    final generated = DataEpoch.generate();
    final parsed = DataEpoch.parse(generated.value);
    expect(parsed, generated);
  });

  test('4. parse() rejects a malformed string', () {
    expect(
        () => DataEpoch.parse('not-a-uuid'), throwsA(isA<FormatException>()));
  });

  test(
      '5. parse() rejects a v5 UUID (an epoch is always v4, never a '
      'deterministic content derivation)', () {
    const v5 = 'affbc527-29c4-5d19-b678-1bc7f9dfb7d4';
    expect(() => DataEpoch.parse(v5), throwsA(isA<FormatException>()));
  });

  test('6. isValid mirrors parse() without throwing', () {
    expect(DataEpoch.isValid('not-a-uuid'), isFalse);
    expect(DataEpoch.isValid(DataEpoch.generate().value), isTrue);
  });

  test('7. equality is value-based', () {
    final a = DataEpoch.parse('11111111-1111-4111-8111-111111111111');
    final b = DataEpoch.parse('11111111-1111-4111-8111-111111111111');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });

  test('8. two different epochs are never equal', () {
    final a = DataEpoch.parse('11111111-1111-4111-8111-111111111111');
    final b = DataEpoch.parse('22222222-2222-4222-8222-222222222222');
    expect(a, isNot(b));
  });
}
