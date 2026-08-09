// Build 26 Phase 4D-1 (correction round): ProtectedSyncPersistenceStore --
// the atomic, protected, file-backed durable sync-state and outbox store,
// now with a mandatory account-scoped dataEpoch and pending-mutation
// supersession. Synthetic content only; no real MethodChannel or CloudKit
// access anywhere in this file.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/persistence/file_protection_bridge.dart';
import 'package:wisdom_app/sync/cloud_kept_wisdom_projection.dart';
import 'package:wisdom_app/sync/data_epoch.dart';
import 'package:wisdom_app/sync/sync_change.dart';
import 'package:wisdom_app/sync_persistence/account_sync_state.dart';
import 'package:wisdom_app/sync_persistence/associated_account_fingerprint_commit.dart';
import 'package:wisdom_app/sync_persistence/persisted_outbox_mutation.dart';
import 'package:wisdom_app/sync_persistence/protected_sync_persistence_store.dart';
import 'package:wisdom_app/sync_persistence/sync_persistence_envelope.dart';
import 'package:wisdom_app/sync_persistence/sync_persistence_store.dart';

/// Fake [FileProtectionBridge] -- identical in shape and intent to the one
/// already used throughout `test/protected_file_kept_state_store_test.dart`.
/// No real MethodChannel is involved anywhere in this file.
class _FakeFileProtectionBridge implements FileProtectionBridge {
  final List<String> protectedPaths = [];
  final Map<String, int> _remainingFailures = {};
  final Map<String, int> _callCounts = {};
  Future<void> Function(String path)? onProtect;

  void failNextTimeFor(String path, {int times = 1}) {
    _remainingFailures[path] = (_remainingFailures[path] ?? 0) + times;
  }

