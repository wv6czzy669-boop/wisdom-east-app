// Build 26 Phase 4E-5: structural proof that the synthetic end-to-end
// CloudKit sync test harness under test/sync_e2e/ remains strictly
// test-only, never couples into production code, never touches the
// daily-access domain, never installs an automatic trigger of its own, and
// never causes any NEW production invocation of a sync/bootstrap trigger API
// to appear merely because this harness exists. Mirrors the discipline
// test/sync_integration/sync_integration_layering_test.dart,
// test/sync_platform/cloud_kit_platform_privacy_test.dart, and
// test/sync/sync_domain_privacy_test.dart already establish for their own
// layers. Synthetic content only; no real MethodChannel or CloudKit access
// anywhere in this file.
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

/// This structural guard file's own path, relative to the package root,
/// normalized to forward slashes -- the exact one file the
/// implementation-file scans below must exclude, and the exact one file
/// [_isSelfScanExemptFromForbiddenTokenScans] must match against. Declared
/// once, top-level, so every scan below (and this file's own positive
/// coverage guard) agree on precisely the same path -- never a second,
/// slightly-different literal.
const String _selfPath = 'test/sync_e2e/sync_e2e_layering_test.dart';

/// `true` only for this structural guard file itself. The daily-access,
/// lifecycle-listener, and MethodChannel/native-CloudKit scans below define
/// their own forbidden-token lists as Dart string literals -- and
/// [_stripComments] deliberately leaves string literals untouched (exactly
/// as every other layering test's own copy of it does), so this file's own
/// source necessarily *contains* the very tokens it forbids elsewhere. That
/// makes this file, and only this file, a structural false positive against
/// those three scans -- never a real end-to-end implementation file, and
/// never exempted from the two scans above (file-non-empty, no `lib/`
/// import) or the trigger-API scan below, none of which this file could
/// ever spuriously trip.
bool _isSelfScanExemptFromForbiddenTokenScans(File file) {
  return file.path.replaceAll('\\', '/').endsWith(_selfPath);
}

