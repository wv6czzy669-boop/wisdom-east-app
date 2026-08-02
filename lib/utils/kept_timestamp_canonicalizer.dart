/// The single shared persisted-time contract for every `DateTime` that
/// reaches a [KeptRecord] (`lib/models/kept_record.dart`) on its way into the
/// protected [KeptStateStore] (`lib/persistence/kept_state_store.dart`).
///
/// Background: `KeptRecord.encode()` serializes every timestamp field via
/// `DateTime.millisecondsSinceEpoch` — the wire format has never stored
/// sub-millisecond precision. `KeptRecord.decode()` reconstructs from that
/// same millisecond integer, so a decoded record's timestamps always have
/// zero microseconds. `KeptRecord.operator==` (and therefore
/// `KeptStateEnvelope.operator==`) compares every timestamp with
/// `DateTime.isAtSameMomentAs`, which is exact down to the microsecond on
/// the Dart VM. `ProtectedFileKeptStateStore._replace`'s own mandatory
/// post-write verification decodes what it just wrote and compares it,
/// field-by-field, against the in-memory envelope it was asked to persist.
///
/// Put those three facts together: any `DateTime` that reaches a
/// constructed `KeptRecord` carrying a non-zero microsecond remainder will
/// make that record compare unequal to its own encode-then-decode
/// read-back — a genuinely valid record spuriously fails verification and
/// the write is rejected. `DateTime.now()` (the default clock for both
/// [KeptRepository] mutations and, historically, this exact class of legacy
/// migration timestamp) routinely returns microsecond-precision values on
/// a real device — this is not a rare edge case, it is the common case.
///
/// [canonicalizeKeptTimestamp] is the one place this truncation happens.
/// Every call site that is about to hand a freshly-supplied or
/// freshly-computed `DateTime` to a [KeptRecord] constructor or `copyWith`
/// call — in [KeptRepository] and in `KeptMigrationCoordinator`
/// (`lib/services/kept_migration_coordinator.dart`) — canonicalizes it
/// first, so the value a [KeptRecord] is built with is already exactly what
/// its own encode/decode round trip will produce. This preserves the real
/// instant to the maximum precision the existing wire format actually
/// supports (whole milliseconds) — it never changes the file schema, never
/// moves to microsecond storage, and never weakens
/// [KeptRecord.operator==]/[KeptStateEnvelope.operator==] or the protected
/// store's own read-back verification, both of which remain exact.
library;

/// Canonicalizes [value] to the UTC, millisecond-precision instant that
/// [KeptRecord]'s wire format (`encode()`/`decode()`) can actually
/// represent losslessly.
///
/// Equivalent to, and must always remain equivalent to:
/// ```dart
/// DateTime.fromMillisecondsSinceEpoch(
///   value.toUtc().millisecondsSinceEpoch,
///   isUtc: true,
/// )
/// ```
///
/// Idempotent: canonicalizing an already-canonical value returns an equal
/// value. Never changes which calendar day, hour, minute, or second [value]
/// represents — only ever discards a sub-millisecond remainder.
DateTime canonicalizeKeptTimestamp(DateTime value) {
  return DateTime.fromMillisecondsSinceEpoch(
    value.toUtc().millisecondsSinceEpoch,
    isUtc: true,
  );
}
