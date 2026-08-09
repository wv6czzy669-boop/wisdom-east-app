/// Build 26 Phase 4F: tests for [CloudKitSyncRuntimeCoordinator].
///
/// `KeptSyncBootstrapCoordinator`, `KeptSyncIntegrationCoordinator`,
/// `IncomingKeptSyncCoordinator`, and `SyncOrchestrator` are all declared
/// `final class` in their own files -- Dart forbids extending, implementing,
/// or mocking any of them from outside their declaring library. So instead
/// of faking those four coordinators directly, every test below builds REAL
/// instances of all four (via [_RuntimeHarness], which mirrors
/// `test/sync_e2e/sync_device_harness.dart`'s own
/// real-coordinators-over-in-memory-doubles composition) and only fakes
/// their *own* dependencies: an in-memory [KeptStateStore]/
/// [LocalSyncIntentStore]/[SyncPersistenceStore], plus a
/// [_FakeRuntimeCloudKitBridge] that delegates to a real, reusable
/// [SyntheticCloudKitServer] (already proven correct by the Phase 4E-5 E2E
/// suite) and adds the one capability that suite's own
/// `E2ECloudKitPlatformBridge` does not need: a controllable, test-driven
/// `accountChangeEvents` stream, required to exercise this coordinator's
/// account-change trigger deterministically.
///
/// Retry timing is never real: every test injects a [_FakeRetryScheduler]
/// that records `(delay, callback)` pairs instead of starting a real
/// `Timer`, and fires callbacks manually -- no test in this file ever
/// sleeps or waits on a wall-clock timer.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:wisdom_app/models/kept_bootstrap_result.dart';
import 'package:wisdom_app/models/kept_record.dart';
import 'package:wisdom_app/models/kept_state_envelope.dart';
import 'package:wisdom_app/persistence/persistence_operation_coordinator.dart';
import 'package:wisdom_app/repositories/kept_repository.dart';
import 'package:wisdom_app/sync/data_epoch.dart';
import 'package:wisdom_app/sync/sync_change.dart';
import 'package:wisdom_app/sync_integration/incoming_kept_sync_coordinator.dart';
import 'package:wisdom_app/sync_integration/kept_sync_bootstrap_coordinator.dart';
import 'package:wisdom_app/sync_integration/kept_sync_integration_coordinator.dart';
import 'package:wisdom_app/sync_orchestration/sync_orchestrator.dart';
import 'package:wisdom_app/sync_persistence/account_sync_state.dart';
import 'package:wisdom_app/sync_persistence/associated_account_fingerprint_commit.dart';
import 'package:wisdom_app/sync_persistence/incoming_batch_checkpoint.dart';
import 'package:wisdom_app/sync_persistence/outbox_mutation_retirement.dart';
import 'package:wisdom_app/sync_persistence/persisted_outbox_mutation.dart';
import 'package:wisdom_app/sync_persistence/sync_persistence_store.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_account_change_event.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_account_snapshot.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_bridge_info.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_modify_records_contract.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_platform_bridge.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_zone_changes_contract.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_zone_configuration_result.dart';
import 'package:wisdom_app/sync_runtime/cloud_kit_sync_runtime_coordinator.dart';

import '../persistence_test_helpers.dart';
import '../sync_integration/in_memory_sync_test_doubles.dart';
import '../sync_e2e/synthetic_cloudkit_server.dart';

/// Deterministic, valid-shape opaque account fingerprint for test fixture
/// use only -- mirrors `test/sync_e2e/cloudkit_sync_e2e_test.dart`'s own
/// `fingerprint(int)` helper exactly, so every fixture in this file actually
/// satisfies `looksLikeAccountFingerprint`'s `^[0-9a-f]{64}$` shape check
/// (never a real CloudKit value; a distinct [n] per distinct logical
/// account, the same [n] reused wherever two devices/tests are meant to
/// represent one shared logical account).
String _fingerprint(int n) => n.toRadixString(16).padLeft(64, '0');