  /// Cumulative number of times [protectAndVerifyComplete] has been called
  /// for [path] so far (including the call currently completing, since this
  /// is only ever read either before or after a call, never from inside
  /// one).
  ///
  /// A read-modify-write operation such as `storeServerChangeToken` calls
  /// `protectAndVerifyComplete(finalPath)` **twice** even in the ordinary
  /// success case: once inside `_loadEnvelope`'s own post-decode re-verify
  /// of the file it just read, and again inside `_replaceEnvelope`'s
  /// post-rename verify. `failNextTimeFor`/`onProtect` alone cannot target
  /// only the second of those without also catching the first -- so a test
  /// that wants to simulate a failure at one specific stage should capture
  /// `callCountFor(path)` as a baseline immediately before triggering the
  /// operation under test, then match on `baseline + N` for the Nth call
  /// from that point on.
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
        Directory.systemTemp.createTempSync('sync_persistence_store_test_');
  });

  tearDown(() {
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  String dirPath() => '${tempRoot.path}/east_sync_state';
  String finalPath() => '${dirPath()}/east_sync_state_v1.json';
  String tempPathFor(String token) =>
      '${dirPath()}/.east_sync_state_v1.tmp-$token.json';
  String backupPathFor(String token) =>
      '${dirPath()}/.east_sync_state_v1.backup-$token.json';

  ProtectedSyncPersistenceStore buildStore({
    FileProtectionBridge? bridge,
    String Function()? tokenFactory,
    DateTime Function()? clock,
  }) {
    var counter = 0;
    return ProtectedSyncPersistenceStore(
      rootDirectoryProvider: () async => tempRoot,
      fileProtectionBridge: bridge ?? _FakeFileProtectionBridge(),
      tokenFactory: tokenFactory ?? (() => 'token-${counter++}'),
      clock: clock ?? (() => DateTime.utc(2026, 8, 1, 12, 0)),
    );
  }

  const fingerprintA =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const fingerprintB =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  final epoch = DataEpoch.parse('12121212-1212-4212-8212-121212121212');
  final otherEpoch = DataEpoch.parse('34343434-3434-4434-8434-343434343434');

  CloudKeptWisdomProjection activeProjection({
    required String revealId,
    String wisdomText = 'Synthetic wisdom text for testing only.',
    int updatedAtMs = 3000,
    String? mutationId,
    DataEpoch? dataEpoch,
    bool hasReflection = false,
  }) {
    return CloudKeptWisdomProjection.tryParseRemote({
      'recordName': 'east-kept-$revealId',
      'isTombstone': false,
      'revealId': revealId,
      'wisdomText': wisdomText,
      'revealedAtMs': 1000,
      'keptAtMs': 2000,
      if (hasReflection) 'reflectionText': 'A synthetic reflection.',
      if (hasReflection) 'reflectedAtMs': updatedAtMs,
      'updatedAtMs': updatedAtMs,
      'mutationId': mutationId ?? _mutationIdFor(revealId),
      'dataEpoch': (dataEpoch ?? epoch).value,
      'schemaVersion': 3,
    })!;
  }

  SyncChange createChangeFor(
    String revealId, {
    DateTime? enqueuedAt,
    String wisdomText = 'Synthetic wisdom text for testing only.',
    String? mutationId,
    DataEpoch? dataEpoch,
    bool hasReflection = false,
    int updatedAtMs = 3000,
  }) {
    return SyncChange(
      kind: SyncChangeKind.create,
      projection: activeProjection(
        revealId: revealId,
        wisdomText: wisdomText,
        mutationId: mutationId,
        dataEpoch: dataEpoch,
        hasReflection: hasReflection,
        updatedAtMs: updatedAtMs,
      ),
      enqueuedAt: enqueuedAt ?? DateTime.utc(2026, 8, 1, 10),
    );
  }

  SyncChange createTombstoneChangeFor(
    String revealId, {
    DateTime? enqueuedAt,
    String? mutationId,
    DataEpoch? dataEpoch,
  }) {
    return SyncChange(
      kind: SyncChangeKind.delete,
      projection: CloudKeptWisdomProjection.tryParseRemote({
        'recordName': 'east-kept-$revealId',
        'isTombstone': true,
        'deletedAtMs': 5000,
        'updatedAtMs': 6000,
        'mutationId': mutationId ?? _tombstoneMutationIdFor(revealId),
        'dataEpoch': (dataEpoch ?? epoch).value,
        'schemaVersion': 1,
      })!,
      enqueuedAt: enqueuedAt ?? DateTime.utc(2026, 8, 1, 10),
    );
  }

  const revealId1 = 'aaaaaaaa-1111-4111-8111-111111111111';
  const revealId2 = 'bbbbbbbb-1111-4111-8111-111111111111';
  const revealId3 = 'cccccccc-1111-4111-8111-111111111111';
  const validToken = 'b3BhcXVlLXRva2Vu';
  const validSystemFields = 'c3lzdGVtLWZpZWxkcw==';

  // -------------------------------------------------------------------
  // Group A: load / account isolation
  // -------------------------------------------------------------------

  test(
      '1. loadAccountState returns null when nothing has ever been '
      'persisted', () async {
    final store = buildStore();
    expect(await store.loadAccountState(fingerprintA), isNull);
  });

  test(
      '2. replaceAccountState round-trips a full state including '
      'dataEpoch', () async {
    final store = buildStore();
    await store.replaceAccountState(
        fingerprintA, AccountSyncState.empty(epoch));
    final loaded = await store.loadAccountState(fingerprintA);
    expect(loaded, AccountSyncState.empty(epoch));
    expect(loaded!.dataEpoch, epoch);
  });

  test('3. two account fingerprints never mix', () async {
    final store = buildStore();
    await store.enqueueMutation(fingerprintA, createChangeFor(revealId1));
    await store.enqueueMutation(fingerprintB, createChangeFor(revealId2));
    await store.storeServerChangeToken(fingerprintA, 'QQQQ');
    await store.storeServerChangeToken(fingerprintB, 'Qkkk');

    final a = await store.loadAccountState(fingerprintA);
    final b = await store.loadAccountState(fingerprintB);
    expect(a!.serverChangeToken, 'QQQQ');
    expect(b!.serverChangeToken, 'Qkkk');
  });

  test(
      '4. an unresolved/unknown fingerprint never surfaces another '
      "account's state", () async {
    final store = buildStore();
    await store.enqueueMutation(fingerprintA, createChangeFor(revealId1));

    const unknownFingerprint =
        'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
    expect(await store.loadAccountState(unknownFingerprint), isNull);
  });

  // -------------------------------------------------------------------
  // Group B: dataEpoch enforcement
  // -------------------------------------------------------------------

  test(
      '5. enqueueMutation on a fresh fingerprint creates the bucket using '
      "the mutation's own dataEpoch -- never a default", () async {
    final store = buildStore();
    await store.enqueueMutation(fingerprintA, createChangeFor(revealId1));

    final loaded = await store.loadAccountState(fingerprintA);
    expect(loaded!.dataEpoch, epoch);
  });

  test(
      '6. an enqueue whose dataEpoch does not match the existing bucket '
      'fails closed', () async {
    final store = buildStore();
    await store.enqueueMutation(fingerprintA, createChangeFor(revealId1));

    final mismatched = createChangeFor(revealId2, dataEpoch: otherEpoch);
    await expectLater(
      store.enqueueMutation(fingerprintA, mismatched),
      throwsA(isA<MutationEpochMismatchException>()),
    );

    // The queue is unaffected by the rejected attempt.
    final pending = await store.readPendingMutations(fingerprintA);
    expect(pending, hasLength(1));
  });

  test(
      '7. a persisted mutation whose own dataEpoch differs from its '
      "account bucket's dataEpoch fails the whole load closed", () async {
    final store = buildStore();
    final mismatchedMutation = PersistedOutboxMutation(
      change: createChangeFor(revealId1, dataEpoch: otherEpoch),
    );
    await Directory(dirPath()).create(recursive: true);
    await File(finalPath()).writeAsString(jsonEncode({
      'schemaVersion': 1,
      'accounts': {
        fingerprintA: {
          'dataEpoch': epoch.value,
          'recordSystemFields': <String, dynamic>{},
          'outbox': [mismatchedMutation.encode()],
        },
      },
      'quarantinedAccounts': <String, dynamic>{},
    }));

    await expectLater(
      store.loadAccountState(fingerprintA),
      throwsA(isA<SyncPersistenceStoreException>()),
    );
  });

  test('8. clearing the server token preserves dataEpoch and the outbox',
      () async {
    final store = buildStore();
    await store.enqueueMutation(fingerprintA, createChangeFor(revealId1));
    await store.storeServerChangeToken(fingerprintA, validToken);

    await store.clearServerChangeToken(fingerprintA);

    final loaded = await store.loadAccountState(fingerprintA);
    expect(loaded!.serverChangeToken, isNull);
    expect(loaded.dataEpoch, epoch);
    expect(loaded.outbox, hasLength(1));
  });

  // -------------------------------------------------------------------
  // Group C: opaque server token
  // -------------------------------------------------------------------

  test('9. the server token round-trips byte-for-byte, uninterpreted',
      () async {
    final store = buildStore();
    await store.enqueueMutation(fingerprintA, createChangeFor(revealId1));
    await store.storeServerChangeToken(fingerprintA, validToken);
    final loaded = await store.loadAccountState(fingerprintA);
    expect(loaded!.serverChangeToken, validToken);
  });

  test('10. a failure exception never renders the token in its message',
      () async {
    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge);
    await store.enqueueMutation(fingerprintA, createChangeFor(revealId1));
    await store.storeServerChangeToken(fingerprintA, validToken);

    bridge.failNextTimeFor(finalPath());
    Object? caught;
    try {
      await store.storeServerChangeToken(fingerprintA, 'anotherToken');
    } catch (error) {
      caught = error;
    }
    expect(caught, isNotNull);
    expect(caught.toString(), isNot(contains(validToken)));
  });

  test('11. a corrupt token on disk fails the whole load closed', () async {
    final store = buildStore();
    await Directory(dirPath()).create(recursive: true);
    await File(finalPath()).writeAsString(jsonEncode({
      'schemaVersion': 1,
      'accounts': {
        fingerprintA: {
          'dataEpoch': epoch.value,
          'serverChangeToken': 'not valid base64!!',
          'recordSystemFields': <String, dynamic>{},
          'outbox': <dynamic>[],
        },
      },
      'quarantinedAccounts': <String, dynamic>{},
    }));

    await expectLater(
      store.loadAccountState(fingerprintA),
      throwsA(isA<SyncPersistenceStoreException>()),
    );
  });

  test(
      '12. storeServerChangeToken/replaceRecordSystemFields refuse to '
      'fabricate an epoch for a brand-new fingerprint', () async {
    final store = buildStore();
    await expectLater(
      store.storeServerChangeToken(fingerprintA, validToken),
      throwsA(isA<SyncPersistenceStoreException>()),
    );
    await expectLater(
      store.replaceRecordSystemFields(
        fingerprintA,
        'east-kept-$revealId1',
        validSystemFields,
      ),
      throwsA(isA<SyncPersistenceStoreException>()),
    );
  });

  // -------------------------------------------------------------------
  // Group D: outbox enqueue / identity / idempotency
  // -------------------------------------------------------------------

  test('13. enqueueMutation stores an active mutation', () async {
    final store = buildStore();
    await store.enqueueMutation(fingerprintA, createChangeFor(revealId1));

    final pending = await store.readPendingMutations(fingerprintA);
    expect(pending, hasLength(1));
    expect(pending.single.change.kind, SyncChangeKind.create);
  });

  test('14. enqueueMutation stores a tombstone mutation', () async {
    final store = buildStore();
    await store.enqueueMutation(
      fingerprintA,
      createTombstoneChangeFor(revealId1),
    );
    final pending = await store.readPendingMutations(fingerprintA);
    expect(pending.single.change.projection.isTombstone, isTrue);
  });

  test('15. an exact duplicate enqueue is idempotent', () async {
    final store = buildStore();
    final change = createChangeFor(revealId1);

    await store.enqueueMutation(fingerprintA, change);
    await store.enqueueMutation(fingerprintA, change);

    final pending = await store.readPendingMutations(fingerprintA);
    expect(pending, hasLength(1));
  });

  test('16. the same mutationId with different content fails closed', () async {
    final store = buildStore();
    final first = createChangeFor(revealId1);
    await store.enqueueMutation(fingerprintA, first);

    final conflicting = createChangeFor(
      revealId1,
      wisdomText: 'Different text, same mutationId -- must be rejected.',
      updatedAtMs: 9999,
    );

    await expectLater(
      store.enqueueMutation(fingerprintA, conflicting),
      throwsA(isA<ConflictingMutationIdentityException>()),
    );
  });

  test(
      '17. two different revealIds with exactly the same wisdom text '
      'enqueue as two independent, valid outbox entries', () async {
    final store = buildStore();
    final one = createChangeFor(revealId1, wisdomText: 'Identical text.');
    final two = createChangeFor(revealId2, wisdomText: 'Identical text.');

    await store.enqueueMutation(fingerprintA, one);
    await store.enqueueMutation(fingerprintA, two);

    final pending = await store.readPendingMutations(fingerprintA);
    expect(pending, hasLength(2));
  });

  // -------------------------------------------------------------------
  // Group E: pending-mutation supersession (the core correction)
  // -------------------------------------------------------------------

  test(
      '18. a newer active mutation (adding a Reflection) supersedes the '
      'pending mutation for the same record, in place', () async {
    final store = buildStore();
    final firstEnqueuedAt = DateTime.utc(2026, 8, 1, 9);
    final keepOnly = createChangeFor(
      revealId1,
      enqueuedAt: firstEnqueuedAt,
      mutationId: 'aaaa0000-0000-4000-8000-000000000001',
    );
    await store.enqueueMutation(fingerprintA, keepOnly);

    final keepWithReflection = createChangeFor(
      revealId1,
      enqueuedAt: DateTime.utc(2026, 8, 1, 11), // later local edit
      mutationId: 'aaaa0000-0000-4000-8000-000000000002',
      hasReflection: true,
      updatedAtMs: 5000,
    );
    await store.enqueueMutation(fingerprintA, keepWithReflection);

    final pending = await store.readPendingMutations(fingerprintA);
    expect(pending, hasLength(1)); // exactly one mutation for the record
    expect(
      pending.single.mutationId,
      'aaaa0000-0000-4000-8000-000000000002',
    );
    expect(pending.single.change.projection.reflectionText, isNotNull);
  });

  test('19. acknowledging the superseded (old) mutationId removes nothing',
      () async {
    final store = buildStore();
    final first = createChangeFor(
      revealId1,
      mutationId: 'aaaa0000-0000-4000-8000-000000000001',
    );
    await store.enqueueMutation(fingerprintA, first);
    final second = createChangeFor(
      revealId1,
      mutationId: 'aaaa0000-0000-4000-8000-000000000002',
      hasReflection: true,
      updatedAtMs: 5000,
    );
    await store.enqueueMutation(fingerprintA, second);

    await store.applyMutationOutcomes(
      fingerprintA,
      acknowledgedMutationIds: {'aaaa0000-0000-4000-8000-000000000001'},
    );

    final pending = await store.readPendingMutations(fingerprintA);
    expect(pending, hasLength(1));
    expect(pending.single.mutationId, 'aaaa0000-0000-4000-8000-000000000002');
  });

  test('20. acknowledging the current mutationId removes the replacement',
      () async {
    final store = buildStore();
    final first = createChangeFor(
      revealId1,
      mutationId: 'aaaa0000-0000-4000-8000-000000000001',
    );
    await store.enqueueMutation(fingerprintA, first);
    final second = createChangeFor(
      revealId1,
      mutationId: 'aaaa0000-0000-4000-8000-000000000002',
      hasReflection: true,
      updatedAtMs: 5000,
    );
    await store.enqueueMutation(fingerprintA, second);

    await store.applyMutationOutcomes(
      fingerprintA,
      acknowledgedMutationIds: {'aaaa0000-0000-4000-8000-000000000002'},
    );

    final pending = await store.readPendingMutations(fingerprintA);
    expect(pending, isEmpty);
  });

  test(
      '21. an active mutation is safely superseded by a tombstone before '
      'upload', () async {
    final store = buildStore();
    await store.enqueueMutation(fingerprintA, createChangeFor(revealId1));
    await store.enqueueMutation(
      fingerprintA,
      createTombstoneChangeFor(revealId1),
    );

    final pending = await store.readPendingMutations(fingerprintA);
    expect(pending, hasLength(1));
    expect(pending.single.change.projection.isTombstone, isTrue);
    expect(pending.single.change.kind, SyncChangeKind.delete);
  });

  test(
      '22. a pending tombstone is safely superseded by an active mutation '
      'before upload', () async {
    final store = buildStore();
    await store.enqueueMutation(
      fingerprintA,
      createTombstoneChangeFor(revealId1),
    );
    await store.enqueueMutation(fingerprintA, createChangeFor(revealId1));

    final pending = await store.readPendingMutations(fingerprintA);
    expect(pending, hasLength(1));
    expect(pending.single.change.projection.isTombstone, isFalse);
    expect(pending.single.change.kind, SyncChangeKind.create);
  });

  test(
      '23. system fields remain associated with a record by identity '
      'across a supersession', () async {
    final store = buildStore();
    await store.enqueueMutation(fingerprintA, createChangeFor(revealId1));
    await store.replaceRecordSystemFields(
      fingerprintA,
      'east-kept-$revealId1',
      validSystemFields,
    );

    await store.enqueueMutation(
      fingerprintA,
      createChangeFor(
        revealId1,
        mutationId: 'aaaa0000-0000-4000-8000-000000000099',
        hasReflection: true,
        updatedAtMs: 7000,
      ),
    );

    final loaded = await store.loadAccountState(fingerprintA);
    // Supersession never fabricates or discards system fields -- they stay
    // exactly where they were, associated by record name.
    expect(
      loaded!.recordSystemFields['east-kept-$revealId1'],
      validSystemFields,
    );
  });

  test(
      '24. unrelated-record ordering remains deterministic even while one '
      'record is repeatedly superseded', () async {
    final store = buildStore();
    await store.enqueueMutation(fingerprintA, createChangeFor(revealId2));
    await store.enqueueMutation(fingerprintA, createChangeFor(revealId1));
    await store.enqueueMutation(fingerprintA, createChangeFor(revealId3));

    // Edit revealId1 again -- must supersede in its own original slot
    // (position 1), never move to the end.
    await store.enqueueMutation(
      fingerprintA,
      createChangeFor(
        revealId1,
        mutationId: 'aaaa0000-0000-4000-8000-000000000077',
        hasReflection: true,
        updatedAtMs: 8000,
      ),
    );

    final pending = await store.readPendingMutations(fingerprintA);
    expect(pending.map((e) => e.recordName).toList(), [
      'east-kept-$revealId2',
      'east-kept-$revealId1',
      'east-kept-$revealId3',
    ]);
    expect(
      pending[1].mutationId,
      'aaaa0000-0000-4000-8000-000000000077',
    );
  });

  test(
      '25. concurrent enqueues for the same brand-new record serialize '
      'without ever producing two entries for that record', () async {
    final store = buildStore();
    // Establish the bucket first (sequential), for an unrelated record.
    await store.enqueueMutation(fingerprintA, createChangeFor(revealId2));

    final first = store.enqueueMutation(
      fingerprintA,
      createChangeFor(
        revealId1,
        mutationId: 'aaaa0000-0000-4000-8000-0000000000a1',
      ),
    );
    final second = store.enqueueMutation(
      fingerprintA,
      createChangeFor(
        revealId1,
        mutationId: 'aaaa0000-0000-4000-8000-0000000000a2',
        hasReflection: true,
        updatedAtMs: 9000,
      ),
    );

    await Future.wait([first, second]);

    final pending = await store.readPendingMutations(fingerprintA);
    final forRecordOne =
        pending.where((e) => e.recordName == 'east-kept-$revealId1').toList();
    expect(forRecordOne, hasLength(1));
  });

  // -------------------------------------------------------------------
  // Group F: mutation outcomes (ack / failed / conflicted / retryable)
  // -------------------------------------------------------------------

  test('26. partial acknowledgment removes only the confirmed successes',
      () async {
    final store = buildStore();
    final changeOne = createChangeFor(revealId1);
    final changeTwo = createChangeFor(revealId2);
    await store.enqueueMutation(fingerprintA, changeOne);
    await store.enqueueMutation(fingerprintA, changeTwo);

    await store.applyMutationOutcomes(
      fingerprintA,
      acknowledgedMutationIds: {changeOne.projection.mutationId},
    );

    final pending = await store.readPendingMutations(fingerprintA);
    expect(pending, hasLength(1));
    expect(pending.single.mutationId, changeTwo.projection.mutationId);
  });

  test('27. a permanently-failed mutation remains queued, marked failed',
      () async {
    final store = buildStore();
    final change = createChangeFor(revealId1);
    await store.enqueueMutation(fingerprintA, change);

    await store.applyMutationOutcomes(
      fingerprintA,
      updatedStatusByMutationId: {
        change.projection.mutationId: PersistedOutboxMutationStatus.failed,
      },
    );

    final pending = await store.readPendingMutations(fingerprintA);
    expect(pending, hasLength(1));
    expect(pending.single.status, PersistedOutboxMutationStatus.failed);
  });

  test('28. a conflicted mutation remains queued and distinguishable',
      () async {
    final store = buildStore();
    final change = createChangeFor(revealId1);
    await store.enqueueMutation(fingerprintA, change);

    await store.applyMutationOutcomes(
      fingerprintA,
      updatedStatusByMutationId: {
        change.projection.mutationId: PersistedOutboxMutationStatus.conflicted,
      },
    );

    final pending = await store.readPendingMutations(fingerprintA);
    expect(pending.single.status, PersistedOutboxMutationStatus.conflicted);
  });

  test(
      '29. a retryable failure (empty outcome maps) never mutates the '
      'queue', () async {
    final store = buildStore();
    final change = createChangeFor(revealId1);
    await store.enqueueMutation(fingerprintA, change);

    await store.applyMutationOutcomes(fingerprintA);

    final pending = await store.readPendingMutations(fingerprintA);
    expect(pending.single.status, PersistedOutboxMutationStatus.pending);
  });

  // -------------------------------------------------------------------
  // Group G: strict parsing / corruption
  // -------------------------------------------------------------------

  test('30. corrupt system fields on disk fail the whole load closed',
      () async {
    final store = buildStore();
    await Directory(dirPath()).create(recursive: true);
    await File(finalPath()).writeAsString(jsonEncode({
      'schemaVersion': 1,
      'accounts': {
        fingerprintA: {
          'dataEpoch': epoch.value,
          'recordSystemFields': {
            'east-kept-$revealId1': 'not valid base64!!',
          },
          'outbox': <dynamic>[],
        },
      },
      'quarantinedAccounts': <String, dynamic>{},
    }));

    await expectLater(
      store.loadAccountState(fingerprintA),
      throwsA(isA<SyncPersistenceStoreException>()),
    );
  });

  test('31. an unrecognized top-level key on disk fails the load closed',
      () async {
    final store = buildStore();
    await Directory(dirPath()).create(recursive: true);
    await File(finalPath()).writeAsString(jsonEncode({
      'schemaVersion': 1,
      'accounts': <String, dynamic>{},
      'quarantinedAccounts': <String, dynamic>{},
      'somethingUnexpected': true,
    }));

    await expectLater(
      store.loadAccountState(fingerprintA),
      throwsA(isA<SyncPersistenceStoreException>()),
    );
  });

  test('32. an unsupported schema version on disk fails the load closed',
      () async {
    final store = buildStore();
    await Directory(dirPath()).create(recursive: true);
    await File(finalPath()).writeAsString(jsonEncode({
      'schemaVersion': 99,
      'accounts': <String, dynamic>{},
    }));

    await expectLater(
      store.loadAccountState(fingerprintA),
      throwsA(isA<SyncPersistenceStoreException>()),
    );
  });

  test(
      '33. a malformed (non-fingerprint-shaped) account key on disk fails '
      'the load closed', () async {
    final store = buildStore();
    await Directory(dirPath()).create(recursive: true);
    await File(finalPath()).writeAsString(jsonEncode({
      'schemaVersion': 1,
      'accounts': {
        'not-a-valid-fingerprint': AccountSyncState.empty(epoch).encode(),
      },
    }));

    await expectLater(
      store.loadAccountState(fingerprintA),
      throwsA(isA<SyncPersistenceStoreException>()),
    );
  });

  test(
      '34. two persisted outbox entries sharing the same recordName '
      '(a malformed duplicate record identity) fail the load closed', () async {
    final store = buildStore();
    final entryOne =
        PersistedOutboxMutation(change: createChangeFor(revealId1));
    final entryTwo = PersistedOutboxMutation(
      change: createChangeFor(
        revealId1,
        mutationId: 'ffffffff-9999-4999-8999-999999999999',
        updatedAtMs: 9999,
      ),
    );
    await Directory(dirPath()).create(recursive: true);
    await File(finalPath()).writeAsString(jsonEncode({
      'schemaVersion': 1,
      'accounts': {
        fingerprintA: {
          'dataEpoch': epoch.value,
          'recordSystemFields': <String, dynamic>{},
          'outbox': [entryOne.encode(), entryTwo.encode()],
        },
      },
      'quarantinedAccounts': <String, dynamic>{},
    }));

    await expectLater(
      store.loadAccountState(fingerprintA),
      throwsA(isA<SyncPersistenceStoreException>()),
    );
  });

  // -------------------------------------------------------------------
  // Group H: atomic-write failure injection
  // -------------------------------------------------------------------

  test(
      '35. a temporary-file protection failure preserves the previous '
      'final file', () async {
    final bridge = _FakeFileProtectionBridge();
    var counter = 0;
    final store = ProtectedSyncPersistenceStore(
      rootDirectoryProvider: () async => tempRoot,
      fileProtectionBridge: bridge,
      tokenFactory: () => 'token-${counter++}',
      clock: () => DateTime.utc(2026, 8, 1, 12, 0),
    );
    await store.enqueueMutation(fingerprintA, createChangeFor(revealId1));
    await store.storeServerChangeToken(fingerprintA, validToken);

    bridge.failNextTimeFor(tempPathFor('token-2'));

    await expectLater(
      store.storeServerChangeToken(fingerprintA, 'replacementToken'),
      throwsA(isA<SyncPersistenceStoreException>()),
    );

    final loaded = await store.loadAccountState(fingerprintA);
    expect(loaded!.serverChangeToken, validToken);
  });

  test(
      '36. a temp-file verification mismatch preserves the previous final '
      'file', () async {
    final bridge = _FakeFileProtectionBridge();
    var counter = 0;
    final store = ProtectedSyncPersistenceStore(
      rootDirectoryProvider: () async => tempRoot,
      fileProtectionBridge: bridge,
      tokenFactory: () => 'token-${counter++}',
      clock: () => DateTime.utc(2026, 8, 1, 12, 0),
    );
    await store.enqueueMutation(fingerprintA, createChangeFor(revealId1));
    await store.storeServerChangeToken(fingerprintA, validToken);

    bridge.onProtect = (path) async {
      if (path == tempPathFor('token-2')) {
        await File(path).writeAsString('{"corrupted": true}');
      }
    };

    await expectLater(
      store.storeServerChangeToken(fingerprintA, 'replacementToken'),
      throwsA(isA<SyncPersistenceStoreException>()),
    );

    bridge.onProtect = null;
    final loaded = await store.loadAccountState(fingerprintA);
    expect(loaded!.serverChangeToken, validToken);
  });

  test(
      '37. a final-file protection failure (with an existing prior final) '
      'preserves the previous final file', () async {
    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge);
    await store.enqueueMutation(fingerprintA, createChangeFor(revealId1));
    await store.storeServerChangeToken(fingerprintA, validToken);

    // The next storeServerChangeToken call below makes two calls to
    // protectAndVerifyComplete(finalPath()) even on a normal path: the
    // first happens inside _loadEnvelope's own post-decode re-verify of the
    // *already-valid* existing final file (a read-time check -- not the
    // stage this test targets); the second happens inside
    // _replaceEnvelope's post-rename verify (the actual final-protection
    // stage under test). Failing on finalPath() indiscriminately hits the
    // first call and proves nothing about the second -- so this targets
    // exactly the second call from this point forward, and lets the first
    // (load-time) call succeed normally.
    final baseline = bridge.callCountFor(finalPath());
    bridge.onProtect = (path) async {
      if (path == finalPath() && bridge.callCountFor(path) == baseline + 2) {
        throw const FileProtectionException('Simulated protection failure.');
      }
    };

    Object? caught;
    try {
      await store.storeServerChangeToken(fingerprintA, 'replacementToken');
    } catch (error) {
      caught = error;
    }
    bridge.onProtect = null;

    expect(caught, isA<SyncPersistenceStoreException>());
    final typed = caught as SyncPersistenceStoreException;
    // The existing naming convention (mirroring
    // ProtectedFileKeptStateStore/KeptStateStoreException) identifies a
    // post-rename final-protection failure as 'replace-post-rename'.
    expect(typed.stage, 'replace-post-rename');
    expect(typed.toString(), isNot(contains(validToken)));
    expect(typed.toString(), isNot(contains(finalPath())));
    expect(typed.toString(), isNot(contains(fingerprintA)));
    // A raw rollback failure/protection error is retained internally
    // (`.cause`, itself possibly a `_CombinedFailure`) but never rendered.
    expect(typed.cause, isNotNull);
    expect(typed.toString(), isNot(contains(typed.cause.toString())));

    // The prior authoritative file is restored byte-for-byte, and a
    // subsequent load returns the prior envelope -- no temporary corrupt
    // final remains.
    final loaded = await store.loadAccountState(fingerprintA);
    expect(loaded!.serverChangeToken, validToken);
    expect(loaded.dataEpoch, epoch);
    final corruptFiles = await tempRoot
        .list(recursive: true)
        .where((entity) => entity is File && entity.path.contains('.corrupt-'))
        .toList();
    expect(corruptFiles, isEmpty);
  });

  test(
      '38. a final-file verification failure restores the previous final '
      'file', () async {
    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge);
    await store.enqueueMutation(fingerprintA, createChangeFor(revealId1));
    await store.storeServerChangeToken(fingerprintA, validToken);

    // Same call-sequence reasoning as test 37: only the *second* call to
    // protectAndVerifyComplete(finalPath()) from this point on -- the
    // post-rename read-back verification -- should observe a corrupt file.
    // The first (load-time) call must see the still-valid existing final,
    // exactly as an ordinary, uneventful load would.
    final baseline = bridge.callCountFor(finalPath());
    bridge.onProtect = (path) async {
      if (path == finalPath() && bridge.callCountFor(path) == baseline + 2) {
        await File(path).writeAsString('{"corrupted": true}');
      }
    };

    Object? caught;
    try {
      await store.storeServerChangeToken(fingerprintA, 'replacementToken');
    } catch (error) {
      caught = error;
    }
    bridge.onProtect = null;

    expect(caught, isA<SyncPersistenceStoreException>());
    final typed = caught as SyncPersistenceStoreException;
    expect(typed.stage, 'replace-post-rename');
    expect(typed.toString(), isNot(contains(validToken)));
    // The underlying decode/protection failure is retained internally but
    // never rendered.
    expect(typed.cause, isNotNull);
    expect(typed.toString(), isNot(contains(typed.cause.toString())));

    // Prior authoritative bytes are restored exactly; a subsequent load
    // returns the prior envelope; no corrupt authoritative state remains;
    // no outbox/token/epoch data was silently lost.
    final loaded = await store.loadAccountState(fingerprintA);
    expect(loaded!.serverChangeToken, validToken);
    expect(loaded.dataEpoch, epoch);
    expect(loaded.outbox, hasLength(1));
  });

  test(
      '38b. an actual load-time protection failure (distinct from a decode '
      'failure) is wrapped, never leaked raw, and never destroys the '
      'authoritative file', () async {
    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge);
    await store.enqueueMutation(fingerprintA, createChangeFor(revealId1));
    await store.storeServerChangeToken(fingerprintA, validToken);

    // Fail only the very next protectAndVerifyComplete(finalPath()) call --
    // the one loadAccountState's own _loadEnvelope performs immediately
    // after successfully reading and decoding the (perfectly valid) final
    // file. This is a pure load-time protection failure: never a decode
    // failure, and never any write at all.
    bridge.failNextTimeFor(finalPath());

    Object? caught;
    try {
      await store.loadAccountState(fingerprintA);
    } catch (error) {
      caught = error;
    }

    expect(caught, isA<SyncPersistenceStoreException>());
    final typed = caught as SyncPersistenceStoreException;
    expect(typed.stage, 'load-protect');
    expect(typed.cause, isA<FileProtectionException>());
    expect(typed.toString(), isNot(contains(validToken)));
    expect(typed.toString(), isNot(contains(finalPath())));
    expect(typed.toString(), isNot(contains(fingerprintA)));
    // The cause is retained internally (asserted above) but never rendered.
    expect(typed.toString(), isNot(contains(typed.cause.toString())));

    // The authoritative file itself was never deleted, reset, or rewritten
    // merely because its post-read protection re-verify failed.
    expect(File(finalPath()).existsSync(), isTrue);

    // A subsequent, unimpeded load still returns the untouched prior
    // state -- no outbox/token/epoch data was lost.
    final loaded = await store.loadAccountState(fingerprintA);
    expect(loaded!.serverChangeToken, validToken);
    expect(loaded.dataEpoch, epoch);
    expect(loaded.outbox, hasLength(1));
  });

  test(
      '38c. a backup-recovery final-protection failure is typed and '
      'preserves the recoverable backup', () async {
    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge);

    // Fixture: a valid account envelope -- explicit dataEpoch, a non-empty
    // outbox, and an opaque server token -- persisted only as a *backup*
    // file. The authoritative final is deliberately absent, so loading
    // must go through _recoverFromBackupIfFinalAbsent.
    final state = AccountSyncState(
      dataEpoch: epoch,
      serverChangeToken: validToken,
      outbox: [PersistedOutboxMutation(change: createChangeFor(revealId1))],
    );
    final envelope =
        SyncPersistenceEnvelope.empty().withAccount(fingerprintA, state);
    await Directory(dirPath()).create(recursive: true);
    final backupPath = backupPathFor('existing-backup');
    final originalBackupBytes = envelope.encodeString();
    await File(backupPath).writeAsString(originalBackupBytes);
    expect(File(finalPath()).existsSync(), isFalse);

    // Fail only the one protectAndVerifyComplete(finalPath()) call
    // recovery performs -- the post-rename verification of the restored
    // authoritative final -- and never during backup listing, reading,
    // decoding, or the separate recovery-temp write/protect/verify stages
    // (none of which ever touch finalPath at all; recovery now stages a
    // dedicated recovery-temp file and only renames *that* into place,
    // rather than renaming the backup itself).
    final baseline = bridge.callCountFor(finalPath());
    bridge.onProtect = (path) async {
      if (path == finalPath() && bridge.callCountFor(path) == baseline + 1) {
        throw const FileProtectionException('Simulated protection failure.');
      }
    };

    Object? caught;
    try {
      await store.loadAccountState(fingerprintA);
    } catch (error) {
      caught = error;
    }

    expect(caught, isA<SyncPersistenceStoreException>());
    final typed = caught as SyncPersistenceStoreException;
    // Distinct from a final *verification* failure (test 38e/38g below):
    // this is purely an infrastructure/bridge protection failure.
    expect(typed.stage, 'load-recover-protect-final');
    expect(typed.cause, isA<FileProtectionException>());
    expect(typed.toString(), isNot(contains(validToken)));
    expect(typed.toString(), isNot(contains(finalPath())));
    expect(typed.toString(), isNot(contains(backupPath)));
    expect(typed.toString(), isNot(contains(fingerprintA)));
    // The cause is retained internally (asserted above) but never rendered.
    expect(typed.toString(), isNot(contains(typed.cause.toString())));

    // The actual guarantee under test: the original backup was never
    // renamed away and never touched at all -- it remains exactly,
    // byte-for-byte, at its own backup path. A rename-directly-into-
    // finalPath design (the prior, defective implementation) would have
    // already consumed it by this point, leaving nothing recoverable if
    // this same protection call then failed.
    expect(File(backupPath).existsSync(), isTrue);
    final backupBytesAfterFailure = await File(backupPath).readAsString();
    expect(backupBytesAfterFailure, originalBackupBytes);

    // No unverified final is left behind to be mistakenly trusted, and no
    // stray recovery-temporary file remains either.
    expect(File(finalPath()).existsSync(), isFalse);
    final leftoverRecoveryTempFiles = await tempRoot
        .list(recursive: true)
        .where((entity) => entity is File && entity.path.contains('.recover-'))
        .toList();
    expect(leftoverRecoveryTempFiles, isEmpty);

    // Disable the injected failure and confirm the next load retries
    // recovery from that same preserved backup, recovering the exact
    // dataEpoch, server change token, and full outbox -- no mutation,
    // token, or epoch was silently lost. The backup is removed only now,
    // after this later successful recovery and final verification.
    bridge.onProtect = null;
    final loaded = await store.loadAccountState(fingerprintA);
    expect(loaded!.dataEpoch, epoch);
    expect(loaded.serverChangeToken, validToken);
    expect(loaded.outbox, hasLength(1));
    expect(File(backupPath).existsSync(), isFalse);
  });

  test(
      '38e. a backup-recovery final read-back corruption fails closed and '
      'preserves the recoverable backup', () async {
    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge);

    final state = AccountSyncState(
      dataEpoch: epoch,
      serverChangeToken: validToken,
      outbox: [PersistedOutboxMutation(change: createChangeFor(revealId1))],
    );
    final envelope =
        SyncPersistenceEnvelope.empty().withAccount(fingerprintA, state);
    await Directory(dirPath()).create(recursive: true);
    final backupPath = backupPathFor('existing-backup');
    final originalBackupBytes = envelope.encodeString();
    await File(backupPath).writeAsString(originalBackupBytes);
    expect(File(finalPath()).existsSync(), isFalse);

    // Corrupt only the authoritative final's on-disk content, immediately
    // after it is protected but before this store re-reads and decodes it
    // -- a pure read-back/decode failure, distinct from test 38c's raw
    // protection-call exception. Never fails during backup load/decode or
    // the recovery-temp stages.
    final baseline = bridge.callCountFor(finalPath());
    bridge.onProtect = (path) async {
      if (path == finalPath() && bridge.callCountFor(path) == baseline + 1) {
        await File(path).writeAsString('{"corrupted": true}');
      }
    };

    Object? caught;
    try {
      await store.loadAccountState(fingerprintA);
    } catch (error) {
      caught = error;
    }

    expect(caught, isA<SyncPersistenceStoreException>());
    final typed = caught as SyncPersistenceStoreException;
    // Proves the failure came from *verification* (read-back/decode),
    // never from the protection call itself (test 38c's distinct stage).
    expect(typed.stage, 'load-recover-verify-final');
    expect(typed.toString(), isNot(contains(validToken)));
    expect(typed.toString(), isNot(contains(finalPath())));
    expect(typed.toString(), isNot(contains(backupPath)));
    expect(typed.toString(), isNot(contains(fingerprintA)));
    // The cause (a decode FormatException here) is retained internally but
    // never rendered.
    expect(typed.cause, isNotNull);
    expect(typed.toString(), isNot(contains(typed.cause.toString())));

    // The corrupt final is never trusted and is removed rather than left
    // behind; the original backup was never touched by the corruption.
    expect(File(finalPath()).existsSync(), isFalse);
    expect(File(backupPath).existsSync(), isTrue);
    final backupBytesAfterFailure = await File(backupPath).readAsString();
    expect(backupBytesAfterFailure, originalBackupBytes);

    // Disable the injected corruption and confirm the next load recovers
    // successfully from the preserved backup -- token, epoch, and outbox
    // unchanged -- and only then is the backup finally removed.
    bridge.onProtect = null;
    final loaded = await store.loadAccountState(fingerprintA);
    expect(loaded!.dataEpoch, epoch);
    expect(loaded.serverChangeToken, validToken);
    expect(loaded.outbox, hasLength(1));
    expect(File(backupPath).existsSync(), isFalse);
  });

  test(
      '38g. a backup-recovery final envelope mismatch (valid JSON, wrong '
      'content) fails closed under final verification, never protection',
      () async {
    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge);

    final state = AccountSyncState(
      dataEpoch: epoch,
      serverChangeToken: validToken,
      outbox: [PersistedOutboxMutation(change: createChangeFor(revealId1))],
    );
    final envelope =
        SyncPersistenceEnvelope.empty().withAccount(fingerprintA, state);
    await Directory(dirPath()).create(recursive: true);
    final backupPath = backupPathFor('existing-backup');
    final originalBackupBytes = envelope.encodeString();
    await File(backupPath).writeAsString(originalBackupBytes);
    expect(File(finalPath()).existsSync(), isFalse);

    // A different, but perfectly well-formed and independently decodable,
    // envelope -- a wholly different account fingerprint's state -- is
    // substituted for the restored final immediately after it is
    // protected. Decoding succeeds; only the equality comparison against
    // the selected backup's own envelope fails.
    final mismatchedState = AccountSyncState(
      dataEpoch: otherEpoch,
      serverChangeToken: 'differentOpaqueToken',
    );
    final mismatchedEnvelope = SyncPersistenceEnvelope.empty()
        .withAccount(fingerprintB, mismatchedState);
    final baseline = bridge.callCountFor(finalPath());
    bridge.onProtect = (path) async {
      if (path == finalPath() && bridge.callCountFor(path) == baseline + 1) {
        await File(path).writeAsString(mismatchedEnvelope.encodeString());
      }
    };

    Object? caught;
    try {
      await store.loadAccountState(fingerprintA);
    } catch (error) {
      caught = error;
    }

    expect(caught, isA<SyncPersistenceStoreException>());
    final typed = caught as SyncPersistenceStoreException;
    expect(typed.stage, 'load-recover-verify-final');
    expect(typed.toString(), isNot(contains(validToken)));
    expect(typed.toString(), isNot(contains('differentOpaqueToken')));
    expect(typed.toString(), isNot(contains(finalPath())));
    expect(typed.toString(), isNot(contains(backupPath)));
    expect(typed.toString(), isNot(contains(fingerprintA)));
    expect(typed.toString(), isNot(contains(fingerprintB)));

    // The mismatched final is never trusted and is removed; the original
    // backup was never touched.
    expect(File(finalPath()).existsSync(), isFalse);
    expect(File(backupPath).existsSync(), isTrue);
    final backupBytesAfterFailure = await File(backupPath).readAsString();
    expect(backupBytesAfterFailure, originalBackupBytes);

    // Disable the injected substitution and confirm the next load
    // recovers successfully from the preserved backup.
    bridge.onProtect = null;
    final loaded = await store.loadAccountState(fingerprintA);
    expect(loaded!.dataEpoch, epoch);
    expect(loaded.serverChangeToken, validToken);
    expect(loaded.outbox, hasLength(1));
    expect(File(backupPath).existsSync(), isFalse);
  });

  test(
      '38h. a redundant-backup deletion failure after a fully verified '
      'recovery does not invalidate the final or leak a raw exception',
      () async {
    if (Platform.isWindows) {
      // POSIX directory-permission semantics (used below to simulate an
      // undeletable file) do not apply on Windows; this store's own
      // best-effort deletion behavior is platform-independent, only this
      // particular failure-injection technique is not.
      return;
    }

    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge);

    final state = AccountSyncState(
      dataEpoch: epoch,
      serverChangeToken: validToken,
      outbox: [PersistedOutboxMutation(change: createChangeFor(revealId1))],
    );
    final envelope =
        SyncPersistenceEnvelope.empty().withAccount(fingerprintA, state);
    await Directory(dirPath()).create(recursive: true);
    final backupPath = backupPathFor('existing-backup');
    final originalBackupBytes = envelope.encodeString();
    await File(backupPath).writeAsString(originalBackupBytes);
    expect(File(finalPath()).existsSync(), isFalse);

    // Remove write permission on the sync-state directory itself exactly
    // when the restored final is protected -- by that point every earlier
    // recovery-temp write/protect/verify/rename stage has already
    // completed, so only the later best-effort deletions (the now-
    // redundant backup, and _cleanupStaleTransactionFilesBestEffort's own
    // sweep) are affected. Listing and reading remain unaffected (POSIX
    // read+execute bits on the directory are untouched).
    bridge.onProtect = (path) async {
      if (path == finalPath()) {
        await Process.run('chmod', ['555', dirPath()]);
      }
    };

    try {
      AccountSyncState? loaded;
      try {
        loaded = await store.loadAccountState(fingerprintA);
      } catch (error) {
        fail(
          'loadAccountState must not throw merely because a redundant '
          'backup could not be deleted after a fully verified recovery: '
          '$error',
        );
      }

      // The public load still returns the exact recovered state.
      expect(loaded, isNotNull);
      expect(loaded!.dataEpoch, epoch);
      expect(loaded.serverChangeToken, validToken);
      expect(loaded.outbox, hasLength(1));

      // The verified final remains authoritative and untouched.
      expect(File(finalPath()).existsSync(), isTrue);
      final rawFinal = await File(finalPath()).readAsString();
      expect(SyncPersistenceEnvelope.decodeString(rawFinal), envelope);

      // The valid backup survives -- a harmless redundant artifact --
      // rather than the already-completed recovery being invalidated
      // because best-effort cleanup failed.
      expect(File(backupPath).existsSync(), isTrue);
      final backupBytesAfterFailedDeletion =
          await File(backupPath).readAsString();
      expect(backupBytesAfterFailedDeletion, originalBackupBytes);
    } finally {
      bridge.onProtect = null;
      await Process.run('chmod', ['755', dirPath()]);
    }

    // A later load remains deterministic and loses nothing, now that
    // permissions are restored (it goes through the ordinary already-
    // final load path, not recovery, since a valid final already exists).
    final loadedAgain = await store.loadAccountState(fingerprintA);
    expect(loadedAgain!.dataEpoch, epoch);
    expect(loadedAgain.serverChangeToken, validToken);
    expect(loadedAgain.outbox, hasLength(1));
  });

  test(
      '38d. a backup-listing failure while recovering is typed, never a '
      'raw filesystem exception (adjacent boundary found during the '
      'recovery-method audit)', () async {
    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge);

    // Force the sync-state directory to disappear the instant it is
    // protected -- by the time _recoverFromBackupIfFinalAbsent tries to
    // list candidate backups, the directory no longer exists: exactly the
    // "became unreadable between resolve and list" scenario this fix
    // guards against. Nothing has been read, moved, or written yet, so
    // there is nothing to roll back.
    bridge.onProtect = (path) async {
      if (path == dirPath()) {
        final dir = Directory(dirPath());
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    };

    Object? caught;
    try {
      await store.loadAccountState(fingerprintA);
    } catch (error) {
      caught = error;
    }
    bridge.onProtect = null;

    expect(caught, isA<SyncPersistenceStoreException>());
    final typed = caught as SyncPersistenceStoreException;
    expect(typed.stage, 'load-recover-list');

    // The underlying filesystem exception is retained internally, for
    // programmatic inspection (and this very assertion) only -- it must
    // never be rendered.
    expect(typed.cause, isNotNull);
    expect(typed.cause, isA<FileSystemException>());

    // The rendered string is the safe `[stage]: message` shape only --
    // it must never include the cause's own text (which, for a real
    // PathNotFoundException, would itself contain the absolute sync-state
    // directory path) nor the path directly.
    final rendered = typed.toString();
    expect(
        rendered,
        'SyncPersistenceStoreException[load-recover-list]: '
        'Could not list candidate backup files while recovering the '
        'authoritative sync-state file.');
    expect(rendered, isNot(contains(dirPath())));
    expect(rendered, isNot(contains(fingerprintA)));
    expect(rendered, isNot(contains(typed.cause.toString())));
  });

  test(
      '39. a first-write failure (no prior final) leaves no authoritative '
      'file behind', () async {
    final bridge = _FakeFileProtectionBridge();
    var counter = 0;
    final freshStore = ProtectedSyncPersistenceStore(
      rootDirectoryProvider: () async => tempRoot,
      fileProtectionBridge: bridge,
      tokenFactory: () => 'first-token-${counter++}',
      clock: () => DateTime.utc(2026, 8, 1, 12, 0),
    );
    bridge.failNextTimeFor(
      '${dirPath()}/.east_sync_state_v1.tmp-first-token-0.json',
    );

    await expectLater(
      freshStore.enqueueMutation(fingerprintA, createChangeFor(revealId1)),
      throwsA(isA<SyncPersistenceStoreException>()),
    );

    expect(File(finalPath()).existsSync(), isFalse);
    expect(await freshStore.loadAccountState(fingerprintA), isNull);
  });

  // -------------------------------------------------------------------
  // Group I: path isolation
  // -------------------------------------------------------------------

  test(
      '40. every file this store writes stays inside its own dedicated '
      'east_sync_state directory, never east_kept_state', () async {
    final store = buildStore();
    await store.enqueueMutation(fingerprintA, createChangeFor(revealId1));
    await store.storeServerChangeToken(fingerprintA, validToken);
    await store.replaceRecordSystemFields(
      fingerprintA,
      'east-kept-$revealId1',
      validSystemFields,
    );

    final allFiles = await tempRoot
        .list(recursive: true)
        .where((entity) => entity is File)
        .cast<File>()
        .toList();

    expect(allFiles, isNotEmpty);
    for (final file in allFiles) {
      expect(file.path, contains('/east_sync_state'));
      expect(file.path, isNot(contains('east_kept_state')));
    }
  });

  // ---------------------------------------------------------------------
  // Build 26 Phase 4E-4: associatedAccountFingerprint CAS surface and
  // loadMeaningfulAccountFingerprints.
  // ---------------------------------------------------------------------

  group('loadAssociatedAccountFingerprint / commitAssociatedAccountFingerprint',
      () {
    test('absent marker loads as null', () async {
      final store = buildStore();
      expect(await store.loadAssociatedAccountFingerprint(), isNull);
    });

    test('CAS with expectedCurrent: null writes a fresh marker', () async {
      final store = buildStore();
      final result = await store.commitAssociatedAccountFingerprint(
        fingerprint: fingerprintA,
        expectedCurrent: null,
      );
      expect(result.status, AssociatedAccountFingerprintCommitStatus.committed);
      expect(await store.loadAssociatedAccountFingerprint(), fingerprintA);
    });

    test(
        'CAS with expectedCurrent exactly matching the existing marker is '
        'an idempotent no-op reported as alreadyCommitted', () async {
      final store = buildStore();
      await store.commitAssociatedAccountFingerprint(
        fingerprint: fingerprintA,
        expectedCurrent: null,
      );
      final result = await store.commitAssociatedAccountFingerprint(
        fingerprint: fingerprintA,
        expectedCurrent: fingerprintA,
      );
      expect(
        result.status,
        AssociatedAccountFingerprintCommitStatus.alreadyCommitted,
      );
      expect(await store.loadAssociatedAccountFingerprint(), fingerprintA);
    });

    test('CAS with the wrong expectedCurrent never writes', () async {
      final store = buildStore();
      final result = await store.commitAssociatedAccountFingerprint(
        fingerprint: fingerprintA,
        expectedCurrent: fingerprintB,
      );
      expect(
        result.status,
        AssociatedAccountFingerprintCommitStatus.expectedCurrentMismatch,
      );
      expect(await store.loadAssociatedAccountFingerprint(), isNull);
    });

    test(
        'a different, already-durable marker can never be accidentally '
        'overwritten by a null-expecting caller', () async {
      final store = buildStore();
      await store.commitAssociatedAccountFingerprint(
        fingerprint: fingerprintA,
        expectedCurrent: null,
      );
      final result = await store.commitAssociatedAccountFingerprint(
        fingerprint: fingerprintB,
        expectedCurrent: null,
      );
      expect(
        result.status,
        AssociatedAccountFingerprintCommitStatus.expectedCurrentMismatch,
      );
      expect(await store.loadAssociatedAccountFingerprint(), fingerprintA);
    });

    test(
        'an invalid (non-fingerprint-shaped) value is rejected before any '
        'write', () async {
      final store = buildStore();
      // The shape check happens synchronously, before the coordinator-
      // serialized write ever begins -- a closure lets `throwsA` catch a
      // synchronous throw, unlike passing the call's (never-produced)
      // Future value directly.
      expect(
        () => store.commitAssociatedAccountFingerprint(
          fingerprint: 'not-a-valid-fingerprint',
          expectedCurrent: null,
        ),
        throwsA(isA<SyncPersistenceStoreException>()),
      );
      expect(await store.loadAssociatedAccountFingerprint(), isNull);
    });

    test('a failed protection write preserves the previous marker value',
        () async {
      final bridge = _FakeFileProtectionBridge();
      final store = buildStore(bridge: bridge);
      await store.commitAssociatedAccountFingerprint(
        fingerprint: fingerprintA,
        expectedCurrent: null,
      );

      // This second `commitAssociatedAccountFingerprint` call still calls
      // `protectAndVerifyComplete(finalPath())` twice even on its ordinary
      // CAS-then-write path: once inside `_loadEnvelope`'s own pre-write
      // re-verify (reading the current marker to compare against
      // `expectedCurrent`), and again inside `_replaceEnvelope`'s
      // post-rename verify of the newly written final file -- see
      // `_FakeFileProtectionBridge.callCountFor`'s doc comment.
      // `failNextTimeFor` alone would catch the *first* (load-time) call,
      // never reaching the write this test means to exercise -- so, per
      // that documented convention, a baseline is captured immediately
      // before this call and the injected failure targets specifically the
      // second (write-time, post-rename) call.
      final baseline = bridge.callCountFor(finalPath());
      bridge.onProtect = (path) async {
        if (path == finalPath() && bridge.callCountFor(path) == baseline + 2) {
          throw const FileProtectionException('Simulated protection failure.');
        }
      };

      Object? caught;
      try {
        await store.commitAssociatedAccountFingerprint(
          fingerprint: fingerprintB,
          expectedCurrent: fingerprintA,
        );
      } catch (error) {
        caught = error;
      }
      bridge.onProtect = null;

      // A raw FileProtectionException must never escape a public
      // ProtectedSyncPersistenceStore operation -- matching every other
      // protection failure in this suite (e.g. 38b's load-time analogue).
      // A write-time final-protect failure specifically triggers
      // `_rollbackAfterRename`, which restores the pre-write backup and, on
      // a successful rollback, reports `replace-post-rename` while
      // retaining the original `FileProtectionException` as `cause` --
      // never surfacing it raw.
      expect(caught, isA<SyncPersistenceStoreException>());
      final typed = caught as SyncPersistenceStoreException;
      expect(typed.stage, 'replace-post-rename');
      expect(typed.cause, isA<FileProtectionException>());

      expect(await store.loadAssociatedAccountFingerprint(), fingerprintA);
      // The failed write must never leave behind an AccountSyncState
      // bucket for either fingerprint, and must never touch unrelated
      // state.
      expect(await store.loadAccountState(fingerprintA), isNull);
      expect(await store.loadAccountState(fingerprintB), isNull);
    });

    test(
        'committing the marker never creates an AccountSyncState bucket for '
        'that fingerprint and never touches an unrelated account\'s state',
        () async {
      final store = buildStore();
      await store.replaceAccountState(
        fingerprintB,
        AccountSyncState(dataEpoch: epoch, serverChangeToken: 'QQQQ'),
      );
      await store.commitAssociatedAccountFingerprint(
        fingerprint: fingerprintA,
        expectedCurrent: null,
      );
      expect(await store.loadAccountState(fingerprintA), isNull);
      final unrelated = await store.loadAccountState(fingerprintB);
      expect(unrelated!.serverChangeToken, 'QQQQ');
      expect(unrelated.dataEpoch, epoch);
    });

    test('toString()/toLogSafeSummary() never render the fingerprint value',
        () async {
      final store = buildStore();
      final result = await store.commitAssociatedAccountFingerprint(
        fingerprint: fingerprintA,
        expectedCurrent: null,
      );
      expect(result.toString().contains(fingerprintA), isFalse);
      expect(
          result.toLogSafeSummary().toString().contains(fingerprintA), isFalse);
    });
  });

  group('loadMeaningfulAccountFingerprints', () {
    test('returns an empty list when no accounts exist', () async {
      final store = buildStore();
      expect(await store.loadMeaningfulAccountFingerprints(), isEmpty);
    });

    test('excludes a bucket whose bootstrapState is notStarted', () async {
      final store = buildStore();
      await store.replaceAccountState(
        fingerprintA,
        AccountSyncState(dataEpoch: epoch),
      );
      expect(await store.loadMeaningfulAccountFingerprints(), isEmpty);
    });

    test('includes a bucket whose bootstrapState is not notStarted', () async {
      final store = buildStore();
      await store.replaceAccountState(
        fingerprintA,
        AccountSyncState(
          dataEpoch: epoch,
          bootstrapState: AccountBootstrapState.remoteBaselinePending,
        ),
      );
      expect(
        await store.loadMeaningfulAccountFingerprints(),
        [fingerprintA],
      );
    });

    test(
        'never includes a quarantined account, even one that was '
        'meaningful before being quarantined', () async {
      final store = buildStore();
      await store.replaceAccountState(
        fingerprintA,
        AccountSyncState(
          dataEpoch: epoch,
          bootstrapState: AccountBootstrapState.complete,
        ),
      );
      await store.quarantineAccountState(fingerprintA);
      expect(await store.loadMeaningfulAccountFingerprints(), isEmpty);
    });
  });
}

String _mutationIdFor(String revealId) {
  // Deterministic, distinct, canonical-v4-shaped mutationId per revealId --
  // synthetic test fixture only, never a real identity derivation.
  final suffix = revealId.substring(0, 8);
  return '$suffix-0000-4000-8000-000000000000';
}

String _tombstoneMutationIdFor(String revealId) {
  // A second, distinct, canonical-v4-shaped mutationId per revealId, used
  // as the default for a tombstone-form change so it never accidentally
  // collides with `_mutationIdFor`'s active-form default.
  final suffix = revealId.substring(0, 8);
  return '$suffix-0000-4000-8000-000000000001';
}
