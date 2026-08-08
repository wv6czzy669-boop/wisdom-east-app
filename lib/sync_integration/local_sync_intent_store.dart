/// Build 26 Phase 4E-1: the durable local sync-intent persistence boundary.
///
/// Deliberately narrow, mirroring `lib/sync_persistence/
/// sync_persistence_store.dart`'s own precedent: this store never calls
/// CloudKit, never touches `KeptStateEnvelope`/`east_kept_state`, and never
/// touches `SyncPersistenceEnvelope`/`east_sync_state` -- it owns exactly
/// one durable concern, the not-yet-resolved [LocalSyncIntent] collection,
/// in its own dedicated protected file.
library;

import 'local_sync_intent.dart';

/// Thrown by [LocalSyncIntentStore] implementations on any failure to load,
/// replace, or otherwise safely mutate the protected intent envelope.
///
/// Narrow, mirroring `SyncPersistenceStoreException`: [stage] identifies
/// which step failed (safe diagnostic metadata) and [message] is always a
/// static, content-safe string authored at the throw site -- never built
/// from, or including, envelope JSON, a `revealId`, a `mutationId`, an
/// `intentId`, wisdom text, reflection text, or a filesystem path.
/// [cause] is retained for programmatic inspection and tests only and is
/// deliberately excluded from [toString] -- an underlying platform/
/// filesystem exception's own message can itself carry an absolute path or
/// other implementation detail this store must never surface.
class LocalSyncIntentStoreException implements Exception {
  const LocalSyncIntentStoreException(this.stage, this.message, [this.cause]);

  final String stage;
  final String message;
  final Object? cause;

  @override
  String toString() => 'LocalSyncIntentStoreException[$stage]: $message';
}

/// Thrown when a caller attempts to enqueue an intent whose [LocalSyncIntent
/// .intentId] already exists in the store with genuinely different content
/// (a different [LocalSyncIntent.kind] or [LocalSyncIntent.payload]) -- an
/// impossible identity collision this store refuses to silently resolve
/// either way.
class ConflictingLocalSyncIntentIdentityException implements Exception {
  const ConflictingLocalSyncIntentIdentityException();

  @override
  String toString() =>
      'ConflictingLocalSyncIntentIdentityException: an intent with this '
      'intentId already exists with different content.';
}

/// Thrown by [LocalSyncIntentStore.advanceIntentStage] when the intent
/// currently stored under the given `intentId` is not in the caller's
/// expected stage -- a fail-closed guard against clobbering a stage a
/// concurrent/later operation has already advanced (or superseded) past
/// what the caller last observed.
class LocalSyncIntentStageMismatchException implements Exception {
  const LocalSyncIntentStageMismatchException();

  @override
  String toString() => 'LocalSyncIntentStageMismatchException: the intent\'s '
      'current stage does not match the expected stage.';
}

/// The durable local sync-intent persistence boundary.
abstract interface class LocalSyncIntentStore {
  /// Returns every currently-pending [LocalSyncIntent], in the exact stored
  /// order (see [LocalSyncIntentEnvelope]'s own doc comment). Returns an
  /// empty list when nothing has ever been enqueued.
  Future<List<LocalSyncIntent>> loadIntents();

  /// Durably enqueues [intent].
  ///
  /// Identity/coalescing policy, keyed by (`intent.intentId`,
  /// `intent.recordName`) -- mirroring `SyncPersistenceStore.enqueueMutation`
  /// exactly:
  /// - **Same `intentId`, same `kind`/`payload`:** idempotent no-op (the
  ///   existing entry, including its current [LocalSyncIntentStage], is left
  ///   completely unchanged).
  /// - **Same `intentId`, different `kind`/`payload`:** an impossible
  ///   identity collision -- throws
  ///   [ConflictingLocalSyncIntentIdentityException].
  /// - **Different `intentId`, different `recordName`:** appended, in
  ///   deterministic order.
  /// - **Different `intentId`, same `recordName`:** the newer intent
  ///   **atomically supersedes** the existing not-yet-resolved one for that
  ///   record, in the same envelope write, preserving that record's
  ///   original position in the stored list (the slot is overwritten in
  ///   place, never removed and re-appended).
  Future<void> enqueueIntent(LocalSyncIntent intent);

  /// Atomically advances the intent currently stored under [intentId] from
  /// [expectedStage] to [nextStage], in one envelope write.
  ///
  /// A no-op if no intent with [intentId] currently exists (it may already
  /// have been resolved/removed, or superseded by a different `intentId`
  /// for the same record -- see [enqueueIntent]'s own doc comment). Throws
  /// [LocalSyncIntentStageMismatchException] if an intent with [intentId]
  /// exists but its current stage does not equal [expectedStage] -- this
  /// method never silently overwrites an unexpected stage.
  Future<void> advanceIntentStage({
    required String intentId,
    required LocalSyncIntentStage expectedStage,
    required LocalSyncIntentStage nextStage,
  });

  /// Atomically and permanently removes the exact intent stored under
  /// [intentId] -- and only that exact `intentId` -- from the store.
  ///
  /// A no-op if no intent with [intentId] currently exists. **This is always
  /// `intentId`-specific, never `recordName`-specific:** if a record's
  /// pending intent was superseded (a newer local action replaced it with a
  /// new `intentId` before the older one was resolved), removing the *old*,
  /// no-longer-queued `intentId` removes nothing -- the current, replacement
  /// intent is untouched and remains exactly where [enqueueIntent] left it.
  Future<void> removeIntent(String intentId);
}
