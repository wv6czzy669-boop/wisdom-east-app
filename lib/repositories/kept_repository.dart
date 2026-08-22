import 'package:uuid/uuid.dart';

import '../models/favorite_item.dart';
import '../models/kept_bootstrap_result.dart';
import '../models/kept_record.dart';
import '../models/kept_state_envelope.dart';
import '../persistence/kept_state_store.dart';
import '../persistence/persistence_operation_coordinator.dart';
import '../utils/canonical_uuid.dart';
import '../utils/date_formatter.dart';
import '../utils/kept_timestamp_canonicalizer.dart';
import '../utils/legacy_kept_identity.dart';

typedef KeptClock = DateTime Function();
typedef KeptIdFactory = String Function();

/// Thrown by every [KeptRepository] operation that cannot complete safely.
///
/// Deliberately narrow, mirroring [KeptStateStoreException]: [stage] is a
/// stable, diagnostic-only code (see the stage constants used throughout
/// this file — `bootstrap-unavailable`, `load`, `replace`,
/// `invalid-reveal-id`, `invalid-generated-id`, `missing-item`,
/// `invalid-reflection`); [message] and [toString] never include wisdom
/// text, reflection text, raw encoded JSON, file paths, or snapshot data.
class KeptRepositoryException implements Exception {
  const KeptRepositoryException(this.stage, this.message, [this.cause]);

  final String stage;
  final String message;
  final Object? cause;

  @override
  String toString() {
    final cause = this.cause;
    if (cause == null) return 'KeptRepositoryException[$stage]: $message';
    return 'KeptRepositoryException[$stage]: $message ($cause)';
  }
}

/// The outcome of a [KeptRepository] mutation: the complete, freshly mapped
/// active item list, and whether a limit blocked the requested change.
class KeptRepositoryMutationResult {
  const KeptRepositoryMutationResult({
    required this.items,
    required this.limitReached,
    this.reflectionLimitReached = false,
  });

  final List<FavoriteItem> items;
  final bool limitReached;
  final bool reflectionLimitReached;
}

/// Enough protected-domain information to restore a removed occurrence to
/// its exact prior identity and position.
///
/// Deliberately retains the full [KeptRecord] (not the mapped
/// [FavoriteItem]) so [KeptRepository.restore] can reconstruct the removed
/// occurrence without losing [KeptRecord.revealId], [KeptRecord.keptAt], or
/// any other protected-domain field a display-only [FavoriteItem] does not
/// carry.
class RemovedKeptOccurrence {
  const RemovedKeptOccurrence({
    required this.record,
    required this.originalIndex,
    required this.items,
  });

  final KeptRecord record;
  final int originalIndex;
  final List<FavoriteItem> items;
}

