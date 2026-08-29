import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/utils/reflection_text_policy.dart';

void main() {
  test('uses the 1000 visible-character product limit', () {
    expect(ReflectionTextPolicy.maximumLength, 1000);
    expect(ReflectionTextPolicy.exceedsMaximum('a' * 1000), isFalse);
    expect(ReflectionTextPolicy.exceedsMaximum('a' * 1001), isTrue);
  });

  test('composed emoji and combining sequences each count as one', () {
    const visibleCharacters = '👨‍👩‍👧‍👦🇹🇷👍🏽é';

    expect(ReflectionTextPolicy.length(visibleCharacters), 4);
  });
}
