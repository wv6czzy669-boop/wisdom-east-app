import '../models/favorite_item.dart';
import '../models/kept_record.dart';
import '../repositories/kept_repository.dart';
import '../sync_integration/kept_sync_integration_coordinator.dart';
import 'analytics_service.dart';

class SavedReflectionsResult {
  const SavedReflectionsResult({
    required this.items,
    required this.limitReached,
    this.reflectionLimitReached = false,
  });

  final List<FavoriteItem> items;
  final bool limitReached;
  final bool reflectionLimitReached;
}

/// Wraps a [RemovedKeptOccurrence] so a caller can later [restore] the exact
/// removed occurrence without losing any protected-domain field a
/// display-only [FavoriteItem] does not carry (in particular
/// [KeptRecord.revealId] and [KeptRecord.keptAt]).
///
/// [items] and [originalIndex] are exposed as pass-through getters so
/// existing callers (`SavedReflectionsScreen._deleteItem`) that only ever
/// read those two fields need no changes.
class RemovedSavedReflection {
  const RemovedSavedReflection({required this.occurrence});

  final RemovedKeptOccurrence occurrence;

  List<FavoriteItem> get items => occurrence.items;
  int get originalIndex => occurrence.originalIndex;
}

/// Build 26 Phase 3D-C production cutover: `SavedReflectionsService` is now
/// a thin, additive-free delegation layer over [KeptRepository] — the
/// actual authoritative protected Kept storage.
///
/// This class no longer touches `SharedPreferences`, the legacy `favorites`
/// key, or migration directly, and holds no storage state of its own; every
/// method here is a direct pass-through to the equivalent [KeptRepository]
/// operation. It exists only so existing callers (`HomeScreen`,
/// `SavedReflectionsScreen`, `ReflectionScreen`) keep their existing
/// method/result shapes (`SavedReflectionsResult`, `RemovedSavedReflection`)
/// without depending on `KeptRepository` types directly.
///
/// **Build 26 Phase 4E-2:** the four real local user mutation paths --
/// [toggle]'s Keep branch, [toggle]'s Remove branch (a non-null
/// `existingId`), [saveReflection], and [deleteReflection] -- now route
/// through [KeptSyncIntegrationCoordinator] instead of calling
/// [KeptRepository] directly, so each one durably records a crash-safe
/// [LocalSyncIntent](../sync_integration/local_sync_intent.dart) before its
/// physical Kept write. Every read path ([load],
/// [resolveLegacyMigratedRevealIdForOccurrence]) and [restore] continue to
/// call [KeptRepository] directly and unchanged -- [restore] has no live UI
/// call site and is deliberately outside this phase's four-operation scope
/// (see the class doc comment on `KeptSyncIntegrationCoordinator`), so it
/// does not create a sync intent. No screen needed to change: every public
/// method here keeps its exact pre-existing signature.
class SavedReflectionsService {
  SavedReflectionsService({
    required KeptRepository keptRepository,
    required KeptSyncIntegrationCoordinator syncCoordinator,
    AnalyticsService? analyticsService,
  })  : _keptRepository = keptRepository,
        _syncCoordinator = syncCoordinator,
        _analyticsService = analyticsService ?? AnalyticsService();

  static const int maximumReflectionLength = KeptRecord.maximumReflectionLength;
  static const int freeReflectionLimit = 3;

  final KeptRepository _keptRepository;
  final KeptSyncIntegrationCoordinator _syncCoordinator;
  final AnalyticsService _analyticsService;

  Future<List<FavoriteItem>> load() => _keptRepository.load();

