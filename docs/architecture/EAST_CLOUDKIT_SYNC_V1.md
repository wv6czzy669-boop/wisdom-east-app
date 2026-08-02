# EAST. CloudKit Sync Design v1.0 (Phase 4A, updated for Phase 4B-1, Phase 4B-2, and Phase 4C-1)

**Status:** Phase 4A's architecture and pure Dart sync-domain foundation are implemented (Sections 1-9). Phase 4B-1 (Section 10) additionally implements a native Swift CloudKit bridge **foundation** — account snapshot, private-zone configuration, static bridge info, and account-change events — behind a narrow Dart platform-bridge layer. Phase 4B-2 activated the iCloud/CloudKit capability and hardened private-zone configuration (including a guarded `CKError.serverRejectedRequest` create-fallback, confirmed necessary and safe on a physical device). Phase 4C-1 (Section 11) additionally implements the **record-schema and encode/decode codec foundation** for both private record types, on both the Dart and native Swift sides — still transport-free. **No Kept/Reflection record has ever been uploaded, downloaded, merged, or deleted.** Every CloudKit read/write operation remains absent from this codebase: nothing in this app's startup path or repository code invokes any of it. This document is the precise design ADR-007 (`docs/decisions/ADR-007-build-26-local-storage-and-icloud-sync.md`) requires its implementation phases to follow.

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
- **A successful local change enqueues durable sync work** (an outbox entry, per ADR-007's Local state envelope/Deletion-outbox strategy) in the **same atomic envelope write** as the local mutation itself — never a separate, later write that could be lost independently.
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

**Inspected:** `ios/Runner.xcodeproj/project.pbxproj` → `IPHONEOS_DEPLOYMENT_TARGET = 13.0` (all three build configurations: Debug, Release, Profile).

**`CKSyncEngine`** (Apple's higher-level, state-machine-managed CloudKit sync API) requires iOS 17 / macOS 14 or later. Raising the minimum supported iOS version is explicitly out of scope for Phase 4A ("Do not raise the minimum iOS version in Phase 4A"), so `CKSyncEngine` **cannot be recommended for this phase** — it is not available on the deployment target this app currently supports.

**Recommendation: an operation-based CloudKit architecture**, built directly on the CloudKit operation classes that have been available since well before iOS 13 and require no minimum-version increase:

- `CKFetchDatabaseChangesOperation` — discovers which zones in the private database have changed (in this design, effectively just `EASTKeptZone`, but the operation is still the correct primitive for discovering zone-level changes and deletions).
- `CKFetchRecordZoneChangesOperation` — pulls changed/deleted records within `EASTKeptZone` since the last persisted server change token, using the zone-level change token (persisted in `syncMetadata`, per ADR-007's Local state envelope).
- `CKModifyRecordsOperation` — pushes local outbox creates/updates (including soft-tombstone updates, §2.4) in batches, using per-record save policies and `CKRecord.ID`-scoped conflict detection (`serverRecordChanged`, §4.2).
- `CKFetchRecordsOperation` / direct record fetch — used narrowly for the `CKEastSyncState` singleton bootstrap/read (§ADR-007 Initial data-epoch bootstrap) and for the prior-epoch cleanup job's own record enumeration.
- Zone/database subscriptions (`CKRecordZoneSubscription`) are **not required** for this design's foreground-only sync timing (ADR-007, Sync timing) and are not part of Phase 4A or its immediate successor — silent push and background delivery are explicit non-goals.

This operation-based approach requires materially more of the durable bookkeeping ADR-007 already specifies as belonging to the local envelope (`syncMetadata`'s per-record pending-operation state, the zone's server change token, last-successful-sync bookkeeping) than `CKSyncEngine` would have required on its own — `CKSyncEngine` manages an equivalent state machine internally. This is an accepted, explicit cost of supporting iOS 13, not an oversight; if a future phase raises the minimum deployment target to iOS 17+, migrating from the operation-based design to `CKSyncEngine` is a contained, later decision (an ADR of its own), not a change forced by this document.

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
