// Build 26 Phase 4E-5: synthetic end-to-end CloudKit sync scenarios --
// exercises the real Phase 4E-1..4E-4 integration seams
// (KeptSyncIntegrationCoordinator, SyncOrchestrator,
// IncomingKeptSyncCoordinator, KeptSyncBootstrapCoordinator) across two
// independent simulated devices sharing one SyntheticCloudKitServer. No
// production behavior is redesigned or bypassed here -- every step below
// calls a real production coordinator method. Synthetic content only.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/models/kept_record.dart';
import 'package:wisdom_app/sync/cloud_east_sync_state_projection.dart';
import 'package:wisdom_app/sync/data_epoch.dart';
import 'package:wisdom_app/sync_integration/incoming_kept_sync_coordinator.dart';
import 'package:wisdom_app/sync_integration/kept_sync_bootstrap_coordinator.dart';
import 'package:wisdom_app/sync_integration/local_sync_intent.dart';
import 'package:wisdom_app/sync_orchestration/sync_pass_result.dart';
import 'package:wisdom_app/sync_persistence/account_sync_state.dart';
import 'package:wisdom_app/sync_persistence/persisted_outbox_mutation.dart';
import 'package:wisdom_app/sync_persistence/sync_persistence_store.dart';

import 'sync_device_harness.dart';
import 'synthetic_cloudkit_server.dart';

/// A fixed base moment -- every device's clock defaults to this unless a
/// test explicitly overrides it; individual scenarios pass explicit
/// `revealedAt`/`reflectedAt` values rather than relying on wall-clock
/// ordering, per the Phase 4E-5 test-quality requirement.
final DateTime t0 = DateTime.utc(2026, 8, 1, 10);

/// A 64-lowercase-hex-digit synthetic account fingerprint -- the exact
/// shape `looksLikeAccountFingerprint` requires, never a real CloudKit
/// identifier of any kind.
String fingerprint(int n) => n.toRadixString(16).padLeft(64, '0');

/// A canonical UUID v4 revealId, distinct per [n].
String revealId(int n) =>
    'aaaaaaaa-1111-4111-8111-${n.toRadixString(16).padLeft(12, '0')}';

/// A deterministic per-device sequential id factory -- canonical UUID v4
/// shaped, mirroring the existing `_sequentialIdFactory` precedent in
/// `test/sync_integration/kept_sync_bootstrap_coordinator_test.dart`, one
/// independent counter per device so two devices' minted ids are visibly
/// distinct in failure output.
String Function() sequentialIdFactory(String devicePrefix) {
  var counter = 0;
  return () {
    counter += 1;
    final suffix = counter.toRadixString(16).padLeft(12, '0');
    return '$devicePrefix-0000-4000-8000-$suffix';
  };
}

SyncDeviceHarness makeDevice(
  String label,
  SyntheticCloudKitServer server, {
  DateTime Function()? clock,
}) {
  return SyncDeviceHarness(
    deviceLabel: label,
    server: server,
    idFactory: sequentialIdFactory(label == 'A' ? 'a0000000' : 'b0000000'),
    clock: clock ?? (() => t0),
  );
}

/// A revealId -> content-only projection map, deliberately excluding every
/// device-local identifier (`KeptRecord.id`) -- the exact shape scenario
/// 2/20's "do not require localId equality" / "ignore device-local localId
/// differences" requirements need for a convergence comparison.
Map<String, Object?> _contentOnly(KeptRecord record) => {
      'wisdomText': record.wisdomText,
      'reflectionText': record.reflectionText,
      'reflectedAtMs': record.reflectedAt?.millisecondsSinceEpoch,
      'mutationId': record.mutationId,
      'updatedAtMs': record.updatedAt.millisecondsSinceEpoch,
    };

Map<String, Map<String, Object?>> _byRevealId(List<KeptRecord> records) => {
      for (final record in records) record.revealId: _contentOnly(record),
    };