/// The authoritative, production Kept repository (Build 26 Phase 3D-C
/// production cutover; wired via `app_services.dart`'s `keptRepository`
/// global and consumed through `SavedReflectionsService`). This doc comment
/// previously claimed "not yet used by production" — that was accurate only
/// during Phase 3D-B and is corrected here as of Phase 4E-2, which adds the
/// optional authorization/preset parameters below without changing anything
/// about who owns this repository's storage.
///
/// Every dependency is constructor-injected — this repository never reads
/// `SharedPreferences` directly, never touches `LegacyFavoritesStore` or
/// `KeptMigrationCoordinator`, never reads any `app_services.dart` global,
/// and never runs migration internally. A [KeptBootstrapResult] is supplied
/// once at construction; this repository does not re-check storage
/// availability beyond consulting that already-computed result.
///
/// Every complete read-modify-replace operation runs inside exactly one
/// [PersistenceOperationCoordinator.runExclusive] call under
/// [resourceKey] (`kept_repository_v1`) — never nested recursively on that
/// same key. The underlying [KeptStateStore]'s own `load()`/`replace()`
/// serialize separately, under their own resource key
/// (`protected_kept_state_file` for [ProtectedFileKeptStateStore]), which
/// this repository always acquires from *inside* its own
/// [resourceKey] exclusive block — repository key first, store key second,
/// never the reverse, and never migration acquired from inside either.
///
/// **Build 26 Phase 4E-2 — optional authorization hook and identity
/// presets.** [keepOccurrence], [saveReflection], and [deleteReflection]
/// each accept optional `preset*` identity/timestamp parameters and an
/// optional `onAuthorized` callback; [remove] accepts only `onAuthorized`.
/// This repository remains completely unaware of CloudKit, accounts,
/// `DataEpoch`, `SyncPersistenceStore`, or `LocalSyncIntentStore` — it
/// imports none of `lib/sync_integration/` or `lib/sync_persistence/`, and
/// every new parameter here is an ordinary domain value (`String`,
/// `DateTime`, or a plain callback over [KeptRecord]). The one caller of
/// these parameters is `KeptSyncIntegrationCoordinator`
/// (`lib/sync_integration/kept_sync_integration_coordinator.dart`), which
/// composes this repository with the sync layers from the outside — never
/// the reverse.
///
/// `onAuthorized`, when supplied, is invoked exactly once per call, with the
/// complete target [KeptRecord] this method is about to (or, for [remove],
/// is about to stop referencing) persist — always *after* every existing
/// validation/no-op/limit check has already concluded a real mutation will
/// occur, and always *before* the physical envelope write. It may be async,
/// is always awaited, and is never caught: if it throws, the physical Kept
/// write does not happen and the whole method call fails. This is what lets
/// a caller durably record "this mutation is about to happen" with a
/// crash-safe guarantee that the physical write never outruns that record.
///
/// **Replay of an already-authorized mutation.** [keepOccurrence] and
/// [saveReflection] each have exactly one *business-authorization* gate (the
/// free-tier Kept/Reflection limit) that must run exactly once per genuine
/// new local user action — never again on crash-recovery replay of a
/// mutation that already passed it. A replay call is recognized structurally
/// (never via a mutable flag): it is the combination of a `preset*` identity
/// parameter being supplied *and* `onAuthorized` being omitted — a shape only
/// `KeptSyncIntegrationCoordinator`'s own replay path ever produces (its
/// normal, first-attempt user-mutation path always supplies *both* a preset
/// and `onAuthorized` together; an ordinary caller supplying neither always
/// gets the full check, unchanged). When that shape is detected, the
/// free-tier limit check is skipped for that call only — every other check
/// (idempotency-by-identity, missing-item, unchanged-content, input
/// validity) still runs unconditionally on every call, replay or not, since
/// those are structural safety checks, not new-action authorization gates.
final class KeptRepository {
  KeptRepository({
    required KeptStateStore store,
    required KeptBootstrapResult bootstrap,
    required PersistenceOperationCoordinator operationCoordinator,
    KeptIdFactory? idFactory,
    KeptClock? clock,
    this.freeKeptLimit = 3,
    this.freeReflectionLimit = 3,
  })  : _store = store,
        _bootstrap = bootstrap,
        _coordinator = operationCoordinator,
        _idFactory = idFactory ?? (() => const Uuid().v4()),
        _clock = clock ?? DateTime.now;

  static const String resourceKey = 'kept_repository_v1';

  final KeptStateStore _store;
  final KeptBootstrapResult _bootstrap;
  final PersistenceOperationCoordinator _coordinator;
  final KeptIdFactory _idFactory;
  final KeptClock _clock;

  /// Maximum active Kept records a non-Keeper user may hold. Migrated
  /// over-limit records (already active before this repository is ever
  /// consulted) are never removed to enforce this — only a *new* record is
  /// blocked once this limit is already met or exceeded.
  final int freeKeptLimit;

  /// Maximum active reflections a non-Keeper user may hold. Only gates
  /// adding a *first* reflection to a record — editing an already-existing
  /// reflection remains allowed even while over this limit.
  final int freeReflectionLimit;

