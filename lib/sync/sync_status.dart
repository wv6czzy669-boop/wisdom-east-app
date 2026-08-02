/// Build 26 Phase 4A: pure sync-domain status/state models. See
/// `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md` §5 (account-boundary
/// behavior) and §7 (native bridge contract — "report sync state").
library;

/// Mirrors the platform's own `CKAccountStatus`, plus an explicit
/// "could not determine" case that is never silently coerced to
/// [available] — an account-status query that fails must be reported as
/// unknown, not treated as if it had succeeded.
enum CloudAccountStatus {
  available,
  noAccount,
  restricted,
  temporarilyUnavailable,
  couldNotDetermine,
}

/// The sync engine's own current phase — never derived from, or conflated
/// with, [CloudAccountStatus] directly (an engine can be [idle] while the
/// account is fully [CloudAccountStatus.available], simply because nothing
/// has triggered a sync cycle yet).
enum SyncPhase {
  /// No sync cycle is running and none is queued.
  idle,

  /// No iCloud account is available (see
  /// `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md` §5).
  accountUnavailable,

  /// iCloud is restricted (e.g. parental controls, MDM policy).
  accountRestricted,

  /// The iCloud account changed and sync is paused pending explicit user
  /// confirmation — see the design doc §5. Never resumes automatically.
  pausedForAccountChange,

  /// A sync cycle is actively running.
  syncing,

  /// The most recent sync attempt failed. See [SyncEngineStatus.message]
  /// for a content-free description; the underlying error's retry
  /// classification is a separate concern (`sync_error_classification.dart`).
  error,
}

/// A snapshot of the sync engine's current state, safe to log or display
/// directly — [message], when present, must never contain wisdom text,
/// Reflection text, or any other user content (see
/// `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md` §7's privacy rules).
final class SyncEngineStatus {
  const SyncEngineStatus({
    required this.phase,
    this.message,
    this.lastSuccessfulSyncAt,
  });

  final SyncPhase phase;

  /// A short, content-free, human-readable description (e.g. "Waiting for
  /// network" or "Sync error: server unavailable") — never built by
  /// string-interpolating record content.
  final String? message;

  /// UTC instant of the last successful sync cycle, if any.
  final DateTime? lastSuccessfulSyncAt;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SyncEngineStatus &&
        other.phase == phase &&
        other.message == message &&
        (other.lastSuccessfulSyncAt == null && lastSuccessfulSyncAt == null ||
            (other.lastSuccessfulSyncAt != null &&
                lastSuccessfulSyncAt != null &&
                other.lastSuccessfulSyncAt!
                    .isAtSameMomentAs(lastSuccessfulSyncAt!)));
  }

  @override
  int get hashCode => Object.hash(
        phase,
        message,
        lastSuccessfulSyncAt?.millisecondsSinceEpoch,
      );
}

/// Reported when the platform detects the signed-in iCloud account has
/// changed. Carries only opaque, per-account scope tokens (see the design
/// doc §5) — never a raw iCloud account identifier, and never sent to
/// analytics.
final class AccountChangeEvent {
  const AccountChangeEvent({
    required this.previousAccountToken,
    required this.newAccountToken,
    required this.requiresUserConfirmation,
  });

  /// Opaque token identifying the previously-active account, or `null` if
  /// no account was previously associated (e.g. first-ever sign-in).
  final String? previousAccountToken;

  /// Opaque token identifying the newly-detected account, or `null` if the
  /// account became unavailable rather than changing to a different one.
  final String? newAccountToken;

  /// Always `true` for a genuine account-identity change (design doc §5) —
  /// modeled explicitly, rather than assumed, so a caller can never
  /// mistakenly treat an unconfirmed change as already safe to reconcile.
  final bool requiresUserConfirmation;
}
