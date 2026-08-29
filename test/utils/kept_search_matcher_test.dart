import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/utils/kept_search_matcher.dart';

void main() {
  test('empty and whitespace-only queries preserve every Kept item', () {
    expect(
      KeptSearchMatcher.matches(
        wisdom: 'Anything',
        reflection: null,
        query: '   ',
      ),
      isTrue,
    );
  });

  test('matches every query term across wisdom and Reflection text', () {
    expect(
      KeptSearchMatcher.matches(
        wisdom: 'A quiet doorway',
        reflection: 'I noticed courage arriving.',
        query: 'doorway courage',
      ),
      isTrue,
    );
    expect(
      KeptSearchMatcher.matches(
        wisdom: 'A quiet doorway',
        reflection: 'I noticed courage arriving.',
        query: 'doorway silence',
      ),
      isFalse,
    );
  });

  test('optional editorial date corpus participates in matching', () {
    expect(
      KeptSearchMatcher.matches(
        wisdom: 'Still water',
        reflection: null,
        query: 'August 2026',
        additionalText: 'August 28, 2026 AUGUST 2026',
      ),
      isTrue,
    );
  });

  test('numeric date terms do not match a partial year', () {
    expect(
      KeptSearchMatcher.matches(
        wisdom: 'Still water',
        reflection: null,
        query: 'July 20',
        additionalText: 'July 21, 2026 JULY 2026 21 7 2026',
      ),
      isFalse,
    );
    expect(
      KeptSearchMatcher.matches(
        wisdom: 'Still water',
        reflection: null,
        query: 'July 20',
        additionalText: 'July 20, 2026 JULY 2026 20 7 2026',
      ),
      isTrue,
    );
  });

  test('folds Turkish I and representative product-locale diacritics', () {
    expect(KeptSearchMatcher.normalize('İÇİMDE IŞIK'), 'icimde isik');
    expect(
        KeptSearchMatcher.normalize('Réflexion déjà là'), 'reflexion deja la');
    expect(
        KeptSearchMatcher.normalize('Zażółć gęślą jaźń'), 'zazolc gesla jazn');
    expect(KeptSearchMatcher.normalize('Điện ở lại'), 'dien o lai');
  });

  test('keeps CJK text searchable and ignores Arabic vocalization marks', () {
    expect(KeptSearchMatcher.normalize('留下的智慧'), '留下的智慧');
    expect(KeptSearchMatcher.normalize('حِكْمَة'), 'حكمة');
  });
}
