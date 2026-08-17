// Build 26: Sync Diagnostics / Safe Recovery core -- SyncRecoveryCoordinator.
// Exercises the coordinator's own decision logic in isolation, against a
// synthetic health snapshot supplied through `evaluateHealth` -- never a
// real SyncHealthEvaluator/CloudKitPlatformBridge/CloudKit call (that
// composition is exercised end-to-end in
// test/sync_diagnostics/sync_health_evaluator_test.dart instead).
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/sync_diagnostics/sync_health_snapshot.dart';
import 'package:wisdom_app/sync_diagnostics/sync_recovery_coordinator.dart';
import 'package:wisdom_app/sync_platform/cloud_kit_account_snapshot.dart';
import 'package:wisdom_app/sync_runtime/cloud_kit_sync_runtime_coordinator.dart';

const _emptyRuntimeStatus = CloudKitSyncRuntimeStatus(
  isRunning: false,
  followUpRequested: false,
  retryScheduled: false,
  retryAttempt: 0,
);

SyncHealthSnapshot _snapshotFor(SyncHealthState state) => SyncHealthSnapshot(
      state: state,
      syncEnabled: state != SyncHealthState.disabled,
      accountAvailability: CloudKitAccountAvailability.available,
      outboxPendingCount: 0,
      hasUnresolvedOutboxEntries: false,
      deletionRecoveryPending: false,
      runtimeStatus: _emptyRuntimeStatus,
    );

void main() {
  late SyncHealthState nextState;
  late int triggerCallCount;
  late SyncRecoveryCoordinator coordinator;

  setUp(() {
    nextState = SyncHealthState.healthy;
    triggerCallCount = 0;
    coordinator = SyncRecoveryCoordinator(
      evaluateHealth: () async => _snapshotFor(nextState),
      triggerRecoverySync: () async {
        triggerCallCount += 1;
      },
    );
  });

  test('healthy -> alreadyHealthy, resume is never triggered', () async {
    nextState = SyncHealthState.healthy;
    final result = await coordinator.attemptRecovery();
    expect(result.outcome, SyncRecoveryOutcome.alreadyHealthy);
    expect(triggerCallCount, 0);
  });

  test('disabled -> disabledNotApplicable, resume is never triggered',
      () async {
    nextState = SyncHealthState.disabled;
    final result = await coordinator.attemptRecovery();
    expect(result.outcome, SyncRecoveryOutcome.disabledNotApplicable);
    expect(triggerCallCount, 0);
  });

  test('recoveryRequired -> notSafeToAutoRecover, never a blind resume',
      () async {
    nextState = SyncHealthState.recoveryRequired;
    final result = await coordinator.attemptRecovery();
    expect(result.outcome, SyncRecoveryOutcome.notSafeToAutoRecover);
    expect(triggerCallCount, 0);
  });

  for (final recoverable in [
    SyncHealthState.pending,
    SyncHealthState.iCloudUnavailable,
    SyncHealthState.recovering,
    SyncHealthState.temporaryFailure,
  ]) {
    test('${recoverable.name} -> resumeTriggered, resume called exactly '
        'once', () async {
      nextState = recoverable;
      final result = await coordinator.attemptRecovery();
      expect(result.outcome, SyncRecoveryOutcome.resumeTriggered);
      expect(result.healthStateAtDecision, recoverable);
      expect(triggerCallCount, 1);
    });
  }

  test('12. repeated recovery invocation is idempotent -- each call '
      're-evaluates fresh and triggers the existing pipeline again, never '
      'more than once per call, and never throws', () async {
    nextState = SyncHealthState.pending;
    final first = await coordinator.attemptRecovery();
    final second = await coordinator.attemptRecovery();

    expect(first.outcome, SyncRecoveryOutcome.resumeTriggered);
    expect(second.outcome, SyncRecoveryOutcome.resumeTriggered);
    expect(triggerCallCount, 2);
  });

  test('a not-safe-to-recover state followed by a resolved healthy state '
      'never leaves a stale trigger call behind', () async {
    nextState = SyncHealthState.recoveryRequired;
    await coordinator.attemptRecovery();
    expect(triggerCallCount, 0);

    nextState = SyncHealthState.healthy;
    await coordinator.attemptRecovery();
    expect(triggerCallCount, 0);
  });

  test('toLogSafeSummary/toString expose only the outcome/state enum names',
      () async {
    nextState = SyncHealthState.pending;
    final result = await coordinator.attemptRecovery();
    final summary = result.toLogSafeSummary();
    expect(summary, {
      'outcome': 'resumeTriggered',
      'healthStateAtDecision': 'pending',
    });
    expect(result.toString(), contains('resumeTriggered'));
  });
}
