# ADR-007: Build 26 Protected Local Storage and Private CloudKit Sync for Kept Wisdoms and Reflections

## Status

Accepted for Build 26. Documentation-only at this stage — no production code, tests, or Xcode configuration has been changed as part of this decision. Implementation proceeds in the phases listed below, each requiring its own review before the next begins.

## Context

Build 25 (tag `v1.0.0+25`, branch `build-19-release`, bundle ID `com.dogukan.dailywisdom`) stores every Kept wisdom and its optional Reflection as a single JSON-encoded `FavoriteItem` (`lib/models/favorite_item.dart`) inside one `SharedPreferences` `StringList` under the key `favorites` (`lib/services/saved_reflections_service.dart`). This is backed by plain `NSUserDefaults` on iOS with no file-protection guarantee beyond the OS default, no Keychain involvement, and no off-device backup beyond whatever the user's general iOS/iCloud device-backup settings already do. Deleting the app removes the app-local copy of this data, and Build 25 provides no supported EAST. in-app recovery or synchronization path for it. (This ADR makes no claim about whether a full-device system backup may or may not separately restore app data — that is outside EAST.'s own control and outside this decision's scope.)

`docs/architecture/EAST_ARCHITECTURE_V1.md` describes a future Supabase/PostgreSQL-based platform (`reflections`, `kept_reflections`, `user_wisdom_favorites` tables in Section 8.2) intended for a later, larger EAST. platform with accounts, commerce, and a website. That platform does not exist yet, and building it is explicitly out of scope for Build 26. Build 26 instead addresses an immediate, narrower need: users should not lose their Kept wisdoms and Reflections if they lose or replace their device, without EAST. adopting server accounts, a backend, or cross-platform sync ahead of that larger platform decision.

This ADR documents the Build 26 answer: a protected local store on-device, kept in sync across the user's own devices via their private Apple iCloud/CloudKit database, with no EAST. account and no third-party backend.

## Decision

Build 26 will:

1. Replace the `favorites` SharedPreferences `StringList` as the **authoritative** store for Kept wisdoms and Reflections with a single versioned, protected, atomically-replaced local state envelope (see Local state envelope).
2. Model active Kept content and sync-only deletion metadata as **two separate types** — `KeptRecord` (active, user-visible) and `SyncTombstone` (sync-only, never shown in the Kept UI) — rather than one record that must represent both states (see Active record and tombstone models).
3. Migrate existing Build 25 data losslessly, idempotently, and verifiably before ever removing the old key.
4. Synchronize Kept wisdoms and Reflections (and only those) to the user's private CloudKit database, using foreground/opportunistic sync only, gated by an explicit data-epoch control record that makes Delete All Synced Data safe against stale offline devices (see Data epoch and Delete All reset safety).
5. Detect and safely handle CloudKit account availability and account-identity changes, never silently uploading one account's local content into a different, newly detected account (see iCloud account change boundary).
6. Add a rating-request mechanism whose intended completed feature is: eligibility becomes true after the fourth genuinely completed new ritual; the actual native request is invoked only after Home reaches a stable idle/revealed state. **This documentation phase implements none of it.**
7. Document (but not implement) analytics deferred until storage and sync are stable.
8. Document (but not implement) the iPhone-only posture as deliberate, and (but not perform) the `Info.plist` cleanup this implies.
9. Document (but not implement) Export My Data and Delete All Synced Data as explicit user-data-access features (see User data access).

None of items 1–9 are implemented by this ADR. This ADR is the authoritative specification those phases must follow.

## Active record and tombstone models

An active `KeptRecord` must never be required to also represent a content-cleared tombstone. Deletion metadata lives in a separate, sync-only local type instead.

**Active `KeptRecord` (successor to `FavoriteItem`, schema v3) — the only model shown in the Kept UI:**

| Field | Type | Notes |
|---|---|---|
| `id` | String | Stable record identity. Same value used as the CloudKit `recordName`. Never derived from wisdom text. |
| `revealId` | String | The stable UUID of the reveal this record was kept from (see Identity rules). |
| `wisdomText` | String | Snapshot at time of keeping. Duplicates across records are expected and allowed. |
| `revealedAt` | DateTime (UTC) | Historical — when the wisdom was originally revealed. Immutable once set. |
| `keptAt` | DateTime (UTC) | Historical — when the user chose to keep it. Immutable once set. |
| `reflectionText` | String? | Optional. |
| `reflectedAt` | DateTime (UTC)? | Optional. |
| `updatedAt` | DateTime (UTC) | Last local mutation to this record; drives conflict resolution. |
| `mutationId` | String | Client-generated UUID, regenerated on every mutation; deterministic tie-breaker only (see Conflict resolution order). Not a record identity. |
| `schemaVersion` | Int | `3`. Decoding of legacy `1`/`2` payloads is retained (see Migration rules). |

**`SyncTombstone` — a separate, local, sync-only model. It is never displayed in the Kept UI, and it contains no wisdom text, reflection text, `revealId`, `revealedAt`, `keptAt`, or `reflectedAt`:**

| Field | Type | Notes |
|---|---|---|
| `id` | String | The same `id` the deleted `KeptRecord` used — identity carries over from active record to tombstone. |
| `dataEpoch` | String | The data epoch this tombstone belongs to (see Data epoch and Delete All reset safety). |
| `updatedAt` | DateTime (UTC) | |
| `deletedAt` | DateTime (UTC) | Presence of a `SyncTombstone` for an `id` is itself what marks that item deleted — there is no separate boolean. |
| `mutationId` | String | Deterministic tie-breaker (see Conflict resolution order). |
| `schemaVersion` | Int | |

The CloudKit record type `CKKeptWisdom` may represent **either** of these two shapes for a given `recordName`: a complete active record (all active `KeptRecord` fields, plus `dataEpoch`), or a soft tombstone identified by the presence of `deletedAt` and containing only minimal deletion metadata (see CloudKit record model). All stored and synced timestamps are UTC.

A canonical, stable `wisdomId` for content items in `lib/data/wisdoms.dart` is **not** introduced in Build 26 — `revealId` plus the `wisdomText` snapshot already give each occurrence a unique, stable identity, which is sufficient for this build's scope.

