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
}