  Future<List<FavoriteItem>> load() {
    return _coordinator.runExclusive<List<FavoriteItem>>(
      resourceKey: resourceKey,
      operation: () async {
        _requireReady();
        final envelope = await _loadEnvelope();
        return _mapAll(envelope);
      },
    );
  }

  Future<KeptRepositoryMutationResult> keepOccurrence({
    required String revealId,
    required String wisdomText,
    String? wisdomId,
    required DateTime revealedAt,
    required bool isKeeper,
    String? presetId,
    String? presetMutationId,
    DateTime? presetKeptAt,
    Future<void> Function(KeptRecord target)? onAuthorized,
  }) {
    return _coordinator.runExclusive<KeptRepositoryMutationResult>(
      resourceKey: resourceKey,
      operation: () async {
        _requireReady();

        // Build 26 Phase 3D-E (safety-gap correction, round 4): accepts
        // both a genuine Build 26-native v4 (the ordinary case) and a
        // deterministic migrated v5 (so a legacy occurrence, once its Daily
        // Access revealId has been reconciled to the migrated identity by
        // `DailyAccessRepository.reconcileRevealIdForOccurrence`, can be
        // deleted and re-kept without failing solely because its revealId
        // is v5, not v4). This is narrower than a blanket loosening: only
        // this externally-supplied `revealId` parameter is affected --
        // `_generateId`'s self-check below, and every other id/mutationId
        // contract in this file, remain v4-only.
        if (!isSupportedRevealId(revealId)) {
          throw const KeptRepositoryException(
            'invalid-reveal-id',
            'keepOccurrence requires a supported (v4 or migrated v5) '
                'revealId.',
          );
        }

        final envelope = await _loadEnvelope();

        final existingIndex = envelope.activeRecords.indexWhere(
          (record) => record.revealId == revealId,
        );
        if (existingIndex >= 0) {
          // Idempotent: an occurrence already kept from this exact reveal.
          // Never replace(), never mint a new id/mutationId.
          return KeptRepositoryMutationResult(
            items: _mapAll(envelope),
            limitReached: false,
          );
        }

        // Build 26 Phase 4E-2: a replay of an already-authorized mutation
        // (see the class doc comment) skips only this business-authorization
        // gate — never the idempotency check above, which always runs.
        final isReplayOfAuthorizedMutation =
            presetId != null && onAuthorized == null;
        if (!isKeeper &&
            !isReplayOfAuthorizedMutation &&
            envelope.activeRecords.length >= freeKeptLimit) {
          return KeptRepositoryMutationResult(
            items: _mapAll(envelope),
            limitReached: true,
          );
        }

        final id = presetId != null ? _validateId(presetId) : _generateId();
        final mutationId = presetMutationId != null
            ? _validateId(presetMutationId)
            : _generateId();
        // Canonicalized before ever reaching a KeptRecord: both the
        // caller-supplied authoritative revealedAt and this freshly-read
        // clock value may carry non-zero microseconds (a real device clock
        // routinely does) — see kept_timestamp_canonicalizer.dart for why
        // that would otherwise make this record fail its own protected
        // store's mandatory post-write read-back verification.
        final canonicalRevealedAt = canonicalizeKeptTimestamp(revealedAt);
        final keptAt = canonicalizeKeptTimestamp(presetKeptAt ?? _clock());

        final record = KeptRecord(
          id: id,
          revealId: revealId,
          wisdomText: wisdomText,
          wisdomId: wisdomId,
          revealedAt: canonicalRevealedAt,
          keptAt: keptAt,
          updatedAt: keptAt,
          mutationId: mutationId,
        );

        if (onAuthorized != null) {
          await onAuthorized(record);
        }

        final nextEnvelope = envelope.copyWith(
          activeRecords: [...envelope.activeRecords, record],
        );
        await _replaceEnvelope(nextEnvelope);

        return KeptRepositoryMutationResult(
          items: _mapAll(nextEnvelope),
          limitReached: false,
        );
      },
    );
  }

