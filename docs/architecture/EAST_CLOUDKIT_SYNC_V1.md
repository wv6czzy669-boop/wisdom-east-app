# EAST. CloudKit Sync Design v1.0 (Phase 4A through Phase 4F+, current shipped state)

**Status (current, Build 26+):** CloudKit sync is implemented and wired end to end. Sections 1-15 below record the design and incremental build order (Phase 4A's pure Dart sync domain through Phase 4E-1's integration foundations) and remain accurate as history and as the frozen record/conflict/privacy model still in force. Beyond Phase 4E-1, the phases anticipated in §15.11 (4E-2 real-mutation wiring, 4E-3 incoming-apply, 4E-4 bootstrap/reconciliation, 4E-5 end-to-end tests, and 4F startup/lifecycle wiring) have since been implemented, plus the "Remove from iCloud" deletion/recovery work and a diagnostics/recovery layer that were not yet designed when Section 15 was written. The current shipped architecture:

- **Kept + Reflections sync through the user's private CloudKit database**, exactly as specified in Sections 1-4 below (private database only, `EASTKeptZone`, deterministic `revealId`-derived record names, whole-record last-writer-wins conflict resolution with the `dataEpoch` precedence rule).
- **Local-first**, unconditionally: local writes complete and are readable before any sync work happens, and CloudKit unavailability never blocks reading or editing existing local content (§3).
- **`revealId` is the sync/occurrence identity** for every Kept/Reflection record — never wisdom text or a display date (§2.2).
- **Daily rolling 24-hour ritual access remains device-local only, in every form** — never represented in any CloudKit record, outbox entry, or sync-domain model (§1).
- **Remote-first bootstrap** for an existing local install associating with CloudKit for the first time, and **account association/change handling** (a stored opaque per-account scope token, `AccountSyncState` bootstrap/association states, and an `associationRequired` transition on a detected account change) are both implemented (`lib/sync_integration/`, `lib/sync_persistence/account_sync_state.dart`).
- **`dataEpoch`** is implemented as the authoritative first-precedence conflict/reset boundary (§4.1, `lib/sync/data_epoch.dart`).
- **Outbox, tombstones, and conflict reconciliation** are implemented (`lib/sync_persistence/`, `lib/sync/conflict_resolution.dart`, `lib/sync/sync_tombstone.dart`).
- **Crash-consistent server change token / checkpoint handling** is implemented (`SyncPersistenceStore.commitIncomingBatchCheckpoint`, `lib/sync_persistence/incoming_batch_checkpoint.dart`).
- **A "Remove from iCloud" deletion/recovery state machine exists** (`lib/sync_deletion/`, `lib/controllers/icloud_removal_controller.dart`), including **deletion ordering, an epoch barrier, and `localFinalizePending` behavior** (`lib/sync_persistence/pending_deletion_transaction.dart`, `lib/sync_deletion/local_deletion_finalizer.dart`, `lib/sync_deletion/cloud_kit_remote_deletion_runner.dart`).
- **A full sync-runtime pipeline exists** — startup, foreground, account-change, and retry-triggered sync passes, with bounded backoff (`lib/sync_runtime/cloud_kit_sync_runtime_coordinator.dart`).
- **A Sync Diagnostics / Recovery core now exists** (`lib/sync_diagnostics/sync_health_evaluator.dart`, `lib/sync_diagnostics/sync_recovery_coordinator.dart`, wired in `lib/services/app_services.dart`). This diagnostics layer is currently **foundation infrastructure only** — it is **not exposed as a user-facing diagnostics screen** anywhere in the app, and, per the same privacy rules as the rest of this document (§2.8, §7, §15.10), it never records `wisdomText`, `reflectionText`, or any other private Kept/Reflection content — only categorical status, counts, and opaque identifiers where already safe to log.
- **No EAST login or backend account exists.** Authentication remains entirely the user's own device-level iCloud sign-in (§1) — EAST never creates, stores, or manages credentials of its own.

This document is the precise design ADR-007 (`docs/decisions/ADR-007-build-26-local-storage-and-icloud-sync.md`) requires its implementation phases to follow.

**Scope of this document:** the CloudKit boundary, record schema, local-first behavior, conflict/deletion rules, account-boundary behavior, sync-engine choice, and the future native bridge contract. It does not implement any of these — see `docs/architecture/EAST_ARCHITECTURE_V1.md` Section 33 for the one-paragraph product-level summary, and ADR-007 for the original decision record.

---

## 0. Relationship to ADR-007 and one explicit supersession

This document implements ADR-007's design precisely, with one deliberate refinement that supersedes a single specific detail of ADR-007's original record model — stated here explicitly, per this phase's own instruction not to silently resolve a conflict between an older accepted decision and a new one.

