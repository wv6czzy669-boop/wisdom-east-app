import '../models/kept_state_envelope.dart';

/// Boundary between Kept/Reflection domain logic and the concrete storage
/// implementation for the protected [KeptStateEnvelope].
///
/// Deliberately narrow — this is not a general database abstraction. It
/// exposes exactly the two operations Phase 3 needs: reading the current
/// authoritative envelope, and replacing it as a whole. Migration,
/// pre-migration snapshotting, and recovery-artifact handling for
/// undecodable legacy entries are separate concerns with their own
/// components; they intentionally do not belong on this interface.
///
/// Phase 3A defines only this contract, with no concrete implementation.
/// Atomicity (temporary file plus rename/replace), iOS file-protection
/// guarantees, and directory handling are introduced in Phase 3B by a
/// concrete [KeptStateStore] implementation.
abstract interface class KeptStateStore {
  /// Returns the current authoritative [KeptStateEnvelope], or `null` when
  /// no authoritative envelope has ever been created yet.
  ///
  /// Must throw when an authoritative envelope already exists but cannot be
  /// read or decoded. This method must never silently return `null`, nor a
  /// partial/synthesized envelope, in place of a genuinely corrupt file —
  /// callers are responsible for deciding how to react to that failure
  /// (for example, corruption-recovery handling introduced in a later
  /// phase).
  Future<KeptStateEnvelope?> load();

  /// Replaces the entire authoritative envelope with [envelope].
  ///
  /// This is always a complete-envelope replacement, never an append or an
  /// in-place update of a single record — the caller is responsible for
  /// computing the full next state before calling this.
  Future<void> replace(KeptStateEnvelope envelope);
}
