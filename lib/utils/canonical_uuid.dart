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
/// only (stricter than [isCanonicalUuidV4OrV5]) — used where a genuine
/// Build 26-native identity is required and a migration-only version 5
/// identity must be rejected (for example `KeptRepository.keepOccurrence`'s
/// `revealId` parameter).
bool isCanonicalUuidV4(String value) {
  return _canonicalUuidV4Pattern.hasMatch(value);
}
