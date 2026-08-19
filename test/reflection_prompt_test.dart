import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/utils/reflection_prompt.dart';

void main() {
  test('there are exactly the six approved prompts, in the approved order', () {
    expect(reflectionPrompts, [
      'What remains?',
      'What stayed with you?',
      'What became clearer?',
      'What are you noticing now?',
      'What feels different?',
      'What would you like to carry forward?',
    ]);
  });

  test('every key resolves to exactly one of the six approved prompts', () {
    final keys = [
      'a5f3c111-1111-4111-8111-111111111111',
      'a5f3c111-1111-4111-8111-111111111112',
      'a5f3c111-1111-4111-8111-111111111113',
      'not-a-uuid-legacy-id',
      '',
      'z' * 500,
    ];

    for (final key in keys) {
      expect(reflectionPrompts, contains(reflectionPromptFor(key)));
    }
  });

  test('the same key always resolves to the same prompt, repeatedly', () {
    const key = 'a5f3c111-1111-4111-8111-111111111111';
    final first = reflectionPromptFor(key);

    for (var i = 0; i < 20; i++) {
      expect(reflectionPromptFor(key), first);
    }
  });

  test(
      'the mapping is pinned to fixed, known values -- proving it does not '
      'depend on String.hashCode (whose value is only guaranteed stable '
      'within a single Dart run, never across relaunches or versions)', () {
    // If this ever depended on `String.hashCode`, these exact assertions
    // would be meaningless to pin (hashCode's own value for these strings
    // is not part of Dart's public API contract), yet this implementation
    // computes them from nothing but each key's fixed UTF-16 code units --
    // so the same expectations hold on every Dart/Flutter version, platform,
    // and process.
    expect(reflectionPromptFor(''), reflectionPrompts[0]);
    expect(reflectionPromptFor('a'), reflectionPrompts[97 % 6]);
    expect(reflectionPromptFor('ab'), reflectionPrompts[(97 + 98) % 6]);
    expect(
      reflectionPromptFor('abc'),
      reflectionPrompts[(97 + 98 + 99) % 6],
    );
  });

  test('different keys can resolve independently (not forced to collide)', () {
    final resolved = {
      for (final key in [
        'a5f3c111-1111-4111-8111-111111111111',
        'a5f3c111-1111-4111-8111-111111111112',
        'a5f3c111-1111-4111-8111-111111111113',
        'a5f3c111-1111-4111-8111-111111111114',
        'a5f3c111-1111-4111-8111-111111111115',
        'a5f3c111-1111-4111-8111-111111111116',
      ])
        key: reflectionPromptFor(key),
    };

    // Six distinct, adjacent revealIds must not all collapse onto a single
    // prompt -- proving selection genuinely varies with the key rather than
    // being a disguised constant.
    expect(resolved.values.toSet().length, greaterThan(1));
  });
}
