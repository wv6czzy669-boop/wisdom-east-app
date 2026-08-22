/// Build 26 Phase 4E-2: the real implementation of the integration boundary
/// `kept_sync_integration_coordinator.dart` reserved as a placeholder in
/// Phase 4E-1. See that phase's committed doc comment (preserved in git
/// history) and `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md`'s Phase 4E-2
/// section for the full design rationale. This file composes
/// [KeptRepository] with the durable sync layers from the outside --
/// [KeptRepository] itself imports nothing from this directory or from
/// `lib/sync_persistence/`.
///
/// Owns exactly one dedicated [PersistenceOperationCoordinator] instance
/// under [resourceKey] (`kept_sync_integration_v1`), never shared with
/// [KeptRepository]'s own `kept_repository_v1` coordinator or with either
/// durable store's own internal coordinator. Every integration-aware
/// transaction -- every `record*` user mutation and every per-intent
/// reconciliation step -- acquires this key for its entire duration. The
/// only nested lock acquisition anywhere in this file is
/// `kept_sync_integration_v1` -> `kept_repository_v1` (via a plain call into
/// [KeptRepository], which acquires its own key internally) -> whichever
/// store's own internal file lock a durable read/write touches. Never the
/// reverse, and this key is never reacquired from within a transaction that
/// already holds it -- in particular, the `onAuthorized` callbacks below
/// never call back into this coordinator's own `record*`/`reconcile*`
/// methods.
///
/// No CloudKit/native account lookup, startup trigger, foreground trigger,
/// network listener, background job, or automatic retry is introduced here.
/// [reconcileForAssociatedAccount] is callable but never called from
/// production code in this phase -- exactly like `SyncOrchestrator
/// .runSyncPass()` and `SyncPersistenceStore.commitIncomingBatchCheckpoint`
/// were in earlier phases before their own callers existed.
library;

import 'package:uuid/uuid.dart';

import '../models/favorite_item.dart';
import '../models/kept_record.dart';
import '../persistence/persistence_operation_coordinator.dart';
import '../repositories/kept_repository.dart';
import '../sync/cloud_kept_wisdom_projection.dart';
import '../sync/data_epoch.dart';
import '../sync/sync_change.dart';
import '../sync/sync_tombstone.dart';
import '../sync_persistence/account_sync_state.dart';
import '../sync_persistence/sync_persistence_store.dart';
import '../utils/canonical_uuid.dart';
import '../utils/kept_timestamp_canonicalizer.dart';
import 'local_sync_intent.dart';
import 'local_sync_intent_store.dart';

/// An already-resolved account identity supplied by a caller external to
/// this phase (a future Phase 4E-4/4F bootstrap flow, or a test).
///
/// [KeptSyncIntegrationCoordinator] never resolves one of these itself,
/// never calls a native/CloudKit bridge, never fabricates
/// [accountFingerprint], and never fabricates a `DataEpoch` -- the epoch
/// used for every enqueued mutation always comes exclusively from the
/// already-persisted [AccountSyncState] this fingerprint resolves to (see
/// [KeptSyncIntegrationCoordinator.reconcileForAssociatedAccount]).
final class AssociatedSyncAccountContext {
  const AssociatedSyncAccountContext({required this.accountFingerprint});

  /// The opaque CloudKit account fingerprint an already-existing
  /// [AccountSyncState] bucket is keyed by. Never derived, guessed, or
  /// looked up by this class.
  final String accountFingerprint;
}

/// The real Phase 4E-2 integration coordinator. See the library doc comment
/// for the full transaction/locking model.
final class KeptSyncIntegrationCoordinator {
  KeptSyncIntegrationCoordinator({
    required KeptRepository keptRepository,
    required LocalSyncIntentStore intentStore,
    required SyncPersistenceStore syncPersistenceStore,
    PersistenceOperationCoordinator? integrationCoordinator,
    String Function()? idFactory,
    DateTime Function()? clock,
    void Function()? onMutationCommitted,
  })  : _keptRepository = keptRepository,
        _intentStore = intentStore,
        _syncPersistenceStore = syncPersistenceStore,
        _integrationCoordinator =
            integrationCoordinator ?? PersistenceOperationCoordinator(),
        _idFactory = idFactory ?? (() => const Uuid().v4()),
        _clock = clock ?? DateTime.now,
        _onMutationCommitted = onMutationCommitted;

