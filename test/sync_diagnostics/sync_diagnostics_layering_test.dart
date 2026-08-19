// Build 26: Sync Diagnostics / Safe Recovery core -- structural proof that
// lib/sync_diagnostics/ stays inside its approved boundaries. Mirrors the
// discipline test/sync_runtime/sync_runtime_layering_test.dart already
// establishes for its own layer.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Strips `//`, `///`, and `/* */` comments while leaving string literals
/// untouched -- a self-contained copy of the same test-only tooling every
/// other layering test in this codebase keeps its own independent copy of.
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
  late Directory diagnosticsDir;
  late List<File> diagnosticsFiles;
  late List<File> allLibFiles;

  setUpAll(() {
    diagnosticsDir = Directory('lib/sync_diagnostics');
    expect(
      diagnosticsDir.existsSync(),
      isTrue,
      reason: 'Expected lib/sync_diagnostics to exist relative to the '
          'package root (the directory flutter test runs from).',
    );
    diagnosticsFiles = diagnosticsDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();

    allLibFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();
  });

  test('1. every file scanned is a real, non-empty pure-Dart source file', () {
    expect(diagnosticsFiles, isNotEmpty);
    for (final file in diagnosticsFiles) {
      expect(file.readAsStringSync().trim(), isNotEmpty);
    }
  });

  test(
      '2. lib/sync_diagnostics/ only imports dart:, itself, or the '
      'already-approved sync_persistence/sync_platform/sync_runtime layers '
      '-- never lib/sync/, sync_integration/, sync_orchestration/, or '
      'sync_deletion/ directly, and never repositories/services/screens/'
      'widgets', () {
    const allowedPrefixes = [
      'dart:',
      'package:wisdom_app/sync_diagnostics/',
      'package:wisdom_app/sync_persistence/',
      'package:wisdom_app/sync_platform/',
      'package:wisdom_app/sync_runtime/',
    ];
    final violations = <String>[];
    for (final file in diagnosticsFiles) {
      for (final line in file.readAsLinesSync()) {
        final trimmed = line.trimLeft();
        if (!trimmed.startsWith('import ') && !trimmed.startsWith('export ')) {
          continue;
        }
        final match = RegExp(r'''['"]([^'"]+)['"]''').firstMatch(trimmed);
        if (match == null) continue;
        final target = match.group(1)!;
        final isApprovedRelative = target.startsWith('../sync_persistence/') ||
            target.startsWith('../sync_platform/') ||
            target.startsWith('../sync_runtime/') ||
            !target.contains('/'); // same-directory sibling import
        final isApprovedPackage = allowedPrefixes.any(target.startsWith);
        if (!isApprovedRelative && !isApprovedPackage) {
          violations.add('${file.path}: "$trimmed"');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test(
      '3. lib/sync_diagnostics/ owns no Flutter widget/lifecycle code of '
      'its own, and never references a raw CloudKit MethodChannel/'
      'EventChannel or the concrete method-channel bridge adapter', () {
    const forbiddenSubstrings = [
      'WidgetsBindingObserver',
      'AppLifecycleState',
      'BuildContext',
      'StatelessWidget',
      'StatefulWidget',
      'MethodChannel(',
      'EventChannel(',
      'invokeMethod',
      'MethodChannelCloudKitPlatformBridge',
      'CKRecord',
    ];
    final violations = <String>[];
    for (final file in diagnosticsFiles) {
      for (final line in file.readAsLinesSync()) {
        final trimmed = line.trimLeft();
        if ((trimmed.startsWith('import ') || trimmed.startsWith('export ')) &&
            trimmed.contains('package:flutter/')) {
          violations.add('${file.path}: "$trimmed"');
        }
      }
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
      '4. lib/sync_diagnostics/ carries zero daily-access dependency -- no '
      'import, reference, or read/write of any daily-access key, type, or '
      'the rolling 24-hour ritual domain', () {
    const forbiddenSubstrings = [
      'daily_wisdom_access',
      'daily_wisdom_text',
      'wisdom_unlock_time_ms',
      'keeper_daily_wisdom_state',
      'unlockAt',
      'lockDuration',
      'DailyAccessRepository',
      'daily_access_repository.dart',
      'DailyWisdomRecord',
      'DailyWisdomAccessService',
      'daily_wisdom_access_service.dart',
      'pending_daily_wisdom_reveal',
      'PendingDailyWisdomReveal',
    ];
    final violations = <String>[];
    for (final file in diagnosticsFiles) {
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
      '5. lib/sync_diagnostics/ never calls CloudKitSyncRuntimeCoordinator'
      '.requestSync directly -- SyncRecoveryCoordinator only ever calls its '
      'own caller-supplied triggerRecoverySync callback (see its own doc '
      'comment for why); only lib/main.dart, '
      'lib/sync_runtime/cloud_kit_sync_runtime_coordinator.dart, and '
      'lib/services/app_services.dart may ever call ".requestSync(", per '
      'test/sync_runtime/sync_runtime_layering_test.dart\'s own allowlist', () {
    final violations = <String>[];
    for (final file in diagnosticsFiles) {
      final codeOnly = _stripComments(file.readAsStringSync());
      if (codeOnly.contains('.requestSync(')) {
        violations.add('${file.path} contains ".requestSync("');
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test(
      '6. SyncHealthEvaluator and SyncRecoveryCoordinator are each '
      'constructed in exactly one production file '
      '(lib/services/app_services.dart) -- no screen, widget, or other '
      'service file constructs a second, competing instance', () {
    const appServicesPath = 'lib/services/app_services.dart';
    final violations = <String>[];
    for (final file in allLibFiles) {
      final normalizedPath = file.path.replaceAll('\\', '/');
      if (normalizedPath.contains('/sync_diagnostics/')) continue;
      if (normalizedPath.endsWith(appServicesPath)) continue;
      final codeOnly = _stripComments(file.readAsStringSync());
      if (codeOnly.contains('SyncHealthEvaluator(')) {
        violations.add('${file.path} constructs a SyncHealthEvaluator');
      }
      if (codeOnly.contains('SyncRecoveryCoordinator(')) {
        violations.add('${file.path} constructs a SyncRecoveryCoordinator');
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test(
      '7. no screen or widget file references SyncHealthEvaluator, '
      'SyncRecoveryCoordinator, SyncHealthSnapshot, or SyncHealthState -- '
      'this phase adds no Settings diagnostics screen or any other '
      'user-facing surface for this core', () {
    const forbiddenSubstrings = [
      'SyncHealthEvaluator',
      'SyncRecoveryCoordinator',
      'SyncHealthSnapshot',
      'SyncHealthState',
    ];
    final violations = <String>[];
    for (final file in allLibFiles) {
      final normalizedPath = file.path.replaceAll('\\', '/');
      if (!normalizedPath.contains('/screens/') &&
          !normalizedPath.contains('/widgets/')) {
        continue;
      }
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
