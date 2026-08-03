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
      '5. only the isolated sync_orchestration layer may consume CloudKit '
      'platform contracts; startup, repositories, UI, services, '
      'persistence, and unrelated production code may not', () {
    // Build 26 Phase 4D-2 correction: this group previously encoded the
    // Phase 4B-1 boundary ("no production file outside lib/sync_platform/
    // may import the platform bridge"), which was correct only while the
    // bridge foundation was intentionally unwired. The approved Phase 4D-2
    // architecture explicitly allows `lib/sync_orchestration/` to consume
    // the abstract platform contracts (never the concrete MethodChannel
    // adapter) -- see docs/architecture/EAST_CLOUDKIT_SYNC_V1.md §14. This
    // group therefore uses a directory allowlist (sync_platform itself,
    // plus its one approved consumer sync_orchestration) rather than a
    // blanket "nothing outside sync_platform" rule, while still asserting
    // sync_orchestration's own narrower rules explicitly below -- it is
    // never excluded from scanning without its own checks.

    final orchestrationDir = Directory('lib/sync_orchestration');
    final persistenceDir = Directory('lib/sync_persistence');
    final repositoriesDir = Directory('lib/repositories');
    final servicesDir = Directory('lib/services');

    List<File> dartFilesIn(Directory dir) {
      if (!dir.existsSync()) return const [];
      return dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
    }

    List<String> importExportLines(File file) => file
        .readAsLinesSync()
        .map((line) => line.trimLeft())
        .where(
            (line) => line.startsWith('import ') || line.startsWith('export '))
        .toList();

    test(
        'app startup (lib/main.dart, lib/app.dart) never mentions CloudKit, '
        'the sync-platform layer, or the sync orchestrator -- no production '
        'startup invocation of runSyncPass() exists yet', () {
      for (final path in ['lib/main.dart', 'lib/app.dart']) {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: '$path must exist.');
        final content = file.readAsStringSync();
        expect(content, isNot(contains('CloudKit')), reason: path);
        expect(content, isNot(contains('sync_platform')), reason: path);
        expect(content, isNot(contains('cloudkit_sync')), reason: path);
        expect(content, isNot(contains('sync_orchestration')), reason: path);
        expect(content, isNot(contains('SyncOrchestrator')), reason: path);
        expect(content, isNot(contains('runSyncPass')), reason: path);
      }
    });

    test(
        'every production file that imports a sync_platform path, or '
        'references the concrete MethodChannelCloudKitPlatformBridge '
        'adapter in code, lives under lib/sync_orchestration/ -- the only '
        'currently approved non-platform consumer (Phase 4D-2); no '
        'unrelated production directory may do either', () {
      final allDartFiles = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();

      final violations = <String>[];
      for (final file in allDartFiles) {
        final normalizedPath = file.path.replaceAll('\\', '/');
        final isPlatformFile = normalizedPath.contains('/sync_platform/');
        final isOrchestrationFile =
            normalizedPath.contains('/sync_orchestration/');
        if (isPlatformFile || isOrchestrationFile) {
          // The platform layer may reference itself; sync_orchestration's
          // own narrower rules are asserted separately below -- never
          // silently skipped without its own checks.
          continue;
        }
        for (final line in importExportLines(file)) {
          if (line.contains('sync_platform/')) {
            violations.add('${file.path}: "$line"');
          }
        }
        final codeOnly = _stripComments(file.readAsStringSync());
        if (codeOnly.contains('MethodChannelCloudKitPlatformBridge')) {
          violations.add(
            '${file.path} references MethodChannelCloudKitPlatformBridge '
            'in code',
          );
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test(
        'lib/sync_orchestration/ may import the abstract CloudKit platform '
        'contracts required for Phase 4D-2, but never imports the concrete '
        'method_channel_cloud_kit_platform_bridge.dart adapter file, and '
        'never constructs/references MethodChannelCloudKitPlatformBridge '
        'in code', () {
      final orchestrationFiles = dartFilesIn(orchestrationDir);
      expect(orchestrationFiles, isNotEmpty);

      final violations = <String>[];
      for (final file in orchestrationFiles) {
        for (final line in importExportLines(file)) {
          if (line.contains('sync_platform/') &&
              line.contains('method_channel_cloud_kit_platform_bridge.dart')) {
            violations.add('${file.path}: "$line"');
          }
        }
        final codeOnly = _stripComments(file.readAsStringSync());
        if (codeOnly.contains('MethodChannelCloudKitPlatformBridge')) {
          violations.add(
            '${file.path} references MethodChannelCloudKitPlatformBridge '
            'in real code (a doc-comment mention would already have been '
            'stripped above)',
          );
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test(
        'lib/sync_persistence/ has zero sync-platform imports (restated '
        'here as a regression guard for this specific privacy boundary, '
        'alongside the equivalent check already enforced by '
        'test/sync_orchestration/sync_orchestration_layering_test.dart)', () {
      final persistenceFiles = dartFilesIn(persistenceDir);
      expect(persistenceFiles, isNotEmpty);

      final violations = <String>[];
      for (final file in persistenceFiles) {
        for (final line in importExportLines(file)) {
          if (line.contains('sync_platform')) {
            violations.add('${file.path}: "$line"');
          }
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test(
        'repository and Reflection/daily-access service files (including '
        'migration and bootstrap coordinators under lib/services/) never '
        'import, mention, or invoke CloudKit platform code', () {
      final targets = <File>[
        ...dartFilesIn(repositoriesDir),
        ...dartFilesIn(servicesDir),
      ];
      expect(targets, isNotEmpty);

      const forbidden = [
        'CloudKit',
        'sync_platform',
        'MethodChannelCloudKitPlatformBridge',
        'SyncOrchestrator',
        'runSyncPass',
      ];

      final violations = <String>[];
      for (final file in targets) {
        final codeOnly = _stripComments(file.readAsStringSync());
        for (final term in forbidden) {
          if (codeOnly.contains(term)) {
            violations.add('${file.path} contains "$term" in code');
          }
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test(
        'no production file outside lib/sync_platform/ references the '
        'concrete CloudKit MethodChannel/EventChannel by name -- the only '
        'legitimate direct channel usage is inside the adapter itself', () {
      const forbiddenChannelNames = [
        'com.dogukan.dailywisdom/cloudkit_sync',
        'com.dogukan.dailywisdom/cloudkit_sync_events',
      ];
      final allDartFiles = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where(
              (f) => !f.path.replaceAll('\\', '/').contains('/sync_platform/'))
          .toList();

      final violations = <String>[];
      for (final file in allDartFiles) {
        final codeOnly = _stripComments(file.readAsStringSync());
        for (final channel in forbiddenChannelNames) {
          if (codeOnly.contains(channel)) {
            violations.add('${file.path} references "$channel" directly');
          }
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test(
        'lib/sync_orchestration/ carries no daily-access identifier -- the '
        'same daily-access isolation group 1 enforces on the platform '
        'layer extends to its one approved consumer', () {
      const forbiddenDailyAccessSubstrings = [
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
      final orchestrationFiles = dartFilesIn(orchestrationDir);
      expect(orchestrationFiles, isNotEmpty);

      final violations = <String>[];
      for (final file in orchestrationFiles) {
        final codeOnly = _stripComments(file.readAsStringSync());
        for (final forbidden in forbiddenDailyAccessSubstrings) {
          if (codeOnly.contains(forbidden)) {
            violations.add('${file.path} contains "$forbidden" in code');
          }
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });
  });
}