  Future<KeptRepositoryMutationResult> saveReflection({
    required String itemId,
    required String reflection,
    required bool isKeeper,
    DateTime? reflectedAt,
    String? presetMutationId,
    DateTime? presetUpdatedAt,
    Future<void> Function(KeptRecord target)? onAuthorized,
  }) {
    return _coordinator.runExclusive<KeptRepositoryMutationResult>(
      resourceKey: resourceKey,
      operation: () async {
        _requireReady();

        final normalized = reflection.trim();
        if (normalized.isEmpty ||
            normalized.runes.length > KeptRecord.maximumReflectionLength) {
          throw const KeptRepositoryException(
            'invalid-reflection',
            'Reflection must be non-empty and within the maximum length.',
          );
        }

        final envelope = await _loadEnvelope();
        final index = envelope.activeRecords.indexWhere(
          (record) => record.id == itemId,
        );
        if (index < 0) {
          throw const KeptRepositoryException(
            'missing-item',
            'The Kept wisdom no longer exists.',
          );
        }

        final existing = envelope.activeRecords[index];
        final isFirstReflection = existing.reflectionText == null;
        // Build 26 Phase 4E-2: see keepOccurrence's identical replay
        // recognition -- skips only this business-authorization gate.
        final isReplayOfAuthorizedMutation =
            presetMutationId != null && onAuthorized == null;
        if (isFirstReflection &&
            !isKeeper &&
            !isReplayOfAuthorizedMutation &&
            envelope.activeRecords
                    .where((record) => record.reflectionText != null)
                    .length >=
                freeReflectionLimit) {
          return KeptRepositoryMutationResult(
            items: _mapAll(envelope),
            limitReached: false,
            reflectionLimitReached: true,
          );
        }

        if (existing.reflectionText == normalized) {
          // Genuinely unchanged content: no replace, no mutationId refresh,
          // no updatedAt change.
          return KeptRepositoryMutationResult(
            items: _mapAll(envelope),
            limitReached: false,
          );
        }

        // Canonicalized: a caller-supplied reflectedAt (e.g. from
        // ReflectionScreen) or this freshly-read clock value may carry
        // non-zero microseconds — see kept_timestamp_canonicalizer.dart.
        final mutationTime = canonicalizeKeptTimestamp(reflectedAt ?? _clock());
        final updatedAt = presetUpdatedAt != null
            ? canonicalizeKeptTimestamp(presetUpdatedAt)
            : mutationTime;
        final mutationId = presetMutationId != null
            ? _validateId(presetMutationId)
            : _generateId();
        final updated = existing.copyWith(
          reflectionText: normalized,
          reflectedAt: mutationTime,
          updatedAt: updatedAt,
          mutationId: mutationId,
        );

        if (onAuthorized != null) {
          await onAuthorized(updated);
        }

        final nextEnvelope = envelope.copyWith(
          activeRecords: _replacingAt(envelope.activeRecords, index, updated),
        );
        await _replaceEnvelope(nextEnvelope);

        return KeptRepositoryMutationResult(
          items: _mapAll(nextEnvelope),
          limitReached: false,
        );
      },
    );
  }

