import '../persistence/storage_preferences_adapter.dart';

/// Item 6 — Save -> Kept micro-guidance.
///
/// Tracks how many times the one-time "Keep this wisdom." -> "Kept."
/// discovery hint has actually been *shown* (not merely eligible), and
/// whether the user has *completed* it by successfully saving a wisdom
/// through it. Backed only by the existing SharedPreferences
/// infrastructure via [StoragePreferencesAdapter] — no new package, no
/// migration, no analytics, no state transmission.
///
/// Mirrors the in-memory fast-path/durable-fallback pattern already used by
/// `WisdomNotificationService`'s prompt-handled tracking: once a value is
/// known in this process, it is trusted for the remainder of the process
/// even if the underlying persisted write later fails, so a persistence
/// failure can never cause the hint to reappear after the user has already
/// completed it in the current session, and can never block the save
/// itself.
class KeptDiscoveryHintService {
  KeptDiscoveryHintService({StoragePreferencesAdapter? storage})
      : _storage = storage ?? StoragePreferencesAdapter();

  static const String hintCountKey = 'kept_discovery_hint_count';
  static const String completedKey = 'kept_discovery_completed';

  /// P13: persisted the moment the central "Keep this wisdom." first-use
  /// discovery is actually presented for the first (and only) time it is
  /// ever eligible to appear (the very first completed ritual). Read back
  /// on cold start so a killed/relaunched app resumes showing it against
  /// the same still-revealed, still-unkept wisdom rather than silently
  /// losing the in-memory "currently showing" state -- see
  /// [KeptDiscoveryHintService] class doc and `home_screen.dart`'s
  /// `_resumePersistedDiscoveryStateIfNeeded`. Superseded by [completedKey]
  /// once the user actually saves; never read once that is true.
  static const String centralDiscoveryPendingKey = 'kept_discovery_pending';

  /// P13: persisted the moment the user completes the central discovery by
  /// saving their first wisdom -- marks the *second* phase (teaching where
  /// Kept lives, via the top-right control's discovery breathing) as
  /// pending until the user actually opens Kept. Deliberately a separate
  /// flag from [completedKey]: completing the central "how to Keep"
  /// discovery and completing the "where Kept lives" discovery are two
  /// distinct moments (see `home_screen.dart`'s
  /// `_onWisdomSuccessfullyKept`/`openFavorites`).
  static const String keptNavDiscoveryPendingKey = 'kept_nav_discovery_pending';

  /// P13: permanently true once the user has opened Kept via the top-right
  /// discovery flow at least once. Never re-checked or reset afterward --
  /// this first-use training sequence never automatically replays.
  static const String keptNavDiscoveryCompletedKey =
      'kept_nav_discovery_completed';

  /// The hint is shown at most twice, ever: once on the first eligible
  /// revealed wisdom, and once more on a later daily reveal if the user did
  /// not save through it the first time.
  static const int maximumDisplayCount = 2;

  final StoragePreferencesAdapter _storage;

  bool? _completedInMemory;
  int? _displayCountInMemory;
  bool? _centralPendingInMemory;
  bool? _navPendingInMemory;
  bool? _navCompletedInMemory;

  /// Missing persisted value defaults to `false` (not completed).
  Future<bool> isCompleted() async {
    if (_completedInMemory == true) return true;
    try {
      final stored = await _storage.getBool(completedKey) ?? false;
      _completedInMemory ??= stored;
      return stored;
    } catch (_) {
      return _completedInMemory ?? false;
    }
  }

  /// Missing persisted value defaults to `0`.
  Future<int> displayCount() async {
    if (_displayCountInMemory != null) return _displayCountInMemory!;
    try {
      final stored = await _storage.getInt(hintCountKey) ?? 0;
      _displayCountInMemory = stored;
      return stored;
    } catch (_) {
      return _displayCountInMemory ?? 0;
    }
  }

  /// True only when the discovery experience has not yet been completed
  /// and the actual-display count has not reached [maximumDisplayCount].
  Future<bool> isEligible() async {
    if (await isCompleted()) return false;
    return (await displayCount()) < maximumDisplayCount;
  }