## Identity rules

- **Exact duplicate wisdom text is allowed and expected.** The same text may be revealed on different days, and the same text may be Kept more than once when it belongs to different `revealId` values. Wisdom text is never the identity of a reveal or a Kept record — only a display/snapshot value.
- **`revealId`:** a client-generated UUID, created exactly once when a genuinely new reveal becomes authoritative (the same commit point that today writes the authoritative `DailyWisdomRecord` in `DailyAccessRepository._writePendingRevealAsDaily` / `_saveDailyWisdomRecord`). It is persisted as part of that same local daily-access record, survives app restart, is reused verbatim during incomplete-reveal recovery (`recoverIncompleteReveal`), and is never regenerated for the same reveal. It is derived from neither the wisdom text nor the date/timestamp alone.
- **`revealId` sync scope, precisely:** `daily_wisdom_access` and the rolling 24-hour ritual lock are never synced, in any form. `revealId` is stored locally as a field of the local daily reveal record; when the user keeps that reveal, `revealId` is copied into the resulting `KeptRecord`; from that point it syncs to CloudKit only as an ordinary field of that `CKKeptWisdom` record. `revealId` must never be sent to analytics.
- **One active record per reveal:** at most one active `KeptRecord` may exist for a given `revealId` at any time. Saving the same reveal twice is idempotent — the second save must locate and reuse the existing active record for that `revealId` rather than creating a duplicate. Identical `wisdomText` values under **different** `revealId` values remain fully valid and always create separate, independent records — this uniqueness rule is scoped to `revealId`, never to text.
- **Migration and uniqueness:** migration preserves every existing item's original ID and must never merge two migrated records merely because their `wisdomText` happens to be identical — identity is always by `id`/`revealId`, never inferred from text equality.
- **Build 25 upgrade backfill — existing authoritative daily record with no `revealId`:** on first Build 26 launch, if an authoritative `daily_wisdom_access` record already exists (written by Build 25 and therefore missing `revealId`), generate a `revealId` for it exactly once and add it to that record (see Daily access backfill write semantics for the precise write mechanism). That `revealId` then persists and survives every subsequent restart, and is never regenerated during later incomplete-reveal recovery. The backfill must not alter `revealedAt`, `unlockAt`, the wisdom text, or the 24-hour lock in any way.
- **Build 25 pending (not-yet-authoritative) reveal:** if a pending reveal exists that has not yet become authoritative at upgrade time, do not backfill it — generate its `revealId` only at the moment it actually becomes authoritative, exactly as a genuinely new Build 26 reveal would.
- **`KeptRecord.id`:** independent of `revealId` and of wisdom text; generated once per Kept record, reused as the CloudKit `recordName`, and reused as the corresponding `SyncTombstone.id` if the record is later deleted; never regenerated.

### Daily access backfill write semantics

The Build 25 upgrade backfill (above) writes to the existing `daily_wisdom_access` `SharedPreferences` record, not to the new protected envelope, and must not be described as if it were a protected-file write:

- Use the existing `DailyAccessRepository`, its storage adapter, and its persistence coordinator — the same components already responsible for every other read/write of the authoritative daily record. Do not introduce a parallel write path.
- Read and decode the authoritative `daily_wisdom_access` record.
- Add only the missing `revealId`.
- Write the updated record once.
- Read it back and verify `revealId` plus every previously existing field (`revealedAt`, `unlockAt`, wisdom text) matches what was read before the write.
- Wisdom text, `revealedAt`, `unlockAt`, and the rolling 24-hour lock must remain exactly unchanged by this backfill.
- If the write or the read-back verification fails, preserve the prior valid record's behavior exactly as Build 25 would have, and retry the backfill safely on a later launch — a failed backfill must never block normal daily-access reads or leave the record in a worse state than before the attempt.
- This is an ordinary `SharedPreferences`-backed record read/write/verify, using the existing repository and coordinator's own guarantees — it does **not** use, and must not be described as using, the protected envelope's temp-file/rename/`NSFileProtectionComplete` semantics (see Local state envelope, Local storage rules). Those apply only to Kept/Reflection content, never to `daily_wisdom_access`.

## Migration rules

Migration from the Build 25 `favorites` key must be lossless, idempotent, verifiable, retryable, and non-destructive until verification succeeds, tracked through an explicit crash-safe state machine.

**Migration state machine:** `notStarted` → `writing` → `verified` → `complete`.

Required sequence:

1. Read the complete old `favorites` value (source of truth while state is `notStarted`/`writing`).
2. Decode every usable item (reusing the existing legacy v1/pipe-format and v2/JSON decoders already present in `FavoriteItem` — these must remain available indefinitely). See Legacy Kept migration identity and Legacy date mapping below.
3. Preserve undecodable entries in a protected recovery artifact (a separate file from the local state envelope — see Local state envelope) rather than silently discarding them.
4. Write the migrated active records into the new local state envelope (state transitions to `writing` at the start of this step).
5. Read the envelope back and verify every usable record **field-by-field** against the source.
6. Verify the expected usable-record count and the protected-recovery (undecodable-entry) count **separately**.
7. Write a protected **pre-migration** recovery snapshot (a durable, protected copy of the old `favorites` value exactly as read in step 1 — also a separate file from the envelope).
8. Set state to `verified`.
9. Remove the old unprotected `favorites` key.
10. Verify the old key removal actually took effect.
11. Set state to `complete`.

**On every app launch, behavior is driven by the current state:**

- `notStarted` / `writing`: retry the full migration safely from the old authoritative `favorites` source — a crash or termination mid-write never mutates the old key, so retrying from scratch is always safe and never produces duplicates (record IDs are stable and re-derived deterministically each time; see Legacy Kept migration identity).
- `verified`: the envelope's migrated content is already correct and authoritative; only old-key cleanup (steps 9–11) remains to retry.
- `complete`: use only the envelope; best-effort confirm the old key is absent.

