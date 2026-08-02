import 'cloud_kept_wisdom_projection.dart';
import 'data_epoch.dart';

/// Build 26 Phase 4A: why [resolveKeptWisdomConflict] picked the winner it
/// did (or declined to pick one). See
/// `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md` §4.
enum ConflictReason {
  /// Exactly one side's `dataEpoch` matched the authoritative epoch; that
  /// side won outright, regardless of `updatedAt`.
  epochSupersedes,

  /// Neither side's `dataEpoch` matched the authoritative epoch —
  /// resolution fails closed rather than guessing (design doc §4.1, step 1).
  bothEpochsStale,

  /// Both sides matched the authoritative epoch; the side with the newer
  /// `updatedAt` won.
  newerUpdatedAt,

  /// `updatedAt` was equal on both sides, and exactly one side is a
  /// tombstone; the tombstone won.
  tombstoneWinsOnTie,

  /// `updatedAt` was equal and both sides have the same active/deleted
  /// state; the lexicographically greater `mutationId` won.
  mutationIdTiebreak,

  /// Both sides are field-for-field identical — no real conflict existed.
  identical,

  /// Both sides claim to be the active form of the same `recordName` but
  /// disagree on an immutable identity field (`revealId`, `wisdomText`,
  /// `revealedAt`, or `keptAt`) — this indicates corruption or tampering,
  /// never a legitimate conflict. Resolution fails closed.
  immutableFieldMismatch,
}

/// The result of [resolveKeptWisdomConflict]. [winner] is `null` exactly
/// when [reason] is [ConflictReason.bothEpochsStale] or
/// [ConflictReason.immutableFieldMismatch] — both are deliberate refusals
/// to guess, not omissions.
final class ConflictOutcome {
  const ConflictOutcome._({required this.reason, this.winner});

  final ConflictReason reason;
  final CloudKeptWisdomProjection? winner;

  /// `true` when resolution deliberately produced no winner — the caller
  /// must not apply either side and must instead re-fetch/reconcile before
  /// retrying (design doc §4.1).
  bool get isRejected => winner == null;
}

/// The pure, deterministic conflict-resolution policy for two
/// [CloudKeptWisdomProjection] candidates that both claim to represent the
/// *same* saved reveal occurrence (`local.recordName == remote.recordName`
/// is required — this is a precondition, not something this function
/// resolves).
///
/// Implements exactly the precedence order in
/// `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md` §4.1:
///
/// 1. `dataEpoch` vs. [authoritativeEpoch] — whichever side matches wins
///    outright; if neither matches, resolution is rejected; if both match,
///    continue.
/// 2. Newer `updatedAt` (millisecond precision) wins.
/// 3. Equal `updatedAt`, one side a tombstone: the tombstone wins.
/// 4. Equal `updatedAt`, same active/deleted state on both sides: the
///    lexicographically greater `mutationId` wins.
///
/// `keptAt` and `revealedAt` are never inputs to this function at all —
/// structurally impossible to influence the outcome, per the design doc's
/// own requirement.
///
/// Throws [ArgumentError] if [local] and [remote] do not share a
/// `recordName` — this function resolves a conflict between two versions of
/// the same record, never a comparison between two different occurrences.
ConflictOutcome resolveKeptWisdomConflict({
  required CloudKeptWisdomProjection local,
  required CloudKeptWisdomProjection remote,
  required DataEpoch authoritativeEpoch,
}) {
  if (local.recordName != remote.recordName) {
    throw ArgumentError(
      'resolveKeptWisdomConflict requires local and remote to share a '
      'recordName (same occurrence); got "${local.recordName}" vs '
      '"${remote.recordName}".',
    );
  }

  if (!local.isTombstone && !remote.isTombstone) {
    final identityMismatch = local.revealId != remote.revealId ||
        local.wisdomText != remote.wisdomText ||
        local.revealedAtMs != remote.revealedAtMs ||
        local.keptAtMs != remote.keptAtMs;
    if (identityMismatch) {
      return const ConflictOutcome._(
        reason: ConflictReason.immutableFieldMismatch,
      );
    }
  }

  final localMatchesEpoch = local.dataEpoch == authoritativeEpoch;
  final remoteMatchesEpoch = remote.dataEpoch == authoritativeEpoch;

  if (localMatchesEpoch && !remoteMatchesEpoch) {
    return ConflictOutcome._(
      reason: ConflictReason.epochSupersedes,
      winner: local,
    );
  }
  if (remoteMatchesEpoch && !localMatchesEpoch) {
    return ConflictOutcome._(
      reason: ConflictReason.epochSupersedes,
      winner: remote,
    );
  }
  if (!localMatchesEpoch && !remoteMatchesEpoch) {
    return const ConflictOutcome._(reason: ConflictReason.bothEpochsStale);
  }

  // Both sides belong to the authoritative epoch.
  if (local.updatedAtMs != remote.updatedAtMs) {
    final newer = local.updatedAtMs > remote.updatedAtMs ? local : remote;
    return ConflictOutcome._(
      reason: ConflictReason.newerUpdatedAt,
      winner: newer,
    );
  }

  // Equal updatedAt.
  if (local.isTombstone != remote.isTombstone) {
    final tombstoneSide = local.isTombstone ? local : remote;
    return ConflictOutcome._(
      reason: ConflictReason.tombstoneWinsOnTie,
      winner: tombstoneSide,
    );
  }

  // Equal updatedAt, same active/deleted state.
  if (local == remote) {
    return ConflictOutcome._(reason: ConflictReason.identical, winner: local);
  }

  final winner =
      local.mutationId.compareTo(remote.mutationId) > 0 ? local : remote;
  return ConflictOutcome._(
    reason: ConflictReason.mutationIdTiebreak,
    winner: winner,
  );
}
