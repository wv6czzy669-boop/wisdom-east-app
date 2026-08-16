/// Build 26 Phase 5 (slice 1): the durable local state machine for the
/// approved "Remove from iCloud" deletion transaction.
///
/// **Scope of this slice.** This file defines and durably persists the
/// transaction's *shape* and *stage machine* only. It performs no CloudKit
/// operation of any kind, no `CKKeptWisdom` deletion, no `CKEastSyncState`
/// mutation, and no local Kept/Reflection mutation -- see
/// `SyncPersistenceStore.beginDeletionTransaction`/
/// `advanceDeletionTransactionStage`/`clearDeletionTransaction`'s own doc
/// comments (`sync_persistence_store.dart`) for the exact guarantees the
/// persistence layer built on top of this shape provides. A future Phase 5
/// slice implements the actual runner that drives a transaction through
/// these stages against real CloudKit.
///
/// **Identity binding.** [accountFingerprint] is fixed for the lifetime of a
/// transaction -- there is no `copyWith`-style path that can change it. A
/// transaction always targets exactly the account it was created for; see
/// `SyncPersistenceStore.beginDeletionTransaction`'s own doc comment for the
/// account-mismatch fail-closed rule this exists to support (a deletion
/// transaction must never silently retarget itself to a different iCloud
/// account).
///
/// **Epoch generation-once.** [replacementDataEpoch] is generated exactly
/// once, by `SyncPersistenceStore.beginDeletionTransaction`, using the same
/// `DataEpoch.generate()` factory every other epoch-creating call site in
/// this codebase already uses -- never re-derived, never regenerated on a
/// crash/retry/resume (a resumed transaction's [replacementDataEpoch] is
/// read back unchanged from durable storage; see
/// `BeginDeletionTransactionStatus.resumedExisting`). [originalDataEpoch] is
/// `null` only when no `AccountSyncState` bucket existed yet for this
/// account at the moment the transaction began (nothing to purge under an
/// old epoch in that case); when non-null, it is that bucket's own
/// `dataEpoch` at that exact moment, captured once and never refreshed.
///
/// **Privacy.** [toLogSafeSummary]/[toString] expose only [stage] -- never
/// [accountFingerprint], [originalDataEpoch], or [replacementDataEpoch].
library;

import '../sync/data_epoch.dart';
import 'sync_persistence_envelope.dart' show looksLikeAccountFingerprint;

/// Thrown by [PendingDeletionTransaction]'s constructor when the given
/// fields would violate one of this type's structural invariants. Never
/// thrown by [PendingDeletionTransaction.tryDecode], which reports the same
/// class of problem by returning `null` instead -- this codebase's
/// established fail-closed `tryDecode` convention (mirrors
/// `AccountSyncStateFormatException`).
class PendingDeletionTransactionFormatException implements Exception {
  const PendingDeletionTransactionFormatException(this.message);

  final String message;

  @override
  String toString() => 'PendingDeletionTransactionFormatException: $message';
}

/// The durable stages a "Remove from iCloud" deletion transaction passes
/// through, in order. See [isValidDeletionTransactionTransition] for the
/// exhaustive, single-choke-point allowlist of legal transitions between
/// them -- no call site may invent a transition ad hoc.
///
/// There is no persisted terminal `complete` value: once every stage below
/// has been durably driven to completion by a future runner, the whole
/// transaction is removed via `SyncPersistenceStore.clearDeletionTransaction`
/// rather than persisted forever in a finished state -- mirroring this
/// codebase's existing precedent of representing "nothing to do" as absence
/// (a `null` bucket, an empty outbox) rather than an explicit terminal enum
/// value, wherever a future reader only ever needs to know "is one currently
/// in progress."
enum DeletionTransactionStage {
  /// The transaction has been durably created: its target account
  /// association, [PendingDeletionTransaction.originalDataEpoch] (if any),
  /// and freshly-generated [PendingDeletionTransaction.replacementDataEpoch]
  /// are all fixed and durable. No CloudKit or local mutation has happened
  /// yet.
  prepared,