  Future<List<FavoriteItem>> deleteReflection({
    required String itemId,
    String? presetMutationId,
    DateTime? presetUpdatedAt,
    Future<void> Function(KeptRecord target)? onAuthorized,
  }) {
    return _coordinator.runExclusive<List<FavoriteItem>>(
      resourceKey: resourceKey,
      operation: () async {
        _requireReady();

        final envelope = await _loadEnvelope();
        final index = envelope.activeRecords.indexWhere(
          (record) => record.id == itemId,
        );
        if (index < 0) {
          throw const KeptRepositoryException(
            'missing-item',
            'The Kept wisdom no longer exists.',
          );
        }

        final existing = envelope.activeRecords[index];
        if (existing.reflectionText == null) {
          return _mapAll(envelope);
        }

        // No free-tier limit gates a deletion, so there is no
        // business-authorization gate to skip on replay here — every check
        // above always runs, replay or not.
        final updatedAt = presetUpdatedAt != null
            ? canonicalizeKeptTimestamp(presetUpdatedAt)
            : canonicalizeKeptTimestamp(_clock());
        final mutationId = presetMutationId != null
            ? _validateId(presetMutationId)
            : _generateId();
        final updated = existing.copyWith(
          clearReflection: true,
          updatedAt: updatedAt,
          mutationId: mutationId,
        );

        if (onAuthorized != null) {
          await onAuthorized(updated);
        }

        final nextEnvelope = envelope.copyWith(
          activeRecords: _replacingAt(envelope.activeRecords, index, updated),
        );
        await _replaceEnvelope(nextEnvelope);

        return _mapAll(nextEnvelope);
      },
    );
  }

  Future<RemovedKeptOccurrence?> remove({
    required String itemId,
    Future<void> Function(KeptRecord removedRecord)? onAuthorized,
  }) {
    return _coordinator.runExclusive<RemovedKeptOccurrence?>(
      resourceKey: resourceKey,
      operation: () async {
        _requireReady();

        final envelope = await _loadEnvelope();
        final index = envelope.activeRecords.indexWhere(
          (record) => record.id == itemId,
        );
        if (index < 0) return null;

        final removedRecord = envelope.activeRecords[index];

        // Build 26 Phase 4E-2: [removedRecord] still exists in the envelope
        // at this exact point -- this is deliberately the last moment before
        // physical deletion at which a caller can capture its complete,
        // still-live state (in particular `revealId`, needed for CloudKit
        // identity) for a durable tombstone. No preset identity is accepted
        // here: removal mints no new content identity of its own inside this
        // repository (a tombstone's own fresh deletion-event mutationId is
        // an independent identity a caller mints outside this repository —
        // see `KeptSyncIntegrationCoordinator`), and there is no free-tier
        // limit gating removal, so there is no replay-authorization
        // distinction to make here either.
        if (onAuthorized != null) {
          await onAuthorized(removedRecord);
        }

        final remaining = [...envelope.activeRecords]..removeAt(index);
        final nextEnvelope = envelope.copyWith(activeRecords: remaining);
        await _replaceEnvelope(nextEnvelope);

        return RemovedKeptOccurrence(
          record: removedRecord,
          originalIndex: index,
          items: _mapAll(nextEnvelope),
        );
      },
    );
  }