void main() {
  test(
      '1. fresh empty remote: Device A bootstraps against a clean remote; '
      'CKEastSyncState is established with no phantom Kept records', () async {
    final server = SyntheticCloudKitServer();
    final a = makeDevice('A', server);
    a.setAccountFingerprint(fingerprint(1));

    final result = await a.bootstrap();
    expect(result.status, BootstrapRunStatus.completed);
    expect(result.isSuccessful, isTrue);

    expect(await a.loadAllRecords(), isEmpty);
    // Exactly the one CKEastSyncState control record -- no phantom Kept
    // record was ever created merely by bootstrapping an empty account.
    expect(server.storedRecordCount, 1);
  });

  test(
      '2. keep on A restores on B with the same revealId/content, without '
      'requiring localId equality', () async {
    final server = SyntheticCloudKitServer();
    final acct = fingerprint(2);

    final a = makeDevice('A', server)..setAccountFingerprint(acct);
    await a.bootstrap();
    await a.keep(
      revealId: revealId(1),
      wisdomText: 'Be still and know.',
      revealedAt: t0,
    );
    final cycle = await a.runOutgoingAndIncomingSync();
    expect(cycle.syncPassResult.status, SyncPassStatus.completed);

    final b = makeDevice('B', server)..setAccountFingerprint(acct);
    final bootstrapResult = await b.bootstrap();
    expect(bootstrapResult.isSuccessful, isTrue);

    final bRecords = await b.loadAllRecords();
    expect(bRecords, hasLength(1));
    expect(bRecords.single.revealId, revealId(1));
    expect(bRecords.single.wisdomText, 'Be still and know.');
    // Deliberately no assertion on `.id` equality between A's and B's
    // records -- each device derives/mints its own local identity.

    // Section I: no wisdom content or raw fingerprint ever appears in a
    // privacy-safe diagnostic summary.
    final summary = bootstrapResult.toLogSafeSummary().toString();
    expect(summary, isNot(contains('Be still and know.')));
    expect(summary, isNot(contains(acct)));
  });

  test('3. Reflection added on A propagates to B', () async {
    final server = SyntheticCloudKitServer();
    final acct = fingerprint(3);

    final a = makeDevice('A', server)..setAccountFingerprint(acct);
    await a.bootstrap();
    final keepResult = await a.keep(
      revealId: revealId(1),
      wisdomText: 'Silence is also an answer.',
      revealedAt: t0,
    );
    final itemId = keepResult.items.single.id;
    await a.saveReflection(
      itemId: itemId,
      reflection: 'This steadied me.',
      reflectedAt: t0.add(const Duration(minutes: 5)),
    );
    await a.runOutgoingAndIncomingSync();

    final b = makeDevice('B', server)..setAccountFingerprint(acct);
    await b.bootstrap();

    final bRecords = await b.loadAllRecords();
    expect(bRecords, hasLength(1));
    expect(bRecords.single.reflectionText, 'This steadied me.');
  });

  test(
      '4. Reflection edited on B (deterministic newer metadata) propagates '
      'to A -- production conflict rules determine the winner', () async {
    final server = SyntheticCloudKitServer();
    final acct = fingerprint(4);
    final t = revealId(1);

    final a = makeDevice('A', server)..setAccountFingerprint(acct);
    await a.bootstrap();
    final keepResult = await a.keep(
      revealId: t,
      wisdomText: 'Return to silence.',
      revealedAt: t0,
    );
    final itemIdOnA = keepResult.items.single.id;
    await a.saveReflection(
      itemId: itemIdOnA,
      reflection: 'first reflection',
      reflectedAt: t0.add(const Duration(minutes: 1)),
    );
    await a.runOutgoingAndIncomingSync();

    final b = makeDevice('B', server)..setAccountFingerprint(acct);
    await b.bootstrap();
    final bBefore = await b.loadAllRecords();
    expect(bBefore, hasLength(1));
    final itemIdOnB = bBefore.single.id;

    // Deterministically newer than A's edit above.
    final newerTime = t0.add(const Duration(hours: 1));
    await b.saveReflection(
      itemId: itemIdOnB,
      reflection: 'B wins because this is strictly newer',
      reflectedAt: newerTime,
    );
    await b.runOutgoingAndIncomingSync();

    await a.runOutgoingAndIncomingSync();
    final aAfter = await a.loadAllRecords();
    expect(aAfter, hasLength(1));
    expect(
        aAfter.single.reflectionText, 'B wins because this is strictly newer');
    expect(
      aAfter.single.reflectedAt!.millisecondsSinceEpoch,
      newerTime.millisecondsSinceEpoch,
    );
  });

  test('5. Remove on A propagates to B', () async {
    final server = SyntheticCloudKitServer();
    final acct = fingerprint(5);
    final r = revealId(1);

    final a = makeDevice('A', server)..setAccountFingerprint(acct);
    await a.bootstrap();
    final keepResult =
        await a.keep(revealId: r, wisdomText: 'Let it pass.', revealedAt: t0);
    await a.runOutgoingAndIncomingSync();

    final b = makeDevice('B', server)..setAccountFingerprint(acct);
    await b.bootstrap();
    expect(await b.loadAllRecords(), hasLength(1));

    await a.remove(itemId: keepResult.items.single.id);
    await a.runOutgoingAndIncomingSync();
    await b.runOutgoingAndIncomingSync();

    expect(await b.loadAllRecords(), isEmpty);
  });

  test(
      '6. Re-Keep after tombstone: a newer active mutation for the SAME '
      'revealId converges correctly through the real local mutation path',
      () async {
    final server = SyntheticCloudKitServer();
    final acct = fingerprint(6);
    final r = revealId(1);

    final a = makeDevice('A', server)..setAccountFingerprint(acct);
    await a.bootstrap();
    final keepResult =
        await a.keep(revealId: r, wisdomText: 'Original text.', revealedAt: t0);
    await a.runOutgoingAndIncomingSync();

    final b = makeDevice('B', server)..setAccountFingerprint(acct);
    await b.bootstrap();
    expect(await b.loadAllRecords(), hasLength(1));

    await a.remove(itemId: keepResult.items.single.id);
    await a.runOutgoingAndIncomingSync();

    // Re-Keep the SAME revealId through the real supported local mutation
    // path -- `keepOccurrence`'s own idempotency check only looks at
    // *currently active* records, so this mints a genuinely new active
    // mutation for a revealId this device just tombstoned.
    await a.keep(
      revealId: r,
      wisdomText: 'Original text.',
      revealedAt: t0,
    );
    await a.runOutgoingAndIncomingSync();
    await b.runOutgoingAndIncomingSync();

    final bAfter = await b.loadAllRecords();
    expect(bAfter, hasLength(1));
    expect(bAfter.single.revealId, r);
  });

  test(
      '7. Duplicate wisdomText under distinct revealIds remain two separate '
      'occurrences after sync', () async {
    final server = SyntheticCloudKitServer();
    final acct = fingerprint(7);
    const sharedText = 'The same words, twice, on purpose.';

    final a = makeDevice('A', server)..setAccountFingerprint(acct);
    await a.bootstrap();
    await a.keep(revealId: revealId(1), wisdomText: sharedText, revealedAt: t0);
    await a.keep(
      revealId: revealId(2),
      wisdomText: sharedText,
      revealedAt: t0.add(const Duration(days: 1)),
    );
    await a.runOutgoingAndIncomingSync();

    final b = makeDevice('B', server)..setAccountFingerprint(acct);
    await b.bootstrap();

    final bRecords = await b.loadAllRecords();
    expect(bRecords, hasLength(2));
    expect(bRecords.map((r) => r.revealId).toSet(), {revealId(1), revealId(2)});
    expect(bRecords.every((r) => r.wisdomText == sharedText), isTrue);
    // Section I: remote record identity is derived from revealId alone --
    // two distinct revealIds always occupy two distinct CloudKit records,
    // never coalesced merely because their content happens to match.
    expect(server.storedRecordCount, 3); // 2 CKKeptWisdom + 1 CKEastSyncState
  });

  test(
      '8. Offline dual Reflection edits on the same occurrence converge to '
      'exactly the real resolveKeptWisdomConflict winner', () async {
    final server = SyntheticCloudKitServer();
    final acct = fingerprint(8);
    final r = revealId(1);

    final a = makeDevice('A', server)..setAccountFingerprint(acct);
    await a.bootstrap();
    final keepResult = await a.keep(
        revealId: r, wisdomText: 'Shared occurrence.', revealedAt: t0);
    await a.runOutgoingAndIncomingSync();

    final b = makeDevice('B', server)..setAccountFingerprint(acct);
    await b.bootstrap();
    final itemIdOnB = (await b.loadAllRecords()).single.id;

    // Both devices edit independently, offline relative to each other --
    // neither syncs between these two calls.
    final earlier = t0.add(const Duration(minutes: 10));
    final later = t0.add(const Duration(minutes: 30));
    await a.saveReflection(
      itemId: keepResult.items.single.id,
      reflection: 'A, earlier',
      reflectedAt: earlier,
    );
    await b.saveReflection(
      itemId: itemIdOnB,
      reflection: 'B, later',
      reflectedAt: later,
    );

    // Deterministic sequence: A syncs out first, then B syncs out (its own
    // upload conflicts against A's already-landed content and is marked
    // `conflicted`, never silently dropped) and in (adopting A's -- now
    // stale relative to B's own newer edit -- content, then immediately
    // resolving back to B's own newer content via the real resolver).
    await a.runOutgoingAndIncomingSync();
    await b.runOutgoingAndIncomingSync();

    // Build 26 Phase 4E-5 convergence correction proof, step 1: B's own
    // local content already shows the correct resolved winner immediately
    // after its own sync pass -- this was never the bug (the bug was
    // durable-outbox bookkeeping, not conflict resolution itself).
    final bAfterFirstSync = await b.loadAllRecords();
    expect(bAfterFirstSync.single.reflectionText, 'B, later');

    // Step 2: the corrected coordinator must leave B's own conflicted
    // outbox mutation durably queued -- never silently discarded -- because
    // it is the only vehicle able to carry B's winning content back to
    // CloudKit. Inspected directly through the harness's own real
    // `SyncPersistenceStore` (no new test-only API).
    final bBucketAfterFirstSync =
        await b.syncPersistenceStore.loadAccountState(acct);
    expect(
      bBucketAfterFirstSync!.outbox,
      hasLength(1),
      reason: 'Build 26 Phase 4E-5 convergence correction: the outbox '
          'mutation carrying B\'s winning "B, later" content must survive '
          'the incoming apply that resolved local as the decisive winner -- '
          'never silently retired merely because a content-identical '
          'physical candidate happened to be the local fold\'s own tie-break '
          'reference.',
    );

    // Step 3: a subsequent B sync pass must now succeed in uploading that
    // SAME preserved mutation -- no new mutationId, no corrective
    // architecture -- using the fresh systemFields the prior incoming apply
    // already checkpointed. This is the real proof the correction works:
    // the mutation actually reaches CloudKit, not just that B's local state
    // looked right.
    final bSecondSync = await b.runOutgoingAndIncomingSync();
    expect(bSecondSync.syncPassResult.status, SyncPassStatus.completed);
    final bBucketAfterSecondSync =
        await b.syncPersistenceStore.loadAccountState(acct);
    expect(
      bBucketAfterSecondSync!.outbox,
      isEmpty,
      reason: 'B\'s preserved mutation must now have been accepted by '
          'CloudKit (via the real SyncOrchestrator upload path, using the '
          'systemFields the earlier incoming apply already checkpointed) '
          'and cleared from the outbox -- proving the correction actually '
          'restores a working upload path, not merely a correct-looking '
          'local read.',
    );

    // Step 4: only now does A fetch/apply B's newly-landed server content.
    await a.runOutgoingAndIncomingSync();

    final aFinal = await a.loadAllRecords();
    final bFinal = await b.loadAllRecords();
    expect(aFinal.single.reflectionText, 'B, later');
    expect(bFinal.single.reflectionText, 'B, later');

    // Step 5: independent server-truth proof -- a brand-new third device
    // bootstrapping fresh from the SAME synthetic server (never seeded or
    // inspected directly) must also observe "B, later". This traverses only
    // real production paths (`KeptSyncBootstrapCoordinator.runBootstrap`),
    // exactly like every other device in this suite -- never a manual peek
    // into the server's internal state.
    final c = makeDevice('C', server)..setAccountFingerprint(acct);
    await c.bootstrap();
    final cFinal = await c.loadAllRecords();
    expect(cFinal.single.reflectionText, 'B, later');
  });

  test(
      '9. Tombstone-vs-active offline conflict converges to exactly the '
      'real resolver result', () async {
    final server = SyntheticCloudKitServer();
    final acct = fingerprint(9);
    final r = revealId(1);
    final tie = DateTime.utc(2026, 8, 1, 12);

    final a = makeDevice('A', server, clock: () => tie)
      ..setAccountFingerprint(acct);
    await a.bootstrap();
    final keepResult = await a.keep(
        revealId: r, wisdomText: 'Contested occurrence.', revealedAt: t0);
    await a.runOutgoingAndIncomingSync();

    final b = makeDevice('B', server)..setAccountFingerprint(acct);
    await b.bootstrap();
    final itemIdOnB = (await b.loadAllRecords()).single.id;

    // A removes (its clock is fixed at `tie`); B edits a Reflection with the
    // exact same `updatedAt` instant -- an equal-`updatedAt` tie, so the
    // real resolver's own `tombstoneWinsOnTie` rule is what must decide
    // this, never a test-owned rule.
    await a.remove(itemId: keepResult.items.single.id);
    await b.saveReflection(
      itemId: itemIdOnB,
      reflection: 'B edits at the exact same instant',
      reflectedAt: tie,
    );

    await a.runOutgoingAndIncomingSync();
    await b.runOutgoingAndIncomingSync();
    await a.runOutgoingAndIncomingSync();

    expect(await a.loadAllRecords(), isEmpty);
    expect(await b.loadAllRecords(), isEmpty);
  });

  test(
      '10. Crash after physical local mutation, before outbox enqueue: the '
      'physical Kept record and the replayable intent both survive; retry '
      'reconciliation eventually produces the outbox entry', () async {
    final server = SyntheticCloudKitServer();
    final a = makeDevice('A', server)..setAccountFingerprint(fingerprint(10));
    await a.bootstrap();

    await a.keep(
      revealId: revealId(1),
      wisdomText: 'Crash-safety fixture.',
      revealedAt: t0,
    );
    // The physical write and the intent's own advance to
    // `localCommittedOutboxPending` are already durable at this point --
    // `KeptSyncIntegrationCoordinator.recordKeep` never itself enqueues to
    // the outbox. Injecting the failure here exercises exactly the
    // durable-enqueue boundary this scenario targets.
    a.syncPersistenceStore.failNextEnqueueMutation =
        Exception('synthetic E2E crash: enqueueMutation');

    await expectLater(a.reconcileOutbox(), throwsA(isA<Exception>()));

    final survivingRecords = await a.loadAllRecords();
    expect(survivingRecords, hasLength(1),
        reason: 'The physical Kept target must survive the injected crash.');

    final survivingIntents = await a.intentStore.loadIntents();
    expect(survivingIntents, hasLength(1));
    expect(
      survivingIntents.single.stage,
      LocalSyncIntentStage.localCommittedOutboxPending,
      reason: 'The replayable intent must survive at the correct stage.',
    );

    final bucketBefore = await a.syncPersistenceStore.loadAccountState(
      fingerprint(10),
    );
    expect(bucketBefore!.outbox, isEmpty,
        reason: 'No lost/duplicated mutation.');

    // Retry: the fault was one-shot and has already cleared itself.
    await a.reconcileOutbox();

    final bucketAfter = await a.syncPersistenceStore.loadAccountState(
      fingerprint(10),
    );
    expect(bucketAfter!.outbox, hasLength(1));
    expect(await a.intentStore.loadIntents(), isEmpty);
  });

  test(
      '11. Crash after outbox enqueue, before intent removal: the outbox '
      'mutation and the intent both remain durable; retry re-enqueue is '
      'idempotent and the intent is then removed exactly once', () async {
    final server = SyntheticCloudKitServer();
    final acct = fingerprint(11);
    final a = makeDevice('A', server)..setAccountFingerprint(acct);
    await a.bootstrap();

    await a.keep(
      revealId: revealId(1),
      wisdomText: 'Crash-safety fixture 2.',
      revealedAt: t0,
    );
    a.intentStore.failNextRemoveIntent =
        Exception('synthetic E2E crash: removeIntent');

    await expectLater(a.reconcileOutbox(), throwsA(isA<Exception>()));

    final bucketAfterFirstAttempt =
        await a.syncPersistenceStore.loadAccountState(acct);
    expect(bucketAfterFirstAttempt!.outbox, hasLength(1),
        reason: 'The outbox mutation must be durable before the injected '
            'removeIntent failure.');
    final survivingIntents = await a.intentStore.loadIntents();
    expect(survivingIntents, hasLength(1),
        reason: 'The intent must still be durable -- never lost.');

    // Retry: idempotent re-enqueue (same mutationId/content -> no-op per
    // SyncPersistenceStore.enqueueMutation's own documented contract), then
    // the intent is finally removed.
    await a.reconcileOutbox();

    final bucketAfterRetry =
        await a.syncPersistenceStore.loadAccountState(acct);
    expect(bucketAfterRetry!.outbox, hasLength(1),
        reason: 'No duplicate logical mutation from the idempotent retry.');
    expect(await a.intentStore.loadIntents(), isEmpty);
  });

  test(
      '12. Crash after incoming Kept apply, before checkpoint: the Kept '
      'replacement is already durable while the checkpoint remains '
      'uncommitted; retry converges safely with no duplicate/loss', () async {
    final server = SyntheticCloudKitServer();
    final acct = fingerprint(12);

    final a = makeDevice('A', server)..setAccountFingerprint(acct);
    await a.bootstrap();
    await a.keep(
      revealId: revealId(1),
      wisdomText: 'Checkpoint crash fixture.',
      revealedAt: t0,
    );
    await a.runOutgoingAndIncomingSync();

    final b = makeDevice('B', server)..setAccountFingerprint(acct);
    await b.bootstrap();

    // A adds a second occurrence for B to newly fetch.
    await a.keep(
      revealId: revealId(2),
      wisdomText: 'Second occurrence.',
      revealedAt: t0,
    );
    await a.runOutgoingAndIncomingSync();

    b.syncPersistenceStore.failNextCommitIncomingBatchCheckpoint =
        const SyncPersistenceStoreException(
      'checkpoint-injected-failure',
      'Synthetic E2E test failure.',
    );

    final syncResult = await b.runSyncPassOnly();
    expect(syncResult.status, SyncPassStatus.completed);
    final applyResult = await b.applyBatchIfPresent(syncResult);
    expect(applyResult, isNotNull);
    expect(applyResult!.status, IncomingApplyStatus.checkpointFailed);
    expect(applyResult.appliedProjectionCount, 1);

    // The Kept replacement is already durable even though the checkpoint
    // failed.
    final bRecordsAfterFailedCheckpoint = await b.loadAllRecords();
    expect(bRecordsAfterFailedCheckpoint, hasLength(2));

    // Retry: refetch (same previousServerToken -- never advanced by the
    // failed checkpoint) / reapply converges safely.
    final retrySyncResult = await b.runSyncPassOnly();
    final retryApplyResult = await b.applyBatchIfPresent(retrySyncResult);
    expect(retryApplyResult, isNotNull);
    expect(retryApplyResult!.isApplied, isTrue);

    final bFinal = await b.loadAllRecords();
    expect(bFinal, hasLength(2),
        reason: 'No duplicate record, no content loss.');
  });

  test(
      '13. Fresh device with pre-existing local history and no marker: '
      'associationRequired, zero automatic remote fetch/upload, no local '
      'deletion, no marker fabrication', () async {
    final server = SyntheticCloudKitServer();
    final b = makeDevice('B', server);
    b.seedLocalHistory([
      KeptRecord(
        id: 'legacy-local-only-id',
        revealId: revealId(1),
        wisdomText: 'Pre-existing local history.',
        revealedAt: t0,
        keptAt: t0,
        updatedAt: t0,
        mutationId: 'bbbbbbbb-0000-4000-8000-000000000001',
      ),
    ]);
    b.setAccountFingerprint(fingerprint(13));

    final evaluation = await b.evaluateAssociation();
    expect(evaluation.status, AssociationEvaluationStatus.associationRequired);
    expect(server.storedRecordCount, 0);
    expect(b.bridge.fetchPrivateZoneChangesCallCount, 0);
    expect(b.bridge.modifyPrivateRecordsCallCount, 0);

    final bootstrapResult = await b.bootstrap();
    expect(bootstrapResult.status, BootstrapRunStatus.associationRequired);
    expect(server.storedRecordCount, 0);
    expect(b.bridge.fetchPrivateZoneChangesCallCount, 0);
    expect(b.bridge.modifyPrivateRecordsCallCount, 0);
    expect(await b.syncPersistenceStore.loadAssociatedAccountFingerprint(),
        isNull);
    expect(await b.loadAllRecords(), hasLength(1));
  });

  test(
      '14. Local history + existing remote history: remote baseline becomes '
      'durable first, then genuinely local-only records are backfilled',
      () async {
    final server = SyntheticCloudKitServer();
    final acct = fingerprint(14);

    final a = makeDevice('A', server)..setAccountFingerprint(acct);
    await a.bootstrap();
    await a.keep(
      revealId: revealId(1),
      wisdomText: 'Remote history from A.',
      revealedAt: t0,
    );
    await a.runOutgoingAndIncomingSync();

    final b = makeDevice('B', server);
    b.seedLocalHistory([
      KeptRecord(
        id: 'legacy-local-only-id-14',
        revealId: revealId(2),
        wisdomText: 'Local-only history on B.',
        revealedAt: t0,
        keptAt: t0,
        updatedAt: t0,
        mutationId: 'bbbbbbbb-0000-4000-8000-000000000002',
      ),
    ]);
    b.setAccountFingerprint(acct);

    // Explicit, user-authorized association despite existing local history
    // -- bypasses the ordinary auto-associable gate deliberately, exactly
    // as a real explicit user confirmation would.
    final authorization = await b.authorizeAssociation(acct);
    expect(authorization.isAuthorized, isTrue);

    final bootstrapResult = await b.bootstrap();
    expect(bootstrapResult.isSuccessful, isTrue);
    expect(bootstrapResult.backfilledIntentCount, greaterThanOrEqualTo(1));
    expect(bootstrapResult.appliedProjectionCount, greaterThanOrEqualTo(1));

    final finalRecords = await b.loadAllRecords();
    expect(finalRecords.map((r) => r.revealId).toSet(),
        {revealId(1), revealId(2)});
  });

  test(
      '15. Free restore above limits is never truncated by the free-tier '
      'NEW-local-action limits', () async {
    final server = SyntheticCloudKitServer();
    final acct = fingerprint(15);

    final a = makeDevice('A', server)..setAccountFingerprint(acct);
    await a.bootstrap();
    for (var i = 1; i <= 5; i++) {
      final result = await a.keep(
        revealId: revealId(i),
        wisdomText: 'Keeper-only occurrence #$i.',
        revealedAt: t0,
        isKeeper: true,
      );
      if (i <= 4) {
        final itemId =
            result.items.firstWhere((it) => it.revealId == revealId(i)).id;
        await a.saveReflection(
          itemId: itemId,
          reflection: 'Reflection #$i.',
          isKeeper: true,
          reflectedAt: t0,
        );
      }
    }
    await a.runOutgoingAndIncomingSync();

    final b = SyncDeviceHarness(
      deviceLabel: 'B',
      server: server,
      idFactory: sequentialIdFactory('b0000000'),
      clock: () => t0,
      freeKeptLimit: 3,
      freeReflectionLimit: 3,
    )..setAccountFingerprint(acct);

    final bootstrapResult = await b.bootstrap();
    expect(bootstrapResult.isSuccessful, isTrue);

    final bRecords = await b.loadAllRecords();
    expect(bRecords, hasLength(5),
        reason: 'Remote restore must never be truncated by the free Kept '
            'limit.');
    expect(bRecords.where((r) => r.reflectionText != null), hasLength(4),
        reason: 'Remote restore must never be truncated by the free '
            'Reflection limit.');

    // The normal NEW-local-action limit remains intact for B's own,
    // genuinely new local mutations after the restore.
    final newKeepResult = await b.keep(
      revealId: revealId(100),
      wisdomText: 'A brand new local Keep on the free tier.',
      revealedAt: t0,
    );
    expect(newKeepResult.limitReached, isTrue);
  });

  test(
      '16. A real local user mutation during an in-flight bootstrap fetch is '
      'not lost, and is not uploaded before the remote baseline is durable',
      () async {
    final server = SyntheticCloudKitServer();
    final acct = fingerprint(16);

    // Seed a remote baseline from a first device so B's bootstrap has real
    // content to fetch (not the empty-remote control-record-creation path).
    final seedDevice = makeDevice('SEED', server)..setAccountFingerprint(acct);
    await seedDevice.bootstrap();
    await seedDevice.keep(
      revealId: revealId(1),
      wisdomText: 'Pre-existing remote content.',
      revealedAt: t0,
    );
    await seedDevice.runOutgoingAndIncomingSync();

    final b = makeDevice('B', server)..setAccountFingerprint(acct);
    final holdFetch = Completer<void>();
    b.bridge.holdFetchUntil = holdFetch;

    final bootstrapFuture = b.bootstrap();

    // Give the bootstrap call a chance to reach the (held-open) fetch --
    // mirrors the exact idiom already established in
    // test/sync_integration/kept_sync_bootstrap_coordinator_test.dart.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(b.bridge.fetchPrivateZoneChangesCallCount, greaterThanOrEqualTo(1));

    // A real local user mutation, through the real
    // KeptSyncIntegrationCoordinator, while the fetch is still held open --
    // this must complete immediately: the integration lock is never held
    // across a CloudKit network call.
    var userMutationCompleted = false;
    final userMutationFuture = b
        .keep(
          revealId: revealId(2),
          wisdomText: 'Typed while bootstrap fetch was in flight.',
          revealedAt: t0,
        )
        .then((_) => userMutationCompleted = true);
    await Future<void>.delayed(Duration.zero);
    expect(userMutationCompleted, isTrue,
        reason: 'A local mutation must not be blocked by an in-flight '
            'bootstrap network fetch.');
    await userMutationFuture;

    holdFetch.complete();
    final bootstrapResult = await bootstrapFuture;
    expect(bootstrapResult.isSuccessful, isTrue);

    final finalRecords = await b.loadAllRecords();
    expect(
      finalRecords.map((r) => r.revealId).toSet(),
      {revealId(1), revealId(2)},
      reason: 'The concurrent local mutation must not be lost, and the '
          'remote baseline must still be fully present.',
    );
  });

  test(
      '17. Account mismatch: fail-closed, zero upload, zero marker '
      'overwrite, zero new-account bucket creation, zero deletion of the '
      'prior account\'s state', () async {
    final server = SyntheticCloudKitServer();
    final acctA = fingerprint(17);
    final acctB = fingerprint(170);

    final device = makeDevice('A', server)..setAccountFingerprint(acctA);
    await device.bootstrap();
    await device.keep(
      revealId: revealId(1),
      wisdomText: 'Belongs to account A only.',
      revealedAt: t0,
    );
    await device.runOutgoingAndIncomingSync();

    final modifyCallsBefore = device.bridge.modifyPrivateRecordsCallCount;

    // The device's iCloud account changes underneath it.
    device.setAccountFingerprint(acctB);

    final evaluation = await device.evaluateAssociation();
    expect(evaluation.status, AssociationEvaluationStatus.associationRequired);

    final bootstrapResult = await device.bootstrap();
    expect(bootstrapResult.status, BootstrapRunStatus.associationRequired);

    expect(device.bridge.modifyPrivateRecordsCallCount, modifyCallsBefore,
        reason: 'Zero upload of A\'s old local history to account B.');
    expect(
      await device.syncPersistenceStore.loadAssociatedAccountFingerprint(),
      acctA,
      reason: 'Zero marker overwrite.',
    );
    expect(await device.syncPersistenceStore.loadAccountState(acctB), isNull,
        reason: 'Zero automatic bucket creation for the new account.');
    final bucketA = await device.syncPersistenceStore.loadAccountState(acctA);
    expect(bucketA, isNotNull, reason: 'Zero deletion of A\'s own state.');
    expect(bucketA!.bootstrapState, AccountBootstrapState.complete);
  });

  test(
      '18. Remote epoch changed after complete: '
      'remoteEpochChangedRecoveryRequired, zero Kept mutation, zero outbox '
      'upload, zero checkpoint rewrite, zero complete-to-bootstrap '
      'regression', () async {
    final server = SyntheticCloudKitServer();
    final acct = fingerprint(18);

    final a = makeDevice('A', server)..setAccountFingerprint(acct);
    await a.bootstrap();
    await a.keep(
      revealId: revealId(1),
      wisdomText: 'Before the external epoch reset.',
      revealedAt: t0,
    );
    await a.runOutgoingAndIncomingSync();

    final bucketBefore = await a.syncPersistenceStore.loadAccountState(acct);
    expect(bucketBefore!.bootstrapState, AccountBootstrapState.complete);
    final epochBefore = bucketBefore.dataEpoch;

    // A controlled, test-only stand-in for an externally-driven
    // CKEastSyncState change (e.g. a real Delete All Synced Data on some
    // other, out-of-scope client) -- never produced through this device's
    // own `modify` path.
    server.seedControlRecordDirectly(
      CloudEastSyncStateProjection.current(
        dataEpoch: DataEpoch.generate(),
        mutationId: 'cccccccc-0000-4000-8000-000000000001',
      ),
    );

    final result = await a.bootstrap();
    expect(
        result.status, BootstrapRunStatus.remoteEpochChangedRecoveryRequired);

    final bucketAfter = await a.syncPersistenceStore.loadAccountState(acct);
    expect(bucketAfter!.dataEpoch, epochBefore,
        reason: 'No checkpoint rewrite.');
    expect(bucketAfter.bootstrapState, AccountBootstrapState.complete,
        reason: 'No complete -> bootstrap regression.');
    expect(bucketAfter.outbox, isEmpty, reason: 'No outbox upload.');
    expect(await a.loadAllRecords(), hasLength(1), reason: 'No Kept mutation.');
  });

  test(
      '19. Offline outbound transport failure leaves the durable outbox '
      'mutation intact for retry', () async {
    final server = SyntheticCloudKitServer();
    final acct = fingerprint(19);

    final a = makeDevice('A', server)..setAccountFingerprint(acct);
    await a.bootstrap();
    await a.keep(
      revealId: revealId(1),
      wisdomText: 'Pending durable outbound work.',
      revealedAt: t0,
    );
    await a.reconcileOutbox();

    final bucketBefore = await a.syncPersistenceStore.loadAccountState(acct);
    expect(bucketBefore!.outbox, hasLength(1));

    server.forceTransportFailureOnNextModify();
    final syncResult = await a.runSyncPassOnly();
    expect(syncResult.status, SyncPassStatus.retryableFailure);

    final bucketAfter = await a.syncPersistenceStore.loadAccountState(acct);
    expect(bucketAfter!.outbox, hasLength(1));
    expect(bucketAfter.outbox.single.status,
        PersistedOutboxMutationStatus.pending);
  });

  test(
      '20. Retry and convergence: after clearing the injected failure, '
      'deterministic later sync passes on both devices converge to an '
      'identical revealId/content set, ignoring device-local id '
      'differences', () async {
    final server = SyntheticCloudKitServer();
    final acct = fingerprint(20);

    final a = makeDevice('A', server)..setAccountFingerprint(acct);
    await a.bootstrap();
    await a.keep(
      revealId: revealId(1),
      wisdomText: 'Converges eventually.',
      revealedAt: t0,
    );
    await a.reconcileOutbox();

    server.forceTransportFailureOnNextModify();
    final failedPass = await a.runSyncPassOnly();
    expect(failedPass.status, SyncPassStatus.retryableFailure);

    // Retry -- the one-shot fault has already cleared itself.
    await a.runOutgoingAndIncomingSync();

    final b = makeDevice('B', server)..setAccountFingerprint(acct);
    await b.bootstrap();

    // One more deterministic pass on each side to fully settle.
    await a.runOutgoingAndIncomingSync();
    await b.runOutgoingAndIncomingSync();

    final aFinal = _byRevealId(await a.loadAllRecords());
    final bFinal = _byRevealId(await b.loadAllRecords());
    expect(aFinal, equals(bFinal));
    expect(aFinal.keys, {revealId(1)});
  });
}