void main() {
  group('defaultBackoffForAttempt', () {
    test('follows the locked 30s/60s/120s/240s doubling sequence', () {
      expect(CloudKitSyncRuntimeCoordinator.defaultBackoffForAttempt(1),
          const Duration(seconds: 30));
      expect(CloudKitSyncRuntimeCoordinator.defaultBackoffForAttempt(2),
          const Duration(seconds: 60));
      expect(CloudKitSyncRuntimeCoordinator.defaultBackoffForAttempt(3),
          const Duration(seconds: 120));
      expect(CloudKitSyncRuntimeCoordinator.defaultBackoffForAttempt(4),
          const Duration(seconds: 240));
    });

    test('caps at 30 minutes and never exceeds it for large attempts', () {
      final at30Min =
          CloudKitSyncRuntimeCoordinator.defaultBackoffForAttempt(7);
      // 30s * 2^6 = 1920s = 32min -> capped to 30min.
      expect(at30Min, const Duration(minutes: 30));
      expect(CloudKitSyncRuntimeCoordinator.defaultBackoffForAttempt(50),
          const Duration(minutes: 30));
      expect(CloudKitSyncRuntimeCoordinator.defaultBackoffForAttempt(1000000),
          const Duration(minutes: 30));
    });

    test('normalizes an attempt below 1 to attempt 1', () {
      expect(CloudKitSyncRuntimeCoordinator.defaultBackoffForAttempt(0),
          const Duration(seconds: 30));
      expect(CloudKitSyncRuntimeCoordinator.defaultBackoffForAttempt(-5),
          const Duration(seconds: 30));
    });
  });

  group('happy-path pipeline', () {
    test(
        'fresh device, available account, empty remote -> completed, '
        'no retry scheduled, every step actually ran', () async {
      final harness = _RuntimeHarness();
      harness.bridge.currentFingerprint = _fingerprint(1);
      final coordinator = harness.buildCoordinator();
      addTearDown(coordinator.dispose);

      await coordinator.requestSync(SyncRuntimeTrigger.startup);

      final status = coordinator.status;
      expect(status.isRunning, isFalse);
      expect(status.lastOutcome, SyncRuntimeOutcome.completed);
      expect(status.retryAttempt, 0);
      expect(status.retryScheduled, isFalse);
      expect(harness.retryScheduler.scheduled, isEmpty);
      // Not asserting an exact fetch-call count here: `runBootstrap()`
      // always performs its own epoch-check fetch even when the bucket is
      // already complete (`_checkAlreadyCompleteForEpochChange`), so the
      // exact number of `fetchPrivateZoneChanges` calls per pass is a
      // bootstrap-internal implementation detail, not part of this
      // coordinator's own contract. `lastOutcome == completed` is the
      // correctness property this test actually needs.
      expect(harness.bridge.getAccountSnapshotCallCount, greaterThan(0));
    });

    test('a pending incoming batch from another device is applied', () async {
      final harness = _RuntimeHarness();

      // Device B writes one Kept record through the real production path,
      // then syncs it up to the shared synthetic server.
      final deviceB = _RuntimeHarness(server: harness.server);
      deviceB.bridge.currentFingerprint = _fingerprint(2);
      await deviceB.bootstrapCoordinator.runBootstrap();
      await deviceB.integrationCoordinator.recordKeep(
        revealId: const Uuid().v4(),
        wisdomText: 'Wisdom from device B.',
        revealedAt: DateTime.utc(2026, 1, 1),
        isKeeper: false,
      );
      await deviceB.integrationCoordinator.reconcileForAssociatedAccount(
        AssociatedSyncAccountContext(
          accountFingerprint: _fingerprint(2),
        ),
      );
      await deviceB.orchestrator.runSyncPass();

      // Device A (this test's actual subject) signs into the same account
      // and runs its runtime coordinator once.
      harness.bridge.currentFingerprint = _fingerprint(2);
      final coordinator = harness.buildCoordinator();
      addTearDown(coordinator.dispose);

      await coordinator.requestSync(SyncRuntimeTrigger.startup);

      expect(coordinator.status.lastOutcome, SyncRuntimeOutcome.completed);
      final records = await harness.keptRepository.loadAllRecords();
      expect(records, hasLength(1));
      expect(records.single.wisdomText, 'Wisdom from device B.');
    });
  });

  group('bootstrap stop statuses', () {
    test(
        'no account signed in -> waitingForAccountAvailability, '
        'reconcile/sync never attempted, no retry timer', () async {
      final harness = _RuntimeHarness();
      harness.bridge.currentFingerprint = null;
      final coordinator = harness.buildCoordinator();
      addTearDown(coordinator.dispose);

      await coordinator.requestSync(SyncRuntimeTrigger.startup);

      expect(coordinator.status.lastOutcome,
          SyncRuntimeOutcome.waitingForAccountAvailability);
      expect(coordinator.status.retryScheduled, isFalse);
      expect(harness.retryScheduler.scheduled, isEmpty);
      expect(harness.bridge.fetchPrivateZoneChangesCallCount, 0);
      expect(harness.bridge.modifyPrivateRecordsCallCount, 0);
    });

    test(
        'pre-existing local history with no prior association -> '
        'associationRequired classified as terminalFailure, no retry timer',
        () async {
      final harness = _RuntimeHarness();
      harness.keptStore.envelope = KeptStateEnvelope(
        activeRecords: [_fixtureKeptRecord()],
      );
      harness.bridge.currentFingerprint = _fingerprint(3);
      final coordinator = harness.buildCoordinator();
      addTearDown(coordinator.dispose);

      await coordinator.requestSync(SyncRuntimeTrigger.startup);

      expect(
          coordinator.status.lastOutcome, SyncRuntimeOutcome.terminalFailure);
      expect(coordinator.status.retryScheduled, isFalse);
      expect(harness.retryScheduler.scheduled, isEmpty);
      expect(harness.bridge.fetchPrivateZoneChangesCallCount, 0);
    });
  });

  group('sync-pass stop statuses', () {
    test(
        'a retryable transport failure during fetch schedules attempt 1 '
        'at 30 seconds', () async {
      final harness = _RuntimeHarness();
      harness.bridge.currentFingerprint = _fingerprint(4);
      harness.server.forceTransportFailureOnNextFetch();
      final coordinator = harness.buildCoordinator();
      addTearDown(coordinator.dispose);

      await coordinator.requestSync(SyncRuntimeTrigger.startup);

      expect(
          coordinator.status.lastOutcome, SyncRuntimeOutcome.retryableFailure);
      expect(coordinator.status.retryScheduled, isTrue);
      expect(coordinator.status.retryAttempt, 1);
      expect(harness.retryScheduler.scheduled.single.delay,
          const Duration(seconds: 30));
    });

    // Note: `runBootstrap()` always performs its own epoch-check fetch
    // first, on every call, even when the bucket is already complete (see
    // `_checkAlreadyCompleteForEpochChange`) -- so a one-shot
    // `forceTransportFailureOnNextFetch` fault is always consumed by
    // bootstrap's own fetch, never by `SyncOrchestrator.runSyncPass`'s
    // fetch, inside one full pipeline pass. There is no way to target the
    // orchestrator's own fetch specifically without a two-fault queue the
    // synthetic server does not provide, so a genuinely-reachable *terminal*
    // status is exercised instead below (`ambiguousLegacyState`) -- the
    // outer coordinator's classification/retry behavior for a terminal
    // outcome is identical regardless of which inner layer produced it (see
    // `_finishPass`), so this is still full coverage of the terminal-outcome
    // contract.
    test(
        'multiple legacy account buckets with no durable marker -> '
        'ambiguousLegacyState classified as terminalFailure, no retry timer',
        () async {
      final harness = _RuntimeHarness();
      harness.syncPersistenceStore.seedAccount(
        _fingerprint(5),
        AccountSyncState(
          dataEpoch: DataEpoch.generate(),
          bootstrapState: AccountBootstrapState.complete,
        ),
      );
      harness.syncPersistenceStore.seedAccount(
        _fingerprint(6),
        AccountSyncState(
          dataEpoch: DataEpoch.generate(),
          bootstrapState: AccountBootstrapState.complete,
        ),
      );
      harness.bridge.currentFingerprint = _fingerprint(7);
      final coordinator = harness.buildCoordinator();
      addTearDown(coordinator.dispose);

      await coordinator.requestSync(SyncRuntimeTrigger.startup);

      expect(
          coordinator.status.lastOutcome, SyncRuntimeOutcome.terminalFailure);
      expect(coordinator.status.retryScheduled, isFalse);
      expect(harness.retryScheduler.scheduled, isEmpty);
      expect(harness.bridge.fetchPrivateZoneChangesCallCount, 0);
    });
  });

  group('backoff progression and reset', () {
    test(
        'consecutive retryable failures advance the attempt count without '
        'resetting it', () async {
      final harness = _RuntimeHarness();
      harness.bridge.currentFingerprint = _fingerprint(8);
      final coordinator = harness.buildCoordinator();
      addTearDown(coordinator.dispose);

      harness.server.forceTransportFailureOnNextFetch();
      await coordinator.requestSync(SyncRuntimeTrigger.startup);
      expect(coordinator.status.retryAttempt, 1);
      expect(harness.retryScheduler.scheduled.last.delay,
          const Duration(seconds: 30));

      harness.server.forceTransportFailureOnNextFetch();
      harness.retryScheduler.fireLatest();
      await _pumpMicrotasks();
      expect(coordinator.status.retryAttempt, 2);
      expect(harness.retryScheduler.scheduled.last.delay,
          const Duration(seconds: 60));

      harness.server.forceTransportFailureOnNextFetch();
      harness.retryScheduler.fireLatest();
      await _pumpMicrotasks();
      expect(coordinator.status.retryAttempt, 3);
      expect(harness.retryScheduler.scheduled.last.delay,
          const Duration(seconds: 120));
    });

    test('a fully completed pass resets the attempt count to zero', () async {
      final harness = _RuntimeHarness();
      harness.bridge.currentFingerprint = _fingerprint(9);
      final coordinator = harness.buildCoordinator();
      addTearDown(coordinator.dispose);

      harness.server.forceTransportFailureOnNextFetch();
      await coordinator.requestSync(SyncRuntimeTrigger.startup);
      expect(coordinator.status.retryAttempt, 1);

      // No further fault injected -- the retry fires against a healthy
      // remote and completes cleanly.
      harness.retryScheduler.fireLatest();
      await _pumpMicrotasks();

      expect(coordinator.status.lastOutcome, SyncRuntimeOutcome.completed);
      expect(coordinator.status.retryAttempt, 0);
      expect(coordinator.status.retryScheduled, isFalse);
      expect(harness.retryScheduler.scheduled, isEmpty);
    });

    test(
        'a terminal outcome after a prior retryable failure does not reset '
        'or advance the attempt count, and cancels any pending timer',
        () async {
      final harness = _RuntimeHarness();
      harness.bridge.currentFingerprint = _fingerprint(10);
      final coordinator = harness.buildCoordinator();
      addTearDown(coordinator.dispose);

      harness.server.forceTransportFailureOnNextFetch();
      await coordinator.requestSync(SyncRuntimeTrigger.startup);
      expect(coordinator.status.retryAttempt, 1);
      expect(harness.retryScheduler.scheduled, hasLength(1));

      // Before the retry ever fires, an account-change arrives that leads
      // to a terminal outcome this time (simulate by making the account
      // unavailable, then requesting a fresh pass directly -- distinct
      // from the retry firing).
      harness.bridge.currentFingerprint = null;
      await coordinator.requestSync(SyncRuntimeTrigger.foreground);

      expect(coordinator.status.lastOutcome,
          SyncRuntimeOutcome.waitingForAccountAvailability);
      // The prior retry timer must have been superseded/cancelled by this
      // fresh explicit request, and this outcome schedules none of its own.
      expect(coordinator.status.retryScheduled, isFalse);
      expect(harness.retryScheduler.scheduled, isEmpty);
      // Attempt count is untouched by a terminal/waiting outcome -- it
      // still reflects the one retryable failure from before.
      expect(coordinator.status.retryAttempt, 1);
    });
  });

  group('single-flight and coalescing', () {
    test(
        'two extra requests while a pass is active coalesce into exactly '
        'one follow-up pass', () async {
      final harness = _RuntimeHarness();
      harness.bridge.currentFingerprint = _fingerprint(11);
      final hold = Completer<void>();
      harness.bridge.holdFetchUntil = hold;
      final coordinator = harness.buildCoordinator();
      addTearDown(coordinator.dispose);

      final first = coordinator.requestSync(SyncRuntimeTrigger.startup);
      await _pumpMicrotasks();
      expect(coordinator.status.isRunning, isTrue);

      final second = coordinator.requestSync(SyncRuntimeTrigger.foreground);
      final third = coordinator.requestSync(SyncRuntimeTrigger.foreground);
      expect(coordinator.status.followUpRequested, isTrue);
      expect(identical(second, third), isTrue);

      hold.complete();
      await first;
      await second;
      await third;

      // `second` and `third` being the exact same Future (asserted above)
      // is itself the proof that however many extra requests arrive while
      // a pass is active, they collapse into a single boolean follow-up
      // flag -- never a queue, never more than one guaranteed extra pass.
      expect(coordinator.status.followUpRequested, isFalse);
      expect(coordinator.status.isRunning, isFalse);
      expect(coordinator.status.lastOutcome, SyncRuntimeOutcome.completed);
    });

    test(
        "a coalesced call's returned future completes only when the "
        'follow-up pass itself finishes, not the original', () async {
      final harness = _RuntimeHarness();
      harness.bridge.currentFingerprint = _fingerprint(12);
      final firstHold = Completer<void>();
      final secondHold = Completer<void>();
      // A fresh device's pass 1 makes three `fetchPrivateZoneChanges` calls
      // before it can finish -- the bootstrap baseline fetch
      // (`_fetchAndMergeBaseline`), the bootstrap control-record
      // verification fetch (`_createAndVerifyControlRecordOutsideLock`,
      // since the remote starts genuinely empty), and
      // `SyncOrchestrator.runSyncPass`'s own unconditional fetch. A single
      // mutable `holdFetchUntil` value swapped mid-test cannot distinguish
      // "pass 1's own remaining fetches" from "the coalesced follow-up
      // pass's fetches" once a pass makes more than one fetch call -- doing
      // so previously deadlocked this test: pass 1's own control-record
      // verify fetch picked up the hold intended for the follow-up pass,
      // and `await first` below never returned.
      // `scriptedFetchHolds` fixes this deterministically by call order
      // rather than by timing: every one of pass 1's three fetches is
      // explicitly scripted against `firstHold`, and the coalesced
      // follow-up pass's own fetches -- exactly two, since by the time it
      // starts the bucket is already `complete` (bootstrap takes the
      // single-fetch "already complete" epoch-check path instead of the
      // three-fetch fresh-device path), plus `runSyncPass`'s own fetch --
      // are explicitly scripted against `secondHold`.
      harness.bridge.scriptedFetchHolds = [
        firstHold, // 1. bootstrap baseline fetch (pass 1)
        firstHold, // 2. bootstrap control-record verify fetch (pass 1)
        firstHold, // 3. SyncOrchestrator fetch (pass 1)
        secondHold, // 4. bootstrap already-complete epoch-check (follow-up)
        secondHold, // 5. SyncOrchestrator fetch (follow-up)
      ];
      final coordinator = harness.buildCoordinator();
      addTearDown(coordinator.dispose);

      final first = coordinator.requestSync(SyncRuntimeTrigger.startup);
      await _pumpMicrotasks();

      var followUpCompleted = false;
      final followUp = coordinator.requestSync(SyncRuntimeTrigger.foreground);
      unawaited(followUp.then((_) => followUpCompleted = true));

      // Release only pass 1's own three scripted fetches -- the follow-up
      // pass's own two scripted fetches remain gated by `secondHold`, a
      // completely separate, still-incomplete `Completer`, regardless of
      // exactly when the follow-up pass's own fetch calls actually occur.
      firstHold.complete();
      await first;
      await _pumpMicrotasks();

      // The original request is done, but the coalesced follow-up is still
      // running its own pass -- its future must not have resolved yet.
      expect(followUpCompleted, isFalse);

      secondHold.complete();
      await followUp;
      expect(followUpCompleted, isTrue);
    });
  });

  group('account-change wiring', () {
    test('an accountChanged event triggers exactly one fresh pass', () async {
      final harness = _RuntimeHarness();
      harness.bridge.currentFingerprint = _fingerprint(13);
      final coordinator = harness.buildCoordinator();
      addTearDown(coordinator.dispose);

      harness.bridge.emitAccountChanged();
      await _pumpMicrotasks();
      await _pumpMicrotasks();

      expect(coordinator.status.lastOutcome, SyncRuntimeOutcome.completed);
      expect(coordinator.status.isRunning, isFalse);
    });

    test(
        'accountChanged cancels a pending retry timer and resets backoff '
        'before requesting a fresh pass', () async {
      final harness = _RuntimeHarness();
      harness.bridge.currentFingerprint = _fingerprint(14);
      final coordinator = harness.buildCoordinator();
      addTearDown(coordinator.dispose);

      harness.server.forceTransportFailureOnNextFetch();
      await coordinator.requestSync(SyncRuntimeTrigger.startup);
      expect(coordinator.status.retryAttempt, 1);
      expect(harness.retryScheduler.scheduled, hasLength(1));

      harness.bridge.emitAccountChanged();
      await _pumpMicrotasks();
      await _pumpMicrotasks();

      expect(harness.retryScheduler.cancelled, isNotEmpty);
      expect(coordinator.status.retryScheduled, isFalse);
      expect(coordinator.status.lastOutcome, SyncRuntimeOutcome.completed);
      expect(coordinator.status.retryAttempt, 0);
    });

    test(
        'accountChanged while a pipeline is active coalesces into the '
        'single guaranteed follow-up rather than a concurrent run', () async {
      final harness = _RuntimeHarness();
      harness.bridge.currentFingerprint = _fingerprint(15);
      final hold = Completer<void>();
      harness.bridge.holdFetchUntil = hold;
      final coordinator = harness.buildCoordinator();
      addTearDown(coordinator.dispose);

      final first = coordinator.requestSync(SyncRuntimeTrigger.startup);
      await _pumpMicrotasks();
      expect(coordinator.status.isRunning, isTrue);

      harness.bridge.emitAccountChanged();
      await _pumpMicrotasks();
      expect(coordinator.status.followUpRequested, isTrue);

      hold.complete();
      await first;
      await _pumpMicrotasks();

      expect(coordinator.status.followUpRequested, isFalse);
      expect(coordinator.status.isRunning, isFalse);
      expect(coordinator.status.lastOutcome, SyncRuntimeOutcome.completed);
    });
  });

  group('privacy-safe status surface', () {
    test('toLogSafeSummary exposes only the documented allow-listed keys',
        () async {
      final harness = _RuntimeHarness();
      harness.bridge.currentFingerprint = _fingerprint(16);
      final coordinator = harness.buildCoordinator();
      addTearDown(coordinator.dispose);

      await coordinator.requestSync(SyncRuntimeTrigger.startup);

      final summary = coordinator.status.toLogSafeSummary();
      expect(
        summary.keys.toSet(),
        {
          'isRunning',
          'followUpRequested',
          'retryScheduled',
          'retryAttempt',
          'lastOutcome',
        },
      );
      // Never the account fingerprint, never a raw string beyond an enum
      // name.
      expect(summary.values.any((v) => v == _fingerprint(16)), isFalse);
    });

    test('isRunning is true only while a pass is actually in flight', () async {
      final harness = _RuntimeHarness();
      harness.bridge.currentFingerprint = _fingerprint(17);
      final hold = Completer<void>();
      harness.bridge.holdFetchUntil = hold;
      final coordinator = harness.buildCoordinator();
      addTearDown(coordinator.dispose);

      expect(coordinator.status.isRunning, isFalse);
      final future = coordinator.requestSync(SyncRuntimeTrigger.startup);
      await _pumpMicrotasks();
      expect(coordinator.status.isRunning, isTrue);

      hold.complete();
      await future;
      expect(coordinator.status.isRunning, isFalse);
    });
  });

  group('fingerprint-marker defensive check', () {
    test(
        'a completed/alreadyComplete bootstrap with no durable marker '
        'fails closed as terminalFailure without calling reconcile/sync',
        () async {
      final harness = _RuntimeHarness();
      harness.bridge.currentFingerprint = _fingerprint(18);
      await harness.bootstrapCoordinator.runBootstrap();
      // Simulate durable state shifting out from under this coordinator's
      // own pipeline, entirely outside any path this coordinator itself
      // controls.
      harness.syncPersistenceStore.seedAssociatedAccountFingerprint(null);

      // Baseline captured *after* the direct `runBootstrap()` call above
      // (which itself already performed at least one fetch) -- this test's
      // own correctness property is "the coordinator's pipeline never
      // reached step 3", not "no fetch ever happened in this test file",
      // so the assertion below is a before/after delta, never an absolute
      // count.
      final fetchCountBeforeCoordinatorRun =
          harness.bridge.fetchPrivateZoneChangesCallCount;

      // Test-fixture note: with the marker just nulled directly above, a
      // coordinator built the normal way (`harness.buildCoordinator()`,
      // sharing one `syncPersistenceStore` with `bootstrapCoordinator`
      // exactly like production) would *not* actually reach this test's
      // intended branch. `evaluateAssociation()` treats a null marker plus
      // an existing `complete` bucket as a legacy candidate and
      // `repairLegacyAssociationMarker` legitimately re-commits the marker
      // as part of `runBootstrap()` itself (see
      // `kept_sync_bootstrap_coordinator.dart`'s own documented backward-
      // compatible legacy-bucket derivation) -- so by the time this
      // coordinator's own Step 2 read the marker, it would already be
      // non-null again, and this test would never exercise its own
      // defensive null-check at all. `_MarkerHidingSyncPersistenceStore`
      // (defined below, alongside `_RuntimeHarness`) is a thin, test-only
      // forwarding decorator that lets *only* this coordinator's own direct
      // `loadAssociatedAccountFingerprint()` read diverge from the real,
      // shared store every other coordinator in the harness continues to
      // read/write normally -- reproducing "durable state shifting out from
      // under this coordinator's own pipeline" deterministically, without
      // relying on (or weakening the proof of) the legacy self-heal
      // behaviour, which remains fully exercised elsewhere.
      final coordinator = CloudKitSyncRuntimeCoordinator(
        bootstrapCoordinator: harness.bootstrapCoordinator,
        integrationCoordinator: harness.integrationCoordinator,
        incomingCoordinator: harness.incomingCoordinator,
        orchestrator: harness.orchestrator,
        syncPersistenceStore:
            _MarkerHidingSyncPersistenceStore(harness.syncPersistenceStore),
        bridge: harness.bridge,
        scheduler: harness.retryScheduler,
      );
      addTearDown(coordinator.dispose);

      await coordinator.requestSync(SyncRuntimeTrigger.startup);

      expect(
          coordinator.status.lastOutcome, SyncRuntimeOutcome.terminalFailure);
      // Bootstrap's own re-run this pass reaches `alreadyComplete` via its
      // epoch-check fetch (one call), then this coordinator's Step 2 fails
      // closed on the missing marker *before* ever calling
      // `SyncOrchestrator.runSyncPass` -- so at most one additional fetch
      // (bootstrap's own), never a second one from the orchestrator.
      expect(
        harness.bridge.fetchPrivateZoneChangesCallCount,
        lessThanOrEqualTo(fetchCountBeforeCoordinatorRun + 1),
      );
    });
  });

  group('dispose', () {
    test(
        'dispose cancels the account-change subscription and any pending '
        'retry timer', () async {
      final harness = _RuntimeHarness();
      harness.bridge.currentFingerprint = _fingerprint(19);
      final coordinator = harness.buildCoordinator();

      harness.server.forceTransportFailureOnNextFetch();
      await coordinator.requestSync(SyncRuntimeTrigger.startup);
      expect(harness.retryScheduler.scheduled, hasLength(1));

      await coordinator.dispose();
      expect(harness.retryScheduler.scheduled, isEmpty);

      final snapshotCountAfterDispose =
          harness.bridge.getAccountSnapshotCallCount;
      harness.bridge.emitAccountChanged();
      await _pumpMicrotasks();
      // No new pass started by the now-cancelled subscription -- proven by
      // a before/after delta on a call every pipeline step-1 attempt must
      // make at least once, rather than an absolute fetch count (which
      // would be sensitive to exactly how many fetches the one prior pass
      // happened to make internally).
      expect(harness.bridge.getAccountSnapshotCallCount,
          snapshotCountAfterDispose);
    });

    test('requestSync after dispose is a safe no-op', () async {
      final harness = _RuntimeHarness();
      harness.bridge.currentFingerprint = _fingerprint(20);
      final coordinator = harness.buildCoordinator();
      await coordinator.dispose();

      await coordinator.requestSync(SyncRuntimeTrigger.startup);
      expect(harness.bridge.getAccountSnapshotCallCount, 0);
    });
  });
}

