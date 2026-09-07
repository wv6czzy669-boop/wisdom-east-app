# Daily ritual account authority

Product decision, 2026-09-07: one wisdom per iCloud account per rolling 24 hours,
including Keeper. A new occurrence requires iCloud and internet. Previously
opened wisdom and local Kept, Reflection and Journal remain readable offline.
This supersedes earlier documents' device-only daily-access requirement.

## Authorization

Runner and the interactive widget use the same CloudKit private database in
`iCloud.com.dogukan.dailywisdom`, separate from optional private-writing sync.
The fixed `current` record in `EASTDailyRitualZone` is the account authority.

An explicit Ask tap probes server time, reads the current record, and either
returns its still-active occurrence or saves a replacement with
`ifServerRecordUnchanged`. Competing requests retry the read after a conflict;
only one can create the next interval. Newly created intervals start at
CloudKit's server-assigned modification date and last exactly 86,400,000 ms.
Device time, candidate preparation and cached data cannot authorize a new
occurrence. Clock-probe writes do not modify the grant record.

The server UUID, public wisdom catalog ID and timestamps are copied unchanged
into the shared protected cache and Flutter daily record. Each device resolves
the public quote in its own language. No question, quote text, private writing,
purchase information or raw Apple account ID is sent through this channel.
The local account scope is a namespaced hash; it is neither uploaded nor logged.

CloudKit authorization is persisted before new text is shown. If the response
is lost, the app is backgrounded or local persistence fails after the server
save, a retry recovers that same occurrence. An uncertain response never falls
back to a local grant. Authorization failure restores Ask with a retry message;
if an earlier occurrence exists, “Previous wisdom” opens it without extending
its interval or generating ritual-completion side effects. A quiet Retry
control on that reading view returns to Ask in the same session, using the
existing fade timing. Returning to Ask does not itself claim a new occurrence.

## Upgrade and account changes

Existing local occurrences remain readable offline. A background refresh can
seed an empty account record with an already-opened legacy occurrence, keeping
its original UUID and original interval. It cannot seed an expired/future
occurrence, overwrite an existing account record, or create a fresh right.
Pre-upgrade widget documents without a reveal UUID have a bounded local import
path; new widget documents must import the shared server-authorized cache.

Account-change notifications invalidate an in-flight CloudKit transport.
Returned grants are checked against that request's verified account scope.
Different iCloud accounts have independent rights. This is an iCloud-account
identity model, not an EAST login or a way to identify a human across accounts.

The strict rule applies to this version's clients. Older already-installed
versions can still reveal locally until updated. A private CloudKit database
is owned by the Apple user; this is a consistency boundary for the official
clients, not a tamper-proof anti-abuse backend. Manual deletion of app cloud
data cannot be prevented by a private-database client.

## Schema and release

Validation on 2026-09-07: 2,537 Flutter tests, 227 native tests, and all 17
locales rendered in light/dark mode at standard and 200% text size (68 screens).
The two Development record types and all five custom fields are saved and were
deployed to Production on 2026-09-07 after explicit user approval. CloudKit
confirmed “The schema is deployed to Production.” The additive deployment
included only the two new types and their default `_world` Read, `_icloud`
Create, and `_creator` Write schema roles; existing record types were unchanged.
Runtime records are written only to the account's private database.

The widget's Apple-managed signing profile was refreshed with the iCloud
capability. A signed Release build for iOS succeeded, and code-signature
verification confirmed the widget's CloudKit/container entitlement. The
embedded Runner and widget development profiles both allow the same container
and Development/Production environments. These are device development signing
checks; App Store export must still select valid distribution profiles.
After the offline-reading return was added, all 129 Home, ritual-controller
and save-feedback layout tests passed again.

The additive field manifest is `daily_ritual_cloudkit_schema.json`.
Both types need to exist in Development and be deployed to Production before
shipping. Fetches use record IDs; no query/search indexes are required.

| Record | Fields | Save policy |
| --- | --- | --- |
| `CKEastDailyRitual/current` | `schemaVersion: INT64`, `wisdomId: STRING`, `revealId: STRING`, optional `legacyRevealedAtMs: INT64` | ifServerRecordUnchanged |
| `CKEastDailyRitualClock/clock` | `nonce: STRING` | allKeys |

The private-writing zone, its opt-in preference and its “Remove from iCloud”
operation remain separate. Removing those writing copies must not reset the
daily right. The widget extension needs the same CloudKit container entitlement
as Runner; verify the distribution provisioning profile before release.

Release verification requires two signed physical devices on the same iCloud
account: simultaneous Ask taps, app/widget handoff, offline denial and cached
reading, account switch, reinstall, and boundary behavior. Simulator unit tests
exercise concurrency and failures using an injectable CloudKit transport; they
do not prove Production schema, signing or real network behavior.

The local countdown is a presentation estimate from the device clock. Moving
that clock forward can make the UI offer a ritual early, but the server still
returns the existing occurrence and never grants an early replacement.

Apple contracts: [conditional saves](https://developer.apple.com/documentation/cloudkit/ckmodifyrecordsoperation/recordsavepolicy/ifserverrecordunchanged)
and [server modification date](https://developer.apple.com/documentation/cloudkit/ckrecord/modificationdate).
