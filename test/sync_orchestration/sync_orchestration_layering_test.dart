// Build 26 Phase 4D-2 (layering proof): structural proof that
// lib/sync_orchestration/ depends only on the approved layers -- the pure
// Dart sync domain (lib/sync/), the Phase 4C platform-bridge transport
// (lib/sync_platform/), the Phase 4D-1 durable persistence
// (lib/sync_persistence/), itself, and the one pre-existing, approved,
// content-free diagnostic helper (lib/utils/kept_diagnostics.dart) -- and
// that nothing outside this new layer depends on it. Mirrors the discipline
// test/sync_platform/cloud_kit_platform_privacy_test.dart and
// test/sync_persistence/sync_persistence_layering_test.dart already
// establish for their own layers. Synthetic content only.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Strips `//`, `///`, and `/* */` comments while leaving string literals
/// untouched -- a small, self-contained copy of the same test-only tooling
/// every sibling layering test file keeps its own independent copy of,
/// deliberately not shared, so this file's correctness is never coupled to
/// edits in any of those.
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
  late Directory orchestrationDir;
  late List<File> orchestrationFiles;
  late List<File> allLibFiles;
  late List<File> persistenceFiles;

  setUpAll(() {
    orchestrationDir = Directory('lib/sync_orchestration');
    expect(
      orchestrationDir.existsSync(),
      isTrue,
      reason: 'Expected lib/sync_orchestration to exist relative to the '
          'package root (the directory flutter test runs from).',
    );
    orchestrationFiles = orchestrationDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();

    allLibFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();

    persistenceFiles = Directory('lib/sync_persistence')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();
  });

  test(
      'every file scanned is a real, non-empty pure-Dart source file (the '
      'checks below are not vacuously passing over zero files)', () {
    expect(orchestrationFiles.length, greaterThanOrEqualTo(2));
    for (final file in orchestrationFiles) {
      expect(file.readAsStringSync().trim(), isNotEmpty);
    }
  });

  test(
      'lib/sync_orchestration/ only imports/exports the approved sync '
      'domain, sync_platform transport, sync_persistence storage, itself, '
      'or the one pre-approved content-free diagnostic helper', () {
    const allowedExactImports = {
      'package:wisdom_app/utils/kept_diagnostics.dart',
    };
    const allowedPrefixes = [
      'dart:',
      'package:wisdom_app/sync/',
      'package:wisdom_app/sync_platform/',
      'package:wisdom_app/sync_persistence/',
      'package:wisdom_app/sync_orchestration/',
    ];

    final violations = <String>[];
    for (final file in orchestrationFiles) {
      for (final line in file.readAsLinesSync()) {
        final trimmed = line.trimLeft();
        if (!trimmed.startsWith('import ') && !trimmed.startsWith('export ')) {
          continue;
        }
        final match = RegExp(r'''['"]([^'"]+)['"]''').firstMatch(trimmed);
        if (match == null) continue;
        final target = match.group(1)!;
        // Relative imports (e.g. '../sync/foo.dart') resolve within this
        // package's approved directories too -- normalize by checking the
        // path segment rather than requiring the package: form.
        final isApprovedRelative = target.startsWith('../sync/') ||
            target.startsWith('../sync_platform/') ||
            target.startsWith('../sync_persistence/') ||
            target.startsWith('../utils/kept_diagnostics.dart') ||
            !target.contains('/'); // same-directory sibling import
        final isApprovedPackage = allowedExactImports.contains(target) ||
            allowedPrefixes.any(target.startsWith);
        if (!isApprovedRelative && !isApprovedPackage) {
          violations.add('${file.path}: "$trimmed"');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test(
      'no production file under lib/sync_persistence/ has an import/export '
      'directive referencing the sync_platform layer (regression guard, '
      'restated for this phase\'s own layering proof)', () {
    final violations = <String>[];
    for (final file in persistenceFiles) {
      for (final line in file.readAsLinesSync()) {
        final trimmed = line.trimLeft();
        if (!trimmed.startsWith('import ') && !trimmed.startsWith('export ')) {
          continue;
        }
        if (trimmed.contains('sync_platform')) {
          violations.add('${file.path}: "$trimmed"');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test(
      'no file under lib/ outside lib/sync_orchestration/ has an '
      'import/export directive referencing sync_orchestration, except the '
      'disclosed consumers -- no repository, service, screen, or other '
      'startup file is wired to it', () {
    // Build 26 Phase 4E-3b: `IncomingKeptSyncCoordinator` is the first
    // consumer of `PendingIncomingSyncBatch`
    // (`SyncPassResult.pendingIncomingBatch`'s own doc comment always
    // anticipated exactly this future consumer -- see
    // `lib/sync_orchestration/pending_incoming_sync_batch.dart`).
    //
    // Build 26 Phase 4F adds exactly two more, both disclosed in that
    // phase's own scope: `lib/sync_runtime/cloud_kit_sync_runtime_coordinator
    // .dart` (the one production caller of `SyncOrchestrator.runSyncPass`)
    // and `lib/services/app_services.dart` (which constructs the one
    // production `SyncOrchestrator` instance, and constructs -- but never
    // calls a trigger method on -- the runtime coordinator). Every other
    // file outside lib/sync_orchestration/ (every repository, other service,
    // screen, and lib/main.dart itself) remains forbidden from importing it.
    const allowedExternalConsumerPaths = {
      'lib/sync_integration/incoming_kept_sync_coordinator.dart',
      'lib/sync_runtime/cloud_kit_sync_runtime_coordinator.dart',
      'lib/services/app_services.dart',
    };

    final violations = <String>[];
    for (final file in allLibFiles) {
      final normalizedPath = file.path.replaceAll('\\', '/');
      if (normalizedPath.contains('/sync_orchestration/')) continue;
      if (allowedExternalConsumerPaths.any(normalizedPath.endsWith)) {
        continue;
      }
      for (final line in file.readAsLinesSync()) {
        final trimmed = line.trimLeft();
        if (!trimmed.startsWith('import ') && !trimmed.startsWith('export ')) {
          continue;
        }
        if (trimmed.contains('sync_orchestration')) {
          violations.add('${file.path}: "$trimmed"');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test(
      'lib/main.dart never mentions SyncOrchestrator, runSyncPass, or '
      'sync_orchestration in real code -- Build 26 Phase 4F wires main.dart '
      'only to CloudKitSyncRuntimeCoordinator.requestSync, never directly to '
      'the orchestration layer', () {
    final mainFile = File('lib/main.dart');
    expect(mainFile.existsSync(), isTrue);
    final codeOnly = _stripComments(mainFile.readAsStringSync());
    expect(codeOnly.contains('SyncOrchestrator'), isFalse);
    expect(codeOnly.contains('runSyncPass'), isFalse);
    expect(codeOnly.contains('sync_orchestration'), isFalse);
  });

  test(
      'no file under lib/sync_orchestration/ mentions a MethodChannel '
      'invocation, or the platform-bridge implementation type, in real code '
      '-- only the existing CloudKitPlatformBridge abstraction is used', () {
    const forbiddenSubstrings = [
      'MethodChannel(',
      'invokeMethod',
      'MethodChannelCloudKitPlatformBridge',
      'EventChannel(',
    ];
    final violations = <String>[];
    for (final file in orchestrationFiles) {
      final codeOnly = _stripComments(file.readAsStringSync());
      for (final forbidden in forbiddenSubstrings) {
        if (codeOnly.contains(forbidden)) {
          violations.add('${file.path} contains "$forbidden" in code');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test(
      'no file under lib/sync_orchestration/ references a raw CloudKit '
      'user identifier concept -- only the opaque accountFingerprint is '
      'ever used', () {
    const forbiddenSubstrings = [
      'userRecordID',
      'CKUserIdentity',
      'rawAccountIdentifier',
      'CKRecordID',
    ];
    final violations = <String>[];
    for (final file in orchestrationFiles) {
      final codeOnly = _stripComments(file.readAsStringSync());
      for (final forbidden in forbiddenSubstrings) {
        if (codeOnly.contains(forbidden)) {
          violations.add('${file.path} contains "$forbidden" in code');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test(
      'no file under lib/sync_orchestration/ reads or writes any '
      'daily-access key, rolling-24-hour state, or repository/service type',
      () {
    const forbiddenSubstrings = [
      'daily_wisdom_access',
      'daily_wisdom_text',
      'wisdom_unlock_time_ms',
      'DailyWisdomRecord',
      'DailyAccessRepository',
      'DailyAccessService',
      'KeptRepository',
      'SavedReflectionsService',
    ];
    final violations = <String>[];
    for (final file in orchestrationFiles) {
      final codeOnly = _stripComments(file.readAsStringSync());
      for (final forbidden in forbiddenSubstrings) {
        if (codeOnly.contains(forbidden)) {
          violations.add('${file.path} contains "$forbidden" in code');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
