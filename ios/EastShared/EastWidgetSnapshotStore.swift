import Foundation

/// The Medium Widget's own resolved view of the day's ritual, mirrored --
/// never independently decided -- from Flutter's authoritative
/// `DailyWisdomAccessService`. Nothing here selects, generates, or reveals
/// wisdom; it only stores exactly what `EastWidgetSnapshotBridge` was told at
/// the one authoritative reveal-commit moment, plus what a resume-time
/// reconciliation republishes.
///
/// Deliberately minimal: the revealed text and its unlock/expiry `Date` are
/// the only two pieces of state kept. No Reflection text, owner name, Kept/
/// Return data, `localId`, account fingerprint, CloudKit identifier,
/// analytics identifier, purchase history, sync epoch, or deletion
/// transaction ever passes through this store.
enum EastWidgetState: Equatable {
    case silence
    case revealed(text: String, unlockAt: Date)
}

/// EAST. 1.2 Slice 1 -- the widget's explicit presentation preferences,
/// independent from [EastWidgetState]'s content. Nothing here selects,
/// generates, resolves, or reveals wisdom, and nothing here is itself
/// wisdom/reflection content -- it only mirrors the app's own explicit
/// Appearance and Language overrides so the widget can honor them instead
/// of always following the device's system appearance/locale.
///
/// `.system` for appearance and `nil` for `localeOverrideTag` both mean the
/// same thing: "no explicit EAST. override -- follow the extension's own
/// current system value," resolved live wherever this is rendered, never
/// frozen at publish time.
enum EastWidgetAppearanceMode: String, Equatable {
    case system
    case light
    case dark
}

struct EastWidgetPresentation: Equatable {
    let appearanceMode: EastWidgetAppearanceMode
    let localeOverrideTag: String?

    static let systemDefault = EastWidgetPresentation(
        appearanceMode: .system,
        localeOverrideTag: nil
    )
}

/// The full resolved view a later slice's `TimelineProvider` will read:
/// [EastWidgetState]'s existing content, unchanged, paired with the
/// independently-resolved [EastWidgetPresentation]. Presentation validation
/// failures never affect content resolution, and content validation
/// failures never affect presentation resolution -- the two are resolved
/// by entirely separate code paths below.
struct EastWidgetSnapshot: Equatable {
    let content: EastWidgetState
    let presentation: EastWidgetPresentation
}

/// Regression-hardening pass: this store is a long-lived native integration
/// point that must survive app relaunches, device restarts, process death,
/// delayed WidgetKit refresh, and App Group state carried over an app/
/// extension binary upgrade -- all without ever crashing, revealing content
/// that should not currently be visible, or fabricating a wisdom of its own.
/// Every read is defensive; every write validates its own input before ever
/// persisting it. Invalid/unreadable state always fails closed to
/// `.silence`, never guessed or reconstructed.
enum EastWidgetSnapshotStore {
    static let appGroupIdentifier = "group.com.dogukan.dailywisdom"

    /// Minimal explicit schema marker (not a migration framework): every
    /// fresh write stamps the current version. A snapshot with no version
    /// key at all predates this field entirely -- treated as compatible
    /// with version 1 so an in-flight valid Phase 11 snapshot keeps working
    /// across the upgrade to this hardened store, rather than suddenly
    /// reading as invalid. A snapshot whose version key holds anything
    /// *other* than the current version is from a future/unknown format
    /// this binary cannot safely interpret, and fails closed to silence.
    static let schemaVersion = 1

    private static let schemaVersionKey = "east_widget_schema_version_v1"
    private static let stateKey = "east_widget_state_v1"
    private static let stateRevealed = "revealed"
    private static let stateSilence = "silence"
    private static let textKey = "east_widget_text_v1"
    private static let unlockAtKey = "east_widget_unlock_at_v1"

    /// EAST. 1.2 Slice 1 -- presentation keys, deliberately namespaced apart
    /// from the content keys above and gated by no shared schema version:
    /// each is read/written independently, so a malformed or absent
    /// presentation value can never invalidate, hide, or alter valid
    /// content, and vice versa. Purely additive -- `schemaVersion` above is
    /// not bumped for these.
    private static let presentationAppearanceKey = "east_widget_presentation_appearance_v1"
    private static let presentationLocaleOverrideKey = "east_widget_presentation_locale_override_v1"

