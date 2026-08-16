/// Build 26 Phase 5 (final slice): focused unit tests for
/// [ICloudRemovalController] -- the controller's own logic in isolation,
/// using the real [InMemorySyncPersistenceStore] test double (the exact same
/// CAS/idempotency semantics the production `ProtectedSyncPersistenceStore`
/// provides, no file I/O) for the happy-path/idempotency/fail-closed-account-
/// mismatch cases, plus a small set of throwing fakes for the read/write
/// exception cases. Widget-level proof that Settings itself wires and reacts
/// to this controller correctly lives in `test/settings_screen_test.dart`.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/controllers/icloud_removal_controller.dart';
import 'package:wisdom_app/sync/data_epoch.dart';
import 'package:wisdom_app/sync/sync_change.dart';
import 'package:wisdom_app/sync_persistence/account_sync_state.dart';
import 'package:wisdom_app/sync_persistence/associated_account_fingerprint_commit.dart';
import 'package:wisdom_app/sync_persistence/deletion_transaction_result.dart';
import 'package:wisdom_app/sync_persistence/incoming_batch_checkpoint.dart';
import 'package:wisdom_app/sync_persistence/outbox_mutation_retirement.dart';
import 'package:wisdom_app/sync_persistence/pending_deletion_transaction.dart';
import 'package:wisdom_app/sync_persistence/persisted_outbox_mutation.dart';
import 'package:wisdom_app/sync_persistence/sync_persistence_store.dart';

import '../sync_integration/in_memory_sync_test_doubles.dart';

String _fingerprint(int n) => n.toRadixString(16).padLeft(64, '0');

