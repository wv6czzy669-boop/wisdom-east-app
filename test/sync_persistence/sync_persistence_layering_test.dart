// Build 26 Phase 4D-1 (layering correction): structural proof that
// lib/sync_persistence/ depends only on the pure Dart sync domain
// (lib/sync/) and existing protected persistence primitives -- never on the
// platform-bridge layer (lib/sync_platform/). Mirrors the discipline
// test/sync_platform/cloud_kit_platform_privacy_test.dart and
// test/sync/sync_domain_privacy_test.dart already establish for their own
// layers. Synthetic content only.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/sync/cloud_kept_wisdom_projection.dart';
import 'package:wisdom_app/sync/data_epoch.dart';
import 'package:wisdom_app/sync/sync_change.dart';
import 'package:wisdom_app/sync/sync_tombstone.dart';
import 'package:wisdom_app/sync_persistence/persisted_outbox_mutation.dart';

/// Strips `//`, `///`, and `/* */` comments while leaving string literals
/// untouched -- a small, self-contained copy of the same test-only tooling
/// `cloud_kit_platform_privacy_test.dart`/`sync_domain_privacy_test.dart`
/// each keep their own independent copy of, deliberately not shared, so this
/// file's correctness is never coupled to edits in either of those.
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
  late Directory persistenceDir;
  late List<File> dartFiles;

  setUpAll(() {
    persistenceDir = Directory('lib/sync_persistence');
    expect(
      persistenceDir.existsSync(),
      isTrue,
      reason: 'Expected lib/sync_persistence to exist relative to the '
          'package root (the directory flutter test runs from).',
    );
    dartFiles = persistenceDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();
  });

  test(
      'every file scanned is a real, non-empty pure-Dart source file (the '
      'checks below are not vacuously passing over zero files)', () {
    expect(dartFiles.length, greaterThanOrEqualTo(4));
    for (final file in dartFiles) {
      expect(file.readAsStringSync().trim(), isNotEmpty);
    }
  });

  test(
      'no production file under lib/sync_persistence/ has an import/export '
      'directive referencing the sync_platform layer', () {
    final violations = <String>[];
    for (final file in dartFiles) {
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
      'no production file under lib/sync_persistence/ mentions the '
      'platform-bridge adapter type by name in real code', () {
    final violations = <String>[];
    for (final file in dartFiles) {
      final codeOnly = _stripComments(file.readAsStringSync());
      if (codeOnly.contains('CloudKeptWisdomWireEnvelope') ||
          codeOnly.contains('MethodChannelCloudKitPlatformBridge')) {
        violations.add(file.path);
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test(
      'no MethodChannel invocation and no CloudKit transport method name '
      'exists anywhere under lib/sync_persistence/ (in real code, not '
      'comments)', () {
    const forbiddenSubstrings = [
      'MethodChannel(',
      'invokeMethod',
      'modifyPrivateRecords',
      'fetchPrivateZoneChanges',
      'CKRecord',
      'CKModifyRecordsOperation',
      'CKFetchRecordZoneChangesOperation',
    ];

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

  // ---------------------------------------------------------------------
  // Behavioral proof: the persisted shape is the domain SyncChange itself,
  // round-tripped through this layer's own local codec -- never a
  // platform-bridge DTO. Supersession, acknowledgment, and queue-ordering
  // behavior are unchanged and already covered exhaustively by
  // protected_sync_persistence_store_test.dart (groups D/E/F); this file
  // only proves the encode/decode boundary itself for each mutation shape.
  // ---------------------------------------------------------------------

  final epoch = DataEpoch.parse('bbbbbbbb-2222-4222-8222-222222222222');
  const revealId = 'aaaaaaaa-1111-4111-8111-111111111111';

  CloudKeptWisdomProjection activeProjection({
    bool hasReflection = false,
    String wisdomText = 'Synthetic wisdom text for testing only.',
  }) {
    return CloudKeptWisdomProjection.tryParseRemote({
      'recordName': 'east-kept-$revealId',
      'isTombstone': false,
      'revealId': revealId,
      'wisdomText': wisdomText,
      'revealedAtMs': 1000,
      'keptAtMs': 2000,
      if (hasReflection) 'reflectionText': 'A synthetic reflection.',
      if (hasReflection) 'reflectedAtMs': 3500,
      'updatedAtMs': 3000,
      'mutationId': 'cccccccc-3333-4333-8333-333333333333',
      'dataEpoch': epoch.value,
      'schemaVersion': 3,
    })!;
  }

  test(
      'an active (Keep-only) mutation round-trips exactly through this '
      "layer's own codec", () {
    final change = SyncChange(
      kind: SyncChangeKind.create,
      projection: activeProjection(),
      enqueuedAt: DateTime.utc(2026, 8, 1),
    );
    final entry = PersistedOutboxMutation(change: change);
    final decoded = PersistedOutboxMutation.tryDecode(entry.encode());

    expect(decoded, entry);
    expect(decoded!.change.projection.reflectionText, isNull);
    expect(decoded.mutationId, change.projection.mutationId);
    expect(decoded.recordName, change.projection.recordName);
  });

  test(
      'an active mutation carrying a Reflection update round-trips '
      'exactly, including reflectionText/reflectedAtMs', () {
    final change = SyncChange(
      kind: SyncChangeKind.update,
      projection: activeProjection(hasReflection: true),
      enqueuedAt: DateTime.utc(2026, 8, 1, 1),
    );
    final entry = PersistedOutboxMutation(change: change);
    final decoded = PersistedOutboxMutation.tryDecode(entry.encode());

    expect(decoded, entry);
    expect(
        decoded!.change.projection.reflectionText, 'A synthetic reflection.');
    expect(decoded.change.projection.reflectedAtMs, 3500);
  });

  test(
      'a tombstone mutation round-trips exactly, preserving revealId '
      'occurrence identity via recordName', () {
    final tombstone = SyncTombstone(
      revealId: revealId,
      dataEpoch: epoch,
      updatedAt: DateTime.utc(2026, 8, 1),
      deletedAt: DateTime.utc(2026, 8, 1),
      mutationId: 'dddddddd-4444-4444-8444-444444444444',
    );
    final change = SyncChange(
      kind: SyncChangeKind.delete,
      projection: CloudKeptWisdomProjection.tombstone(tombstone),
      enqueuedAt: DateTime.utc(2026, 8, 1, 2),
    );
    final entry = PersistedOutboxMutation(change: change);
    final decoded = PersistedOutboxMutation.tryDecode(entry.encode());

    expect(decoded, entry);
    expect(decoded!.change.projection.isTombstone, isTrue);
    expect(
      decoded.recordName,
      change.projection.recordName,
    );
  });

  test(
      'a malformed persisted projection (missing mutationId) fails closed, '
      'never throws', () {
    final raw = <Object?, Object?>{
      'kind': 'create',
      'status': 'pending',
      'enqueuedAtMs': 1000,
      'record': {
        'recordName': 'east-kept-$revealId',
        'isTombstone': false,
        'revealId': revealId,
        'wisdomText': 'Synthetic.',
        'revealedAtMs': 1000,
        'keptAtMs': 2000,
        'updatedAtMs': 3000,
        // 'mutationId' deliberately omitted.
        'dataEpoch': epoch.value,
        'schemaVersion': 3,
      },
    };

    expect(PersistedOutboxMutation.tryDecode(raw), isNull);
  });

  test('a malformed persisted projection (invalid dataEpoch) fails closed', () {
    final raw = <Object?, Object?>{
      'kind': 'create',
      'status': 'pending',
      'enqueuedAtMs': 1000,
      'record': {
        'recordName': 'east-kept-$revealId',
        'isTombstone': false,
        'revealId': revealId,
        'wisdomText': 'Synthetic.',
        'revealedAtMs': 1000,
        'keptAtMs': 2000,
        'updatedAtMs': 3000,
        'mutationId': 'cccccccc-3333-4333-8333-333333333333',
        'dataEpoch': 'not-a-uuid',
        'schemaVersion': 3,
      },
    };

    expect(PersistedOutboxMutation.tryDecode(raw), isNull);
  });
}
