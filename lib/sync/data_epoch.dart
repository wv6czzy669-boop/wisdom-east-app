import 'package:uuid/uuid.dart';

import '../utils/canonical_uuid.dart';

/// Build 26 Phase 4A: the CloudKit-sync "generation" identifier described in
/// ADR-007 (Data epoch and Delete All reset safety) and
/// `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md` §4.1.
///
/// A [DataEpoch] is always a freshly-generated, random canonical UUID
/// version 4 — never derived from any record's content, `revealId`, or
/// timestamp, and never a v5 (v5 is reserved for deterministic *content*
/// derivations elsewhere in this codebase, e.g. `deriveLegacyMigrationRevealId`
/// — an epoch is deliberately the opposite: unpredictable and content-free).
///
/// This type carries no CloudKit or persistence behavior of its own; it is a
/// pure value object shared by every sync-domain model that needs to carry
/// or compare an epoch (`CloudKeptWisdomProjection`, `SyncTombstone`,
/// `ConflictOutcome`).
final class DataEpoch {
  const DataEpoch._(this.value);

  /// The raw canonical UUID v4 string. Never a `revealId`, never a
  /// `mutationId`, never derived from wisdom or Reflection content.
  final String value;

  /// Generates a fresh, random epoch — the only way ordinary application
  /// code should ever create a new [DataEpoch] (e.g. at first-ever sync
  /// bootstrap, or when the user explicitly confirms Delete All Synced
  /// Data). Never call this to "refresh" an existing epoch merely to force
  /// a resync — a new epoch is a deliberate reset signal, not routine
  /// bookkeeping.
  factory DataEpoch.generate({Uuid? uuidSource}) {
    final source = uuidSource ?? const Uuid();
    return DataEpoch._(source.v4());
  }

  /// Parses an already-known epoch value (e.g. one just read from local
  /// storage or from a fetched `CKEastSyncState` record). Throws
  /// [FormatException] for anything that is not an exact canonical UUID v4
  /// — an epoch is never a v5 or any other shape.
  factory DataEpoch.parse(String value) {
    if (!isCanonicalUuidV4(value)) {
      throw FormatException('Invalid data epoch: $value');
    }
    return DataEpoch._(value);
  }

  /// Returns whether [value] would be accepted by [DataEpoch.parse],
  /// without throwing — useful for validating a remote/untrusted value
  /// before deciding whether to construct one.
  static bool isValid(String value) => isCanonicalUuidV4(value);

  @override
  bool operator ==(Object other) => other is DataEpoch && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'DataEpoch($value)';
}