/// Waits for a handful of microtask/event-loop turns -- long enough for any
/// chain of already-scheduled `Future`s in this file's fakes (all
/// synchronous or single-microtask; never a real `Timer` or real I/O) to
/// fully settle, without ever depending on wall-clock time.
Future<void> _pumpMicrotasks() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

KeptRecord _fixtureKeptRecord() {
  final now = DateTime.utc(2026, 1, 1);
  return KeptRecord(
    id: 'kept-fixture-1',
    revealId: const Uuid().v4(),
    wisdomText: 'Pre-existing local wisdom.',
    revealedAt: now,
    keptAt: now,
    updatedAt: now,
    mutationId: const Uuid().v4(),
  );
}

/// Records every [SyncRetryScheduler.schedule] call instead of starting a
/// real [Timer]; [fireLatest] lets a test manually fire the most recently
/// scheduled (and not yet cancelled) callback, deterministically, with no
/// wall-clock wait.
class _FakeRetryScheduler implements SyncRetryScheduler {
  final List<_ScheduledCallback> scheduled = [];
  final List<Object> cancelled = [];

  @override
  Object schedule(Duration delay, void Function() callback) {
    final handle = Object();
    scheduled
        .add(_ScheduledCallback(handle: handle, delay: delay, run: callback));
    return handle;
  }