  /// Build 26 Phase 3D-E (safety-gap correction, round 3 — direction
  /// inversion): a **read-only** lookup that never mutates protected Kept
  /// storage in any way.
  ///
  /// Background — why the migrated [KeptRecord] itself must never be
  /// touched: `KeptMigrationCoordinator._handleComplete()` runs on *every*
  /// app launch after the first (inside `KeptStorageBootstrapper`, before
  /// `HomeScreen` ever mounts) and re-derives the exact expected envelope
  /// from the immutable migration snapshot, then verifies the current
  /// protected envelope against it field-by-field
  /// (`_verifyFieldByField`, using [KeptRecord.operator==], which compares
  /// every field including `revealId`, `updatedAt`, and `mutationId`). A
  /// prior version of this fix rewrote a migrated record's `revealId` in
  /// place — which is exactly what made that verification fail on the very
  /// next launch (`KeptMigrationException['field-verify-mismatch']`),
  /// confirmed by real `flutter test` evidence. A migrated [KeptRecord] is
  /// permanently, byte-for-byte fixed the moment migration completes; nothing
  /// may ever change it again, including this lookup.
  ///
  /// So the correction runs in the *other* direction: the Build 25 daily
  /// wisdom occurrence's own `DailyWisdomRecord.revealId` (which never
  /// existed pre-Build-26, and is only ever a fresh, unrelated random UUID
  /// v4 minted by `DailyAccessRepository.backfillRevealIdIfNeeded()`) is
  /// what gets corrected — see
  /// `DailyAccessRepository.reconcileRevealIdForOccurrence`, which calls
  /// this method to discover what to correct *to*. Nothing in the protected
  /// Kept store ever changes as a result.
  ///
  /// Returns the already-existing, already-verified `revealId` of the one
  /// migrated [KeptRecord] that can be *proven* to be the exact same
  /// occurrence as [wisdomText] /
  /// `[committedRevealedAt, committedUnlockAt)` — never merely on the
  /// strength of matching text alone, which could just as easily describe
  /// an ordinary Build 26 record kept for a recurring wisdom on some other,
  /// unrelated occasion. Returns `null` for every other case (see below).
  ///
  /// A candidate is eligible only when ALL of the following hold:
  ///
  /// 1. [KeptRecord.wisdomText] matches [wisdomText] exactly.
  /// 2. Legacy save-instant window rule: the record's [KeptRecord.id] is a
  ///    parseable Build 25 `sr-v1-<micros>-<serial>` id
  ///    ([parseLegacySavedReflectionId]) whose embedded save instant falls
  ///    inside `[committedRevealedAt, committedUnlockAt)` — the committed
  ///    daily occurrence's own active window. See
  ///    `legacy_kept_identity.dart` for why this is genuinely
  ///    timezone-independent: the embedded value is
  ///    `DateTime.now().microsecondsSinceEpoch` at the moment the item was
  ///    originally Kept — an absolute Unix epoch instant, never
  ///    reinterpreted through any device's timezone at any point. The
  ///    window is right-exclusive (`< committedUnlockAt`) because a save at
  ///    or after `unlockAt` belongs, by the product's own rolling-24-hour
  ///    rule, to a *different* (later) occurrence, not this one.
  /// 3. Provenance gate: the record's existing `revealId` exactly equals
  ///    [deriveLegacyMigrationRevealId] of the record's own [KeptRecord.id]
  ///    — the same deterministic UUID v5 `KeptMigrationCoordinator` itself
  ///    minted for it at migration time. A normal Build 26 record's
  ///    `revealId` is a genuine random UUID v4 sourced from its own daily
  ///    record, never this deterministic v5 value, so it can never satisfy
  ///    this gate — an ordinary record is never returned here merely
  ///    because its text and window happen to coincide.
  /// 4. Exactly one such record exists. Zero or more than one is `null`:
  ///    ambiguity is never guessed at.
  ///
  /// Not every legacy id carries a derivable timestamp.
  /// `legacy-v1-<index>-...` (`StoredFavoriteEntryCodec.fallbackIdFor`,
  /// assigned when no id was ever stored at all) and
  /// `duplicate-v1-<index>-...`
  /// (`SavedReflectionsService._duplicateIdFor`, assigned to whichever of
  /// two colliding same-id legacy entries was decoded second) are both
  /// purely content-derived, carry no timestamp, and
  /// [parseLegacySavedReflectionId] correctly returns `null` for them — such
  /// a record can never be returned here, with no generic text/date
  /// fallback introduced to paper over it.
  Future<String?> resolveLegacyMigratedRevealIdForOccurrence({
    required String wisdomText,
    required DateTime committedRevealedAt,
    required DateTime committedUnlockAt,
  }) {
    return _coordinator.runExclusive<String?>(
      resourceKey: resourceKey,
      operation: () async {
        _requireReady();

        if (wisdomText.trim().isEmpty) return null;
        if (!committedUnlockAt.isAfter(committedRevealedAt)) return null;

        // Read-only: `load()`/`_loadEnvelope()` only, never `replace()`.
        final envelope = await _loadEnvelope();

        final candidates = envelope.activeRecords.where((record) {
          if (record.wisdomText != wisdomText) return false;

          final legacyInfo = parseLegacySavedReflectionId(record.id);
          if (legacyInfo == null) return false;

          final savedAt = legacyInfo.savedAt;
          if (savedAt.isBefore(committedRevealedAt)) return false;
          if (!savedAt.isBefore(committedUnlockAt)) return false;

          return record.revealId == deriveLegacyMigrationRevealId(record.id);
        }).toList();

        if (candidates.length != 1) return null;
        return candidates.single.revealId;
      },
    );
  }