If any step fails before state reaches `verified`: do not remove or modify the old authoritative data, do not advance the state past the failing step, keep Build 25 data readable and the app fully functional on it, and allow retry later. Reflection text must not be retained indefinitely in the old unprotected key once migration reaches `complete` — the protected pre-migration recovery snapshot is the rollback path instead (see Protected snapshot retention).

### Legacy Kept migration identity

- **Preserve every existing `FavoriteItem.id` unchanged as the new `KeptRecord.id`.** Migration must never assign a new record identity to an existing Kept item.
- **Legacy `revealId` is derived deterministically, not freshly generated.** Compute it from the stable `FavoriteItem.id` using a fixed EAST.-specific UUID namespace and a UUIDv5-equivalent deterministic algorithm, so the same legacy item receives the **same** `revealId` on every migration retry and on every device that independently migrates the same original record. Never derived from wisdom text or the visible legacy date.

### Legacy date mapping

Build 25 held only a single historical date per item (`FavoriteItem.date`) — it never recorded separate reveal and keep timestamps. Mapping that one value onto both new historical fields is the least lossy, most honest conversion available:

- `revealedAt` = the legacy `date`.
- `keptAt` = the legacy `date`.
- `reflectedAt` = the existing `reflectedAt` value when the legacy record already has one; otherwise remains unset.
- `updatedAt` = `reflectedAt` when present, otherwise the legacy `date`. **`updatedAt` is never set to the migration's own execution time.**

## Local state envelope

The smallest safe local-store design is **one versioned, protected state envelope, atomically replaced as a whole**:

```
east_kept_state_v3.json
```

It contains:

- `activeRecords` — the active `KeptRecord` collection.
- `pendingUndoDeletions` — see Crash-safe undo window.
- `tombstones` — the local `SyncTombstone` collection.
- `outbox` — durable, not-yet-synced local mutations.
- `syncMetadata` — server change token, last-successful-sync bookkeeping, and per-record pending-operation state.
- `pendingEpochCleanup` — the durable prior-epoch hard-deletion job, when one is in progress (see Data epoch and Delete All reset safety).
- the current `dataEpoch` known to this device.

Migration recovery artifacts (undecodable legacy entries) and the pre-migration recovery snapshot **remain separate protected files**, not part of this envelope — they are rollback aids for the migration itself, not live application state.

**Atomicity requirements:**

- A local content mutation and its corresponding outbox mutation must be committed in the **same** atomic envelope write. There must be no state where a local mutation succeeds but its outbox entry is missing.
- Applying pulled remote changes and advancing the server change token must be committed in the **same** atomic envelope write. There must be no state where the token advances but the corresponding remote changes were not durably applied.
- **All local mutations and all remote merges pass through one serialized mutation/coordinator path** — never two independent writers touching the envelope concurrently. This is a direct extension of the existing `PersistenceOperationCoordinator` pattern already used elsewhere in this codebase, applied to the new envelope as its single point of entry.
- Atomic replacement follows the same temporary-file-then-rename/replace discipline as before, with native verification required immediately after the final rename/replace.

## Local storage rules

- The local state envelope (see above) is the sole authoritative store for active Kept content, tombstones, the outbox, sync metadata, and the current data epoch.
- Atomic writes: temporary file, then rename/replace — never a partial in-place overwrite. Native verification of the write is required immediately after the final rename/replace before the operation is considered durable.
- Read-back verification after every migration write and, as general practice, after ordinary mutating writes where reasonably cheap.
- **Strong iOS file protection, applied consistently across every piece of Kept/Reflection-related state:** require `NSFileProtectionComplete` for the envelope file, its temporary atomic-write file, the migration recovery artifact, the pre-migration recovery snapshot, and the containing storage directory itself where the platform allows directory-level protection. Preferred throughout because the first CloudKit implementation syncs only while the app is active or returning to foreground — there is no locked-device background access path in this build that would need weaker protection anywhere this data lives.
- `SavedReflectionsService`'s existing public API (`load`, `toggle`, `saveReflection`, `deleteReflection`, `remove`, `restore`) should remain stable where reasonably possible so calling screens and existing tests are not forced to change merely because the storage backend changed underneath.
- `SharedPreferences` remains appropriate and continues to be used for: small settings, counters, migration-progress flags, tutorial/hint state, daily-access state (`daily_wisdom_access`, `pending_daily_wisdom_reveal`), and other non-sensitive preferences. Only Kept/Reflection content and its supporting sync state move to the protected envelope.

### Protected snapshot retention

The protected pre-migration recovery snapshot is **not retained forever**. Delete it once **all** of the following are true:

- migration state has reached `complete`;
- the envelope has opened successfully on at least three **later** app launches (after the one that reached `complete`);
- at least 30 days have passed since the state reached `verified`.

Independent of that schedule, the snapshot must also be deleted **immediately** as part of Delete All Synced Data.

## CloudKit scope

- Apple CloudKit, **private database only**, dedicated custom record zone.
- No EAST. account or login of any kind. No third-party backend for this feature.
- One CloudKit record per Kept+Reflection pairing (record type `CKKeptWisdom`) — never the entire collection as one JSON blob.
- A single control record, `CKEastSyncState`, exists per private database to carry the current data epoch (see Data epoch and Delete All reset safety).
- The app remains fully usable offline or when iCloud is unavailable; cloud sync never blocks the ritual or a local save/edit/delete.

**Synced:** `CKKeptWisdom` records (active and soft-tombstone forms), the `CKEastSyncState` control record, and the minimum record metadata required for safe synchronization. `revealId` is synced only as an ordinary field of the active-form `CKKeptWisdom` record it belongs to.

**Never synced:** `daily_wisdom_access`, the rolling 24-hour wisdom lock, pending ritual state, notification permission state, notification scheduling state, Keeper entitlement, purchase state, Reduce Motion preference, tutorial/hint state, temporary UI state, and analytics identifiers/queues. Keeper entitlement continues to be handled exclusively through StoreKit and Restore Purchases, unaffected by this ADR.

It is an accepted, explicit consequence of this scope that reinstalling the app or opening it on a second device may allow a new wisdom sooner than the prior device's rolling 24-hour lock would have allowed.

### CloudKit record model