  /// Records one actual visible presentation of the hint text. Must be
  /// called only when the hint truly became visible to the user, never for
  /// a mere eligibility check. A persistence failure is non-critical and is
  /// swallowed: the in-memory count still prevents over-display for the
  /// rest of this process.
  Future<void> recordDisplayShown() async {
    final current = await displayCount();
    final next = current + 1;
    _displayCountInMemory = next;
    try {
      await _storage.setInt(hintCountKey, next);
    } catch (_) {
      // Non-critical: see class doc comment.
    }
  }

  /// Marks the discovery experience permanently complete. Must be called
  /// only immediately after a save that succeeded through this hint. A
  /// write failure here must never block or undo the save itself; it is
  /// swallowed and the in-memory flag alone prevents the hint from
  /// reappearing for the remainder of this process.
  Future<void> markCompleted() async {
    _completedInMemory = true;
    try {
      await _storage.setBool(completedKey, true);
    } catch (_) {
      // Non-critical: see class doc comment.
    }
  }

  /// Missing persisted value defaults to `false` -- correct both for a
  /// genuinely fresh install and for an existing install that predates P13
  /// (this key never existed before, so it is simply never true for them).
  Future<bool> isCentralDiscoveryPending() async {
    if (_centralPendingInMemory == true) return true;
    try {
      final stored =
          await _storage.getBool(centralDiscoveryPendingKey) ?? false;
      _centralPendingInMemory ??= stored;
      return stored;
    } catch (_) {
      return _centralPendingInMemory ?? false;
    }
  }

  /// Records that the central "Keep this wisdom." discovery has actually
  /// been presented, so a killed/relaunched app can resume it. A write
  /// failure is non-critical and swallowed, matching every other method on
  /// this class.
  Future<void> markCentralDiscoveryPending() async {
    _centralPendingInMemory = true;
    try {
      await _storage.setBool(centralDiscoveryPendingKey, true);
    } catch (_) {
      // Non-critical: see class doc comment.
    }
  }

  /// Missing persisted value defaults to `false`.
  Future<bool> isNavDiscoveryCompleted() async {
    if (_navCompletedInMemory == true) return true;
    try {
      final stored =
          await _storage.getBool(keptNavDiscoveryCompletedKey) ?? false;
      _navCompletedInMemory ??= stored;
      return stored;
    } catch (_) {
      return _navCompletedInMemory ?? false;
    }
  }

  /// Missing persisted value defaults to `false`.
  Future<bool> isNavDiscoveryPending() async {
    if (_navPendingInMemory == true) return true;
    try {
      final stored =
          await _storage.getBool(keptNavDiscoveryPendingKey) ?? false;
      _navPendingInMemory ??= stored;
      return stored;
    } catch (_) {
      return _navPendingInMemory ?? false;
    }
  }

  /// Marks the top-right Kept-navigation discovery pending -- called once,
  /// right after the save that completes the central discovery for the
  /// first time. A write failure is non-critical and swallowed; the
  /// in-memory flag alone drives the discovery animation for the rest of
  /// this process.
  Future<void> markNavDiscoveryPending() async {
    _navPendingInMemory = true;
    try {
      await _storage.setBool(keptNavDiscoveryPendingKey, true);
    } catch (_) {
      // Non-critical: see class doc comment.
    }
  }

  /// Marks the top-right Kept-navigation discovery permanently complete --
  /// called only once the user has actually opened Kept via that control.
  /// This first-use training sequence never automatically replays after
  /// this. A write failure is non-critical and swallowed; the in-memory
  /// flag alone prevents replay for the rest of this process.
  Future<void> markNavDiscoveryCompleted() async {
    _navCompletedInMemory = true;
    _navPendingInMemory = false;
    try {
      await _storage.setBool(keptNavDiscoveryCompletedKey, true);
      await _storage.setBool(keptNavDiscoveryPendingKey, false);
    } catch (_) {
      // Non-critical: see class doc comment.
    }
  }
}