  /// The single Phase 4E-2 integration transaction resource key. See the
  /// library doc comment for the required acquisition order.
  static const String resourceKey = 'kept_sync_integration_v1';

  final KeptRepository _keptRepository;
  final LocalSyncIntentStore _intentStore;
  final SyncPersistenceStore _syncPersistenceStore;
  final PersistenceOperationCoordinator _integrationCoordinator;
  final String Function() _idFactory;
  final DateTime Function() _clock;

  /// Build 26 Phase 4F fast-follow: an optional, payload-free notification
  /// invoked at most once per fresh outward-facing user mutation
  /// ([recordKeep]/[recordReflectionSave]/[recordReflectionDelete]/
  /// [recordRemove]) that actually wrote a durable [LocalSyncIntent] --
  /// never on an idempotent no-op, a free-tier rejection, an unchanged
  /// reflection, a missing item, or a validation failure (see each method's
  /// own `writtenIntentId != null` guard), and never during
  /// [reconcileForAssociatedAccount]'s replay path, which reuses the same
  /// [_advanceIfIntentWasWritten] helper without triggering this callback.
  ///
  /// Deliberately typed as a plain, argument-free `void Function()` --
  /// this file imports nothing from `lib/sync_runtime/` and never learns
  /// about `SyncRuntimeTrigger` or `CloudKitSyncRuntimeCoordinator`. The
  /// caller supplied at construction (`app_services.dart`) is solely
  /// responsible for what happens next; this coordinator only promises to
  /// call it, synchronously, with zero payload, and to never let a failure
  /// inside it affect the mutation that just committed -- see
  /// [_notifyIfIntentWasWritten].
  final void Function()? _onMutationCommitted;

  // -----------------------------------------------------------------------
  // User-mutation surface. Each method acquires [resourceKey] for its
  // entire transaction: pre-mint identity -> call the plain KeptRepository
  // method with `onAuthorized` -> (if a real mutation was authorized)
  // advance the durable intent to localCommittedOutboxPending -> release.
  // No account/CloudKit lookup and no outbox enqueue happens on this path --
  // that only ever happens via reconcileForAssociatedAccount, an explicit,
  // separate call.
  // -----------------------------------------------------------------------

  Future<KeptRepositoryMutationResult> recordKeep({
    required String revealId,
    required String wisdomText,
    String? wisdomId,
    required DateTime revealedAt,
    required bool isKeeper,
  }) {
    return _integrationCoordinator.runExclusive<KeptRepositoryMutationResult>(
      resourceKey: resourceKey,
      operation: () async {
        final presetId = _mintId();
        final presetMutationId = _mintId();
        final presetKeptAt = canonicalizeKeptTimestamp(_clock());
        String? writtenIntentId;

        final result = await _keptRepository.keepOccurrence(
          revealId: revealId,
          wisdomText: wisdomText,
          wisdomId: wisdomId,
          revealedAt: revealedAt,
          isKeeper: isKeeper,
          presetId: presetId,
          presetMutationId: presetMutationId,
          presetKeptAt: presetKeptAt,
          onAuthorized: (target) async {
            final intentId = _mintId();
            await _intentStore.enqueueIntent(
              LocalSyncIntent(
                intentId: intentId,
                kind: LocalSyncIntentKind.create,
                payload: _activePayloadFromTarget(
                  target,
                  operation: LocalSyncIntentOperation.keep,
                ),
                stage: LocalSyncIntentStage.pendingLocalApplication,
                enqueuedAt: canonicalizeKeptTimestamp(_clock()),
              ),
            );
            writtenIntentId = intentId;
          },
        );

        await _advanceIfIntentWasWritten(writtenIntentId);
        _notifyIfIntentWasWritten(writtenIntentId);
        return result;
      },
    );
  }