void main() {
  late Directory e2eDir;
  late List<File> e2eFiles;
  late List<File> e2eImplementationFiles;
  late Directory libDir;
  late List<File> allLibFiles;

  setUpAll(() {
    e2eDir = Directory('test/sync_e2e');
    expect(
      e2eDir.existsSync(),
      isTrue,
      reason: 'Expected test/sync_e2e to exist relative to the package '
          'root (the directory flutter test runs from).',
    );
    e2eFiles = e2eDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();

    // The forbidden-token scans below (daily-access, lifecycle listener,
    // MethodChannel/native CloudKit) must inspect every real E2E
    // implementation/test file -- but never this structural guard file
    // itself, whose own source unavoidably quotes those same tokens as the
    // literal strings it scans for. This excludes ONLY that one exact file
    // by normalized path -- never the whole directory, and never any other
    // current or future `test/sync_e2e/` file.
    e2eImplementationFiles = e2eFiles
        .where((file) => !_isSelfScanExemptFromForbiddenTokenScans(file))
        .toList();

    // Positive coverage guard: the exclusion above must never silently
    // degrade these scans into an empty (vacuously-passing) no-op. Exactly
    // one file (this guard file itself) is removed, and every currently
    // known real E2E implementation file must still be present.
    expect(
      e2eImplementationFiles.length,
      e2eFiles.length - 1,
      reason: 'Expected the forbidden-token scans\' candidate set to drop '
          'exactly one file (this structural guard file itself) relative '
          'to the full test/sync_e2e/ file list.',
    );
    expect(
      e2eImplementationFiles.any(_isSelfScanExemptFromForbiddenTokenScans),
      isFalse,
      reason: 'The structural guard file itself must never appear in its '
          'own forbidden-token scan candidate set.',
    );
    const expectedImplementationFileSuffixes = [
      'test/sync_e2e/synthetic_cloudkit_server.dart',
      'test/sync_e2e/sync_device_harness.dart',
      'test/sync_e2e/cloudkit_sync_e2e_test.dart',
    ];
    for (final suffix in expectedImplementationFileSuffixes) {
      expect(
        e2eImplementationFiles.any(
          (file) => file.path.replaceAll('\\', '/').endsWith(suffix),
        ),
        isTrue,
        reason: 'Expected the forbidden-token scans\' candidate set to '
            'still include "$suffix" -- the exclusion above must remove '
            'only this guard file, never a real E2E implementation file.',
      );
    }

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
    expect(e2eFiles.length, greaterThanOrEqualTo(4));
    for (final file in e2eFiles) {
      expect(file.readAsStringSync().trim(), isNotEmpty);
    }
  });

  test(
      'test/sync_e2e/ remains test-only: no production file under lib/ '
      'imports or exports anything from test/sync_e2e/', () {
    final violations = <String>[];
    for (final file in allLibFiles) {
      for (final line in file.readAsLinesSync()) {
        final trimmed = line.trimLeft();
        if (!trimmed.startsWith('import ') && !trimmed.startsWith('export ')) {
          continue;
        }
        if (trimmed.contains('sync_e2e')) {
          violations.add('${file.path}: "$trimmed"');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test(
      'no file under test/sync_e2e/ imports, exports, or references the '
      'daily-access domain in any way', () {
    const forbiddenReferences = [
      'daily_wisdom_access',
      'daily_wisdom_text',
      'wisdom_unlock_time_ms',
      'keeper_daily_wisdom_state',
      'unlockAt',
      'DailyAccessRepository',
      'daily_access_repository.dart',
      'DailyWisdomRecord',
      'DailyWisdomAccessService',
      'daily_wisdom_access_service.dart',
    ];

    final violations = <String>[];
    for (final file in e2eImplementationFiles) {
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
      'no file under test/sync_e2e/ installs a startup, foreground, '
      'lifecycle, or automatic network/account-change listener of its own', () {
    const forbiddenPatterns = [
      'WidgetsBindingObserver',
      'WidgetsBinding.instance',
      'Timer.periodic',
      'accountChangeEvents.listen(',
      'didChangeAppLifecycleState',
    ];

    final violations = <String>[];
    for (final file in e2eImplementationFiles) {
      final codeOnly = _stripComments(file.readAsStringSync());
      for (final pattern in forbiddenPatterns) {
        if (codeOnly.contains(pattern)) {
          violations.add('${file.path} contains "$pattern"');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test(
      'no file under test/sync_e2e/ constructs a MethodChannel/EventChannel '
      'or references a raw CloudKit wire/native transport type -- every '
      'CloudKit interaction goes through the real CloudKitPlatformBridge '
      'interface and the synthetic server only', () {
    const forbiddenSubstrings = [
      'MethodChannel(',
      'EventChannel(',
      'invokeMethod',
      'CKRecord',
      'CKModifyRecordsOperation',
      'CKFetchRecordZoneChangesOperation',
      'MethodChannelCloudKitPlatformBridge',
    ];

    final violations = <String>[];
    for (final file in e2eImplementationFiles) {
      final codeOnly = _stripComments(file.readAsStringSync());
      for (final forbidden in forbiddenSubstrings) {
        if (codeOnly.contains(forbidden)) {
          violations.add('${file.path} contains "$forbidden"');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test(
      'every production invocation of a sync/bootstrap trigger API anywhere '
      'under lib/ is confined to that API\'s own definition file, the '
      'single Build 26 Phase 4F runtime coordinator, or (Build 26 Phase 4G, '
      'evaluateAssociation/authorizeAssociation only) the one approved '
      'explicit-association controller -- '
      'evaluateAssociation/authorizeAssociation remain callable by exactly '
      'that one disclosed extra caller and no other; '
      'repairLegacyAssociationMarker remains callable but uncalled by any '
      'production code path outside its own definition file (Phase 4F never '
      'calls it directly -- runBootstrap() already owns that decision tree '
      'internally); '
      'runBootstrap/reconcileForAssociatedAccount/applyIncomingBatch/'
      'runSyncPass are each called by exactly one production file beyond '
      'their own definition -- '
      'lib/sync_runtime/cloud_kit_sync_runtime_coordinator.dart -- and by no '
      'other production file. This test harness (test/sync_e2e/, already '
      'proven test-only above) and existing coordinator-level test suites '
      'may call any of them freely; this test only ever scans lib/.', () {
    const runtimeCoordinatorFile =
        'lib/sync_runtime/cloud_kit_sync_runtime_coordinator.dart';
    // Build 26 Phase 4G correction (post-Mac-validation): this test predates
    // the explicitly-approved one-time iCloud association UX, which
    // introduced exactly one new, disclosed production caller of
    // evaluateAssociation()/authorizeAssociation() outside
    // kept_sync_bootstrap_coordinator.dart itself --
    // lib/controllers/sync_association_controller.dart (Settings' only
    // association surface; see its own doc comment, and
    // test/sync_integration/sync_integration_layering_test.dart's matching
    // exact-file allowance for this same pair of methods). This is an
    // exact, single-file addition scoped to these two patterns only --
    // never a directory-wide exemption for lib/controllers/, and it does
    // not extend to repairLegacyAssociationMarker or to the runtime
    // coordinator for any of the four association/bootstrap patterns below.
    const syncAssociationControllerFile =
        'lib/controllers/sync_association_controller.dart';

    // Pattern -> (own definition file, whether the Phase 4F runtime
    // coordinator is also an allowed caller, and any further exact-file
    // allowances beyond those two). `evaluateAssociation`/
    // `authorizeAssociation`/`repairLegacyAssociationMarker` are NOT
    // extended to the runtime coordinator: `CloudKitSyncRuntimeCoordinator`
    // only ever calls `runBootstrap()` itself, which already owns the full
    // association decision tree internally -- calling any of these three
    // directly from the runtime coordinator would duplicate that decision.
    const triggerCallSpecs = {
      '.runBootstrap(': (
        ownFile: 'lib/sync_integration/kept_sync_bootstrap_coordinator.dart',
        runtimeCoordinatorAllowed: true,
        extraAllowedFiles: <String>{},
      ),
      '.evaluateAssociation(': (
        ownFile: 'lib/sync_integration/kept_sync_bootstrap_coordinator.dart',
        runtimeCoordinatorAllowed: false,
        extraAllowedFiles: {syncAssociationControllerFile},
      ),
      '.authorizeAssociation(': (
        ownFile: 'lib/sync_integration/kept_sync_bootstrap_coordinator.dart',
        runtimeCoordinatorAllowed: false,
        extraAllowedFiles: {syncAssociationControllerFile},
      ),
      '.repairLegacyAssociationMarker(': (
        ownFile: 'lib/sync_integration/kept_sync_bootstrap_coordinator.dart',
        runtimeCoordinatorAllowed: false,
        extraAllowedFiles: <String>{},
      ),
      '.reconcileForAssociatedAccount(': (
        ownFile: 'lib/sync_integration/kept_sync_integration_coordinator.dart',
        runtimeCoordinatorAllowed: true,
        extraAllowedFiles: <String>{},
      ),
      '.applyIncomingBatch(': (
        ownFile: 'lib/sync_integration/incoming_kept_sync_coordinator.dart',
        runtimeCoordinatorAllowed: true,
        extraAllowedFiles: <String>{},
      ),
      '.runSyncPass(': (
        ownFile: 'lib/sync_orchestration/sync_orchestrator.dart',
        runtimeCoordinatorAllowed: true,
        extraAllowedFiles: <String>{},
      ),
    };

    final violations = <String>[];
    for (final file in allLibFiles) {
      final normalizedPath = file.path.replaceAll('\\', '/');
      final codeOnly = _stripComments(file.readAsStringSync());
      triggerCallSpecs.forEach((pattern, spec) {
        if (normalizedPath.endsWith(spec.ownFile)) return;
        if (spec.runtimeCoordinatorAllowed &&
            normalizedPath.endsWith(runtimeCoordinatorFile)) {
          return;
        }
        if (spec.extraAllowedFiles
            .any((allowed) => normalizedPath.endsWith(allowed))) {
          return;
        }
        if (codeOnly.contains(pattern)) {
          violations.add('${file.path} contains "$pattern"');
        }
      });
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });
}