  /// Keeps a new occurrence identified by [revealId], or removes an already
  /// -kept occurrence identified by [existingId] (the one-way toggle:
  /// removal via this path is retained only for test/back-compat
  /// completeness — `HomeScreen`'s save ring itself never calls this with a
  /// non-null `existingId`, since its own save ring is one-way).
  ///
  /// Build 26 Phase 3D-C compatibility contract (locked): the public
  /// parameter names are [text]/[date]/[isKeeper]/[revealId]/[revealedAt]/
  /// [existingId] — matching the pre-cutover call shape byte-for-byte so
  /// every existing caller/test needs no structural changes beyond the
  /// rename.
  ///
  /// [text] is forwarded as [KeptRepository.keepOccurrence]'s `wisdomText`.
  /// [date] exists for source/API compatibility only: it is never parsed,
  /// never used to derive [revealedAt], and never participates in Kept
  /// identity in any way — it is accepted and otherwise completely ignored.
  /// Identity is [revealId] alone; the authoritative timestamp is
  /// [revealedAt] alone. [existingId] compatibility-removal behavior is
  /// unchanged from before this rename.
  Future<SavedReflectionsResult> toggle({
    required String text,
    required String date,
    required bool isKeeper,
    required String revealId,
    required DateTime revealedAt,
    String? existingId,
  }) async {
    if (existingId != null) {
      final removed = await _syncCoordinator.recordRemove(itemId: existingId);
      final items = removed?.items ?? await _keptRepository.load();
      return SavedReflectionsResult(items: items, limitReached: false);
    }

    final result = await _syncCoordinator.recordKeep(
      revealId: revealId,
      wisdomText: text,
      revealedAt: revealedAt,
      isKeeper: isKeeper,
    );
    // EAST. Phase 7: a genuinely successful Keep -- never a free-limit
    // rejection -- and never for the Remove branch above. No parameter:
    // see AnalyticsService's own doc comment for why none of this method's
    // arguments (revealId, wisdomText, revealedAt) is ever passed through.
    if (!result.limitReached) {
      _analyticsService.keptSaved();
    }
    return SavedReflectionsResult(
      items: result.items,
      limitReached: result.limitReached,
    );
  }

  Future<SavedReflectionsResult> saveReflection({
    required String itemId,
    required String reflection,
    required bool isKeeper,
    DateTime? reflectedAt,
  }) async {
    final result = await _syncCoordinator.recordReflectionSave(
      itemId: itemId,
      reflection: reflection,
      isKeeper: isKeeper,
      reflectedAt: reflectedAt,
    );
    // EAST. Phase 7: a genuinely successful Reflection save -- never a
    // free-limit rejection. No parameter: reflection text never travels
    // through this call.
    if (!result.limitReached && !result.reflectionLimitReached) {
      _analyticsService.reflectionSaved();
    }
    return SavedReflectionsResult(
      items: result.items,
      limitReached: result.limitReached,
      reflectionLimitReached: result.reflectionLimitReached,
    );
  }

  Future<List<FavoriteItem>> deleteReflection({required String itemId}) {
    return _syncCoordinator.recordReflectionDelete(itemId: itemId);
  }

  Future<RemovedSavedReflection?> remove({required String itemId}) async {
    final removed = await _syncCoordinator.recordRemove(itemId: itemId);
    if (removed == null) return null;
    return RemovedSavedReflection(occurrence: removed);
  }

  Future<List<FavoriteItem>> restore(RemovedSavedReflection removed) {
    return _keptRepository.restore(removed.occurrence);
  }

  /// Thin pass-through to
  /// [KeptRepository.resolveLegacyMigratedRevealIdForOccurrence] — see its
  /// doc comment for the full Build 26 Phase 3D-E (round 3) migration-
  /// identity rationale. Read-only: never mutates Kept storage. `HomeScreen`
  /// calls this at startup to discover the migrated Kept revealId (if any)
  /// for the currently committed daily occurrence, then applies the
  /// correction on the Daily Access side via
  /// `DailyWisdomAccessService.reconcileRevealIdForOccurrence` — never here.
  Future<String?> resolveLegacyMigratedRevealIdForOccurrence({
    required String wisdomText,
    required DateTime committedRevealedAt,
    required DateTime committedUnlockAt,
  }) {
    return _keptRepository.resolveLegacyMigratedRevealIdForOccurrence(
      wisdomText: wisdomText,
      committedRevealedAt: committedRevealedAt,
      committedUnlockAt: committedUnlockAt,
    );
  }
}
