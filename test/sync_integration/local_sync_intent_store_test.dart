// Build 26 Phase 4E-1: ProtectedLocalSyncIntentStore -- the durable,
// account-free local sync-intent store. Synthetic content only; no real
// MethodChannel or CloudKit access anywhere in this file.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/persistence/file_protection_bridge.dart';
import 'package:wisdom_app/sync_integration/local_sync_intent.dart';
import 'package:wisdom_app/sync_integration/local_sync_intent_envelope.dart';
import 'package:wisdom_app/sync_integration/local_sync_intent_store.dart';
import 'package:wisdom_app/sync_integration/protected_local_sync_intent_store.dart';
import 'package:wisdom_app/utils/kept_timestamp_canonicalizer.dart';

/// Fake [FileProtectionBridge] -- identical in shape and intent to the one
/// already used throughout `test/sync_persistence/
/// protected_sync_persistence_store_test.dart`. No real MethodChannel is
/// involved anywhere in this file.
class _FakeFileProtectionBridge implements FileProtectionBridge {
  final List<String> protectedPaths = [];
  final Map<String, int> _remainingFailures = {};
  final Map<String, int> _callCounts = {};
  Future<void> Function(String path)? onProtect;

  void failNextTimeFor(String path, {int times = 1}) {
    _remainingFailures[path] = (_remainingFailures[path] ?? 0) + times;
  }

  int callCountFor(String path) => _callCounts[path] ?? 0;

  @override
  Future<void> protectAndVerifyComplete(String path) async {
    protectedPaths.add(path);
    _callCounts[path] = (_callCounts[path] ?? 0) + 1;
    if (onProtect != null) {
      await onProtect!(path);
    }
    final remaining = _remainingFailures[path];
    if (remaining != null && remaining > 0) {
      _remainingFailures[path] = remaining - 1;
      throw const FileProtectionException('Simulated protection failure.');
    }
  }
}