void main() {
  group('checkStatus', () {
    test('no associated account, no transaction -> notApplicable', () async {
      final store = InMemorySyncPersistenceStore();
      final controller = ICloudRemovalController(
        syncPersistenceStore: store,
        requestSyncAfterRemoval: () {},
      );

      final result = await controller.checkStatus();

      expect(result.displayStatus, ICloudRemovalDisplayStatus.notApplicable);
    });

    test('an associated account with no pending transaction -> idle', () async {
      final store = InMemorySyncPersistenceStore();
      store.seedAssociatedAccountFingerprint(_fingerprint(1));
      final controller = ICloudRemovalController(
        syncPersistenceStore: store,
        requestSyncAfterRemoval: () {},
      );

      final result = await controller.checkStatus();

      expect(result.displayStatus, ICloudRemovalDisplayStatus.idle);
    });

    test(
        'a durable pending deletion transaction -> pending, regardless of '
        'the association marker', () async {
      final store = InMemorySyncPersistenceStore();
      store.seedAssociatedAccountFingerprint(_fingerprint(1));
      store.seedPendingDeletionTransaction(
        PendingDeletionTransaction(
          accountFingerprint: _fingerprint(1),
          originalDataEpoch: null,
          replacementDataEpoch: DataEpoch.generate(),
          stage: DeletionTransactionStage.localFinalizePending,
        ),
      );
      final controller = ICloudRemovalController(
        syncPersistenceStore: store,
        requestSyncAfterRemoval: () {},
      );

      final result = await controller.checkStatus();

      expect(result.displayStatus, ICloudRemovalDisplayStatus.pending);
    });

    test(
        'a transaction pending with no associated marker (post-finalize '
        'marker clear, transaction not yet cleared) -> still pending, never '
        'idle/notApplicable', () async {
      final store = InMemorySyncPersistenceStore();
      store.seedPendingDeletionTransaction(
        PendingDeletionTransaction(
          accountFingerprint: _fingerprint(1),
          originalDataEpoch: null,
          replacementDataEpoch: DataEpoch.generate(),
          stage: DeletionTransactionStage.localFinalizePending,
        ),
      );
      final controller = ICloudRemovalController(
        syncPersistenceStore: store,
        requestSyncAfterRemoval: () {},
      );

      final result = await controller.checkStatus();

      expect(result.displayStatus, ICloudRemovalDisplayStatus.pending);
    });

    test('a transaction-read failure fails closed to notApplicable', () async {
      final controller = ICloudRemovalController(
        syncPersistenceStore: _ThrowingLoadPendingTransactionStore(),
        requestSyncAfterRemoval: () {},
      );

      final result = await controller.checkStatus();

      expect(result.displayStatus, ICloudRemovalDisplayStatus.notApplicable);
    });

    test(
        'a marker-read failure (after a clean "no transaction" read) fails '
        'closed to notApplicable', () async {
      final controller = ICloudRemovalController(
        syncPersistenceStore: _ThrowingLoadMarkerStore(),
        requestSyncAfterRemoval: () {},
      );

      final result = await controller.checkStatus();

      expect(result.displayStatus, ICloudRemovalDisplayStatus.notApplicable);
    });
  });

  group('beginRemoval', () {
    test(
        'no associated account -> notApplicable, zero mutation, callback '
        'never fires', () async {
      final store = InMemorySyncPersistenceStore();
      var callbackCount = 0;
      final controller = ICloudRemovalController(
        syncPersistenceStore: store,
        requestSyncAfterRemoval: () => callbackCount += 1,
      );

      final outcome = await controller.beginRemoval();

      expect(outcome, ICloudRemovalBeginOutcome.notApplicable);
      expect(await store.loadPendingDeletionTransaction(), isNull);
      expect(callbackCount, 0);
    });

    test(
        'an associated account with nothing pending -> started, durably '
        'begins the transaction for that exact account, and fires the '
        'sync-nudge callback exactly once', () async {
      final store = InMemorySyncPersistenceStore();
      store.seedAssociatedAccountFingerprint(_fingerprint(1));
      var callbackCount = 0;
      final controller = ICloudRemovalController(
        syncPersistenceStore: store,
        requestSyncAfterRemoval: () => callbackCount += 1,
      );

      final outcome = await controller.beginRemoval();

      expect(outcome, ICloudRemovalBeginOutcome.started);
      final transaction = await store.loadPendingDeletionTransaction();
      expect(transaction, isNotNull);
      expect(transaction!.accountFingerprint, _fingerprint(1));
      expect(transaction.stage, DeletionTransactionStage.prepared);
      expect(callbackCount, 1);
    });

    test(
        'a second call while the same account\'s transaction is already '
        'pending -> started again (idempotent resume, never a competing '
        'transaction), and fires the callback again', () async {
      final store = InMemorySyncPersistenceStore();
      store.seedAssociatedAccountFingerprint(_fingerprint(1));
      var callbackCount = 0;
      final controller = ICloudRemovalController(
        syncPersistenceStore: store,
        requestSyncAfterRemoval: () => callbackCount += 1,
      );

      final first = await controller.beginRemoval();
      final firstTransaction = await store.loadPendingDeletionTransaction();
      final second = await controller.beginRemoval();
      final secondTransaction = await store.loadPendingDeletionTransaction();

      expect(first, ICloudRemovalBeginOutcome.started);
      expect(second, ICloudRemovalBeginOutcome.started);
      expect(callbackCount, 2);
      // The exact same transaction -- never regenerated, never reset.
      expect(secondTransaction, firstTransaction);
    });

    test(
        'a transaction already pending for a DIFFERENT account than the '
        'one currently associated -> failed, zero mutation, callback never '
        'fires', () async {
      final store = InMemorySyncPersistenceStore();
      store.seedAssociatedAccountFingerprint(_fingerprint(1));
      store.seedPendingDeletionTransaction(
        PendingDeletionTransaction(
          accountFingerprint: _fingerprint(2),
          originalDataEpoch: null,
          replacementDataEpoch: DataEpoch.generate(),
          stage: DeletionTransactionStage.prepared,
        ),
      );
      var callbackCount = 0;
      final controller = ICloudRemovalController(
        syncPersistenceStore: store,
        requestSyncAfterRemoval: () => callbackCount += 1,
      );

      final outcome = await controller.beginRemoval();

      expect(outcome, ICloudRemovalBeginOutcome.failed);
      final transaction = await store.loadPendingDeletionTransaction();
      expect(transaction!.accountFingerprint, _fingerprint(2),
          reason: 'the existing transaction must be left completely '
              'untouched -- never retargeted.');
      expect(callbackCount, 0);
    });

    test('a marker-read failure -> failed, callback never fires', () async {
      var callbackCount = 0;
      final controller = ICloudRemovalController(
        syncPersistenceStore: _ThrowingLoadMarkerStore(),
        requestSyncAfterRemoval: () => callbackCount += 1,
      );

      final outcome = await controller.beginRemoval();

      expect(outcome, ICloudRemovalBeginOutcome.failed);
      expect(callbackCount, 0);
    });

    test(
        'an exception from beginDeletionTransaction itself -> failed, '
        'callback never fires', () async {
      var callbackCount = 0;
      final controller = ICloudRemovalController(
        syncPersistenceStore: _ThrowingBeginTransactionStore(),
        requestSyncAfterRemoval: () => callbackCount += 1,
      );

      final outcome = await controller.beginRemoval();

      expect(outcome, ICloudRemovalBeginOutcome.failed);
      expect(callbackCount, 0);
    });
  });

  group('layering / content-safety', () {
    test(
        'ICloudRemovalController never depends on Kept/Reflection/daily-'
        'access storage -- structural proof by source inspection, mirroring '
        'this codebase\'s established layering-test convention', () {
      final file = File('lib/controllers/icloud_removal_controller.dart');
      expect(file.existsSync(), isTrue);
      final source = file.readAsStringSync();
      const forbiddenImportFragments = [
        'kept_repository',
        'saved_reflections_service',
        'daily_access_repository',
        'daily_wisdom_access_service',
        'purchase_service',
        'sync_runtime',
        'sync_platform',
      ];
      for (final fragment in forbiddenImportFragments) {
        expect(
          source.contains(fragment),
          isFalse,
          reason: 'icloud_removal_controller.dart must never import or '
              'reference "$fragment" -- it only ever calls '
              'SyncPersistenceStore.beginDeletionTransaction/'
              'loadPendingDeletionTransaction/'
              'loadAssociatedAccountFingerprint, plus a plain callback for '
              'the sync nudge.',
        );
      }
      expect(
        source.contains('.requestSync('),
        isFalse,
        reason: 'This file must never call CloudKitSyncRuntimeCoordinator'
            '.requestSync itself -- only the injected '
            'requestSyncAfterRemoval callback.',
      );
    });
  });
}