    /// The real, shared App Group container. Production call sites below
    /// never reference this directly -- only through the single-argument
    /// overloads, which resolve it exactly once per call. Tests instead
    /// call the explicit `defaults:`-taking overloads with a fully isolated
    /// `UserDefaults` (or literal `nil`, to exercise "App Group
    /// unavailable"), never touching the real shared container at all.
    private static var productionDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    // MARK: - Writes

    /// Returns `true` only when the persisted snapshot actually changed as a
    /// result of this call -- the bridge uses this to decide whether a
    /// `WidgetCenter.reloadTimelines` call is warranted, so an ordinary
    /// republish of the same occurrence (e.g. a resume-time reconciliation
    /// that finds nothing new) never triggers a reload.
    @discardableResult
    static func publishRevealed(text: String, unlockAt: Date) -> Bool {
        publishRevealed(text: text, unlockAt: unlockAt, defaults: productionDefaults)
    }

    @discardableResult
    static func publishRevealed(
        text: String,
        unlockAt: Date,
        defaults: UserDefaults?
    ) -> Bool {
        guard let defaults else { return false }

        // Defensive backstop only -- `EastWidgetSnapshotBridge` already
        // validates argument presence/type before ever reaching here. Never
        // persist unsafe/invalid revealed content (empty/whitespace-only
        // text, or a non-finite unlock instant): fail closed to silence
        // instead of storing something `resolvedState` would only have to
        // reject later anyway.
        guard isValidRevealedText(text), isValidUnlockAt(unlockAt) else {
            return writeSilence(defaults: defaults)
        }

        let unchanged = defaults.string(forKey: stateKey) == stateRevealed
            && defaults.string(forKey: textKey) == text
            && defaults.object(forKey: unlockAtKey) != nil
            && defaults.double(forKey: unlockAtKey) == unlockAt.timeIntervalSince1970

        defaults.set(stateRevealed, forKey: stateKey)
        defaults.set(text, forKey: textKey)
        defaults.set(unlockAt.timeIntervalSince1970, forKey: unlockAtKey)
        defaults.set(schemaVersion, forKey: schemaVersionKey)
        return !unchanged
    }

    @discardableResult
    static func publishSilence() -> Bool {
        publishSilence(defaults: productionDefaults)
    }

    @discardableResult
    static func publishSilence(defaults: UserDefaults?) -> Bool {
        guard let defaults else { return false }
        return writeSilence(defaults: defaults)
    }

    @discardableResult
    private static func writeSilence(defaults: UserDefaults) -> Bool {
        let unchanged = defaults.string(forKey: stateKey) == stateSilence
            || defaults.string(forKey: stateKey) == nil

        defaults.set(stateSilence, forKey: stateKey)
        defaults.removeObject(forKey: textKey)
        defaults.removeObject(forKey: unlockAtKey)
        defaults.set(schemaVersion, forKey: schemaVersionKey)
        return !unchanged
    }

    // MARK: - Presentation-aware writes (EAST. 1.2 Slice 1, wired to the bridge in Slice 2A)

    /// Writes content through the exact same unmodified
    /// `publishRevealed(text:unlockAt:defaults:)` this file already had,
    /// then writes presentation through the same `defaults` handle, so both
    /// land before this call returns. Returns `true` when either content or
    /// presentation actually changed.
    @discardableResult
    static func publishRevealed(
        text: String,
        unlockAt: Date,
        presentation: EastWidgetPresentation,
        defaults: UserDefaults?
    ) -> Bool {
        guard let defaults else { return false }
        let contentChanged = publishRevealed(text: text, unlockAt: unlockAt, defaults: defaults)
        let presentationChanged = writePresentation(presentation, defaults: defaults)
        return contentChanged || presentationChanged
    }

    /// EAST. 1.2 Slice 2A -- the production convenience overload
    /// `EastWidgetSnapshotBridge` calls for a presentation-aware reveal,
    /// resolving the real shared App Group container exactly once, mirroring
    /// `publishRevealed(text:unlockAt:)` above.
    @discardableResult
    static func publishRevealed(
        text: String,
        unlockAt: Date,
        presentation: EastWidgetPresentation
    ) -> Bool {
        publishRevealed(text: text, unlockAt: unlockAt, presentation: presentation, defaults: productionDefaults)
    }