**`CKKeptWisdom` — active form:**

| Field | Source |
|---|---|
| `recordName` | The stable local `KeptRecord.id` |
| `revealId` | Local `revealId` |
| `wisdomText` | Local `wisdomText` snapshot |
| `revealedAt` | Local `revealedAt` (UTC) |
| `keptAt` | Local `keptAt` (UTC) |
| `reflectionText` | Optional |
| `reflectedAt` | Optional (UTC) |
| `updatedAt` | Local `updatedAt` (UTC) |
| `mutationId` | Local `mutationId` |
| `dataEpoch` | The epoch this record was written under |
| `schemaVersion` | Local `schemaVersion` |

**`CKKeptWisdom` — soft tombstone form (same `recordType`, same `recordName` space, identified by the presence of `deletedAt`):**

| Field | Source |
|---|---|
| `recordName` | The same `id` the active record used |
| `deletedAt` | Local `SyncTombstone.deletedAt` (UTC) |
| `updatedAt` | Local `SyncTombstone.updatedAt` (UTC) |
| `mutationId` | Local `SyncTombstone.mutationId` |
| `dataEpoch` | Local `SyncTombstone.dataEpoch` |
| `schemaVersion` | Local `SyncTombstone.schemaVersion` |

A tombstone record contains **no** `revealId`, `wisdomText`, `reflectionText`, `revealedAt`, `keptAt`, or `reflectedAt` — those fields are cleared/omitted entirely, not merely blanked, when a record transitions to tombstone form.

**`CKEastSyncState` — singleton control record:**

| Field | Notes |
|---|---|
| `recordName` | Fixed value `sync-state` — exactly one instance ever exists per private database. |
| `dataEpoch` | Current authoritative epoch (see Data epoch and Delete All reset safety). |
| `resetAt` | UTC timestamp of the most recent epoch reset, if any. |
| `mutationId` | Deterministic tie-breaker, consistent with all other records. |
| `schemaVersion` | |

A canonical `wisdomId` field is intentionally not required for Build 26 — `revealId` plus the `wisdomText` snapshot already provide the occurrence identity this build needs.

**Local synchronization metadata required (kept local, inside the envelope's `syncMetadata`, not part of any CloudKit record's own domain fields):** archived `CKRecord` system fields or equivalent server change-tag state per record; a pending-operation type per record (create/update/delete); a pending-operation timestamp (UTC); the zone's server change token; and last-successful-sync bookkeeping (UTC).

## Sync timing

Foreground/opportunistic synchronization only, in this first implementation. Sync runs:

- At app launch, after local initialization completes.
- When the app returns to foreground.
- After a local Kept or Reflection mutation (create, edit, or delete).
- On an appropriate foreground retry once connectivity returns, if a previous attempt failed.

**Not included in this first implementation:** silent push, any APNs dependency, the remote-notification background mode, background fetch, continuous polling, or any sync work scheduled inside the ritual animation sequence. All local changes succeed locally first, unconditionally; cloud sync is asynchronous and strictly secondary.

### Sync order, every foreground cycle

Each sync cycle must run in exactly this order:

1. Fetch/resolve the authoritative `CKEastSyncState` and compare its `dataEpoch` against the device's locally known epoch.
2. Pull remote custom-zone changes (`CKKeptWisdom` records, both active and soft-tombstone forms).
3. Apply remote creates, updates, and soft tombstones locally (committed atomically with the token advance — see Local state envelope).
4. Resolve conflicts (see Conflict resolution order).
5. Persist the new server change token (same atomic write as step 3).
6. Push durable local outbox mutations — **only** for records belonging to the current, non-stale `dataEpoch`; never push anything belonging to a stale epoch (see Data epoch and Delete All reset safety).
7. Perform a follow-up pull if required (e.g., the push itself surfaced a server-side conflict that needs a fresh read).
8. Persist last-successful-sync state.

**Pull-before-push is required, not incidental:** applying remote changes (including tombstones) before pushing local outbox mutations is what prevents an older offline local update from resurrecting a record that a newer cloud tombstone has already deleted.

## Conflict resolution order

Whole-record last-writer-wins remains the strategy — no CRDTs, no field-level merge — but the epoch now takes precedence over everything else. The exact, deterministic order:

1. **The authoritative `CKEastSyncState.dataEpoch` controls which generation is valid.** A record belonging to an older epoch than the authoritative one is never applied and never wins, regardless of its own `updatedAt`.
2. **Within the same epoch**, the version with the newer `updatedAt` (UTC) wins.
3. **If `updatedAt` is equal and one version is a tombstone**, the tombstone wins.
4. **If both versions have the same active/deleted state** (both active, or both tombstones) and `updatedAt` is equal, the lexicographically greater `mutationId` wins.
5. **`keptAt` and `revealedAt` remain immutable and are never used to resolve conflicts.**

Where practical, recoverable conflict information may be logged/preserved locally for diagnostics, without ever exposing reflection or wisdom text to analytics.

## Crash-safe undo window

When the user swipes to delete a Kept item, the app must **immediately** persist a `pendingUndoDeletion` entry into the local state envelope, containing: the record ID, a copy of the original active record, and a `pendingDeleteUntil` UTC timestamp. No cloud tombstone is enqueued or sent before that undo window ends.

- **Undo:** removes the pending marker and restores the active record — a pure local operation, nothing is ever sent to CloudKit for an undone deletion.
- **Restart before `pendingDeleteUntil`:** the app must restore the active record on relaunch rather than silently finalizing what might have been an accidental deletion the user never got to undo — a pending, not-yet-expired undo window is not itself proof of intent to delete.
- **Resume after `pendingDeleteUntil`:** finalize the deletion — remove the active record, create the corresponding `SyncTombstone`, and enqueue the outbox mutation, all **atomically in one envelope write**.
- **Reflection-only deletion remains an ordinary active-record update** (clearing `reflectionText`/`reflectedAt` on the still-active `KeptRecord`) — it is never a tombstone and never enters the undo-window/outbox-delete path described here.

## Deletion/outbox strategy

Every unsent local cloud mutation — create, update, or delete — must survive **process termination and app restart** via the durable outbox inside the local state envelope.

