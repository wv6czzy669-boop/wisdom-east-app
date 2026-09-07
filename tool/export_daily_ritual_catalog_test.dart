import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/data/localized_wisdoms.dart';
import 'package:wisdom_app/data/wisdoms.dart';

// Run explicitly with `flutter test tool/export_daily_ritual_catalog_test.dart`
// whenever the reviewed public wisdom catalogs change.
void main() {
  test('export the shared native public wisdom catalog', () {
    final catalogs = {
      'en': {
        for (final entry in wisdoms)
          entry['id'] as String: entry['text'] as String
      },
      ...reviewedLocalizedWisdomCatalogs,
    };
    File('ios/EastShared/EastDailyWisdomCatalog.json').writeAsStringSync(
      jsonEncode({'schemaVersion': 1, 'catalogs': catalogs}),
    );
  });
}