  /// A future runner is establishing (or has established) the fresh
  /// `CKEastSyncState.dataEpoch` barrier remotely, using
  /// [PendingDeletionTransaction.replacementDataEpoch] -- out of this
  /// slice's scope.
  epochBarrierPending,

  /// A future runner is purging (or has purged) every `CKKeptWisdom` record
  /// under the old epoch from the user's private CloudKit database -- out of
  /// this slice's scope.
  cloudPurgePending,

  /// A future runner is confirming (or has confirmed) zero `CKKeptWisdom`
  /// records remain remotely -- out of this slice's scope.
  verificationPending,

  /// A future runner is detaching (or has detached) this device's old sync
  /// association/local sync state, while leaving local Kept/Reflection
  /// content untouched -- out of this slice's scope. The whole transaction
  /// is removed (see this enum's own doc comment) once this stage is itself
  /// durably complete.
  localFinalizePending,
}

/// The explicit, exhaustive allowlist of valid [DeletionTransactionStage]
/// transitions -- deliberately a single choke point, mirroring
/// `isValidBootstrapTransition`'s identical precedent in
/// `account_sync_state.dart`. `from == to` (a no-op re-assertion of the
/// current stage) is always valid, so retrying an identical stage-advance
/// request stays idempotent.
bool isValidDeletionTransactionTransition(
  DeletionTransactionStage from,
  DeletionTransactionStage to,
) {
  if (from == to) return true;

  const forwardChain = {
    DeletionTransactionStage.prepared:
        DeletionTransactionStage.epochBarrierPending,
    DeletionTransactionStage.epochBarrierPending:
        DeletionTransactionStage.cloudPurgePending,
    DeletionTransactionStage.cloudPurgePending:
        DeletionTransactionStage.verificationPending,
    DeletionTransactionStage.verificationPending:
        DeletionTransactionStage.localFinalizePending,
  };
  return forwardChain[from] == to;
}

/// One durable "Remove from iCloud" deletion transaction. See the library
/// doc comment for the full contract.
final class PendingDeletionTransaction {
  factory PendingDeletionTransaction({
    required String accountFingerprint,
    required DataEpoch? originalDataEpoch,
    required DataEpoch replacementDataEpoch,
    required DeletionTransactionStage stage,
  }) {
    if (!looksLikeAccountFingerprint(accountFingerprint)) {
      throw const PendingDeletionTransactionFormatException(
        'accountFingerprint does not look like an opaque account '
        'fingerprint.',
      );
    }
    if (originalDataEpoch != null &&
        originalDataEpoch == replacementDataEpoch) {
      throw const PendingDeletionTransactionFormatException(
        'replacementDataEpoch must differ from originalDataEpoch -- a '
        'deletion transaction always establishes a genuinely fresh epoch.',
      );
    }
    return PendingDeletionTransaction._(
      accountFingerprint: accountFingerprint,
      originalDataEpoch: originalDataEpoch,
      replacementDataEpoch: replacementDataEpoch,
      stage: stage,
    );
  }

  const PendingDeletionTransaction._({
    required this.accountFingerprint,
    required this.originalDataEpoch,
    required this.replacementDataEpoch,
    required this.stage,
  });

  /// The opaque CloudKit account fingerprint this transaction targets --
  /// fixed for the transaction's lifetime. Never rendered by [toString]/
  /// [toLogSafeSummary].
  final String accountFingerprint;

  /// This account's `AccountSyncState.dataEpoch` at the exact moment this
  /// transaction began, or `null` if no bucket existed yet. Never rendered
  /// by [toString]/[toLogSafeSummary].
  final DataEpoch? originalDataEpoch;

