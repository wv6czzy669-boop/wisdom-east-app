// Build 26 Phase 4E-2: coordinator-level tests for
// `KeptSyncIntegrationCoordinator` -- the real wiring between real local
// Kept/Reflection user mutations and the crash-safe LocalSyncIntent
// architecture. Every test here uses purely in-memory test doubles
// (`InMemoryKeptStateStore`, `InMemoryLocalSyncIntentStore`,
// `InMemorySyncPersistenceStore`) -- no real file I/O, no real CloudKit
// access.
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/models/kept_bootstrap_result.dart';
import 'package:wisdom_app/models/kept_record.dart';
import 'package:wisdom_app/models/kept_state_envelope.dart';
import 'package:wisdom_app/persistence/persistence_operation_coordinator.dart';
import 'package:wisdom_app/repositories/kept_repository.dart';
import 'package:wisdom_app/sync/data_epoch.dart';
import 'package:wisdom_app/sync_integration/kept_sync_integration_coordinator.dart';
import 'package:wisdom_app/sync_integration/local_sync_intent.dart';
import 'package:wisdom_app/sync_persistence/account_sync_state.dart';
import 'package:wisdom_app/utils/kept_timestamp_canonicalizer.dart';

import '../persistence_test_helpers.dart';
import 'in_memory_sync_test_doubles.dart';

/// Deterministic, canonical-UUID-v4-shaped id generator for tests --
/// `00000000-0000-4000-8000-<counter padded to 12 digits>`.
class _SequentialIdFactory {
  int _next = 0;

  String call() {
    final suffix = (_next++).toString().padLeft(12, '0');
    return '00000000-0000-4000-8000-$suffix';
  }
}

class _Harness {
  _Harness(
      {DateTime Function()? clock,
      int freeKeptLimit = 3,
      int freeReflectionLimit = 3,
      InMemoryLocalSyncIntentStore? intentStore,
      void Function()? onMutationCommitted})
      : store = InMemoryKeptStateStore(),
        intentStore = intentStore ?? InMemoryLocalSyncIntentStore(),
        syncPersistenceStore = InMemorySyncPersistenceStore(),
        _repositoryIdFactory = _SequentialIdFactory(),
        _coordinatorIdFactory = _SequentialIdFactory() {
    repository = KeptRepository(
      store: store,
      bootstrap: const KeptBootstrapResult.ready(),
      operationCoordinator: PersistenceOperationCoordinator(),
      clock: clock,
      idFactory: _repositoryIdFactory.call,
      freeKeptLimit: freeKeptLimit,
      freeReflectionLimit: freeReflectionLimit,
    );
    coordinator = KeptSyncIntegrationCoordinator(
      keptRepository: repository,
      intentStore: this.intentStore,
      syncPersistenceStore: syncPersistenceStore,
      idFactory: _coordinatorIdFactory.call,
      clock: clock,
      onMutationCommitted: onMutationCommitted,
    );
  }

  final InMemoryKeptStateStore store;
  final InMemoryLocalSyncIntentStore intentStore;
  final InMemorySyncPersistenceStore syncPersistenceStore;
  final _SequentialIdFactory _repositoryIdFactory;
  final _SequentialIdFactory _coordinatorIdFactory;
  late final KeptRepository repository;
  late final KeptSyncIntegrationCoordinator coordinator;
}

/// Build 26 Phase 4F fast-follow: an [InMemoryLocalSyncIntentStore] subclass
/// that appends a marker to a shared, injected [order] log every time
/// [advanceIntentStage] completes -- used only to prove the nudge callback
/// fires strictly *after* the intent has already reached
/// `localCommittedOutboxPending`, never before (see the "invoked only after
/// the intent reaches the outbox-ready stage" test below).
class _OrderTrackingIntentStore extends InMemoryLocalSyncIntentStore {
  _OrderTrackingIntentStore(this.order);

  final List<String> order;

  @override
  Future<void> advanceIntentStage({
    required String intentId,
    required LocalSyncIntentStage expectedStage,
    required LocalSyncIntentStage nextStage,
  }) async {
    await super.advanceIntentStage(
      intentId: intentId,
      expectedStage: expectedStage,
      nextStage: nextStage,
    );
    order.add('advanceIntentStage');
  }
}

const _fingerprint = 'test-account-fingerprint';
final _epoch = DataEpoch.parse('00000000-0000-4000-8000-000000000abc');

