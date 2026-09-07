# Dated Reflection thoughts

The original Reflection remains in `reflectionText` / `reflectedAt`. A person
can add another dated thought without changing that original or requesting
another wisdom. This changes no ritual eligibility, Keeper entitlement or
free-tier occurrence limit.

## Storage and sync

`reflectionHistoryJson` is an optional String on an active `KeptRecord` and
its `CKKeptWisdom` projection. Existing local records need no migration.
The existing active record schema stays at 3; the JSON payload is version 1:

```json
{
  "version": 1,
  "clearedAtMs": 0,
  "thoughts": [
    {
      "id": "aaaaaaaa-0000-4000-8000-000000000001",
      "text": "A later thought.",
      "createdAtMs": 1788602400000,
      "updatedAtMs": 1788602400000,
      "mutationId": "bbbbbbbb-0000-4000-8000-000000000001"
    }
  ]
}
```

Each thought has a stable UUID and immutable writing date, with a 1,000
grapheme text limit. The complete encoded field is limited to 512 KiB;
an oversized write fails without truncating stored writing. The editor
retains the draft and offers Copy and Retry. “Saved” acknowledges a durable
local write, never a CloudKit upload.

The existing record winner still controls the original Reflection and
occurrence metadata. Within the same occurrence and data epoch, additional
thoughts merge by identity; edits to the same thought use its timestamp and
mutation ID. Independent offline additions survive. A deterministic merge
mutation is durably staged before local replacement or a sync checkpoint,
then sent through the existing outbox. Epoch and Kept tombstone precedence
are unchanged. Reflection deletion clears the whole collection and persists
a watermark to filter delayed pre-deletion thoughts.

Older clients do not display the additional field. If an older client deletes
the original Reflection and leaves the unknown field on the server, the new
remote parser treats the residual valid history as deleted. Invalid JSON
remains a failure, and local disk parsing stays strict. All devices should
use the new build to read and edit dated thoughts.

Journal renders each thought and its writing date, including across page
breaks, with matching VoiceOver content. Kept search includes later thoughts.
Data Export format 3 includes a `thoughts` array with user-owned text, IDs and
ISO dates; it excludes sync mutation IDs and deletion metadata.

## CloudKit release prerequisite

Before distributing a build with this feature, verify the following additive
field in the CloudKit schema for `iCloud.com.dogukan.dailywisdom`:

| Record type | Field | Type | Index requirement |
| --- | --- | --- | --- |
| `CKKeptWisdom` | `reflectionHistoryJson` | String, optional | None |

Create/verify the field in Development, then deploy the additive schema to
Production before TestFlight/App Store rollout. The app continues using the
private database and `EASTKeptZone`. This needs no zone reset, record deletion,
new container, or change to the existing fields. The field contains private
writing and follows the existing database access controls.

No CloudKit schema deployment was performed during this implementation.
Automated two-device sync uses the synthetic CloudKit server; native tests
exercise CKRecord encoding, decoding and field clearing. Release validation
still needs a real iCloud round trip on two devices running the new build.
