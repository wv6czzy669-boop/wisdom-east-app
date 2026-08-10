/// Build 26 Phase 4G (renamed post-Mac-validation, same phase): the smallest
/// safe app-facing surface for the explicit, one-time iCloud association
/// decision Settings needs.
///
/// Named [SyncAssociationController] -- deliberately platform-neutral --
/// rather than after the underlying transport, so `lib/screens/
/// settings_screen.dart` can depend on this file without ever containing the
/// substring "CloudKit" anywhere in its own source (see
/// `test/sync_platform/cloud_kit_platform_privacy_test.dart`'s screen/widget/
/// service/repository privacy guard). Settings knows only about generic
/// "iCloud Sync" product state and actions; this file is where that neutral
/// surface is composed over the real, CloudKit-aware bootstrap coordinator.
///
/// Wraps the existing, already-audited
/// [KeptSyncBootstrapCoordinator.evaluateAssociation]/
/// [KeptSyncBootstrapCoordinator.authorizeAssociation] pair -- this file
/// never reimplements any part of the association decision itself, never
/// constructs CloudKit transport, and never exposes a fingerprint, account
/// identifier, or CloudKit record name to its caller
/// ([SyncAssociationCheckResult]/[SyncAssociationEnableOutcome] are both
/// content-free by construction: an enum and a boolean, nothing more).
///
/// [SyncAssociationController] is deliberately unaware of
/// `CloudKitSyncRuntimeCoordinator`/`SyncRuntimeTrigger`:
/// [requestSyncAfterAssociation] is a plain, argument-free callback --
/// exactly the same shape `KeptSyncIntegrationCoordinator
/// .onMutationCommitted` already uses for the local-mutation nudge -- so
/// this file never imports `lib/sync_runtime/` and never calls
/// `CloudKitSyncRuntimeCoordinator.requestSync` directly. Production wiring
/// (`lib/services/app_services.dart`) supplies a closure that calls
/// `cloudKitSyncRuntimeCoordinator.requestSync(SyncRuntimeTrigger
/// .explicitAssociation)`; see
/// `test/sync_runtime/sync_runtime_layering_test.dart`'s own structural
/// proof that `requestSync` is only ever called from three disclosed
/// production files, none of which is this one.
///
/// This is also the one, exact, narrowly-approved production caller of
/// [KeptSyncBootstrapCoordinator.evaluateAssociation]/
/// [KeptSyncBootstrapCoordinator.authorizeAssociation] outside those methods'
/// own definition file -- see
/// `test/sync_integration/sync_integration_layering_test.dart`'s exact,
/// two-file allowlist for both call patterns. It never calls
/// `repairLegacyAssociationMarker` or `runBootstrap`, both of which remain
/// restricted to their own existing, narrower allowances.
library;

import '../sync_integration/kept_sync_bootstrap_coordinator.dart';

/// Settings-facing association state. Never distinguishes *why* iCloud Sync
/// is not enabled (account unavailable, ambiguous legacy state, and so on)
/// -- only whether it is, and whether this screen may prompt for it right
/// now. See [SyncAssociationCheckResult.requiresExplicitConsent].
enum SyncAssociationDisplayStatus {
  /// Explicit association has already been authorized (durably, by this
  /// device, for the currently-resolved iCloud account) -- whether that
  /// happened just now or before this screen was ever opened.
  enabled,

  /// Not yet authorized. May or may not be actionable right now -- see
  /// [SyncAssociationCheckResult.requiresExplicitConsent].
  notEnabled,
}

/// Content-free by construction: an enum and a boolean, never a
/// fingerprint, account identifier, or CloudKit status detail.
final class SyncAssociationCheckResult {
  const SyncAssociationCheckResult({
    required this.displayStatus,
    required this.requiresExplicitConsent,
  });

  final SyncAssociationDisplayStatus displayStatus;

  /// `true` only when tapping the Settings row should show the "Enable
  /// iCloud Sync?" confirmation sheet -- i.e. exactly when
  /// [KeptSyncBootstrapCoordinator.evaluateAssociation] freshly reported
  /// [AssociationEvaluationStatus.associationRequired]. Every other status
  /// (already associated, a transient account-availability state, or a
  /// state [KeptSyncBootstrapCoordinator.runBootstrap] already resolves
  /// automatically with no user decision) is `false` -- this screen must
  /// never show an unnecessary authorization prompt.
  final bool requiresExplicitConsent;
}

/// The categorical, content-safe outcome of one [SyncAssociationController
/// .enableSync] call.
enum SyncAssociationEnableOutcome {
  /// The association marker is now durably set for the currently-resolved
  /// account -- whether this call itself just wrote it, or it was already
  /// present and matching (an idempotent no-op repeat).
  success,

  /// Nothing to do -- association was not actually pending when this call
  /// ran (already resolved by something else, or a state this method
  /// cannot resolve, e.g. the account is temporarily unavailable). Never
  /// surfaced to the user as a failure.
  notApplicable,

