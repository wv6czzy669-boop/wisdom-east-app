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
      '5. only the isolated sync_orchestration layer, plus two exact, '
      'narrowly-approved Phase 4E-4 exceptions, may consume CloudKit '
      'platform contracts; startup, repositories, screens, widgets, '
      'services, persistence, and unrelated production code may not', () {
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
    //
    // Build 26 Phase 4E-4 correction: the locked Phase 4E-4 design adds
    // exactly two further, file-exact (never directory-wide) exceptions to
    // that same boundary -- see
    // docs/architecture/EAST_CLOUDKIT_SYNC_V1.md's Phase 4E-4 section:
    //
    //   1. lib/sync_integration/kept_sync_bootstrap_coordinator.dart --
    //      the only file in lib/sync_integration/ permitted to import
    //      abstract sync_platform CONTRACTS (it owns remote-first
    //      bootstrap network sequencing and must not go through
    //      SyncOrchestrator.runSyncPass). It must never import the
    //      concrete method_channel_cloud_kit_platform_bridge.dart adapter
    //      or reference MethodChannelCloudKitPlatformBridge in code --
    //      asserted explicitly below, never merely assumed.
    //   2. lib/services/app_services.dart -- the composition root, and the
    //      only production file anywhere permitted to reference the
    //      concrete MethodChannelCloudKitPlatformBridge adapter or import
    //      its file. This is not permission for any other file under
    //      lib/services/ (or lib/repositories/, lib/screens/,
    //      lib/widgets/) to do either -- asserted explicitly below.
    //
    // Every exception here is an exact file path, never a directory-wide
    // allowlist entry.

    final orchestrationDir = Directory('lib/sync_orchestration');
    final integrationDir = Directory('lib/sync_integration');
    final persistenceDir = Directory('lib/sync_persistence');
    final repositoriesDir = Directory('lib/repositories');
    final servicesDir = Directory('lib/services');
    final screensDir = Directory('lib/screens');
    final widgetsDir = Directory('lib/widgets');

    const bootstrapCoordinatorPath =
        'lib/sync_integration/kept_sync_bootstrap_coordinator.dart';
    const appServicesPath = 'lib/services/app_services.dart';
    // Build 26 Phase 4F Exception 3: the one production runtime trigger/
    // retry/lifecycle coordinator. Like kept_sync_bootstrap_coordinator.dart
    // (Exception 1), it depends on abstract sync_platform CONTRACTS only
    // (CloudKitPlatformBridge, CloudKitAccountChangeEvent) -- never the
    // concrete method_channel_cloud_kit_platform_bridge.dart adapter, and
    // never MethodChannelCloudKitPlatformBridge in code. This is an exact
    // file-path exception, never a directory-wide one.
    const runtimeCoordinatorPath =
        'lib/sync_runtime/cloud_kit_sync_runtime_coordinator.dart';
    // Build 26 Phase 5 (slice 2) Exception 4: the remote deletion runner.
    // Like kept_sync_bootstrap_coordinator.dart (Exception 1) and
    // cloud_kit_sync_runtime_coordinator.dart (Exception 3), it depends on
    // abstract sync_platform CONTRACTS only -- never the concrete
    // method_channel_cloud_kit_platform_bridge.dart adapter, and never
    // MethodChannelCloudKitPlatformBridge in code. This is an exact
    // file-path exception, never a directory-wide one.
    const deletionRunnerPath =
        'lib/sync_deletion/cloud_kit_remote_deletion_runner.dart';

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
        'lib/app.dart never mentions CloudKit, the sync-platform layer, the '
        'sync orchestrator, or the sync runtime layer -- it remains a pure '
        'MaterialApp shell with no lifecycle or sync ownership of any kind',
        () {
      const path = 'lib/app.dart';
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path must exist.');
      final content = file.readAsStringSync();
      expect(content, isNot(contains('CloudKit')), reason: path);
      expect(content, isNot(contains('sync_platform')), reason: path);
      expect(content, isNot(contains('cloudkit_sync')), reason: path);
      expect(content, isNot(contains('sync_orchestration')), reason: path);
      expect(content, isNot(contains('SyncOrchestrator')), reason: path);
      expect(content, isNot(contains('runSyncPass')), reason: path);
      expect(content, isNot(contains('sync_runtime')), reason: path);
    });

    test(
        'lib/main.dart never mentions the sync-platform transport layer or '
        'the sync orchestrator directly -- Build 26 Phase 4F wires startup '
        'and foreground triggers only through '
        'CloudKitSyncRuntimeCoordinator.requestSync (lib/sync_runtime/), '
        'never directly to CloudKitPlatformBridge, MethodChannel, or '
        'SyncOrchestrator.runSyncPass', () {
      const path = 'lib/main.dart';
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path must exist.');
      final content = file.readAsStringSync();
      expect(content, isNot(contains('sync_platform')), reason: path);
      expect(content, isNot(contains('MethodChannel')), reason: path);
      expect(content, isNot(contains('cloudkit_sync')), reason: path);
      expect(content, isNot(contains('sync_orchestration')), reason: path);
      expect(content, isNot(contains('SyncOrchestrator')), reason: path);
      expect(content, isNot(contains('runSyncPass')), reason: path);
      // Build 26 Phase 4F: main.dart IS now expected to reference the
      // runtime coordinator -- this is this phase's own, disclosed startup
      // wiring, not a regression of the boundary above.
      expect(content, contains('sync_runtime'), reason: path);
      expect(content, contains('cloudKitSyncRuntimeCoordinator'), reason: path);
    });

    test(
        'every production file that imports a sync_platform path lives '
        'under lib/sync_orchestration/, or is one of the three exact '
        'exceptions (kept_sync_bootstrap_coordinator.dart and '
        'cloud_kit_sync_runtime_coordinator.dart for CONTRACTS, '
        'app_services.dart as the composition root) -- and no production '
        'file anywhere except app_services.dart references the concrete '
        'MethodChannelCloudKitPlatformBridge adapter in code', () {
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
        final isBootstrapCoordinator =
            normalizedPath.endsWith(bootstrapCoordinatorPath);
        final isRuntimeCoordinator =
            normalizedPath.endsWith(runtimeCoordinatorPath);
        final isDeletionRunner = normalizedPath.endsWith(deletionRunnerPath);
        final isAppServices = normalizedPath.endsWith(appServicesPath);

        if (!isPlatformFile &&
            !isOrchestrationFile &&
            !isBootstrapCoordinator &&
            !isRuntimeCoordinator &&
            !isDeletionRunner &&
            !isAppServices) {
          for (final line in importExportLines(file)) {
            if (line.contains('sync_platform/')) {
              violations.add('${file.path}: "$line"');
            }
          }
        }

        if (isPlatformFile || isOrchestrationFile) {
          // The platform layer may reference itself; sync_orchestration's
          // own narrower rules (never the concrete adapter) are asserted
          // separately below -- never silently skipped without its own
          // checks. Nothing else to check for these files here.
          continue;
        }

        // The concrete MethodChannel adapter may only ever be referenced
        // from the composition root (app_services.dart) -- not even the
        // bootstrap coordinator or the runtime coordinator, each of which is
        // asserted (in its own dedicated test below) to depend on abstract
        // contracts only.
        final codeOnly = _stripComments(file.readAsStringSync());
        if (codeOnly.contains('MethodChannelCloudKitPlatformBridge') &&
            !isAppServices) {
          violations.add(
            '${file.path} references MethodChannelCloudKitPlatformBridge '
            'in code',
          );
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test(
        'kept_sync_bootstrap_coordinator.dart is the only file under '
        'lib/sync_integration/ permitted to import a sync_platform path -- '
        'this is an exact-file allowlist entry, never a directory-wide '
        'exception', () {
      final integrationFiles = dartFilesIn(integrationDir);
      expect(integrationFiles, isNotEmpty);

      final violations = <String>[];
      for (final file in integrationFiles) {
        final normalizedPath = file.path.replaceAll('\\', '/');
        if (normalizedPath.endsWith(bootstrapCoordinatorPath)) continue;
        for (final line in importExportLines(file)) {
          if (line.contains('sync_platform/')) {
            violations.add('${file.path}: "$line"');
          }
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test(
        'kept_sync_bootstrap_coordinator.dart never imports the concrete '
        'method_channel_cloud_kit_platform_bridge.dart adapter and never '
        'references MethodChannelCloudKitPlatformBridge in code -- it '
        'depends on abstract sync_platform CONTRACTS only (Phase 4E-4 '
        'Exception 1)', () {
      final file = File(bootstrapCoordinatorPath);
      expect(file.existsSync(), isTrue,
          reason: '$bootstrapCoordinatorPath must exist.');

      final violations = <String>[];
      for (final line in importExportLines(file)) {
        if (line.contains('sync_platform/') &&
            line.contains('method_channel_cloud_kit_platform_bridge.dart')) {
          violations.add('$bootstrapCoordinatorPath: "$line"');
        }
      }
      final codeOnly = _stripComments(file.readAsStringSync());
      if (codeOnly.contains('MethodChannelCloudKitPlatformBridge')) {
        violations.add(
          '$bootstrapCoordinatorPath references '
          'MethodChannelCloudKitPlatformBridge in real code (a doc-comment '
          'mention would already have been stripped above)',
        );
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test(
        'cloud_kit_sync_runtime_coordinator.dart never imports the concrete '
        'method_channel_cloud_kit_platform_bridge.dart adapter and never '
        'references MethodChannelCloudKitPlatformBridge in code -- it '
        'depends on abstract sync_platform CONTRACTS only (Build 26 Phase '
        '4F Exception 3, mirroring kept_sync_bootstrap_coordinator.dart\'s '
        'own Exception 1)', () {
      final file = File(runtimeCoordinatorPath);
      expect(file.existsSync(), isTrue,
          reason: '$runtimeCoordinatorPath must exist.');

      final violations = <String>[];
      for (final line in importExportLines(file)) {
        if (line.contains('sync_platform/') &&
            line.contains('method_channel_cloud_kit_platform_bridge.dart')) {
          violations.add('$runtimeCoordinatorPath: "$line"');
        }
      }
      final codeOnly = _stripComments(file.readAsStringSync());
      if (codeOnly.contains('MethodChannelCloudKitPlatformBridge')) {
        violations.add(
          '$runtimeCoordinatorPath references '
          'MethodChannelCloudKitPlatformBridge in real code (a doc-comment '
          'mention would already have been stripped above)',
        );
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test(
        'cloud_kit_remote_deletion_runner.dart never imports the concrete '
        'method_channel_cloud_kit_platform_bridge.dart adapter and never '
        'references MethodChannelCloudKitPlatformBridge in code -- it '
        'depends on abstract sync_platform CONTRACTS only (Build 26 Phase 5 '
        'slice 2 Exception 4, mirroring kept_sync_bootstrap_coordinator.dart\'s '
        'own Exception 1)', () {
      final file = File(deletionRunnerPath);
      expect(file.existsSync(), isTrue,
          reason: '$deletionRunnerPath must exist.');

      final violations = <String>[];
      for (final line in importExportLines(file)) {
        if (line.contains('sync_platform/') &&
            line.contains('method_channel_cloud_kit_platform_bridge.dart')) {
          violations.add('$deletionRunnerPath: "$line"');
        }
      }
      final codeOnly = _stripComments(file.readAsStringSync());
      if (codeOnly.contains('MethodChannelCloudKitPlatformBridge')) {
        violations.add(
          '$deletionRunnerPath references '
          'MethodChannelCloudKitPlatformBridge in real code (a doc-comment '
          'mention would already have been stripped above)',
        );
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test(
        'app_services.dart is the only production file outside '
        'sync_platform/ and sync_orchestration/ permitted to reference the '
        'concrete MethodChannelCloudKitPlatformBridge adapter -- restated '
        'here as its own dedicated, explicitly-named guard (Phase 4E-4 '
        'Exception 2), independent of the combined scan above', () {
      final allDartFiles = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();

      final violations = <String>[];
      for (final file in allDartFiles) {
        final normalizedPath = file.path.replaceAll('\\', '/');
        if (normalizedPath.contains('/sync_platform/') ||
            normalizedPath.contains('/sync_orchestration/') ||
            normalizedPath.endsWith(appServicesPath)) {
          continue;
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
        'app_services.dart only constructs/wires KeptSyncBootstrapCoordinator '
        '-- it never calls runBootstrap, evaluateAssociation, '
        'authorizeAssociation, or repairLegacyAssociationMarker itself '
        '(Phase 4E-4: app_services is composition wiring only, never a '
        'caller of bootstrap operations; Phase 4F owns wiring an actual '
        'trigger)', () {
      final file = File(appServicesPath);
      expect(file.existsSync(), isTrue, reason: '$appServicesPath must exist.');
      final codeOnly = _stripComments(file.readAsStringSync());

      const forbiddenCalls = [
        '.runBootstrap(',
        '.evaluateAssociation(',
        '.authorizeAssociation(',
        '.repairLegacyAssociationMarker(',
      ];
      final violations = <String>[
        for (final call in forbiddenCalls)
          if (codeOnly.contains(call)) '$appServicesPath calls "$call"',
      ];
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
        'repository, screen, widget, and Reflection/daily-access service '
        'files (every lib/services/ file except the exact composition-root '
        'exception app_services.dart, whose narrower, explicit allowances '
        'are asserted separately above) never import, mention, or invoke '
        'CloudKit platform code', () {
      final targets = <File>[
        ...dartFilesIn(repositoriesDir),
        ...dartFilesIn(servicesDir).where(
          (f) => !f.path.replaceAll('\\', '/').endsWith(appServicesPath),
        ),
        ...dartFilesIn(screensDir),
        ...dartFilesIn(widgetsDir),
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