  Future<KeptRepositoryMutationResult> recordReflectionSave({
    required String itemId,
    required String reflection,
    required bool isKeeper,
    DateTime? reflectedAt,
  }) {
    return _integrationCoordinator.runExclusive<KeptRepositoryMutationResult>(
      resourceKey: resourceKey,
      operation: () async {
        final presetMutationId = _mintId();
        final presetUpdatedAt =
            canonicalizeKeptTimestamp(reflectedAt ?? _clock());
        String? writtenIntentId;

        final result = await _keptRepository.saveReflection(
          itemId: itemId,
          reflection: reflection,
          isKeeper: isKeeper,
          reflectedAt: reflectedAt,
          presetMutationId: presetMutationId,
          presetUpdatedAt: presetUpdatedAt,
          onAuthorized: (target) async {
            final intentId = _mintId();
            await _intentStore.enqueueIntent(
              LocalSyncIntent(
                intentId: intentId,
                kind: LocalSyncIntentKind.update,
                payload: _activePayloadFromTarget(
                  target,
                  operation: LocalSyncIntentOperation.reflectionSave,
                ),
                stage: LocalSyncIntentStage.pendingLocalApplication,
                enqueuedAt: canonicalizeKeptTimestamp(_clock()),
              ),
            );
            writtenIntentId = intentId;
          },
        );

        await _advanceIfIntentWasWritten(writtenIntentId);
        _notifyIfIntentWasWritten(writtenIntentId);
        return result;
      },
    );
  }

  Future<List<FavoriteItem>> recordReflectionDelete({
    required String itemId,
  }) {
    return _integrationCoordinator.runExclusive<List<FavoriteItem>>(
      resourceKey: resourceKey,
      operation: () async {
        final presetMutationId = _mintId();
        final presetUpdatedAt = canonicalizeKeptTimestamp(_clock());
        String? writtenIntentId;

        final result = await _keptRepository.deleteReflection(
          itemId: itemId,
          presetMutationId: presetMutationId,
          presetUpdatedAt: presetUpdatedAt,
          onAuthorized: (target) async {
            final intentId = _mintId();
            await _intentStore.enqueueIntent(
              LocalSyncIntent(
                intentId: intentId,
                kind: LocalSyncIntentKind.update,
                payload: _activePayloadFromTarget(
                  target,
                  operation: LocalSyncIntentOperation.reflectionDelete,
                ),
                stage: LocalSyncIntentStage.pendingLocalApplication,
                enqueuedAt: canonicalizeKeptTimestamp(_clock()),
              ),
            );
            writtenIntentId = intentId;
          },
        );

        await _advanceIfIntentWasWritten(writtenIntentId);
        _notifyIfIntentWasWritten(writtenIntentId);
        return result;
      },
    );
  }

  Future<RemovedKeptOccurrence?> recordRemove({required String itemId}) {
    return _integrationCoordinator.runExclusive<RemovedKeptOccurrence?>(
      resourceKey: resourceKey,
      operation: () async {
        String? writtenIntentId;

        final result = await _keptRepository.remove(
          itemId: itemId,
          onAuthorized: (removedRecord) async {
            final intentId = _mintId();
            // A fresh, independent deletion-event identity -- deliberately
            // never the removed record's own last `mutationId`, which
            // described its last *active* state, not this deletion. Mirrors
            // `SyncTombstone.mutationId`'s own contract exactly.
            final tombstoneMutationId = _mintId();
            final deletedAt = canonicalizeKeptTimestamp(_clock());
            await _intentStore.enqueueIntent(
              LocalSyncIntent(
                intentId: intentId,
                kind: LocalSyncIntentKind.delete,
                payload: LocalSyncIntentPayload.tombstone(
                  revealId: removedRecord.revealId,
                  deletedAtMs: deletedAt.millisecondsSinceEpoch,
                  updatedAtMs: deletedAt.millisecondsSinceEpoch,
                  mutationId: tombstoneMutationId,
                  // Local bookkeeping only -- never CloudKit identity, which
                  // remains `removedRecord.revealId` alone.
                  localId: removedRecord.id,
                ),
                stage: LocalSyncIntentStage.pendingLocalApplication,
                enqueuedAt: canonicalizeKeptTimestamp(_clock()),
              ),
            );
            writtenIntentId = intentId;
          },
        );

        await _advanceIfIntentWasWritten(writtenIntentId);
        _notifyIfIntentWasWritten(writtenIntentId);
        return result;
      },
    );
  }

