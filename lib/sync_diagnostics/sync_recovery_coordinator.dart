/// Build 26: Sync Diagnostics / Safe Recovery core -- the one narrowly-scoped
/// answer to "is there a non-destructive existing recovery path we should
/// resume/retry right now."
///
/// **Invents no recovery mechanism of its own.** [SyncRecoveryCoordinator
/// .attemptRecovery] never deletes local Kept/Reflection content, never
/// clears a tombstone, never resets a `dataEpoch`, never detaches an account
/// association outside its own existing protocol, and never chooses a
/// last-write-wins/text-based/date-based shortcut. Its only possible
/// side effect is [triggerRecoverySync] -- a caller-supplied callback that,
/// in production, is nothing more than a fresh call into the *exact same*
/// [CloudKitSyncRuntimeCoordinator.requestSync] every startup/foreground/
/// account-change/retry trigger already calls. This coordinator adds no new
/// mutation path: it only decides *whether* the existing, already-safe
/// pipeline should be nudged again, based on [SyncHealthEvaluator]'s own
/// read-only classification.
///
/// **Why a plain callback, never a direct [CloudKitSyncRuntimeCoordinator]
/// reference.** `test/sync_runtime/sync_runtime_layering_test.dart` already
/// proves `.requestSync(` is called from exactly three production files
/// (`lib/main.dart`, the coordinator's own retry/account-change internals,
/// and `lib/services/app_services.dart`). This file follows the exact same
/// shape `lib/controllers/sync_association_controller.dart`'s
/// `requestSyncAfterAssociation` and `lib/controllers/
/// icloud_removal_controller.dart`'s `requestSyncAfterRemoval` already
/// established: a plain, argument-free `Future<void> Function()`, composed
/// over the real coordinator only inside `app_services.dart`'s own bootstrap
/// closure -- so this file never imports `lib/sync_runtime/`'s coordinator
/// type for anything beyond [SyncHealthEvaluator]'s own already-approved
/// dependency on it, and never becomes a fourth `.requestSync(` call site.
///
/// **Safety properties, all inherited, none reimplemented.**
/// [CloudKitSyncRuntimeCoordinator.requestSync] is already documented as
/// idempotent, single-flight (at most one runtime pipeline ever active,
/// with any concurrent caller coalesced into one guaranteed follow-up
/// pass), safe to call after an app kill/relaunch (every decision it makes
/// is re-derived from durable state, never from anything this coordinator
/// remembers across calls), and safe to call repeatedly. This class itself
/// holds no mutable state of its own -- [attemptRecovery] never remembers a
/// prior call -- so every one of those properties carries through
/// unchanged; this file adds a decision, never a lock, a timer, or a queue.
library;

import 'sync_health_snapshot.dart';

/// The categorical, content-safe outcome of one [SyncRecoveryCoordinator
/// .attemptRecovery] call.
enum SyncRecoveryOutcome {
  /// [SyncHealthEvaluator.evaluate] reported [SyncHealthState.healthy] --
  /// nothing to resume. [SyncRecoveryCoordinator.triggerRecoverySync] was
  /// never called.
  alreadyHealthy,

  /// The user has not enabled iCloud Sync ([SyncHealthState.disabled]) --
  /// there is no existing sync/recovery pipeline for this coordinator to
  /// resume. Enabling sync remains Settings' own explicit, one-time
  /// decision (`lib/controllers/sync_association_controller.dart`); never
  /// performed here. [SyncRecoveryCoordinator.triggerRecoverySync] was never
  /// called.
  disabledNotApplicable,

  /// [SyncHealthEvaluator.evaluate] reported [SyncHealthState
  /// .recoveryRequired] -- the detected condition requires either a real
  /// external state change (e.g. the user reassociating a changed iCloud
  /// account) or a decision this coordinator cannot safely make
  /// automatically (e.g. an outbox mutation already permanently failed or
  /// conflicted). Reported honestly, with zero mutation attempted, rather
  /// than guessing at a destructive repair -- see the library doc comment's
  /// "invents no recovery mechanism of its own" section.
  /// [SyncRecoveryCoordinator.triggerRecoverySync] was never called.
  notSafeToAutoRecover,

