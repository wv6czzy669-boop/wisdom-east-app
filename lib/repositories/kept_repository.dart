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

/// Additive, fully isolated Phase 3D-B Kept repository.
///
/// Not yet used by production: nothing in `app_services.dart`, `main.dart`,
/// or any screen constructs or calls this class. It exists so later phases
/// can migrate `SavedReflectionsService`'s callers onto it deliberately,
/// one call site at a time, instead of switching all production Kept
/// reads/writes over in one step.
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
    required DateTime revealedAt,
    required bool isKeeper,
  }) {
    return _coordinator.runExclusive<KeptRepositoryMutationResult>(
      resourceKey: resourceKey,
      operation: () async {
        _requireReady();

        if (!isCanonicalUuidV4(revealId)) {
          throw const KeptRepositoryException(
            'invalid-reveal-id',
            'keepOccurrence requires a canonical UUID v4 revealId.',
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

        if (!isKeeper && envelope.activeRecords.length >= freeKeptLimit) {
          return KeptRepositoryMutationResult(
            items: _mapAll(envelope),
            limitReached: true,
          );
        }

        final id = _generateId();
        final mutationId = _generateId();
        // Canonicalized before ever reaching a KeptRecord: both the
        // caller-supplied authoritative revealedAt and this freshly-read
        // clock value may carry non-zero microseconds (a real device clock
        // routinely does) — see kept_timestamp_canonicalizer.dart for why
        // that would otherwise make this record fail its own protected
        // store's mandatory post-write read-back verification.
        final canonicalRevealedAt = canonicalizeKeptTimestamp(revealedAt);
        final keptAt = canonicalizeKeptTimestamp(_clock());

        final record = KeptRecord(
          id: id,
          revealId: revealId,
          wisdomText: wisdomText,
          revealedAt: canonicalRevealedAt,
          keptAt: keptAt,
          updatedAt: keptAt,
          mutationId: mutationId,
        );

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
        if (isFirstReflection &&
            !isKeeper &&
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
        final updated = existing.copyWith(
          reflectionText: normalized,
          reflectedAt: mutationTime,
          updatedAt: mutationTime,
          mutationId: _generateId(),
        );

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

  Future<List<FavoriteItem>> deleteReflection({required String itemId}) {
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

        final updated = existing.copyWith(
          clearReflection: true,
          updatedAt: canonicalizeKeptTimestamp(_clock()),
          mutationId: _generateId(),
        );

        final nextEnvelope = envelope.copyWith(
          activeRecords: _replacingAt(envelope.activeRecords, index, updated),
        );
        await _replaceEnvelope(nextEnvelope);

        return _mapAll(nextEnvelope);
      },
    );
  }

  Future<RemovedKeptOccurrence?> remove({required String itemId}) {
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

  String _generateId() {
    final id = _idFactory();
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
    );
  }
}
