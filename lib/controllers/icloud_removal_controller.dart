/// Build 26 Phase 5 (final slice): the Settings-facing "Remove from iCloud"
/// surface.
///
/// Named platform-neutrally ([ICloudRemovalController], never
/// "CloudKitDeletionController" or similar) so `lib/screens/
/// settings_screen.dart` can depend on this file without ever containing the
/// substring "CloudKit" -- mirrors `lib/controllers/
/// sync_association_controller.dart`'s own naming rationale exactly (see
/// that file's library doc comment).
///
/// **Never a second deletion implementation.** This file performs no
/// CloudKit operation, no deletion-stage advancement, no local finalize, and
/// no verification of any kind -- it only calls the two already-existing,
/// already-audited entry points the real Phase 5 (slices 1-3) deletion
/// machinery exposes:
///
///  * [SyncPersistenceStore.beginDeletionTransaction] -- the one durable,
///    idempotent "start or resume" entry point
///    `sync_persistence_store.dart` already defines (Phase 5 slice 1). This
///    file never constructs a [PendingDeletionTransaction] itself, never
///    advances a stage, and never clears one.
///  * A plain, argument-free `requestSyncAfterRemoval` callback -- the exact
///    same fire-and-forget shape [SyncAssociationController]'s own
///    `requestSyncAfterAssociation` already uses. This file never imports
///    the runtime coordinator's own source directory, never learns
///    `SyncRuntimeTrigger` exists, and never invokes the runtime
///    coordinator's own sync-request entry point itself -- production
///    wiring (`lib/services/app_services.dart`) supplies a closure that
///    performs that call on this file's behalf, passing the dedicated
///    `explicitDeletion` trigger value. See that coordinator's own
///    dedicated structural layering test, which proves its sync-request
///    entry point is only ever invoked from three disclosed production
///    files, none of which is this one.
///
/// Once [beginRemoval] durably starts (or resumes) the transaction and fires
/// the nudge, every further step -- the epoch barrier, the remote purge, the
/// remote-empty verification, and the local finalize/detach -- is driven
/// entirely by `CloudKitRemoteDeletionRunner`/`LocalDeletionFinalizer`
/// (Phase 5 slices 2-3), unconditionally, as the very first step of every
/// future sync pass, exactly as already implemented and already tested.
/// Nothing in this file duplicates any part of that pipeline.
///
/// **Never touches local content.** This file depends on
/// [SyncPersistenceStore] only -- never a `KeptRepository`, never a
/// `SavedReflectionsService`, never `DailyWisdomAccessService`/
/// `DailyAccessRepository`. Kept wisdoms, Reflections, and the rolling
/// 24-hour daily-access ritual state are all completely outside this file's
/// reach because it is never given a reference to any of them -- the
/// deletion transaction this file starts targets only this device's
/// CloudKit-side sync metadata (see `pending_deletion_transaction.dart`'s
/// own "Scope of this slice" section); the finalizer that eventually
/// completes it is independently already proven (Phase 5 slice 3) to leave
/// local Kept/Reflection content completely untouched.
///
/// **Privacy.** [ICloudRemovalCheckResult]/[ICloudRemovalBeginOutcome] are
/// both content-free by construction -- an enum, nothing more. This file
/// never exposes an account fingerprint, a `DataEpoch`, a stage name, or any
/// other durable identifier to its caller.
library;

import '../sync_persistence/deletion_transaction_result.dart';
import '../sync_persistence/pending_deletion_transaction.dart';
import '../sync_persistence/sync_persistence_store.dart';

/// Settings-facing "Remove from iCloud" row state. Deliberately coarse --
/// this screen never distinguishes *why* a pending removal has not yet
/// finished (a bounded-backoff retry still waiting, a transient account
/// unavailability, or genuine forward progress already made) from any other
/// -- every one of those durable-transaction-still-present cases reads as
/// [pending] alike, so a still-in-progress removal is never mistaken for a
/// failure the user must react to, and a transient background hiccup is
/// never surfaced as an alarming error. See the library doc comment's
/// "Never a second deletion implementation" section.
enum ICloudRemovalDisplayStatus {
  /// No account is currently associated with iCloud Sync, and no deletion
  /// transaction is pending -- there is nothing for this row to remove.
  notApplicable,

  /// An account is currently associated and no deletion transaction is
  /// pending -- tapping the row may start one.
  idle,

  /// A deletion transaction currently exists durably (whether just started
  /// by this device or resumed from a previous session) -- the real Phase 5
  /// runtime pipeline will keep driving it forward on its own; this row
  /// reflects that fact only.
  pending,
}

/// Content-free by construction: an enum, nothing more.
final class ICloudRemovalCheckResult {
  const ICloudRemovalCheckResult({required this.displayStatus});