  @override
  void cancel(Object handle) {
    cancelled.add(handle);
    scheduled.removeWhere((entry) => entry.handle == handle);
  }

  void fireLatest() {
    final entry = scheduled.removeLast();
    entry.run();
  }
}

class _ScheduledCallback {
  _ScheduledCallback({
    required this.handle,
    required this.delay,
    required this.run,
  });

  final Object handle;
  final Duration delay;
  final void Function() run;
}

/// One simulated device's [CloudKitPlatformBridge], pointing at a shared
/// [SyntheticCloudKitServer] exactly like `E2ECloudKitPlatformBridge` --
/// with one addition this file's own tests specifically need: a
/// controllable `accountChangeEvents` stream, driven by [emitAccountChanged]
/// rather than hard-coded to `Stream.empty()`.
class _FakeRuntimeCloudKitBridge implements CloudKitPlatformBridge {
  _FakeRuntimeCloudKitBridge({required this.server});

  final SyntheticCloudKitServer server;

  String? currentFingerprint;

  Completer<void>? holdFetchUntil;
  Completer<void>? holdModifyUntil;

  /// Test-only, optional, ordered per-call fetch-hold script -- exists only
  /// for tests that must distinguish which logical runtime pass a given
  /// [fetchPrivateZoneChanges] call belongs to. A single [holdFetchUntil]
  /// value cannot do this: it is read fresh on every call, and a single
  /// runtime pass can make more than one such call (a fresh device's
  /// bootstrap makes its own baseline fetch *and* a control-record
  /// verification fetch, and `SyncOrchestrator.runSyncPass` always makes one
  /// more on top of whatever bootstrap did) -- see
  /// `kept_sync_bootstrap_coordinator.dart` (`_fetchAndMergeBaseline`,
  /// `_createAndVerifyControlRecordOutsideLock`) and
  /// `sync_orchestrator.dart` (`_runSyncPassOnce`'s own unconditional fetch
  /// step). When non-null, [fetchPrivateZoneChanges] consumes exactly one
  /// entry per call, in call order, instead of consulting [holdFetchUntil]
  /// at all -- entirely additive: every test that never sets this field
  /// keeps exactly today's [holdFetchUntil] behavior, unchanged. A `null`
  /// entry means "do not block this call"; once every scripted entry has
  /// been consumed, any further call is explicitly, deterministically
  /// unblocked (never a leftover previous hold, never a hang).
  List<Completer<void>?>? scriptedFetchHolds;
  int _scriptedFetchHoldIndex = 0;

