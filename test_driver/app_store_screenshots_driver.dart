import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() {
  final rawDirectory = Platform.environment['EAST_SCREENSHOT_RAW_DIR'];
  if (rawDirectory == null || rawDirectory.trim().isEmpty) {
    throw StateError('EAST_SCREENSHOT_RAW_DIR must be set.');
  }

  final directory = Directory(rawDirectory)..createSync(recursive: true);
  return integrationDriver(
    onScreenshot: (name, screenshotBytes, [args]) async {
      final file = File('${directory.path}/$name.png');
      await file.writeAsBytes(screenshotBytes, flush: true);
      return true;
    },
  );
}
