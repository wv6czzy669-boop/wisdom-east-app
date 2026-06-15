import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/data/wisdoms.dart';

void main() {
  test('wisdom database entries are valid', () {
    expect(wisdoms.length, greaterThan(500));

    for (final wisdom in wisdoms) {
      expect(wisdom['text'], isA<String>());
      expect((wisdom['text'] as String).trim(), isNotEmpty);

      expect(wisdom['tags'], isA<List>());
      final tags = wisdom['tags'] as List;
      expect(tags, isNotEmpty);

      for (final tag in tags) {
        expect(tag, isA<String>());
        expect((tag as String).trim(), isNotEmpty);
      }

      expect(wisdom['tone'], isA<String>());
      expect((wisdom['tone'] as String).trim(), isNotEmpty);
    }
  });
}