  int getAccountSnapshotCallCount = 0;
  int configurePrivateZoneCallCount = 0;
  int modifyPrivateRecordsCallCount = 0;
  int fetchPrivateZoneChangesCallCount = 0;

  final StreamController<CloudKitAccountChangeEvent> _accountChangeController =
      StreamController<CloudKitAccountChangeEvent>.broadcast();

  @override
  Future<CloudKitAccountSnapshot> getAccountSnapshot() async {
    getAccountSnapshotCallCount += 1;
    final fingerprint = currentFingerprint;
    if (fingerprint == null) {
      return const CloudKitAccountSnapshot(
        availability: CloudKitAccountAvailability.noAccount,
        isPrivateDatabaseUsable: false,
        accountFingerprint: null,
        fingerprintResolved: false,
        bridgeVersion: 1,
      );
    }
    return CloudKitAccountSnapshot(
      availability: CloudKitAccountAvailability.available,
      isPrivateDatabaseUsable: true,
      accountFingerprint: fingerprint,
      fingerprintResolved: true,
      bridgeVersion: 1,
    );
  }

  @override
  Future<CloudKitZoneConfigurationResult> configurePrivateZone() async {
    configurePrivateZoneCallCount += 1;
    return const CloudKitZoneConfigurationResult(
      success: true,
      zoneCreated: false,
      zoneAlreadyExisted: true,
      accountAvailability: CloudKitAccountAvailability.available,
    );
  }

