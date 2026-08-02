/// Build 26 Phase 4A: deterministic CloudKit identity constants and
/// derivation, per `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md` §2.
///
/// This file intentionally has no dependency on `KeptRecord`, `dart:io`, or
/// any platform channel — it is a pure naming/derivation contract that both
/// the Dart sync domain and (eventually) the native Swift CloudKit
/// implementation must agree on identically (see the design doc §2.2).
library;

import '../utils/canonical_uuid.dart';

/// The one custom CloudKit record zone EAST. protected content lives in.
/// Never the default zone — see the design doc §1.
const String keptRecordZoneName = 'EASTKeptZone';

/// CloudKit `recordType` for a saved reveal occurrence — both its active
/// form and its tombstone form share this one record type (design doc §2.1,
/// §2.3, §2.4).
const String keptWisdomRecordType = 'CKKeptWisdom';

/// CloudKit `recordType` for the per-database data-epoch singleton control
/// record (design doc §2.5).
const String syncStateRecordType = 'CKEastSyncState';

/// The fixed, singleton `recordName` for the one `CKEastSyncState` record
/// that ever exists per private database. Never derived from anything —
/// always this exact literal.
const String syncStateRecordName = 'sync-state';

/// Prefix used by [deriveKeptWisdomRecordName] — chosen so a derived name
/// can never collide with [syncStateRecordName], and so every EAST-owned
/// record is self-describing in CloudKit Dashboard inspection without ever
/// containing wisdom or Reflection content.
const String keptWisdomRecordNamePrefix = 'east-kept-';

/// Deterministically derives the CloudKit `recordName` for the saved reveal
/// occurrence identified by [revealId].
///
/// Pure function of [revealId] alone — never of wisdom text, a display
/// date, `KeptRecord.id`, or any timestamp (design doc §0, §2.2). The same
/// [revealId] always produces the same record name, on every device, every
/// time; two different [revealId] values always produce two different
/// record names. Applies identically to a record's active form and its
/// tombstone form — the record name never changes when a record transitions
/// between the two.
///
/// Throws [FormatException] when [revealId] is not
/// [isCanonicalUuidV4OrV5] — a noncanonical `revealId` must never silently
/// produce a record name.
String deriveKeptWisdomRecordName(String revealId) {
  if (!isCanonicalUuidV4OrV5(revealId)) {
    throw FormatException('Invalid revealId for CloudKit identity: $revealId');
  }
  return '$keptWisdomRecordNamePrefix$revealId';
}

/// Returns whether [recordName] is exactly what [deriveKeptWisdomRecordName]
/// would produce for [revealId] — never a substring match, never
/// case-insensitive, never accepting extra characters before or after.
bool recordNameMatchesRevealId(String recordName, String revealId) {
  if (!isCanonicalUuidV4OrV5(revealId)) return false;
  return recordName == deriveKeptWisdomRecordName(revealId);
}