**ADR-007 originally specified:** `CKKeptWisdom.recordName = KeptRecord.id` (the local Kept record's own identity, independent of `revealId`, which appeared only as an ordinary field).

**This document instead specifies:** `CKKeptWisdom.recordName` is deterministically derived from the canonical `revealId` (Section 2.2 below), not from `KeptRecord.id`.

**Why this is a safe, deliberate refinement, not a silent change:**

- The Phase 4A instruction that produced this document explicitly requires "a deterministic CloudKit record name derived from canonical `revealId`" as the core identity rule for this phase, restated multiple times ("each saved wisdom occurrence is identified by its stable canonical `revealId`"). This is the newer, explicit decision.
- It does not weaken any existing invariant. `KeptStateEnvelope._validate` already enforces that at most one active `KeptRecord` exists per `revealId` at any time (duplicate `revealId` is rejected), so `revealId` is already a valid, already-enforced 1:1 record identity for every active record — exactly the property a `recordName` requires.
- `revealId` is always a validated canonical UUID (v4 for a genuine Build 26 reveal, v5 for a deterministic Build 25 migration identity — see `lib/utils/canonical_uuid.dart`), which is a materially safer, more constrained input for a deterministic external identifier than `KeptRecord.id`, which may still be an arbitrary legacy string (`sr-v1-<micros>-<serial>`, `legacy-v1-<index>-<hash>`, `duplicate-v1-<index>-<hash>`) for records migrated from Build 25.
- `KeptRecord.id` remains fully intact as the record's own local identity (used for local list rendering, removal/restore, and reflection edits) — this refinement affects only what value is projected into the CloudKit `recordName` field, not what `KeptRecord.id` means or how it is used locally.
- Both choices satisfy ADR-007's tombstone-continuity requirement ("reused as the corresponding `SyncTombstone.id` if the record is later deleted; never regenerated") equally well, since `revealId`, like `id`, is fixed for the lifetime of a `KeptRecord` and copied forward unchanged into its tombstone.

No other part of ADR-007 is altered by this document. Everywhere ADR-007 says "`recordName`... the stable local `KeptRecord.id`", read it as "the deterministic derivation of the record's `revealId`" per Section 2.2 below; every other rule (tombstone shape, conflict order, data epoch, outbox, account-change boundary) is unchanged.

---

## 1. CloudKit boundary

- **Private database only.** No public database. No shared database. No CloudKit sharing UI (`CKShare`) of any kind — Kept wisdoms and Reflections are single-owner, private content; there is no product requirement for one user to share a Kept item with another.
- **One custom record zone**, dedicated entirely to EAST protected user content: `EASTKeptZone`. No system default zone is used for this data (the default zone cannot be used for atomic zone-wide operations or per-zone change tokens in the way this design needs).
- **No separate EAST account.** Authentication is entirely delegated to the user's own device-level iCloud sign-in; EAST never creates, stores, or manages credentials of its own.
- **No daily-access records in CloudKit, ever, in any form.** `daily_wisdom_access`, the rolling 24-hour lock, `revealedAt`/`unlockAt` belonging to daily access, current ritual screen/animation state, ritual eligibility, any pending daily reveal, private diagnostics, and analytics data are structurally excluded — no type in the pure Dart sync domain (Section 6) can represent any of them, and no code path constructs a CloudKit projection from `DailyWisdomRecord` (enforced by a dedicated test — see `test/sync/sync_domain_privacy_test.dart`).

## 2. Record model

One CloudKit record per saved reveal occurrence (record type `CKKeptWisdom`), covering both the Kept content and its attached Reflection together — never two related records, never the whole collection as one blob. This matches ADR-007's rejection of a separate `CKReflection` type: nothing in the product allows a Reflection to exist without its Kept wisdom.

### 2.1 Record type and zone

| Constant | Value |
|---|---|
| Custom zone name | `EASTKeptZone` |
| Kept/Reflection record type | `CKKeptWisdom` |
| Sync-state singleton record type | `CKEastSyncState` |
| Sync-state singleton record name | `sync-state` (exactly one instance ever exists per private database) |

### 2.2 Deterministic record name derivation

```
recordName = "east-kept-" + revealId
```

- `revealId` must first pass `isCanonicalUuidV4OrV5` (`lib/utils/canonical_uuid.dart`) — the same validation `KeptRecord` itself already requires. A noncanonical `revealId` never produces a record name; derivation throws.
- The `east-kept-` prefix is deliberate, not cosmetic: it guarantees the derived name can never collide with the fixed singleton name `sync-state`, and it makes every EAST-owned record name self-describing in CloudKit Dashboard inspection without ever containing wisdom or Reflection content.
- Derivation is a pure function of `revealId` alone — never of `wisdomText`, a display date, `KeptRecord.id`, or any timestamp. Two different `revealId` values always produce two different record names; the same `revealId` always produces the same record name, on every device, on every run.
- This rule applies identically to a record's active form and its tombstone form — the record name never changes when a `KeptRecord` transitions to a `SyncTombstone`, exactly matching ADR-007's continuity requirement.

Implemented in pure Dart as `deriveKeptWisdomRecordName(String revealId)` (Section 6.1) — no platform channel call is required to compute it; the same derivation must be usable identically on the Swift side once Phase 4B implements real CloudKit calls, so the algorithm above (not merely its Dart implementation) is the authoritative specification.

### 2.3 Fields — active form

| Field | Type | Source | Notes |
|---|---|---|---|
| `recordName` | String | §2.2 | Identity. Immutable once created. |
| `revealId` | String (UUID) | `KeptRecord.revealId` | Immutable identity field. |
| `wisdomText` | String | `KeptRecord.wisdomText` | Immutable identity field (snapshot). Never used as `recordName` or as a dedup key. |
| `revealedAt` | Int64 (ms since epoch, UTC) | `KeptRecord.revealedAt` | Immutable identity field. |
| `keptAt` | Int64 (ms since epoch, UTC) | `KeptRecord.keptAt` | Immutable identity field. |
| `reflectionText` | String? | `KeptRecord.reflectionText` | Mutable. Absent (not merely empty) when there is no Reflection. |
| `reflectedAt` | Int64? (ms, UTC) | `KeptRecord.reflectedAt` | Mutable. Must be absent whenever `reflectionText` is absent. |
| `updatedAt` | Int64 (ms, UTC) | `KeptRecord.updatedAt` | Client modification timestamp — drives conflict resolution (§4). |
| `mutationId` | String (UUID) | `KeptRecord.mutationId` | Deterministic tie-breaker only, never an identity. |
| `dataEpoch` | String (UUID) | current device epoch | See §4.1. |
| `schemaVersion` | Int | `KeptRecord.currentSchemaVersion` | Currently `3`. Read from the single existing constant — never a second, independently-maintained literal. |
| `isTombstone` | Bool | `false` for this form | Present on every record so a malformed record missing this field is unambiguously rejected (§2.6), not defaulted. |

### 2.4 Fields — tombstone form

Same `recordType` (`CKKeptWisdom`), same `recordName` space (identity carries over from the deleted active record — never a new name).

| Field | Type | Source | Notes |
|---|---|---|---|
| `recordName` | String | the same name the active record used | Unchanged. |
| `isTombstone` | Bool | `true` | |
| `deletedAt` | Int64 (ms, UTC) | `SyncTombstone.deletedAt` | Presence of a tombstone-form record for a `recordName` is itself what marks that occurrence deleted. |
| `updatedAt` | Int64 (ms, UTC) | `SyncTombstone.updatedAt` | |
| `mutationId` | String (UUID) | `SyncTombstone.mutationId` | |
| `dataEpoch` | String (UUID) | `SyncTombstone.dataEpoch` | |
| `schemaVersion` | Int | `SyncTombstone.currentSchemaVersion` (`1`) | Independently versioned from the active form's schema — a tombstone is a different shape, not a partially-populated active record. |

A tombstone-form record contains **no** `revealId`, `wisdomText`, `reflectionText`, `revealedAt`, `keptAt`, or `reflectedAt` field at all — cleared entirely, never merely blanked to an empty string or zero, matching ADR-007. (`revealId` is not duplicated as a wire field on the tombstone form because it is already recoverable from `recordName` itself, §2.2 — the local pure Dart `SyncTombstone` model still carries `revealId` internally, since it is what `recordName` is derived *from*, but that derivation happens once, locally, before the record is ever projected for CloudKit; the wire shape stays exactly as minimal as ADR-007 specifies.)

### 2.5 `CKEastSyncState` — singleton control record

| Field | Type | Notes |
|---|---|---|
| `recordName` | String | Fixed value `sync-state`. |
| `dataEpoch` | String (UUID) | Current authoritative epoch (§4.1). |
| `resetAt` | Int64? (ms, UTC) | Most recent epoch reset, if any. |
| `mutationId` | String (UUID) | Deterministic tie-breaker, consistent with every other record type. |
| `schemaVersion` | Int | `1`. |

### 2.6 Schema version, malformed records, and payload limits

- **Schema version is mandatory on every record.** A record missing `schemaVersion`, or carrying a `schemaVersion` this client does not recognize (currently anything other than `3` active / `1` tombstone / `1` sync-state), fails closed: it is never applied to local state, never merged, and never silently coerced into the nearest known shape. It is retained only as an opaque "unrecognized remote record" for later diagnostics (identifiers only — see §2.7), and the sync cycle continues with everything else it could safely process.
- **A record missing `isTombstone`** is treated identically to a schema-version failure — never defaulted to "active" or "tombstone", since guessing wrong in either direction is unsafe (guessing "active" could resurrect deleted content; guessing "tombstone" could destructively hide valid content).
- **An active-form record missing an identity field** (`revealId`, `wisdomText`, `revealedAt`, `keptAt`) fails closed the same way.
- **A tombstone-form record carrying identity/content fields it must not have** (e.g. a `wisdomText` present alongside `isTombstone = true`) fails closed — this is a malformed record, not a permissive union; a real tombstone this client itself writes never has this shape (§2.4), so seeing one from elsewhere indicates a defect or tampering, not a variant to tolerate.
- **`revealId` must be `isCanonicalUuidV4OrV5`.** A remote record whose `revealId` fails this check fails closed.
- **Payload limits, defensively enforced client-side before ever syncing** (independent of CloudKit's own much larger per-field limits, which are not relied upon as this client's own safety boundary):
  - `wisdomText`: capped at 10,000 Unicode code points. This is a defensive sync-domain guard, not a change to `KeptRecord`'s own validation (which places no upper bound on `wisdomText` today).
  - `reflectionText`: capped at `KeptRecord.maximumReflectionLength` (250 Unicode code points) — the same existing local limit, read from the single existing constant, never duplicated as a second literal.
  - A projection whose source `KeptRecord`/`SyncTombstone` violates either cap fails to construct at all (throws), so an over-limit record can never be enqueued for sync in the first place.

### 2.7 Device-independent serialization and timestamp canonicalization

- All timestamps are stored as **Int64 milliseconds since the Unix epoch, UTC** — never a locale- or timezone-dependent string, and never a platform-native date type whose wire representation could differ between Swift and Dart.
- Every timestamp is canonicalized to millisecond precision **before** being placed into a projection (mirroring `lib/utils/kept_timestamp_canonicalizer.dart`'s existing rationale for local storage) — a sub-millisecond-precision `DateTime` must never silently round-trip differently than the value CloudKit itself stores, which is exactly the class of defect already fixed once for local storage in this codebase (see the "Fix Kept timestamp round-trip persistence" commit). The pure Dart projection model canonicalizes on construction, not on read, so a canonicalized value round-trips byte-for-byte through `encode`/`decode`.
- No field's serialized form depends on device locale, timezone, or calendar — every date field is an absolute instant, exactly as `KeptRecord.revealedAt`/`keptAt`/`updatedAt`/`reflectedAt` already are.
- Diagnostic/log projections of any sync-domain object (§2.8) never include `wisdomText`, `reflectionText`, or `recordName` derivation inputs beyond the already-opaque `revealId` itself — see §7 (Privacy) for the exact rule.

### 2.8 Behavior for malformed or unsupported records — summary

A remote record that fails any check in §2.6 is never applied, never merged, never causes a crash, and never blocks processing of every other, valid remote record in the same fetch batch. It is skipped, and where diagnostics exist, only its `recordName` and the specific validation failure code are recorded — never any field that could contain user content.

## 3. Local-first behavior

- **Protected local storage (the ADR-007 local state envelope) is the UI's only source of truth.** No screen ever reads from, or waits on, CloudKit directly.
- **Local writes complete locally first, unconditionally.** A Keep, a Reflection edit, or a deletion is durable in the local envelope before any sync work is even considered.
- **A successful local change enqueues durable sync work** (an outbox entry, per ADR-007's Local state envelope/Deletion-outbox strategy). **Correction (Phase 4E-1):** the protected Kept envelope (`east_kept_state`) and the protected sync-persistence envelope (`east_sync_state`) are two separate physical files, each with its own independent atomic-write cycle (Phase 4D-1 §13.1) — a local Kept/Reflection mutation and its corresponding outbox enqueue can therefore never be one single cross-file atomic write, and this document no longer claims otherwise. Instead, **local state and sync intent are durably linked through replayable protected intent state and reconciliation, not one cross-file atomic write**: a durable, account-free local sync intent (Phase 4E-1, `lib/sync_integration/`) is recorded before the local write, advanced once the local write is confirmed, and only removed once the corresponding outbox enqueue is itself confirmed durable — so a crash at any point between the two file writes leaves a recoverable, replayable trace rather than a silently lost mutation. See this document's Phase 4E-1 section (§15) for the full design this correction anticipates; a reconciliation pass (Phase 4E-4) is the explicit backstop for any case the intent record itself does not cover (for example, Kept data that already existed locally before this mechanism was ever introduced).
- **The UI never waits for CloudKit.** There is no loading state, spinner, or blocking call anywhere in the Kept/Reflection UI that depends on network reachability or CloudKit round-trip latency.
- **A failed CloudKit operation retains its pending work.** The outbox entry is not removed, and local content is not altered, purely because a push or pull attempt failed.
- **Retries use bounded exponential backoff**, informed by CloudKit's own retry hints where the platform provides them (e.g. an `NSError`'s `CKErrorRetryAfterKey`) — never an unbounded tight retry loop, and never a retry policy that ignores a server-provided backoff hint when present.
- **A sync failure never removes valid local content.** The only paths that remove active local content are an explicit user deletion (via the crash-safe undo window, ADR-007) or a fully-verified Delete All Synced Data reset — never a sync error, a malformed remote record, or an account-status change.
- **CloudKit unavailability never blocks reading or editing existing local content.** Every existing `SavedReflectionsService`/`KeptRepository` operation (`load`, `toggle`, `saveReflection`, `deleteReflection`, `remove`, `restore`) continues to function identically whether or not CloudKit is reachable, exactly as it does today with no sync feature at all.

## 4. Conflict rules

Whole-record last-writer-wins remains the strategy (no CRDTs, no field-level merge — ADR-007's rejected-alternatives list), refined by a strict, deterministic precedence order. This section states that order precisely enough to implement as a pure function (Section 6.7) and to test exhaustively (Section 8).

### 4.1 Precedence order

1. **`dataEpoch` first.** The authoritative `CKEastSyncState.dataEpoch` controls which generation of data is valid. A candidate record whose `dataEpoch` does not equal the authoritative epoch is never applied and never wins, regardless of its `updatedAt` — this is the mechanism that prevents an old offline device from resurrecting data after a Delete All Synced Data reset (ADR-007, Data epoch and Delete All reset safety).
   - If exactly one of {local, remote} matches the authoritative epoch, that one wins outright — evaluation stops here.
   - If both match, proceed to step 2.
   - If **neither** matches (a state that should not occur in a correctly-operating client, since a device must reconcile its own epoch before comparing), resolution fails closed: neither side is applied, and the caller must re-fetch the authoritative `CKEastSyncState` before retrying. This is a deliberate refusal to guess, not an oversight.
2. **Newer `updatedAt` wins**, compared at millisecond precision (§2.7).
3. **Equal `updatedAt`, one side a tombstone:** the tombstone wins. A deletion is never silently undone by an equally-timestamped active edit.
4. **Equal `updatedAt`, same active/deleted state on both sides:** the lexicographically greater `mutationId` (canonical UUID string comparison) wins — a stable, deterministic tie-breaker with no reliance on wall-clock ordering.
5. **`keptAt` and `revealedAt` are never inputs to conflict resolution.** They are immutable identity fields, carried through unchanged from whichever side wins; the pure resolver function does not even accept them as comparison parameters (Section 6.7), so they structurally cannot influence an outcome.

### 4.2 Specific scenarios

- **Concurrent Reflection edits (two devices, same occurrence, both still active):** resolved entirely by steps 1–2 (same epoch expected; whichever `updatedAt` is newer wins in full — never a field-level merge of the two Reflection texts).
- **Keep on one device, delete on another:** if both changes reach the same epoch, resolved by steps 2–4 exactly as above; a delete is represented as a tombstone-form update to the same record (§2.4), not a native CloudKit record deletion, so it is received and resolved through the same ordinary changed-record path as any edit.
- **An old offline device returning after deletion:** its stale local active record is superseded the moment it observes either (a) a newer tombstone under the same epoch (step 2/3), or (b) a `dataEpoch` mismatch (step 1) if a Delete All Synced Data reset occurred while it was offline. Pull-before-push (§3, and ADR-007's Sync order) guarantees this resolution happens before the stale device is ever allowed to push its own outdated state.
- **Duplicate uploads of the same `revealId`:** by construction, at most one active local record can exist per `revealId` at any time (`KeptStateEnvelope._validate`), and `recordName` is derived solely from `revealId` (§2.2), so two "uploads" of the same occurrence are always the same CloudKit record — never two records. A concurrent double-save of the same occurrence (e.g. a retried operation) resolves to `CKError.serverRecordChanged` at the CloudKit layer (see below), not a duplicate.
- **Immutable-field mismatches:** if two active-form candidates for the *same* `recordName` ever carry different `revealId`, `wisdomText`, `revealedAt`, or `keptAt` values, this indicates corruption or tampering, not a legitimate conflict — resolution fails closed for that record (skipped, as in §2.8), never silently picking one side's identity fields.
- **Malformed remote records:** handled entirely by §2.6/§2.8 before ever reaching conflict resolution — a malformed record never participates in step 1–4 comparison at all.
- **`serverRecordChanged` (CloudKit's own optimistic-concurrency error):** treated as a signal to re-fetch the current server record and re-run the full precedence order above against the fresh server copy — never treated as an automatic "local wins" or "remote wins" shortcut.
- **Equal timestamps:** resolved deterministically by steps 3–4 above; there is no scenario where equal `updatedAt` values produce a nondeterministic or random outcome.
- **Clock skew:** because `updatedAt` is always the *writing device's own* clock reading (never a server-assigned timestamp), two devices with skewed clocks could, in principle, produce a genuinely "wrong" temporal ordering by human-real-time standards. This design does not attempt to detect or correct clock skew (no NTP-style correction, no server-timestamp substitution) — it only guarantees that whatever `updatedAt` values are actually recorded, the resulting resolution is *deterministic and reproducible* given those values, on every device, every time. This is a known, accepted limitation, consistent with ADR-007's existing rejection of more complex conflict machinery for this data volume.

### 4.3 Deletion safety

- **Deletion must never be silently undone by an older offline device.** Guaranteed structurally by §4.1 step 1 (epoch) and step 3 (tombstone-wins-on-tie) together with pull-before-push ordering (§3): an old device cannot push a resurrecting active-record write without first observing, and losing to, either the newer tombstone or the newer epoch.
- **Tombstones and `dataEpoch` are both required, not optional refinements** — a design lacking tombstones cannot distinguish "deliberately deleted" from "never existed here" for an offline device syncing later (ADR-007's rejected-alternatives list); a design lacking `dataEpoch` cannot safely support Delete All Synced Data against stale offline devices at all.
- **This design never uses naive "last local write always wins."** Every "last write wins" comparison above is scoped *within* a single, already-epoch-validated generation, and a tombstone always wins a tie against an equally-timestamped active edit — never the reverse.

## 5. Account-boundary behavior

| Situation | Behavior |
|---|---|
| No iCloud account available | Sync is inactive; the app is fully usable on local data; no error is surfaced as if it were a defect. |
| iCloud restricted (e.g. parental controls, MDM policy) | Same as above — treated as a normal, non-error "sync unavailable" state, not retried aggressively. |
| iCloud temporarily unavailable (e.g. transient system condition) | Same as above; retried later using the same bounded-backoff policy as any other retryable failure (§3). **Local data is never deleted for this reason.** |
| The iCloud account changes (a different account is now signed in than sync was last operating against) | Sync **pauses immediately**. The previous account's cached local content is never automatically uploaded into, associated with, or reconciled against the new account. A deliberate, explicit user confirmation is required before local content is associated with the newly detected account. |
| The user signs out and later signs back in to the *same* account | Treated as a normal account-availability transition (unavailable, then available again) — not an account *change*, since the account identity is unchanged; no confirmation prompt is required, and sync resumes normally once available. |
| The private database becomes unavailable (e.g. a CloudKit-side outage) | Treated as a retryable failure (§3); local data is never deleted or hidden because of it. |

- Account status and identity changes are detected using native CloudKit account APIs (account status queries and the platform's own account-change notification mechanism) — never inferred merely from a pattern of sync failures, which could be indistinguishable from an ordinary transient network problem.
- Only an **opaque per-account scope token** — sufficient to detect "this is a different account than before," nothing more — is ever stored locally to support this detection. It is never sent to analytics, never logged with any other identifying detail, and is not itself an iCloud identifier of any kind that could be independently meaningful outside this app's own change-detection.

## 6. Sync engine choice

**Inspected at Phase 4A:** `ios/Runner.xcodeproj/project.pbxproj` → `IPHONEOS_DEPLOYMENT_TARGET = 13.0` (all three Runner build configurations: Debug, Release, Profile). **Current (Build 26+):** the Runner target's minimum deployment target has since been raised to **iOS 15.0** (a later, separate decision from this document, unrelated to `CKSyncEngine`); the `EastWidgetExtension` target remains **iOS 17.0**.

**`CKSyncEngine`** (Apple's higher-level, state-machine-managed CloudKit sync API) requires iOS 17 / macOS 14 or later. Raising the minimum supported iOS version was explicitly out of scope for Phase 4A ("Do not raise the minimum iOS version in Phase 4A"), so `CKSyncEngine` **could not be recommended for that phase** — it was not available on the deployment target the app supported at the time. The Runner target's later move to iOS 15.0 still does not meet `CKSyncEngine`'s iOS 17 floor, so the operation-based recommendation below remains the implemented architecture; adopting `CKSyncEngine` would still be a distinct future decision, not one this document's history changes.

**Recommendation (implemented): an operation-based CloudKit architecture**, built directly on the CloudKit operation classes that have been available since well before iOS 13 and require no minimum-version increase:

- `CKFetchDatabaseChangesOperation` — discovers which zones in the private database have changed (in this design, effectively just `EASTKeptZone`, but the operation is still the correct primitive for discovering zone-level changes and deletions).
- `CKFetchRecordZoneChangesOperation` — pulls changed/deleted records within `EASTKeptZone` since the last persisted server change token, using the zone-level change token (persisted in `syncMetadata`, per ADR-007's Local state envelope).
- `CKModifyRecordsOperation` — pushes local outbox creates/updates (including soft-tombstone updates, §2.4) in batches, using per-record save policies and `CKRecord.ID`-scoped conflict detection (`serverRecordChanged`, §4.2).
- `CKFetchRecordsOperation` / direct record fetch — used narrowly for the `CKEastSyncState` singleton bootstrap/read (§ADR-007 Initial data-epoch bootstrap) and for the prior-epoch cleanup job's own record enumeration.
- Zone/database subscriptions (`CKRecordZoneSubscription`) are **not required** for this design's foreground-only sync timing (ADR-007, Sync timing) and are not part of Phase 4A or its immediate successor — silent push and background delivery are explicit non-goals.

This operation-based approach requires materially more of the durable bookkeeping ADR-007 already specifies as belonging to the local envelope (`syncMetadata`'s per-record pending-operation state, the zone's server change token, last-successful-sync bookkeeping) than `CKSyncEngine` would have required on its own — `CKSyncEngine` manages an equivalent state machine internally. This was an accepted, explicit cost of the deployment target in force when this design was chosen, not an oversight; it remains the implemented architecture today (deployment target now iOS 15.0, still below `CKSyncEngine`'s iOS 17 floor). If a future phase raises the minimum deployment target to iOS 17+, migrating from the operation-based design to `CKSyncEngine` would be a contained, later decision (an ADR of its own), not a change forced by this document.

**No third-party CloudKit package is added.** A native Swift implementation, using only Apple's own `CloudKit` framework, behind a narrow Flutter method/event-channel boundary (§7) is used throughout — consistent with this codebase's existing precedent (`MethodChannelFileProtectionBridge`, `lib/persistence/file_protection_bridge.dart`) of small, purpose-built native bridges rather than general-purpose third-party plugins.

## 7. Future native bridge contract

This section specifies the **proposed shape** of the Dart-to-Swift boundary for Phase 4B's implementation. **No networking is implemented by this phase** — the pure Dart `SyncEngine` interface (Section 8.8) is the Dart-side contract this bridge must eventually satisfy; the table below is what the native (Swift) side of that implementation will need to expose once it exists.

| Capability | Direction | Shape (indicative) |
|---|---|---|
| Account status | Swift → Dart | Method call returning one of: `available`, `noAccount`, `restricted`, `temporarilyUnavailable`, `couldNotDetermine` (mirroring `CKAccountStatus`, plus an explicit unknown/error case never silently coerced to `available`). |
| Configure zone | Dart → Swift | Method call: ensure `EASTKeptZone` exists in the private database; idempotent; returns success/failure, never partial state. |
| Start sync | Dart → Swift | Method call: begin the foreground sync cycle described in ADR-007's Sync order (fetch changes → apply → resolve conflicts → persist token → push outbox → follow-up pull → persist last-sync state). |
| Request immediate sync | Dart → Swift | Method call: same cycle, triggered explicitly (e.g. after a local mutation) rather than on the passive foreground/launch schedule. |
| Enqueue local change | Dart → Swift | Method call carrying a serialized `SyncChange` (Section 8.2) — the native side never independently constructs sync payloads from local storage; Dart remains the single source of truth for what is enqueued. |
| Fetch/apply remote changes | Swift → Dart | Event (or a paired method-call/response) carrying serialized `CloudKeptWisdomProjection` values (Section 8.4) for Dart-side conflict resolution (Section 8.7) and local envelope application — the native side never resolves conflicts or writes local storage itself. |
| Report sync state | Swift → Dart | Event stream carrying a serialized `SyncEngineStatus` (Section 8.5) — idle / syncing / error, with a privacy-safe, content-free message only. |
| Account-change events | Swift → Dart | Event carrying a serialized `AccountChangeEvent` (Section 8.6) — opaque before/after account-scope tokens plus a `requiresUserConfirmation` flag; never raw iCloud account identifiers, never analytics. |
| Retryable vs. permanent errors | Swift → Dart | Every failure response carries a symbolic error code Dart can classify via the pure `SyncErrorClassification` model (Section 8.9) — Dart owns the retry/backoff policy (§3); Swift only reports what happened, using CloudKit's own retry hint where available. |

**Privacy rules for the bridge, structurally, not merely by convention:**

- No method call or event payload ever includes `wisdomText` or `reflectionText` in a diagnostic, log, or error-detail field — only in the one legitimate content field of an actual enqueue/apply payload, which is never itself logged.
- No diagnostic message strings are ever built by string-interpolating record content — mirroring the existing `lib/utils/kept_diagnostics.dart` rule (stage names, exception types/codes, and already-sanitized `.message` strings only).
- The bridge is a thin transport: business rules (record projection, conflict resolution, epoch handling) live entirely in pure Dart (Section 8), so the native Swift side has no independent copy of any rule that could drift from the Dart implementation.

## 8. Pure Dart sync-domain foundations (implemented this phase)

All of the following live under `lib/sync/`, are pure (no `dart:io`, no platform channel, no network), and are fully unit-testable without a device, simulator, or CloudKit access. None duplicates `KeptRecord` as a second competing domain model — every type here is either a pure projection *of* `KeptRecord`/`SyncTombstone` or an independent sync-only concern (status, conflict input/output, engine port).

1. **`lib/sync/sync_record_identity.dart`** — `deriveKeptWisdomRecordName(String revealId)` (§2.2) plus the zone/record-type/singleton-name constants (§2.1).
2. **`lib/sync/data_epoch.dart`** — `DataEpoch` value type: validated canonical UUID v4, `DataEpoch.generate()`, `DataEpoch.parse(String)`, equality.
3. **`lib/sync/sync_tombstone.dart`** — `SyncTombstone` (§2.4's local counterpart, per ADR-007's Active record and tombstone models): `id`, `dataEpoch`, `updatedAt`, `deletedAt`, `mutationId`, `schemaVersion`.
4. **`lib/sync/cloud_kept_wisdom_projection.dart`** — `CloudKeptWisdomProjection`: the CloudKit-safe projection (§2.3/§2.4), built only via `CloudKeptWisdomProjection.active(KeptRecord, {required DataEpoch})` or `CloudKeptWisdomProjection.tombstone(SyncTombstone)` — no constructor accepts a `DailyWisdomRecord` or any daily-access type, and the type itself has no field that could hold one. Includes `toLogSafeSummary()`, which excludes `wisdomText`/`reflectionText` entirely (§2.7/§7).
5. **`lib/sync/sync_change.dart`** — `SyncChangeKind` (`create`/`update`/`delete`) and `SyncChange` (kind + projection + enqueued-at timestamp) — the pending-outbox-mutation model (ADR-007's per-record pending-operation state).
6. **`lib/sync/sync_status.dart`** — `CloudAccountStatus` enum, `SyncPhase` enum (`idle`/`accountUnavailable`/`accountRestricted`/`pausedForAccountChange`/`syncing`/`error`), `SyncEngineStatus` (phase + content-free message + last-successful-sync instant).
7. **`lib/sync/sync_error_classification.dart`** — `SyncErrorCategory` (`retryable`/`permanent`/`accountIssue`) and `classifySyncErrorCode(String symbolicCode)`, a pure lookup with no dependency on any real CloudKit error type.
8. **`lib/sync/conflict_resolution.dart`** — `ConflictCandidate` (projection + its role as local/remote), `ConflictOutcome` (winner + `ConflictReason`), and `resolveKeptWisdomConflict({required local, required remote, required authoritativeEpoch})` — the pure, deterministic implementation of §4.1's precedence order, including the immutable-field-mismatch fail-closed check (§4.2).
9. **`lib/sync/sync_engine.dart`** — `SyncEngine`, an abstract interface (the "port") with no implementation, covering exactly the capabilities in §7's table (`accountStatus`, `configureZone`, `startSync`, `requestImmediateSync`, `enqueueLocalChange`, a remote-changes stream, a status stream, an account-change-event stream).
10. A fake, in-memory `SyncEngine` implementation for tests lives in `test/sync_engine_test_helpers.dart` (test-only, following this codebase's existing convention of keeping test doubles in `test/`, e.g. `JsonRoundTrippingKeptStateStore` in `test/persistence_test_helpers.dart` — not shipped in `lib/`).

No durable outbox store, no real queue persistence, and no platform channel implementation are added in this phase — those belong to the later subphase that actually implements Phase 4B.

## 9. Explicit non-goals (Phase 4A)

Restated from the Phase 4A instruction, for a single authoritative list in this document: no iCloud entitlement, no CloudKit container, no network calls, no change to application/ritual behavior, no syncing of the rolling 24-hour lock or the current daily wisdom, no analytics, no rating-request changes, no export/delete UI, no Keeper/monetization changes, no package/version changes, and no start of Phase 4B.

(Phase 4B-1, Section 10 below, is the controlled start of Phase 4B this note anticipated — it does not retroactively change anything in Sections 1-9.)

## 10. Phase 4B-1 — native CloudKit bridge foundation (implemented this phase)

**Scope:** a compiling native Swift bridge and a Dart platform-bridge layer that can report account status, idempotently configure the private zone, report static bridge info, and emit content-free account-change events. **No user-content sync exists yet** — no method here uploads, downloads, merges, or deletes a Kept/Reflection record, and nothing in this phase adds the iCloud capability, registers a container, or deploys a CloudKit schema.

### 10.1 Bridge boundary

- **Two new native files categories:** six focused Swift types under `ios/Runner/` (`CloudKitSyncBridgeConstants`, `CloudKitAccountStatusMapper`, `CloudKitErrorClassifier`, `CloudKitAccountFingerprintUtility`, `CloudKitPrivateZoneCoordinator`, `CloudKitSyncBridge`), and a Dart platform-bridge layer under `lib/sync_platform/`, deliberately separate from the pure Phase 4A sync domain (`lib/sync/`).
- **`CloudKitSyncBridge` is registered** in `AppDelegate.didInitializeImplicitFlutterEngine` via `registerCloudKitSyncChannel`, following the exact same `registry.registrar(forPlugin:)` pattern already used for the Phase 3B file-protection channel. **Registration itself performs no CloudKit network request, no account lookup, and no zone creation** — every CloudKit call happens lazily, only in direct response to an explicit Dart method invocation.
- **`lib/sync_platform/cloud_kit_platform_bridge.dart` (`CloudKitPlatformBridge`) is deliberately not `lib/sync/sync_engine.dart`'s `SyncEngine`.** `SyncEngine`'s `startSync`/`requestImmediateSync`/`enqueueLocalChange`/`remoteChanges` describe real record synchronization, which does not exist yet — implementing `SyncEngine` now, with those methods missing or stubbed, would misrepresent capability that is not actually present. A future phase's real `SyncEngine` implementation may compose this bridge as one of its collaborators.
- **No production code invokes any of this in Phase 4B-1.** `lib/main.dart` and every repository/service file are unchanged; nothing outside `lib/sync_platform/` imports `MethodChannelCloudKitPlatformBridge` (enforced by `test/sync_platform/cloud_kit_platform_privacy_test.dart`).
- **Production code always uses `CKContainer.default()`**, never an explicit container identifier — Xcode-managed entitlements remain the single source of truth for which container is actually used once Phase 4B-2 activates the capability. The proposed identifier `iCloud.com.dogukan.dailywisdom` is written down (`CloudKitSyncBridgeConstants.proposedContainerIdentifierForPhase4B2`) but referenced nowhere else in bridge code.

### 10.2 Exact channel contract

| | Name |
|---|---|
| MethodChannel | `com.dogukan.dailywisdom/cloudkit_sync` |
| EventChannel | `com.dogukan.dailywisdom/cloudkit_sync_events` |

**Methods** (`MethodChannelCloudKitPlatformBridge` / `CloudKitSyncBridge.handle`):

| Method | Result shape (all fields content-free) |
|---|---|
| `getAccountSnapshot` | `{status, isPrivateDatabaseUsable, accountFingerprint?, fingerprintResolved, bridgeVersion}` |
| `configurePrivateZone` | `{success, zoneCreated, zoneAlreadyExisted, accountStatus, errorCode?}` |
| `getBridgeInfo` | `{bridgeVersion, expectedZoneName, expectedRecordTypes, privateDatabaseOnly, capabilityActivationExpected}` |

`status`/`accountStatus` values: `available`, `noAccount`, `restricted`, `couldNotDetermine`, `temporarilyUnavailable` (native), normalized on the Dart side (`CloudKitAccountAvailability`) with an additional `unknown` case for any value Dart does not recognize — never silently coerced to `available`.

**Event channel payload:** `{"event": "accountChanged"}` — the only event this phase ever emits, and the only content it ever carries.

**Error reporting:** every failure response carries a symbolic error code from the exact vocabulary `lib/sync/sync_error_classification.dart` already defines (`CloudKitErrorClassifier`'s Swift constants mirror those Dart constants by literal string value) — Swift only reports what happened; Dart classifies retryability by calling the existing `classifySyncErrorCode`, never a second, native-side classification scheme.

### 10.3 Account-fingerprint privacy treatment

- Derived only when `accountStatus == .available`, via `CKContainer.fetchUserRecordID` followed by `CloudKitAccountFingerprintUtility.fingerprint(for:)` — a namespaced (`com.dogukan.dailywisdom.cloudkit.account.v1`) SHA-256 hash of the record's `recordName`, computed with CryptoKit (no new dependency).
- **Never the raw CloudKit record name or user record ID** — only the opaque hash ever crosses the channel.
- **Never logged, in Swift or Dart**, and **never persisted anywhere in Phase 4B-1** — it exists solely to support a future same-account/different-account boundary check (Section 5).
- **An identity-fetch failure never falsely reports a different account** — `fingerprintResolved` simply stays `false`; the already-known account status is unaffected.
- Omitted from every Dart-side `toLogSafeSummary()`/`toString()` (`CloudKitAccountSnapshot`) — only `fingerprintResolved` (a boolean) is ever surfaced there.

### 10.4 Account-change event behavior

- `CloudKitSyncBridge` observes `NotificationCenter`'s `.CKAccountChanged` lazily, only while the Dart `EventChannel` has an active listener (`onListen`/`onCancel`) — registration/removal is idempotent (a repeated `onListen` without an intervening `onCancel` never double-registers).
- Delivered to the Flutter event sink only after hopping to the main thread (`DispatchQueue.main.async`), regardless of which queue `NotificationCenter` posted the underlying notification on.
- Carries no account identity, old or new — Dart must explicitly call `getAccountSnapshot` afterward to learn anything further (Section 5).
- Never itself triggers a sync operation, a zone configuration call, or anything else — it is purely advisory.
- A malformed/unrecognized raw event on the Dart side is silently dropped (`CloudKitAccountChangeEvent.tryParse` returns `null`), never surfaced as a stream error.

### 10.5 Zone-configuration behavior

- `CloudKitPrivateZoneCoordinator.configureZone` first attempts `CKDatabase.fetch(withRecordZoneID:)`; if the zone already exists, that is reported as success (`zoneAlreadyExisted: true`), never an error.
- Only when the fetch fails with `CKError.Code.zoneNotFound` does it proceed to create the zone via `CKModifyRecordZonesOperation` — the exact operation named in the Phase 4B-1 instruction.
- Scoped to exactly `CKContainer.default().privateCloudDatabase` and exactly the one Phase 4A custom zone name (`EASTKeptZone`) — never the public or shared database, never a second zone, never a subscription, never a user-content record.
- `configurePrivateZone` first checks `accountStatus`; if not `.available`, it reports failure with the symbolic code `accountTemporarilyUnavailable` without ever attempting a zone operation.
- **Never invoked automatically.** No app-startup or repository code calls `configurePrivateZone` in Phase 4B-1 — it exists only for a future, explicit call site.

### 10.6 Capability/container activation status

**Not yet applied.** No entitlements file exists in this repository. `ios/Runner.xcodeproj/project.pbxproj` has no iCloud/CloudKit capability, no container reference, and no Push Notifications/Background Modes addition. `getBridgeInfo().capabilityActivationExpected` is hardcoded `false` in this phase specifically so a future caller can distinguish "the bridge foundation exists" from "the capability has been activated."

### 10.7 Phase 4B-2 manual checklist (not yet performed)

Performed by a human in Xcode, on the developer's own machine, after this subphase is reviewed and approved — never automated, never performed by this coding session:

1. Open `ios/Runner.xcworkspace`.
2. Select the Runner target.
3. Verify the correct Apple Development Team and bundle ID.
4. Add the iCloud capability through Xcode.
5. Enable CloudKit only — not iCloud Documents or key-value storage.
6. Select or create `iCloud.com.dogukan.dailywisdom` (Section 10.1's proposed identifier).
7. Confirm Xcode-created entitlements and container association.
8. Allow Xcode to update signing assets.
9. Inspect any automatically added Push Notifications capability.
10. Build and run on the existing physical iPhone without uninstalling EAST.
11. Call only bridge-info/account-status/zone-configuration smoke operations.
12. Verify no Kept/Reflection record upload occurs.
13. Inspect the CloudKit development environment only.
14. Do not deploy schema to production.

### 10.8 Explicit non-goals (Phase 4B-1)

No iCloud capability, no container registration, no production CloudKit entitlements, no CloudKit schema deployment, no automatic CloudKit invocation during app startup, no record upload/download/merge/delete, no private-zone creation during normal application execution, no durable outbox, no background modes, no notification handling, no `aps-environment`, no third-party dependency, no minimum-iOS-version increase, no public/shared database use, and no start of Phase 4C.

### 10.9 Phase 4B-2 addendum — capability activation and zone-configuration hardening

Performed after this section was first written, on the developer's own machine and physical device, per the §10.7 checklist:

- The iCloud/CloudKit capability is now active (`ios/Runner/Runner.entitlements`: `com.apple.developer.icloud-container-identifiers = [iCloud.com.dogukan.dailywisdom]`, `com.apple.developer.icloud-services = [CloudKit]`).
- `CloudKitPrivateZoneCoordinator.configureZone`'s fetch-then-create flow gained one guarded fallback, scoped only to this one operation: a fetch that fails with `CKError.serverRejectedRequest` now also attempts `createZone` (the same call already used for `.zoneNotFound`), because a physical device was observed to have `EASTKeptZone`'s initial fetch fail with `.serverRejectedRequest` (CloudKit Console: `ZoneFetch` / `SERVER_ERROR` / `INTERNAL_ERROR`) even though directly saving the same zone succeeds, repeatably. This fallback never claims success on its own — the create/save attempt must still succeed, and its own normalized error (never the original fetch error) is what a caller sees if it does not.
- `CloudKitErrorClassifier` gained one additional stable symbolic code, `serverRejectedRequest`, for `CKError.Code.serverRejectedRequest` — non-retryable (Dart's `classifySyncErrorCode` defaults any code it does not recognize by name to `SyncErrorCategory.permanent`, which already covers this code without requiring a separate Dart-side entry).
- No other behavior in Section 10 changed.

## 11. Phase 4C-1 — private record schema and codec foundation (implemented this phase)

**Scope:** the production-grade record-schema and encode/decode foundation for both private record types (`CKKeptWisdom`, `CKEastSyncState`), on both the Dart and native Swift sides. **This phase remains entirely transport-free** — it prepares deterministic, validated records and parses/validates hypothetical wire payloads, but performs no real `CKDatabase` read or write, and adds no `CKModifyRecordsOperation`, `CKFetchRecordZoneChangesOperation`, subscription, or any other network-performing CloudKit API.

### 11.1 The record schema itself was already frozen by Phase 4A — this phase implements it, it does not redesign it

Sections 2.1–2.8 above (written during Phase 4A) already specify the complete, exact field set for both record types, their deterministic identity rule, their schema-versioning behavior, and their malformed-record handling. Phase 4C-1 introduces no new field, no renamed field, and no changed identity rule — it is the first phase to actually implement encode/decode against that existing specification, on both sides of the Dart/Swift boundary. Where this section restates a field name or rule from Section 2, it is restating it, not redefining it.

One genuine gap existed and is filled by this phase: no pure Dart type previously represented `CKEastSyncState` (§2.5) at all — only its `dataEpoch` value (`DataEpoch`) existed as a shared value type. This phase adds `CloudEastSyncStateProjection` (`lib/sync/cloud_east_sync_state_projection.dart`), a pure sync-domain type built the same way `CloudKeptWisdomProjection` already was in Phase 4A — no new fields beyond exactly what §2.5 already specifies (`dataEpoch`, `resetAtMs`, `mutationId`, `schemaVersion`), and no dependency on any local Kept/Reflection/daily-access model (there is nothing local to project *from* for this singleton record).

**Existing-implementation reuse, not a competing model:** `CloudKeptWisdomProjection.tryParseRemote` (Phase 4A) already implements every §2.6 fail-closed validation rule for `CKKeptWisdom` — this phase's Dart wire-boundary layer (§11.3 below) delegates to it rather than re-implementing field-level validation a second time, exactly as `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md`'s own engineering discipline (and the Lead Engineer's standing "never duplicate business logic, never create multiple sources of truth" rule) requires.

### 11.2 Exact record types and field names (restated from §2, for a single authoritative Phase 4C-1 cross-reference)

| Record type | Constant | Fields (required unless marked optional) |
|---|---|---|
| `CKKeptWisdom` — active form | `keptWisdomRecordType` | `recordName`, `revealId`, `wisdomText`, `revealedAtMs` (Int64), `keptAtMs` (Int64), `reflectionText` (optional String), `reflectedAtMs` (optional Int64, present iff `reflectionText` present), `updatedAtMs` (Int64), `mutationId`, `dataEpoch`, `schemaVersion` (currently `3`), `isTombstone` (`false`) |
| `CKKeptWisdom` — tombstone form | `keptWisdomRecordType` | `recordName` (unchanged from the active form), `isTombstone` (`true`), `deletedAtMs` (Int64), `updatedAtMs` (Int64), `mutationId`, `dataEpoch`, `schemaVersion` (currently `1`) — **never** `revealId`, `wisdomText`, `reflectionText`, `revealedAtMs`, `keptAtMs`, or `reflectedAtMs` |
| `CKEastSyncState` | `syncStateRecordType` | `recordName` (fixed literal `"sync-state"`), `dataEpoch`, `resetAtMs` (optional Int64), `mutationId`, `schemaVersion` (currently `1`) |

Custom zone: `EASTKeptZone` (`zoneName` on every record above). Container: `iCloud.com.dogukan.dailywisdom`. Database: private only. No field name, required/optional designation, or schema-version number above differs from Section 2 — this table exists only so Phase 4C-1's own Dart and Swift implementations can be checked against one place without cross-referencing every subsection of Section 2 individually.

### 11.3 Dart wire-boundary layer (`lib/sync_platform/`)

Two new thin codec types, deliberately not new business-rule models:

- `CloudKeptWisdomWireEnvelope` (`lib/sync_platform/cloud_kept_wisdom_wire_envelope.dart`): `encode(CloudKeptWisdomProjection) -> Map<Object?, Object?>` / `tryDecode(Map<Object?, Object?>) -> CloudKeptWisdomProjection?`. Rejects, before ever delegating to `CloudKeptWisdomProjection.tryParseRemote`: a `recordType` other than `CKKeptWisdom`; a `zoneName` other than `EASTKeptZone`; any key in `forbiddenDailyAccessKeys`; any non-`String` map key.
- `CloudEastSyncStateWireEnvelope` (`lib/sync_platform/cloud_east_sync_state_wire_envelope.dart`): the same shape for `CKEastSyncState`, additionally rejecting any `recordName` other than the fixed singleton literal `"sync-state"`.

Both types are pure `Map`-shape codecs only — no `MethodChannel` call, no `CKRecord`, no network access. A future phase that actually implements record push/pull would use these to prepare/parse whatever a native bridge method eventually carries.

### 11.4 Native Swift schema and codec (`ios/Runner/`)

Four new, narrowly-scoped files, none of which depends on `CKDatabase`:

- `CloudKitRecordSchema.swift` — record-type, zone-name, and field-name constants for both record types, plus each schema-version literal. This project's one authoritative native-side copy of these values (mirroring `lib/sync/sync_record_identity.dart`).
- `CloudKitRecordIdentity.swift` — deterministic `CKRecord.ID` construction, mirroring `deriveKeptWisdomRecordName` exactly (`east-kept-<revealId>` inside `EASTKeptZone`), plus the fixed `CKEastSyncState` singleton identity and a canonical-revealId check mirroring `lib/utils/canonical_uuid.dart`.
- `CloudKitKeptWisdomCodec.swift` — `encodeActive`/`encodeTombstone` (validated values → `CKRecord`) and `decode` (`CKRecord` → `Result<CloudKitKeptWisdomWireEnvelope, DecodeError>`). Rejects a wrong record type, a wrong (including default) zone, a record-name/`revealId` mismatch, a missing or wrong-typed required field, an unrecognized schema version, a tombstone carrying a forbidden content field, and an internally-inconsistent Reflection field pair — no force cast, no force unwrap, no localized `CKError` description, no logging of content or identity values anywhere in the file.
- `CloudKitSyncStateCodec.swift` — the same shape for `CKEastSyncState`, additionally rejecting any `recordName` other than the fixed singleton literal.

Both codec files are registered in `ios/Runner.xcodeproj/project.pbxproj`'s Runner target only (not `RunnerTests`, which accesses them via `@testable import Runner`).

### 11.5 Explicit non-goals (Phase 4C-1)

No `CKDatabase.save`, no `CKModifyRecordsOperation`, no `CKFetchRecordZoneChangesOperation`, no record query, no subscription, no change-token persistence, no outbox/inbox processing, no background or startup sync, no retry scheduling, no automatic zone configuration, no repository wiring, no Settings or user-visible sync UI, no account-change migration behavior, no change to application startup, and no start of whatever a later Phase 4C-2 (real record push/pull) will be.

## 12. Phase 4C-2 — private record transport foundation (implemented this phase)

**Scope:** the narrow native and Dart transport boundary required to operate on the already-frozen `CKKeptWisdom`/`CKEastSyncState` records (Section 11), using the private database only, custom zone `EASTKeptZone`, container `iCloud.com.dogukan.dailywisdom`. This phase provides explicit record operations but does **not** connect them to the application repository, startup, UI, outbox, automatic sync, migration, or background behavior — every rule in Section 9/10.8/11.5 restricting those things remains in force.

### 12.1 Container construction — explicit identifier is mandatory for the transport

The private record transport (`modifyPrivateRecords`/`fetchPrivateZoneChanges`) **must** construct `CKContainer(identifier: "iCloud.com.dogukan.dailywisdom")` explicitly, via `CloudKitSyncBridgeConstants.containerIdentifier` (`CloudKitSyncBridge.transportContainer`), and hand that container's `privateCloudDatabase` to `CloudKitRecordTransportCoordinator` — never `CKContainer.default()`. This is a hard requirement, not a preference: the transport must never depend on Xcode-managed entitlement resolution to determine which container it reaches.

Phase 4B-1's account-status/zone-configuration bridge (`getAccountSnapshot`, `configurePrivateZone`, via `CloudKitSyncBridge.container`) is unmodified by this correction and continues to resolve `CKContainer.default()` — that pre-existing code was not touched, per the standing rule against modifying pre-Phase-4C-2 account/zone code without necessity. The two container-resolution paths are independent: `container` (Phase 4B-1, `.default()`) and `transportContainer` (Phase 4C-2, explicit identifier) are two separate, separately-resolved properties on `CloudKitSyncBridge`, each used only by its own methods.

### 12.2 Operation set derived from this document, Section 6 and Section 4.2 (no invented operations)

| Capability (from the Phase 4C-2 instruction's own list) | Resolution |
|---|---|
| (1) Atomically save one or more validated records | `CKModifyRecordsOperation`, `recordsToSave` only, `savePolicy = .ifServerRecordUnchanged` (see 12.3). |
| (2) Delete records only through the approved tombstone strategy | Already answered by Section 4.2: "a delete is represented as a tombstone-form update to the same record... not a native CloudKit record deletion." `recordIDsToDelete` is therefore always `nil` on every `CKModifyRecordsOperation` this phase's coordinator builds — never a genuine gap, a restated existing rule. If `CKFetchRecordZoneChangesOperation` ever reports an actual physical-deletion notification anyway (only possible from an out-of-band actor, e.g. a manual CloudKit Dashboard action — never this transport itself), the entire fetch fails closed with the distinct `unexpectedPhysicalDeletion` outcome (12.4) rather than being tolerated or silently noted. |
| (3) Fetch records or zone changes for incremental sync | `CKFetchRecordZoneChangesOperation`, scoped to the one `EASTKeptZone`, `fetchAllChanges = true` (native aggregates every page before this phase's single Dart-facing completion — Section 6 does not assign pagination to Dart). |
| (4) Return a server change token / opaque cursor | `CKServerChangeToken`, securely archived (`NSKeyedArchiver`/`NSKeyedUnarchiver`, `requiresSecureCoding = true`, explicit `allowedClasses`) and transported as an opaque Base64 string, exactly per this document's existing "opaque per-account scope token"-style privacy rule (Section 5) extended to this new opaque value. Never interpreted, compared, or persisted by Dart or by this phase. |
| (5) Detect token expiration and surface a stable normalized result | **Genuine, disclosed gap fill:** this document did not previously define a vocabulary entry for `CKError.Code.changeTokenExpired`. It is added as both a new `CloudKitErrorClassifier.changeTokenExpired` symbolic constant *and* a first-class `CloudKitZoneChangesOutcome.tokenExpired` result variant — not folded into the generic error vocabulary — because its only correct handling (discard the token, resync from `nil`) is categorically different from an ordinary retryable/permanent failure. This phase never mutates or persists a token itself, on expiry or otherwise; a caller who discards a token in response to `tokenExpired` and later needs this zone's data again must issue a fresh **initial** fetch (`previousServerToken: nil`) — there is no other recovery path within this phase, since no orchestration or persistence of tokens exists here at all. |
| (6) Support partial failure without treating successful records as failed | Every requested record's own outcome is collected independently via `CKModifyRecordsOperation.perRecordCompletionBlock` (the legacy per-record completion API, available well before iOS 13 — this app's deployment target, per Section 6 — unlike the `perRecordSaveBlock`/`modifyRecordsResultBlock` pair, which requires iOS 15+). A record CloudKit never got to attempt is never reported as failed; see 12.4. |
| (7) Surface server versions needed for deterministic conflict handling | Each record's post-save "system fields" (identity + change tag, never user field values) are archived the same opaque way as the change token (`CKRecord.encodeSystemFields(with:)` / `CKRecord(coder:)`) and returned as `systemFields` on a successful per-record outcome, for a caller (outside this phase's scope) to present as `previousSystemFields` on that record's next save. |

No operation beyond this table was added. `CKFetchDatabaseChangesOperation` (multi-zone discovery) and zone/database subscriptions remain out of scope, exactly as Section 6 already scoped them ("effectively just `EASTKeptZone`" — a single already-known zone needs no separate discovery step; "not required for this design's foreground-only sync timing").

### 12.3 Save policy: `.ifServerRecordUnchanged`

The architecture did not previously name a save policy explicitly; disclosed here as a derived, necessary decision rather than a silent one. `.ifServerRecordUnchanged` is the only `CKRecordSavePolicy` consistent with "never silently overwrite a server version when conflict detection requires a change tag" and with Section 4.2's explicit reliance on `CKError.serverRecordChanged` as the signal to re-run conflict resolution — `.changedKeys`/`.allKeys` both bypass CloudKit's own change-tag comparison entirely and were rejected for that reason. A record saved for the first time (no `previousSystemFields` supplied) is saved unconditionally, exactly as CloudKit itself treats a `CKRecord` with no known prior server version.

### 12.4 Result shapes (native `CloudKitRecordTransportCoordinator` / Dart `lib/sync_platform/cloud_kit_modify_records_contract.dart` + `cloud_kit_zone_changes_contract.dart`)

- **`modifyPrivateRecords`** result is exactly one of: `allSucceeded` (every requested record — including the empty-request case — succeeded), `partialFailure` (at least one per-record outcome is known and at least one failed; a `serverRecordChanged` conflict is always represented here, as one record's own outcome, never as a distinct top-level state), or `transportFailure` (the operation could not attempt *any* record at all — e.g. no network — carrying a top-level symbolic `errorCode` and no per-record outcomes, since none could honestly be reported).
- **`fetchPrivateZoneChanges`** result is exactly one of: `success` (every page CloudKit reported has been aggregated; carries the changed `CKKeptWisdom`/`CKEastSyncState` records — each independently re-validated through the existing Phase 4C-1 codecs — and the new opaque server token; **carries no deletion-related field of any kind**), `tokenExpired` (Section 12.2 row 5), `unexpectedPhysicalDeletion` (below), or `failure` (a stable symbolic `errorCode`, no partial data ever attached to a non-`success` outcome).
- **Physical deletion is a fail-closed outcome, never a defensive passthrough.** This transport never issues one (12.2 row 2). A successful `fetchPrivateZoneChanges` response contains exactly two things: the changed `CKKeptWisdom`/`CKEastSyncState` records, and an opaque server token — no field of any name that collects or lists a physically-deleted record's identity exists anywhere in the successful-fetch contract, native or Dart; a successful result cannot carry deletion data because none is ever expected to exist. If `CKFetchRecordZoneChangesOperation.recordWithIDWasDeletedBlock` fires anyway (only from an out-of-band actor, e.g. a manual CloudKit Dashboard action), the coordinator does not attempt to report which record was deleted at all: it records only that this occurred (a `Bool`, never a captured record name or `CKRecord.ID`), takes priority over every other outcome that fetch could otherwise report (a concurrent token-expiry or transport error is superseded), and completes with the distinct `unexpectedPhysicalDeletion` outcome — no changed records, no token, and the deleted record's identity never enters the result, an error, a log line, or any `toString` anywhere in this transport. This outcome does not itself apply, persist, or otherwise act on the deletion; it exists solely so this invariant violation is never silently absorbed into an apparently-successful fetch.

### 12.5 MethodChannel bridge extension

Still exactly one channel, `com.dogukan.dailywisdom/cloudkit_sync` (never a second one). Two new methods, `modifyPrivateRecords` and `fetchPrivateZoneChanges`, alongside the three unchanged Phase 4B-1 methods (`getAccountSnapshot`, `configurePrivateZone`, `getBridgeInfo` — same names, same no-argument call shape, same result shape). Both new methods validate their full argument envelope on the native side (`CloudKitSyncBridge.handleModifyPrivateRecords`/`.handleFetchPrivateZoneChanges`): an unrecognized top-level key, a wrong-typed value, or a record envelope that fails the Phase 4C-1 codec's own encode validation (via the new `CloudKitRecordEnvelopeArgumentParser`) rejects the entire call with a stable `invalidArguments`-coded `FlutterError` before any `CKModifyRecordsOperation`/`CKFetchRecordZoneChangesOperation` is ever constructed — never a partial attempt against only the valid entries of a malformed batch.

### 12.6 Native files added

- `CloudKitOpaqueArchive.swift` — the one place this codebase archives/unarchives a `CKServerChangeToken` or a `CKRecord`'s own system fields, always via `NSKeyedArchiver`/`NSKeyedUnarchiver` with `requiresSecureCoding = true` and an explicit `allowedClasses`/decode-type restriction — never the insecure, deprecated unarchiving API, never a custom token/system-fields semantic.
- `CloudKitRecordEnvelopeArgumentParser.swift` — the native-side mirror of the Dart wire envelopes' `encode`, in the opposite direction: turns a raw MethodChannel argument entry back into a validated `CKRecord`, via the existing Phase 4C-1 `CloudKitKeptWisdomCodec`/`CloudKitSyncStateCodec` encode functions only — never a second, competing validation path.
- `CloudKitRecordTransportCoordinator.swift` — the coordinator described throughout this section. Reuses `CloudKitPrivateZoneCoordinator.swift`'s existing `CloudKitZoneOperationDatabase` injectable-database seam rather than inventing a second one.
- `CloudKitErrorClassifier.swift` gained five additional symbolic constants (`permissionFailure`, `zoneNotFound`, `badContainer`, `badDatabase`, `changeTokenExpired`) — none added to `lib/sync/sync_error_classification.dart`'s explicit table, for the same reason `serverRejectedRequest` (Section 10.9) was not: that function's existing default (any unrecognized code → `SyncErrorCategory.permanent`) is already the correct category for all five.
- `CloudKitSyncBridge.swift`/`CloudKitSyncBridgeConstants.swift` gained the two new method names/handlers/payload builders described in 12.5, with the three existing methods' handlers and result shapes untouched.

### 12.7 Dart files added

- `lib/sync_platform/cloud_kit_modify_records_contract.dart` — `CloudKitRecordChangeInput` (buildable only from an already-validated projection via `.keptWisdom`/`.syncState`, never from a raw map), `CloudKitModifyRecordsRequest`, `CloudKitRecordModifyOutcome`, `CloudKitModifyRecordsOverallStatus`, `CloudKitModifyRecordsResult`.
- `lib/sync_platform/cloud_kit_zone_changes_contract.dart` — `CloudKitZoneChangesRequest`, `CloudKitZoneChangesOutcome`, `CloudKitZoneChangesResult` (decodes every changed record through the existing Phase 4C-1 wire envelopes, never a second parser).
- `lib/sync_platform/cloud_kit_platform_bridge.dart`/`method_channel_cloud_kit_platform_bridge.dart` gained `modifyPrivateRecords`/`fetchPrivateZoneChanges`, narrowly, alongside the three unchanged existing members.

### 12.8 Explicit non-goals (Phase 4C-2)

No repository, startup, UI, outbox, retry-scheduling, background-task, subscription, push-handling, Settings/sync-status UI, or account-change wiring of any kind calls either new method. No change-token or system-fields value is persisted anywhere in this phase — a caller outside this phase's scope is responsible for that. No application-level conflict resolution is implemented here (`serverRecordChanged` is surfaced, never resolved, by this phase). No change to `lib/main.dart`, daily-access behavior, Keeper/purchase logic, notifications, protected Kept/Reflection storage, entitlements, capability settings, bundle/container identifier, deployment target, build number, or package dependencies. No automated test in this phase contacts real CloudKit.

## 13. Phase 4D-1 — durable local sync-state and outbox persistence foundation (implemented this phase)

**Scope:** the durable local persistence foundation a future sync orchestrator will need: an account-scoped opaque server change token, a durable pending-outbound-mutation outbox, opaque per-record CloudKit system fields, all inside one versioned, protected, atomically-replaced local envelope. **This phase contacts CloudKit for nothing.** No method added by this phase calls `modifyPrivateRecords` or `fetchPrivateZoneChanges` (Section 12), inspects or modifies the live Kept repository, triggers on a Keep/Reflection/reveal event, runs at startup, applies an incoming record, resolves a conflict, schedules a retry, or listens for an account-change event. Every rule in Sections 9/10.8/11.5/12.8 restricting those things remains in force.

### 13.1 Deliberate, disclosed refinement of ADR-007's single-envelope sketch

ADR-007's Local state envelope section describes `outbox` and `syncMetadata` (server change token, per-record pending-operation state) as additive top-level fields of the *same* `east_kept_state_v3.json` file `KeptStateEnvelope` (Phase 3B) already owns — and, as of this phase, `KeptStateEnvelope` still serializes only `activeRecords`; none of `dataEpoch`, `pendingUndoDeletions`, `tombstones`, `outbox`, `syncMetadata`, or `pendingEpochCleanup` has been added to it by any phase to date.

This phase's own instruction is explicit and newer, in the same manner Section 0 above already documents one supersession of ADR-007's original record model: keep this durable sync state in a **separate** protected store, never inside the existing authoritative Kept envelope, and never alter `KeptStateEnvelope`'s own format. That instruction is followed here, not silently reconciled with ADR-007's original sketch. Concretely: a new file, `east_sync_state_v1.json`, in its own `east_sync_state` directory, distinct from `east_kept_state`'s directory and file, is introduced. `KeptStateEnvelope` and `ProtectedFileKeptStateStore` are untouched by this phase.

### 13.2 Persisted concepts, derived from the architecture

| ADR-007 / design-doc concept | This phase's persisted representation |
|---|---|
| "the zone's server change token" (ADR-007 Local state envelope; design doc §6, §12.2 row 4) | `AccountSyncState.serverChangeToken` — the exact opaque Base64 string Phase 4C-2's `fetchPrivateZoneChanges` already returns. Never decoded, interpreted, or re-encoded. |
| "durable, not-yet-synced local mutations" / "a pending-operation type per record (create/update/delete)" (ADR-007 Local state envelope, Deletion/outbox strategy) | `AccountSyncState.outbox` — a list of `PersistedOutboxMutation`, each wrapping an already-validated Phase 4A `SyncChange` (kind + `CloudKeptWisdomProjection` + enqueued-at timestamp) plus a persistence-only outcome `status` (`pending`/`failed`/`conflicted`). No new mutation-shape model was introduced — `SyncChange` already is ADR-007's pending-outbox-mutation shape (design doc §8 item 5), and reusing it directly means kind/tombstone-form consistency is enforced exactly once, by `SyncChange`'s own constructor. |
| "archived `CKRecord` system fields or equivalent server change-tag state per record" (ADR-007 Local state envelope) | `AccountSyncState.recordSystemFields` — a `Map<recordName, opaque Base64 systemFields>`, populated only from a caller-confirmed `CloudKitRecordModifyOutcome.systemFields` (Section 12.4). Never decoded, never associated by wisdom text. |
| Account-scoping / iCloud account change boundary (ADR-007; design doc §5) | The whole envelope is keyed by the opaque CloudKit account fingerprint (`CloudKitAccountSnapshot.accountFingerprint`, Section 10.3) — see §13.3. |
| `dataEpoch` (ADR-007's Data epoch and Delete All reset safety; design doc §4.1) | **Correction, now authoritative:** every `AccountSyncState` account bucket carries a mandatory `dataEpoch` (reusing exactly the `DataEpoch` type Section 8 item 2 and the Phase 4A sync projections already established — never a new epoch type, never a normalization rule of this phase's own invention). There is no default: a bucket cannot be constructed or decoded without one (§13.6). |
| Schema version | `SyncPersistenceEnvelope.currentSchemaVersion = 1`, checked exactly like `KeptStateEnvelope.currentSchemaVersion`; an unrecognized version fails the whole load closed. |

**Genuine, disclosed gaps this phase still does not fill:** ADR-007's `pendingUndoDeletions`, `tombstones` (as a *live* Kept-domain collection), and `pendingEpochCleanup` remain envelope-level concepts belonging to the live Kept/Reflection repository and the Delete-All-Synced-Data reset flow — neither exists yet in code this phase touches, and this phase does not read or write the live Kept repository at all (an explicit boundary above). **This phase performs no automatic epoch reset and no reset orchestration of any kind** — `dataEpoch` is persisted and enforced (§13.6), never generated, rotated, or reconciled by this phase; a genuine epoch reset (Delete All Synced Data) remains entirely a future orchestrator's responsibility. Similarly, ADR-007's "retry metadata" is not added beyond the single `pending`/`failed`/`conflicted` status already described above — no attempt counter, no last-error code, no backoff timestamp — since no phase to date has approved a richer retry-metadata shape.

### 13.3 Account scoping

Every persisted value lives under `SyncPersistenceEnvelope.accounts[accountFingerprint]` (an `AccountSyncState`), where `accountFingerprint` is the exact opaque, namespaced SHA-256 hash Section 10.3 already defines — never a raw CloudKit user/record identifier, never derived from email, Apple ID, or device name. Two fingerprints' state can never mix: each is a distinct map entry, validated on decode to look like the native fingerprint's shape (64 lowercase hex characters) and rejected (fail-closed) otherwise. An unresolved or unknown fingerprint reading through `loadAccountState` receives `null`, never another fingerprint's state.

**The account fingerprint is never written into a file path, and never logged.** Unlike `ProtectedFileKeptStateStore` (whose directory path carries no per-account component and is therefore safe to log), this phase's fingerprint-scoping happens entirely inside the JSON *content* of one fingerprint-independent file (`east_sync_state_v1.json`) — the file path this store reads and writes is always exactly the same string regardless of which fingerprint an operation targets. This was a deliberate design choice specifically so a fingerprint could never leak through this store's own diagnostic path logging.

`SyncPersistenceEnvelope` additionally distinguishes an *active* account (`accounts`) from a *quarantined* one (`quarantinedAccounts`) — see §13.9's `quarantineAccountState`/`clearAccountState` — so a future account-change-boundary layer (design doc §5) has an explicit, safe way to set a previous account's state aside without destroying it, without this phase itself implementing any account-change orchestration.

### 13.4 Storage location and atomic-write guarantees

A new directory, `east_sync_state`, and a new file, `east_sync_state_v1.json`, both beneath the platform's Application Support directory, entirely separate from `east_kept_state`'s directory/file. iOS file protection (`NSFileProtectionComplete`, via the existing, unmodified `FileProtectionBridge`/`MethodChannelFileProtectionBridge`) is applied to the directory, every temporary file, every backup file, and the final file — exactly the same protection this codebase already requires for `east_kept_state`.

The atomic-write algorithm (`ProtectedSyncPersistenceStore`) mirrors `ProtectedFileKeptStateStore`'s already-reviewed algorithm step for step: write a temporary file, protect and read back the temporary file to verify it byte-for-byte, back up and verify any existing final file, atomically rename the temporary file into place, protect and read back the final file to verify it, and — on any failure after the rename — restore the backed-up prior final file and re-verify it before surfacing the original failure. A first-ever write that fails before its rename step leaves no final file behind at all. Every operation for this store's one resource key is serialized through the same, unmodified `PersistenceOperationCoordinator` primitive `ProtectedFileKeptStateStore` already uses, under its own distinct resource key (`protected_sync_state_file`) — a load can never observe a half-completed replace, and two mutations against this envelope, for any fingerprint, can never interleave.

The tested primitives (`FileProtectionBridge`, `PersistenceOperationCoordinator`) are reused unmodified; the atomic-write *control flow* is necessarily re-implemented for the new envelope type rather than factored into a shared generic base class, since doing so would require modifying the already-reviewed `ProtectedFileKeptStateStore` — out of scope for this phase, and against the standing instruction not to refactor unrelated Kept-storage code broadly. This is a disclosed trade-off.

Malformed authoritative data — an unrecognized top-level or nested key, a wrong type, an unsupported schema version, a token or system-fields value that does not look like opaque Base64, a record name that does not look like a real `CKKeptWisdom` record name, a duplicate outbox `mutationId`, or two outbox entries for the same record name — fails the **entire load** closed (the raw bytes are preserved to a separate `.corrupt-` file for later inspection, mirroring `ProtectedFileKeptStateStore`'s own corruption handling) rather than silently discarding just the malformed piece. Nothing is ever silently reset to empty because of corruption.

### 13.5 Opaque server change token

Persisted exactly as Phase 4C-2's `fetchPrivateZoneChanges` returns it — an opaque Base64 string, validated only for outer shape (Base64 charset) on load, never decoded or interpreted. A `null` token means "no successful fetch has completed yet for this account" — the next fetch must be an initial one (`previousServerToken: null`). A corrupt persisted token fails the whole account-state load closed (§13.4), never silently treated as absent and never auto-cleared. `clearServerChangeToken` is the one explicit, atomic API a future orchestrator uses after observing `CloudKitZoneChangesOutcome.tokenExpired` (Section 12.2 row 5) — it clears only the token, leaving the outbox and every stored system-fields value completely untouched in the same atomic write.

### 13.6 Outbox model

Mutation identity is the enqueued `SyncChange.projection.mutationId` — a stable UUID for the lifetime of that specific queued entry, even though a later, different local edit to the same occurrence would carry a different `mutationId` of its own (design doc §2.3). Record identity is `SyncChange.projection.recordName`, the same deterministic `east-kept-<revealId>` derivation used everywhere else in this design — never wisdom text, never a display date. Two outbox entries for two different `revealId` values with byte-identical `wisdomText` are and remain two fully independent entries; wisdom text and display dates are never inputs to outbox identity or deduplication.

**dataEpoch enforcement, frozen this round:** every queued mutation's own `projection.dataEpoch` must equal its account bucket's `dataEpoch`. Enqueueing against an existing bucket with a mismatched epoch fails closed as `MutationEpochMismatchException` before anything is written; a bucket freshly created by the first enqueue for a fingerprint simply adopts that first mutation's `dataEpoch` as its own. Loading a persisted account whose stored mutation epoch differs from its own stored bucket epoch fails the whole account-state load closed (§13.4), exactly like any other malformed-data case — never silently repaired or defaulted. `clearServerChangeToken`, `applyMutationOutcomes`, and `replaceRecordSystemFields` all preserve `dataEpoch` structurally: `AccountSyncState.copyWith` has no `dataEpoch` parameter at all, so no call path through this store can change an account's epoch. No automatic epoch reset or reconciliation is implemented by this phase (§13.2).

Enqueue rules, now the frozen, authoritative policy for this phase (superseding the original draft's stricter "second pending mutation for the same record throws" behavior):

1. An exact repeat of an already-queued mutation (identical `mutationId` and byte/value-equivalent projection content) is **idempotent** — a no-op, not an error.
2. A different mutation sharing an already-queued `mutationId` (a value collision with different content) is rejected as `ConflictingMutationIdentityException` — an impossible state this store refuses to silently resolve either way.
3. A mutation with a new `mutationId` for a record name with no existing pending entry is appended as a new outbox entry, in deterministic order (see below).
4. A mutation with a new `mutationId` for a record name that already has a distinct pending entry queued **atomically supersedes** that existing entry in place: the newer local enqueue call's projection becomes the record's sole desired outbound state, stored under the new `mutationId`, overwriting the old entry at its **existing list index** rather than being removed and re-appended. Active may supersede active, a tombstone may supersede a pending active entry, and an active entry may supersede a pending tombstone — `revealId`/`recordName` identity is what is compared, never wisdom text or a display date. No CloudKit call occurs during a supersession, no mutation is marked successful, and any system fields already stored for that record name in `recordSystemFields` are left completely untouched (they are associated by record name, independent of the outbox).

Outbox order is the **stored list order**: an entry occupies the position it was first inserted at, and a supersession (rule 4) overwrites that same position rather than moving it to the end — so a record that is repeatedly edited before it syncs can never starve other queued records of their turn. `readPendingMutations` returns entries in exactly this stored order, regardless of status; it never re-sorts by timestamp or `mutationId`.

Outcomes are applied atomically and only on explicit confirmed input (`applyMutationOutcomes`), and acknowledgment is strictly **mutationId-specific**: only the exact `mutationId` currently occupying an outbox slot may be acknowledged and removed. Acknowledging an older `mutationId` that a supersession (rule 4) has since replaced is a no-op — it does not remove the newer, currently-queued mutation, since that would silently drop a local edit the caller never confirmed as synced. Every other named mutation id has its status updated to `failed` or `conflicted` and remains queued; any mutation id named in neither collection — the representation of a retryable transport failure — is left completely unchanged. Tombstones are ordinary outbox entries like any other (`SyncChangeKind.delete`, tombstone-form projection); active and tombstone-form entries can never be confused, since `SyncChange`'s own constructor rejects any mismatch between `kind` and `projection.isTombstone`.

### 13.7 Record system fields

Stored as `AccountSyncState.recordSystemFields`, a `Map<recordName, opaque Base64 systemFields>`. Associated only with the exact deterministic record name a caller supplies after confirming that record's own save succeeded — never by wisdom text, never inferred. A corrupt stored value (present but not shaped like opaque Base64) fails the whole account-state load closed, exactly like a corrupt token. No native decoding of a system-fields value occurs anywhere in this phase.

### 13.8 Storage envelope schema

```
east_sync_state_v1.json
{
  "schemaVersion": 1,
  "accounts": {
    "<64-hex-char opaque account fingerprint>": {
      "dataEpoch": "<canonical UUID v4, mandatory -- no default, never absent>",
      "serverChangeToken": "<opaque Base64>",           // omitted, never null-valued, when absent
      "recordSystemFields": { "<recordName>": "<opaque Base64>" },
      "outbox": [
        {
          "kind": "create" | "update" | "delete",
          "status": "pending" | "failed" | "conflicted",
          "enqueuedAtMs": <Int64, UTC, non-negative>,
          "record": { /* Phase 4D-1's own local domain-projection encode shape (recordName, isTombstone, revealId/wisdomText/timestamps or deletedAtMs, reflection fields when present, mutationId, dataEpoch, schemaVersion) -- CloudKeptWisdomProjection's own fields only, never the platform-bridge wire envelope's recordType/zoneName tags; carries its own dataEpoch, which must equal the account bucket's dataEpoch */ }
        }
      ]
    }
  },
  "quarantinedAccounts": { /* same per-account shape, set aside rather than destroyed */ }
}
```

Parsing is a strict allowlist at every level (top-level keys; per-account keys; per-outbox-entry keys); an unrecognized key, a wrong type, a missing or malformed `dataEpoch`, a mutation `dataEpoch` that does not match its account bucket's `dataEpoch`, an unrecognized `kind`/`status` value, a negative `enqueuedAtMs`, a malformed record name, a malformed fingerprint, an unsupported `schemaVersion`, a duplicate outbox `mutationId`, a duplicate outbox `recordName`, or an impossible active/tombstone combination all fail the parse closed. A fingerprint can never appear in both `accounts` and `quarantinedAccounts` at once. Malformed persisted state is never silently repaired.

### 13.9 Public Dart interfaces (`lib/sync_persistence/`)

`SyncPersistenceStore` (interface) / `ProtectedSyncPersistenceStore` (implementation): `loadAccountState`, `replaceAccountState`, `enqueueMutation`, `applyMutationOutcomes`, `readPendingMutations`, `replaceRecordSystemFields`, `storeServerChangeToken`, `clearServerChangeToken`, `clearAccountState` (permanent, no recovery), `quarantineAccountState` (reversible set-aside, not yet paired with a restore API — a future phase's explicit responsibility). No method exposes a mutable collection; no method calls a `MethodChannel` or CloudKit method of any kind.

### 13.10 Privacy rules, structurally enforced

None of the following is ever written into a log line, an exception message/`toString`, or diagnostic output produced by this phase's own code: wisdom text, reflection text, a record name, a `revealId`, a `mutationId`, the account fingerprint, the server token, a record's system fields, or raw persisted JSON. Every exception type this phase adds (`SyncPersistenceStoreException`, `ConflictingMutationIdentityException`, `MutationEpochMismatchException`, `AccountSyncStateFormatException`) carries only a stage name and/or a stable, content-free description. No new `print`/`debugPrint`/`NSLog` call was added beyond reusing the existing, `kDebugMode`-gated `keptDiagnostic` helper with stage-name-and-count-only messages, exactly as `ProtectedFileKeptStateStore` already does.

### 13.11 Explicit non-goals (Phase 4D-1)

No CloudKit call of any kind (`modifyPrivateRecords`, `fetchPrivateZoneChanges`, or any native method). No live Kept/Reflection repository read or write. No trigger on Keep/Reflection/reveal. No startup wiring. No conflict resolution, no incoming-record application, no retry scheduling, no account-change listener, no background execution, no subscription/push handling, no sync-status UI, no Settings toggle. No change to `lib/main.dart`, daily-access behavior, Keeper/purchase logic, notifications, analytics, the existing protected Kept/Reflection envelope or its migration semantics, native CloudKit transport, entitlements, capability settings, bundle/container identifier, deployment target, build number, or package dependencies. No automated test in this phase contacts real CloudKit or a real native file-protection channel.

## 14. Phase 4D-2 — isolated CloudKit sync orchestrator (implemented this phase)

**Scope:** `lib/sync_orchestration/` (`SyncOrchestrator`, `SyncPassResult`/`SyncPassStatus`) connects three already-implemented, independently-tested layers — the Phase 4A sync-domain contracts (`lib/sync/`), the Phase 4C CloudKit transport (`lib/sync_platform/`), and the Phase 4D-1 durable local sync persistence (`lib/sync_persistence/`) — through injected abstractions only. It introduces no new record shape, codec, or conflict/classification rule of its own. **This phase remains entirely unwired to the application:** no `KeptRepository`, `SavedReflectionsService`, home screen, `lib/main.dart`, lifecycle observer, account-change listener, or network observer imports or calls `SyncOrchestrator` — that integration is explicitly Phase 4E's responsibility, not this phase's (enforced by `test/sync_orchestration/sync_orchestration_layering_test.dart`).

### 14.1 One explicit sync pass

`SyncOrchestrator.runSyncPass()` coordinates exactly one sync pass and never starts automatically, never schedules itself, and never subscribes to `CloudKitPlatformBridge.accountChangeEvents` — a caller decides if/when/how often to invoke it. Concurrent calls while a pass is already running share that exact in-flight `Future` rather than starting a second, concurrent upload/fetch sequence against the same persistence state (this codebase's existing single-resource-key serialization precedent, `PersistenceOperationCoordinator`, applied here at the orchestrator level instead of the file level).

One pass proceeds, in order: (1) resolve the account snapshot and gate on availability/fingerprint; (2) configure the private zone through the existing platform abstraction only (never a re-implemented fetch-first/create-fallback algorithm in Dart); (3) load the account-scoped Phase 4D-1 bucket by the opaque fingerprint (never fabricating one if absent); (3.5) re-verify the account snapshot has not drifted since step 1 before any persistence mutation, failing closed on any inconsistency; (4) upload the pending outbox (§14.2); (5) durably apply upload outcomes (§14.3) *before* any fetch is attempted; (6) fetch private-zone changes using the persisted opaque server token (§14.4); (7) handle `tokenExpired` distinctly (§14.5). See §14.7 for the exact points at which account consistency is re-checked.

### 14.2 Upload-before-fetch ordering and translation

The pass never fetches before every currently-pending outbox mutation has had its upload outcome durably applied (or the pass has already stopped with a non-`completed` status). Each persisted `SyncChange` is translated into a `CloudKitRecordChangeInput.keptWisdom(projection, previousSystemFields: ...)` only at this orchestration boundary — never a parallel DTO — preserving deterministic queue order, `mutationId`, record identity, `revealId`, active/tombstone state, and the latest Reflection projection exactly as persisted; `previousSystemFields` is attached only from the exact matching record identity already stored in `AccountSyncState.recordSystemFields`. No batch-size limit is documented anywhere in the Phase 4C-2 transport contract, so this phase uses one single, deterministically-ordered batch per pass rather than inventing an undocumented limit.

### 14.3 Durable application of upload outcomes before fetch

Every attempted mutation's outcome is classified and applied through the existing, unmodified Phase 4D-1 API, in two ordered steps — never one combined step — so a durable local effect is never assumed to exist before it actually landed:

1. **System fields first.** For every outcome that succeeded, its returned `systemFields` is durably persisted (`replaceRecordSystemFields`) under the exact matching record identity, one record at a time, before anything is acknowledged. If persisting any one of these fails, the pass stops immediately with `persistenceFailure` — no mutationId has been acknowledged or marked yet, so every mutation this pass touched simply remains queued exactly as it was (any system-fields values that did land are still valid for a future conflict-safe retry). The fetch step is never reached.
2. **Acknowledgment/marking second, only after every system-fields write above succeeded.** A single `applyMutationOutcomes` call acknowledges only the exact `mutationId`s that succeeded, marks a `serverRecordChanged` outcome's exact mutation `conflicted`, and marks any other classified-permanent outcome's exact mutation `failed`; a classified-retryable per-record outcome, or a transport-wide failure, leaves the entire outbox completely unchanged. If this call itself fails, the pass stops immediately with `persistenceFailure` — the affected mutations remain queued, already carrying whatever system fields step 1 durably stored, so a future upload retry for them remains conflict-safe and idempotent. The fetch step is never reached.

Because acknowledgment inside `applyMutationOutcomes` is already strictly `mutationId`-specific and already a documented no-op for a since-superseded `mutationId` (§13.6), a stale response naming an old, already-superseded mutation can never remove the newer, currently-queued replacement — this phase relies on that existing, already-tested guarantee rather than re-implementing it.

### 14.4 Fetch behavior and the crash-consistency correction: a successful fetch never commits its token

`fetchPrivateZoneChanges` is called with the account bucket's exact persisted `serverChangeToken` (or `null` for an initial fetch). This call already aggregates every page CloudKit reports internally before returning once (its own existing doc comment) — there is no `moreComing`/pagination field anywhere in the Phase 4C-2 contract for this orchestrator to loop over, so one call fully represents one pass's fetch step; this is a disclosed, existing-contract fact, not a limitation this phase introduces.

**Corrected rule, superseding this section's original text:** on a `success` outcome, this phase does **not** call `storeServerChangeToken` and does **not** otherwise mutate the persisted account bucket. Phase 4D-2 does not durably apply incoming Kept/Reflection changes to any repository (§14.6) — advancing the persisted checkpoint immediately on a successful fetch would create a crash window in which the local checkpoint had moved past an incoming batch that was never actually saved locally, so that batch could never be fetched again after an app termination before Phase 4E's application step ran. Instead, the new server change token is returned only as `PendingIncomingSyncBatch.pendingServerChangeToken` (§14.6), inside `SyncPassResult.pendingIncomingBatch` — a *proposed*, not-yet-committed checkpoint, opaque and nullable exactly like the underlying transport contract's own token, never named "persisted" or "committed." This holds whether or not an account bucket currently exists: a no-bucket account may fetch from a `null` token for remote bootstrap, and this phase never fabricates a bucket merely to hold a checkpoint. Repeating the same pass before a future Phase 4E commit simply refetches the same, still-uncommitted range from the account's last *actually committed* token — redundant, but always safe and never lossy, since nothing this phase does depends on that repeated fetch being the only one that ever happens.

The fetched, already-validated `CloudKeptWisdomProjection`/`CloudEastSyncStateProjection` values, together with the account fingerprint, the bucket's `dataEpoch` at fetch time, and the exact previous token the fetch was performed against, are returned as one typed `PendingIncomingSyncBatch` (§14.6) — never as loose, individually-scoped result fields. An `unexpectedPhysicalDeletion` or unrecognized (`unknown`) outcome is treated as a permanent failure and returns no pending batch; an ordinary `failure` is classified via the existing `classifySyncErrorCode`, returns no pending batch, and never changes the persisted token either; `tokenExpired` (§14.5) likewise returns no pending batch.

### 14.5 Token-expired behavior

On `CloudKitZoneChangesOutcome.tokenExpired`, only the account bucket's server change token is cleared (`clearServerChangeToken`) — `dataEpoch`, the outbox, and every stored record-system-fields value are left completely untouched, exactly as that existing Phase 4D-1 API already guarantees. This is unaffected by §14.4's correction: an *expired* token is already known-obsolete, so clearing it immediately (rather than deferring to a future commit) discards nothing a future Phase 4E could still use. The pass returns `SyncPassStatus.tokenExpiredNeedsRefetch` and does not loop to retry within the same pass; a future pass beginning with a `null` token performs the required full-zone refetch.

### 14.6 The pending incoming batch: durable scope binding and Phase 4E ownership

**Incoming-batch scope-binding correction.** A successful fetch's incoming projections and proposed checkpoint are not returned as loose `SyncPassResult` fields — they are wrapped in one typed `PendingIncomingSyncBatch` (`lib/sync_orchestration/pending_incoming_sync_batch.dart`), returned as `SyncPassResult.pendingIncomingBatch`. This exists to close a remaining integration-boundary gap: without durable scope metadata, a future Phase 4E could not reliably reject a batch fetched for one account after the device switched to another, a batch built from a stale `dataEpoch`, a batch built from an older server-token baseline, or two repeated pre-commit fetch results being committed out of order. `PendingIncomingSyncBatch` carries, internally:

- `accountFingerprint` — the opaque fingerprint resolved at the start of the pass that produced this batch (never a raw CloudKit user identifier);
- `baseDataEpoch` — the account bucket's exact `dataEpoch` at fetch time, or `null` when no bucket existed (never a fabricated/default epoch);
- `previousServerChangeToken` — the exact opaque token this batch's fetch was performed against (the same value passed as `CloudKitZoneChangesRequest.previousServerToken`), or `null` for an initial/bootstrap fetch;
- `pendingServerChangeToken` — the proposed, not-yet-committed next checkpoint (§14.4);
- `incomingKeptWisdomProjections`/`incomingSyncStateProjections` — every changed record this pass's fetch validated and decoded, active and tombstone forms alike.

**This phase never applies an incoming record to the live Kept/Reflection repository, never resolves a conflict, never writes local Kept/Reflection storage, never commits the pending checkpoint, and performs no persistence mutation merely by constructing or returning this batch** — `lib/sync_orchestration/` has no import of, and no call path to, `KeptRepository` or `SavedReflectionsService` (enforced structurally), and the batch is a pure in-memory value.

**Phase 4E's validation/commit contract.** Before applying a `PendingIncomingSyncBatch` or committing its token, Phase 4E must validate, in order: (1) the current opaque account fingerprint equals `batch.accountFingerprint`; (2) the current bucket's `dataEpoch` equals `batch.baseDataEpoch` — or, when `baseDataEpoch` is `null`, the no-bucket bootstrap rules explicitly permit establishing one from an incoming sync-state record; (3) the currently persisted server change token equals `batch.previousServerChangeToken`; (4) the incoming records pass account/dataEpoch/domain validation; (5) the records are durably and idempotently applied; (6) only then may `batch.pendingServerChangeToken` be committed via `storeServerChangeToken`. A stale or account-mismatched batch must fail closed — Phase 4E must never apply it and must never advance the token from it. Deciding when/how often to call `runSyncPass` from real application code is also explicitly **Phase 4E's** responsibility, not this phase's.

**Rendering and privacy.** `PendingIncomingSyncBatch`'s account fingerprint, `dataEpoch`, and both token values are never rendered by its own `toString()`/`toLogSafeSummary()`, and never by `SyncPassResult`'s — only safe booleans/counts are ever surfaced: `hasPendingBatch`, `incomingKeptCount`, `incomingSyncStateCount`, `hasBaseDataEpoch`, `hasPreviousCheckpoint`, `hasPendingCheckpoint`, mirroring every other opaque value this design already refuses to log (§13.10).

### 14.7 Account isolation

Every persistence mutation in a pass uses only the fingerprint resolved at the start of that pass. The account snapshot is re-resolved and checked against that fingerprint at three points, each immediately before a group of persistence mutations that point guards:

1. **After zone configuration and before upload** — checked once the account-scoped bucket has been loaded, before any outbox translation or upload begins.
2. **After `modifyPrivateRecords` returns and before any upload-result persistence** — checked once the transport call has actually completed, before the system-fields-then-acknowledgment sequence (§14.3) ever writes this fingerprint's outcome into its bucket.
3. **After `fetchPrivateZoneChanges` returns `tokenExpired` and before the one remaining token-expired persistence mutation** — checked immediately before `clearServerChangeToken`. (A `success` outcome needs no such checkpoint, since §14.4's correction means it performs no persistence mutation at all.)

At every one of these points, a mismatch fails the pass closed (`permanentFailure`) without performing the mutation that checkpoint was guarding — never writing into, merging, or exposing another account's bucket. This phase adds no account-change **event subscription** of any kind; every checkpoint above is a same-pass consistency re-verification, not a listener. The fingerprint itself is never exposed by any checkpoint's result — only a pass/fail boolean gates the call site.

### 14.8 Explicit non-goals (Phase 4D-2)

No wiring to `KeptRepository`, `SavedReflectionsService`, the home screen, `lib/main.dart`, app startup, a lifecycle observer, an account-change-event listener, or a network observer. No application of an incoming record to live storage, no conflict resolution performed against live data, no retry scheduling or background execution, no Settings/sync-status UI. No new record shape, wire codec, or conflict/classification rule — every translation reuses the existing Phase 4A/4C/4D-1 types exactly. No orchestrator-level pagination loop (§14.4 explains why none exists). No change to `lib/main.dart`, iOS files, entitlements, the Xcode project, native CloudKit transport, `KeptRepository`, `SavedReflectionsService`, existing Kept/Reflection persistence, daily-access behavior, migrations, package dependencies, or build number 25. No automated test in this phase contacts real CloudKit or a real `MethodChannel`.

## 15. Phase 4E-1 — integration contracts, durable recovery state, account-scoped bootstrap state, and atomic incoming checkpoint persistence (implemented this phase)

**Scope:** the foundations a future Phase 4E-2/4E-3/4E-4 needs to connect real Kept/Reflection mutations to the sync layers already built (Sections 8-14), without yet performing that connection. This phase adds: a new `lib/sync_integration/` layer (a durable, account-free local sync-intent model and protected store, plus a documented but unimplemented future coordinator boundary); an account-scoped bootstrap/association state added, backward-compatibly, to `AccountSyncState` (§13); and one new atomic incoming-checkpoint operation on `SyncPersistenceStore`. **This phase wires nothing to production.** `KeptRepository`/`SavedReflectionsService` are unmodified; no screen, service, startup path, or lifecycle observer imports or calls anything under `lib/sync_integration/`; no incoming CloudKit record is ever applied to Kept/Reflection storage by this phase; and no existing-user bootstrap process actually runs (that is Phase 4E-4's responsibility — this phase only adds the durable state such a process will need).

### 15.1 The new `lib/sync_integration/` layer

Four new files:

- `local_sync_intent.dart` — `LocalSyncIntentKind` (`create`/`update`/`delete`, a deliberately parallel, not-yet-account-bound precursor to `SyncChangeKind`), `LocalSyncIntentStage` (`pendingLocalApplication`/`localCommittedOutboxPending` — exactly the two stages needed, see §15.2), `LocalSyncIntentPayload` (a complete, self-sufficient content snapshot mirroring `CloudKeptWisdomProjection`'s own active/tombstone field split, built via `.active(...)`/`.tombstone(...)` factories), and `LocalSyncIntent` (an `intentId` + `kind` + `payload` + `stage` + `enqueuedAt`).
- `local_sync_intent_envelope.dart` — the versioned envelope one `LocalSyncIntent` list is persisted as, structurally enforcing at most one pending intent per deterministic record name.
- `local_sync_intent_store.dart` / `protected_local_sync_intent_store.dart` — the `LocalSyncIntentStore` interface and its protected, atomic, file-backed implementation (§15.3).
- `kept_sync_integration_coordinator.dart` — a documentation-only contract placeholder (`KeptSyncIntegrationCoordinatorBoundary`), reserving the name and recording the intended future shape (§15.7) without declaring or implementing any member yet — deliberately, per this codebase's standing discipline against introducing abstractions ahead of an actual caller.

**Why a local sync intent is not simply a `SyncChange`:** a `SyncChange`/`CloudKeptWisdomProjection` requires an already-known `DataEpoch` (§4.1) — but a purely local Keep/Reflection/removal action can happen before any account association has ever occurred, or while iCloud is unavailable entirely, and per the design's own account-boundary rules (§5) that must never block or degrade the local action. A `LocalSyncIntent` therefore carries no account fingerprint and no `dataEpoch` at all; a future Phase 4E-2 conversion step is what binds a resolved `LocalSyncIntentPayload` to the account's current `DataEpoch`, at the moment it is actually durably enqueued via `SyncPersistenceStore.enqueueMutation` — never earlier.

**Why a tombstone intent carries a full payload, not a reference:** `LocalSyncIntentPayload.tombstone(...)` carries `revealId`, `deletedAtMs`, `updatedAtMs`, and `mutationId` directly — never a pointer back to the `KeptRecord` it originated from — specifically so it remains fully recoverable after a crash even when that `KeptRecord` has already been removed from `KeptStateEnvelope` by the very same local action this intent represents.

### 15.2 Intent stages and supersession

Exactly two stages exist, matching the two crash windows a durable intent needs to close: [`pendingLocalApplication`] records that a local write is *about to* happen (written before it, so a crash between this write and the local write leaves a durable trace of the intended action); [`localCommittedOutboxPending`] records that the local write is confirmed durable but the corresponding outbox enqueue is not yet confirmed. There is no third "complete" stage — once the outbox enqueue is confirmed, `LocalSyncIntentStore.removeIntent` removes the intent entirely, since retaining it further would serve no purpose.

Supersession/idempotency policy (`LocalSyncIntentStore.enqueueIntent`) exactly mirrors `SyncPersistenceStore.enqueueMutation`'s already-frozen, already-tested policy (§13.6), keyed by (`intentId`, deterministic record name) instead of (`mutationId`, record name): an exact repeat (same `intentId`, same `kind`/`payload`) is an idempotent no-op; a value collision (same `intentId`, different content) is rejected (`ConflictingLocalSyncIntentIdentityException`); a genuinely new intent for a record with no existing pending intent is appended; a genuinely new intent for a record that already has one supersedes it in place, at its existing position, never moving to the end. **`intentId` is deliberately distinct from both `revealId` and `mutationId`:** a superseding intent always mints a *new* `intentId`, never reusing the superseded one, which is exactly what makes `removeIntent`'s exact-`intentId`-specific removal structurally safe — an acknowledgment/removal call naming an old, already-superseded `intentId` can never remove the newer, currently-queued replacement, since that old id simply no longer names any stored entry.

### 15.3 Protected local sync-intent storage

`ProtectedLocalSyncIntentStore` persists the intent envelope as one file, `east_sync_intents_v1.json`, inside its own `east_sync_integration_state` directory beneath the platform's Application Support directory — a third, fully independent protected file, distinct from both `east_kept_state` (Phase 3B) and `east_sync_state` (Phase 4D-1). It reuses the same tested primitives every other protected store in this codebase already uses (`FileProtectionBridge`, `PersistenceOperationCoordinator`, under its own dedicated resource key `protected_sync_integration_state_file`) and the identical atomic-write algorithm (temp write → protect+verify temp → back up and verify any existing final → atomic rename → protect+verify final → restore the backup and re-verify on any post-rename failure). Malformed authoritative data fails the entire load closed, exactly as `ProtectedFileKeptStateStore`/`ProtectedSyncPersistenceStore` already do.

### 15.4 Cross-file atomicity correction (§3)

§3 previously stated that a local mutation and its outbox enqueue occur "in the same atomic envelope write." **This is corrected here, not silently:** `east_kept_state` and `east_sync_state` are two separate physical files with two separate atomic-write cycles (§13.1), so no single write can ever span both. §3 now states the accurate contract: **local state and sync intent are durably linked through replayable protected intent state and reconciliation; they are not one cross-file atomic write.** The `lib/sync_integration/` intent mechanism (§15.1-15.2) is the replayable link this corrected contract refers to; a future Phase 4E-4 reconciliation pass is the explicit backstop for whatever the intent mechanism alone does not cover (most notably, Kept/Reflection data that already existed locally before this mechanism was ever introduced — see §15.6).

### 15.5 Account-scoped bootstrap/association state

`AccountSyncState` (§13) gains one new field, `bootstrapState` (`AccountBootstrapState`: `notStarted` / `remoteBaselinePending` / `localReconciliationPending` / `complete` / `associationRequired`), added as a factory-constructor parameter defaulting to `notStarted` — fully backward-compatible at both the Dart call-site level (every existing `AccountSyncState(...)` construction across this codebase's tests continues to compile and behave identically) and the wire-format level (`AccountSyncState.tryDecode` treats a missing `bootstrapState` key on a pre-Phase-4E-1 persisted bucket as `notStarted`, never as a decode failure and never as `complete` — a legacy bucket can never be assumed to have already completed a bootstrap process that did not yet exist when it was written). A *present but unrecognized* `bootstrapState` value still fails the whole account-state decode closed, exactly like every other enum-shaped field in this persisted envelope.

This status is deliberately scoped to whatever `dataEpoch` its own bucket currently carries, with no separate epoch field of its own: `AccountSyncState.copyWith` already structurally cannot change `dataEpoch` (§13.2), so a genuine epoch reset always means constructing a brand-new bucket from scratch — this status is automatically "tied to the exact dataEpoch" of whichever bucket instance carries it. Transitions are validated against one explicit, exhaustive allowlist (`isValidBootstrapTransition`, `lib/sync_persistence/account_sync_state.dart`): the forward chain `notStarted → remoteBaselinePending → localReconciliationPending → complete`; a transition to `associationRequired` from any non-`associationRequired` state (an account change may be detected at any point in bootstrap); a transition from `associationRequired` back to `notStarted` (bootstrap restarts fresh once a future phase resolves the detected account change); and a same-state no-op transition from any state (so retrying an identical checkpoint request stays idempotent). No other transition is valid. `associationRequired` is defined here so a future phase has an already-tested place to persist it; **nothing in this phase ever sets it automatically** (that requires an account-change detection this phase does not implement), and this phase adds no user-facing UI of any kind for it.

### 15.6 Atomic incoming-checkpoint operation

`SyncPersistenceStore` (§13.9) gains one new method, `commitIncomingBatchCheckpoint`, taking a `CommitIncomingBatchCheckpointRequest` (`lib/sync_persistence/incoming_batch_checkpoint.dart`) and returning a `CommitIncomingBatchCheckpointResult`. In exactly **one** coordinator-serialized read-modify-replace envelope write, it durably commits every requested record's system-fields value, the new server change token, and (optionally) a validated `AccountBootstrapState` transition — never calling `replaceRecordSystemFields`/`storeServerChangeToken` internally (which would each independently re-load and re-write the envelope, defeating the "one atomic write" guarantee). It never touches the Kept/Reflection envelope, never applies an incoming record to any repository, and never acknowledges or otherwise touches the outbox.

Two modes: `existingBucket` (the ordinary case — validates the caller's expected current `dataEpoch`, expected previous server token, and optional expected `bootstrapState` all match the actual persisted bucket before committing anything) and `bootstrapCreate` (the one-time remote-bootstrap case — creates a brand-new bucket using exactly one explicitly-supplied `DataEpoch`, permitted only when no bucket already exists for that fingerprint, the request's expected-current-epoch/expected-previous-token fields are both `null`, and the requested bootstrap-state transition is valid; this method never fabricates an epoch on its own, and never overwrites a bucket that unexpectedly already exists). Every business-rule failure (missing bucket, epoch mismatch, token mismatch, bootstrap-state mismatch, an invalid transition, a duplicate record name, an invalid record-system-fields value, or a structurally malformed request) is returned as a typed, non-`committed` `IncomingCheckpointStatus` — never thrown — so this phase's own privacy-safe result type (`toLogSafeSummary`: status/counts/booleans only) is the one thing every caller needs to inspect; only a genuine underlying storage failure still surfaces as a thrown `SyncPersistenceStoreException`, exactly as every other method on this interface already behaves.

This operation implements only step 8 of the future Phase 4E-3 incoming-apply transaction (below) — it does not implement steps 1-7, and this phase calls it from nowhere in production.

**Future Phase 4E-3's full incoming-apply transaction** (unchanged from, and still owned entirely by, Phase 4E-3 — restated here only for the exact boundary this phase's one new operation fits into): (1) validate the current usable account fingerprint; (2) validate the current `dataEpoch`/bootstrap state; (3) validate the currently persisted previous server token; (4) validate every incoming record; (5) reject duplicate record names/`revealId`s inside the batch; (6) calculate one complete merged Kept envelope; (7) replace the Kept envelope once; (8) atomically persist all incoming record system fields and the new server token in one sync-envelope write — this is exactly `commitIncomingBatchCheckpoint`, called only after step 7 has already durably succeeded, never before.

### 15.7 Repository boundary (unchanged, restated explicitly)

`KeptRepository` remains the local Kept repository. It imports nothing from `lib/sync_platform/` and gains no CloudKit transport knowledge of its own in this phase, and none is planned to be added to it directly by any future phase either — the intended shape (`kept_sync_integration_coordinator.dart`, §15.1) composes `KeptRepository`, `SyncPersistenceStore`, and `LocalSyncIntentStore` together from *outside* `KeptRepository`, never the reverse.

### 15.8 Local limits versus remote restore behavior — open decision, not resolved by this phase

The current free-tier limits (3 Kept, 3 Reflections; Keeper unlimited) are enforced by `KeptRepository` only against *new local user actions* (`keepOccurrence`/`saveReflection`). **This phase makes no change to that enforcement, and does not decide** whether a future Phase 4E-3 incoming-apply step must also honor those limits against *restored/incoming* remote data. Per this document's own explicit instruction, incoming remote data and restoration must never be silently truncated to enforce a free-tier limit that was only ever designed to gate a user's own new local actions — but the exact mechanism (bypass the limit entirely for incoming application, or something else) remains an explicit open decision for whichever phase first implements incoming Kept-envelope application (Phase 4E-3), not something this phase's new persistence foundations presume an answer to.

### 15.9 Occurrence `revealedAt` versus daily-access state — restated, not reopened

`KeptRecord.revealedAt`/`CloudKeptWisdomProjection.revealedAtMs` (§2.3) is **occurrence `revealedAt`** — a Kept occurrence's own immutable historical snapshot of when that specific saved wisdom was originally revealed, syncing exactly as `keptAt` already does. This is categorically distinct from, and never derived from or written into, the permanently device-local daily-ritual state this document already excludes absolutely (§1: "No daily-access records in CloudKit, ever, in any form" — `daily_wisdom_access`, the rolling 24-hour lock, daily access's own `unlockAt`/lock duration, current ritual screen/animation state, ritual eligibility, Keeper purchase state, and ritual availability state). Nothing in this phase renames, touches, or reinterprets `KeptRecord.revealedAt` — it remains exactly the field Phase 4A already froze and Phase 4C-1 already implemented; this section exists only to record the distinction explicitly, per this phase's own product-decision list, not to change any behavior.

### 15.10 Privacy rule for opaque identifiers in diagnostics

Every new production type this phase adds follows the same rule Phase 4D-1/4D-2 already established, stated once more, explicitly, because this phase's own instruction treats it as a first-class requirement rather than an inherited assumption: an opaque identifier (a `revealId`, a `mutationId`, an `intentId`, a record name, an account fingerprint, a `dataEpoch` value, or a server token) is **not** considered safe for diagnostics merely because it is already opaque — `LocalSyncIntent.toLogSafeSummary`/`toString`, `CommitIncomingBatchCheckpointResult.toLogSafeSummary`/`toString`, and every exception this phase adds (`LocalSyncIntentStoreException`, `ConflictingLocalSyncIntentIdentityException`, `LocalSyncIntentStageMismatchException`) render only categorical status, counts, and booleans (or, for exceptions, a static stage name and content-free message, with `cause` always excluded from `toString`) — never any of the identifier values themselves.

### 15.11 Explicit boundaries between 4E-1 and later subphases

- **Phase 4E-1 (this phase):** contracts, models, durable persistence foundations, and tests only — no real user-mutation wiring, no incoming application, no bootstrap execution, no reconciliation execution.
- **Phase 4E-2:** wires real `KeptRepository` mutation methods (`keepOccurrence`, `saveReflection`, `deleteReflection`, `remove`) through the `LocalSyncIntent`/`LocalSyncIntentStore` seam this phase establishes, converting a resolved intent into a real `SyncChange` and enqueuing it via `SyncPersistenceStore.enqueueMutation`.
- **Phase 4E-3:** implements the full incoming-apply transaction (§15.6's eight steps), calling `commitIncomingBatchCheckpoint` only for its final step.
- **Phase 4E-4:** implements the actual existing-user bootstrap execution (using the `AccountBootstrapState` vocabulary this phase defines) and the reconciliation backstop §15.4 anticipates.
- **Phase 4E-5:** synthetic end-to-end tests spanning the above, still with no automatic startup trigger.
- **Phase 4F:** startup wiring, foreground/lifecycle triggers, account-change subscriptions, network-return triggers, retry scheduling, and any background/automatic execution — none of which any 4E subphase, including this one, introduces.

### 15.12 Explicit non-goals (Phase 4E-1)

No wiring of any kind to `KeptRepository`, `SavedReflectionsService`, any screen, `lib/main.dart`, app startup, a lifecycle observer, an account-change listener, or a network observer. No actual Keep/unkeep/Reflection-to-outbox conversion. No incoming Kept-envelope application. No existing-user bootstrap execution and no reconciliation execution. No account-change detection and no automatic `associationRequired` transition. No Settings or sync-status UI. No change to `lib/main.dart`, iOS/native files, entitlements, the Xcode project, `pubspec.yaml`/`pubspec.lock`, deployment target, build number 25, `KeptRepository`'s own dependencies, existing Kept/Reflection persistence behavior, daily-access behavior, or any existing free/Keeper limit enforcement for local actions. No automated test in this phase contacts real CloudKit, a real `MethodChannel`, or a real native file-protection channel.
