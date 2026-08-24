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