void main() {
  group('Keep', () {
    test(
        'produces exactly one active intent whose identity/timestamps match '
        'the persisted KeptRecord exactly', () async {
      final harness = _Harness(clock: () => DateTime.utc(2026, 8, 1, 12));

      final result = await harness.coordinator.recordKeep(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );

      expect(result.limitReached, isFalse);
      final record = harness.store.envelope!.activeRecords.single;

      final intents = await harness.intentStore.loadIntents();
      expect(intents, hasLength(1));
      final intent = intents.single;
      expect(intent.stage, LocalSyncIntentStage.localCommittedOutboxPending);
      expect(intent.payload.operation, LocalSyncIntentOperation.keep);
      expect(intent.payload.revealId, record.revealId);
      expect(intent.payload.localId, record.id);
      expect(intent.payload.mutationId, record.mutationId);
      expect(intent.payload.wisdomText, record.wisdomText);
      expect(intent.payload.revealedAtMs,
          record.revealedAt.millisecondsSinceEpoch);
      expect(intent.payload.keptAtMs, record.keptAt.millisecondsSinceEpoch);
      expect(
          intent.payload.updatedAtMs, record.updatedAt.millisecondsSinceEpoch);
    });

    test(
        'duplicate wisdom text under two different revealIds stays '
        'independent (two intents, two records)', () async {
      final harness = _Harness(clock: () => DateTime.utc(2026, 8, 1, 12));

      await harness.coordinator.recordKeep(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: true,
      );
      await harness.coordinator.recordKeep(
        revealId: 'a5f3c111-2222-4111-8111-222222222222',
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 2),
        isKeeper: true,
      );

      expect(harness.store.envelope!.activeRecords, hasLength(2));
      final intents = await harness.intentStore.loadIntents();
      expect(intents, hasLength(2));
      expect(
        intents.map((i) => i.payload.revealId).toSet(),
        {
          'a5f3c111-1111-4111-8111-111111111111',
          'a5f3c111-2222-4111-8111-222222222222',
        },
      );
    });

    test('a free-limit-blocked Keep creates no durable intent', () async {
      final harness = _Harness(freeKeptLimit: 1);
      await harness.coordinator.recordKeep(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        wisdomText: 'First.',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );

      final result = await harness.coordinator.recordKeep(
        revealId: 'a5f3c111-2222-4111-8111-222222222222',
        wisdomText: 'Second.',
        revealedAt: DateTime.utc(2026, 8, 2),
        isKeeper: false,
      );

      expect(result.limitReached, isTrue);
      expect(harness.store.envelope!.activeRecords, hasLength(1));
      final intents = await harness.intentStore.loadIntents();
      expect(intents, hasLength(1)); // only the first Keep's intent.
    });

    test('an already-kept revealId creates no new intent', () async {
      final harness = _Harness();
      const revealId = 'a5f3c111-1111-4111-8111-111111111111';
      await harness.coordinator.recordKeep(
        revealId: revealId,
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );

      final result = await harness.coordinator.recordKeep(
        revealId: revealId,
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );

      expect(result.limitReached, isFalse);
      expect(harness.store.envelope!.activeRecords, hasLength(1));
      expect(await harness.intentStore.loadIntents(), hasLength(1));
    });
  });

  group('Reflection save', () {
    test(
        'produces the complete target occurrence, not only the changed '
        'field', () async {
      final harness = _Harness(clock: () => DateTime.utc(2026, 8, 1, 12));
      final kept = await harness.coordinator.recordKeep(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );
      final itemId = kept.items.single.id;

      await harness.coordinator.recordReflectionSave(
        itemId: itemId,
        reflection: 'A quiet thought.',
        isKeeper: false,
        reflectedAt: DateTime.utc(2026, 8, 1, 13),
      );

      final record = harness.store.envelope!.activeRecords.single;
      final intents = await harness.intentStore.loadIntents();
      final intent = intents.single;
      expect(intent.payload.operation, LocalSyncIntentOperation.reflectionSave);
      expect(intent.payload.revealId, record.revealId);
      expect(intent.payload.localId, record.id);
      expect(intent.payload.wisdomText, record.wisdomText);
      expect(intent.payload.revealedAtMs,
          record.revealedAt.millisecondsSinceEpoch);
      expect(intent.payload.keptAtMs, record.keptAt.millisecondsSinceEpoch);
      expect(intent.payload.reflectionText, 'A quiet thought.');
      expect(intent.payload.reflectedAtMs,
          record.reflectedAt!.millisecondsSinceEpoch);
      expect(intent.payload.mutationId, record.mutationId);
      expect(
          intent.payload.updatedAtMs, record.updatedAt.millisecondsSinceEpoch);
    });

    test('unchanged reflection text creates no new intent', () async {
      final harness = _Harness();
      final kept = await harness.coordinator.recordKeep(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );
      final itemId = kept.items.single.id;
      await harness.coordinator.recordReflectionSave(
        itemId: itemId,
        reflection: 'Same.',
        isKeeper: false,
      );
      final intentsAfterFirstSave = await harness.intentStore.loadIntents();

      await harness.coordinator.recordReflectionSave(
        itemId: itemId,
        reflection: 'Same.',
        isKeeper: false,
      );

      expect(await harness.intentStore.loadIntents(), intentsAfterFirstSave);
    });

    test('a free-reflection-limit-blocked save creates no intent', () async {
      final harness = _Harness(freeReflectionLimit: 0);
      final kept = await harness.coordinator.recordKeep(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );
      final itemId = kept.items.single.id;
      final intentsBefore = await harness.intentStore.loadIntents();

      final result = await harness.coordinator.recordReflectionSave(
        itemId: itemId,
        reflection: 'Blocked.',
        isKeeper: false,
      );

      expect(result.reflectionLimitReached, isTrue);
      expect(await harness.intentStore.loadIntents(), intentsBefore);
    });
  });

  group('Reflection delete', () {
    test('produces an active target with Reflection absent', () async {
      final harness = _Harness();
      final kept = await harness.coordinator.recordKeep(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );
      final itemId = kept.items.single.id;
      await harness.coordinator.recordReflectionSave(
        itemId: itemId,
        reflection: 'A quiet thought.',
        isKeeper: false,
      );

      await harness.coordinator.recordReflectionDelete(itemId: itemId);

      final record = harness.store.envelope!.activeRecords.single;
      expect(record.reflectionText, isNull);
      final intents = await harness.intentStore.loadIntents();
      final intent = intents.single;
      expect(
          intent.payload.operation, LocalSyncIntentOperation.reflectionDelete);
      expect(intent.payload.reflectionText, isNull);
      expect(intent.payload.reflectedAtMs, isNull);
      // Never becomes a tombstone.
      expect(intent.payload.isTombstone, isFalse);
    });

    test('deleting an already-absent reflection creates no new intent',
        () async {
      final harness = _Harness();
      final kept = await harness.coordinator.recordKeep(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );
      final itemId = kept.items.single.id;
      final intentsBefore = await harness.intentStore.loadIntents();

      await harness.coordinator.recordReflectionDelete(itemId: itemId);

      expect(await harness.intentStore.loadIntents(), intentsBefore);
    });
  });

  group('Remove', () {
    test(
        'creates a complete tombstone intent with a fresh deletion-event '
        'mutationId, distinct from the removed record\'s own mutationId',
        () async {
      final harness = _Harness();
      final kept = await harness.coordinator.recordKeep(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );
      final removedRecordMutationId =
          harness.store.envelope!.activeRecords.single.mutationId;
      final itemId = kept.items.single.id;

      final removed = await harness.coordinator.recordRemove(itemId: itemId);

      expect(removed, isNotNull);
      expect(harness.store.envelope!.activeRecords, isEmpty);
      final intents = await harness.intentStore.loadIntents();
      final intent = intents.single;
      expect(intent.payload.operation, LocalSyncIntentOperation.remove);
      expect(intent.payload.isTombstone, isTrue);
      expect(intent.payload.revealId, 'a5f3c111-1111-4111-8111-111111111111');
      expect(intent.payload.localId, itemId);
      expect(intent.payload.mutationId, isNot(removedRecordMutationId));
    });

    test('removing a missing item creates no intent', () async {
      final harness = _Harness();
      final removed =
          await harness.coordinator.recordRemove(itemId: 'nonexistent');
      expect(removed, isNull);
      expect(await harness.intentStore.loadIntents(), isEmpty);
    });

    test(
        're-Keep after tombstone mints a fresh id/mutationId and supersedes '
        'the pending tombstone intent', () async {
      final harness = _Harness();
      const revealId = 'a5f3c111-1111-4111-8111-111111111111';
      final kept = await harness.coordinator.recordKeep(
        revealId: revealId,
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );
      final firstId = kept.items.single.id;
      await harness.coordinator.recordRemove(itemId: firstId);

      final reKept = await harness.coordinator.recordKeep(
        revealId: revealId,
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );

      final newRecord = harness.store.envelope!.activeRecords.single;
      expect(newRecord.id, isNot(firstId));
      expect(reKept.limitReached, isFalse);

      final intents = await harness.intentStore.loadIntents();
      // Only one intent remains for this revealId -- the tombstone was
      // superseded by the fresh active intent, never left stacked alongside
      // it.
      expect(
          intents.where((i) => i.payload.revealId == revealId), hasLength(1));
      expect(intents.single.payload.operation, LocalSyncIntentOperation.keep);
      expect(intents.single.payload.isTombstone, isFalse);
    });
  });

  group('Replay (pendingLocalApplication)', () {
    test(
        'intent persistence failure inside onAuthorized leaves the Kept '
        'envelope completely unchanged', () async {
      final harness = _Harness();
      harness.intentStore.failNextEnqueueIntent = StateError('disk full');

      await expectLater(
        harness.coordinator.recordKeep(
          revealId: 'a5f3c111-1111-4111-8111-111111111111',
          wisdomText: 'Be still.',
          revealedAt: DateTime.utc(2026, 8, 1),
          isKeeper: false,
        ),
        throwsA(isA<StateError>()),
      );

      expect(harness.store.envelope, isNull);
      expect(await harness.intentStore.loadIntents(), isEmpty);

      // The integration lock must have been released despite the thrown
      // failure -- a subsequent, genuine mutation must be able to acquire it
      // and complete normally, proving this was not left permanently held.
      final recovered = await harness.coordinator.recordKeep(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );
      expect(recovered.limitReached, isFalse);
      expect(harness.store.envelope!.activeRecords, hasLength(1));
      expect(await harness.intentStore.loadIntents(), hasLength(1));
    });

    test(
        'replaying a still-pendingLocalApplication intent applies the exact '
        'captured identity/timestamps, mints nothing new, and does not '
        're-run the free-tier limit check', () async {
      final harness =
          _Harness(freeKeptLimit: 1, clock: () => DateTime.utc(2026, 8, 1, 12));

      // Simulate "crash after intent persistence but before the physical
      // Kept write completed" by durably writing the intent directly,
      // bypassing the repository call the coordinator would otherwise make.
      const revealId = 'a5f3c111-1111-4111-8111-111111111111';
      final intent = LocalSyncIntent(
        intentId: '00000000-0000-4000-8000-000000000099',
        kind: LocalSyncIntentKind.create,
        payload: LocalSyncIntentPayload.active(
          revealId: revealId,
          operation: LocalSyncIntentOperation.keep,
          wisdomText: 'Be still.',
          revealedAtMs: DateTime.utc(2026, 8, 1).millisecondsSinceEpoch,
          keptAtMs: DateTime.utc(2026, 8, 1, 12).millisecondsSinceEpoch,
          updatedAtMs: DateTime.utc(2026, 8, 1, 12).millisecondsSinceEpoch,
          mutationId: '00000000-0000-4000-8000-000000000098',
          localId: '00000000-0000-4000-8000-000000000097',
        ),
        stage: LocalSyncIntentStage.pendingLocalApplication,
        enqueuedAt: DateTime.utc(2026, 8, 1, 12),
      );
      await harness.intentStore.enqueueIntent(intent);

      // Now push the free-tier limit to its ceiling via a second, genuine
      // Keep -- if replay incorrectly re-ran the limit check, it would now
      // find the limit already met and silently fail to apply the
      // already-authorized mutation above.
      await harness.coordinator.recordKeep(
        revealId: 'a5f3c111-2222-4111-8111-222222222222',
        wisdomText: 'Something else.',
        revealedAt: DateTime.utc(2026, 8, 2),
        isKeeper: false,
      );

      await harness.coordinator.reconcileForAssociatedAccount(
        const AssociatedSyncAccountContext(accountFingerprint: _fingerprint),
      );

      final applied = harness.store.envelope!.activeRecords
          .firstWhere((r) => r.revealId == revealId);
      expect(applied.id, '00000000-0000-4000-8000-000000000097');
      expect(applied.mutationId, '00000000-0000-4000-8000-000000000098');
      expect(applied.keptAt.millisecondsSinceEpoch,
          DateTime.utc(2026, 8, 1, 12).millisecondsSinceEpoch);
    });
  });

  group('Account gating', () {
    for (final state in [
      AccountBootstrapState.notStarted,
      AccountBootstrapState.remoteBaselinePending,
      AccountBootstrapState.localReconciliationPending,
      AccountBootstrapState.associationRequired,
    ]) {
      test('bootstrapState $state never enqueues, never removes the intent',
          () async {
        final harness = _Harness();
        await harness.coordinator.recordKeep(
          revealId: 'a5f3c111-1111-4111-8111-111111111111',
          wisdomText: 'Be still.',
          revealedAt: DateTime.utc(2026, 8, 1),
          isKeeper: false,
        );
        harness.syncPersistenceStore.seedAccount(
          _fingerprint,
          AccountSyncState(dataEpoch: _epoch, bootstrapState: state),
        );

        await harness.coordinator.reconcileForAssociatedAccount(
          const AssociatedSyncAccountContext(accountFingerprint: _fingerprint),
        );

        expect(await harness.intentStore.loadIntents(), hasLength(1));
        final bucket =
            await harness.syncPersistenceStore.loadAccountState(_fingerprint);
        expect(bucket!.outbox, isEmpty);
      });
    }

    test('a missing account bucket never enqueues and never fabricates one',
        () async {
      final harness = _Harness();
      await harness.coordinator.recordKeep(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );

      await harness.coordinator.reconcileForAssociatedAccount(
        const AssociatedSyncAccountContext(accountFingerprint: _fingerprint),
      );

      expect(await harness.syncPersistenceStore.loadAccountState(_fingerprint),
          isNull);
      expect(await harness.intentStore.loadIntents(), hasLength(1));
    });

    test(
        'bootstrapState complete enqueues using exclusively the persisted '
        "bucket's own dataEpoch, then removes the intent", () async {
      final harness = _Harness();
      await harness.coordinator.recordKeep(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );
      harness.syncPersistenceStore.seedAccount(
        _fingerprint,
        AccountSyncState(
          dataEpoch: _epoch,
          bootstrapState: AccountBootstrapState.complete,
        ),
      );

      await harness.coordinator.reconcileForAssociatedAccount(
        const AssociatedSyncAccountContext(accountFingerprint: _fingerprint),
      );

      expect(await harness.intentStore.loadIntents(), isEmpty);
      final bucket =
          await harness.syncPersistenceStore.loadAccountState(_fingerprint);
      expect(bucket!.outbox, hasLength(1));
      expect(bucket.outbox.single.change.projection.dataEpoch, _epoch);
      expect(bucket.outbox.single.change.projection.revealId,
          'a5f3c111-1111-4111-8111-111111111111');
    });

    test('reconciliation is idempotent across repeated calls', () async {
      final harness = _Harness();
      await harness.coordinator.recordKeep(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );
      harness.syncPersistenceStore.seedAccount(
        _fingerprint,
        AccountSyncState(
            dataEpoch: _epoch, bootstrapState: AccountBootstrapState.complete),
      );

      final context =
          const AssociatedSyncAccountContext(accountFingerprint: _fingerprint);
      await harness.coordinator.reconcileForAssociatedAccount(context);
      await harness.coordinator.reconcileForAssociatedAccount(context);
      await harness.coordinator.reconcileForAssociatedAccount(context);

      final bucket =
          await harness.syncPersistenceStore.loadAccountState(_fingerprint);
      expect(bucket!.outbox, hasLength(1));
    });
  });

  group('Migration exclusion', () {
    test(
        'a write that bypasses the coordinator (mirroring '
        'KeptMigrationCoordinator writing the store directly) creates zero '
        'intents', () async {
      final harness = _Harness();
      // Mirrors KeptMigrationCoordinator's own direct `_keptStateStore
      // .replace(...)` call -- never touches KeptSyncIntegrationCoordinator,
      // KeptRepository's `onAuthorized` hook, or any preset parameter at
      // all.
      final migrated = KeptRecord(
        id: 'sr-v1-1700000000000000-1',
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        wisdomText: 'A migrated Build 25 record.',
        revealedAt: DateTime.utc(2025, 1, 1),
        keptAt: DateTime.utc(2025, 1, 1),
        updatedAt: DateTime.utc(2025, 1, 1),
        mutationId: '00000000-0000-4000-8000-000000000001',
      );
      harness.store.envelope = KeptStateEnvelope(activeRecords: [migrated]);

      expect(harness.store.envelope!.activeRecords, hasLength(1));
      expect(await harness.intentStore.loadIntents(), isEmpty);
    });
  });

  group('Concurrency (real Futures)', () {
    test(
        'stale pendingLocalApplication Reflection Save cannot replay after a '
        'newer Reflection Delete has already superseded it -- a genuine '
        'concurrent, lock-ordered proof', () async {
      // Build 26 Phase 4E-2 correction (post-Mac-failure root-cause fix):
      // the previous version of this test had two independent defects, both
      // in the test fixture, never in production:
      //
      // 1. It never gave the physical Kept record a real reflection before
      //    calling `recordReflectionDelete` -- `KeptRepository
      //    .deleteReflection`'s own pre-existing no-op-when-absent check
      //    (`if (existing.reflectionText == null) return _mapAll(envelope);`)
      //    therefore fired, `onAuthorized` was never invoked, no intent was
      //    ever created, and the stale intent was consequently never
      //    superseded at all -- the test's own premise ("B has already
      //    superseded A") was never established. Reconciliation then
      //    correctly found the still-current stale intent and correctly
      //    replayed it: that was production behaving exactly as designed
      //    given a scenario the test never actually built.
      // 2. The stale intent's `updatedAtMs` was a hardcoded literal
      //    (2026-08-01 09:00 UTC) while the harness used no injected clock,
      //    so the base record's `keptAt` came from the real, un-fixed
      //    `DateTime.now()` at whatever moment the suite actually executed.
      //    `KeptRecord._validate`'s `updatedAt >= keptAt` invariant is then
      //    satisfied or violated purely by accident of wall-clock time --
      //    on the Mac, real "now" fell after the hardcoded literal, so
      //    `KeptRecord.copyWith` correctly threw `FormatException: Kept
      //    record updatedAt cannot be before keptAt.` This was never a
      //    production defect to fix; `KeptRecord._validate` is correct and
      //    is not touched here.
      //
      // The fix below (a) uses one fixed, injected clock for every
      // timestamp in this test, so the domain invariant is satisfied by
      // construction rather than by luck, and (b) gives the record a real
      // reflection first, so `recordReflectionDelete` performs a genuine
      // authorized mutation that actually creates a superseding intent.
      final fixedClock = DateTime.utc(2026, 8, 1, 8);
      final harness = _Harness(clock: () => fixedClock);

      final kept = await harness.coordinator.recordKeep(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );
      final itemId = kept.items.single.id;
      final revealId = harness.store.envelope!.activeRecords.single.revealId;

      // A real, physically-committed reflection -- without this,
      // `recordReflectionDelete` below would be a silent no-op (see
      // defect 1 above) and "B" would never exist at all.
      await harness.coordinator.recordReflectionSave(
        itemId: itemId,
        reflection: 'Original reflection.',
        isKeeper: false,
      );
      final baseKeptAtMs = harness
          .store.envelope!.activeRecords.single.keptAt.millisecondsSinceEpoch;

      // A stale, already-superseded intent, seeded directly (as if left
      // behind by a crash before a real, later Reflection Delete ran).
      // Every timestamp here is derived from the same fixed clock the
      // harness uses everywhere else -- never a literal disconnected from
      // the real record's own `keptAt` (see defect 2 above).
      const staleIntentId = '00000000-0000-4000-8000-000000000050';
      final staleIntent = LocalSyncIntent(
        intentId: staleIntentId,
        kind: LocalSyncIntentKind.update,
        payload: LocalSyncIntentPayload.active(
          revealId: revealId,
          operation: LocalSyncIntentOperation.reflectionSave,
          wisdomText: 'Be still.',
          revealedAtMs: DateTime.utc(2026, 8, 1).millisecondsSinceEpoch,
          keptAtMs: baseKeptAtMs,
          updatedAtMs: fixedClock.millisecondsSinceEpoch,
          mutationId: '00000000-0000-4000-8000-000000000051',
          reflectionText: 'STALE TEXT THAT MUST NEVER WIN.',
          reflectedAtMs: fixedClock.millisecondsSinceEpoch,
          localId: itemId,
        ),
        stage: LocalSyncIntentStage.pendingLocalApplication,
        enqueuedAt: fixedClock,
      );
      await harness.intentStore.enqueueIntent(staleIntent);

      harness.syncPersistenceStore.seedAccount(
        _fingerprint,
        AccountSyncState(
          dataEpoch: _epoch,
          bootstrapState: AccountBootstrapState.complete,
        ),
      );

      // Launch the real, newer user action and a reconciliation pass
      // WITHOUT sequentially awaiting the first -- a genuine concurrent
      // race, not a sequential fake. `PersistenceOperationCoordinator
      // .runExclusive` registers its resource-key tail *synchronously*, at
      // call time (`_trackResourceTail` reads the current tail and installs
      // the new one with no `await` between the two steps). `
      // recordReflectionDelete` is itself a plain (non-`async`) function
      // that returns `runExclusive(...)` directly, so calling it on this
      // line registers `kept_sync_integration_v1`'s tail immediately --
      // strictly before `reconcileForAssociatedAccount` is even invoked on
      // the next line, let alone before its internal `await
      // _intentStore.loadIntents()` (its own first suspension point) can
      // reach the `for` loop that acquires the same key. This deterministic
      // FIFO tail registration -- not a lucky race -- is what guarantees
      // the delete's entire transaction (authorization, intent
      // supersession, physical write, stage advance) is queued ahead of
      // reconciliation's per-intent transaction for the stale candidate.
      final deleteFuture =
          harness.coordinator.recordReflectionDelete(itemId: itemId);
      final reconcileFuture = harness.coordinator.reconcileForAssociatedAccount(
        const AssociatedSyncAccountContext(accountFingerprint: _fingerprint),
      );
      await Future.wait([deleteFuture, reconcileFuture]);

      // Regardless of exactly when reconciliation's own candidate snapshot
      // ran relative to the delete's completion, the stale intent's own
      // identity must never survive, and it must never have won a replay.
      final afterFirstPass = await harness.intentStore.loadIntents();
      expect(
        afterFirstPass.any((intent) => intent.intentId == staleIntentId),
        isFalse,
        reason: 'the stale intent\'s own identity must never survive once '
            'the real Reflection Delete has superseded it',
      );
      expect(
        harness.store.envelope!.activeRecords.single.reflectionText,
        isNull,
        reason: 'the stale Reflection Save must never win over the newer '
            'Reflection Delete',
      );

      // A second, deterministic reconciliation pass settles whatever the
      // real Reflection Delete's own intent still needs -- it may or may
      // not have already been included in the first pass's candidate
      // snapshot, depending on exactly when that snapshot ran; this pass
      // removes that ambiguity and drives durable state to its final,
      // fully-settled shape so the outbox assertions below are exact, not
      // timing-dependent.
      await harness.coordinator.reconcileForAssociatedAccount(
        const AssociatedSyncAccountContext(accountFingerprint: _fingerprint),
      );

      expect(await harness.intentStore.loadIntents(), isEmpty);
      final bucket =
          await harness.syncPersistenceStore.loadAccountState(_fingerprint);
      expect(bucket!.outbox, hasLength(1));
      expect(bucket.outbox.single.change.projection.reflectionText, isNull);
      expect(
        harness.store.envelope!.activeRecords.single.reflectionText,
        isNull,
      );
    });

    test(
        'two simultaneous user mutations for the same revealId are fully '
        'serialized by the single integration lock', () async {
      final harness = _Harness();
      final kept = await harness.coordinator.recordKeep(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );
      final itemId = kept.items.single.id;

      final futureA = harness.coordinator.recordReflectionSave(
        itemId: itemId,
        reflection: 'First reflection.',
        isKeeper: false,
      );
      final futureB = harness.coordinator.recordReflectionSave(
        itemId: itemId,
        reflection: 'Second reflection.',
        isKeeper: false,
      );

      await Future.wait([futureA, futureB]);

      final record = harness.store.envelope!.activeRecords.single;
      // Whichever ran second wins -- but the record must reflect exactly
      // one coherent, non-corrupted final state, and exactly one intent
      // must exist for it afterward.
      expect(['First reflection.', 'Second reflection.'],
          contains(record.reflectionText));
      final intents = await harness.intentStore.loadIntents();
      expect(intents, hasLength(1));
      expect(intents.single.payload.reflectionText, record.reflectionText);
      expect(intents.single.payload.mutationId, record.mutationId);
    });

    test(
        'while reconciliation holds the integration lock, a concurrent user '
        'mutation is blocked until reconciliation completes', () async {
      final harness = _Harness();
      await harness.coordinator.recordKeep(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );

      final order = <String>[];
      // No account bucket exists, so reconciliation resolves quickly but
      // still must acquire and release the integration lock around its
      // (trivial) per-intent work.
      final reconcileFuture = harness.coordinator
          .reconcileForAssociatedAccount(
            const AssociatedSyncAccountContext(
                accountFingerprint: _fingerprint),
          )
          .then((_) => order.add('reconcile'));

      final mutationFuture = harness.coordinator
          .recordKeep(
            revealId: 'a5f3c111-2222-4111-8111-222222222222',
            wisdomText: 'Second.',
            revealedAt: DateTime.utc(2026, 8, 2),
            isKeeper: false,
          )
          .then((_) => order.add('mutation'));

      await Future.wait([reconcileFuture, mutationFuture]);

      // Both complete; the important invariant is that both operations
      // fully completed without corrupting shared state, regardless of
      // which happened to run first (the lock guarantees no interleaving,
      // not a specific order between two unrelated transactions).
      expect(order, containsAll(['reconcile', 'mutation']));
      expect(harness.store.envelope!.activeRecords, hasLength(2));
    });
  });

  group('Local-mutation nudge callback (Build 26 Phase 4F fast-follow)', () {
    test('a successful Keep invokes the callback exactly once', () async {
      var callCount = 0;
      final harness = _Harness(onMutationCommitted: () => callCount++);

      await harness.coordinator.recordKeep(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );

      expect(callCount, 1);
    });

    test('a successful Reflection save invokes the callback exactly once',
        () async {
      var callCount = 0;
      final harness = _Harness(onMutationCommitted: () => callCount++);
      final kept = await harness.coordinator.recordKeep(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );
      // Only isolate the Reflection-save invocation below; the Keep above
      // already correctly invoked the callback once of its own accord.
      expect(callCount, 1);
      callCount = 0;

      await harness.coordinator.recordReflectionSave(
        itemId: kept.items.single.id,
        reflection: 'A quiet thought.',
        isKeeper: false,
      );

      expect(callCount, 1);
    });

    test('a successful Reflection delete invokes the callback exactly once',
        () async {
      var callCount = 0;
      final harness = _Harness(onMutationCommitted: () => callCount++);
      final kept = await harness.coordinator.recordKeep(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );
      final itemId = kept.items.single.id;
      await harness.coordinator.recordReflectionSave(
        itemId: itemId,
        reflection: 'A quiet thought.',
        isKeeper: false,
      );
      callCount = 0;

      await harness.coordinator.recordReflectionDelete(itemId: itemId);

      expect(callCount, 1);
    });

    test('a successful Remove invokes the callback exactly once', () async {
      var callCount = 0;
      final harness = _Harness(onMutationCommitted: () => callCount++);
      final kept = await harness.coordinator.recordKeep(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );
      callCount = 0;

      final removed =
          await harness.coordinator.recordRemove(itemId: kept.items.single.id);

      expect(removed, isNotNull);
      expect(callCount, 1);
    });

    test('an already-Kept no-op never invokes the callback', () async {
      var callCount = 0;
      final harness = _Harness(onMutationCommitted: () => callCount++);
      const revealId = 'a5f3c111-1111-4111-8111-111111111111';
      await harness.coordinator.recordKeep(
        revealId: revealId,
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );
      callCount = 0;

      await harness.coordinator.recordKeep(
        revealId: revealId,
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );

      expect(callCount, 0);
    });

    test('a free-Kept-limit rejection never invokes the callback', () async {
      var callCount = 0;
      final harness =
          _Harness(freeKeptLimit: 1, onMutationCommitted: () => callCount++);
      await harness.coordinator.recordKeep(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        wisdomText: 'First.',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );
      callCount = 0;

      final result = await harness.coordinator.recordKeep(
        revealId: 'a5f3c111-2222-4111-8111-222222222222',
        wisdomText: 'Second.',
        revealedAt: DateTime.utc(2026, 8, 2),
        isKeeper: false,
      );

      expect(result.limitReached, isTrue);
      expect(callCount, 0);
    });

    test('a free-Reflection-limit rejection never invokes the callback',
        () async {
      var callCount = 0;
      final harness = _Harness(
          freeReflectionLimit: 0, onMutationCommitted: () => callCount++);
      final kept = await harness.coordinator.recordKeep(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );
      callCount = 0;

      final result = await harness.coordinator.recordReflectionSave(
        itemId: kept.items.single.id,
        reflection: 'Blocked.',
        isKeeper: false,
      );

      expect(result.reflectionLimitReached, isTrue);
      expect(callCount, 0);
    });

    test('an unchanged Reflection never invokes the callback', () async {
      var callCount = 0;
      final harness = _Harness(onMutationCommitted: () => callCount++);
      final kept = await harness.coordinator.recordKeep(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );
      final itemId = kept.items.single.id;
      await harness.coordinator.recordReflectionSave(
        itemId: itemId,
        reflection: 'Same.',
        isKeeper: false,
      );
      callCount = 0;

      await harness.coordinator.recordReflectionSave(
        itemId: itemId,
        reflection: 'Same.',
        isKeeper: false,
      );

      expect(callCount, 0);
    });

    test('removing a missing item never invokes the callback', () async {
      var callCount = 0;
      final harness = _Harness(onMutationCommitted: () => callCount++);

      final removed =
          await harness.coordinator.recordRemove(itemId: 'nonexistent');

      expect(removed, isNull);
      expect(callCount, 0);
    });

    test(
        'a callback that throws synchronously never affects the local '
        'mutation\'s own success or durability', () async {
      final harness = _Harness(onMutationCommitted: () {
        throw StateError('boom -- must be contained');
      });

      final result = await harness.coordinator.recordKeep(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );

      expect(result.limitReached, isFalse);
      expect(harness.store.envelope!.activeRecords, hasLength(1));
      final intents = await harness.intentStore.loadIntents();
      expect(intents, hasLength(1));
      expect(intents.single.stage,
          LocalSyncIntentStage.localCommittedOutboxPending);
    });

    test(
        'the callback is invoked only after the intent has already reached '
        'localCommittedOutboxPending -- never before', () async {
      final order = <String>[];
      final harness = _Harness(
        intentStore: _OrderTrackingIntentStore(order),
        onMutationCommitted: () => order.add('callback'),
      );

      await harness.coordinator.recordKeep(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );

      expect(order, ['advanceIntentStage', 'callback']);
    });

    test(
        'reconciliation/replay of a still-pending intent never invokes the '
        'user-mutation callback', () async {
      var callCount = 0;
      final harness = _Harness(onMutationCommitted: () => callCount++);

      // Seed a still-pendingLocalApplication intent directly, bypassing the
      // coordinator's own record* methods entirely (mirroring the existing
      // "replaying a still-pendingLocalApplication intent" test above) --
      // this is the only way to exercise `_replayPendingLocalApplication`
      // without it ever passing through a `record*` call site.
      const revealId = 'a5f3c111-1111-4111-8111-111111111111';
      final intent = LocalSyncIntent(
        intentId: '00000000-0000-4000-8000-000000000099',
        kind: LocalSyncIntentKind.create,
        payload: LocalSyncIntentPayload.active(
          revealId: revealId,
          operation: LocalSyncIntentOperation.keep,
          wisdomText: 'Be still.',
          revealedAtMs: DateTime.utc(2026, 8, 1).millisecondsSinceEpoch,
          keptAtMs: DateTime.utc(2026, 8, 1, 12).millisecondsSinceEpoch,
          updatedAtMs: DateTime.utc(2026, 8, 1, 12).millisecondsSinceEpoch,
          mutationId: '00000000-0000-4000-8000-000000000098',
          localId: '00000000-0000-4000-8000-000000000097',
        ),
        stage: LocalSyncIntentStage.pendingLocalApplication,
        enqueuedAt: DateTime.utc(2026, 8, 1, 12),
      );
      await harness.intentStore.enqueueIntent(intent);
      expect(callCount, 0);

      harness.syncPersistenceStore.seedAccount(
        _fingerprint,
        AccountSyncState(
          dataEpoch: _epoch,
          bootstrapState: AccountBootstrapState.complete,
        ),
      );

      await harness.coordinator.reconcileForAssociatedAccount(
        const AssociatedSyncAccountContext(accountFingerprint: _fingerprint),
      );

      // The replay + outbox handoff above durably applied and retired the
      // seeded intent -- proving reconciliation actually did real work --
      // yet the user-mutation nudge callback must never have fired for it.
      expect(await harness.intentStore.loadIntents(), isEmpty);
      final bucket =
          await harness.syncPersistenceStore.loadAccountState(_fingerprint);
      expect(bucket!.outbox, hasLength(1));
      expect(callCount, 0);
    });
  });

  group('Timestamp canonicalization (Phase 4G real-device fix)', () {
    // Root cause: `LocalSyncIntent.enqueuedAt` (and, transitively,
    // `SyncChange.enqueuedAt` once handed to `PersistedOutboxMutation`) is
    // encoded via `toUtc().millisecondsSinceEpoch` and decoded back with
    // zero microseconds, while both types' `operator==` compares with
    // `DateTime.isAtSameMomentAs`, exact to the microsecond. A raw clock
    // read on real iOS hardware routinely carries a non-zero microsecond
    // remainder, which made the real `ProtectedLocalSyncIntentStore`'s (and
    // `ProtectedSyncPersistenceStore`'s) own mandatory post-write read-back
    // verification correctly -- but spuriously, from the user's perspective
    // -- reject an otherwise valid write. Every `enqueuedAt:` construction
    // site in `KeptSyncIntegrationCoordinator` now wraps its clock read in
    // `canonicalizeKeptTimestamp` before constructing the persisted object.
    // This harness's stores are pure in-memory fakes with no JSON round
    // trip, so these tests assert directly on the constructed
    // `LocalSyncIntent`/`SyncChange` objects' `enqueuedAt` fields -- the
    // real-file round trip itself is covered separately, against the real
    // `ProtectedLocalSyncIntentStore`, in
    // `test/sync_integration/local_sync_intent_store_test.dart` (tests 26
    // and 27).
    final microsecondClock = DateTime.utc(2026, 8, 9, 12, 0, 0, 123, 456);
    final expectedCanonicalEnqueuedAt =
        canonicalizeKeptTimestamp(microsecondClock);

    test(
        'Keep: the constructed LocalSyncIntent.enqueuedAt is canonicalized '
        'to millisecond precision from a microsecond-precision clock',
        () async {
      final harness = _Harness(clock: () => microsecondClock);

      await harness.coordinator.recordKeep(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 9),
        isKeeper: false,
      );

      final intent = (await harness.intentStore.loadIntents()).single;
      expect(intent.enqueuedAt.microsecond, 0);
      expect(intent.enqueuedAt, expectedCanonicalEnqueuedAt);
      expect(
        intent.enqueuedAt.isAtSameMomentAs(expectedCanonicalEnqueuedAt),
        isTrue,
      );
    });

    test(
        'Reflection save: the constructed LocalSyncIntent.enqueuedAt is '
        'canonicalized to millisecond precision from a microsecond-precision '
        'clock', () async {
      final harness = _Harness(clock: () => microsecondClock);
      final kept = await harness.coordinator.recordKeep(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 9),
        isKeeper: false,
      );

      await harness.coordinator.recordReflectionSave(
        itemId: kept.items.single.id,
        reflection: 'A quiet thought.',
        isKeeper: false,
      );

      final intent = (await harness.intentStore.loadIntents())
          .firstWhere((i) => i.payload.operation ==
              LocalSyncIntentOperation.reflectionSave);
      expect(intent.enqueuedAt.microsecond, 0);
      expect(intent.enqueuedAt, expectedCanonicalEnqueuedAt);
    });

    test(
        'Reflection delete: the constructed LocalSyncIntent.enqueuedAt is '
        'canonicalized to millisecond precision from a microsecond-precision '
        'clock', () async {
      final harness = _Harness(clock: () => microsecondClock);
      final kept = await harness.coordinator.recordKeep(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 9),
        isKeeper: false,
      );
      final itemId = kept.items.single.id;
      await harness.coordinator.recordReflectionSave(
        itemId: itemId,
        reflection: 'A quiet thought.',
        isKeeper: false,
      );

      await harness.coordinator.recordReflectionDelete(itemId: itemId);

      final intent = (await harness.intentStore.loadIntents())
          .firstWhere((i) => i.payload.operation ==
              LocalSyncIntentOperation.reflectionDelete);
      expect(intent.enqueuedAt.microsecond, 0);
      expect(intent.enqueuedAt, expectedCanonicalEnqueuedAt);
    });

    test(
        'Remove: the constructed tombstone LocalSyncIntent.enqueuedAt is '
        'canonicalized to millisecond precision from a microsecond-precision '
        'clock, independent of the already-canonical deletedAt embedded in '
        'the tombstone payload', () async {
      final harness = _Harness(clock: () => microsecondClock);
      final kept = await harness.coordinator.recordKeep(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 9),
        isKeeper: false,
      );

      await harness.coordinator.recordRemove(itemId: kept.items.single.id);

      final intent = (await harness.intentStore.loadIntents()).single;
      expect(intent.payload.isTombstone, isTrue);
      expect(intent.enqueuedAt.microsecond, 0);
      expect(intent.enqueuedAt, expectedCanonicalEnqueuedAt);
      // The tombstone payload's own deletedAtMs was already canonicalized
      // (pre-existing behavior, unrelated to this fix) -- both timestamps
      // agree on the same canonical millisecond instant here only because
      // the harness's clock is fixed for the whole test; they remain two
      // independently-computed values in production.
      expect(
        intent.payload.deletedAtMs,
        expectedCanonicalEnqueuedAt.millisecondsSinceEpoch,
      );
    });

    test(
        'Reconciliation of an active (Keep) intent produces a SyncChange '
        'whose enqueuedAt is canonicalized to millisecond precision -- the '
        'active branch of _toSyncChange', () async {
      final harness = _Harness(clock: () => microsecondClock);
      await harness.coordinator.recordKeep(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 9),
        isKeeper: false,
      );
      harness.syncPersistenceStore.seedAccount(
        _fingerprint,
        AccountSyncState(
          dataEpoch: _epoch,
          bootstrapState: AccountBootstrapState.complete,
        ),
      );

      await harness.coordinator.reconcileForAssociatedAccount(
        const AssociatedSyncAccountContext(accountFingerprint: _fingerprint),
      );

      final bucket =
          await harness.syncPersistenceStore.loadAccountState(_fingerprint);
      final enqueuedAt = bucket!.outbox.single.change.enqueuedAt;
      expect(enqueuedAt.microsecond, 0);
      expect(enqueuedAt, expectedCanonicalEnqueuedAt);
    });

    test(
        'Reconciliation of a tombstone (Remove) intent produces a '
        'SyncChange whose enqueuedAt is canonicalized to millisecond '
        'precision -- the tombstone branch of _toSyncChange', () async {
      final harness = _Harness(clock: () => microsecondClock);
      final kept = await harness.coordinator.recordKeep(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 9),
        isKeeper: false,
      );
      await harness.coordinator.recordRemove(itemId: kept.items.single.id);
      harness.syncPersistenceStore.seedAccount(
        _fingerprint,
        AccountSyncState(
          dataEpoch: _epoch,
          bootstrapState: AccountBootstrapState.complete,
        ),
      );

      await harness.coordinator.reconcileForAssociatedAccount(
        const AssociatedSyncAccountContext(accountFingerprint: _fingerprint),
      );

      final bucket =
          await harness.syncPersistenceStore.loadAccountState(_fingerprint);
      final enqueuedAt = bucket!.outbox.single.change.enqueuedAt;
      expect(enqueuedAt.microsecond, 0);
      expect(enqueuedAt, expectedCanonicalEnqueuedAt);
    });
  });
}