  final ICloudRemovalDisplayStatus displayStatus;
}

/// The categorical, content-safe outcome of one [ICloudRemovalController
/// .beginRemoval] call.
enum ICloudRemovalBeginOutcome {
  /// The deletion transaction is now durably pending for the currently
  /// associated account -- whether this call itself just created it
  /// ([BeginDeletionTransactionStatus.started]) or it already existed
  /// ([BeginDeletionTransactionStatus.resumedExisting]), and the
  /// fire-and-forget sync nudge has been requested.
  started,

  /// No account was actually associated when this call ran -- nothing to
  /// remove. Never surfaced to the user as a failure (mirrors
  /// [SyncAssociationEnableOutcome.notApplicable]'s identical precedent).
  notApplicable,

  /// The durable begin call itself was refused or threw -- a generic,
  /// content-free outcome. The UI shows one fixed, retry-eligible message;
  /// never an account-fingerprint or the underlying
  /// [BeginDeletionTransactionStatus].
  failed,
}

/// See the library doc comment for the full contract.
final class ICloudRemovalController {
  ICloudRemovalController({
    required SyncPersistenceStore syncPersistenceStore,
    required void Function() requestSyncAfterRemoval,
  })  : _syncPersistenceStore = syncPersistenceStore,
        _requestSyncAfterRemoval = requestSyncAfterRemoval;

  final SyncPersistenceStore _syncPersistenceStore;
  final void Function() _requestSyncAfterRemoval;

  /// Read-only -- performs no write of any kind. Safe to call as often as
  /// Settings needs (every time the screen opens, and again after the user
  /// taps the row while a removal is already [ICloudRemovalDisplayStatus
  /// .pending], to reflect whatever has changed since -- never cached here).
  /// A read failure of either underlying durable value fails closed to
  /// [ICloudRemovalDisplayStatus.notApplicable] -- the same safe,
  /// non-actionable default [SyncAssociationController.checkStatus] already
  /// returns for its own unexpected-failure case.
  Future<ICloudRemovalCheckResult> checkStatus() async {
    final PendingDeletionTransaction? transaction;
    try {
      transaction =
          await _syncPersistenceStore.loadPendingDeletionTransaction();
    } catch (_) {
      return const ICloudRemovalCheckResult(
        displayStatus: ICloudRemovalDisplayStatus.notApplicable,
      );
    }
    if (transaction != null) {
      return const ICloudRemovalCheckResult(
        displayStatus: ICloudRemovalDisplayStatus.pending,
      );
    }

    final String? fingerprint;
    try {
      fingerprint =
          await _syncPersistenceStore.loadAssociatedAccountFingerprint();
    } catch (_) {
      return const ICloudRemovalCheckResult(
        displayStatus: ICloudRemovalDisplayStatus.notApplicable,
      );
    }

    return ICloudRemovalCheckResult(
      displayStatus: fingerprint == null
          ? ICloudRemovalDisplayStatus.notApplicable
          : ICloudRemovalDisplayStatus.idle,
    );
  }

  /// Must only be called after the user has explicitly confirmed the
  /// "Remove from iCloud?" prompt. Idempotent: [SyncPersistenceStore
  /// .beginDeletionTransaction] itself already guarantees a second call for
  /// the same currently-associated account resumes the exact same
  /// transaction rather than creating a competing one
  /// ([BeginDeletionTransactionStatus.resumedExisting]) -- this method never
  /// duplicates any part of that guarantee, and never advances a stage,
  /// clears a transaction, or performs a CloudKit operation itself.
  Future<ICloudRemovalBeginOutcome> beginRemoval() async {
    final String? fingerprint;
    try {
      fingerprint =
          await _syncPersistenceStore.loadAssociatedAccountFingerprint();
    } catch (_) {
      return ICloudRemovalBeginOutcome.failed;
    }

    if (fingerprint == null) {
      // Nothing associated -- never reported as a failure.
      return ICloudRemovalBeginOutcome.notApplicable;
    }

    final BeginDeletionTransactionResult result;
    try {
      result = await _syncPersistenceStore.beginDeletionTransaction(
        accountFingerprint: fingerprint,
      );
    } catch (_) {
      return ICloudRemovalBeginOutcome.failed;
    }

    switch (result.status) {
      case BeginDeletionTransactionStatus.started:
      case BeginDeletionTransactionStatus.resumedExisting:
        _requestSyncAfterRemoval();
        return ICloudRemovalBeginOutcome.started;
      case BeginDeletionTransactionStatus.accountMismatch:
      case BeginDeletionTransactionStatus.invalidFingerprint:
        // Fail closed -- a deletion transaction is never silently
        // retargeted to a different account, and an unrecognizable
        // fingerprint value is never forced through.
        return ICloudRemovalBeginOutcome.failed;
    }
  }
}