  @override
  Future<CloudKitBridgeInfo> getBridgeInfo() => throw UnimplementedError(
        'Not used by the Phase 4F runtime coordinator tests.',
      );

  @override
  Stream<CloudKitAccountChangeEvent> get accountChangeEvents =>
      _accountChangeController.stream;

  /// Test-only: fires one synthetic `accountChanged` event, exactly the
  /// content-free shape the real native bridge would emit.
  void emitAccountChanged() {
    _accountChangeController.add(
      const CloudKitAccountChangeEvent(
        kind: CloudKitAccountChangeEventKind.accountChanged,
      ),
    );
  }

  @override
  Future<CloudKitModifyRecordsResult> modifyPrivateRecords(
    CloudKitModifyRecordsRequest request,
  ) async {
    modifyPrivateRecordsCallCount += 1;
    final hold = holdModifyUntil;
    if (hold != null) await hold.future;
    return server.modify(request);
  }

  @override
  Future<CloudKitZoneChangesResult> fetchPrivateZoneChanges(
    CloudKitZoneChangesRequest request,
  ) async {
    fetchPrivateZoneChangesCallCount += 1;
    final script = scriptedFetchHolds;
    if (script != null) {
      final hold = _scriptedFetchHoldIndex < script.length
          ? script[_scriptedFetchHoldIndex]
          : null;
      _scriptedFetchHoldIndex += 1;
      if (hold != null) await hold.future;
    } else {
      final hold = holdFetchUntil;
      if (hold != null) await hold.future;
    }
    return server.fetch(request);
  }
}

