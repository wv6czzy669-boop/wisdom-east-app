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
      'directive referencing the sync_platform layer, EXCEPT '
      'kept_sync_bootstrap_coordinator.dart -- Build 26 Phase 4E-4\'s '
      'existing-user remote-first bootstrap is the one deliberate, '
      'disclosed exception to this prior-phase invariant: it alone must '
      'call the real CloudKit transport primitives '
      '(getAccountSnapshot/configurePrivateZone/fetchPrivateZoneChanges/'
      'modifyPrivateRecords) directly to perform its one-time remote '
      'baseline fetch -- never KeptSyncIntegrationCoordinator or '
      'IncomingKeptSyncCoordinator, which remain sync_platform-free exactly '
      'as before', () {
    const allowedFiles = {
      'lib/sync_integration/kept_sync_bootstrap_coordinator.dart',
    };
    final violations = <String>[];
    for (final file in integrationFiles) {
      final normalizedPath = file.path.replaceAll('\\', '/');
      final isAllowed =
          allowedFiles.any((allowed) => normalizedPath.endsWith(allowed));
      if (isAllowed) continue;
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
      'sync_persistence, sync, persistence, utils, or the exact narrow '
      'Phase 4E-2 KeptRepository/model dependency -- never any other '
      'repository, services, screens, or widgets', () {
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
      // Build 26 Phase 4E-2: KeptSyncIntegrationCoordinator composes
      // KeptRepository with the durable sync layers from the outside, per
      // the locked dependency direction (sync_integration -> KeptRepository
      // / domain models -- never the reverse). These are deliberately exact,
      // full-path allowances, never a broad `../models/` or
      // `../repositories/` directory exemption -- no other model or
      // repository file may be imported here without its own explicit,
      // justified addition to this list.
      '../models/favorite_item.dart',
      '../models/kept_record.dart',
      '../repositories/kept_repository.dart',
      'package:wisdom_app/models/favorite_item.dart',
      'package:wisdom_app/models/kept_record.dart',
      'package:wisdom_app/repositories/kept_repository.dart',
      // Build 26 Phase 4E-3b: `IncomingKeptSyncCoordinator` consumes
      // `PendingIncomingSyncBatch` -- a single, exact, full-path allowance
      // for this one type's own definition file, never a broad
      // `../sync_orchestration/` directory exemption. Mirrors
      // `test/sync_orchestration/sync_orchestration_layering_test.dart`'s own
      // matching exception for this same, disclosed dependency.
      '../sync_orchestration/pending_incoming_sync_batch.dart',
      'package:wisdom_app/sync_orchestration/pending_incoming_sync_batch.dart',
      // Bare same-directory relative imports (this codebase's own
      // sync_integration files importing one another directly).
      'local_sync_intent',
      'protected_local_sync_intent_store.dart',
      'kept_sync_integration_coordinator.dart',
    ];

    // Build 26 Phase 4E-4: kept_sync_bootstrap_coordinator.dart alone may
    // additionally import from sync_platform -- see the dedicated
    // sync_platform-exception test immediately above for the full
    // rationale. This is an exact, single-file addition, never a directory-
    // wide loosening of the allowlist above.
    const bootstrapCoordinatorAdditionalPrefixes = [
      '../sync_platform/',
      'package:wisdom_app/sync_platform/',
    ];
    const bootstrapCoordinatorFile =
        'lib/sync_integration/kept_sync_bootstrap_coordinator.dart';

    final violations = <String>[];
    for (final file in integrationFiles) {
      final normalizedPath = file.path.replaceAll('\\', '/');
      final effectivePrefixes =
          normalizedPath.endsWith(bootstrapCoordinatorFile)
              ? [...allowedPrefixes, ...bootstrapCoordinatorAdditionalPrefixes]
              : allowedPrefixes;
      for (final line in file.readAsLinesSync()) {
        final trimmed = line.trimLeft();
        if (!trimmed.startsWith('import ') && !trimmed.startsWith('export ')) {
          continue;
        }
        final match = RegExp(r'''['"]([^'"]+)['"]''').firstMatch(trimmed);
        if (match == null) continue;
        final target = match.group(1)!;
        final isAllowed =
            effectivePrefixes.any((prefix) => target.startsWith(prefix));
        if (!isAllowed) {
          violations.add('${file.path}: "$trimmed"');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test(
      'no MethodChannel/EventChannel invocation and no raw CloudKit wire/'
      'native transport type exists anywhere under lib/sync_integration/ '
      '(in real code, not comments) -- Build 26 Phase 4E-4: '
      'kept_sync_bootstrap_coordinator.dart alone may call the '
      'CloudKitPlatformBridge interface\'s own modifyPrivateRecords/'
      'fetchPrivateZoneChanges methods (never MethodChannel/EventChannel '
      'directly, never a raw CKRecord/wire-envelope type), since it alone '
      'performs the one-time remote baseline fetch', () {
    const alwaysForbiddenSubstrings = [
      'MethodChannel(',
      'EventChannel(',
      'invokeMethod',
      'CKRecord',
      'CKModifyRecordsOperation',
      'CKFetchRecordZoneChangesOperation',
      'CloudKeptWisdomWireEnvelope',
      'MethodChannelCloudKitPlatformBridge',
    ];
    const onlyForbiddenOutsideBootstrapCoordinator = [
      'modifyPrivateRecords',
      'fetchPrivateZoneChanges',
    ];
    const bootstrapCoordinatorFile =
        'lib/sync_integration/kept_sync_bootstrap_coordinator.dart';

    final violations = <String>[];
    for (final file in integrationFiles) {
      final normalizedPath = file.path.replaceAll('\\', '/');
      final isBootstrapCoordinator =
          normalizedPath.endsWith(bootstrapCoordinatorFile);
      final codeOnly = _stripComments(file.readAsStringSync());
      for (final forbidden in alwaysForbiddenSubstrings) {
        if (codeOnly.contains(forbidden)) {
          violations.add('${file.path} contains "$forbidden" in code');
        }
      }
      if (!isBootstrapCoordinator) {
        for (final forbidden in onlyForbiddenOutsideBootstrapCoordinator) {
          if (codeOnly.contains(forbidden)) {
            violations.add('${file.path} contains "$forbidden" in code');
          }
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test(
      'KeptRepository still imports no CloudKit/sync-platform adapter, no '
      'sync_integration type, and no sync_persistence type -- the '
      'dependency direction is always sync_integration -> KeptRepository, '
      'never the reverse', () {
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
      // Build 26 Phase 4E-2: this is a permanent architectural invariant,
      // not a "not yet wired" placeholder -- KeptRepository remains
      // completely CloudKit/account/sync-unaware forever.
      // KeptSyncIntegrationCoordinator composes KeptRepository from the
      // outside; KeptRepository must never import sync_integration or
      // sync_persistence in either direction.
      expect(trimmed.contains('sync_integration'), isFalse,
          reason: 'kept_repository.dart must never import sync_integration: '
              '"$trimmed"');
      expect(trimmed.contains('sync_persistence'), isFalse,
          reason: 'kept_repository.dart must never import sync_persistence: '
              '"$trimmed"');
    }
  });

  test(
      'no startup, foreground, lifecycle, or network trigger anywhere under '
      'lib/ calls reconcileForAssociatedAccount, except '
      'KeptSyncIntegrationCoordinator\'s own definition file and the single '
      'Build 26 Phase 4F runtime coordinator '
      '(lib/sync_runtime/cloud_kit_sync_runtime_coordinator.dart)', () {
    final violations = <String>[];
    for (final file in allLibFiles) {
      final normalizedPath = file.path.replaceAll('\\', '/');
      if (normalizedPath.endsWith(
            'lib/sync_integration/kept_sync_integration_coordinator.dart',
          ) ||
          normalizedPath.endsWith(
            'lib/sync_runtime/cloud_kit_sync_runtime_coordinator.dart',
          )) {
        continue;
      }
      final codeOnly = _stripComments(file.readAsStringSync());
      if (codeOnly.contains('reconcileForAssociatedAccount(')) {
        violations.add(file.path);
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test(
      'no startup, foreground, lifecycle, or network trigger anywhere under '
      'lib/ calls applyIncomingBatch, except IncomingKeptSyncCoordinator\'s '
      'own definition file and the single Build 26 Phase 4F runtime '
      'coordinator (lib/sync_runtime/cloud_kit_sync_runtime_coordinator.dart)',
      () {
    final violations = <String>[];
    for (final file in allLibFiles) {
      final normalizedPath = file.path.replaceAll('\\', '/');
      if (normalizedPath.endsWith(
            'lib/sync_integration/incoming_kept_sync_coordinator.dart',
          ) ||
          normalizedPath.endsWith(
            'lib/sync_runtime/cloud_kit_sync_runtime_coordinator.dart',
          )) {
        continue;
      }
      final codeOnly = _stripComments(file.readAsStringSync());
      if (codeOnly.contains('applyIncomingBatch(')) {
        violations.add(file.path);
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test(
      'Build 26 Phase 4F: no startup, foreground, lifecycle, screen, '
      'widget, or network trigger anywhere under lib/ (outside '
      'kept_sync_bootstrap_coordinator.dart\'s own definition file -- '
      'app_services.dart only ever constructs the coordinator, it never '
      'calls any of these methods) calls evaluateAssociation/'
      'authorizeAssociation/repairLegacyAssociationMarker -- every one '
      'remains callable but uncalled by any production code path outside '
      'its own definition file; runBootstrap is additionally, and solely, '
      'called by the single Build 26 Phase 4F runtime coordinator '
      '(lib/sync_runtime/cloud_kit_sync_runtime_coordinator.dart), which '
      'never calls the other three directly (runBootstrap already owns '
      'that decision tree internally)', () {
    const neverCalledOutsideOwnFile = [
      '.evaluateAssociation(',
      '.authorizeAssociation(',
      '.repairLegacyAssociationMarker(',
    ];
    const runtimeCoordinatorFile =
        'lib/sync_runtime/cloud_kit_sync_runtime_coordinator.dart';
    final violations = <String>[];
    for (final file in allLibFiles) {
      final normalizedPath = file.path.replaceAll('\\', '/');
      final isOwnDefinitionFile = normalizedPath.endsWith(
        'lib/sync_integration/kept_sync_bootstrap_coordinator.dart',
      );
      final isRuntimeCoordinatorFile =
          normalizedPath.endsWith(runtimeCoordinatorFile);
      final codeOnly = _stripComments(file.readAsStringSync());
      if (!isOwnDefinitionFile) {
        for (final pattern in neverCalledOutsideOwnFile) {
          if (codeOnly.contains(pattern)) {
            violations.add('${file.path} contains "$pattern"');
          }
        }
      }
      if (!isOwnDefinitionFile &&
          !isRuntimeCoordinatorFile &&
          codeOnly.contains('.runBootstrap(')) {
        violations.add('${file.path} contains ".runBootstrap("');
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test(
      'Build 26 Phase 4E-4: app_services.dart constructs exactly one '
      'production KeptSyncBootstrapCoordinator, sharing the same '
      'syncIntegrationOperationCoordinator instance and resource key that '
      'KeptSyncIntegrationCoordinator/IncomingKeptSyncCoordinator use -- a '
      'positive proof that bootstrap, every outgoing user mutation, and '
      'every incoming-apply pass always serialize against each other', () {
    final matches = allLibFiles
        .where((file) => file.path
            .replaceAll('\\', '/')
            .endsWith('lib/services/app_services.dart'))
        .toList();
    expect(matches, hasLength(1),
        reason: 'Expected to find exactly one app_services.dart under '
            'lib/services/.');
    final source = matches.single.readAsStringSync();

    final importsBootstrapCoordinator = source
        .split('\n')
        .map((line) => line.trimLeft())
        .where(
            (line) => line.startsWith('import ') || line.startsWith('export '))
        .any((line) => line.contains('kept_sync_bootstrap_coordinator.dart'));
    expect(importsBootstrapCoordinator, isTrue,
        reason: 'app_services.dart is expected to import '
            'kept_sync_bootstrap_coordinator.dart.');

    final codeOnly = _stripComments(source);
    expect(codeOnly.contains('KeptSyncBootstrapCoordinator('), isTrue,
        reason: 'app_services.dart is expected to construct '
            'KeptSyncBootstrapCoordinator directly.');
    // Exactly one construction call -- never a second, independently
    // configured instance elsewhere.
    final constructionCount =
        RegExp('KeptSyncBootstrapCoordinator\\(').allMatches(codeOnly).length;
    expect(constructionCount, 1,
        reason: 'Expected exactly one KeptSyncBootstrapCoordinator( '
            'construction call in app_services.dart.');
    expect(
      codeOnly.contains(
        'integrationCoordinator: syncIntegrationOperationCoordinator,',
      ),
      isTrue,
      reason: 'app_services.dart is expected to pass the shared '
          'syncIntegrationOperationCoordinator instance to every '
          'sync_integration coordinator, including the new bootstrap '
          'coordinator.',
    );
    // Confirm it is never called automatically from within app_services.dart
    // itself either.
    const automaticTriggerMethodCalls = [
      '.evaluateAssociation(',
      '.authorizeAssociation(',
      '.repairLegacyAssociationMarker(',
      '.runBootstrap(',
    ];
    for (final pattern in automaticTriggerMethodCalls) {
      expect(codeOnly.contains(pattern), isFalse,
          reason: 'app_services.dart must never call "$pattern" -- '
              'construction only.');
    }
  });

  test(
      'app_services.dart constructs exactly one production '
      'IncomingKeptSyncCoordinator, sharing the same '
      'syncIntegrationOperationCoordinator instance and resource key that '
      'KeptSyncIntegrationCoordinator uses -- a positive proof that an '
      'incoming apply and every outgoing user mutation always serialize '
      'against each other', () {
    final matches = allLibFiles
        .where((file) => file.path
            .replaceAll('\\', '/')
            .endsWith('lib/services/app_services.dart'))
        .toList();
    expect(matches, hasLength(1),
        reason: 'Expected to find exactly one app_services.dart under '
            'lib/services/.');
    final source = matches.single.readAsStringSync();

    final importsIncomingCoordinator = source
        .split('\n')
        .map((line) => line.trimLeft())
        .where(
            (line) => line.startsWith('import ') || line.startsWith('export '))
        .any((line) => line.contains('incoming_kept_sync_coordinator.dart'));
    expect(importsIncomingCoordinator, isTrue,
        reason: 'app_services.dart is expected to import '
            'incoming_kept_sync_coordinator.dart.');

    final codeOnly = _stripComments(source);
    expect(codeOnly.contains('IncomingKeptSyncCoordinator('), isTrue,
        reason: 'app_services.dart is expected to construct '
            'IncomingKeptSyncCoordinator directly.');
    expect(
      codeOnly.contains(
        'integrationCoordinator: syncIntegrationOperationCoordinator,',
      ),
      isTrue,
      reason: 'app_services.dart is expected to pass the shared '
          'syncIntegrationOperationCoordinator instance to both '
          'coordinators.',
    );
  });

  test(
      'SavedReflectionsService is the intended service-level importer of '
      'KeptSyncIntegrationCoordinator -- a positive proof, not merely the '
      'absence of other importers', () {
    final matches = allLibFiles
        .where((file) => file.path.replaceAll('\\', '/').endsWith(
              'lib/services/saved_reflections_service.dart',
            ))
        .toList();
    expect(matches, hasLength(1),
        reason: 'Expected to find exactly one saved_reflections_service.dart '
            'under lib/services/.');
    final source = matches.single.readAsStringSync();

    final importsSyncIntegration = source
        .split('\n')
        .map((line) => line.trimLeft())
        .where(
            (line) => line.startsWith('import ') || line.startsWith('export '))
        .any((line) => line.contains('sync_integration'));
    expect(importsSyncIntegration, isTrue,
        reason: 'saved_reflections_service.dart is expected to import '
            'something from lib/sync_integration/.');

    final codeOnly = _stripComments(source);
    expect(codeOnly.contains('KeptSyncIntegrationCoordinator'), isTrue,
        reason: 'saved_reflections_service.dart is expected to reference '
            'KeptSyncIntegrationCoordinator directly.');
  });

  test(
      'privileged KeptRepository replay parameters (presetId:, '
      'presetMutationId:, presetKeptAt:, presetUpdatedAt:, onAuthorized:) '
      'are used at a call site only in kept_repository.dart (declares them) '
      'and kept_sync_integration_coordinator.dart (the single authorized '
      'production caller) -- never anywhere else under lib/', () {
    // Build 26 Phase 4E-2 correction (final-audit blocker): KeptRepository
    // recognizes a crash-recovery replay of an already-authorized mutation
    // structurally, by the exact call shape "a preset identity/timestamp
    // supplied with no `onAuthorized`" -- see KeptRepository's own class doc
    // comment. That shape is only ever safe because, today,
    // KeptSyncIntegrationCoordinator is the *only* production caller that
    // ever supplies these parameters. Nothing in the type system enforces
    // that -- `keptRepository` is a bare public global
    // (`app_services.dart`) and `keepOccurrence`/`saveReflection` are public
    // methods, so any other production file could, in principle, reproduce
    // this exact shape and silently bypass the free-tier Keep/Reflection
    // limit for a call that never went through a real, durably-recorded,
    // previously-authorized mutation. This test converts that
    // convention-only invariant into a machine-enforced one: an exact,
    // two-file allowlist -- never a directory-wide exemption for
    // `repositories/`, `sync_integration/`, `services/`, or any other
    // directory. Deliberately an exact-token scan (never a fragile
    // multiline regex trying to recognize specific method invocations),
    // matching the instruction that produced this correction.
    const privilegedTokens = [
      'presetId:',
      'presetMutationId:',
      'presetKeptAt:',
      'presetUpdatedAt:',
      'onAuthorized:',
    ];
    const allowedFiles = {
      'lib/repositories/kept_repository.dart',
      'lib/sync_integration/kept_sync_integration_coordinator.dart',
    };

    final violations = <String>[];
    for (final file in allLibFiles) {
      final normalizedPath = file.path.replaceAll('\\', '/');
      final isAllowed =
          allowedFiles.any((allowed) => normalizedPath.endsWith(allowed));
      if (isAllowed) continue;

      final codeOnly = _stripComments(file.readAsStringSync());
      for (final token in privilegedTokens) {
        if (codeOnly.contains(token)) {
          violations.add('$normalizedPath uses privileged token "$token"');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test(
      'privileged KeptRepository raw-envelope surface (.loadAllRecords( and '
      '.replaceAllRecords() is called only in kept_repository.dart (declares '
      'them), incoming_kept_sync_coordinator.dart, and (Build 26 Phase 4E-4) '
      'kept_sync_bootstrap_coordinator.dart -- the sole authorized '
      'production consumers -- never anywhere else under lib/', () {
    // Build 26 Phase 4E-3b final-audit correction (BLOCKING finding):
    // `KeptRepository.loadAllRecords`/`replaceAllRecords` are a privileged,
    // sync-unaware raw-envelope surface that `IncomingKeptSyncCoordinator`
    // must use to apply a whole incoming batch as one atomic replacement.
    // `replaceAllRecords` intentionally bypasses the normal user-action
    // free-tier Keep limit, exactly like the `KeptRepository` replay
    // parameters guarded by the test immediately above -- and, exactly like
    // that surface, nothing in the type system stops a future screen,
    // widget, feature service, import/restore feature, or unrelated
    // coordinator from calling `keptRepository.replaceAllRecords(...)` or
    // `.loadAllRecords()` directly and silently bypassing that limit.
    // `keptRepository` is a bare public global (`app_services.dart`) and
    // both methods are bare public instance methods, so this invariant is
    // convention-only until a test enforces it. This test converts it into
    // a machine-enforced one: an exact, two-file allowlist -- never a
    // directory-wide exemption for `repositories/`, `sync_integration/`,
    // `services/`, or any other directory -- mirroring the privileged
    // replay-parameter guard's own exact-token, exact-file-allowlist
    // design precisely.
    const privilegedCallPatterns = [
      '.loadAllRecords(',
      '.replaceAllRecords(',
    ];
    const allowedFiles = {
      'lib/repositories/kept_repository.dart',
      'lib/sync_integration/incoming_kept_sync_coordinator.dart',
      'lib/sync_integration/kept_sync_bootstrap_coordinator.dart',
    };

    final violations = <String>[];
    for (final file in allLibFiles) {
      final normalizedPath = file.path.replaceAll('\\', '/');
      final isAllowed =
          allowedFiles.any((allowed) => normalizedPath.endsWith(allowed));
      if (isAllowed) continue;

      final codeOnly = _stripComments(file.readAsStringSync());
      for (final pattern in privilegedCallPatterns) {
        if (codeOnly.contains(pattern)) {
          violations.add(
            '$normalizedPath calls privileged KeptRepository method '
            '"$pattern"',
          );
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test(
      'no screen or widget file imports anything from lib/sync_integration/ '
      '-- scanned by actual UI path (lib/screens/, lib/widgets/), never by '
      'process of elimination over every other file under lib/. Build 26 '
      'Phase 4E-2 wires real call sites only through '
      'SavedReflectionsService/app_services.dart, and Build 26 Phase 4F '
      'additionally wires lib/sync_runtime/ -- none of those are UI, so '
      'none of them belong in this test\'s candidate set at all; they have '
      'their own dedicated positive-proof/allowlist guards elsewhere in '
      'this suite', () {
    // Phase 4E-2 correction (superseded further here): Phase 4E-1's version
    // of this test forbade *every* file outside lib/sync_integration/ from
    // importing it, because no real call site existed yet. That "everything
    // except sync_integration itself" candidate set was never actually
    // "screens and widgets" -- it silently included services,
    // sync_orchestration, sync_platform, and (once Build 26 Phase 4F
    // introduced it) lib/sync_runtime/ too, which is runtime infrastructure,
    // not UI, and may legitimately import the integration coordinators.
    // This test now scans exactly the two real UI directories its own title
    // names -- the same lib/screens/ and lib/widgets/ path classification
    // this suite's own type-name-reference test (below) already uses -- so a
    // genuinely non-UI importer can never trip it again, and a real future
    // UI violation still fails loudly instead of being masked by an
    // ever-growing exception list.
    final violations = <String>[];
    for (final file in allLibFiles) {
      final normalizedPath = file.path.replaceAll('\\', '/');
      final isScreenOrWidget = normalizedPath.contains('/lib/screens/') ||
          normalizedPath.startsWith('lib/screens/') ||
          normalizedPath.contains('/lib/widgets/') ||
          normalizedPath.startsWith('lib/widgets/');
      if (!isScreenOrWidget) continue;
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
      'no screen, widget, or main.dart file references any sync_integration '
      'type name in real code -- only SavedReflectionsService/'
      'app_services.dart may', () {
    const typeNames = [
      'LocalSyncIntent',
      'LocalSyncIntentPayload',
      'LocalSyncIntentKind',
      'LocalSyncIntentOperation',
      'LocalSyncIntentStage',
      'LocalSyncIntentStore',
      'ProtectedLocalSyncIntentStore',
      'LocalSyncIntentEnvelope',
      'KeptSyncIntegrationCoordinator',
      'AssociatedSyncAccountContext',
      // Build 26 Phase 4E-3b additions.
      'IncomingKeptSyncCoordinator',
      'IncomingApplyResult',
      'IncomingApplyStatus',
      // Build 26 Phase 4E-4 additions.
      'KeptSyncBootstrapCoordinator',
      'AssociationEvaluation',
      'AssociationAuthorizationResult',
      'LegacyAssociationRepairResult',
      'BootstrapRunResult',
    ];

    final scanTargets = allLibFiles.where((file) {
      final p = file.path.replaceAll('\\', '/');
      final isAllowed =
          p.endsWith('lib/services/saved_reflections_service.dart') ||
              p.endsWith('lib/services/app_services.dart');
      if (isAllowed) return false;
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
      'Build 26 Phase 4F: production runSyncPass() invocation is permitted '
      'only from its own definition file '
      '(lib/sync_orchestration/sync_orchestrator.dart) and the single '
      'runtime pipeline owner '
      '(lib/sync_runtime/cloud_kit_sync_runtime_coordinator.dart) -- no '
      'other production file under lib/ (no screen, no widget, no service, '
      'no main.dart, and no other file under lib/sync_runtime/ itself) may '
      'call it', () {
    // Supersedes the prior Phase 4E invariant ("no production caller
    // exists at all"), which is now obsolete by design: Build 26 Phase 4F's
    // entire purpose is to introduce exactly one production runtime caller
    // of runSyncPass(). This allowlist is deliberately an exact,
    // normalized-path, two-file allowlist -- never a directory-wide
    // exemption for lib/sync_runtime/ (which would also silently permit a
    // second, unaudited runSyncPass() caller to be added anywhere else
    // under that directory), never main.dart, never app_services.dart,
    // never a screen, and never an arbitrary service. The exact runtime
    // coordinator file remains the sole permitted runtime caller.
    const allowedExactFiles = {
      'lib/sync_orchestration/sync_orchestrator.dart',
      'lib/sync_runtime/cloud_kit_sync_runtime_coordinator.dart',
    };
    final violations = <String>[];
    for (final file in allLibFiles) {
      final normalizedPath = file.path.replaceAll('\\', '/');
      final isAllowed =
          allowedExactFiles.any((allowed) => normalizedPath.endsWith(allowed));
      if (isAllowed) continue;
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
        operation: LocalSyncIntentOperation.reflectionSave,
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

  // -------------------------------------------------------------------
  // Build 26 Phase 4F fast-follow: local-mutation nudge dependency-direction
  // and composition-root guards.
  // -------------------------------------------------------------------

  test(
      'no file under lib/sync_integration/ imports anything from '
      'lib/sync_runtime/ -- the local-mutation nudge callback added in the '
      'Build 26 Phase 4F fast-follow is a plain, argument-free '
      '`void Function()?` with no reference to SyncRuntimeTrigger or '
      'CloudKitSyncRuntimeCoordinator, keeping the existing one-directional '
      'sync_runtime -> sync_integration import edge intact and never '
      'reversed', () {
    final violations = <String>[];
    for (final file in integrationFiles) {
      for (final line in file.readAsLinesSync()) {
        final trimmed = line.trimLeft();
        if (!trimmed.startsWith('import ') && !trimmed.startsWith('export ')) {
          continue;
        }
        if (trimmed.contains('sync_runtime')) {
          violations.add('${file.path}: "$trimmed"');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test(
      'no file under lib/sync_integration/ references SyncRuntimeTrigger or '
      'CloudKitSyncRuntimeCoordinator by name in real code', () {
    const forbiddenTypeNames = [
      'SyncRuntimeTrigger',
      'CloudKitSyncRuntimeCoordinator',
    ];
    final violations = <String>[];
    for (final file in integrationFiles) {
      final codeOnly = _stripComments(file.readAsStringSync());
      for (final typeName in forbiddenTypeNames) {
        if (codeOnly.contains(typeName)) {
          violations.add('${file.path} references "$typeName"');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test(
      'no screen or widget file references requestSync(, '
      'SyncRuntimeTrigger, or cloudKitSyncRuntimeCoordinator directly -- the '
      'Build 26 Phase 4F fast-follow nudge is wired exclusively through '
      'KeptSyncIntegrationCoordinator\'s onMutationCommitted callback, '
      'composed only in app_services.dart, never scattered across UI call '
      'sites', () {
    const forbiddenReferences = [
      'requestSync(',
      'SyncRuntimeTrigger',
      'cloudKitSyncRuntimeCoordinator',
    ];
    final violations = <String>[];
    for (final file in allLibFiles) {
      final normalizedPath = file.path.replaceAll('\\', '/');
      final isScreenOrWidget = normalizedPath.contains('/lib/screens/') ||
          normalizedPath.startsWith('lib/screens/') ||
          normalizedPath.contains('/lib/widgets/') ||
          normalizedPath.startsWith('lib/widgets/');
      if (!isScreenOrWidget) continue;
      final codeOnly = _stripComments(file.readAsStringSync());
      for (final forbidden in forbiddenReferences) {
        if (codeOnly.contains(forbidden)) {
          violations.add('$normalizedPath references "$forbidden"');
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test(
      'app_services.dart is the sole production file that supplies '
      'onMutationCommitted: to KeptSyncIntegrationCoordinator, and it does '
      'so exactly once, referencing cloudKitSyncRuntimeCoordinator.'
      'requestSync(SyncRuntimeTrigger.localMutation) fire-and-forget', () {
    final violations = <String>[];
    String? appServicesSource;
    for (final file in allLibFiles) {
      final normalizedPath = file.path.replaceAll('\\', '/');
      final isAppServices = normalizedPath.endsWith(
        'lib/services/app_services.dart',
      );
      final codeOnly = _stripComments(file.readAsStringSync());
      if (codeOnly.contains('onMutationCommitted:')) {
        if (!isAppServices) {
          violations.add(
            '$normalizedPath supplies onMutationCommitted: -- only '
            'app_services.dart may',
          );
        } else {
          appServicesSource = codeOnly;
        }
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
    expect(appServicesSource, isNotNull,
        reason: 'Expected app_services.dart to supply onMutationCommitted: '
            'to KeptSyncIntegrationCoordinator.');
    // Whitespace-insensitive: tolerates any dart-format-chosen line wrapping
    // between the two tokens, never depends on an exact literal layout.
    final requestSyncWithLocalMutation = RegExp(
      r'requestSync\(\s*SyncRuntimeTrigger\.localMutation\s*,?\s*\)',
    );
    expect(
      requestSyncWithLocalMutation.hasMatch(appServicesSource!),
      isTrue,
      reason: 'Expected app_services.dart to call requestSync with '
          'SyncRuntimeTrigger.localMutation.',
    );
    expect(appServicesSource.contains('unawaited('), isTrue,
        reason: 'Expected the nudge call in app_services.dart to be '
            'fire-and-forget via unawaited(...).');
  });
}
