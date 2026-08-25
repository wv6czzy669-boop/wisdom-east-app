import '../persistence/storage_preferences_adapter.dart';
import 'rating_request_service.dart';

/// Owns the one-time entrance guidance shown during EAST.'s first ritual.
///
/// Existing installs must not receive onboarding again after upgrading. If
/// this feature's own completion key does not exist, the durable completed-
/// ritual count is therefore used as a migration signal: any previously
/// completed ritual permanently suppresses the guidance.
class FirstRitualGuidanceService {
  FirstRitualGuidanceService({StoragePreferencesAdapter? storage})
      : _storage = storage ?? StoragePreferencesAdapter();

  static const String completedKey = 'east_first_ritual_guidance_completed';

  final StoragePreferencesAdapter _storage;
  bool? _shouldShowInMemory;

  Future<bool> shouldShow() async {
    final cached = _shouldShowInMemory;
    if (cached != null) return cached;

    try {
      if (await _storage.getBool(completedKey) == true) {
        _shouldShowInMemory = false;
        return false;
      }

      final completedRituals = await _storage.getInt(
            RatingRequestService.completedRitualCountKey,
          ) ??
          0;
      if (completedRituals > 0) {
        _shouldShowInMemory = false;
        try {
          await _storage.setBool(completedKey, true);
        } catch (_) {
          // The in-memory result still prevents upgrade-time onboarding in
          // this process; a bookkeeping failure never blocks Home.
        }
        return false;
      }

      _shouldShowInMemory = true;
      return true;
    } catch (_) {
      // Fail closed. Optional guidance must never delay Home or repeatedly
      // appear when local bookkeeping is unavailable.
      _shouldShowInMemory = false;
      return false;
    }
  }

  Future<void> markCompleted() async {
    _shouldShowInMemory = false;
    try {
      await _storage.setBool(completedKey, true);
    } catch (_) {
      // Best-effort onboarding bookkeeping must never affect the ritual.
    }
  }
}
