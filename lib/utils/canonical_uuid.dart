/// Canonical RFC 4122 UUID shape checks, narrowly scoped to the two UUID
/// versions this codebase actually produces or accepts: version 4 (every
/// genuine Build 26-native identity, minted via `Uuid().v4()`) and version 5
/// (deterministic, namespace-derived identity produced only during Build 25
/// legacy migration). Any other version, an invalid variant nibble, braces,
/// surrounding whitespace, missing hyphens, or any other malformed shape is
/// rejected.
///
/// Extracted as one shared, narrow utility specifically so this identity
/// shape is defined exactly once and reused everywhere it is genuinely
/// needed (currently [KeptRecord]'s `revealId`/`mutationId` validation and
/// `FavoriteItem`'s compatibility `revealId` validation), rather than
/// duplicated with subtly different rules per call site.
///
/// This is deliberately not a general-purpose UUID library: it does not
/// validate version 1/2/3, nil UUIDs, or non-canonical (braced/urn-prefixed)
/// forms, since nothing in this codebase produces or accepts those shapes.
library;

final RegExp _canonicalUuidV4OrV5Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[45][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

final RegExp _canonicalUuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// Returns whether [value] is an exact, canonical UUID version 4 or version
/// 5 string (no surrounding whitespace, no wrong-version or wrong-variant
/// nibble).
bool isCanonicalUuidV4OrV5(String value) {
  return _canonicalUuidV4OrV5Pattern.hasMatch(value);
}

/// Returns whether [value] is an exact, canonical UUID version 4 string
/// only (stricter than [isCanonicalUuidV4OrV5]) — used specifically where a
/// freshly self-generated identity (an `id`/`mutationId` minted by this
/// codebase's own id factory, never a value accepted from elsewhere) must
/// be proven to be a genuine, newly-minted v4 and never any other shape.
bool isCanonicalUuidV4(String value) {
  return _canonicalUuidV4Pattern.hasMatch(value);
}

/// Build 26 Phase 3D-E (safety-gap correction, round 4): the migration-aware
/// acceptance policy for `revealId` fields specifically —
/// `DailyWisdomRecord.revealId`, `KeptRecord.revealId`, and
/// `FavoriteItem.revealId`.
///
/// A `revealId` may legitimately be either shape this codebase ever
/// produces for it: a genuine Build 26-native identity (canonical UUID v4,
/// minted by `Uuid().v4()`) or a deterministic migrated Build 25 identity
/// (canonical UUID v5, minted once by `KeptMigrationCoordinator` and later
/// adopted onto the Daily Access side by
/// `DailyAccessRepository.reconcileRevealIdForOccurrence`). Today this is
/// the same shape check as [isCanonicalUuidV4OrV5] — but named and used
/// separately, specifically for `revealId` fields, so that record `id` and
/// `mutationId` (each validated via [isCanonicalUuidV4] against freshly
/// self-generated values only) can never be accidentally loosened or
/// tightened by a future, unrelated change to this policy, and vice versa.
///
/// A malformed UUID, or a UUID of any version this codebase does not
/// actually produce for a `revealId` (v1/v2/v3/v6/...), remains rejected.
bool isSupportedRevealId(String value) {
  return isCanonicalUuidV4OrV5(value);
}

/// Stable wisdom catalog IDs are validated without importing catalog content
/// into persistence or sync layers.
bool isCanonicalEastWisdomId(String value) {
  return RegExp(
    r'^east_wisdom_(?:0(?:0(?:0[1-9]|[1-9][0-9])|[1-5][0-9]{2})|060[0-3])$',
  ).hasMatch(value);
}
