// Build 26 Phase 4E-1: SyncPersistenceStore.commitIncomingBatchCheckpoint --
// the one atomic incoming-checkpoint write (record system fields + next
// server token + optional bootstrap-state transition). Synthetic content
// only; no real MethodChannel or CloudKit access anywhere in this file.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/persistence/file_protection_bridge.dart';
import 'package:wisdom_app/sync/cloud_kept_wisdom_projection.dart';
import 'package:wisdom_app/sync/data_epoch.dart';
import 'package:wisdom_app/sync/sync_change.dart';
import 'package:wisdom_app/sync_persistence/account_sync_state.dart';
import 'package:wisdom_app/sync_persistence/incoming_batch_checkpoint.dart';
import 'package:wisdom_app/sync_persistence/protected_sync_persistence_store.dart';
import 'package:wisdom_app/sync_persistence/sync_persistence_store.dart';

/// Fake [FileProtectionBridge], identical in shape/intent to the one in
/// `protected_sync_persistence_store_test.dart`. No real MethodChannel.
class _FakeFileProtectionBridge implements FileProtectionBridge {
  final Map<String, int> _remainingFailures = {};

  void failNextTimeFor(String path, {int times = 1}) {
    _remainingFailures[path] = (_remainingFailures[path] ?? 0) + times;
  }

