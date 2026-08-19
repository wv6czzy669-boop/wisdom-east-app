// CloudKit incoming-merge / Reflection-conflict regression suite.
//
// Primary hypothesis under test: a stale CloudKit record for the SAME
// revealId arriving immediately after a successful LOCAL Reflection save
// could overwrite the newly-saved reflection with an older remote state.
//
// This exercises the REAL production classes for both the local-mutation
// side and the incoming-merge side: `KeptRepository`,
// `KeptSyncIntegrationCoordinator` (the exact chain
// `SavedReflectionsService.saveReflection` -> `ReflectionScreen` drives),
// and `IncomingKeptSyncCoordinator` (the exact production incoming-apply/
// conflict-resolution coordinator) -- all sharing one
// `PersistenceOperationCoordinator` instance and one `KeptRepository`
// instance, exactly mirroring `app_services.dart`'s composition root
// wiring. Only the actual CloudKit/native transport boundary is faked: the
// "incoming batch" is constructed directly (standing in for an
// already-fetched, already-decoded server response), and
// `InMemoryLocalSyncIntentStore`/`InMemorySyncPersistenceStore` (the same
// established test doubles `KeptRepositoryTestGraph` and
// `incoming_kept_sync_coordinator_test.dart` already use) stand in for the
// durable intent/outbox/account-bucket storage.
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/models/kept_bootstrap_result.dart';
import 'package:wisdom_app/models/kept_record.dart';
import 'package:wisdom_app/persistence/persistence_operation_coordinator.dart';
import 'package:wisdom_app/repositories/kept_repository.dart';
import 'package:wisdom_app/sync/cloud_kept_wisdom_projection.dart';
import 'package:wisdom_app/sync/data_epoch.dart';
import 'package:wisdom_app/sync/sync_change.dart';
import 'package:wisdom_app/sync_integration/incoming_kept_sync_coordinator.dart';
import 'package:wisdom_app/sync_integration/kept_sync_integration_coordinator.dart';
import 'package:wisdom_app/sync_orchestration/pending_incoming_sync_batch.dart';
import 'package:wisdom_app/sync_persistence/account_sync_state.dart';
import 'package:wisdom_app/sync_persistence/persisted_outbox_mutation.dart';

import 'persistence_test_helpers.dart' show InMemoryKeptStateStore;
import 'sync_integration/in_memory_sync_test_doubles.dart';

