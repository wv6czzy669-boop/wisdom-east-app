import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Phase 5F-A addition: when set, `onScreenshot` shells out to
/// `xcrun simctl io <udid> screenshot` instead of writing the Flutter-only
/// surface bytes the VM service hands back. `binding.takeScreenshot()`'s own
/// bytes never include the native iOS status bar (SpringBoard compositing
/// sits outside Flutter's own rendered surface), so App Store plates that
/// must show a real status bar need the OS-level capture instead. The
/// original bytes-only path (used by `app_store_screenshots_test.dart`/
/// `compose.py`) is completely unchanged when this variable is unset.
final String? _nativeUdid = Platform.environment['EAST_SCREENSHOT_NATIVE_UDID'];

Future<void> main() {
  final rawDirectory = Platform.environment['EAST_SCREENSHOT_RAW_DIR'];
  if (rawDirectory == null || rawDirectory.trim().isEmpty) {
    throw StateError('EAST_SCREENSHOT_RAW_DIR must be set.');
  }

  final directory = Directory(rawDirectory)..createSync(recursive: true);
  return integrationDriver(
    onScreenshot: (name, screenshotBytes, [args]) async {
      final file = File('${directory.path}/$name.png');
      final udid = _nativeUdid;
      if (udid == null || udid.trim().isEmpty) {
        await file.writeAsBytes(screenshotBytes, flush: true);
        return true;
      }
      final result = await Process.run(
        'xcrun',
        ['simctl', 'io', udid, 'screenshot', file.path],
      );
      if (result.exitCode != 0) {
        stderr.write(result.stderr);
        return false;
      }
      return true;
    },
  );
}