  // -----------------------------------------------------------------------
  // Reconciliation surface. Never calls the record* methods above -- it
  // calls the plain KeptRepository methods directly (no `onAuthorized`, so
  // it structurally cannot create a new intent), passing back the exact
  // presets the original, already-authorized intent captured. Each intent
  // is reconciled inside its own separate `resourceKey` acquisition, so
  // unrelated intents/user mutations are never blocked for longer than one
  // intent's own transaction.
  // -----------------------------------------------------------------------

  /// Attempts to move every currently durable [LocalSyncIntent] one step
  /// closer to (and, when [context] resolves to a bootstrap-complete
  /// account bucket, all the way into) the durable sync outbox.
  ///
  /// Never resolves [context] itself, never calls a native/CloudKit bridge,
  /// never creates an account bucket, and never fabricates a `DataEpoch` --
  /// see [AssociatedSyncAccountContext]'s own doc comment. Not called by any
  /// production code path in this phase.
  Future<void> reconcileForAssociatedAccount(
    AssociatedSyncAccountContext context,
  ) async {
    // A snapshot only -- never trusted as still-current by the time each
    // per-intent transaction actually acquires the lock below. The
    // authoritative check is the `reload + confirm this exact intentId`
    // step inside [_reconcileOneIntent].
    final candidateIntentIds = (await _intentStore.loadIntents())
        .map((intent) => intent.intentId)
        .toList(growable: false);

    for (final intentId in candidateIntentIds) {
      await _integrationCoordinator.runExclusive<void>(
        resourceKey: resourceKey,
        operation: () => _reconcileOneIntent(intentId, context),
      );
    }
  }

  Future<void> _reconcileOneIntent(
    String intentId,
    AssociatedSyncAccountContext context,
  ) async {
    var intent = await _findCurrentIntent(intentId);
    if (intent == null) return;

    if (intent.stage == LocalSyncIntentStage.pendingLocalApplication) {
      await _replayPendingLocalApplication(intent);

      // The replay call above may have advanced this exact intentId's stage
      // (via advanceIntentStage, itself a no-op if something else already
      // resolved it) -- reload before deciding whether an outbox handoff is
      // now also possible in this same locked transaction.
      final refreshed = await _findCurrentIntent(intentId);
      if (refreshed == null) return;
      intent = refreshed;
    }

    if (intent.stage == LocalSyncIntentStage.localCommittedOutboxPending) {
      await _handleOutboxPending(intent, context);
    }
  }

  Future<LocalSyncIntent?> _findCurrentIntent(String intentId) async {
    final intents = await _intentStore.loadIntents();
    for (final intent in intents) {
      if (intent.intentId == intentId) return intent;
    }
    return null;
  }