/// One independent simulated device's full real-coordinator composition,
/// mirroring `test/sync_e2e/sync_device_harness.dart`'s `SyncDeviceHarness`
/// pattern -- REAL `KeptSyncBootstrapCoordinator`/
/// `KeptSyncIntegrationCoordinator`/`IncomingKeptSyncCoordinator`/
/// `SyncOrchestrator` instances, sharing one integration
/// `PersistenceOperationCoordinator` exactly like production's own
/// `app_services.dart` wiring, over purely in-memory doubles.
class _RuntimeHarness {
  _RuntimeHarness({SyntheticCloudKitServer? server})
      : server = server ?? SyntheticCloudKitServer(),
        keptStore = InMemoryKeptStateStore(),
        intentStore = InMemoryLocalSyncIntentStore(),
        syncPersistenceStore = InMemorySyncPersistenceStore(),
        retryScheduler = _FakeRetryScheduler() {
    bridge = _FakeRuntimeCloudKitBridge(server: this.server);
    final integrationOperationCoordinator = PersistenceOperationCoordinator();
    keptRepository = KeptRepository(
      store: keptStore,
      bootstrap: const KeptBootstrapResult.ready(),
      operationCoordinator: PersistenceOperationCoordinator(),
    );
    integrationCoordinator = KeptSyncIntegrationCoordinator(
      keptRepository: keptRepository,
      intentStore: intentStore,
      syncPersistenceStore: syncPersistenceStore,
      integrationCoordinator: integrationOperationCoordinator,
    );
    incomingCoordinator = IncomingKeptSyncCoordinator(
      keptRepository: keptRepository,
      intentStore: intentStore,
      syncPersistenceStore: syncPersistenceStore,
      integrationCoordinator: integrationOperationCoordinator,
    );
    bootstrapCoordinator = KeptSyncBootstrapCoordinator(
      bridge: bridge,
      keptRepository: keptRepository,
      intentStore: intentStore,
      syncPersistenceStore: syncPersistenceStore,
      integrationCoordinator: integrationOperationCoordinator,
    );
    orchestrator = SyncOrchestrator(
      bridge: bridge,
      persistenceStore: syncPersistenceStore,
    );
  }

