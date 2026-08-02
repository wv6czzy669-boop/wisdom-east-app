// Build 26 Phase 4B-1: structural proof that the CloudKit platform-bridge
// layer (lib/sync_platform/) never depends on daily access, never accepts
// wisdom/Reflection/KeptRecord-shaped payloads, and never references the
// public or shared CloudKit database. See
// docs/architecture/EAST_CLOUDKIT_SYNC_V1.md's Phase 4B-1 section.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Strips `//`, `///`, and `/* */` comments from [source] while leaving
/// single-, double-, and triple-quoted string literals untouched. This is a
/// small, self-contained piece of *test tooling*, deliberately not shared
/// with `test/sync/sync_domain_privacy_test.dart`'s own copy -- duplicating
/// a few lines of test-only source-scanning logic across two independent
/// structural-proof test files is preferable here to coupling this new
/// Phase 4B-1 test file's correctness to edits in an already-verified
/// Phase 4A test file.
String _stripComments(String source) {
  final buffer = StringBuffer();
  var i = 0;
  final length = source.length;

  while (i < length) {
    final char = source[i];

    if (char == '/' && i + 1 < length && source[i + 1] == '/') {
      while (i < length && source[i] != '\n') {
        buffer.write(' ');
        i++;
      }
      continue;
    }

    if (char == '/' && i + 1 < length && source[i + 1] == '*') {
      var depth = 1;
      buffer.write('  ');
      i += 2;
      while (i < length && depth > 0) {
        if (i + 1 < length && source[i] == '/' && source[i + 1] == '*') {
          depth++;
          buffer.write('  ');
          i += 2;
          continue;
        }
        if (i + 1 < length && source[i] == '*' && source[i + 1] == '/') {
          depth--;
          buffer.write('  ');
          i += 2;
          continue;
        }
        buffer.write(source[i] == '\n' ? '\n' : ' ');
        i++;
      }
      continue;
    }

    if ((char == "'" || char == '"') &&
        i + 2 < length &&
        source[i + 1] == char &&
        source[i + 2] == char) {
      final quote = char * 3;
      buffer.write(quote);
      i += 3;
      while (i < length && !source.startsWith(quote, i)) {
        buffer.write(source[i]);
        i++;
      }
      if (i < length) {
        buffer.write(quote);
        i += 3;
      }
      continue;
    }

    if (char == "'" || char == '"') {
      final quote = char;
      buffer.write(char);
      i++;
      while (i < length && source[i] != quote && source[i] != '\n') {
        if (source[i] == '\\' && i + 1 < length) {
          buffer.write(source[i]);
          buffer.write(source[i + 1]);
          i += 2;
          continue;
        }
        buffer.write(source[i]);
        i++;
      }
      if (i < length && source[i] == quote) {
        buffer.write(quote);
        i++;
      }
      continue;
    }

    buffer.write(char);
    i++;
  }

  return buffer.toString();
}