  @override
  Future<void> protectAndVerifyComplete(String path) async {
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
    tempRoot = Directory.systemTemp.createTempSync('incoming_checkpoint_test_');
  });

  tearDown(() {
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  String dirPath() => '${tempRoot.path}/east_sync_state';

  ProtectedSyncPersistenceStore buildStore({
    FileProtectionBridge? bridge,
    String Function()? tokenFactory,
  }) {
    var counter = 0;
    return ProtectedSyncPersistenceStore(
      rootDirectoryProvider: () async => tempRoot,
      fileProtectionBridge: bridge ?? _FakeFileProtectionBridge(),
      tokenFactory: tokenFactory ?? (() => 'token-${counter++}'),
      clock: () => DateTime.utc(2026, 8, 1, 12, 0),
    );
  }

  const fingerprintA =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const fingerprintB =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  final epoch = DataEpoch.parse('12121212-1212-4212-8212-121212121212');
  final otherEpoch = DataEpoch.parse('34343434-3434-4434-8434-343434343434');

  const recordNameOne = 'east-kept-11111111-1111-4111-8111-111111111111';
  const recordNameTwo = 'east-kept-22222222-2222-4222-8222-222222222222';
  const tokenOne = 'dG9rZW4tb25l'; // 'token-one'
  const tokenTwo = 'dG9rZW4tdHdv'; // 'token-two'
  const tokenThree = 'dG9rZW4tdGhyZWU='; // 'token-three'
  const fieldsOne = 'ZmllbGRzLW9uZQ=='; // 'fields-one'
  const fieldsTwo = 'ZmllbGRzLXR3bw=='; // 'fields-two'

  SyncChange createChangeFor(String revealId) {
    return SyncChange(
      kind: SyncChangeKind.create,
      projection: CloudKeptWisdomProjection.tryParseRemote({
        'recordName': 'east-kept-$revealId',
        'isTombstone': false,
        'revealId': revealId,
        'wisdomText': 'Synthetic wisdom text for testing only.',
        'revealedAtMs': 1000,
        'keptAtMs': 2000,
        'updatedAtMs': 3000,
        'mutationId': '99999999-9999-4999-8999-999999999999',
        'dataEpoch': epoch.value,
        'schemaVersion': 3,
      })!,
      enqueuedAt: DateTime.utc(2026, 8, 1, 10),
    );
  }

  /// Seeds an existing bucket for [fingerprint] directly via
  /// `replaceAccountState`, bypassing the checkpoint API under test.
  Future<void> seedBucket(
    ProtectedSyncPersistenceStore store,
    String fingerprint,
    AccountSyncState state,
  ) {
    return store.replaceAccountState(fingerprint, state);
  }

  group('1. system fields + token commit in one write', () {
    test('existingBucket mode durably commits both in exactly one replace',
        () async {
      final store = buildStore();
      await seedBucket(
        store,
        fingerprintA,
        AccountSyncState(dataEpoch: epoch, serverChangeToken: tokenOne),
      );

      final result = await store.commitIncomingBatchCheckpoint(
        CommitIncomingBatchCheckpointRequest(
          accountFingerprint: fingerprintA,
          mode: IncomingCheckpointMode.existingBucket,
          expectedCurrentDataEpoch: epoch,
          expectedPreviousServerToken: tokenOne,
          pendingServerChangeToken: tokenTwo,
          recordSystemFieldsUpdates: const [
            IncomingRecordSystemFieldsUpdate(
              recordName: recordNameOne,
              systemFields: fieldsOne,
            ),
          ],
        ),
      );

      expect(result.isCommitted, isTrue);
      expect(result.tokenChanged, isTrue);
      expect(result.systemFieldCount, 1);

      final loaded = await store.loadAccountState(fingerprintA);
      expect(loaded!.serverChangeToken, tokenTwo);
      expect(loaded.recordSystemFields[recordNameOne], fieldsOne);
    });

    test('commits in exactly one temp-file write (one atomic replace)',
        () async {
      var tokenCalls = 0;
      final store = buildStore(
        tokenFactory: () {
          tokenCalls += 1;
          return 'tok-$tokenCalls';
        },
      );
      await seedBucket(
        store,
        fingerprintA,
        AccountSyncState(dataEpoch: epoch, serverChangeToken: tokenOne),
      );
      final tokenCallsAfterSeed = tokenCalls;

      await store.commitIncomingBatchCheckpoint(
        CommitIncomingBatchCheckpointRequest(
          accountFingerprint: fingerprintA,
          mode: IncomingCheckpointMode.existingBucket,
          expectedCurrentDataEpoch: epoch,
          expectedPreviousServerToken: tokenOne,
          pendingServerChangeToken: tokenTwo,
          recordSystemFieldsUpdates: const [
            IncomingRecordSystemFieldsUpdate(
              recordName: recordNameOne,
              systemFields: fieldsOne,
            ),
          ],
        ),
      );

      // Exactly one `_replaceEnvelope` call consumes exactly one temp
      // token (plus, if a final already existed, one backup token from the
      // *same* replace cycle -- `_replaceEnvelope` calls the token factory
      // once for the temp path and reuses that same token for the backup
      // path). One replace call therefore advances the counter by exactly
      // 1, never 2 (which a "two separate envelope writes" implementation
      // -- e.g. calling `replaceRecordSystemFields` then
      // `storeServerChangeToken` -- would produce).
      expect(tokenCalls - tokenCallsAfterSeed, 1);
    });
  });

  test('2. token mismatch fails with zero mutation', () async {
    final store = buildStore();
    await seedBucket(
      store,
      fingerprintA,
      AccountSyncState(dataEpoch: epoch, serverChangeToken: tokenOne),
    );

    final result = await store.commitIncomingBatchCheckpoint(
      CommitIncomingBatchCheckpointRequest(
        accountFingerprint: fingerprintA,
        mode: IncomingCheckpointMode.existingBucket,
        expectedCurrentDataEpoch: epoch,
        expectedPreviousServerToken: tokenTwo, // wrong -- current is tokenOne
        pendingServerChangeToken: tokenThree,
      ),
    );

    expect(result.status, IncomingCheckpointStatus.previousTokenMismatch);
    expect(result.isCommitted, isFalse);

    final loaded = await store.loadAccountState(fingerprintA);
    expect(loaded!.serverChangeToken, tokenOne);
    expect(loaded.recordSystemFields, isEmpty);
  });

  test('3. epoch mismatch fails with zero mutation', () async {
    final store = buildStore();
    await seedBucket(
      store,
      fingerprintA,
      AccountSyncState(dataEpoch: epoch, serverChangeToken: tokenOne),
    );

    final result = await store.commitIncomingBatchCheckpoint(
      CommitIncomingBatchCheckpointRequest(
        accountFingerprint: fingerprintA,
        mode: IncomingCheckpointMode.existingBucket,
        expectedCurrentDataEpoch: otherEpoch, // wrong -- current is epoch
        expectedPreviousServerToken: tokenOne,
        pendingServerChangeToken: tokenTwo,
      ),
    );

    expect(result.status, IncomingCheckpointStatus.dataEpochMismatch);
    final loaded = await store.loadAccountState(fingerprintA);
    expect(loaded!.dataEpoch, epoch);
    expect(loaded.serverChangeToken, tokenOne);
  });

  test('4. missing bucket fails outside bootstrap mode', () async {
    final store = buildStore();

    final result = await store.commitIncomingBatchCheckpoint(
      CommitIncomingBatchCheckpointRequest(
        accountFingerprint: fingerprintA,
        mode: IncomingCheckpointMode.existingBucket,
        expectedCurrentDataEpoch: epoch,
        expectedPreviousServerToken: null,
        pendingServerChangeToken: tokenOne,
      ),
    );

    expect(result.status, IncomingCheckpointStatus.bucketMissing);
    expect(await store.loadAccountState(fingerprintA), isNull);
  });

  test('5. bootstrap creation uses exactly the supplied epoch', () async {
    final store = buildStore();

    final result = await store.commitIncomingBatchCheckpoint(
      CommitIncomingBatchCheckpointRequest(
        accountFingerprint: fingerprintA,
        mode: IncomingCheckpointMode.bootstrapCreate,
        pendingServerChangeToken: tokenOne,
        bootstrapTargetDataEpoch: epoch,
        recordSystemFieldsUpdates: const [
          IncomingRecordSystemFieldsUpdate(
            recordName: recordNameOne,
            systemFields: fieldsOne,
          ),
        ],
      ),
    );

    expect(result.isCommitted, isTrue);
    final loaded = await store.loadAccountState(fingerprintA);
    expect(loaded, isNotNull);
    // Exactly the supplied epoch -- never a fabricated/default one.
    expect(loaded!.dataEpoch, epoch);
    expect(loaded.dataEpoch, isNot(otherEpoch));
    expect(loaded.serverChangeToken, tokenOne);
    expect(loaded.recordSystemFields[recordNameOne], fieldsOne);
  });

  test('6. bootstrap creation rejects an already-existing bucket', () async {
    final store = buildStore();
    await seedBucket(
      store,
      fingerprintA,
      AccountSyncState(dataEpoch: epoch, serverChangeToken: tokenOne),
    );

    final result = await store.commitIncomingBatchCheckpoint(
      CommitIncomingBatchCheckpointRequest(
        accountFingerprint: fingerprintA,
        mode: IncomingCheckpointMode.bootstrapCreate,
        pendingServerChangeToken: tokenTwo,
        bootstrapTargetDataEpoch: otherEpoch,
      ),
    );

    expect(result.status, IncomingCheckpointStatus.bucketAlreadyExists);
    // The unexpectedly-existing bucket is never overwritten.
    final loaded = await store.loadAccountState(fingerprintA);
    expect(loaded!.dataEpoch, epoch);
    expect(loaded.serverChangeToken, tokenOne);
  });

  test('7. duplicate record names inside one request fail closed', () async {
    final store = buildStore();
    await seedBucket(
      store,
      fingerprintA,
      AccountSyncState(dataEpoch: epoch, serverChangeToken: tokenOne),
    );

    final result = await store.commitIncomingBatchCheckpoint(
      CommitIncomingBatchCheckpointRequest(
        accountFingerprint: fingerprintA,
        mode: IncomingCheckpointMode.existingBucket,
        expectedCurrentDataEpoch: epoch,
        expectedPreviousServerToken: tokenOne,
        pendingServerChangeToken: tokenTwo,
        recordSystemFieldsUpdates: const [
          IncomingRecordSystemFieldsUpdate(
            recordName: recordNameOne,
            systemFields: fieldsOne,
          ),
          IncomingRecordSystemFieldsUpdate(
            recordName: recordNameOne,
            systemFields: fieldsTwo,
          ),
        ],
      ),
    );

    expect(result.status, IncomingCheckpointStatus.duplicateRecordName);
    final loaded = await store.loadAccountState(fingerprintA);
    expect(loaded!.serverChangeToken, tokenOne);
    expect(loaded.recordSystemFields, isEmpty);
  });

  test('8. invalid record system fields fail closed', () async {
    final store = buildStore();
    await seedBucket(
      store,
      fingerprintA,
      AccountSyncState(dataEpoch: epoch, serverChangeToken: tokenOne),
    );

    final result = await store.commitIncomingBatchCheckpoint(
      CommitIncomingBatchCheckpointRequest(
        accountFingerprint: fingerprintA,
        mode: IncomingCheckpointMode.existingBucket,
        expectedCurrentDataEpoch: epoch,
        expectedPreviousServerToken: tokenOne,
        pendingServerChangeToken: tokenTwo,
        recordSystemFieldsUpdates: const [
          IncomingRecordSystemFieldsUpdate(
            recordName: 'not-a-real-record-name',
            systemFields: fieldsOne,
          ),
        ],
      ),
    );

    expect(result.status, IncomingCheckpointStatus.invalidRecordSystemFields);
    final loaded = await store.loadAccountState(fingerprintA);
    expect(loaded!.serverChangeToken, tokenOne);
    expect(loaded.recordSystemFields, isEmpty);
  });

  test('9. bootstrap-state transition mismatch fails closed', () async {
    final store = buildStore();
    await seedBucket(
      store,
      fingerprintA,
      AccountSyncState(
        dataEpoch: epoch,
        serverChangeToken: tokenOne,
        bootstrapState: AccountBootstrapState.notStarted,
      ),
    );

    // expectedBootstrapState says remoteBaselinePending, but the bucket is
    // actually notStarted -- must fail closed, not silently proceed.
    final result = await store.commitIncomingBatchCheckpoint(
      CommitIncomingBatchCheckpointRequest(
        accountFingerprint: fingerprintA,
        mode: IncomingCheckpointMode.existingBucket,
        expectedCurrentDataEpoch: epoch,
        expectedPreviousServerToken: tokenOne,
        pendingServerChangeToken: tokenTwo,
        expectedBootstrapState: AccountBootstrapState.remoteBaselinePending,
        nextBootstrapState: AccountBootstrapState.localReconciliationPending,
      ),
    );

    expect(result.status, IncomingCheckpointStatus.bootstrapStateMismatch);
    final loaded = await store.loadAccountState(fingerprintA);
    expect(loaded!.bootstrapState, AccountBootstrapState.notStarted);
    expect(loaded.serverChangeToken, tokenOne);
  });

  test(
      '9b. an invalid bootstrap-state transition (skipping a step) fails '
      'closed even when expectedBootstrapState correctly matches', () async {
    final store = buildStore();
    await seedBucket(
      store,
      fingerprintA,
      AccountSyncState(
        dataEpoch: epoch,
        serverChangeToken: tokenOne,
        bootstrapState: AccountBootstrapState.notStarted,
      ),
    );

    final result = await store.commitIncomingBatchCheckpoint(
      CommitIncomingBatchCheckpointRequest(
        accountFingerprint: fingerprintA,
        mode: IncomingCheckpointMode.existingBucket,
        expectedCurrentDataEpoch: epoch,
        expectedPreviousServerToken: tokenOne,
        pendingServerChangeToken: tokenTwo,
        expectedBootstrapState: AccountBootstrapState.notStarted,
        // Skips remoteBaselinePending/localReconciliationPending.
        nextBootstrapState: AccountBootstrapState.complete,
      ),
    );

    expect(result.status, IncomingCheckpointStatus.invalidBootstrapTransition);
    final loaded = await store.loadAccountState(fingerprintA);
    expect(loaded!.bootstrapState, AccountBootstrapState.notStarted);
    expect(loaded.serverChangeToken, tokenOne);
  });

  test('10. account A checkpoint never touches account B', () async {
    final store = buildStore();
    await seedBucket(
      store,
      fingerprintA,
      AccountSyncState(dataEpoch: epoch, serverChangeToken: tokenOne),
    );
    await seedBucket(
      store,
      fingerprintB,
      AccountSyncState(dataEpoch: otherEpoch, serverChangeToken: tokenTwo),
    );

    await store.commitIncomingBatchCheckpoint(
      CommitIncomingBatchCheckpointRequest(
        accountFingerprint: fingerprintA,
        mode: IncomingCheckpointMode.existingBucket,
        expectedCurrentDataEpoch: epoch,
        expectedPreviousServerToken: tokenOne,
        pendingServerChangeToken: tokenThree,
        recordSystemFieldsUpdates: const [
          IncomingRecordSystemFieldsUpdate(
            recordName: recordNameOne,
            systemFields: fieldsOne,
          ),
        ],
      ),
    );

    final loadedB = await store.loadAccountState(fingerprintB);
    expect(loadedB!.dataEpoch, otherEpoch);
    expect(loadedB.serverChangeToken, tokenTwo);
    expect(loadedB.recordSystemFields, isEmpty);
  });

  test('11. the outbox remains unchanged by a checkpoint', () async {
    final store = buildStore();
    final change = createChangeFor('55555555-5555-4555-8555-555555555555');
    await store.enqueueMutation(fingerprintA, change);
    // enqueueMutation created the bucket with serverChangeToken == null.

    final result = await store.commitIncomingBatchCheckpoint(
      CommitIncomingBatchCheckpointRequest(
        accountFingerprint: fingerprintA,
        mode: IncomingCheckpointMode.existingBucket,
        expectedCurrentDataEpoch: epoch,
        expectedPreviousServerToken: null,
        pendingServerChangeToken: tokenOne,
      ),
    );

    expect(result.isCommitted, isTrue);
    final loaded = await store.loadAccountState(fingerprintA);
    expect(loaded!.outbox, hasLength(1));
    expect(loaded.outbox.single.change.projection, change.projection);
    expect(loaded.serverChangeToken, tokenOne);
  });

  test(
      '12. unrelated existing record-system-fields entries are unchanged '
      'by a checkpoint touching a different record', () async {
    final store = buildStore();
    await seedBucket(
      store,
      fingerprintA,
      AccountSyncState(
        dataEpoch: epoch,
        serverChangeToken: tokenOne,
        recordSystemFields: const {recordNameOne: fieldsOne},
      ),
    );

    final result = await store.commitIncomingBatchCheckpoint(
      CommitIncomingBatchCheckpointRequest(
        accountFingerprint: fingerprintA,
        mode: IncomingCheckpointMode.existingBucket,
        expectedCurrentDataEpoch: epoch,
        expectedPreviousServerToken: tokenOne,
        pendingServerChangeToken: tokenTwo,
        recordSystemFieldsUpdates: const [
          IncomingRecordSystemFieldsUpdate(
            recordName: recordNameTwo,
            systemFields: fieldsTwo,
          ),
        ],
      ),
    );

    expect(result.isCommitted, isTrue);
    final loaded = await store.loadAccountState(fingerprintA);
    expect(loaded!.recordSystemFields[recordNameOne], fieldsOne);
    expect(loaded.recordSystemFields[recordNameTwo], fieldsTwo);
  });

  test(
      '13. a write failure during the checkpoint changes neither the '
      'token nor the system fields', () async {
    final bridge = _FakeFileProtectionBridge();
    final store = buildStore(bridge: bridge);
    await seedBucket(
      store,
      fingerprintA,
      AccountSyncState(dataEpoch: epoch, serverChangeToken: tokenOne),
    );

    // Fail the temp-file protection step of the checkpoint's own
    // `_replaceEnvelope` call -- this is a genuine I/O failure, so it is
    // expected to throw rather than return a typed result.
    bridge.failNextTimeFor('${dirPath()}/.east_sync_state_v1.tmp-token-1.json');

    await expectLater(
      store.commitIncomingBatchCheckpoint(
        CommitIncomingBatchCheckpointRequest(
          accountFingerprint: fingerprintA,
          mode: IncomingCheckpointMode.existingBucket,
          expectedCurrentDataEpoch: epoch,
          expectedPreviousServerToken: tokenOne,
          pendingServerChangeToken: tokenTwo,
          recordSystemFieldsUpdates: const [
            IncomingRecordSystemFieldsUpdate(
              recordName: recordNameOne,
              systemFields: fieldsOne,
            ),
          ],
        ),
      ),
      throwsA(isA<SyncPersistenceStoreException>()),
    );

    final loaded = await store.loadAccountState(fingerprintA);
    expect(loaded!.serverChangeToken, tokenOne);
    expect(loaded.recordSystemFields, isEmpty);
  });

  test('14. retrying the exact same checkpoint request is idempotent',
      () async {
    final store = buildStore();
    await seedBucket(
      store,
      fingerprintA,
      AccountSyncState(dataEpoch: epoch, serverChangeToken: tokenOne),
    );

    final request = CommitIncomingBatchCheckpointRequest(
      accountFingerprint: fingerprintA,
      mode: IncomingCheckpointMode.existingBucket,
      expectedCurrentDataEpoch: epoch,
      expectedPreviousServerToken: tokenOne,
      pendingServerChangeToken: tokenTwo,
      recordSystemFieldsUpdates: const [
        IncomingRecordSystemFieldsUpdate(
          recordName: recordNameOne,
          systemFields: fieldsOne,
        ),
      ],
    );

    final first = await store.commitIncomingBatchCheckpoint(request);
    expect(first.isCommitted, isTrue);
    expect(first.tokenChanged, isTrue);

    // Retrying the exact same request -- as a caller would after a crash
    // or a dropped response -- must still report success, not
    // previousTokenMismatch, even though the bucket's token has already
    // moved past the request's own `expectedPreviousServerToken`.
    final second = await store.commitIncomingBatchCheckpoint(request);
    expect(second.isCommitted, isTrue);
    expect(second.tokenChanged, isFalse);
    expect(second.bootstrapStateChanged, isFalse);

    final loaded = await store.loadAccountState(fingerprintA);
    expect(loaded!.serverChangeToken, tokenTwo);
    expect(loaded.recordSystemFields[recordNameOne], fieldsOne);
  });

  test(
      '14b. a partial-target mismatch (pending token already equals the '
      'current token, but a requested system-field value differs from '
      "what's currently persisted) is never accepted as an idempotent "
      'no-op -- the mismatching target is actually applied, never '
      'silently ignored', () async {
    final store = buildStore();
    await seedBucket(
      store,
      fingerprintA,
      AccountSyncState(
        dataEpoch: epoch,
        serverChangeToken: tokenOne,
        recordSystemFields: const {
          recordNameOne: fieldsOne,
          recordNameTwo: fieldsTwo,
        },
      ),
    );
    // An unrelated account bucket, and an unrelated outbox entry on the
    // target account, must both remain untouched by this checkpoint.
    await seedBucket(
      store,
      fingerprintB,
      AccountSyncState(dataEpoch: otherEpoch, serverChangeToken: tokenTwo),
    );

    // `pendingServerChangeToken` already equals the currently-persisted
    // token -- exactly the condition that makes the first component of
    // `_alreadyMatchesCheckpointTarget`'s check pass -- but the requested
    // system-fields value for `recordNameOne` (`fieldsTwo`) genuinely
    // differs from what is currently stored for it (`fieldsOne`). This
    // must never be waved through as "nothing to do."
    final result = await store.commitIncomingBatchCheckpoint(
      CommitIncomingBatchCheckpointRequest(
        accountFingerprint: fingerprintA,
        mode: IncomingCheckpointMode.existingBucket,
        expectedCurrentDataEpoch: epoch,
        expectedPreviousServerToken: tokenOne,
        pendingServerChangeToken: tokenOne, // same as current -- not a typo
        recordSystemFieldsUpdates: const [
          IncomingRecordSystemFieldsUpdate(
            recordName: recordNameOne,
            systemFields: fieldsTwo, // differs from the persisted fieldsOne
          ),
        ],
      ),
    );

    // The real contract for this request (epoch/token/bootstrap-state all
    // otherwise valid) is that it commits, actually applying the changed
    // system-field value -- not that it reports a trivial idempotent
    // success while leaving `recordNameOne` still holding `fieldsOne`.
    expect(result.isCommitted, isTrue);
    expect(result.tokenChanged, isFalse);
    expect(result.bootstrapStateChanged, isFalse);
    expect(result.systemFieldCount, 1);

    final loaded = await store.loadAccountState(fingerprintA);
    // The mismatching target was actually applied.
    expect(loaded!.recordSystemFields[recordNameOne], fieldsTwo);
    // An unrelated existing system-fields entry on the same bucket is
    // untouched.
    expect(loaded.recordSystemFields[recordNameTwo], fieldsTwo);
    expect(loaded.serverChangeToken, tokenOne);
    expect(loaded.outbox, isEmpty);

    // The unrelated account bucket is completely untouched.
    final loadedB = await store.loadAccountState(fingerprintB);
    expect(loadedB!.dataEpoch, otherEpoch);
    expect(loadedB.serverChangeToken, tokenTwo);
    expect(loadedB.recordSystemFields, isEmpty);
  });

  test(
      '15. safe rendering exposes only counts/booleans/categories -- never '
      'a fingerprint, epoch, token, or record name value', () {
    const result = CommitIncomingBatchCheckpointResult(
      status: IncomingCheckpointStatus.committed,
      systemFieldCount: 3,
      bootstrapStateChanged: true,
      tokenChanged: true,
    );

    final summary = result.toLogSafeSummary();
    expect(summary, {
      'status': 'committed',
      'systemFieldCount': 3,
      'bootstrapStateChanged': true,
      'tokenChanged': true,
    });

    final rendered = result.toString();
    expect(rendered, contains('committed'));
    expect(rendered, contains('systemFieldCount: 3'));
    expect(rendered, isNot(contains(fingerprintA)));
    expect(rendered, isNot(contains(tokenOne)));
    expect(rendered, isNot(contains(tokenTwo)));
    expect(rendered, isNot(contains(recordNameOne)));
    expect(rendered, isNot(contains(fieldsOne)));
    expect(rendered, isNot(contains(epoch.value)));
  });

  test(
      'a structurally invalid request (missing expectedCurrentDataEpoch in '
      'existingBucket mode) fails closed before touching any bucket', () async {
    final store = buildStore();
    await seedBucket(
      store,
      fingerprintA,
      AccountSyncState(dataEpoch: epoch, serverChangeToken: tokenOne),
    );

    final result = await store.commitIncomingBatchCheckpoint(
      CommitIncomingBatchCheckpointRequest(
        accountFingerprint: fingerprintA,
        mode: IncomingCheckpointMode.existingBucket,
        expectedCurrentDataEpoch: null,
        pendingServerChangeToken: tokenTwo,
      ),
    );

    expect(result.status, IncomingCheckpointStatus.invalidRequest);
    final loaded = await store.loadAccountState(fingerprintA);
    expect(loaded!.serverChangeToken, tokenOne);
  });
}
