import 'package:uuid/uuid.dart';

/// Build 26 Phase 3D-E (safety-gap correction): the exact namespaced name
/// `KeptMigrationCoordinator._convertToKeptRecord` derives a migrated
/// [KeptRecord]'s `revealId` from, given the original legacy
/// `FavoriteItem.id` it was migrated from.
///
/// Defined exactly once and shared by both sides that must agree on this
/// value — `KeptMigrationCoordinator` (which mints it at migration time) and
/// `KeptRepository.resolveLegacyMigratedRevealIdForOccurrence` (which
/// re-derives it to prove a candidate record actually came from that
/// migration, never merely that its text/day happen to match) — so the two
/// can never silently drift apart. This is the same defect class (two
/// independently-computed values for what should be one identity) that made
/// the reconciliation fix necessary in the first place; the derivation
/// itself must not repeat it.
String legacyMigrationRevealIdName(String legacyItemId) =>
    'com.dogukan.dailywisdom/build25/reveal/$legacyItemId';

/// Derives the deterministic migrated-[KeptRecord] `revealId` for
/// [legacyItemId].
///
/// [uuidV5Factory] defaults to the real UUID v5 algorithm over the standard
/// URL namespace — the exact same default `KeptMigrationCoordinator` itself
/// falls back to when its own `uuidV5Factory` constructor parameter is not
/// overridden, which is always the case in production. That constructor
/// parameter exists solely so one pre-existing coordinator test
/// (`kept_migration_coordinator_test.dart`, "a duplicate reveal ID
/// (different record IDs) blocks and retains the legacy key") can force two
/// different legacy ids to collide on the same revealId, to test the
/// coordinator's own duplicate-identity-conflict handling in isolation.
/// `KeptRepository` has no such test-only need and no reason to accept an
/// injected factory: its provenance gate always uses the real derivation,
/// matching what any actual physical-device migration always produces.
String deriveLegacyMigrationRevealId(
  String legacyItemId, {
  String Function(String name)? uuidV5Factory,
}) {
  final factory =
      uuidV5Factory ?? (name) => const Uuid().v5(Namespace.url.value, name);
  return factory(legacyMigrationRevealIdName(legacyItemId));
}

/// The proven outcome of parsing a Build 25 `sr-v1-<...>` legacy id via
/// [parseLegacySavedReflectionId].
class LegacySavedReflectionIdInfo {
  const LegacySavedReflectionIdInfo({required this.savedAt});

  /// The exact instant `SavedReflectionsService._createId()` embedded in
  /// this id at the moment the legacy item was first Kept — a genuine,
  /// timezone-independent Unix epoch instant, tagged UTC (an exact
  /// re-expression of the same absolute instant, never a reinterpretation
  /// through any device's timezone).
  final DateTime savedAt;
}

/// Matches exactly the Build 25 `SavedReflectionsService._createId()`
/// format. Confirmed from that method's own source (present in this
/// repository's history prior to the Build 26 `KeptRepository` cutover,
/// commit `046dd36` "Complete protected Kept storage cutover" —
/// `lib/services/saved_reflections_service.dart`, `_createId()`):
///
/// ```dart
/// String _createId() {
///   final now = DateTime.now().microsecondsSinceEpoch;
///   final serial = _generatedIdSerial++;
///   return 'sr-v1-$now-$serial';
/// }
/// ```
///
/// `now` is `DateTime.now().microsecondsSinceEpoch` — `DateTime.now()`
/// itself returns a device-local-flagged value, but `.microsecondsSinceEpoch`
/// is always the absolute Unix epoch microsecond count of that instant,
/// identical regardless of the device's timezone at the moment the item was
/// Kept. This is therefore a genuine, timezone-independent save instant —
/// unlike every other legacy timestamp this migration handles
/// (`FavoriteItem.date`/`reflectedAt`, both opaque display/wall-clock
/// strings with no reliable timezone reference of their own, handled by
/// `FavoriteDateCodec` instead). `serial` is an in-memory-only monotonic
/// counter reset to 0 on every app launch (never persisted, never a
/// timestamp) — present in the format but never itself load-bearing here,
/// beyond confirming the id's overall shape.
///
/// Two other id shapes can also reach migration and must never be parsed as
/// this format — both are content-derived, never time-derived, and this
/// function correctly returns `null` for both:
///
/// - `legacy-v1-<index>-<stable hash>`
///   (`StoredFavoriteEntryCodec.fallbackIdFor`) — assigned to any stored
///   entry with no explicit id at all (a current-schema entry missing its
///   `id` key, or any legacy pipe-format entry, which never carried one).
/// - `duplicate-v1-<index>-<stable hash>`
///   (`SavedReflectionsService._duplicateIdFor`) — assigned, at the moment
///   of an original Build 25 save, to whichever of two entries that decoded
///   to the same id was encountered second.
///
/// Returns `null` for anything not exactly matching `sr-v1-<digits>-<digits>`
/// (including a non-numeric, empty, or negative-looking microsecond
/// component) — including both shapes above, and any other malformed or
/// unsupported id. Never guesses, never falls back to text/date.
LegacySavedReflectionIdInfo? parseLegacySavedReflectionId(String id) {
  final match = _srV1Pattern.firstMatch(id);
  if (match == null) return null;

  final micros = int.tryParse(match.group(1)!);
  if (micros == null || micros < 0) return null;

  return LegacySavedReflectionIdInfo(
    savedAt: DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true),
  );
}

/// `sr-v1-<microseconds>-<serial>`, both components plain non-negative
/// decimal digit sequences with no sign, no decimal point, and no other
/// separator — anchored at both ends so trailing/leading content of any
/// kind is rejected rather than silently ignored.
final RegExp _srV1Pattern = RegExp(r'^sr-v1-(\d+)-\d+$');