void main() {
  late Directory platformDir;
  late List<File> dartFiles;

  setUpAll(() {
    platformDir = Directory('lib/sync_platform');
    expect(
      platformDir.existsSync(),
      isTrue,
      reason: 'Expected lib/sync_platform to exist relative to the package '
          'root (the directory flutter test runs from).',
    );
    dartFiles = platformDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();
  });

  group('1. no platform-bridge source file imports daily-access files', () {
    const forbiddenSubstrings = [
      'DailyWisdomRecord',
      'DailyAccessRepository',
      'DailyWisdomAccessService',
      'daily_wisdom_access',
      'daily_wisdom_record.dart',
      'daily_access_repository.dart',
      'unlockAt',
      'lockDuration',
      'pending_daily_wisdom_reveal',
      'PendingDailyWisdomReveal',
    ];

    const forbiddenImportPathSubstrings = [
      'daily_wisdom_record.dart',
      'daily_access_repository.dart',
      'daily_wisdom_access_service.dart',
      'pending_daily_wisdom_reveal.dart',
      'daily_access_snapshot.dart',
    ];

    test('no forbidden daily-access identifier appears in real code', () {
      expect(dartFiles, isNotEmpty);
      final violations = <String>[];
      for (final file in dartFiles) {
        final codeOnly = _stripComments(file.readAsStringSync());
        for (final forbidden in forbiddenSubstrings) {
          if (codeOnly.contains(forbidden)) {
            violations.add('${file.path} contains "$forbidden" in code');
          }
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('no import/export directive references a daily-access file', () {
      final violations = <String>[];
      for (final file in dartFiles) {
        for (final line in file.readAsLinesSync()) {
          final trimmed = line.trimLeft();
          if (!trimmed.startsWith('import ') &&
              !trimmed.startsWith('export ')) {
            continue;
          }
          for (final forbiddenPath in forbiddenImportPathSubstrings) {
            if (trimmed.contains(forbiddenPath)) {
              violations.add('${file.path}: "$trimmed"');
            }
          }
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });
  });

  group(
      '2. no platform-bridge source file references public/shared CloudKit '
      'database concepts', () {
    const forbiddenDatabaseSubstrings = [
      'publicCloudDatabase',
      'sharedCloudDatabase',
      'CKShare',
      'CKContainer.default().publicCloudDatabase',
    ];

    test('no forbidden public/shared database identifier appears in code', () {
      final violations = <String>[];
      for (final file in dartFiles) {
        final codeOnly = _stripComments(file.readAsStringSync());
        for (final forbidden in forbiddenDatabaseSubstrings) {
          if (codeOnly.contains(forbidden)) {
            violations.add('${file.path} contains "$forbidden" in code');
          }
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });
  });

  group(
      '3. no Dart bridge method accepts wisdom, Reflection, KeptRecord, or '
      'daily-access payloads', () {
    const forbiddenParameterTypeSubstrings = [
      'KeptRecord',
      'SyncTombstone', // sync-domain content types stay in lib/sync/, not
      // accepted directly as platform-bridge method parameters.
      'wisdomText',
      'reflectionText',
    ];

    test(
        'the platform-bridge interface and its production implementation '
        'never mention a content-bearing type as a parameter', () {
      final targets = dartFiles.where((f) =>
          f.path.endsWith('cloud_kit_platform_bridge.dart') ||
          f.path.endsWith('method_channel_cloud_kit_platform_bridge.dart'));
      expect(targets, isNotEmpty);

      final violations = <String>[];
      for (final file in targets) {
        final codeOnly = _stripComments(file.readAsStringSync());
        for (final forbidden in forbiddenParameterTypeSubstrings) {
          if (codeOnly.contains(forbidden)) {
            violations.add('${file.path} contains "$forbidden"');
          }
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });
  });

  test(
      '4. every file scanned is a real, non-empty pure-Dart source file '
      '(the checks above are not vacuously passing over zero files)', () {
    expect(dartFiles.length, greaterThanOrEqualTo(6));
    for (final file in dartFiles) {
      expect(file.readAsStringSync().trim(), isNotEmpty);
    }
  });

  group(
      '5. no app startup/repository code invokes CloudKit methods (Phase '
      '4B-1 never wires this bridge into production app startup)', () {
    test('lib/main.dart never mentions CloudKit or the sync-platform layer',
        () {
      final mainFile = File('lib/main.dart');
      expect(mainFile.existsSync(), isTrue);
      final content = mainFile.readAsStringSync();
      expect(content, isNot(contains('CloudKit')));
      expect(content, isNot(contains('sync_platform')));
      expect(content, isNot(contains('cloudkit_sync')));
    });

    test(
        'no production lib/ file outside lib/sync_platform/ imports the '
        'platform-bridge adapter', () {
      final libDir = Directory('lib');
      final allDartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !f.path.contains(
              '${Platform.pathSeparator}sync_platform${Platform.pathSeparator}'))
          .toList();

      final violations = <String>[];
      for (final file in allDartFiles) {
        final content = file.readAsStringSync();
        if (content.contains('sync_platform/') ||
            content.contains('MethodChannelCloudKitPlatformBridge')) {
          violations.add(file.path);
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });
  });
}