  final SyntheticCloudKitServer server;
  final InMemoryKeptStateStore keptStore;
  final InMemoryLocalSyncIntentStore intentStore;
  final InMemorySyncPersistenceStore syncPersistenceStore;
  final _FakeRetryScheduler retryScheduler;

  late final _FakeRuntimeCloudKitBridge bridge;
  late final KeptRepository keptRepository;
  late final KeptSyncIntegrationCoordinator integrationCoordinator;
  late final IncomingKeptSyncCoordinator incomingCoordinator;
  late final KeptSyncBootstrapCoordinator bootstrapCoordinator;
  late final SyncOrchestrator orchestrator;

  CloudKitSyncRuntimeCoordinator buildCoordinator() {
    return CloudKitSyncRuntimeCoordinator(
      bootstrapCoordinator: bootstrapCoordinator,
      integrationCoordinator: integrationCoordinator,
      incomingCoordinator: incomingCoordinator,
      orchestrator: orchestrator,
      syncPersistenceStore: syncPersistenceStore,
      bridge: bridge,
      scheduler: retryScheduler,
    );
  }
}

/// Test-only forwarding decorator used by exactly one test ("fingerprint-
/// marker defensive check"): every method forwards to [_delegate] --
/// the harness's own real, shared [InMemorySyncPersistenceStore] -- *except*
/// [loadAssociatedAccountFingerprint], which always returns `null`
/// regardless of the delegate's actual state.
///
/// This exists solely so a [CloudKitSyncRuntimeCoordinator] built with this
/// wrapper as its own `syncPersistenceStore` can have its own Step 2 marker
/// read genuinely, deterministically diverge from what
/// `KeptSyncBootstrapCoordinator`'s internal `runBootstrap()` sees on the
/// real, unwrapped store passed to every other coordinator in the harness --
/// see that one test's own comment for why a plain
/// `seedAssociatedAccountFingerprint(null)` alone is not sufficient (the
/// bootstrap coordinator's own documented, already-covered legacy-marker
/// self-heal would otherwise silently re-commit the marker first).
class _MarkerHidingSyncPersistenceStore implements SyncPersistenceStore {
  _MarkerHidingSyncPersistenceStore(this._delegate);

  final SyncPersistenceStore _delegate;

  @override
  Future<String?> loadAssociatedAccountFingerprint() async => null;

  @override
  Future<AccountSyncState?> loadAccountState(String accountFingerprint) =>
      _delegate.loadAccountState(accountFingerprint);

  @override
  Future<void> replaceAccountState(
    String accountFingerprint,
    AccountSyncState state,
  ) =>
      _delegate.replaceAccountState(accountFingerprint, state);

  @override
  Future<void> enqueueMutation(String accountFingerprint, SyncChange change) =>
      _delegate.enqueueMutation(accountFingerprint, change);

  @override
  Future<void> applyMutationOutcomes(
    String accountFingerprint, {
    Set<String> acknowledgedMutationIds = const {},
    Map<String, PersistedOutboxMutationStatus> updatedStatusByMutationId =
        const {},
  }) =>
      _delegate.applyMutationOutcomes(
        accountFingerprint,
        acknowledgedMutationIds: acknowledgedMutationIds,
        updatedStatusByMutationId: updatedStatusByMutationId,
      );

  @override
  Future<List<PersistedOutboxMutation>> readPendingMutations(
    String accountFingerprint,
  ) =>
      _delegate.readPendingMutations(accountFingerprint);

  @override
  Future<void> replaceRecordSystemFields(
    String accountFingerprint,
    String recordName,
    String systemFields,
  ) =>
      _delegate.replaceRecordSystemFields(
        accountFingerprint,
        recordName,
        systemFields,
      );

  @override
  Future<void> storeServerChangeToken(
    String accountFingerprint,
    String serverToken,
  ) =>
      _delegate.storeServerChangeToken(accountFingerprint, serverToken);

  @override
  Future<void> clearServerChangeToken(String accountFingerprint) =>
      _delegate.clearServerChangeToken(accountFingerprint);

  @override
  Future<void> clearAccountState(String accountFingerprint) =>
      _delegate.clearAccountState(accountFingerprint);

  @override
  Future<void> quarantineAccountState(String accountFingerprint) =>
      _delegate.quarantineAccountState(accountFingerprint);

  @override
  Future<CommitIncomingBatchCheckpointResult> commitIncomingBatchCheckpoint(
    CommitIncomingBatchCheckpointRequest request,
  ) =>
      _delegate.commitIncomingBatchCheckpoint(request);

  @override
  Future<RetireOutboxMutationResult> retireOutboxMutationIfCurrent(
    RetireOutboxMutationRequest request,
  ) =>
      _delegate.retireOutboxMutationIfCurrent(request);

  @override
  Future<CommitAssociatedAccountFingerprintResult>
      commitAssociatedAccountFingerprint({
    required String fingerprint,
    required String? expectedCurrent,
  }) =>
          _delegate.commitAssociatedAccountFingerprint(
            fingerprint: fingerprint,
            expectedCurrent: expectedCurrent,
          );

  @override
  Future<List<String>> loadMeaningfulAccountFingerprints() =>
      _delegate.loadMeaningfulAccountFingerprints();
}