  /// Replays exactly one `pendingLocalApplication` intent's local
  /// `KeptRepository` mutation, dispatching on [LocalSyncIntentPayload
  /// .operation] -- never inferred from payload shape. Uses the intent's own
  /// captured presets exactly; never mints a new id, mutationId, or
  /// timestamp, and never runs a second, coordinator-level free-limit check
  /// (the plain `KeptRepository` call itself skips its one business-
  /// authorization gate for this exact preset-without-`onAuthorized` shape --
  /// see `KeptRepository`'s own doc comment). No `onAuthorized` is ever
  /// passed here, so this call structurally cannot create a new intent.
  Future<void> _replayPendingLocalApplication(LocalSyncIntent intent) async {
    final payload = intent.payload;

    // An explicit, exhaustive if/else-if dispatch (never a fall-through
    // switch statement) over the closed [LocalSyncIntentOperation]
    // vocabulary -- never inferred from payload shape.
    if (payload.operation == LocalSyncIntentOperation.keep) {
      await _keptRepository.keepOccurrence(
        revealId: payload.revealId,
        wisdomText: payload.wisdomText!,
        wisdomId: payload.wisdomId,
        revealedAt: DateTime.fromMillisecondsSinceEpoch(
          payload.revealedAtMs!,
          isUtc: true,
        ),
        // Inert on this replay path: the free-tier gate this flag would
        // otherwise affect is already unconditionally skipped whenever a
        // preset identity is supplied without `onAuthorized` (this exact
        // call shape) -- see KeptRepository's own doc comment.
        isKeeper: true,
        presetId: payload.localId,
        presetMutationId: payload.mutationId,
        presetKeptAt: DateTime.fromMillisecondsSinceEpoch(
          payload.keptAtMs!,
          isUtc: true,
        ),
      );
    } else if (payload.operation == LocalSyncIntentOperation.reflectionSave) {
      await _keptRepository.saveReflection(
        itemId: payload.localId!,
        reflection: payload.reflectionText!,
        isKeeper: true, // inert -- see the keep case above.
        reflectedAt: payload.reflectedAtMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                payload.reflectedAtMs!,
                isUtc: true,
              ),
        presetMutationId: payload.mutationId,
        presetUpdatedAt: DateTime.fromMillisecondsSinceEpoch(
          payload.updatedAtMs,
          isUtc: true,
        ),
      );
    } else if (payload.operation == LocalSyncIntentOperation.reflectionDelete) {
      await _keptRepository.deleteReflection(
        itemId: payload.localId!,
        presetMutationId: payload.mutationId,
        presetUpdatedAt: DateTime.fromMillisecondsSinceEpoch(
          payload.updatedAtMs,
          isUtc: true,
        ),
      );
    } else if (payload.operation == LocalSyncIntentOperation.remove) {
      await _keptRepository.remove(itemId: payload.localId!);
    } else {
      throw StateError(
        'Unhandled LocalSyncIntentOperation during replay dispatch.',
      );
    }

