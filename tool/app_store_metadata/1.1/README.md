# EAST. 1.1 App Store Metadata

Ready-to-paste App Store Connect text for EAST. 1.1.0+31.

## Final identity decisions

- App name: **KEEP EXISTING — `EAST.`**. Apple’s public catalog currently lists the live app under this name, so it remains unchanged in every locale.
- English subtitle: **KEEP EXISTING — `Where Silence Speaks`**. This preserves the approved product direction without adding a period to the App Store field.
- Promotional text, description, keywords, and What’s New: use the final 1.1 values in each locale file.
- `master_en.md` is the semantic source of truth. Every localized description was written directly from that final English version.

## Files

- `master_en.md`: final English semantic master
- `app_review_notes_en.md`: final English App Review notes
- `metadata.json`: all fields, exact character/UTF-8 byte counts, limits, and review notes
- `en.md`, `tr.md`, `ja.md`, `de.md`, `fr.md`, `ko.md`, `zh-Hant.md`, `ar.md`, `es.md`, `pt-BR.md`, `it.md`, `th.md`, `nl.md`, `pl.md`, `vi.md`: locale-specific copy/paste sheets

Exactly 15 product locales are included. Generator-only `pt` and `zh` fallback catalogs are intentionally excluded.

## Validated App Store Connect limits

| Field | Limit | Validation unit |
| --- | ---: | --- |
| App name | 30 | characters |
| Subtitle | 30 | characters |
| Promotional text | 170 | characters |
| Description | 4,000 | characters |
| Keywords | 100 | UTF-8 bytes |
| What’s New | 4,000 | characters |
| App Review notes | 4,000 | UTF-8 bytes |

Counts in `metadata.json` record both Unicode character count and UTF-8 byte count for every localized field. Keyword acceptance is evaluated by UTF-8 bytes, which is especially important for non-Latin locales.

Official references:

- [Apple — App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/)
- [Apple — Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/)

## Content lock

The final copy consistently states:

- one wisdom per rolling 24 hours
- no feed, streak, or endless scroll
- Keep, private Reflection, Kept, and Journal
- Keeper is an optional one-time purchase
- Keeper never grants another daily wisdom
- 15-language support in version 1.1

The copy contains no retired feature references, subscription claim, medical or mental-health outcome, AI-personalization claim, or additional-daily-wisdom claim.

## App Store Connect workflow

Open the required locale file and copy each value under its matching heading. Use `app_review_notes_en.md` once for the English App Review Notes field. Do not paste Markdown headings into App Store Connect.
