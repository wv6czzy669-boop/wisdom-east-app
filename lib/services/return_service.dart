import 'dart:convert';

import '../models/favorite_item.dart';
import '../persistence/storage_preferences_adapter.dart';

/// EAST. Phase 9 — Return's own device-local scheduling state.
///
/// [history] maps a Kept occurrence's `revealId` to the instant it was most
/// recently *selected* as a Return (not merely viewed) — the sole record
/// [ReturnService] needs to enforce the 90-day repeat gap. Deliberately
/// never keyed or compared by wisdom text.
class ReturnState {
  const ReturnState({
    this.currentRevealId,
    this.currentSelectedAt,
    this.history = const {},
    this.anniversaryDate,
    this.anniversaryRevealId,
  });

  final String? currentRevealId;
  final DateTime? currentSelectedAt;
  final Map<String, DateTime> history;

  /// Anniversary-priority repair: a deliberately SEPARATE pair of fields
  /// from [currentRevealId]/[currentSelectedAt] above -- never read or
  /// written by the normal 7-day-cadence rotation logic in
  /// [ReturnService.resolveCurrentReturn], so an anniversary surfacing can
  /// never reset, extend, shorten, or consume that cadence, and can never
  /// overwrite the normal pinned selection underneath it.
  ///
  /// [anniversaryDate] is the local calendar day (`yyyy-MM-dd`) an
  /// anniversary occurrence was last surfaced on; [anniversaryRevealId] is
  /// that occurrence's identity. Together they exist purely so reopening
  /// Return on the *same* calendar day replays the same occurrence instead
  /// of rerolling -- nothing more.
  final String? anniversaryDate;
  final String? anniversaryRevealId;

  ReturnState withAnniversary({
    required String anniversaryDate,
    required String anniversaryRevealId,
  }) {
    return ReturnState(
      currentRevealId: currentRevealId,
      currentSelectedAt: currentSelectedAt,
      history: history,
      anniversaryDate: anniversaryDate,
      anniversaryRevealId: anniversaryRevealId,
    );
  }

  String encode() {
    return jsonEncode({
      if (currentRevealId != null) 'currentRevealId': currentRevealId,
      if (currentSelectedAt != null)
        'currentSelectedAt': currentSelectedAt!.toIso8601String(),
      'history': history.map(
        (revealId, at) => MapEntry(revealId, at.toIso8601String()),
      ),
      if (anniversaryDate != null) 'anniversaryDate': anniversaryDate,
      if (anniversaryRevealId != null)
        'anniversaryRevealId': anniversaryRevealId,
    });
  }

  static ReturnState decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const ReturnState();

      final rawCurrentRevealId = decoded['currentRevealId'];
      final rawCurrentSelectedAt = decoded['currentSelectedAt'];
      final rawHistory = decoded['history'];
      final rawAnniversaryDate = decoded['anniversaryDate'];
      final rawAnniversaryRevealId = decoded['anniversaryRevealId'];

      final history = <String, DateTime>{};
      if (rawHistory is Map) {
        for (final entry in rawHistory.entries) {
          final revealId = entry.key;
          final at = entry.value;
          if (revealId is String && at is String) {
            final parsed = DateTime.tryParse(at);
            if (parsed != null) history[revealId] = parsed;
          }
        }
      }

      return ReturnState(
        currentRevealId:
            rawCurrentRevealId is String ? rawCurrentRevealId : null,
        currentSelectedAt: rawCurrentSelectedAt is String
            ? DateTime.tryParse(rawCurrentSelectedAt)
            : null,
        history: history,
        anniversaryDate:
            rawAnniversaryDate is String ? rawAnniversaryDate : null,
        anniversaryRevealId:
            rawAnniversaryRevealId is String ? rawAnniversaryRevealId : null,
      );
    } catch (_) {
      // Corrupt/unreadable state recovers to "nothing selected yet" —
      // exactly the same fail-safe posture as every other locally
      // persisted, non-authoritative EAST scheduling record.
      return const ReturnState();
    }
  }
}