**Soft tombstones are ordinary `CKRecord` updates, not native CloudKit deletions.** A `SyncTombstone` is synced as an update to the existing `CKKeptWisdom` record (clearing its private content fields and setting `deletedAt`/`updatedAt`) and is received by other devices as a **changed record** through ordinary custom-zone change fetching — the same pull path as any other update. Native CloudKit deleted-record IDs (the mechanism that reports "this record no longer exists at all") apply **only** to records that are actually hard-deleted from CloudKit, which in this design happens only during Delete All Synced Data cleanup of prior-epoch records — never during normal, single-item deletion.

**Honest limits of the durable outbox:** the outbox survives process termination and app restart — it **cannot** survive app uninstall. A local mutation (including a finalized pending delete) that has not yet reached CloudKit may be permanently lost if the user deletes the app while offline and before that mutation ever synced. Once a mutation is confirmed in CloudKit, a later reinstall's restoration follows whatever state CloudKit holds at that time.

**Epoch-aware push:** the outbox must never push a mutation whose `dataEpoch` does not match the authoritative epoch (see Sync order and Data epoch and Delete All reset safety) — a stale-epoch outbox entry is discarded locally rather than pushed, once the device has observed the new epoch.

## Data epoch and Delete All reset safety

A CloudKit singleton control record, `CKEastSyncState` (see CloudKit record model), carries the current `dataEpoch` for the private database. Every active `CKKeptWisdom` record and every soft tombstone carries the `dataEpoch` it was written under.

**Normal sync:** fetch and resolve the authoritative `CKEastSyncState` before pushing any local mutation; never push records belonging to a stale (superseded) epoch.

**Delete All Synced Data must:**

1. Require deliberate user confirmation.
2. Generate a new, random `dataEpoch`.
3. Save and confirm the new `CKEastSyncState` **first**, before any other step below.
4. In the **same atomic envelope write**: clear the current device's active records, pending undo entries, tombstones, and outbox; clear the protected migration snapshot; and create a `pendingEpochCleanup` entry recording the epoch(s) to be purged (see Durable prior-epoch cleanup job below).
5. Hard-delete all active and tombstone records from earlier epochs, as **durably retryable cleanup carried out by the `pendingEpochCleanup` job**, not a one-shot best-effort pass (this is the one path in this design that performs real CloudKit hard deletion).
6. Keep the new `CKEastSyncState` control record in place.
7. Ensure every other device, upon later observing the new epoch, clears its own stale local synced content and stale outbox **before** it is allowed to push anything at all.

**Why the epoch control record matters:** without it, an offline device that still holds pre-reset local data — including outbox entries queued before the reset — could sync after the reset and effectively recreate the very data Delete All Synced Data was meant to erase. Because every record and every outbox entry carries its epoch, and because step 7 forces any device to reconcile against the new epoch before pushing anything, an old offline device can only ever discover "my epoch is stale, discard and clear before continuing" — it can never push its way past that check.

### Durable prior-epoch cleanup job

Prior-epoch hard deletion is called "retryable cleanup" above, but that requires an actual durable job, not an in-memory best-effort pass that silently disappears if the app is killed mid-cleanup. The local state envelope carries a `pendingEpochCleanup` entry for this purpose:

- `previousEpochs` — the epoch(s) whose active/tombstone records still need hard deletion from CloudKit.
- `startedAt` — UTC timestamp the cleanup job began.
- `status` — the job's current state (e.g., `pending` / `inProgress` / `verifying`).
- a continuation/query cursor, when the underlying CloudKit query/delete operation is paginated and needs to resume mid-batch.

Rules:

- Creating `pendingEpochCleanup` happens in the same atomic envelope write as clearing the current device's own local synced content (step 4 above) — the cleanup job's existence is never lost relative to the reset that spawned it.
- Prior-epoch CloudKit records are hard-deleted in **retryable batches**, not one unrecoverable bulk operation.
- App termination or restart must not lose the cleanup job — it is durable envelope state, read back and resumed like any other envelope content.
- Cleanup resumes automatically on a later foreground sync if it was left `inProgress` (or `pending`) at last launch.
- The `pendingEpochCleanup` marker is removed **only** after CloudKit has actually been checked and confirmed that no records from the target prior epoch(s) remain — never removed merely because a delete request was issued.
- **The cleanup job itself belongs to the new/current epoch** and must not be discarded or treated as stale by the epoch-aware push rule (see Sync order, Epoch-aware push) — it is current-epoch bookkeeping about old-epoch data, not old-epoch data itself.

### Initial data-epoch bootstrap

The very first sync for a given private database has no `CKEastSyncState` yet. This is handled without any distributed-lock or server-backend complexity, using only CloudKit's own record-creation semantics:

