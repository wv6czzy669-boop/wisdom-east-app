import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/data/localized_wisdoms.dart';
import 'package:wisdom_app/data/wisdoms.dart';

void main() {
  test(
      'the app and interactive widget use the exact same reviewed public catalog',
      () {
    final exported = jsonDecode(
        File('ios/EastShared/EastDailyWisdomCatalog.json').readAsStringSync());
    expect(exported, {
      'schemaVersion': 1,
      'catalogs': {
        'en': {
          for (final entry in wisdoms)
            entry['id'] as String: entry['text'] as String
        },
        ...reviewedLocalizedWisdomCatalogs,
      },
    });
  });
}