    await _advanceIfIntentWasWritten(intent.intentId);
  }

  Future<void> _handleOutboxPending(
    LocalSyncIntent intent,
    AssociatedSyncAccountContext context,
  ) async {
    final bucket = await _syncPersistenceStore.loadAccountState(
      context.accountFingerprint,
    );
    // Build 26 Phase 4E-2: the only permitted gate. A missing bucket, or one
    // whose bootstrapState is anything other than `complete`
    // (notStarted/remoteBaselinePending/localReconciliationPending --
    // explicitly reserved for a future Phase 4E-4 bulk reconciliation, never
    // this phase -- or associationRequired), leaves the intent exactly as it
    // is: durably parked, never lost, never force-enqueued.
    if (bucket == null ||
        bucket.bootstrapState != AccountBootstrapState.complete) {
      return;
    }

    final change = _toSyncChange(intent, bucket.dataEpoch);
    await _syncPersistenceStore.enqueueMutation(
      context.accountFingerprint,
      change,
    );
    await _intentStore.removeIntent(intent.intentId);
  }

  SyncChange _toSyncChange(LocalSyncIntent intent, DataEpoch dataEpoch) {
    final payload = intent.payload;

    if (payload.isTombstone) {
      final tombstone = SyncTombstone(
        revealId: payload.revealId,
        dataEpoch: dataEpoch,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          payload.updatedAtMs,
          isUtc: true,
        ),
        deletedAt: DateTime.fromMillisecondsSinceEpoch(
          payload.deletedAtMs!,
          isUtc: true,
        ),
        mutationId: payload.mutationId,
        localId: payload.localId,
      );
      return SyncChange(
        kind: SyncChangeKind.delete,
        projection: CloudKeptWisdomProjection.tombstone(tombstone),
        enqueuedAt: canonicalizeKeptTimestamp(_clock()),
      );
    }

    // `CloudKeptWisdomProjection.active` requires a `KeptRecord` -- this one
    // is reconstructed purely as a conversion vehicle. `KeptRecord.id`
    // itself never appears anywhere in a `CloudKeptWisdomProjection`'s own
    // encoded shape (confirmed directly from that class), so a legitimately
    // absent `payload.localId` falling back to `payload.mutationId` here has
    // zero effect on the eventual wire projection or on CloudKit identity,
    // which remains `revealId`-derived throughout.
    final record = KeptRecord(
      id: payload.localId ?? payload.mutationId,
      revealId: payload.revealId,
      wisdomText: payload.wisdomText!,
      wisdomId: payload.wisdomId,
      revealedAt: DateTime.fromMillisecondsSinceEpoch(
        payload.revealedAtMs!,
        isUtc: true,
      ),
      keptAt: DateTime.fromMillisecondsSinceEpoch(
        payload.keptAtMs!,
        isUtc: true,
      ),
      reflectionText: payload.reflectionText,
      reflectedAt: payload.reflectedAtMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              payload.reflectedAtMs!,
              isUtc: true,
            ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        payload.updatedAtMs,
        isUtc: true,
      ),
      mutationId: payload.mutationId,
    );

    final kind = switch (intent.kind) {
      LocalSyncIntentKind.create => SyncChangeKind.create,
      LocalSyncIntentKind.update => SyncChangeKind.update,
      LocalSyncIntentKind.delete => SyncChangeKind.delete,
    };

    return SyncChange(
      kind: kind,
      projection:
          CloudKeptWisdomProjection.active(record, dataEpoch: dataEpoch),
      enqueuedAt: canonicalizeKeptTimestamp(_clock()),
    );
  }

  // -----------------------------------------------------------------------
  // Shared helpers.
  // -----------------------------------------------------------------------

  /// Builds the active-form payload for [target] -- the complete target
  /// occurrence, never only the field that changed -- reusing [target]'s own
  /// already-persisted (or, for a not-yet-persisted authorization callback,
  /// about-to-be-persisted) identity/timestamp fields exactly. Never mints
  /// anything here; every value comes directly from [target].
  LocalSyncIntentPayload _activePayloadFromTarget(
    KeptRecord target, {
    required LocalSyncIntentOperation operation,
  }) {
    return LocalSyncIntentPayload.active(
      revealId: target.revealId,
      operation: operation,
      wisdomText: target.wisdomText,
      wisdomId: target.wisdomId,
      revealedAtMs: target.revealedAt.millisecondsSinceEpoch,
      keptAtMs: target.keptAt.millisecondsSinceEpoch,
      updatedAtMs: target.updatedAt.millisecondsSinceEpoch,
      mutationId: target.mutationId,
      reflectionText: target.reflectionText,
      reflectedAtMs: target.reflectedAt?.millisecondsSinceEpoch,
      localId: target.id,
    );
  }

  Future<void> _advanceIfIntentWasWritten(String? intentId) async {
    if (intentId == null) return;
    await _intentStore.advanceIntentStage(
      intentId: intentId,
      expectedStage: LocalSyncIntentStage.pendingLocalApplication,
      nextStage: LocalSyncIntentStage.localCommittedOutboxPending,
    );
  }

  /// Build 26 Phase 4F fast-follow: invokes [_onMutationCommitted] exactly
  /// once, but only when [intentId] is non-null -- the same durable-write
  /// signal [_advanceIfIntentWasWritten] itself already uses, never
  /// re-derived from a mutation's result shape (`limitReached`,
  /// `reflectionLimitReached`, a `null` return, and so on). Called only from
  /// the four outward-facing `record*` methods, each *after* their own
  /// `_advanceIfIntentWasWritten` call has already completed -- never from
  /// [_replayPendingLocalApplication], which calls
  /// `_advanceIfIntentWasWritten` directly and deliberately does not reach
  /// this method, so a runtime-triggered reconciliation replay never
  /// generates an artificial second nudge back into the runtime coordinator
  /// that is already driving it.
  ///
  /// Synchronous, defensive containment: [_onMutationCommitted] is invoked
  /// with zero arguments and its result (if any) is ignored, wrapped in a
  /// `try`/`catch` that swallows every exception -- a failure here can never
  /// affect the mutation that already durably committed, and is never
  /// logged with any identifier or content.
  void _notifyIfIntentWasWritten(String? intentId) {
    if (intentId == null) return;
    try {
      _onMutationCommitted?.call();
    } catch (_) {
      // Intentionally contained -- see the doc comment above.
    }
  }

  String _mintId() {
    final id = _idFactory();
    if (!isCanonicalUuidV4(id)) {
      throw StateError(
        'Sync integration id factory produced a non-canonical UUID v4.',
      );
    }
    return id;
  }
}