- Query/fetch `CKEastSyncState` before any push, exactly as in normal sync.
- If it does not exist, generate a random initial `dataEpoch` locally and attempt to **create** the singleton control record (`recordName = sync-state`) with that epoch.
- The **server-confirmed** `CKEastSyncState` is authoritative, whichever device's create attempt the server actually accepts.
- If two devices race to create it (e.g., two devices' first launches overlap), exactly one creation succeeds; the device whose creation is rejected must refetch and adopt the server-confirmed epoch instead of its own locally generated one.
- No local Kept, Reflection, tombstone, or outbox mutation may be pushed until the authoritative epoch has been confirmed from the server — bootstrap blocks push, not read.
- On a device's first account association (e.g., first launch with iCloud already signed in, or first sync after account change confirmation), its existing local-only records are bound to the confirmed epoch atomically in the local envelope — stamped with the confirmed `dataEpoch` in the same atomic write — **before** any of them are pushed.

## iCloud account change boundary

- Detect CloudKit account availability and account-identity changes using the native CloudKit account APIs (account status queries and the platform's account-change notification mechanism) — not by inference from sync failures alone.
- **Temporary iCloud unavailability must never delete local data.** The app remains fully usable on local data regardless of account state.
- **When the iCloud account changes (a different iCloud account is now signed in than the one sync was last operating against), pause sync immediately** — do not attempt to reconcile against the new account automatically.
- **Never automatically upload local Kept or Reflection content that belonged to a prior account into a newly detected account.** Local data belonging to the previous account's sync session must not be silently associated with, or pushed into, the new account's private database.
- Preserve all local data on-device regardless of account change — nothing is deleted merely because the signed-in account changed.
- **Require a deliberate, explicit user confirmation** before associating or merging existing local content with the newly detected account.
- Store only the minimum account-scope identifier needed to detect a change (e.g., an opaque per-account token sufficient to notice "this is different from before") — never send this identifier to analytics.
- Required tests must prove that an account change can never silently leak Reflection content into a different private database (see Required tests).

## Free-limit behavior

Current limits are unchanged: free users may have up to 3 Kept wisdoms and up to 3 Reflections; Keeper removes both limits. Cloud synchronization must never delete or hide valid user data merely because a merged, multi-device collection exceeds a free limit. If a free user ends up with more than the current limit after migration or multi-device sync: keep all existing records visible, preserve all Reflection content, and block only the creation of *additional* new Kept or Reflection records until the count returns below the applicable limit or the user becomes Keeper. Never automatically delete, and never silently hide, excess records.

## User data access

**Export My Data:**

- Exports UTF-8 JSON through the iOS share sheet.
- Includes: an export schema version, an export timestamp, and the user's active Kept/Reflection content (the active `KeptRecord` fields that are user-facing content).
- Does **not** include: tombstones, outbox operations, server change tokens, any CloudKit system fields, the account-scope identifier, `mutationId`, or any other internal diagnostic/sync metadata.
- Does not require an EAST. server — it reads directly from the local envelope (and, implicitly, whatever has already synced into it).

**Delete All Synced Data:**

- Follows the `dataEpoch` reset process in full (see Data epoch and Delete All reset safety).
- Clears the current device's local synced content and the protected migration recovery snapshot.
- Hard-deletes prior-epoch active records and tombstones from the private CloudKit database, as retryable cleanup.
- Does **not** delete Keeper entitlement or purchase history — those remain governed entirely by StoreKit/Restore Purchases and are outside this feature's scope.
- Cannot instantly erase local copies held on another, currently-offline device — but that device must clear its own stale synced content and stale outbox before it is allowed to push anything, as soon as it observes the new epoch (see Data epoch and Delete All reset safety).

Neither feature is implemented in this documentation phase.

## Rating-request scope

This ADR documents, but Build 26's documentation phase does not implement, the rating-request mechanism:

- **One successful request submission per installation/local app-data lifetime** — not an absolute, permanent-across-all-time guarantee. If the app is uninstalled and reinstalled, EAST.'s own local eligibility counter and attempt flag are reset along with the rest of its local state, and a fresh installation may reach eligibility and submit a request again.
- Eligibility becomes true after the fourth genuinely completed new ritual — counting only successfully completed new wisdom reveals, never app opens, and never the recovery/replay of an already-committed reveal; never after purchase, restore, or a failed/abandoned ritual.
- `rating_request_attempted` remains `false` whenever no active scene exists or the native call cannot be submitted, so a later valid opportunity remains possible.
- `rating_request_attempted` becomes `true` only once the native request call has actually been successfully handed to iOS — regardless of whether iOS chooses to visibly display anything.
- **Apple's own system-level rate limiting remains authoritative across reinstalls** — EAST. resetting its own local flag on reinstall does not mean the system will necessarily show a prompt again; Apple's own request-frequency limits apply independently of anything EAST. tracks locally.
- **Do not add Keychain or CloudKit storage solely to make the rating flag survive reinstall or sync across devices.** This flag is deliberately ordinary local app state, not synced content, and does not need protection or persistence beyond the app's own lifetime — introducing Keychain or CloudKit here would be unjustified complexity for a flag whose only purpose is a soft, best-effort, per-installation courtesy limit, with the real limit enforced by Apple regardless.
- The native bridge call must only be made from a stable Home idle/revealed state, and must never interrupt notification-permission UI, another modal, or the ritual's own animation sequence.
- Prefer a small native iOS `MethodChannel` bridge over adding a third-party package, using the current StoreKit/`AppStore` review API where available and an availability-safe fallback for older supported iOS versions.

## Analytics boundary

Analytics transport remains deferred until local storage and CloudKit sync are stable in the field — this ADR does not implement analytics. The approved future aggregate events are: `app_open`, `ritual_started`, `wisdom_revealed`, `wisdom_kept`, `reflection_created`, `keeper_screen_viewed`, `purchase_started`, `purchase_completed`, `restore_completed`, `notification_permission_result`, `objects_opened`, `etsy_link_opened`. The following must never be sent, structurally, not merely by convention: wisdom text, reflection text, any user-written content, which specific wisdom was saved, `revealId`, any Kept item ID, any CloudKit record ID or sync metadata (change tokens, `mutationId`, `dataEpoch`), the account-scope identifier, persistent advertising identifiers, screen recordings, session replay, unnecessary device profile data, or personal profiling data. When eventually implemented, a typed analytics facade (named methods per event, not a generic `track(String, Map)` call) should make content leakage structurally difficult rather than merely discouraged. No persistent analytics queue should be built while the sink remains a no-op.

## Privacy and App Store consequences

Build 26 requires, ahead of release:

- A Privacy Policy update describing private iCloud synchronization of Kept wisdoms and Reflections.
- Re-review of the App Store privacy answers (App Privacy "nutrition label") to reflect the new iCloud data use.
- Privacy-manifest and required-reason API validation performed against the **final Xcode Archive**, not just this repository's own source tree.
- CloudKit capability configuration and CloudKit container creation in the Apple Developer portal / Xcode signing settings.
- A provisioning-profile refresh after any capability change.
- Development-schema testing in CloudKit before any production-schema deployment.
- Explicit, deliberate production CloudKit schema deployment before TestFlight or App Store release.

## Architecture boundary (relative to `EAST_ARCHITECTURE_V1.md`)

This decision is intentionally limited to **private, Apple-device-only synchronization** of Kept wisdoms and Reflections. It does not: introduce an EAST. account system; replace the future website/backend architecture described in `EAST_ARCHITECTURE_V1.md` Section 8.2 (`reflections`, `kept_reflections`, `user_wisdom_favorites`); sync the ritual lock (`daily_wisdom_access`) in any form; create cross-platform (e.g., Android or web) sync; or commit EAST. to CloudKit as the sync mechanism for any future platform. This is a deliberate, bounded, iOS-native interim layer — see the companion update to `EAST_ARCHITECTURE_V1.md` (Section 33) for the exact boundary language inserted into the authoritative document.

## Alternatives rejected

- **A fully separate `CKReflection` record type**, referencing a `CKKeptWisdom` by ID. Rejected: nothing in the current product allows a reflection to exist without its Kept wisdom; this would be speculative abstraction for a hypothetical future requirement.
- **A canonical, stable `wisdomId` on every wisdom content entry**, introduced now. Rejected: `revealId` plus the text snapshot already satisfy this build's identity requirements; a separate content-modeling decision, not required to ship this feature.
- **Silent-push-triggered background sync** in the first implementation. Rejected: adds an APNs dependency and materially more complexity for a feature whose data volumes and urgency don't require it.
- **`NSFileProtectionCompleteUntilFirstUserAuthentication`** instead of `NSFileProtectionComplete`. Rejected: there is no locked-device background access path in this build that would need the weaker class.
- **Field-level CRDT-based conflict merging.** Rejected as unjustified complexity for single-owner, private-database records at this data volume.
- **Immediately hard-deleting a `CKKeptWisdom` record on every normal item deletion.** Rejected: without a minimized tombstone, a device offline at deletion time and syncing later would see the record simply vanish, unable to distinguish "deliberately deleted" from "never existed here" — risking stale-device resurrection. Hard deletion is reserved for the epoch-scoped Delete All Synced Data cleanup.
- **Freshly generating a random `revealId` for every migrated legacy Kept item.** Rejected: breaks idempotency across retries/devices; a deterministic, namespace-derived UUID solves this.
- **Setting migrated `updatedAt` to the migration's execution time.** Rejected: would make old, untouched records incorrectly win future conflicts against genuinely newer edits.
- **A single `KeptRecord` type that can also represent a content-cleared tombstone**, instead of a separate `SyncTombstone` type. Rejected: it would force every consumer of active records (UI, migration, Export My Data) to defensively check for a tombstone-shaped record, whereas a separate type makes it structurally impossible for tombstone data to appear in the Kept UI or in an export.
- **Treating soft tombstones as native CloudKit record deletions.** Rejected: soft tombstones must remain ordinary record updates so they propagate through the standard changed-record pull path; conflating them with native deleted-record IDs (which only apply to records actually hard-deleted) would misrepresent how they are detected and applied.
- **Silently associating/merging local content with a newly detected iCloud account.** Rejected: could cross-contaminate one account's private Reflection content into another account's private database without the user's knowledge; deliberate confirmation is required instead.
- **Storing the rating-request attempt flag in Keychain or CloudKit** so it survives reinstall/syncs across devices. Rejected: unjustified complexity for a soft, best-effort local courtesy limit; Apple's own system-level throttling is the real backstop regardless of what EAST. remembers locally.

## Known tradeoffs

- A free user who reaches their Kept/Reflection limit independently on two offline devices and then syncs will temporarily see all of their items merged even though this exceeds the stated free limit — by design; new creation is blocked, but nothing already created is ever deleted or hidden.
- A second device or a reinstall may unlock a new daily wisdom sooner than the original device's 24-hour lock would have allowed, because the rolling lock is deliberately not synced.
- Whole-record last-writer-wins (with epoch and `mutationId` tie-breaking) means a genuine simultaneous edit to two different fields of the same record on two devices will discard one device's edit entirely rather than merging both.
- Migrated `revealId` values are deterministically reconstructed, not historically real, since Build 25 never recorded reveal identity.
- The single historical `date` field in Build 25 records is mapped onto both `revealedAt` and `keptAt`, so migrated records cannot express "revealed on one day, kept on a later day" even though Build 26-native records can.
- A local mutation that never reaches CloudKit before the app is uninstalled is genuinely lost — the durable outbox protects against process/restart loss, not uninstall loss.
- The protected pre-migration recovery snapshot is retained for a bounded window, not forever.
- Reinstalling the app resets EAST.'s own local rating-request eligibility/attempt state, so a fresh install may see a rating request submitted again — bounded in practice only by Apple's own system-level rate limiting, not by anything EAST. persists.
- A currently-offline device is not instantly affected by a remote Delete All Synced Data reset — it retains its local copy of pre-reset content until it next comes online and observes the new epoch, at which point it must clear that content before it can push anything.

## Implementation phases

1. **iPhone-only `Info.plist` cleanup.**
2. **`revealId` introduction and the Build 25 active-daily-record backfill.**
3. **Protected local state envelope and Build 25 Kept/Reflection migration.**
4. **CloudKit capability, account-change boundary, sync-state epoch, foreground sync, outbox, and soft tombstones.**
5. **Export My Data and Delete All Synced Data.**
6. **Rating request (eligibility tracking and native bridge).**
7. **Analytics deferred / interface only, no transport.**

Each phase requires its own isolated commit and its own test gate passing before the next phase begins. No phase requires an intermediate App Store release — all seven may land within the same Build 26 development branch, gated by review and tests rather than by shipping.

## Required tests

- **One active record per `revealId`:** saving the same reveal twice is idempotent and reuses the existing active record rather than duplicating it.
- **Identical text, different `revealId`, remain distinct:** two Kept records with identical `wisdomText` but different `revealId` values are and remain two separate records.
- **Local mutation / outbox enqueue atomicity:** a simulated crash between writing a local mutation and writing its outbox entry never leaves one without the other (both present or both absent after recovery).
- **Remote apply / server-token advancement atomicity:** a simulated crash between applying pulled remote changes and persisting the new change token never leaves the token advanced without the changes durably applied, or vice versa.
- **Serialized mutation/merge behavior:** concurrent local mutation and remote-merge attempts against the envelope are provably serialized through one coordinator path, never interleaved unsafely.
- **Pending undo surviving a restart safely:** a `pendingUndoDeletion` still within its window survives a simulated app restart and the active record is restored, not finalized as deleted.
- **Reflection-only delete does not create a tombstone:** clearing a reflection while keeping the Kept item produces an ordinary active-record update, never a `SyncTombstone`.
- **Delete All `dataEpoch` preventing stale-device resurrection:** a synthetic offline device holding pre-reset data and a queued outbox mutation, upon later syncing, discards its stale-epoch state and outbox before pushing anything, rather than recreating deleted content.
- **Old-epoch outbox is never pushed:** an outbox entry stamped with a superseded `dataEpoch` is discarded locally, never transmitted to CloudKit.
- **Absent-state epoch bootstrap:** on a private database with no `CKEastSyncState` yet, the device generates a random epoch, successfully creates the control record, and no local mutation is pushed before that creation is confirmed.
- **Simultaneous two-device bootstrap:** a synthetic race between two devices both attempting to create `CKEastSyncState` for the first time results in exactly one creation succeeding; the losing device refetches and adopts the server-confirmed epoch rather than keeping its own locally generated one, and neither device pushes before it holds the confirmed epoch.
- **`pendingEpochCleanup` interruption and resume:** a simulated app termination mid-cleanup leaves the `pendingEpochCleanup` marker intact, and a later foreground sync resumes the same job (using its continuation/query cursor where applicable) rather than losing or restarting it incorrectly.
- **`pendingEpochCleanup` partial failure:** a simulated failure partway through a batch of prior-epoch hard deletions leaves the job in a state that safely retries the remaining batches without re-deleting or skipping records.
- **`pendingEpochCleanup` final verification before marker removal:** the marker is removed only after a check confirms no records from the target prior epoch(s) remain in CloudKit — a test asserts the marker is not removed merely because delete requests were issued.
- **`pendingEpochCleanup` is never treated as stale:** the job's own current-epoch bookkeeping is never discarded by the epoch-aware push rule, even though it exists to clean up old-epoch data.
- **Account change pausing sync and preventing cross-account upload:** a simulated iCloud account change pauses sync immediately and never uploads the prior account's local content into the newly detected account's private database without explicit confirmation.
- **Soft tombstones arrive as changed records:** a soft tombstone is received via the ordinary changed-record pull path, not via native deleted-record IDs; a test asserts native deleted-record IDs are only ever produced by actual hard deletion (Delete All Synced Data cleanup).
- **Exact conflict-order precedence:** synthetic fixtures prove the order — epoch, then `updatedAt`, then tombstone-wins-on-tie, then `mutationId` tie-break within same active/deleted state, with `keptAt`/`revealedAt` never influencing the outcome.
- **`daily_wisdom_access` backfill using repository/read-back verification:** the backfill goes through `DailyAccessRepository`'s existing storage adapter and persistence coordinator, writes once, reads back, and verifies `revealId` plus every previously-unchanged field.
- **Rating attempt scope is per installation:** a simulated uninstall/reinstall resets local eligibility/attempt state, and a fresh installation can reach eligibility and submit a request again.
- **Export excludes all internal sync/diagnostic metadata:** an exported payload never contains tombstones, outbox entries, change tokens, CloudKit system fields, the account-scope identifier, or `mutationId`.
- Protected local store: read/write/delete round-trip; `NSFileProtectionComplete` actually applied to the envelope, its temp file, the recovery artifact, and the recovery snapshot; corruption recovery.
- Migration: verify-before-delete sequencing; idempotent re-run; a simulated crash between `verified` and `complete` recovers correctly; all existing legacy v1/v2 decode tests continue to pass unmodified; undecodable entries land in the protected recovery artifact.
- Legacy identity/date mapping: deterministic legacy `revealId` across retries/devices; preservation of `FavoriteItem.id`; `revealedAt`/`keptAt` both equal the legacy date; `updatedAt` equals `reflectedAt` when present, otherwise the legacy date, and is never the migration's own execution time.
- Recovery-snapshot expiration: retained before all three retention conditions are met; deleted once they are; deleted immediately under Delete All Synced Data regardless of schedule.

## Rollback/recovery approach

- Migration: the protected pre-migration recovery snapshot is the rollback path if the envelope's migrated content is later found to be wrong, for as long as it is retained; the old `favorites` key itself is never removed before state reaches `verified`.
- Sync: because all local mutations succeed locally first and cloud sync is strictly secondary/asynchronous, disabling sync entirely at any time leaves the app fully functional on local data alone.
- Deletion: the crash-safe undo window and soft-tombstone design are themselves recovery mechanisms against premature/incorrect deletion propagation — an undo restores the active record purely locally, and even after finalization the tombstone retains identity/version metadata rather than vanishing outright, until Delete All Synced Data explicitly hard-deletes it.
- Data epoch: the epoch control record is itself the recovery mechanism against stale-device resurrection after a reset — any device observing a newer epoch must reconcile against it before it can push anything.
- CloudKit schema: development-schema testing must fully precede any production-schema deployment.

## Explicit non-goals

- No EAST. account or login system.
- No introduction or replacement of the future website/backend architecture in `EAST_ARCHITECTURE_V1.md`.
- No syncing of the rolling 24-hour ritual lock, in any form.
- No cross-platform (Android/web) sync.
- No commitment to CloudKit as the sync mechanism for any future platform beyond this iOS app.
- No canonical/stable `wisdomId` on wisdom content entries.
- No field-level conflict merge or CRDT.
- No silent push, APNs dependency, background fetch, or continuous polling in this first implementation.
- No standalone Reflection entity independent of its Kept wisdom.
- No analytics transport or persistent analytics queue.
- No claim that the durable local outbox survives app uninstall — it does not.
- No automatic association/merge of local content into a newly detected iCloud account without explicit user confirmation.
- No Keychain or CloudKit storage for the rating-request attempt flag.
- No implementation of storage, CloudKit, account-change handling, rating request, Export My Data, Delete All Synced Data, or analytics in this documentation phase — this ADR is the specification those later phases must follow.
