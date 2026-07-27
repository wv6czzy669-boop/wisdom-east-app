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

  /// The hint is shown at most twice, ever: once on the first eligible
  /// revealed wisdom, and once more on a later daily reveal if the user did
  /// not save through it the first time.
  static const int maximumDisplayCount = 2;

  final StoragePreferencesAdapter _storage;

  bool? _completedInMemory;
  int? _displayCountInMemory;

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
}