  /// Build 26 Phase 4E-3b: the minimal, sync-unaware full-envelope
  /// read/replace surface an external incoming-apply coordinator needs to
  /// durably write a *complete*, already fully-computed target Kept state --
  /// never record-by-record, never with any of this repository's own
  /// id/timestamp generation, free-tier gating, or `onAuthorized` hook.
  ///
  /// This repository remains completely unaware of what "incoming",
  /// "remote", "conflict", or "sync" mean -- [loadAllRecords]/
  /// [replaceAllRecords] are exactly as sync-domain-free as [load]/
  /// [keepOccurrence] above; the caller (`IncomingKeptSyncCoordinator`,
  /// `lib/sync_integration/incoming_kept_sync_coordinator.dart`) is solely
  /// responsible for computing the complete next [KeptRecord] list (which
  /// existing records to keep unchanged, which to replace with adopted
  /// remote content, which to remove for a winning remote tombstone) before
  /// ever calling [replaceAllRecords].
  ///
  /// Returns the complete, currently active [KeptRecord] collection, in
  /// storage order. Never mapped to [FavoriteItem] -- a sync coordinator
  /// needs the protected-domain fields (`revealId`, `mutationId`, raw
  /// timestamps) a display-only [FavoriteItem] does not carry.
  Future<List<KeptRecord>> loadAllRecords() {
    return _coordinator.runExclusive<List<KeptRecord>>(
      resourceKey: resourceKey,
      operation: () async {
        _requireReady();
        final envelope = await _loadEnvelope();
        return envelope.activeRecords;
      },
    );
  }

  /// Atomically and unconditionally replaces the complete active [KeptRecord]
  /// collection with [records] -- one single read-modify-replace operation,
  /// never a per-record write. [records] must already be the caller's
  /// complete, final target list (every record unaffected by this
  /// transaction included unchanged, exactly as it already was); this method
  /// performs no merge, no dedup, no id/timestamp minting, and invokes no
  /// `onAuthorized`-style callback. [KeptStateEnvelope]'s own constructor
  /// still enforces its structural invariants (no duplicate `id`, no
  /// duplicate `revealId`) -- a caller that computed a duplicate-producing
  /// target list fails this call closed via that existing, unmodified
  /// validation, exactly as [keepOccurrence] and every other mutation above
  /// already rely on.
  ///
  /// Returns the complete resulting [KeptRecord] collection.
  Future<List<KeptRecord>> replaceAllRecords(List<KeptRecord> records) {
    return _coordinator.runExclusive<List<KeptRecord>>(
      resourceKey: resourceKey,
      operation: () async {
        _requireReady();
        final envelope = await _loadEnvelope();
        final nextEnvelope = envelope.copyWith(activeRecords: records);
        await _replaceEnvelope(nextEnvelope);
        return nextEnvelope.activeRecords;
      },
    );
  }

