import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/data/wisdoms.dart';
import 'package:wisdom_app/services/wisdom_selector.dart';

void main() {
  test('selector draws from the shared database without immediate repeats', () {
    final selector = WisdomSelectorService();
    final selectedTexts = <String>{};
    final databaseTexts = wisdoms.map((item) => item['text']).toSet();

    for (var index = 0; index < 20; index++) {
      final selection = selector.select();
      final text = selection['text'] as String;

      expect(databaseTexts, contains(text));
      expect(selectedTexts.add(text), isTrue);
    }
  });
}