void main() {
  const fingerprint = 'fingerprint-under-test';
  final epoch = DataEpoch.parse('11111111-1111-4111-8111-111111111111');
  const revealIdX = 'aaaaaaaa-1111-4111-8111-111111111111';
  const revealIdY = 'bbbbbbbb-2222-4222-8222-222222222222';
  final t0 = DateTime.utc(2026, 8, 1, 10, 0, 0);

  String systemFieldsFor(String recordName) =>
      'c3lzdGVtRmllbGRzXyR7cmVjb3JkTmFtZX0=';

  /// One shared production-shaped graph: a single `KeptRepository`, a
  /// single `PersistenceOperationCoordinator`, real
  /// `KeptSyncIntegrationCoordinator` (outgoing/local mutations) and real
  /// `IncomingKeptSyncCoordinator` (incoming merge) over it -- exactly
  /// `app_services.dart`'s own wiring shape.
  late InMemoryKeptStateStore keptStore;
  late KeptRepository keptRepository;
  late InMemoryLocalSyncIntentStore intentStore;
  late InMemorySyncPersistenceStore syncStore;
  late PersistenceOperationCoordinator sharedCoordinator;
  late KeptSyncIntegrationCoordinator outgoing;
  late IncomingKeptSyncCoordinator incoming;
  late DateTime clockNow;

  DateTime clock() => clockNow;

  setUp(() {
    clockNow = t0;
    keptStore = InMemoryKeptStateStore();
    keptRepository = KeptRepository(
      store: keptStore,
      bootstrap: const KeptBootstrapResult.ready(),
      operationCoordinator: PersistenceOperationCoordinator(),
    );
    intentStore = InMemoryLocalSyncIntentStore();
    syncStore = InMemorySyncPersistenceStore();
    sharedCoordinator = PersistenceOperationCoordinator();
    outgoing = KeptSyncIntegrationCoordinator(
      keptRepository: keptRepository,
      intentStore: intentStore,
      syncPersistenceStore: syncStore,
      integrationCoordinator: sharedCoordinator,
      clock: clock,
    );
    incoming = IncomingKeptSyncCoordinator(
      keptRepository: keptRepository,
      intentStore: intentStore,
      syncPersistenceStore: syncStore,
      integrationCoordinator: sharedCoordinator,
    );
  });

  void seedBucket({
    List<PersistedOutboxMutation> outbox = const [],
    String? serverChangeToken = 'b2xkdG9rZW4=',
  }) {
    syncStore.seedAccount(
      fingerprint,
      AccountSyncState(
        dataEpoch: epoch,
        serverChangeToken: serverChangeToken,
        outbox: outbox,
        bootstrapState: AccountBootstrapState.complete,
      ),
    );
  }

  PendingIncomingSyncBatch batchWith(
    CloudKeptWisdomProjection projection, {
    String? previousServerChangeToken = 'b2xkdG9rZW4=',
    String pendingServerChangeToken = 'bmV3dG9rZW4=',
  }) {
    return PendingIncomingSyncBatch(
      accountFingerprint: fingerprint,
      baseDataEpoch: epoch,
      previousServerChangeToken: previousServerChangeToken,
      pendingServerChangeToken: pendingServerChangeToken,
      incomingKeptWisdomProjections: [projection],
      incomingSyncStateProjections: const [],
      incomingKeptWisdomRecordSystemFields: {
        projection.recordName: systemFieldsFor(projection.recordName),
      },
    );
  }

  /// Builds a remote projection claiming to be the SAME occurrence as
  /// [local] (identical immutable fields: revealId/wisdomText/revealedAt/
  /// keptAt -- required or the resolver rejects the whole batch as
  /// corruption) but with the given `reflectionText`/`reflectedAt`/
  /// `updatedAt`/`mutationId` -- i.e. a genuinely different version of the
  /// same record, exactly what a real CloudKit fetch returns.
  CloudKeptWisdomProjection remoteVersionOf(
    KeptRecord local, {
    String? reflectionText,
    DateTime? reflectedAt,
    required DateTime updatedAt,
    required String mutationId,
  }) {
    return CloudKeptWisdomProjection.active(
      KeptRecord(
        id: 'remote-conversion-vehicle',
        revealId: local.revealId,
        wisdomText: local.wisdomText,
        revealedAt: local.revealedAt,
        keptAt: local.keptAt,
        reflectionText: reflectionText,
        reflectedAt: reflectedAt,
        updatedAt: updatedAt,
        mutationId: mutationId,
      ),
      dataEpoch: epoch,
    );
  }

  Future<KeptRecord> soleRecord() async {
    final records = await keptRepository.loadAllRecords();
    expect(records, hasLength(1));
    return records.single;
  }

  group(
      'CASE 1 -- primary hypothesis: stale remote after a fresh local '
      'Reflection save', () {
    test(
        'a stale remote record (no reflection, older updatedAt) for the '
        'SAME revealId must NOT erase a just-saved newer local Reflection',
        () async {
      // 1. Real local Keep, through the real production mutation path.
      clockNow = t0;
      await outgoing.recordKeep(
        revealId: revealIdX,
        wisdomText: 'What is gentle with your spirit is not accidental.',
        revealedAt: t0,
        isKeeper: true,
      );
      final kept = await soleRecord();
      expect(kept.reflectionText, isNull);

      // 2. Real local Reflection save, through the exact same coordinator
      // method `SavedReflectionsService.saveReflection` calls.
      clockNow = t0.add(const Duration(minutes: 10));
      await outgoing.recordReflectionSave(
        itemId: kept.id,
        reflection: 'The reflection that must survive.',
        isKeeper: true,
      );

      // 3. Authoritative local repository now has the exact reflection.
      final afterLocalSave = await soleRecord();
      expect(
        afterLocalSave.reflectionText,
        'The reflection that must survive.',
      );
      expect(afterLocalSave.updatedAt, clockNow);

      // 4/5. A STALE remote snapshot for the same revealId -- fetched, in
      // spirit, from before this reflection ever existed: no reflection,
      // and an updatedAt clearly BEFORE the local save above.
      seedBucket();
      final staleRemote = remoteVersionOf(
        afterLocalSave,
        reflectionText: null,
        reflectedAt: null,
        updatedAt: t0, // older than afterLocalSave.updatedAt
        mutationId: '99999999-0000-4000-8000-000000000001',
      );

      // 6. Apply through the REAL incoming/reconciliation path.
      final result = await incoming.applyIncomingBatch(batchWith(staleRemote));
      expect(result.status, IncomingApplyStatus.applied);

      // 7. Reload authoritative repository -- the newer local Reflection
      // MUST still exist exactly.
      final afterIncoming = await soleRecord();
      expect(
        afterIncoming.reflectionText,
        'The reflection that must survive.',
        reason: 'A stale incoming record must never erase a newer local '
            'Reflection.',
      );
      expect(afterIncoming.reflectedAt, afterLocalSave.reflectedAt);
      expect(afterIncoming.id, kept.id);
    });
  });

  group('CASE 2 -- local newer wins over a differing remote', () {
    test('local newer Reflection beats a remote OLDER, DIFFERENT Reflection',
        () async {
      clockNow = t0;
      await outgoing.recordKeep(
        revealId: revealIdX,
        wisdomText: 'Let the next step be honest rather than impressive.',
        revealedAt: t0,
        isKeeper: true,
      );
      final kept = await soleRecord();

      clockNow = t0.add(const Duration(hours: 1));
      await outgoing.recordReflectionSave(
        itemId: kept.id,
        reflection: 'The newer local reflection.',
        isKeeper: true,
      );
      final afterLocalSave = await soleRecord();

      seedBucket();
      final olderDifferentRemote = remoteVersionOf(
        afterLocalSave,
        reflectionText: 'An older, different reflection.',
        reflectedAt: t0,
        updatedAt: t0.add(const Duration(minutes: 30)), // older
        mutationId: '99999999-0000-4000-8000-000000000002',
      );

      final result =
          await incoming.applyIncomingBatch(batchWith(olderDifferentRemote));
      expect(result.status, IncomingApplyStatus.applied);

      final afterIncoming = await soleRecord();
      expect(afterIncoming.reflectionText, 'The newer local reflection.');
    });
  });

  group('CASE 3 -- genuinely newer remote converges correctly', () {
    test('remote newer Reflection legitimately wins over an older local one',
        () async {
      clockNow = t0;
      await outgoing.recordKeep(
        revealId: revealIdX,
        wisdomText: 'What stays gentle under pressure deserves attention.',
        revealedAt: t0,
        isKeeper: true,
      );
      final kept = await soleRecord();

      clockNow = t0.add(const Duration(minutes: 10));
      await outgoing.recordReflectionSave(
        itemId: kept.id,
        reflection: 'The older local reflection.',
        isKeeper: true,
      );
      final afterLocalSave = await soleRecord();

      seedBucket();
      final genuinelyNewerRemote = remoteVersionOf(
        afterLocalSave,
        reflectionText: 'A genuinely newer remote reflection (another '
            'device).',
        reflectedAt: t0.add(const Duration(hours: 2)),
        updatedAt: t0.add(const Duration(hours: 2)), // newer than local
        mutationId: '99999999-0000-4000-8000-000000000003',
      );

      final result =
          await incoming.applyIncomingBatch(batchWith(genuinelyNewerRemote));
      expect(result.status, IncomingApplyStatus.applied);

      final afterIncoming = await soleRecord();
      expect(
        afterIncoming.reflectionText,
        'A genuinely newer remote reflection (another device).',
        reason: 'Documented conflict rule: strictly newer updatedAt '
            'legitimately wins, regardless of which side it is.',
      );
    });
  });

  group('CASE 4 -- remote missing the reflection field entirely', () {
    test(
        'an older remote that is identical except its reflection fields '
        'are simply absent must not erase newer local reflection fields',
        () async {
      clockNow = t0;
      await outgoing.recordKeep(
        revealId: revealIdX,
        wisdomText: 'A wisdom kept before any reflection existed.',
        revealedAt: t0,
        isKeeper: true,
      );
      final kept = await soleRecord();

      clockNow = t0.add(const Duration(minutes: 5));
      await outgoing.recordReflectionSave(
        itemId: kept.id,
        reflection: 'Added after the remote snapshot was taken.',
        isKeeper: true,
      );
      final afterLocalSave = await soleRecord();

      seedBucket();
      // Same occurrence, reflection fields simply absent (never synced),
      // older updatedAt -- the literal shape of "record as it existed on
      // the server before this device ever wrote a reflection".
      final remoteBeforeReflectionExisted = remoteVersionOf(
        afterLocalSave,
        reflectionText: null,
        reflectedAt: null,
        updatedAt: t0,
        mutationId: '99999999-0000-4000-8000-000000000004',
      );

      final result = await incoming
          .applyIncomingBatch(batchWith(remoteBeforeReflectionExisted));
      expect(result.status, IncomingApplyStatus.applied);

      final afterIncoming = await soleRecord();
      expect(
        afterIncoming.reflectionText,
        'Added after the remote snapshot was taken.',
      );
      expect(afterIncoming.reflectedAt, isNotNull);
    });
  });

  group('CASE 5 -- distinct revealIds never cross-merge', () {
    test('identical wisdomText but different revealIds stay fully separate',
        () async {
      clockNow = t0;
      await outgoing.recordKeep(
        revealId: revealIdX,
        wisdomText: 'The exact same wisdom text.',
        revealedAt: t0,
        isKeeper: true,
      );
      await outgoing.recordKeep(
        revealId: revealIdY,
        wisdomText: 'The exact same wisdom text.',
        revealedAt: t0,
        isKeeper: true,
      );
      final before = await keptRepository.loadAllRecords();
      expect(before, hasLength(2));
      final recordX = before.firstWhere((r) => r.revealId == revealIdX);

      clockNow = t0.add(const Duration(minutes: 10));
      await outgoing.recordReflectionSave(
        itemId: recordX.id,
        reflection: 'Only revealId X should ever carry this.',
        isKeeper: true,
      );

      final afterSave = await keptRepository.loadAllRecords();
      final xAfter = afterSave.firstWhere((r) => r.revealId == revealIdX);
      final yAfter = afterSave.firstWhere((r) => r.revealId == revealIdY);
      expect(xAfter.reflectionText, 'Only revealId X should ever carry this.');
      expect(
        yAfter.reflectionText,
        isNull,
        reason: 'revealId Y must never receive revealId X\'s reflection, '
            'despite sharing wisdomText.',
      );
    });
  });

  group(
      'CASE 6 -- reflection still pending in the outbox when stale '
      'incoming arrives', () {
    test(
        'the LOCAL mutation, still only present as a pending outbox entry '
        '(not yet acknowledged by CloudKit), must not be silently erased '
        'by a stale incoming fetch for the same revealId', () async {
      clockNow = t0;
      await outgoing.recordKeep(
        revealId: revealIdX,
        wisdomText: 'A wisdom whose reflection push has not landed yet.',
        revealedAt: t0,
        isKeeper: true,
      );
      final kept = await soleRecord();

      clockNow = t0.add(const Duration(minutes: 10));
      await outgoing.recordReflectionSave(
        itemId: kept.id,
        reflection: 'Queued for push, not yet acknowledged.',
        isKeeper: true,
      );
      final afterLocalSave = await soleRecord();

      // The pending push itself, exactly mirroring the winning local
      // content -- representing "already written locally and durably
      // queued to go out, but CloudKit has not acknowledged it yet".
      final pendingPush = CloudKeptWisdomProjection.active(
        afterLocalSave,
        dataEpoch: epoch,
      );
      seedBucket(
        outbox: [
          PersistedOutboxMutation(
            change: SyncChange(
              kind: SyncChangeKind.update,
              projection: pendingPush,
              enqueuedAt: clockNow,
            ),
          ),
        ],
      );

      final staleRemote = remoteVersionOf(
        afterLocalSave,
        reflectionText: null,
        reflectedAt: null,
        updatedAt: t0,
        mutationId: '99999999-0000-4000-8000-000000000005',
      );

      final result = await incoming.applyIncomingBatch(batchWith(staleRemote));
      expect(result.status, IncomingApplyStatus.applied);

      final afterIncoming = await soleRecord();
      expect(
        afterIncoming.reflectionText,
        'Queued for push, not yet acknowledged.',
        reason: 'A still-pending local outbox mutation must win over a '
            'stale incoming fetch for the same occurrence.',
      );
    });
  });
}