/// A [SyncPersistenceStore] base whose every method throws
/// [UnimplementedError] -- each throwing fake below overrides only the one
/// or two methods its own scenario actually exercises, exactly mirroring
/// this codebase's other narrow, single-purpose test doubles (e.g.
/// `_CrashInjectingSyncPersistenceStore` in
/// `test/sync_deletion/local_deletion_finalizer_test.dart`, which wraps a
/// real delegate instead since it needs full pass-through; this base has no
/// real delegate at all since [ICloudRemovalController] only ever calls
/// three of these methods).
abstract class _UnimplementedSyncPersistenceStore
    implements SyncPersistenceStore {
  @override
  Future<AccountSyncState?> loadAccountState(String accountFingerprint) =>
      throw UnimplementedError();
  @override
  Future<void> replaceAccountState(
          String accountFingerprint, AccountSyncState state) =>
      throw UnimplementedError();
  @override
  Future<void> enqueueMutation(String accountFingerprint, SyncChange change) =>
      throw UnimplementedError();
  @override
  Future<void> applyMutationOutcomes(
    String accountFingerprint, {
    Set<String> acknowledgedMutationIds = const {},
    Map<String, PersistedOutboxMutationStatus> updatedStatusByMutationId =
        const {},
  }) =>
      throw UnimplementedError();
  @override
  Future<List<PersistedOutboxMutation>> readPendingMutations(
          String accountFingerprint) =>
      throw UnimplementedError();
  @override
  Future<void> replaceRecordSystemFields(
          String accountFingerprint, String recordName, String systemFields) =>
      throw UnimplementedError();
  @override
  Future<void> storeServerChangeToken(
          String accountFingerprint, String serverToken) =>
      throw UnimplementedError();
  @override
  Future<void> clearServerChangeToken(String accountFingerprint) =>
      throw UnimplementedError();
  @override
  Future<void> clearAccountState(String accountFingerprint) =>
      throw UnimplementedError();
  @override
  Future<void> quarantineAccountState(String accountFingerprint) =>
      throw UnimplementedError();
  @override
  Future<CommitIncomingBatchCheckpointResult> commitIncomingBatchCheckpoint(
    CommitIncomingBatchCheckpointRequest request,
  ) =>
      throw UnimplementedError();
  @override
  Future<RetireOutboxMutationResult> retireOutboxMutationIfCurrent(
    RetireOutboxMutationRequest request,
  ) =>
      throw UnimplementedError();
  @override
  Future<String?> loadAssociatedAccountFingerprint() =>
      throw UnimplementedError();
  @override
  Future<CommitAssociatedAccountFingerprintResult>
      commitAssociatedAccountFingerprint({
    required String fingerprint,
    required String? expectedCurrent,
  }) =>
          throw UnimplementedError();
  @override
  Future<ClearAssociatedAccountFingerprintResult>
      clearAssociatedAccountFingerprintIfCurrent({
    required String expectedCurrent,
  }) =>
          throw UnimplementedError();
  @override
  Future<List<String>> loadMeaningfulAccountFingerprints() =>
      throw UnimplementedError();
  @override
  Future<PendingDeletionTransaction?> loadPendingDeletionTransaction() =>
      throw UnimplementedError();
  @override
  Future<BeginDeletionTransactionResult> beginDeletionTransaction({
    required String accountFingerprint,
  }) =>
      throw UnimplementedError();
  @override
  Future<AdvanceDeletionTransactionResult> advanceDeletionTransactionStage({
    required String accountFingerprint,
    required DeletionTransactionStage expectedCurrentStage,
    required DeletionTransactionStage nextStage,
  }) =>
      throw UnimplementedError();
  @override
  Future<void> clearDeletionTransaction({
    required String accountFingerprint,
  }) =>
      throw UnimplementedError();
}