    /// Mirrors `publishRevealed(text:unlockAt:presentation:defaults:)`
    /// above: delegates content to the exact same unmodified
    /// `publishSilence(defaults:)`, then writes presentation.
    @discardableResult
    static func publishSilence(
        presentation: EastWidgetPresentation,
        defaults: UserDefaults?
    ) -> Bool {
        guard let defaults else { return false }
        let contentChanged = publishSilence(defaults: defaults)
        let presentationChanged = writePresentation(presentation, defaults: defaults)
        return contentChanged || presentationChanged
    }

    /// EAST. 1.2 Slice 2A -- the production convenience overload
    /// `EastWidgetSnapshotBridge` calls for a presentation-aware silence,
    /// mirroring `publishSilence()` above.
    @discardableResult
    static func publishSilence(presentation: EastWidgetPresentation) -> Bool {
        publishSilence(presentation: presentation, defaults: productionDefaults)
    }

    /// Returns `true` only when the persisted presentation actually changed.
    /// `appearanceMode` is always written explicitly (including `.system`,
    /// per this slice's own requirement -- `.system` is a real, durable
    /// resolved value here, not merely "absent").
    ///
    /// Slice 1 correction: `localeOverrideTag` is normalized through the
    /// exact same `parseLocaleOverrideTag` used on read -- the single
    /// source of truth for "is this one of EAST.'s 15 canonical product
    /// tags" -- *before* it is ever compared or persisted, never trusted
    /// verbatim from the caller. An invalid raw value (a bare `pt`/`zh`,
    /// wrong casing, or anything outside the allowlist) is therefore never
    /// written to the App Group at all; it is treated exactly as `nil`
    /// (System Default), removing any existing key. The *existing* stored
    /// value is normalized the same way before comparison, so a
    /// previously-invalid or stale value already in the store can never
    /// cause a spurious "changed" result once both sides agree it means
    /// System Default. `localeOverrideTag` is removed entirely when the
    /// normalized value is `nil`, so its absence is exactly what "follow
    /// system locale" means on read -- never a stored empty-string
    /// sentinel and never a stored invalid tag.
    @discardableResult
    private static func writePresentation(
        _ presentation: EastWidgetPresentation,
        defaults: UserDefaults
    ) -> Bool {
        let normalizedLocaleOverrideTag = parseLocaleOverrideTag(presentation.localeOverrideTag)
        let existingNormalizedLocaleOverrideTag =
            parseLocaleOverrideTag(defaults.string(forKey: presentationLocaleOverrideKey))

        let unchanged = defaults.string(forKey: presentationAppearanceKey)
            == presentation.appearanceMode.rawValue
            && existingNormalizedLocaleOverrideTag == normalizedLocaleOverrideTag

        defaults.set(presentation.appearanceMode.rawValue, forKey: presentationAppearanceKey)
        if let normalizedLocaleOverrideTag {
            defaults.set(normalizedLocaleOverrideTag, forKey: presentationLocaleOverrideKey)
        } else {
            defaults.removeObject(forKey: presentationLocaleOverrideKey)
        }
        return !unchanged
    }

    // MARK: - Reads

    /// Self-healing, defensive resolution used by the widget's own
    /// `TimelineProvider`. Even if the persisted state still says
    /// "revealed" -- for example because the app never got a chance to
    /// publish silence, or a native timeline refresh fired a little late --
    /// this never trusts a "revealed" flag past its own `unlockAt`; a stale
    /// record always resolves back to `.silence` on read, with no countdown
    /// ever computed or shown. Every field is independently validated:
    /// missing/wrong-type/malformed/empty/non-finite/partial/unknown-
    /// version state all fail closed to `.silence`, and this never throws
    /// or crashes regardless of what is actually stored.
    static func resolvedState(now: Date) -> EastWidgetState {
        resolvedState(now: now, defaults: productionDefaults)
    }

    static func resolvedState(now: Date, defaults: UserDefaults?) -> EastWidgetState {
        guard let defaults,
              isCurrentSchemaVersion(defaults),
              defaults.string(forKey: stateKey) == stateRevealed,
              let text = defaults.string(forKey: textKey),
              isValidRevealedText(text),
              defaults.object(forKey: unlockAtKey) != nil
        else {
            return .silence
        }

        let unlockAtSeconds = defaults.double(forKey: unlockAtKey)
        guard unlockAtSeconds.isFinite else { return .silence }

        let unlockAt = Date(timeIntervalSince1970: unlockAtSeconds)
        guard unlockAt > now else { return .silence }
        return .revealed(text: text, unlockAt: unlockAt)
    }

