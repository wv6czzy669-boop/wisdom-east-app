// Build 26 Phase 4F: structural proof that lib/sync_runtime/ (the runtime
// trigger/retry/lifecycle coordinator layer) stays inside its approved
// boundaries -- depends only on the already-approved sync layers, owns no
// Flutter lifecycle/widget code of its own, never touches the daily-access
// domain, never couples directly to a repository/service, never
// constructs the concrete CloudKit adapter, and is wired into the app from
// exactly the two disclosed production call sites
// (lib/services/app_services.dart, lib/main.dart) and nowhere else.
// Mirrors the discipline test/sync_orchestration/sync_orchestration_layering_test.dart,
// test/sync_integration/sync_integration_layering_test.dart, and
// test/sync_e2e/sync_e2e_layering_test.dart already establish for their
// own layers.
//
// Self-scan note (the exact mistake flagged after Phase 4E-5's own
// layering test tripped over its own forbidden-token string literals):
// every forbidden-token scan in this file iterates only files under
// `lib/sync_runtime/` -- production code. This guard file itself lives
// under `test/sync_runtime/`, a different directory entirely, so it is
// never a member of any list this file scans and can never trip its own
// checks. No self-exclusion mechanism is therefore needed here (unlike
// `sync_e2e_layering_test.dart`, which scans `test/sync_e2e/` -- the same
// directory it lives in).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
  late Directory runtimeDir;
  late List<File> runtimeFiles;
  late List<File> allLibFiles;

  setUpAll(() {
    runtimeDir = Directory('lib/sync_runtime');
    expect(
      runtimeDir.existsSync(),
      isTrue,
      reason: 'Expected lib/sync_runtime to exist relative to the package '
          'root (the directory flutter test runs from).',
    );
    runtimeFiles = runtimeDir
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

  test(
      '1. every file scanned is a real, non-empty pure-Dart source file '
      '(the checks below are not vacuously passing over zero files)', () {
    expect(runtimeFiles, isNotEmpty);
    for (final file in runtimeFiles) {
      expect(file.readAsStringSync().trim(), isNotEmpty);
    }
  });

  test(
      '2. lib/sync_runtime/ only imports dart:, itself, the already-'
      'approved sync_integration/sync_orchestration/sync_persistence/'
      'sync_platform layers, (Build 26 Phase 4G, temporary diagnostics '
      'only) lib/utils/kept_diagnostics.dart, or (Build 26 Phase 5, the '
      'deletion-transaction recovery pipeline CloudKitSyncRuntimeCoordinator '
      'drives at the start of every pass) lib/sync_deletion/ -- never '
      'lib/sync/ directly, never repositories/services/screens/widgets', () {
    const allowedPrefixes = [
      'dart:',
      'package:wisdom_app/sync_runtime/',
      'package:wisdom_app/sync_integration/',
      'package:wisdom_app/sync_orchestration/',
      'package:wisdom_app/sync_persistence/',
      'package:wisdom_app/sync_platform/',
      // Build 26 Phase 4G: a narrow, temporary allowance for
      // keptDiagnostic(...) debug-only logging (see
      // cloud_kit_sync_runtime_coordinator.dart's own inline comments) --
      // never a broad `lib/utils/` exemption for anything else. Mirrors the
      // identical `../utils/`/`package:wisdom_app/utils/` allowance
      // test/sync_integration/sync_integration_layering_test.dart already
      // grants that layer.
      'package:wisdom_app/utils/kept_diagnostics.dart',
      // Build 26 Phase 5: sync_deletion is now an intentional sibling layer
      // -- CloudKitRemoteDeletionRunner and LocalDeletionFinalizer, which
      // CloudKitSyncRuntimeCoordinator constructs and drives for "Remove
      // from iCloud" transaction recovery. Not a broad exemption: only the
      // sync_deletion/ directory itself, same discipline as every other
      // approved sibling layer in this same list.
      'package:wisdom_app/sync_deletion/',
    ];

    final violations = <String>[];
    for (final file in runtimeFiles) {
      for (final line in file.readAsLinesSync()) {
        final trimmed = line.trimLeft();
        if (!trimmed.startsWith('import ') && !trimmed.startsWith('export ')) {
          continue;
        }
        final match = RegExp(r'''['"]([^'"]+)['"]''').firstMatch(trimmed);
        if (match == null) continue;
        final target = match.group(1)!;
        final isApprovedRelative = target.startsWith('../sync_integration/') ||
            target.startsWith('../sync_orchestration/') ||
            target.startsWith('../sync_persistence/') ||
            target.startsWith('../sync_platform/') ||
            target.startsWith('../sync_deletion/') ||
            target == '../utils/kept_diagnostics.dart' ||
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
      '3. lib/sync_runtime/ never imports the concrete '
      'method_channel_cloud_kit_platform_bridge.dart adapter and never '
      'references MethodChannelCloudKitPlatformBridge in code -- it depends '
      'on the abstract CloudKitPlatformBridge contract only (restated here '
      'as this layer\'s own regression guard, alongside the equivalent '
      'check test/sync_platform/cloud_kit_platform_privacy_test.dart '
      'already enforces)', () {
    final violations = <String>[];
    for (final file in runtimeFiles) {
      for (final line in file.readAsLinesSync()) {
        final trimmed = line.trimLeft();
        if ((trimmed.startsWith('import ') || trimmed.startsWith('export ')) &&
            trimmed.contains('method_channel_cloud_kit_platform_bridge.dart')) {
          violations.add('${file.path}: "$trimmed"');
        }
      }
      final codeOnly = _stripComments(file.readAsStringSync());
      if (codeOnly.contains('MethodChannelCloudKitPlatformBridge')) {
        violations.add(
          '${file.path} references MethodChannelCloudKitPlatformBridge in '
          'real code',
        );
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test(
      '4. lib/sync_runtime/ owns no Flutter widget/lifecycle code of its '
      'own -- never imports package:flutter/, never mentions '
      'WidgetsBindingObserver, AppLifecycleState, or BuildContext; '
      'lib/main.dart alone owns the real AppLifecycleState subscription', () {
    const forbiddenSubstrings = [
      'WidgetsBindingObserver',
      'AppLifecycleState',
      'BuildContext',
      'StatelessWidget',
      'StatefulWidget',
    ];
    final violations = <String>[];
    for (final file in runtimeFiles) {
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
      '5. lib/sync_runtime/ carries zero daily-access dependency -- no '
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
    for (final file in runtimeFiles) {
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
      '6. lib/sync_runtime/ never references KeptRepository or '
      'SavedReflectionsService directly -- the Build 26 Phase 4F fast-follow '
      'local-mutation nudge is wired entirely through '
      'KeptSyncIntegrationCoordinator\'s own payload-free '
      'onMutationCommitted callback, composed only in app_services.dart; '
      'the runtime coordinator itself still only ever calls the four '
      'already-existing coordinator/orchestrator APIs, never a repository '
      'or service directly', () {
    const forbiddenSubstrings = [
      'KeptRepository',
      'SavedReflectionsService',
    ];
    final violations = <String>[];
    for (final file in runtimeFiles) {
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
      '7. CloudKitSyncRuntimeCoordinator.requestSync is called only from '
      'lib/main.dart (startup + foreground triggers), from within '
      'lib/sync_runtime/ itself (the retry timer and the account-change '
      'handler), and from lib/services/app_services.dart (the Build 26 '
      'Phase 4F fast-follow local-mutation nudge, wired as a fire-and-forget '
      'closure passed to KeptSyncIntegrationCoordinator\'s '
      'onMutationCommitted callback) -- no repository, screen, or widget '
      'file calls it directly, and no Keep/Reflection/Remove call site '
      'references SyncRuntimeTrigger or requestSync itself (see the '
      'dedicated sync_integration_layering_test.dart guards for the '
      'screen/widget and sync_integration import-direction proofs)', () {
    const allowedCallerSuffixes = {
      'lib/main.dart',
      'lib/sync_runtime/cloud_kit_sync_runtime_coordinator.dart',
      'lib/services/app_services.dart',
    };
    final violations = <String>[];
    for (final file in allLibFiles) {
      final normalizedPath = file.path.replaceAll('\\', '/');
      if (allowedCallerSuffixes.any(normalizedPath.endsWith)) continue;
      final codeOnly = _stripComments(file.readAsStringSync());
      if (codeOnly.contains('.requestSync(')) {
        violations.add('${file.path} contains ".requestSync("');
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test(
      '8. CloudKitSyncRuntimeCoordinator is constructed in exactly one '
      'production file (lib/services/app_services.dart) -- no screen, '
      'widget, or other service file constructs a second, competing '
      'runtime coordinator instance', () {
    const appServicesPath = 'lib/services/app_services.dart';
    final violations = <String>[];
    for (final file in allLibFiles) {
      final normalizedPath = file.path.replaceAll('\\', '/');
      if (normalizedPath.contains('/sync_runtime/')) continue;
      if (normalizedPath.endsWith(appServicesPath)) continue;
      final codeOnly = _stripComments(file.readAsStringSync());
      if (codeOnly.contains('CloudKitSyncRuntimeCoordinator(')) {
        violations.add(
          '${file.path} constructs a CloudKitSyncRuntimeCoordinator',
        );
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test(
      '9. lib/sync_runtime/ never references a raw CloudKit MethodChannel/'
      'EventChannel by name, and never mentions a raw CloudKit record/'
      'operation type -- every CloudKit interaction goes through the '
      'existing CloudKitPlatformBridge/CloudKitAccountChangeEvent '
      'abstractions only', () {
    const forbiddenSubstrings = [
      'MethodChannel(',
      'EventChannel(',
      'invokeMethod',
      'com.dogukan.dailywisdom/cloudkit_sync',
      'CKRecord',
      'CKModifyRecordsOperation',
      'CKFetchRecordZoneChangesOperation',
    ];
    final violations = <String>[];
    for (final file in runtimeFiles) {
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
      '10. CloudKitSyncRuntimeStatus.toLogSafeSummary\'s own source never '
      'declares a privacy-forbidden field name as one of its exposed keys '
      '-- fingerprint, dataEpoch, server token, systemFields, recordName, '
      'revealId, localId, intentId, mutationId, wisdom/Reflection text, or '
      'a raw timestamp/path field are never part of the log-safe summary '
      'map (best-effort static check on the map-literal source text; the '
      'coordinator test file\'s own runtime assertion on the map\'s actual '
      'key set is the authoritative proof)', () {
    const forbiddenFieldNameSubstrings = [
      'fingerprint',
      'dataEpoch',
      'serverToken',
      'systemFields',
      'recordName',
      'revealId',
      'localId',
      'intentId',
      'mutationId',
      'wisdomText',
      'reflectionText',
      'timestamp',
    ];
    final statusFile = File(
      'lib/sync_runtime/cloud_kit_sync_runtime_coordinator.dart',
    );
    expect(statusFile.existsSync(), isTrue);
    final codeOnly = _stripComments(statusFile.readAsStringSync());

    // Isolate just the toLogSafeSummary method body -- this test's intent
    // is narrowly "the exposed summary map never carries a forbidden
    // field," not "the file never mentions these words anywhere" (the
    // library doc comment's own privacy section legitimately names every
    // one of them as an example of what must never appear).
    final methodStart =
        codeOnly.indexOf('Map<String, Object?> toLogSafeSummary');
    expect(methodStart, greaterThanOrEqualTo(0),
        reason: 'Expected to find toLogSafeSummary in $statusFile.');
    final bodyStart = codeOnly.indexOf('{', methodStart);
    final bodyEnd = codeOnly.indexOf('};', bodyStart);
    final methodBody = codeOnly.substring(bodyStart, bodyEnd);

    final violations = <String>[
      for (final forbidden in forbiddenFieldNameSubstrings)
        if (methodBody.toLowerCase().contains(forbidden.toLowerCase()))
          'toLogSafeSummary body contains "$forbidden"',
    ];
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test(
      '11. SyncRuntimeTrigger.localMutation (Build 26 Phase 4F fast-follow) '
      'exists, and none of the four outcome-classification methods -- which '
      'together define every retry/account/bootstrap/epoch-recovery '
      'decision this coordinator ever makes -- reference the trigger '
      'parameter at all, proving localMutation is classified through the '
      'exact same pipeline as every other trigger with no special-cased '
      'behavior of its own', () {
    final coordinatorFile = File(
      'lib/sync_runtime/cloud_kit_sync_runtime_coordinator.dart',
    );
    expect(coordinatorFile.existsSync(), isTrue);
    final source = coordinatorFile.readAsStringSync();
    final codeOnly = _stripComments(source);

    expect(
        codeOnly.contains('localMutation,') ||
            codeOnly.contains('localMutation;'),
        isTrue,
        reason: 'Expected SyncRuntimeTrigger to declare a localMutation '
            'member.');

    const classificationMethods = [
      'SyncRuntimeOutcome _classifyBootstrapStopStatus(BootstrapRunStatus status)',
      'SyncRuntimeOutcome _classifySyncPassStopStatus(SyncPassStatus status)',
      'SyncRuntimeOutcome _classifyIncomingApplyStatus(IncomingApplyStatus status)',
    ];
    final violations = <String>[];
    for (final signature in classificationMethods) {
      final start = codeOnly.indexOf(signature);
      expect(start, greaterThanOrEqualTo(0),
          reason: 'Expected to find "$signature" in $coordinatorFile.');
      final bodyStart = codeOnly.indexOf('{', start);
      expect(bodyStart, greaterThanOrEqualTo(0),
          reason: 'Expected to find the opening brace for "$signature".');
      // Each of these methods is an ordinary `switch (status) { ... }`
      // statement, not a `=>` expression -- brace-match to find the
      // method's own real closing brace, never merely the first `;`
      // (which would stop inside the very first `case` and silently miss
      // a violation appearing later in the body).
      var depth = 0;
      var bodyEnd = -1;
      for (var i = bodyStart; i < codeOnly.length; i++) {
        if (codeOnly[i] == '{') depth++;
        if (codeOnly[i] == '}') {
          depth--;
          if (depth == 0) {
            bodyEnd = i;
            break;
          }
        }
      }
      expect(bodyEnd, greaterThan(bodyStart),
          reason: 'Expected to find the matching closing brace for '
              '"$signature".');
      final body = codeOnly.substring(bodyStart, bodyEnd + 1);
      if (body.contains('trigger')) {
        violations.add('$signature references "trigger" in its own body');
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));

    // `_finishPass` itself (called with only an outcome, never a trigger)
    // is the other place a special case could hide -- confirm its own
    // signature never takes a trigger argument.
    final finishPassSignatureMatch =
        RegExp(r'void _finishPass\(([^)]*)\)').firstMatch(codeOnly);
    expect(finishPassSignatureMatch, isNotNull,
        reason: 'Expected to find _finishPass in $coordinatorFile.');
    expect(finishPassSignatureMatch!.group(1), isNot(contains('trigger')),
        reason: '_finishPass must not take a trigger parameter -- outcome '
            'classification must never special-case by trigger.');
  });
}