/// A [SyncPersistenceStore] fake whose [loadPendingDeletionTransaction]
/// throws -- proving [ICloudRemovalController.checkStatus]/[beginRemoval]
/// fail closed rather than propagate.
class _ThrowingLoadPendingTransactionStore
    extends _UnimplementedSyncPersistenceStore {
  @override
  Future<PendingDeletionTransaction?> loadPendingDeletionTransaction() async {
    throw Exception('simulated read failure');
  }
}

/// A [SyncPersistenceStore] fake whose [loadPendingDeletionTransaction]
/// cleanly reports "none", but [loadAssociatedAccountFingerprint] throws.
class _ThrowingLoadMarkerStore extends _UnimplementedSyncPersistenceStore {
  @override
  Future<PendingDeletionTransaction?> loadPendingDeletionTransaction() async =>
      null;

  @override
  Future<String?> loadAssociatedAccountFingerprint() async {
    throw Exception('simulated read failure');
  }
}

/// A [SyncPersistenceStore] fake whose reads succeed (an account is
/// associated, nothing pending) but [beginDeletionTransaction] itself
/// throws.
class _ThrowingBeginTransactionStore
    extends _UnimplementedSyncPersistenceStore {
  @override
  Future<PendingDeletionTransaction?> loadPendingDeletionTransaction() async =>
      null;

  @override
  Future<String?> loadAssociatedAccountFingerprint() async => _fingerprint(1);

  @override
  Future<BeginDeletionTransactionResult> beginDeletionTransaction({
    required String accountFingerprint,
  }) async {
    throw Exception('simulated write failure');
  }
}