    /// Pairs the exact existing `resolvedState(now:defaults:)` content
    /// result (untouched since Slice 1) with the independently-resolved
    /// presentation below.
    static func resolvedSnapshot(now: Date, defaults: UserDefaults?) -> EastWidgetSnapshot {
        EastWidgetSnapshot(
            content: resolvedState(now: now, defaults: defaults),
            presentation: resolvedPresentation(defaults: defaults)
        )
    }

    /// EAST. 1.2 Slice 2B -- the production convenience overload
    /// `EastWidgetProvider` calls, resolving the real shared App Group
    /// container exactly once, mirroring `resolvedState(now:)` above.
    static func resolvedSnapshot(now: Date) -> EastWidgetSnapshot {
        resolvedSnapshot(now: now, defaults: productionDefaults)
    }

    /// Defensive, independent of content resolution: a missing App Group,
    /// missing keys, or malformed values each fall back to their own safe
    /// default field-by-field, never to `.silence` and never affecting
    /// whether content resolves.
    private static func resolvedPresentation(defaults: UserDefaults?) -> EastWidgetPresentation {
        guard let defaults else { return .systemDefault }
        return EastWidgetPresentation(
            appearanceMode: parseAppearanceMode(defaults.string(forKey: presentationAppearanceKey)),
            localeOverrideTag: parseLocaleOverrideTag(
                defaults.string(forKey: presentationLocaleOverrideKey)
            )
        )
    }

    /// EAST. 1.2 Slice 2A -- the one narrow entry point `EastWidgetSnapshotBridge`
    /// (a different file, same module) uses to turn raw, untrusted
    /// MethodChannel argument strings into a validated `EastWidgetPresentation`.
    /// Reuses exactly the same `parseAppearanceMode`/`parseLocaleOverrideTag`
    /// this store already uses for its own write- and read-time validation --
    /// never a second, independent copy of the 15-locale allowlist or
    /// appearance parsing. Missing/invalid appearance resolves to `.system`;
    /// missing/invalid locale override resolves to `nil`; the two fields are
    /// validated entirely independently, so one invalid field never discards
    /// the other, valid one, and this function never touches content state
    /// at all.
    static func validatedPresentation(
        appearanceModeRaw: String?,
        localeOverrideTagRaw: String?
    ) -> EastWidgetPresentation {
        EastWidgetPresentation(
            appearanceMode: parseAppearanceMode(appearanceModeRaw),
            localeOverrideTag: parseLocaleOverrideTag(localeOverrideTagRaw)
        )
    }

    // MARK: - Validation

    private static func isValidRevealedText(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func isValidUnlockAt(_ date: Date) -> Bool {
        date.timeIntervalSince1970.isFinite
    }

    /// Absent means "written before schema versioning existed" -- treated
    /// as compatible with the current version (see `schemaVersion`'s own
    /// doc comment) rather than invalid.
    private static func isCurrentSchemaVersion(_ defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: schemaVersionKey) != nil else { return true }
        return defaults.integer(forKey: schemaVersionKey) == schemaVersion
    }

    /// Absent or any string other than exactly `"system"`/`"light"`/`"dark"`
    /// (including case variants, e.g. `"Light"`) resolves to `.system` --
    /// never guessed, never a crash.
    private static func parseAppearanceMode(_ raw: String?) -> EastWidgetAppearanceMode {
        guard let raw, let mode = EastWidgetAppearanceMode(rawValue: raw) else {
            return .system
        }
        return mode
    }

    /// EAST. 1.2 Slice 2B -- delegates entirely to
    /// `EastWidgetLocaleResolver.validatedOverrideTag`, the single native
    /// product-locale allowlist authority, rather than keeping a second,
    /// independent copy of the 15-locale allowlist here. Absent, a bare
    /// technical fallback tag (`"pt"`, `"zh"`), a case variant, or any tag
    /// outside EAST.'s 15 reviewed product locales all resolve to `nil` --
    /// exactly the same meaning as "never explicitly overridden," which is
    /// the only safe interpretation of a value this binary cannot validate.
    private static func parseLocaleOverrideTag(_ raw: String?) -> String? {
        EastWidgetLocaleResolver.validatedOverrideTag(raw)
    }
}
