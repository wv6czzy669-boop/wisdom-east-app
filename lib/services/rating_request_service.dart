import 'package:in_app_review/in_app_review.dart';

import '../persistence/storage_preferences_adapter.dart';

/// Wraps Apple's native `SKStoreReviewController` (via `in_app_review`, which
/// calls it directly with no custom UI of its own). A thin seam only —
/// [RatingRequestService] owns every eligibility/repeat-request decision.
abstract interface class RatingRequestPlatform {
  Future<void> requestReview();
}

class StoreKitRatingRequestPlatform implements RatingRequestPlatform {
  const StoreKitRatingRequestPlatform();

  @override
  Future<void> requestReview() {
    return InAppReview.instance.requestReview();
  }
}

/// EAST. Phase 6 — App Store rating request.
///
/// Eligibility begins only once [eligibleCompletedRitualCount] rituals have
/// each been successfully, durably completed (never an interrupted or
/// still-retrying reveal — see [recordCompletedRitual]'s own doc comment).
/// From that point on, [maybeRequestReview] attempts Apple's native prompt
/// at most once, ever — identical for Free and Keeper, with no positive-
/// rating filtering and no custom dialog of its own. A native failure (or a
/// local persistence failure) is always swallowed; it never surfaces, never
/// retries within the same call, and never affects the ritual.
class RatingRequestService {
  RatingRequestService({
    RatingRequestPlatform? platform,
    StoragePreferencesAdapter? preferencesAdapter,
  })  : _platform = platform ?? const StoreKitRatingRequestPlatform(),
        _preferencesAdapter = preferencesAdapter ?? StoragePreferencesAdapter();

  static const int eligibleCompletedRitualCount = 4;
  static const String completedRitualCountKey =
      'east_rating_completed_ritual_count';
  static const String requestAttemptedKey = 'east_rating_request_attempted';

  final RatingRequestPlatform _platform;
  final StoragePreferencesAdapter _preferencesAdapter;

  bool _requestAttemptedInMemory = false;

  /// Records one successfully, durably completed ritual. Callers must only
  /// invoke this once the reveal it represents is actually committed —
  /// never for a ritual that was abandoned mid-flow or a reveal that is
  /// still waiting on a persistence retry. Idempotent no-op once a request
  /// has already been attempted; any persistence failure is swallowed so it
  /// can never affect the ritual that just completed.
  ///
  /// Returns the 1-based ordinal of the ritual just recorded (`1` for the
  /// very first one this device has ever durably completed, `2` for the
  /// second, and so on) — EAST's one authoritative "genuinely completed
  /// ritual" counter, reused by `home_screen.dart`'s P13 first/second-
  /// ritual gating rather than introducing a second, competing counter.
  /// Returns `null` when the ordinal could not be determined (a rating
  /// request has already been attempted, so this counter has stopped
  /// advancing, or the read/write itself failed) — callers must treat
  /// `null` exactly like "not the first or second ritual" (fall back to
  /// existing, unmodified behavior), never as "definitely the first."
  Future<int?> recordCompletedRitual() async {
    if (_requestAttemptedInMemory) return null;
    try {
      if (await _hasAttemptedRequest()) return null;
      final count = await _preferencesAdapter
              .getInt(completedRitualCountKey) ??
          0;
      final next = count + 1;
      await _preferencesAdapter.setInt(completedRitualCountKey, next);
      return next;
    } catch (_) {
      // Local bookkeeping is best-effort only.
      return null;
    }
  }

  /// Attempts Apple's native in-app rating request exactly once, the first
  /// time this is called after eligibility is reached. Safe to call from
  /// any settled, non-interrupting moment (app launch, resume) — every call
  /// before eligibility, and every call after the one real attempt,
  /// including one that failed, is a no-op.
  Future<void> maybeRequestReview() async {
    if (_requestAttemptedInMemory) return;
    try {
      if (await _hasAttemptedRequest()) return;
      final count =
          await _preferencesAdapter.getInt(completedRitualCountKey) ?? 0;
      if (count < eligibleCompletedRitualCount) return;

      // Claimed before the native call so a native failure (or the app
      // being killed mid-request) never causes a retry.
      _requestAttemptedInMemory = true;
      await _preferencesAdapter.setBool(requestAttemptedKey, true);
      await _platform.requestReview();
    } catch (_) {
      // The native rating prompt is always optional and must never affect
      // app usability.
    }
  }

  Future<bool> _hasAttemptedRequest() async {
    if (_requestAttemptedInMemory) return true;
    final attempted =
        await _preferencesAdapter.getBool(requestAttemptedKey) ?? false;
    if (attempted) _requestAttemptedInMemory = true;
    return attempted;
  }
}