  /// The detected state ([SyncHealthState.pending], [SyncHealthState
  /// .iCloudUnavailable], [SyncHealthState.recovering], or [SyncHealthState
  /// .temporaryFailure]) is one the existing sync/recovery pipeline can
  /// safely resume on its own -- [SyncRecoveryCoordinator
  /// .triggerRecoverySync] was called exactly once.
  resumeTriggered,
}

/// A privacy-safe, immutable result of one [SyncRecoveryCoordinator
/// .attemptRecovery] call.
final class SyncRecoveryResult {
  const SyncRecoveryResult({
    required this.outcome,
    required this.healthStateAtDecision,
  });

  final SyncRecoveryOutcome outcome;

  /// The exact [SyncHealthState] [attemptRecovery] observed at the moment it
  /// decided [outcome] -- never re-evaluated afterward by this result
  /// itself.
  final SyncHealthState healthStateAtDecision;

  Map<String, Object?> toLogSafeSummary() => {
        'outcome': outcome.name,
        'healthStateAtDecision': healthStateAtDecision.name,
      };

  @override
  String toString() => 'SyncRecoveryResult(${toLogSafeSummary()})';
}

/// See the library doc comment for the full contract.
final class SyncRecoveryCoordinator {
  const SyncRecoveryCoordinator({
    required Future<SyncHealthSnapshot> Function() evaluateHealth,
    required Future<void> Function() triggerRecoverySync,
  })  : _evaluateHealth = evaluateHealth,
        _triggerRecoverySync = triggerRecoverySync;

  /// A plain, injectable read of `SyncHealthEvaluator.evaluate` -- never the
  /// evaluator instance itself. `SyncHealthEvaluator` is a `final class`
  /// (deliberately unextendable/unimplementable outside its own library,
  /// mirroring `lib/sync_runtime/`'s own design), so this narrow function
  /// seam is what lets this coordinator's own decision logic be exercised
  /// against a fully controlled, synthetic [SyncHealthSnapshot] in tests,
  /// independent of `SyncHealthEvaluator`'s own precedence tests. Production
  /// wiring (`lib/services/app_services.dart`) simply passes
  /// `syncHealthEvaluator.evaluate`.
  final Future<SyncHealthSnapshot> Function() _evaluateHealth;
  final Future<void> Function() _triggerRecoverySync;

  /// Evaluates current sync health, then either does nothing (already
  /// healthy, disabled, or a state this coordinator refuses to auto-recover)
  /// or calls [triggerRecoverySync] exactly once. Never throws for an
  /// ordinary business-rule outcome -- see [SyncRecoveryOutcome]. Safe to
  /// call as often as a caller likes, including back-to-back or immediately
  /// after a prior call's [triggerRecoverySync] is still in flight: the
  /// underlying pipeline's own single-flight/coalescing guarantee (see the
  /// library doc comment) makes a second concurrent call a safe, cheap
  /// follow-up, never a second competing pass.
  Future<SyncRecoveryResult> attemptRecovery() async {
    final snapshot = await _evaluateHealth();
    switch (snapshot.state) {
      case SyncHealthState.healthy:
        return SyncRecoveryResult(
          outcome: SyncRecoveryOutcome.alreadyHealthy,
          healthStateAtDecision: snapshot.state,
        );
      case SyncHealthState.disabled:
        return SyncRecoveryResult(
          outcome: SyncRecoveryOutcome.disabledNotApplicable,
          healthStateAtDecision: snapshot.state,
        );
      case SyncHealthState.recoveryRequired:
        return SyncRecoveryResult(
          outcome: SyncRecoveryOutcome.notSafeToAutoRecover,
          healthStateAtDecision: snapshot.state,
        );
      case SyncHealthState.pending:
      case SyncHealthState.iCloudUnavailable:
      case SyncHealthState.recovering:
      case SyncHealthState.temporaryFailure:
        await _triggerRecoverySync();
        return SyncRecoveryResult(
          outcome: SyncRecoveryOutcome.resumeTriggered,
          healthStateAtDecision: snapshot.state,
        );
    }
  }
}