/// EAST. Phase 9 — Return: quietly resurfaces one older Kept occurrence.
///
/// Owns exactly the local scheduling state described in [ReturnState] —
/// never the Kept/Reflection content itself, which continues to live
/// entirely in [KeptRepository](../repositories/kept_repository.dart) via
/// the existing [FavoriteItem] read model. Selection is keyed only by
/// `revealId`; wisdom text is never used as identity or for deduplication,
/// so two occurrences that happen to share identical wisdom text remain
/// fully independent.
///
/// [resolveCurrentReturn] is the single entry point: it is safe (and
/// intended) to call on every Kept screen load — it never rerolls an
/// already-pinned, still-current selection, and it persists a freshly
/// chosen selection *before* returning it, so presentation can never race
/// ahead of durability. A local persistence failure of any kind is
/// swallowed and resolves to "no Return available" — Return is always
/// optional, ambient product state; it must never surface an error or
/// affect Kept/Reflection/ritual usability.
class ReturnService {
  ReturnService({
    StoragePreferencesAdapter? preferencesAdapter,
    DateTime Function()? clock,
  })  : _preferencesAdapter = preferencesAdapter ?? StoragePreferencesAdapter(),
        _clock = clock ?? DateTime.now;

  static const String stateKey = 'east_return_state_v1';

  /// A Kept occurrence must be at least this old (since it was added to
  /// Kept — see [FavoriteItem.keptAt]) before it can participate at all.
  static const Duration eligibilityAge = Duration(days: 14);

  /// At most one *new* Return selection may be made within this window of
  /// the previous selection.
  static const Duration newSelectionCadence = Duration(days: 7);

  /// An occurrence already selected as a Return cannot be selected again
  /// until at least this long has passed since that selection.
  static const Duration repeatProtectionGap = Duration(days: 90);

  final StoragePreferencesAdapter _preferencesAdapter;
  final DateTime Function() _clock;

  /// Resolves which [FavoriteItem] (if any) Return currently points at,
  /// among [items] — the same list [SavedReflectionsService.load] already
  /// returns. Returns `null` exactly when Return must not appear at all
  /// (see the class doc comment and each branch below for why).
  Future<FavoriteItem?> resolveCurrentReturn(List<FavoriteItem> items) async {
    try {
      final now = _clock();
      final byRevealId = <String, FavoriteItem>{
        for (final item in items)
          if (item.revealId != null) item.revealId!: item,
      };
      final eligible = items
          .where((item) => item.revealId != null && _isEligible(item, now))
          .toList(growable: false);

      final state = ReturnState.decode(
        await _preferencesAdapter.getString(stateKey) ?? '',
      );

      // Anniversary priority (see the class doc comment's own section):
      // checked first, entirely independent of the normal pinned-selection
      // machinery below. A valid, non-90-day-blocked anniversary occurrence
      // is returned directly, without ever reading or writing
      // `currentRevealId`/`currentSelectedAt` -- the normal current Return
      // (if any) is left completely untouched underneath it. Returns
      // `null` when there is no valid anniversary today, in which case
      // resolution falls through to the unchanged normal logic below.
      final anniversaryItem = await _resolveAnniversaryPriority(
        items: items,
        state: state,
        now: now,
      );
      if (anniversaryItem != null) {
        return anniversaryItem;
      }

      final pinnedItem = state.currentRevealId == null
          ? null
          : byRevealId[state.currentRevealId];
      final pinnedStillWithinCadence = state.currentSelectedAt != null &&
          now.isBefore(state.currentSelectedAt!.add(newSelectionCadence));

      // Rule 3/4: a still-current, still-existing pinned selection is never
      // rerolled — reopening, rebuilding, relaunching, or backgrounding all
      // resolve here identically, with no write at all.
      if (pinnedItem != null && pinnedStillWithinCadence) {
        return pinnedItem;
      }

      if (eligible.isEmpty) {
        // Nothing currently eligible to select from -- but a pinned
        // selection whose occurrence still exists remains showable even
        // past its own cadence window (Rule: "keep the current Return
        // accessible if one exists" when no valid new candidate exists).
        return pinnedItem;
      }

      final candidate = _selectNewCandidate(eligible, state.history, now);
      if (candidate == null) {
        // A 7-day cadence elapsed (or nothing was pinned yet), but every
        // eligible occurrence is still inside its own 90-day repeat gap --
        // never manufacture a repeat; keep whatever was already pinned.
        return pinnedItem;
      }

      final nextHistory = Map<String, DateTime>.from(state.history)
        ..[candidate.revealId!] = now;
      // Persisted before this method returns -- presentation can never
      // observe a selection that was not already durable.
      await _preferencesAdapter.setString(
        stateKey,
        ReturnState(
          currentRevealId: candidate.revealId,
          currentSelectedAt: now,
          history: nextHistory,
        ).encode(),
      );
      return candidate;
    } catch (_) {
      // Local persistence failures never surface -- Return simply does not
      // appear this time, exactly as if nothing were eligible yet.
      return null;
    }
  }