  Future<List<FavoriteItem>> restore(RemovedKeptOccurrence removed) {
    return _coordinator.runExclusive<List<FavoriteItem>>(
      resourceKey: resourceKey,
      operation: () async {
        _requireReady();

        final envelope = await _loadEnvelope();
        final alreadyActive = envelope.activeRecords.any(
          (record) =>
              record.id == removed.record.id ||
              record.revealId == removed.record.revealId,
        );
        if (alreadyActive) {
          return _mapAll(envelope);
        }

        // A genuine new local mutation: only updatedAt/mutationId change.
        // Every identity/content field (id, revealId, wisdomText,
        // revealedAt, keptAt, reflectionText, reflectedAt) is preserved
        // exactly, since KeptRecord.copyWith deliberately cannot alter any
        // of them.
        final restoredRecord = removed.record.copyWith(
          updatedAt: canonicalizeKeptTimestamp(_clock()),
          mutationId: _generateId(),
        );

        final insertionIndex =
            removed.originalIndex.clamp(0, envelope.activeRecords.length);
        final records = [...envelope.activeRecords]
          ..insert(insertionIndex, restoredRecord);
        final nextEnvelope = envelope.copyWith(activeRecords: records);
        await _replaceEnvelope(nextEnvelope);

        return _mapAll(nextEnvelope);
      },
    );
  }

  // -------------------------------------------------------------------
  // Shared helpers. None of these acquire the coordinator lock themselves
  // — only the public entry points above do.
  // -------------------------------------------------------------------

  void _requireReady() {
    if (_bootstrap.isUnavailable) {
      throw KeptRepositoryException(
        'bootstrap-unavailable',
        'Kept storage is unavailable (${_bootstrap.errorCode}); this '
            'operation cannot proceed.',
      );
    }
  }

  Future<KeptStateEnvelope> _loadEnvelope() async {
    final KeptStateEnvelope? loaded;
    try {
      loaded = await _store.load();
    } catch (error) {
      throw KeptRepositoryException(
        'load',
        'Could not load the protected Kept state.',
        error,
      );
    }
    // A genuine `null` (no authoritative envelope has ever been written)
    // is the only case mapped to an empty envelope. A thrown decode/read
    // failure is never reached here — it is already rethrown above as a
    // KeptRepositoryException, never silently treated as empty.
    return loaded ?? KeptStateEnvelope();
  }

  Future<void> _replaceEnvelope(KeptStateEnvelope envelope) async {
    try {
      await _store.replace(envelope);
    } catch (error) {
      throw KeptRepositoryException(
        'replace',
        'Could not replace the protected Kept state.',
        error,
      );
    }
  }

  String _generateId() => _validateId(_idFactory());

  /// Build 26 Phase 4E-2: the same canonical-UUID-v4 validation an
  /// internally-generated id already received, applied uniformly to a
  /// caller-supplied `preset*` identity too — an externally-supplied id is
  /// never trusted merely because it came from a caller.
  String _validateId(String id) {
    if (!isCanonicalUuidV4(id)) {
      throw const KeptRepositoryException(
        'invalid-generated-id',
        'Generated identity was not a canonical UUID v4.',
      );
    }
    return id;
  }

  List<KeptRecord> _replacingAt(
    List<KeptRecord> records,
    int index,
    KeptRecord replacement,
  ) {
    final next = [...records];
    next[index] = replacement;
    return next;
  }

  List<FavoriteItem> _mapAll(KeptStateEnvelope envelope) {
    return envelope.activeRecords
        .map(_mapToFavoriteItem)
        .toList(growable: false);
  }

  /// Maps one [KeptRecord] to its Build 25-compatible [FavoriteItem] shape.
  /// Preserves envelope order — callers/screens remain responsible for any
  /// display-order reversal, exactly as `SavedReflectionsScreen` already
  /// does for `SavedReflectionsService.load()`'s output.
  FavoriteItem _mapToFavoriteItem(KeptRecord record) {
    return FavoriteItem(
      id: record.id,
      revealId: record.revealId,
      text: record.wisdomText,
      date: formatFavoriteDisplayDate(record.keptAt.toLocal()),
      reflection: record.reflectionText,
      reflectedAt: record.reflectedAt?.toIso8601String(),
      keptAt: record.keptAt.toIso8601String(),
      wisdomId: record.wisdomId,
    );
  }
}
