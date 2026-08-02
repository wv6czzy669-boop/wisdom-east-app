import 'cloud_kept_wisdom_projection.dart';
import 'sync_change.dart';
import 'sync_status.dart';

/// Build 26 Phase 4A: the sync-engine "port" — a pure interface with **no
/// implementation** in this phase. See
/// `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md` §7 for the full contract
/// this is the Dart-side shape of, and §6 for why the eventual
/// implementation is a native Swift CloudKit bridge (operation-based, not
/// `CKSyncEngine`) behind a narrow method/event-channel boundary, rather
/// than a package added to this interface's own dependencies.
///
/// No concrete class in `lib/` implements this interface yet. A fake,
/// in-memory implementation for tests lives in
/// `test/sync_engine_test_helpers.dart`, following this codebase's existing
/// convention of keeping test doubles in `test/` (e.g.
/// `JsonRoundTrippingKeptStateStore` in `test/persistence_test_helpers.dart`).
abstract interface class SyncEngine {
  /// The current CloudKit account status. Never throws for "no account" or
  /// "restricted" — those are ordinary, expected values, not failures (see
  /// the design doc §5).
  Future<CloudAccountStatus> accountStatus();

  /// Ensures the dedicated custom zone (`keptRecordZoneName`) exists in the
  /// private database. Idempotent.
  Future<void> configureZone();

  /// Begins the passive foreground sync cycle (app launch, foreground
  /// return, or scheduled retry) described in ADR-007's Sync order.
  Future<void> startSync();

  /// Triggers the same sync cycle explicitly and immediately — e.g. right
  /// after a local mutation, per the design doc §3's "local writes complete
  /// locally first, then enqueue durable sync work" rule. Never required
  /// for correctness (a passive [startSync] would eventually pick up the
  /// same enqueued work) — only for latency.
  Future<void> requestImmediateSync();

  /// Durably enqueues [change] for the next sync cycle to push. Must not
  /// block on network reachability — enqueueing is a local operation only
  /// (design doc §3).
  Future<void> enqueueLocalChange(SyncChange change);

  /// A stream of remote [CloudKeptWisdomProjection]s discovered by the most
  /// recent (or an in-progress) sync cycle's pull phase — the Dart side is
  /// solely responsible for conflict resolution and local-envelope
  /// application of what arrives here; the engine implementation itself
  /// never resolves conflicts or writes local storage (design doc §7).
  Stream<CloudKeptWisdomProjection> get remoteChanges;

  /// The engine's current status — see `sync_status.dart`.
  Stream<SyncEngineStatus> get statusChanges;

  /// Emitted when the platform detects the signed-in iCloud account has
  /// changed — see `sync_status.dart`'s `AccountChangeEvent` and the design
  /// doc §5. The engine itself pauses sync immediately when this fires; it
  /// never resumes automatically without an explicit, separate
  /// confirmation call (deliberately not modeled as a method on this
  /// interface yet — the confirmation UX belongs to a later phase).
  Stream<AccountChangeEvent> get accountChangeEvents;
}
