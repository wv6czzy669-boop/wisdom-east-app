// Build 26 Phase 4E-1: structural proof that lib/sync_integration/ depends
// only on lib/sync/ and lib/sync_persistence/ (plus this codebase's existing
// protected-persistence primitives), never on lib/sync_platform/, never on
// MethodChannel/EventChannel directly, and is not wired into any screen,
// service, startup path, or the daily-access domain. Mirrors the discipline
// test/sync_persistence/sync_persistence_layering_test.dart,
// test/sync_platform/cloud_kit_platform_privacy_test.dart, and
// test/sync/sync_domain_privacy_test.dart already establish for their own
// layers. Synthetic content only; no real MethodChannel or CloudKit access
// anywhere in this file.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/sync_integration/local_sync_intent.dart';
import 'package:wisdom_app/sync_integration/local_sync_intent_store.dart';

/// Strips `//`, `///`, and `/* */` comments while leaving string literals
/// untouched -- a small, self-contained copy of the same test-only tooling
/// every other layering test in this codebase keeps its own independent
/// copy of, deliberately not shared.
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
  late Directory integrationDir;
  late List<File> integrationFiles;
  late Directory libDir;
  late List<File> allLibFiles;

  setUpAll(() {
    integrationDir = Directory('lib/sync_integration');
    expect(
      integrationDir.existsSync(),
      isTrue,
      reason: 'Expected lib/sync_integration to exist relative to the '
          'package root (the directory flutter test runs from).',
    );
    integrationFiles = integrationDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();

    libDir = Directory('lib');
    allLibFiles = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();
  });

  test(
      'every file scanned is a real, non-empty pure-Dart source file (the '
      'checks below are not vacuously passing over zero files)', () {
    expect(integrationFiles.length, greaterThanOrEqualTo(5));
    for (final file in integrationFiles) {
      expect(file.readAsStringSync().trim(), isNotEmpty);
    }
  });

  test(
      'no production file under lib/sync_integration/ has an import/export '
      'directive referencing the sync_platform layer', () {
    final violations = <String>[];
    for (final file in integrationFiles) {
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
      'every import under lib/sync_integration/ resolves to dart:, '
      'package:path_provider, package:uuid, sync_integration itself, '
      'sync_persistence, sync, persistence, or utils -- never repositories, '
      'services, screens, or widgets', () {
    final allowedPrefixes = [
      'dart:',
      'package:path_provider/',
      'package:uuid/',
      'package:wisdom_app/sync_integration/',
      'package:wisdom_app/sync_persistence/',
      'package:wisdom_app/sync/',
      'package:wisdom_app/persistence/',
      'package:wisdom_app/utils/',
      '../sync_persistence/',
      '../sync/',
      '../persistence/',
      '../utils/',
      // Bare same-directory relative imports (this codebase's own
      // sync_integration files importing one another directly).
      'local_sync_intent',
      'protected_local_sync_intent_store.dart',
      'kept_sync_integration_coordinator.dart',
    ];

    final violations = <String>[];
    for (final file in integrationFiles) {
      for (final line in file.readAsLinesSync()) {
        final trimmed = line.trimLeft();
        if (!trimmed.startsWith('import ') && !trimmed.startsWith('export ')) {
          continue;
        }
        final match = RegExp(r'''['"]([^'"]+)['"]''').firstMatch(trimmed);
        if (match == null) continue;
        final target = match.group(1)!;
        final isAllowed =
            allowedPrefixes.any((prefix) => target.startsWith(prefix));
        if (!isAllowed) {
          violations.add('${file.path}: "$trimmed"');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test(
      'no MethodChannel/EventChannel invocation and no CloudKit transport '
      'method or type name exists anywhere under lib/sync_integration/ (in '
      'real code, not comments)', () {
    const forbiddenSubstrings = [
      'MethodChannel(',
      'EventChannel(',
      'invokeMethod',
      'modifyPrivateRecords',
      'fetchPrivateZoneChanges',
      'CKRecord',
      'CKModifyRecordsOperation',
      'CKFetchRecordZoneChangesOperation',
      'CloudKeptWisdomWireEnvelope',
      'MethodChannelCloudKitPlatformBridge',
    ];

    final violations = <String>[];
    for (final file in integrationFiles) {
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
      'KeptRepository still imports no CloudKit/sync-platform adapter and '
      'no sync_integration type', () {
    final matches = allLibFiles
        .where((file) => file.path.replaceAll('\\', '/').endsWith(
              'lib/repositories/kept_repository.dart',
            ))
        .toList();
    expect(matches, hasLength(1),
        reason: 'Expected to find exactly one kept_repository.dart under '
            'lib/repositories/.');
    final source = matches.single.readAsStringSync();
    for (final line in source.split('\n')) {
      final trimmed = line.trimLeft();
      if (!trimmed.startsWith('import ') && !trimmed.startsWith('export ')) {
        continue;
      }
      expect(trimmed.contains('sync_platform'), isFalse,
          reason: 'kept_repository.dart must not import sync_platform: '
              '"$trimmed"');
      expect(trimmed.contains('sync_integration'), isFalse,
          reason: 'kept_repository.dart must not import sync_integration '
              'in Phase 4E-1 (no wiring yet): "$trimmed"');
    }
  });

  test(
      'no file outside lib/sync_integration/ imports anything from '
      'lib/sync_integration/ -- Phase 4E-1 establishes the layer without '
      'wiring any real call site to it yet', () {
    final violations = <String>[];
    for (final file in allLibFiles) {
      final normalizedPath = file.path.replaceAll('\\', '/');
      if (normalizedPath.contains('/lib/sync_integration/') ||
          normalizedPath.startsWith('lib/sync_integration/')) {
        continue;
      }
      for (final line in file.readAsLinesSync()) {
        final trimmed = line.trimLeft();
        if (!trimmed.startsWith('import ') && !trimmed.startsWith('export ')) {
          continue;
        }
        if (trimmed.contains('sync_integration')) {
          violations.add('$normalizedPath: "$trimmed"');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test(
      'no screen, widget, service, or main.dart file references any '
      'sync_integration type name in real code', () {
    const typeNames = [
      'LocalSyncIntent',
      'LocalSyncIntentPayload',
      'LocalSyncIntentKind',
      'LocalSyncIntentStage',
      'LocalSyncIntentStore',
      'ProtectedLocalSyncIntentStore',
      'LocalSyncIntentEnvelope',
      'KeptSyncIntegrationCoordinatorBoundary',
    ];

    final scanTargets = allLibFiles.where((file) {
      final p = file.path.replaceAll('\\', '/');
      return p.contains('/lib/screens/') ||
          p.contains('/lib/widgets/') ||
          p.contains('/lib/services/') ||
          p.endsWith('/lib/main.dart');
    });

    final violations = <String>[];
    for (final file in scanTargets) {
      final codeOnly = _stripComments(file.readAsStringSync());
      for (final typeName in typeNames) {
        if (codeOnly.contains(typeName)) {
          violations.add('${file.path} references "$typeName"');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test(
      'no production runSyncPass() startup invocation exists anywhere under '
      'lib/ outside sync_orchestration\'s own definition file', () {
    final violations = <String>[];
    for (final file in allLibFiles) {
      final normalizedPath = file.path.replaceAll('\\', '/');
      if (normalizedPath.endsWith(
        'lib/sync_orchestration/sync_orchestrator.dart',
      )) {
        continue;
      }
      final codeOnly = _stripComments(file.readAsStringSync());
      if (codeOnly.contains('runSyncPass()') ||
          codeOnly.contains('.runSyncPass(')) {
        violations.add(file.path);
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test(
      'no daily-access persistence key or file is imported into, or '
      'referenced by, any file under lib/sync_integration/', () {
    const forbiddenReferences = [
      'daily_wisdom_access',
      'daily_wisdom_text',
      'wisdom_unlock_time_ms',
      'keeper_daily_wisdom_state',
      'DailyAccessRepository',
      'daily_access_repository.dart',
      'DailyWisdomRecord',
    ];

    final violations = <String>[];
    for (final file in integrationFiles) {
      final codeOnly = _stripComments(file.readAsStringSync());
      for (final forbidden in forbiddenReferences) {
        if (codeOnly.contains(forbidden)) {
          violations.add('${file.path} references "$forbidden"');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test(
      'no file under lib/sync_integration/ uses SharedPreferences directly '
      '-- the durable intent store uses the dedicated protected-file '
      'primitives, never SharedPreferences', () {
    final violations = <String>[];
    for (final file in integrationFiles) {
      final codeOnly = _stripComments(file.readAsStringSync());
      if (codeOnly.contains('SharedPreferences')) {
        violations.add(file.path);
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  // -------------------------------------------------------------------
  // Privacy: toString()/toLogSafeSummary() rendering never leaks a real
  // revealId, mutationId, intentId, or wisdom/reflection text value.
  // -------------------------------------------------------------------

  test(
      'LocalSyncIntent.toString()/toLogSafeSummary() never render the '
      'intentId, revealId, mutationId, wisdom text, or reflection text', () {
    const revealId = '11111111-1111-4111-8111-111111111111';
    const intentId = '22222222-2222-4222-8222-222222222222';
    const mutationId = '33333333-3333-4333-8333-333333333333';
    const wisdomText = 'A very specific synthetic secret wisdom sentence.';
    const reflectionText = 'A very specific synthetic secret reflection.';

    final intent = LocalSyncIntent(
      intentId: intentId,
      kind: LocalSyncIntentKind.update,
      payload: LocalSyncIntentPayload.active(
        revealId: revealId,
        wisdomText: wisdomText,
        revealedAtMs: 1000,
        keptAtMs: 2000,
        updatedAtMs: 3000,
        mutationId: mutationId,
        reflectionText: reflectionText,
        reflectedAtMs: 3500,
      ),
      stage: LocalSyncIntentStage.pendingLocalApplication,
      enqueuedAt: DateTime.utc(2026, 8, 1),
    );

    final rendered = intent.toString();
    final summary = intent.toLogSafeSummary().toString();

    for (final secret in [
      revealId,
      intentId,
      mutationId,
      wisdomText,
      reflectionText,
    ]) {
      expect(rendered, isNot(contains(secret)),
          reason: 'toString() leaked "$secret"');
      expect(summary, isNot(contains(secret)),
          reason: 'toLogSafeSummary() leaked "$secret"');
    }

    // The summary is still informative -- categorical fields only.
    expect(summary, contains('update'));
    expect(summary, contains('pendingLocalApplication'));
  });

  test('LocalSyncIntentStoreException.toString() never renders its cause', () {
    const secretCause = 'a very specific synthetic file-path secret';
    final exception = LocalSyncIntentStoreException(
      'replace-post-rename',
      'Something failed.',
      secretCause,
    );

    expect(exception.toString(), isNot(contains(secretCause)));
  });
}