void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot =
        Directory.systemTemp.createTempSync('sync_integration_store_test_');
  });

  tearDown(() {
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  String dirPath() => '${tempRoot.path}/east_sync_integration_state';
  String finalPath() => '${dirPath()}/east_sync_intents_v1.json';
  String tempPathFor(String token) =>
      '${dirPath()}/.east_sync_intents_v1.tmp-$token.json';
  String backupPathFor(String token) =>
      '${dirPath()}/.east_sync_intents_v1.backup-$token.json';
  String recoveryTempPathFor(String token) =>
      '${dirPath()}/.east_sync_intents_v1.recover-$token.json';

  ProtectedLocalSyncIntentStore buildStore({
    FileProtectionBridge? bridge,
    String Function()? tokenFactory,
    DateTime Function()? clock,
  }) {
    var counter = 0;
    return ProtectedLocalSyncIntentStore(
      rootDirectoryProvider: () async => tempRoot,
      fileProtectionBridge: bridge ?? _FakeFileProtectionBridge(),
      tokenFactory: tokenFactory ?? (() => 'token-${counter++}'),
      clock: clock ?? (() => DateTime.utc(2026, 8, 1, 12, 0)),
    );
  }

  const revealIdA = 'aaaaaaaa-1111-4111-8111-111111111111';
  const revealIdB = 'bbbbbbbb-2222-4222-8222-222222222222';
  const intentId1 = '11111111-1111-4111-8111-111111111111';
  const intentId2 = '22222222-2222-4222-8222-222222222222';
  const intentId3 = '33333333-3333-4333-8333-333333333333';
  const mutationId1 = '44444444-4444-4444-8444-444444444444';

  LocalSyncIntent activeIntent({
    required String intentId,
    String revealId = revealIdA,
    String mutationId = mutationId1,
    String wisdomText = 'Synthetic wisdom text for testing only.',
    bool hasReflection = false,
    int updatedAtMs = 3000,
    LocalSyncIntentStage stage = LocalSyncIntentStage.pendingLocalApplication,
    DateTime? enqueuedAt,
  }) {
    return LocalSyncIntent(
      intentId: intentId,
      kind: LocalSyncIntentKind.create,
      payload: LocalSyncIntentPayload.active(
        revealId: revealId,
        operation: LocalSyncIntentOperation.keep,
        wisdomText: wisdomText,
        revealedAtMs: 1000,
        keptAtMs: 2000,
        updatedAtMs: updatedAtMs,
        mutationId: mutationId,
        reflectionText: hasReflection ? 'A synthetic reflection.' : null,
        reflectedAtMs: hasReflection ? updatedAtMs : null,
      ),
      stage: stage,
      enqueuedAt: enqueuedAt ?? DateTime.utc(2026, 8, 1),
    );
  }

  LocalSyncIntent tombstoneIntent({
    required String intentId,
    String revealId = revealIdA,
    String mutationId = mutationId1,
    int updatedAtMs = 5000,
    LocalSyncIntentStage stage = LocalSyncIntentStage.pendingLocalApplication,
  }) {
    return LocalSyncIntent(
      intentId: intentId,
      kind: LocalSyncIntentKind.delete,
      payload: LocalSyncIntentPayload.tombstone(
        revealId: revealId,
        deletedAtMs: updatedAtMs,
        updatedAtMs: updatedAtMs,
        mutationId: mutationId,
      ),
      stage: stage,
      enqueuedAt: DateTime.utc(2026, 8, 1, 1),
    );
  }

  // ---------------------------------------------------------------------
  // 1. empty load.
  // ---------------------------------------------------------------------
  test('1. loadIntents on a never-written store returns an empty list',
      () async {
    final store = buildStore();
    expect(await store.loadIntents(), isEmpty);
  });

  // ---------------------------------------------------------------------
  // 2. active intent round-trip.
  // ---------------------------------------------------------------------
  test('2. an active (Keep-only) intent round-trips exactly', () async {
    final store = buildStore();
    final intent = activeIntent(intentId: intentId1);
    await store.enqueueIntent(intent);

    final loaded = await store.loadIntents();
    expect(loaded, hasLength(1));
    expect(loaded.single, intent);
    expect(loaded.single.payload.reflectionText, isNull);
  });

  // ---------------------------------------------------------------------
  // 3. Reflection-bearing active intent round-trip.
  // ---------------------------------------------------------------------
  test(
      '3. an active intent carrying a Reflection round-trips exactly, '
      'including reflectionText/reflectedAtMs', () async {
    final store = buildStore();
    final intent = activeIntent(intentId: intentId1, hasReflection: true);
    await store.enqueueIntent(intent);

    final loaded = await store.loadIntents();
    expect(loaded.single.payload.reflectionText, 'A synthetic reflection.');
    expect(loaded.single.payload.reflectedAtMs, 3000);
  });

  // ---------------------------------------------------------------------
  // 4. Reflection-deletion intent (active form, reflectionText cleared).
  // ---------------------------------------------------------------------
  test(
      '4. a Reflection-deletion intent (active form with no reflection '
      'field) round-trips exactly', () async {
    final store = buildStore();
    final intent = activeIntent(intentId: intentId1, hasReflection: false);
    await store.enqueueIntent(intent);

    final loaded = await store.loadIntents();
    expect(loaded.single.payload.reflectionText, isNull);
    expect(loaded.single.payload.reflectedAtMs, isNull);
    expect(loaded.single.payload.isTombstone, isFalse);
  });

  // ---------------------------------------------------------------------
  // 5. tombstone intent remains recoverable without a local Kept record.
  // ---------------------------------------------------------------------
  test(
      '5. a tombstone intent round-trips exactly and carries every field '
      "needed to recover without ever reading a live Kept record", () async {
    final store = buildStore();
    final intent = tombstoneIntent(intentId: intentId1);
    await store.enqueueIntent(intent);

    final loaded = await store.loadIntents();
    expect(loaded.single, intent);
    expect(loaded.single.payload.isTombstone, isTrue);
    expect(loaded.single.payload.wisdomText, isNull);
    expect(loaded.single.payload.deletedAtMs, 5000);
    // Structurally: the payload alone is enough to derive recordName --
    // no field references any live Kept record at all.
    expect(loaded.single.recordName, 'east-kept-$revealIdA');
  });

  // ---------------------------------------------------------------------
  // 6. exact duplicate enqueue is idempotent.
  // ---------------------------------------------------------------------
  test(
      '6. an exact duplicate enqueue (same intentId, same content) is '
      'idempotent', () async {
    final store = buildStore();
    final intent = activeIntent(intentId: intentId1);
    await store.enqueueIntent(intent);
    await store.enqueueIntent(intent);

    final loaded = await store.loadIntents();
    expect(loaded, hasLength(1));
  });

  // ---------------------------------------------------------------------
  // 7. same intent ID with different content fails closed.
  // ---------------------------------------------------------------------
  test(
      '7. the same intentId with genuinely different content is rejected, '
      'never silently resolved either way', () async {
    final store = buildStore();
    await store.enqueueIntent(activeIntent(intentId: intentId1));

    expect(
      () => store.enqueueIntent(
        activeIntent(intentId: intentId1, wisdomText: 'A different text.'),
      ),
      throwsA(isA<ConflictingLocalSyncIntentIdentityException>()),
    );
    // Nothing was mutated by the rejected attempt.
    final loaded = await store.loadIntents();
    expect(loaded.single.payload.wisdomText,
        'Synthetic wisdom text for testing only.');
  });

  // ---------------------------------------------------------------------
  // 8. same-record active supersession.
  // ---------------------------------------------------------------------
  test(
      '8. a new intentId for the same record supersedes the existing '
      'active intent in place', () async {
    final store = buildStore();
    await store.enqueueIntent(
      activeIntent(intentId: intentId1, wisdomText: 'Original text.'),
    );
    await store.enqueueIntent(
      activeIntent(intentId: intentId2, wisdomText: 'Edited text.'),
    );

    final loaded = await store.loadIntents();
    expect(loaded, hasLength(1));
    expect(loaded.single.intentId, intentId2);
    expect(loaded.single.payload.wisdomText, 'Edited text.');
  });

  // ---------------------------------------------------------------------
  // 9. active -> tombstone supersession.
  // ---------------------------------------------------------------------
  test(
      '9. a tombstone intent supersedes a pending active intent for the '
      'same record', () async {
    final store = buildStore();
    await store.enqueueIntent(activeIntent(intentId: intentId1));
    await store.enqueueIntent(tombstoneIntent(intentId: intentId2));

    final loaded = await store.loadIntents();
    expect(loaded, hasLength(1));
    expect(loaded.single.intentId, intentId2);
    expect(loaded.single.payload.isTombstone, isTrue);
  });

  // ---------------------------------------------------------------------
  // 10. tombstone -> active supersession (re-Keep after removal).
  // ---------------------------------------------------------------------
  test(
      '10. an active intent (re-Keep) supersedes a pending tombstone '
      'intent for the same record', () async {
    final store = buildStore();
    await store.enqueueIntent(tombstoneIntent(intentId: intentId1));
    await store.enqueueIntent(
      activeIntent(intentId: intentId2, wisdomText: 'Re-kept text.'),
    );

    final loaded = await store.loadIntents();
    expect(loaded, hasLength(1));
    expect(loaded.single.intentId, intentId2);
    expect(loaded.single.payload.isTombstone, isFalse);
    expect(loaded.single.payload.wisdomText, 'Re-kept text.');
  });

  // ---------------------------------------------------------------------
  // 11. stale intent acknowledgment cannot remove replacement.
  // ---------------------------------------------------------------------
  test(
      '11. removing a stale, already-superseded intentId never removes '
      'the newer replacement', () async {
    final store = buildStore();
    await store.enqueueIntent(
      activeIntent(intentId: intentId1, wisdomText: 'Original text.'),
    );
    await store.enqueueIntent(
      activeIntent(intentId: intentId2, wisdomText: 'Edited text.'),
    );

    // The old, now-superseded intentId1 no longer names any stored entry.
    await store.removeIntent(intentId1);

    final loaded = await store.loadIntents();
    expect(loaded, hasLength(1));
    expect(loaded.single.intentId, intentId2);
    expect(loaded.single.payload.wisdomText, 'Edited text.');
  });

  // ---------------------------------------------------------------------
  // 12. unrelated intent ordering remains deterministic.
  // ---------------------------------------------------------------------
  test(
      '12. unrelated intents preserve deterministic queue order, and a '
      'supersession never moves a record to the back of the queue', () async {
    final store = buildStore();
    await store
        .enqueueIntent(activeIntent(intentId: intentId1, revealId: revealIdA));
    await store
        .enqueueIntent(activeIntent(intentId: intentId2, revealId: revealIdB));
    // Supersede the first record's intent -- it must keep its original
    // (first) position, not move to the end.
    await store.enqueueIntent(
      activeIntent(
          intentId: intentId3, revealId: revealIdA, wisdomText: 'Edited.'),
    );

    final loaded = await store.loadIntents();
    expect(loaded, hasLength(2));
    expect(loaded[0].payload.revealId, revealIdA);
    expect(loaded[0].intentId, intentId3);
    expect(loaded[1].payload.revealId, revealIdB);
    expect(loaded[1].intentId, intentId2);
  });

  // ---------------------------------------------------------------------
  // 13. two revealIds with identical wisdom text remain independent.
  // ---------------------------------------------------------------------
  test(
      '13. two distinct revealIds carrying exact duplicate wisdom text '
      'remain two fully independent intents', () async {
    final store = buildStore();
    await store.enqueueIntent(
      activeIntent(
          intentId: intentId1, revealId: revealIdA, wisdomText: 'Same text.'),
    );
    await store.enqueueIntent(
      activeIntent(
          intentId: intentId2, revealId: revealIdB, wisdomText: 'Same text.'),
    );

    final loaded = await store.loadIntents();
    expect(loaded, hasLength(2));
    expect(loaded[0].payload.revealId, isNot(loaded[1].payload.revealId));
  });

  // ---------------------------------------------------------------------
  // 14. corruption fails closed.
  // ---------------------------------------------------------------------
  test('14. a corrupt authoritative file fails the load closed', () async {
    final store = buildStore();
    await store.enqueueIntent(activeIntent(intentId: intentId1));

    await File(finalPath()).writeAsString('not valid json at all {{{');

    expect(store.loadIntents(), throwsA(isA<LocalSyncIntentStoreException>()));
  });

  // ---------------------------------------------------------------------
  // 15. unknown fields/schema fail closed.
  // ---------------------------------------------------------------------
  test('15. an unrecognized schema version fails the load closed', () async {
    final store = buildStore();
    await store.enqueueIntent(activeIntent(intentId: intentId1));

    await File(finalPath()).writeAsString(
      jsonEncode({'schemaVersion': 999, 'intents': <Object?>[]}),
    );

    expect(store.loadIntents(), throwsA(isA<LocalSyncIntentStoreException>()));
  });

  test(
      '15b. an unrecognized top-level key on the persisted envelope fails '
      'the load closed', () async {
    final store = buildStore();
    await store.enqueueIntent(activeIntent(intentId: intentId1));

    await File(finalPath()).writeAsString(
      jsonEncode({
        'schemaVersion': 1,
        'intents': <Object?>[],
        'somethingUnexpected': true,
      }),
    );

    expect(store.loadIntents(), throwsA(isA<LocalSyncIntentStoreException>()));
  });

  // ---------------------------------------------------------------------
  // 16. temp protection failure preserves prior final.
  // ---------------------------------------------------------------------
  test(
      '16. a temp-file protection failure during replace preserves the '
      'prior authoritative file untouched', () async {
    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge, tokenFactory: () => 'tok');
    await store.enqueueIntent(activeIntent(intentId: intentId1));
    final beforeRaw = await File(finalPath()).readAsString();

    bridge.failNextTimeFor(tempPathFor('tok'));
    await expectLater(
      store.enqueueIntent(
          activeIntent(intentId: intentId2, revealId: revealIdB)),
      throwsA(isA<LocalSyncIntentStoreException>()),
    );

    final afterRaw = await File(finalPath()).readAsString();
    expect(afterRaw, beforeRaw);
    expect(await File(tempPathFor('tok')).exists(), isFalse);
  });

  // ---------------------------------------------------------------------
  // 17. temp verification failure preserves prior final.
  // ---------------------------------------------------------------------
  test(
      '17. a temp-file verification failure (corrupted between protect and '
      "the store's own read-back) preserves the prior authoritative file "
      'untouched', () async {
    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge, tokenFactory: () => 'tok');
    await store.enqueueIntent(activeIntent(intentId: intentId1));
    final beforeRaw = await File(finalPath()).readAsString();

    bridge.onProtect = (path) async {
      if (path == tempPathFor('tok')) {
        await File(path).writeAsString('{"corrupted": true}');
      }
    };
    await expectLater(
      store.enqueueIntent(
          activeIntent(intentId: intentId2, revealId: revealIdB)),
      throwsA(isA<LocalSyncIntentStoreException>()),
    );
    bridge.onProtect = null;

    final afterRaw = await File(finalPath()).readAsString();
    expect(afterRaw, beforeRaw);
    expect(await File(tempPathFor('tok')).exists(), isFalse);
  });

  // ---------------------------------------------------------------------
  // 18. final protection failure restores prior final.
  // ---------------------------------------------------------------------
  test(
      '18. a final-file protection failure after rename restores the '
      'prior authoritative file', () async {
    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge, tokenFactory: () => 'tok');
    await store.enqueueIntent(activeIntent(intentId: intentId1));
    final beforeRaw = await File(finalPath()).readAsString();

    final baseline = bridge.callCountFor(finalPath());
    bridge.failNextTimeFor(finalPath());
    // The first call after baseline will be the temp-file's own
    // protect+verify happening on `tempPathFor`, not `finalPath` -- so this
    // targets exactly the post-rename final-file protect call.
    await expectLater(
      store.enqueueIntent(
          activeIntent(intentId: intentId2, revealId: revealIdB)),
      throwsA(isA<LocalSyncIntentStoreException>()),
    );
    expect(bridge.callCountFor(finalPath()), greaterThan(baseline));

    final afterRaw = await File(finalPath()).readAsString();
    expect(afterRaw, beforeRaw);
  });

  // ---------------------------------------------------------------------
  // 19. final verification failure restores prior final.
  // ---------------------------------------------------------------------
  test(
      '19. a final-file verification failure (corrupted immediately after '
      'the post-rename protect call) restores the prior authoritative '
      'file, read back and re-verified', () async {
    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge, tokenFactory: () => 'tok');
    await store.enqueueIntent(activeIntent(intentId: intentId1));
    final beforeRaw = await File(finalPath()).readAsString();

    // Call sequence for the second enqueue: load-time protect(final) is
    // call #2 overall, and the post-rename protect(final) is call #3 --
    // corrupt exactly that one, mirroring the established
    // protected_sync_persistence_store_test.dart pattern for this same
    // class of failure.
    final baseline = bridge.callCountFor(finalPath());
    bridge.onProtect = (path) async {
      if (path == finalPath() && bridge.callCountFor(path) == baseline + 2) {
        await File(path).writeAsString('{"corrupted": true}');
      }
    };

    Object? caught;
    try {
      await store.enqueueIntent(
        activeIntent(intentId: intentId2, revealId: revealIdB),
      );
    } catch (error) {
      caught = error;
    }
    bridge.onProtect = null;

    expect(caught, isA<LocalSyncIntentStoreException>());
    final typed = caught as LocalSyncIntentStoreException;
    expect(typed.stage, 'replace-post-rename');

    final afterRaw = await File(finalPath()).readAsString();
    expect(afterRaw, beforeRaw);
    final reloaded = await store.loadIntents();
    expect(reloaded, hasLength(1));
    expect(reloaded.single.intentId, intentId1);
  });

  // ---------------------------------------------------------------------
  // 20. first-write failure leaves no authoritative file.
  // ---------------------------------------------------------------------
  test(
      '20. a failure on the very first write leaves no authoritative file '
      'behind at all', () async {
    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge, tokenFactory: () => 'tok');

    bridge.failNextTimeFor(tempPathFor('tok'));
    await expectLater(
      store.enqueueIntent(activeIntent(intentId: intentId1)),
      throwsA(isA<LocalSyncIntentStoreException>()),
    );

    expect(await File(finalPath()).exists(), isFalse);
  });

  // ---------------------------------------------------------------------
  // 21. all files remain inside the dedicated integration directory.
  // ---------------------------------------------------------------------
  test(
      '21. every file this store writes lives inside its own dedicated '
      'east_sync_integration_state directory, never east_kept_state or '
      'east_sync_state', () async {
    final store = buildStore();
    await store.enqueueIntent(activeIntent(intentId: intentId1));

    final dir = Directory(dirPath());
    expect(dir.existsSync(), isTrue);
    final entries = dir.listSync();
    expect(entries, isNotEmpty);
    for (final entry in entries) {
      expect(entry.path, startsWith(dirPath()));
      expect(entry.path, isNot(contains('east_kept_state')));
      expect(entry.path, isNot(contains('east_sync_state_v1')));
    }
    expect(
      Directory('${tempRoot.path}/east_kept_state').existsSync(),
      isFalse,
    );
    expect(
      Directory('${tempRoot.path}/east_sync_state').existsSync(),
      isFalse,
    );
  });

  // ---------------------------------------------------------------------
  // 22. concurrent writes serialize.
  // ---------------------------------------------------------------------
  test('22. concurrent enqueue calls serialize rather than interleaving',
      () async {
    final store = buildStore();

    await Future.wait([
      store.enqueueIntent(
          activeIntent(intentId: intentId1, revealId: revealIdA)),
      store.enqueueIntent(
          activeIntent(intentId: intentId2, revealId: revealIdB)),
    ]);

    final loaded = await store.loadIntents();
    expect(loaded, hasLength(2));
    final revealIds = loaded.map((e) => e.payload.revealId).toSet();
    expect(revealIds, {revealIdA, revealIdB});
  });

  // ---------------------------------------------------------------------
  // 23. exceptions and summaries never render private values.
  // ---------------------------------------------------------------------
  test(
      '23. LocalSyncIntent rendering and every exception here never '
      'include wisdom/reflection text, revealId, mutationId, or intentId',
      () async {
    final intent = activeIntent(
      intentId: intentId1,
      revealId: revealIdA,
      mutationId: mutationId1,
      wisdomText: 'Secret wisdom text that must never leak.',
      hasReflection: true,
    );

    final rendered = intent.toString();
    expect(rendered, isNot(contains('Secret wisdom text')));
    expect(rendered, isNot(contains('A synthetic reflection.')));
    expect(rendered, isNot(contains(revealIdA)));
    expect(rendered, isNot(contains(mutationId1)));
    expect(rendered, isNot(contains(intentId1)));
    expect(
      rendered,
      'LocalSyncIntent({kind: create, operation: keep, '
      'stage: pendingLocalApplication, '
      'hasPrivatePayload: true, isTombstone: false, hasReflection: true})',
    );

    const exception = LocalSyncIntentStoreException(
      'load-decode',
      'The authoritative sync-intent file is corrupt.',
      'a raw cause that must never render',
    );
    expect(exception.toString(), isNot(contains('a raw cause')));
    expect(
      exception.toString(),
      'LocalSyncIntentStoreException[load-decode]: The authoritative '
      'sync-intent file is corrupt.',
    );

    expect(
      const ConflictingLocalSyncIntentIdentityException().toString(),
      isNot(contains(intentId1)),
    );
  });

  // ---------------------------------------------------------------------
  // 24. successful recovery from a backup when the final file is absent.
  // ---------------------------------------------------------------------
  test(
      '24. loading recovers the exact envelope from a valid backup when the '
      'authoritative final file is absent, without duplicating intents, '
      'and leaves only the recovered final file behind afterward', () async {
    final store = buildStore();
    final seedEnvelope = LocalSyncIntentEnvelope(intents: [
      activeIntent(intentId: intentId1, revealId: revealIdA),
      tombstoneIntent(intentId: intentId2, revealId: revealIdB),
    ]);

    // Construct the exact "final absent, one valid backup present"
    // precondition directly on disk -- this is what a backup left over
    // from an earlier operation looks like when the final file is,
    // for any reason, not present. The backup is written independently
    // of the store's own API so this test does not depend on ever
    // triggering the precondition through a real crash.
    final dir = Directory(dirPath());
    await dir.create(recursive: true);
    await File(backupPathFor('seed')).writeAsString(
      seedEnvelope.encodeString(),
    );
    expect(await File(finalPath()).exists(), isFalse);

    final loaded = await store.loadIntents();

    expect(loaded, hasLength(2));
    expect(loaded[0].intentId, intentId1);
    expect(loaded[0].payload.revealId, revealIdA);
    expect(loaded[1].intentId, intentId2);
    expect(loaded[1].payload.revealId, revealIdB);
    expect(loaded[1].payload.isTombstone, isTrue);

    // The final authoritative file now exists and decodes to exactly the
    // recovered envelope -- identity, content, and order all preserved.
    expect(await File(finalPath()).exists(), isTrue);
    final finalRaw = await File(finalPath()).readAsString();
    expect(LocalSyncIntentEnvelope.decodeString(finalRaw), seedEnvelope);

    // Only the recovered final file remains: the original backup was
    // deleted only after the restored final was written, protected, read
    // back, and confirmed to match; the disposable recovery-temp file
    // was consumed by the successful rename and never lingers.
    final remaining = dir
        .listSync()
        .whereType<File>()
        .map((f) => f.path.split('/').last)
        .toList();
    expect(remaining, ['east_sync_intents_v1.json']);

    // Recovery is not repeated or duplicated on a subsequent ordinary
    // load of the now-recovered final.
    final reloaded = await store.loadIntents();
    expect(reloaded, loaded);
  });

  // ---------------------------------------------------------------------
  // 25. a protection failure during backup recovery preserves the backup.
  // ---------------------------------------------------------------------
  test(
      '25. a protectAndVerifyComplete failure during backup recovery (after '
      'recovery has begun) preserves the original backup byte-for-byte, '
      'fails the load closed without ever producing an authoritative '
      'final file, and a retry with a healthy bridge still recovers the '
      'exact original envelope', () async {
    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge, tokenFactory: () => 'tok');
    final seedEnvelope = LocalSyncIntentEnvelope(intents: [
      activeIntent(intentId: intentId1, revealId: revealIdA),
    ]);

    final dir = Directory(dirPath());
    await dir.create(recursive: true);
    final backupBytes = seedEnvelope.encodeString();
    await File(backupPathFor('seed')).writeAsString(backupBytes);
    expect(await File(finalPath()).exists(), isFalse);

    // Fail exactly the recovery-temp file's own protect+verify call --
    // distinct from the ordinary replace path (never exercised in this
    // test, since no enqueue happens) and distinct from the directory's
    // own protect call (a different path entirely). This targets the
    // moment recovery has already written the recovery-temp file and is
    // attempting to protect it, i.e. after recovery has begun.
    bridge.failNextTimeFor(recoveryTempPathFor('tok'));

    await expectLater(
      store.loadIntents(),
      throwsA(isA<LocalSyncIntentStoreException>()),
    );

    // The original backup survives completely untouched -- it was only
    // ever read from, never renamed or rewritten.
    expect(await File(backupPathFor('seed')).exists(), isTrue);
    expect(await File(backupPathFor('seed')).readAsString(), backupBytes);
    expect(
      LocalSyncIntentEnvelope.decodeString(
        await File(backupPathFor('seed')).readAsString(),
      ),
      seedEnvelope,
    );

    // No authoritative final file was ever produced by the failed
    // attempt -- an unverified file is never treated as authoritative.
    expect(await File(finalPath()).exists(), isFalse);

    // The disposable recovery-temp file was not left behind as a false
    // trail.
    expect(await File(recoveryTempPathFor('tok')).exists(), isFalse);

    // Retrying with the same store (whose bridge no longer has an
    // injected failure queued) still recovers the exact original
    // envelope from the still-intact backup -- recoverability was fully
    // preserved by the failed attempt.
    final loaded = await store.loadIntents();
    expect(loaded, hasLength(1));
    expect(loaded.single.intentId, intentId1);
    expect(loaded.single.payload.revealId, revealIdA);
    expect(await File(finalPath()).exists(), isTrue);
  });

  // ---------------------------------------------------------------------
  // 26/27. Real-device timestamp-canonicalization regression (the proven
  // Phase 4G Keep-failure root cause). `LocalSyncIntent.enqueuedAt` is the
  // one `DateTime`-typed field anywhere in this store's object graph;
  // `encode()` truncates it to whole milliseconds
  // (`toUtc().millisecondsSinceEpoch`) and `tryDecode` reconstructs a
  // zero-microsecond `DateTime`, while `LocalSyncIntent.operator==` compares
  // it with `DateTime.isAtSameMomentAs`, which is exact to the microsecond.
  // A caller that hands this store a raw, uncanonicalized clock value
  // (`DateTime.now()` on a real device routinely carries non-zero
  // microseconds) makes the store's own mandatory `replace-verify-temp`
  // read-back comparison genuinely, correctly fail. These two tests exercise
  // the real `ProtectedLocalSyncIntentStore` -- only the native
  // `FileProtectionBridge` is faked -- to prove both halves of this: an
  // un-canonicalized microsecond timestamp is rejected (this is what a
  // caller that skipped `canonicalizeKeptTimestamp` would have hit in
  // production), and the same source instant, canonicalized first exactly as
  // `KeptSyncIntegrationCoordinator` now does at every `enqueuedAt:`
  // construction site, survives the full real
  // encode->write->protect->verify->rename->protect->verify path and decodes
  // back to the expected millisecond-precise instant.
  // ---------------------------------------------------------------------
  test(
      '26. an intent whose enqueuedAt still carries a non-zero microsecond '
      'remainder (an un-canonicalized real-device clock read) is correctly '
      'rejected by the store\'s own strict post-write verification -- this '
      'is the exact real-device failure a caller that skips '
      'canonicalizeKeptTimestamp before constructing a LocalSyncIntent '
      'would hit', () async {
    final store = buildStore();
    // A raw clock read with a non-zero microsecond remainder -- exactly the
    // shape `DateTime.now()` routinely produces on real iOS hardware, never
    // on the Dart VM's own coarser host-test clock. Deliberately NOT run
    // through `canonicalizeKeptTimestamp` here, to reproduce the pre-fix
    // caller shape against the store's real, unmodified verification logic.
    final uncanonicalizedClockRead =
        DateTime.utc(2026, 8, 9, 12, 0, 0, 123, 456);

    final intent = activeIntent(
      intentId: intentId1,
      enqueuedAt: uncanonicalizedClockRead,
    );

    Object? caught;
    try {
      await store.enqueueIntent(intent);
    } catch (error) {
      caught = error;
    }

    expect(caught, isA<LocalSyncIntentStoreException>());
    final typed = caught as LocalSyncIntentStoreException;
    expect(typed.stage, 'replace-verify-temp');
  });

  test(
      '27. the identical source instant, canonicalized first exactly as '
      'every KeptSyncIntegrationCoordinator enqueuedAt: construction site '
      'now does, survives the real encode->write->protect->verify->'
      'rename->protect->verify round trip and decodes back to the expected '
      'millisecond-canonical instant, with zero microseconds', () async {
    final store = buildStore();
    final rawClockRead = DateTime.utc(2026, 8, 9, 12, 0, 0, 123, 456);
    final canonicalized = canonicalizeKeptTimestamp(rawClockRead);

    // Canonicalization only ever discards the sub-millisecond remainder --
    // it never changes which millisecond instant this is.
    expect(canonicalized, DateTime.utc(2026, 8, 9, 12, 0, 0, 123));
    expect(canonicalized.microsecond, 0);

    final intent = activeIntent(
      intentId: intentId1,
      enqueuedAt: canonicalized,
    );

    // Must not throw: this is the exact real store, with only the native
    // file-protection bridge faked -- a genuine production-shaped write.
    await store.enqueueIntent(intent);

    final loaded = await store.loadIntents();
    expect(loaded, hasLength(1));
    expect(loaded.single.enqueuedAt, canonicalized);
    expect(loaded.single.enqueuedAt.microsecond, 0);
    expect(loaded.single.enqueuedAt.isAtSameMomentAs(canonicalized), isTrue);

    // A fresh load (a second full read-back of the already-committed final
    // file) is exactly as canonical -- this is not a one-shot artifact of
    // the write path.
    final reloaded = await store.loadIntents();
    expect(reloaded.single.enqueuedAt, DateTime.utc(2026, 8, 9, 12, 0, 0, 123));
  });
}