  /// Visual-polish repair: a read-only presentation derivation, never a
  /// selection decision -- this must never influence, and is never
  /// consulted by, [resolveCurrentReturn]'s own timing/selection algorithm
  /// above. Returns how long remains until a *new* Return selection could
  /// next be made, based purely on the currently persisted
  /// [ReturnState.currentSelectedAt] (the exact same field
  /// [resolveCurrentReturn] already reads/writes). `null` means nothing has
  /// ever been selected yet, or the persisted state could not be read.
  /// Never negative -- a fully elapsed cadence window reports
  /// [Duration.zero], never a negative duration.
  Future<Duration?> cadenceRemaining() async {
    try {
      final state = ReturnState.decode(
        await _preferencesAdapter.getString(stateKey) ?? '',
      );
      final selectedAt = state.currentSelectedAt;
      if (selectedAt == null) return null;

      final remaining =
          selectedAt.add(newSelectionCadence).difference(_clock());
      return remaining.isNegative ? Duration.zero : remaining;
    } catch (_) {
      return null;
    }
  }

  /// Anniversary priority. Resolves and, if a fresh selection was made,
  /// durably persists (state fields entirely separate from the normal
  /// rotation's own -- see [ReturnState.withAnniversary]) which occurrence
  /// (if any) should be shown today because today is its genuine calendar
  /// anniversary. `null` means "no anniversary applies today" -- the
  /// caller then proceeds exactly as if this method did not exist.
  Future<FavoriteItem?> _resolveAnniversaryPriority({
    required List<FavoriteItem> items,
    required ReturnState state,
    required DateTime now,
  }) async {
    final today = _localCalendarDate(now);

    // Same calendar day as an already-surfaced anniversary: replay it
    // verbatim -- reopening Return today must never reroll.
    if (state.anniversaryDate == today && state.anniversaryRevealId != null) {
      for (final item in items) {
        if (item.revealId == state.anniversaryRevealId) return item;
      }
      // The previously surfaced occurrence no longer exists among `items`
      // (e.g. removed from Kept since) -- fall through to a fresh pick.
    }

    final candidate = _selectAnniversaryCandidate(items, state.history, now);
    if (candidate == null) return null;

    await _preferencesAdapter.setString(
      stateKey,
      state
          .withAnniversary(
            anniversaryDate: today,
            anniversaryRevealId: candidate.revealId!,
          )
          .encode(),
    );
    return candidate;
  }

