/// Build 26 Phase 4E-1: the documented future integration boundary between
/// real local Kept/Reflection mutations and the durable sync-intent/outbox
/// machinery this phase establishes.
///
/// This file is a **contract placeholder only**. Phase 4E-1 deliberately
/// does not implement, and does not wire, the coordinator this class
/// documents -- no concrete class implements or extends it, nothing in
/// production constructs one, and no `KeptRepository`/
/// `SavedReflectionsService` call site is changed by this phase. See
/// `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md`'s Phase 4E-1 section for
/// the full rationale and the exact boundary this establishes:
///
/// ```text
/// UI / SavedReflectionsService
///         |
///         v
/// (a future) KeptSyncIntegrationCoordinator
///         |-- KeptRepository        (local Kept/Reflection reads/writes;
///         |                          gains no CloudKit/sync-platform
///         |                          knowledge of its own)
///         |-- SyncPersistenceStore  (durable outbox + atomic incoming
///         |                          checkpoint, lib/sync_persistence/)
///         `-- LocalSyncIntentStore  (durable, account-free crash-recovery
///                                    intent, this directory)
/// ```
///
/// `KeptRepository` remains the local Kept repository and never imports
/// `lib/sync_platform/` or gains a CloudKit transport dependency of its own
/// -- a future implementation of this boundary composes `KeptRepository`
/// and the sync layers together from the outside, never the reverse. That
/// future implementation (Phase 4E-2) is expected to:
///
/// 1. durably enqueue a [LocalSyncIntent] at
///    [LocalSyncIntentStage.pendingLocalApplication] *before* performing the
///    corresponding `KeptRepository` write;
/// 2. perform the `KeptRepository` write;
/// 3. advance that intent to
///    [LocalSyncIntentStage.localCommittedOutboxPending] once the write is
///    confirmed durable;
/// 4. convert the intent's [LocalSyncIntentPayload] into a real
///    `SyncChange` (binding it to the account's current `DataEpoch` for the
///    first time) and durably enqueue it via
///    `SyncPersistenceStore.enqueueMutation`;
/// 5. remove the intent once that enqueue is confirmed durable.
///
/// This class intentionally declares no member: adding one before a real
/// implementation exists to satisfy it would be speculative API surface
/// with no caller, contrary to this codebase's standing engineering
/// discipline against introducing abstractions ahead of an actual need. Its
/// only purpose in Phase 4E-1 is to reserve the name and record the
/// intended shape in one authoritative place, so Phase 4E-2 has an
/// already-agreed boundary to implement against rather than inventing one
/// under time pressure.
library;

import 'local_sync_intent.dart';

final class KeptSyncIntegrationCoordinatorBoundary {
  const KeptSyncIntegrationCoordinatorBoundary._();
}