  /// The fresh epoch this transaction will establish as the new remote
  /// deletion/resurrection barrier -- generated exactly once, at creation.
  /// Never rendered by [toString]/[toLogSafeSummary].
  final DataEpoch replacementDataEpoch;

  /// This transaction's current durable stage.
  final DeletionTransactionStage stage;

  /// Returns a copy with [stage] replaced. [accountFingerprint],
  /// [originalDataEpoch], and [replacementDataEpoch] can never be changed --
  /// see the library doc comment's "Identity binding"/"Epoch
  /// generation-once" sections.
  PendingDeletionTransaction copyWithStage(DeletionTransactionStage stage) {
    return PendingDeletionTransaction._(
      accountFingerprint: accountFingerprint,
      originalDataEpoch: originalDataEpoch,
      replacementDataEpoch: replacementDataEpoch,
      stage: stage,
    );
  }

  Map<String, Object?> encode() => {
        'accountFingerprint': accountFingerprint,
        if (originalDataEpoch != null)
          'originalDataEpoch': originalDataEpoch!.value,
        'replacementDataEpoch': replacementDataEpoch.value,
        'stage': stage.name,
      };

  /// Strictly parses one raw deletion-transaction map. Returns `null` for
  /// anything malformed -- an unrecognized key, a missing/malformed
  /// `accountFingerprint`, an invalid `originalDataEpoch`/
  /// `replacementDataEpoch`, an unrecognized `stage`, or any structural
  /// invariant the constructor itself enforces. Never throws.
  static PendingDeletionTransaction? tryDecode(Map<Object?, Object?> raw) {
    const allowedKeys = {
      'accountFingerprint',
      'originalDataEpoch',
      'replacementDataEpoch',
      'stage',
    };
    for (final key in raw.keys) {
      if (key is! String || !allowedKeys.contains(key)) return null;
    }

    final fingerprintValue = raw['accountFingerprint'];
    if (fingerprintValue is! String ||
        !looksLikeAccountFingerprint(fingerprintValue)) {
      return null;
    }

    DataEpoch? originalDataEpoch;
    final originalDataEpochValue = raw['originalDataEpoch'];
    if (originalDataEpochValue != null) {
      if (originalDataEpochValue is! String ||
          !DataEpoch.isValid(originalDataEpochValue)) {
        return null;
      }
      originalDataEpoch = DataEpoch.parse(originalDataEpochValue);
    }

    final replacementDataEpochValue = raw['replacementDataEpoch'];
    if (replacementDataEpochValue is! String ||
        !DataEpoch.isValid(replacementDataEpochValue)) {
      return null;
    }
    final replacementDataEpoch = DataEpoch.parse(replacementDataEpochValue);

    final stageValue = raw['stage'];
    if (stageValue is! String) return null;
    DeletionTransactionStage? stage;
    for (final candidate in DeletionTransactionStage.values) {
      if (candidate.name == stageValue) stage = candidate;
    }
    if (stage == null) return null;

    try {
      return PendingDeletionTransaction(
        accountFingerprint: fingerprintValue,
        originalDataEpoch: originalDataEpoch,
        replacementDataEpoch: replacementDataEpoch,
        stage: stage,
      );
    } on PendingDeletionTransactionFormatException {
      return null;
    }
  }

  /// A privacy-safe summary: [stage] only -- never [accountFingerprint],
  /// [originalDataEpoch], or [replacementDataEpoch].
  Map<String, Object?> toLogSafeSummary() => {'stage': stage.name};

  @override
  String toString() => 'PendingDeletionTransaction(${toLogSafeSummary()})';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PendingDeletionTransaction &&
        other.accountFingerprint == accountFingerprint &&
        other.originalDataEpoch == originalDataEpoch &&
        other.replacementDataEpoch == replacementDataEpoch &&
        other.stage == stage;
  }

  @override
  int get hashCode => Object.hash(
        accountFingerprint,
        originalDataEpoch,
        replacementDataEpoch,
        stage,
      );
}