  /// Every occurrence whose *trustworthy* original date ([_keptAtOf] --
  /// never a legacy record with no such date, which is never guessed into
  /// an anniversary) shares today's local calendar month/day from a
  /// strictly earlier year, and which the existing 90-day repeat-
  /// protection history does not currently block. Ties/multiple matches
  /// prefer the most recent original year, then `revealId` -- deterministic,
  /// never wisdom text, never randomized.
  FavoriteItem? _selectAnniversaryCandidate(
    List<FavoriteItem> items,
    Map<String, DateTime> history,
    DateTime now,
  ) {
    final today = now.toLocal();
    final candidates = <FavoriteItem>[];

    for (final item in items) {
      final revealId = item.revealId;
      if (revealId == null) continue;
      final original = _keptAtOf(item);
      if (original == null) continue;
      if (!_isAnniversaryMatch(original: original.toLocal(), today: today)) {
        continue;
      }

      // Hard rule: the 90-day repeat gap is never bypassed for sentiment.
      final lastReturnedAt = history[revealId];
      if (lastReturnedAt != null &&
          now.isBefore(lastReturnedAt.add(repeatProtectionGap))) {
        continue;
      }

      candidates.add(item);
    }

    if (candidates.isEmpty) return null;

    candidates.sort((a, b) {
      final aYear = _keptAtOf(a)!.toLocal().year;
      final bYear = _keptAtOf(b)!.toLocal().year;
      // Most recent original year first (smallest year-gap).
      final byRecency = bYear.compareTo(aYear);
      return byRecency != 0 ? byRecency : a.revealId!.compareTo(b.revealId!);
    });
    return candidates.first;
  }

  /// `today` must already be in local time (see [_selectAnniversaryCandidate]).
  /// A February 29 original date maps to February 28 in a non-leap
  /// anniversary year -- deterministic, and never also matches March 1 in
  /// that same year (no duplicate anniversary opportunity).
  bool _isAnniversaryMatch({
    required DateTime original,
    required DateTime today,
  }) {
    if (original.year >= today.year) return false;

    var anniversaryDay = original.day;
    if (original.month == 2 && original.day == 29 && !_isLeapYear(today.year)) {
      anniversaryDay = 28;
    }
    return today.month == original.month && today.day == anniversaryDay;
  }

  bool _isLeapYear(int year) {
    return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
  }

  String _localCalendarDate(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  bool _isEligible(FavoriteItem item, DateTime now) {
    final keptAt = _keptAtOf(item);
    if (keptAt == null) return false;
    return !now.isBefore(keptAt.add(eligibilityAge));
  }

  DateTime? _keptAtOf(FavoriteItem item) {
    final raw = item.keptAt;
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  /// Selection priority (see the class doc comment):
  /// A/B — prefer eligible occurrences never previously selected, oldest
  /// [FavoriteItem.keptAt] first (deterministic, no randomness);
  /// C/D — only once every eligible occurrence has already been returned,
  /// fall back to previously-returned candidates whose 90-day gap has
  /// expired, least-recently-returned first. Ties within either pool break
  /// on `revealId` itself, purely for full determinism -- never on wisdom
  /// text.
  FavoriteItem? _selectNewCandidate(
    List<FavoriteItem> eligible,
    Map<String, DateTime> history,
    DateTime now,
  ) {
    final neverReturned = eligible
        .where((item) => !history.containsKey(item.revealId))
        .toList(growable: false);

    if (neverReturned.isNotEmpty) {
      final pool = List<FavoriteItem>.from(neverReturned);
      pool.sort((a, b) {
        final aKeptAt = _keptAtOf(a)!;
        final bKeptAt = _keptAtOf(b)!;
        final byAge = aKeptAt.compareTo(bKeptAt);
        return byAge != 0 ? byAge : a.revealId!.compareTo(b.revealId!);
      });
      return pool.first;
    }

    final repeatEligible = eligible.where((item) {
      final lastReturnedAt = history[item.revealId];
      return lastReturnedAt != null &&
          !now.isBefore(lastReturnedAt.add(repeatProtectionGap));
    }).toList(growable: false);

    if (repeatEligible.isEmpty) return null;

    final pool = List<FavoriteItem>.from(repeatEligible);
    pool.sort((a, b) {
      final byLastReturned =
          history[a.revealId]!.compareTo(history[b.revealId]!);
      return byLastReturned != 0
          ? byLastReturned
          : a.revealId!.compareTo(b.revealId!);
    });
    return pool.first;
  }
}
