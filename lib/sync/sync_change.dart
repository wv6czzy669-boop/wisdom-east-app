import 'cloud_kept_wisdom_projection.dart';

/// Build 26 Phase 4A: the kind of pending local mutation a [SyncChange]
/// represents — mirrors ADR-007's "a pending-operation type per record
/// (create/update/delete)" (Local state envelope, `syncMetadata`).
///
/// Note: a `delete` here always carries a tombstone-form
/// [CloudKeptWisdomProjection] (`SyncChange.projection.isTombstone == true`)
/// — per ADR-007's Deletion/outbox strategy, a soft tombstone is synced as
/// an ordinary `CKRecord` **update**, never a native CloudKit record
/// deletion. This enum still distinguishes `delete` from `update` for local
/// outbox bookkeeping (e.g. so a UI can report "this item was deleted"
/// distinctly from "this item was edited"), even though both perform the
/// same kind of CloudKit operation.
enum SyncChangeKind { create, update, delete }

/// Build 26 Phase 4A: one durable, pending local mutation awaiting sync —
/// the pure-Dart shape of an ADR-007 outbox entry (Local state envelope,
/// Deletion/outbox strategy). This class has no persistence behavior of its
/// own; a later subphase's durable outbox store is responsible for actually
/// storing/loading these.
final class SyncChange {
  SyncChange({
    required this.kind,
    required this.projection,
    required this.enqueuedAt,
  }) {
    if (kind == SyncChangeKind.delete && !projection.isTombstone) {
      throw const FormatException(
        'A delete SyncChange must carry a tombstone-form projection.',
      );
    }
    if (kind != SyncChangeKind.delete && projection.isTombstone) {
      throw const FormatException(
        'A create/update SyncChange must carry an active-form projection.',
      );
    }
  }

  final SyncChangeKind kind;
  final CloudKeptWisdomProjection projection;

  /// When this change was enqueued locally — UTC. Used for outbox ordering
  /// and diagnostics only; never used as a conflict-resolution input (see
  /// `conflict_resolution.dart` — only the projection's own `updatedAtMs`
  /// participates in conflict resolution).
  final DateTime enqueuedAt;

  /// Privacy-safe summary — see [CloudKeptWisdomProjection.toLogSafeSummary].
  Map<String, Object?> toLogSafeSummary() => {
        'kind': kind.name,
        'enqueuedAtMs': enqueuedAt.toUtc().millisecondsSinceEpoch,
        ...projection.toLogSafeSummary(),
      };
}