  /// Authorization did not succeed -- a generic, content-free outcome. The
  /// UI shows one fixed, retry-eligible message; never a CloudKit/account
  /// identifier or the underlying [AssociationAuthorizationStatus].
  failed,
}

/// See the library doc comment for the full contract.
final class SyncAssociationController {
  SyncAssociationController({
    required KeptSyncBootstrapCoordinator bootstrapCoordinator,
    required void Function() requestSyncAfterAssociation,
  })  : _bootstrapCoordinator = bootstrapCoordinator,
        _requestSyncAfterAssociation = requestSyncAfterAssociation;

  final KeptSyncBootstrapCoordinator _bootstrapCoordinator;
  final void Function() _requestSyncAfterAssociation;

  /// Read-only -- performs no write of any kind (see
  /// [KeptSyncBootstrapCoordinator.evaluateAssociation]'s own doc comment).
  /// Safe to call as often as Settings needs (every time the screen opens,
  /// for instance) to reflect the live association state -- never cached
  /// here, so an iCloud account change or an association completed via any
  /// other path is always reflected on the very next call (requirement 8:
  /// account-change safety is never weakened by this controller).
  Future<SyncAssociationCheckResult> checkStatus() async {
    final AssociationEvaluation evaluation;
    try {
      evaluation = await _bootstrapCoordinator.evaluateAssociation();
    } catch (_) {
      return const SyncAssociationCheckResult(
        displayStatus: SyncAssociationDisplayStatus.notEnabled,
        requiresExplicitConsent: false,
      );
    }
    return _toCheckResult(evaluation.status);
  }

  SyncAssociationCheckResult _toCheckResult(
    AssociationEvaluationStatus status,
  ) {
    switch (status) {
      case AssociationEvaluationStatus.resumeAssociation:
        return const SyncAssociationCheckResult(
          displayStatus: SyncAssociationDisplayStatus.enabled,
          requiresExplicitConsent: false,
        );
      case AssociationEvaluationStatus.associationRequired:
        return const SyncAssociationCheckResult(
          displayStatus: SyncAssociationDisplayStatus.notEnabled,
          requiresExplicitConsent: true,
        );
      case AssociationEvaluationStatus.autoAssociable:
      case AssociationEvaluationStatus.unresolvedLegacyAssociation:
      case AssociationEvaluationStatus.ambiguousLegacyState:
      case AssociationEvaluationStatus.accountUnavailable:
      case AssociationEvaluationStatus.fingerprintUnresolved:
        // None of these require, or even permit, an explicit consent
        // prompt from this screen: `autoAssociable`/
        // `unresolvedLegacyAssociation` are already resolved automatically
        // by `KeptSyncBootstrapCoordinator.runBootstrap` itself on the next
        // ordinary sync trigger (see its own doc comment), and the
        // remaining three are transient account-availability/fail-closed
        // states, not a pending decision this screen can make.
        return const SyncAssociationCheckResult(
          displayStatus: SyncAssociationDisplayStatus.notEnabled,
          requiresExplicitConsent: false,
        );
    }
  }

  /// Must only be called after the user has explicitly confirmed the
  /// "Enable iCloud Sync?" prompt. Idempotent: re-evaluates association
  /// fresh immediately before ever authorizing, so a second call -- a
  /// genuine repeated tap, a relaunch replay, or a call that arrives after
  /// association was already resolved by some other path -- never
  /// re-authorizes, never creates a duplicate marker, and never touches any
  /// Kept/Reflection data, dataEpoch, or outbox content.
  /// [KeptSyncBootstrapCoordinator.authorizeAssociation] itself performs
  /// only the one durable association-marker write and nothing else (see
  /// its own doc comment) -- this method never duplicates any part of that
  /// logic.
  Future<SyncAssociationEnableOutcome> enableSync() async {
    final AssociationEvaluation evaluation;
    try {
      evaluation = await _bootstrapCoordinator.evaluateAssociation();
    } catch (_) {
      return SyncAssociationEnableOutcome.failed;
    }

    if (evaluation.status != AssociationEvaluationStatus.associationRequired) {
      // Nothing left to authorize -- either already associated, or a state
      // no explicit consent tap can resolve right now. Never reported as a
      // failure.
      return SyncAssociationEnableOutcome.notApplicable;
    }

    final fingerprint = evaluation.currentFingerprint;
    if (fingerprint == null) {
      return SyncAssociationEnableOutcome.failed;
    }

    final AssociationAuthorizationResult result;
    try {
      result = await _bootstrapCoordinator.authorizeAssociation(
        fingerprint: fingerprint,
      );
    } catch (_) {
      return SyncAssociationEnableOutcome.failed;
    }

    if (!result.isAuthorized) {
      // `accountMismatch`/`differentAssociationExists`/`invalidFingerprint`
      // -- never silently retried with a different fingerprint, and never
      // overwrites an existing, different association (requirement 8).
      return SyncAssociationEnableOutcome.failed;
    }

    _requestSyncAfterAssociation();
    return SyncAssociationEnableOutcome.success;
  }
}
