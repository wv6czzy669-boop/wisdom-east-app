import XCTest

@testable import Runner

/// Widget health / regression hardening.
///
/// Every test here uses a fully isolated `UserDefaults` suite -- never the
/// real `group.com.dogukan.dailywisdom` App Group container -- so these
/// tests are deterministic regardless of whether App Group provisioning is
/// actually configured in the environment they run in, and can never leak
/// state into (or read stale state from) a real device/simulator's shared
/// container. `EastWidgetSnapshotStore` is otherwise fully stateless (all
/// state lives in the injected `UserDefaults`), so "process/repository
/// recreation" is modeled faithfully by simply constructing a *second*,
/// independent `UserDefaults(suiteName:)` handle onto the same suite.
///
/// Dates use a fixed, whole-second reference instant throughout (never
/// `Date()`) for two reasons: determinism (no wall-clock dependency), and
/// -- decisively -- because `UserDefaults`/CFPreferences round-trips a
/// stored `Double` through property-list (de)serialization, which does not
/// always preserve `Date()`'s full sub-millisecond precision. Comparing a
/// freshly-read `Date` for exact equality against a sub-millisecond-precise
/// `Date()` value is not a real product requirement (production `unlockAt`
/// values only ever carry millisecond precision to begin with -- see
/// `EastWidgetSnapshotBridge.handlePublishRevealed`'s own
/// `unlockAtMillis`), so these tests never manufacture precision the real
/// app never produces.
final class EastWidgetSnapshotStoreTests: XCTestCase {
    private static let suiteName = "east-widget-snapshot-store-tests"

    private var defaults: UserDefaults!

    /// A fixed, whole-second reference instant -- see the class doc comment
    /// for why this is never `Date()`.
    private let referenceNow = Date(timeIntervalSince1970: 1_755_337_200)

    override func setUp() {
        super.setUp()
        let handle = UserDefaults(suiteName: Self.suiteName)!
        handle.removePersistentDomain(forName: Self.suiteName)
        defaults = handle
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: Self.suiteName)
        defaults = nil
        super.tearDown()
    }

    private func freshHandle() -> UserDefaults {
        // A brand-new `UserDefaults` instance onto the exact same suite --
        // stands in for "a different process/extension re-reading the same
        // durable App Group container", never sharing any in-memory state
        // with `defaults` above.
        UserDefaults(suiteName: Self.suiteName)!
    }

    /// Only the keys this suite's own persistent domain actually holds --
    /// unlike `UserDefaults.dictionaryRepresentation()` (which merges in the
    /// entire search list, including `NSGlobalDomain`'s many unrelated
    /// system keys such as `AppleLanguages`/`METAL_*`/etc., even for a
    /// suite-specific instance), this reflects only what this store itself
    /// ever wrote.
    private func persistedKeys() -> Set<String> {
        Set((UserDefaults().persistentDomain(forName: Self.suiteName) ?? [:]).keys)
    }

    // MARK: - A/B/C/D/E/F/G: lifecycle regression matrix

    // A. no valid reveal -> silence.
    func testNoSnapshotResolvesToSilence() {
        XCTAssertEqual(
            EastWidgetSnapshotStore.resolvedState(now: referenceNow, defaults: defaults),
            .silence
        )
    }

    // B. genuine app reveal committed -> exact revealed wisdom snapshot,
    // reload requested exactly once.
    func testGenuineRevealPublishesExactWisdomAndRequestsReloadOnce() {
        let unlockAt = referenceNow.addingTimeInterval(3600)
        let changed = EastWidgetSnapshotStore.publishRevealed(
            text: "Be water.",
            unlockAt: unlockAt,
            defaults: defaults
        )
        XCTAssertTrue(changed, "a genuine silence -> revealed transition must request a reload")

        let resolved = EastWidgetSnapshotStore.resolvedState(now: referenceNow, defaults: defaults)
        XCTAssertEqual(resolved, .revealed(text: "Be water.", unlockAt: unlockAt))
    }

    // C. same app state reconciled repeatedly -> no duplicate reload spam.
    func testRepeatedIdenticalReconciliationNeverSpamsReload() {
        let unlockAt = referenceNow.addingTimeInterval(3600)
        XCTAssertTrue(
            EastWidgetSnapshotStore.publishRevealed(text: "Be water.", unlockAt: unlockAt, defaults: defaults)
        )
        for _ in 0..<5 {
            XCTAssertFalse(
                EastWidgetSnapshotStore.publishRevealed(text: "Be water.", unlockAt: unlockAt, defaults: defaults),
                "an unchanged republish must never report a change"
            )
        }
    }

    // D. app/widget process recreated -> same valid revealed wisdom
    // resolves correctly from shared state.
    func testProcessRecreationPreservesValidRevealedState() {
        let unlockAt = referenceNow.addingTimeInterval(3600)
        EastWidgetSnapshotStore.publishRevealed(text: "Be water.", unlockAt: unlockAt, defaults: defaults)

        let recreated = freshHandle()
        XCTAssertEqual(
            EastWidgetSnapshotStore.resolvedState(now: referenceNow, defaults: recreated),
            .revealed(text: "Be water.", unlockAt: unlockAt)
        )
    }

    // E. unlockAt passes -> resolved widget state is silence even if no
    // timely WidgetKit refresh occurred (pure native resolution, no app
    // launch involved at all).
    func testExpiredUnlockAtResolvesToSilenceWithoutAppLaunch() {
        let unlockAt = referenceNow.addingTimeInterval(-5) // already in the past
        EastWidgetSnapshotStore.publishRevealed(text: "Be water.", unlockAt: unlockAt, defaults: defaults)

        let resolved = EastWidgetSnapshotStore.resolvedState(now: referenceNow, defaults: defaults)
        XCTAssertEqual(resolved, .silence)
    }

    // F. app later reconciles expired state -> stale shared revealed
    // snapshot is cleaned/replaced without changing daily access (daily
    // access itself lives entirely in Flutter/Dart and is structurally
    // unreachable from this store -- the proof here is that reconciling to
    // silence behaves exactly like any other genuine state change).
    func testAppReconciliationOfExpiredStateRequestsReloadAndClearsText() {
        let unlockAt = referenceNow.addingTimeInterval(-5)
        EastWidgetSnapshotStore.publishRevealed(text: "Be water.", unlockAt: unlockAt, defaults: defaults)

        // The app's own resume-time reconciliation republishes silence once
        // it observes (via `DailyWisdomAccessService.status()`) that
        // nothing is currently locked -- modeled here directly.
        let changed = EastWidgetSnapshotStore.publishSilence(defaults: defaults)
        XCTAssertTrue(changed, "reconciling an expired revealed snapshot to silence is a real change")
        XCTAssertNil(defaults.object(forKey: "east_widget_text_v1"))
        XCTAssertNil(defaults.object(forKey: "east_widget_unlock_at_v1"))
    }

    // G. new future ritual later completes -> new exact wisdom appears
    // normally.
    func testNextRealRevealPublishesNewExactWisdomAfterSilence() {
        let firstUnlockAt = referenceNow.addingTimeInterval(-5)
        EastWidgetSnapshotStore.publishRevealed(text: "First wisdom.", unlockAt: firstUnlockAt, defaults: defaults)
        EastWidgetSnapshotStore.publishSilence(defaults: defaults)

        let secondUnlockAt = referenceNow.addingTimeInterval(3600)
        let changed = EastWidgetSnapshotStore.publishRevealed(
            text: "Second wisdom.",
            unlockAt: secondUnlockAt,
            defaults: defaults
        )
        XCTAssertTrue(changed)

        XCTAssertEqual(
            EastWidgetSnapshotStore.resolvedState(now: referenceNow, defaults: defaults),
            .revealed(text: "Second wisdom.", unlockAt: secondUnlockAt)
        )
    }

    // MARK: - Reload de-duplication (section 4)

    func testValidSilenceSnapshotResolvesToExactSilenceCopy() {
        EastWidgetSnapshotStore.publishSilence(defaults: defaults)
        XCTAssertEqual(
            EastWidgetSnapshotStore.resolvedState(now: referenceNow, defaults: defaults),
            .silence
        )
    }

    func testPublishingSilenceWhenAlreadySilenceNeverReportsChange() {
        // Fresh defaults are already implicitly silence.
        XCTAssertFalse(EastWidgetSnapshotStore.publishSilence(defaults: defaults))

        EastWidgetSnapshotStore.publishSilence(defaults: defaults)
        XCTAssertFalse(
            EastWidgetSnapshotStore.publishSilence(defaults: defaults),
            "repeated silence reconciliation must never spam a reload"
        )
    }

    func testRevealedToSilenceReconciliationTriggersReloadOnlyWhenStateActuallyChanges() {
        let unlockAt = referenceNow.addingTimeInterval(3600)
        EastWidgetSnapshotStore.publishRevealed(text: "Be water.", unlockAt: unlockAt, defaults: defaults)

        XCTAssertTrue(EastWidgetSnapshotStore.publishSilence(defaults: defaults))
        XCTAssertFalse(
            EastWidgetSnapshotStore.publishSilence(defaults: defaults),
            "already-silence must not report a further change"
        )
    }

    // MARK: - Malformed snapshot matrix (section 9)

    func testMissingAppGroupStorageFailsSafelyOnRead() {
        XCTAssertEqual(
            EastWidgetSnapshotStore.resolvedState(now: referenceNow, defaults: nil),
            .silence
        )
    }

    func testMissingAppGroupStorageFailsSafelyOnWrite() {
        XCTAssertFalse(
            EastWidgetSnapshotStore.publishRevealed(
                text: "Be water.",
                unlockAt: referenceNow.addingTimeInterval(3600),
                defaults: nil
            )
        )
        XCTAssertFalse(EastWidgetSnapshotStore.publishSilence(defaults: nil))
    }

    func testEmptyWisdomFailsClosedAndIsNeverPersistedAsRevealed() {
        let changed = EastWidgetSnapshotStore.publishRevealed(
            text: "",
            unlockAt: referenceNow.addingTimeInterval(3600),
            defaults: defaults
        )
        // Fresh defaults were already silence, so an invalid write that
        // falls back to silence reports no change.
        XCTAssertFalse(changed)
        XCTAssertEqual(
            EastWidgetSnapshotStore.resolvedState(now: referenceNow, defaults: defaults),
            .silence
        )
    }

    func testWhitespaceOnlyWisdomFailsClosed() {
        EastWidgetSnapshotStore.publishRevealed(
            text: "   \n\t  ",
            unlockAt: referenceNow.addingTimeInterval(3600),
            defaults: defaults
        )
        XCTAssertEqual(
            EastWidgetSnapshotStore.resolvedState(now: referenceNow, defaults: defaults),
            .silence
        )
    }

    func testMissingWisdomTextFailsClosed() {
        // Directly simulate a partially-written snapshot: state says
        // "revealed" and unlockAt is present, but the text key was never
        // written (e.g. a crash between writes, or a future format this
        // binary does not understand).
        defaults.set("revealed", forKey: "east_widget_state_v1")
        defaults.set(
            referenceNow.addingTimeInterval(3600).timeIntervalSince1970,
            forKey: "east_widget_unlock_at_v1"
        )
        defaults.set(1, forKey: "east_widget_schema_version_v1")

        XCTAssertEqual(
            EastWidgetSnapshotStore.resolvedState(now: referenceNow, defaults: defaults),
            .silence
        )
    }

    func testMissingUnlockAtFailsClosed() {
        defaults.set("revealed", forKey: "east_widget_state_v1")
        defaults.set("Be water.", forKey: "east_widget_text_v1")
        defaults.set(1, forKey: "east_widget_schema_version_v1")
        // east_widget_unlock_at_v1 intentionally never written.

        XCTAssertEqual(
            EastWidgetSnapshotStore.resolvedState(now: referenceNow, defaults: defaults),
            .silence
        )
    }

    func testInvalidUnlockAtRepresentationFailsClosed() {
        defaults.set("revealed", forKey: "east_widget_state_v1")
        defaults.set("Be water.", forKey: "east_widget_text_v1")
        defaults.set("not-a-date", forKey: "east_widget_unlock_at_v1")
        defaults.set(1, forKey: "east_widget_schema_version_v1")

        // `UserDefaults.double(forKey:)` safely coerces a non-numeric
        // stored value to 0 (1970 epoch) rather than throwing -- always in
        // the past, so this already resolves to silence.
        XCTAssertEqual(
            EastWidgetSnapshotStore.resolvedState(now: referenceNow, defaults: defaults),
            .silence
        )
    }

    func testNonFiniteUnlockAtNeverPersistsAsRevealed() {
        let changed = EastWidgetSnapshotStore.publishRevealed(
            text: "Be water.",
            unlockAt: Date(timeIntervalSince1970: .nan),
            defaults: defaults
        )
        XCTAssertFalse(changed)
        XCTAssertEqual(
            EastWidgetSnapshotStore.resolvedState(now: referenceNow, defaults: defaults),
            .silence
        )
    }

    func testExpiredUnlockAtFailsClosed() {
        EastWidgetSnapshotStore.publishRevealed(
            text: "Be water.",
            unlockAt: referenceNow.addingTimeInterval(-1),
            defaults: defaults
        )
        XCTAssertEqual(
            EastWidgetSnapshotStore.resolvedState(now: referenceNow, defaults: defaults),
            .silence
        )
    }

    func testUnknownStateValueFailsClosed() {
        defaults.set("some-future-state", forKey: "east_widget_state_v1")
        defaults.set("Be water.", forKey: "east_widget_text_v1")
        defaults.set(
            referenceNow.addingTimeInterval(3600).timeIntervalSince1970,
            forKey: "east_widget_unlock_at_v1"
        )

        XCTAssertEqual(
            EastWidgetSnapshotStore.resolvedState(now: referenceNow, defaults: defaults),
            .silence
        )
    }

    func testUnknownSchemaVersionFailsClosedEvenWithOtherwiseValidFields() {
        let unlockAt = referenceNow.addingTimeInterval(3600)
        EastWidgetSnapshotStore.publishRevealed(text: "Be water.", unlockAt: unlockAt, defaults: defaults)
        // Simulate a future binary's format this version cannot interpret.
        defaults.set(999, forKey: "east_widget_schema_version_v1")

        XCTAssertEqual(
            EastWidgetSnapshotStore.resolvedState(now: referenceNow, defaults: defaults),
            .silence
        )
    }

    func testMissingSchemaVersionIsTreatedAsCompatible() {
        // Exactly the Phase 11 (pre-hardening) on-disk shape: no version
        // key at all. Must keep resolving correctly across the upgrade.
        let unlockAt = referenceNow.addingTimeInterval(3600)
        defaults.set("revealed", forKey: "east_widget_state_v1")
        defaults.set("Be water.", forKey: "east_widget_text_v1")
        defaults.set(unlockAt.timeIntervalSince1970, forKey: "east_widget_unlock_at_v1")

        XCTAssertEqual(
            EastWidgetSnapshotStore.resolvedState(now: referenceNow, defaults: defaults),
            .revealed(text: "Be water.", unlockAt: unlockAt)
        )
    }

    func testMalformedWrongTypedValuesNeverCrash() {
        // Every key holds a value of a type it was never meant to hold.
        defaults.set(12345, forKey: "east_widget_state_v1")
        defaults.set(Data([0x00, 0x01]), forKey: "east_widget_text_v1")
        defaults.set(["not", "a", "date"], forKey: "east_widget_unlock_at_v1")
        defaults.set("also-not-an-int", forKey: "east_widget_schema_version_v1")

        // The only assertion that matters here is that this line is
        // reached at all -- resolving must never throw or crash.
        let resolved = EastWidgetSnapshotStore.resolvedState(now: referenceNow, defaults: defaults)
        XCTAssertEqual(resolved, .silence)
    }

    func testFutureUnlockAtWithValidWisdomResolvesRevealed() {
        let unlockAt = referenceNow.addingTimeInterval(86_400)
        EastWidgetSnapshotStore.publishRevealed(text: "Be water.", unlockAt: unlockAt, defaults: defaults)

        XCTAssertEqual(
            EastWidgetSnapshotStore.resolvedState(now: referenceNow, defaults: defaults),
            .revealed(text: "Be water.", unlockAt: unlockAt)
        )
    }

    func testRepeatedIdenticalWriteOnlyReportsChangeOnce() {
        let unlockAt = referenceNow.addingTimeInterval(3600)
        XCTAssertTrue(
            EastWidgetSnapshotStore.publishRevealed(text: "Be water.", unlockAt: unlockAt, defaults: defaults)
        )
        XCTAssertFalse(
            EastWidgetSnapshotStore.publishRevealed(text: "Be water.", unlockAt: unlockAt, defaults: defaults)
        )
        XCTAssertFalse(
            EastWidgetSnapshotStore.publishRevealed(text: "Be water.", unlockAt: unlockAt, defaults: defaults)
        )
    }

    // MARK: - Privacy boundary (section 6)

    func testOnlyTheMinimalExpectedKeysEverExistInSharedStorage() {
        EastWidgetSnapshotStore.publishRevealed(
            text: "Be water.",
            unlockAt: referenceNow.addingTimeInterval(3600),
            defaults: defaults
        )

        let allowedKeys: Set<String> = [
            "east_widget_state_v1",
            "east_widget_text_v1",
            "east_widget_unlock_at_v1",
            "east_widget_schema_version_v1",
        ]
        let actualKeys = persistedKeys()
        XCTAssertTrue(
            actualKeys.isSubset(of: allowedKeys),
            "unexpected keys found in shared widget storage: \(actualKeys.subtracting(allowedKeys))"
        )

        EastWidgetSnapshotStore.publishSilence(defaults: defaults)
        let afterSilenceKeys = persistedKeys()
        XCTAssertTrue(afterSilenceKeys.isSubset(of: allowedKeys))
        // Revealed content is fully cleared, never left behind once silent.
        XCTAssertFalse(afterSilenceKeys.contains("east_widget_text_v1"))
        XCTAssertFalse(afterSilenceKeys.contains("east_widget_unlock_at_v1"))
    }

    // MARK: - Presentation (EAST. 1.2 Slice 1)
    //
    // Every test below uses the same fully isolated `UserDefaults` suite as
    // the rest of this file (see the class doc comment). Presentation is
    // deliberately exercised independently from content wherever possible,
    // mirroring `EastWidgetSnapshotStore`'s own separation.

    // 1. An old Build-34-era revealed snapshot -- only the original four
    // keys, no presentation keys at all -- must resolve its valid content
    // exactly as before, with presentation falling back to System/no
    // override.
    func testOldFourKeyRevealedSnapshotResolvesWithSystemPresentationFallback() {
        let unlockAt = referenceNow.addingTimeInterval(3600)
        defaults.set("revealed", forKey: "east_widget_state_v1")
        defaults.set("Be water.", forKey: "east_widget_text_v1")
        defaults.set(unlockAt.timeIntervalSince1970, forKey: "east_widget_unlock_at_v1")
        defaults.set(1, forKey: "east_widget_schema_version_v1")
        // No presentation keys written at all -- exactly a Build-34 snapshot.

        let snapshot = EastWidgetSnapshotStore.resolvedSnapshot(now: referenceNow, defaults: defaults)
        XCTAssertEqual(snapshot.content, .revealed(text: "Be water.", unlockAt: unlockAt))
        XCTAssertEqual(snapshot.presentation, .systemDefault)
    }

    // 2. An old silence snapshot resolves with default presentation too.
    func testOldSilenceSnapshotResolvesWithSystemPresentationFallback() {
        EastWidgetSnapshotStore.publishSilence(defaults: defaults) // legacy overload only

        let snapshot = EastWidgetSnapshotStore.resolvedSnapshot(now: referenceNow, defaults: defaults)
        XCTAssertEqual(snapshot.content, .silence)
        XCTAssertEqual(snapshot.presentation, .systemDefault)
    }

    // 3. Explicit Light, Dark, and System presentation round-trip correctly.
    func testExplicitAppearanceModesRoundTripCorrectly() {
        let modes: [EastWidgetAppearanceMode] = [.light, .dark, .system]
        for mode in modes {
            EastWidgetSnapshotStore.publishSilence(
                presentation: EastWidgetPresentation(appearanceMode: mode, localeOverrideTag: nil),
                defaults: defaults
            )
            let resolved = EastWidgetSnapshotStore.resolvedSnapshot(now: referenceNow, defaults: defaults)
            XCTAssertEqual(resolved.presentation.appearanceMode, mode)
        }
    }

    // 4. All 15 canonical explicit locale override tags round-trip exactly.
    func testAllFifteenCanonicalLocaleOverrideTagsRoundTripCorrectly() {
        let canonicalTags = [
            "en", "tr", "ja", "de", "fr", "ko", "zh-Hant", "ar", "es",
            "pt-BR", "it", "th", "nl", "pl", "vi",
        ]
        for tag in canonicalTags {
            EastWidgetSnapshotStore.publishSilence(
                presentation: EastWidgetPresentation(appearanceMode: .system, localeOverrideTag: tag),
                defaults: defaults
            )
            let resolved = EastWidgetSnapshotStore.resolvedSnapshot(now: referenceNow, defaults: defaults)
            XCTAssertEqual(
                resolved.presentation.localeOverrideTag, tag,
                "canonical tag \(tag) must round-trip exactly"
            )
        }
    }

    // 5. Bare `pt`, bare `zh`, malformed, wrong-case, and unsupported tags
    // all resolve to `nil` (System Default), never crashing and never
    // accepted as an explicit override.
    func testInvalidLocaleOverrideTagsAllFallBackToNil() {
        let invalidTags = [
            "pt", "zh", // bare technical fallback tags, never a valid override
            "PT-BR", "TR", "zh-hant", // wrong casing
            "fr-FR", "xx", // unsupported/unknown
            "", // malformed/empty
        ]
        for tag in invalidTags {
            defaults.removePersistentDomain(forName: Self.suiteName)
            EastWidgetSnapshotStore.publishSilence(
                presentation: EastWidgetPresentation(appearanceMode: .system, localeOverrideTag: tag),
                defaults: defaults
            )
            let resolved = EastWidgetSnapshotStore.resolvedSnapshot(now: referenceNow, defaults: defaults)
            XCTAssertNil(
                resolved.presentation.localeOverrideTag,
                "invalid tag '\(tag)' must fall back to nil"
            )
        }
    }

    // 6. A malformed/unknown appearance value resolves to `.system`.
    func testMalformedAppearanceValueResolvesToSystem() {
        defaults.set("not-a-real-mode", forKey: "east_widget_presentation_appearance_v1")
        let resolved = EastWidgetSnapshotStore.resolvedSnapshot(now: referenceNow, defaults: defaults)
        XCTAssertEqual(resolved.presentation.appearanceMode, .system)
    }

    // 7. Malformed presentation data must never hide, invalidate, or alter
    // otherwise-valid revealed content.
    func testMalformedPresentationNeverHidesValidRevealedContent() {
        let unlockAt = referenceNow.addingTimeInterval(3600)
        EastWidgetSnapshotStore.publishRevealed(text: "Be water.", unlockAt: unlockAt, defaults: defaults)
        // Corrupt presentation directly, independent of the content write above.
        defaults.set("not-a-real-mode", forKey: "east_widget_presentation_appearance_v1")
        defaults.set("also-not-a-real-tag", forKey: "east_widget_presentation_locale_override_v1")

        let resolved = EastWidgetSnapshotStore.resolvedSnapshot(now: referenceNow, defaults: defaults)
        XCTAssertEqual(resolved.content, .revealed(text: "Be water.", unlockAt: unlockAt))
        XCTAssertEqual(resolved.presentation, .systemDefault)
    }

    // 8. A presentation-only appearance change (content unchanged) still
    // reports a change.
    func testPresentationOnlyAppearanceChangeReportsChangeTrue() {
        let unlockAt = referenceNow.addingTimeInterval(3600)
        EastWidgetSnapshotStore.publishRevealed(
            text: "Be water.",
            unlockAt: unlockAt,
            presentation: EastWidgetPresentation(appearanceMode: .light, localeOverrideTag: nil),
            defaults: defaults
        )
        let changed = EastWidgetSnapshotStore.publishRevealed(
            text: "Be water.",
            unlockAt: unlockAt,
            presentation: EastWidgetPresentation(appearanceMode: .dark, localeOverrideTag: nil),
            defaults: defaults
        )
        XCTAssertTrue(changed, "an appearance-only change, with content unchanged, must still report a change")
    }

    // 9. A presentation-only locale change (content unchanged) still reports
    // a change.
    func testPresentationOnlyLocaleChangeReportsChangeTrue() {
        let unlockAt = referenceNow.addingTimeInterval(3600)
        EastWidgetSnapshotStore.publishRevealed(
            text: "Be water.",
            unlockAt: unlockAt,
            presentation: EastWidgetPresentation(appearanceMode: .system, localeOverrideTag: "en"),
            defaults: defaults
        )
        let changed = EastWidgetSnapshotStore.publishRevealed(
            text: "Be water.",
            unlockAt: unlockAt,
            presentation: EastWidgetPresentation(appearanceMode: .system, localeOverrideTag: "tr"),
            defaults: defaults
        )
        XCTAssertTrue(changed, "a locale-only change, with content unchanged, must still report a change")
    }

    // 10. A fully identical content-and-presentation write reports no
    // change.
    func testFullyIdenticalContentAndPresentationWriteReportsChangeFalse() {
        let unlockAt = referenceNow.addingTimeInterval(3600)
        let presentation = EastWidgetPresentation(appearanceMode: .dark, localeOverrideTag: "ja")
        EastWidgetSnapshotStore.publishRevealed(
            text: "Be water.", unlockAt: unlockAt, presentation: presentation, defaults: defaults
        )
        let changed = EastWidgetSnapshotStore.publishRevealed(
            text: "Be water.", unlockAt: unlockAt, presentation: presentation, defaults: defaults
        )
        XCTAssertFalse(changed, "identical content and presentation must never report a change")
    }

    // 11. Switching from an explicit locale override back to System removes
    // the locale override key entirely and reports a change.
    func testSwitchingFromExplicitLocaleOverrideToSystemRemovesKeyAndReportsChange() {
        EastWidgetSnapshotStore.publishSilence(
            presentation: EastWidgetPresentation(appearanceMode: .system, localeOverrideTag: "de"),
            defaults: defaults
        )
        XCTAssertEqual(defaults.string(forKey: "east_widget_presentation_locale_override_v1"), "de")

        let changed = EastWidgetSnapshotStore.publishSilence(
            presentation: EastWidgetPresentation(appearanceMode: .system, localeOverrideTag: nil),
            defaults: defaults
        )
        XCTAssertTrue(changed, "returning to System Default is itself a real presentation change")
        XCTAssertNil(defaults.object(forKey: "east_widget_presentation_locale_override_v1"))
    }

    // 12. A repeated identical System Default presentation write reports no
    // change.
    func testRepeatedSystemPresentationWriteReportsChangeFalse() {
        let presentation = EastWidgetPresentation.systemDefault
        EastWidgetSnapshotStore.publishSilence(presentation: presentation, defaults: defaults)
        let changed = EastWidgetSnapshotStore.publishSilence(presentation: presentation, defaults: defaults)
        XCTAssertFalse(changed, "an unchanged repeated System Default write must never report a change")
    }

    // 13. The existing legacy overloads (no `presentation:` argument) must
    // still produce only the original four-key set -- never a presentation
    // key -- so the old bridge remains behaviorally unchanged until a later
    // slice wires it up.
    func testLegacyOverloadsStillProduceOnlyOriginalKeySet() {
        EastWidgetSnapshotStore.publishRevealed(
            text: "Be water.",
            unlockAt: referenceNow.addingTimeInterval(3600),
            defaults: defaults
        )
        let originalKeys: Set<String> = [
            "east_widget_state_v1",
            "east_widget_text_v1",
            "east_widget_unlock_at_v1",
            "east_widget_schema_version_v1",
        ]
        XCTAssertEqual(
            persistedKeys(), originalKeys,
            "the legacy publishRevealed(text:unlockAt:defaults:) overload must never create presentation keys"
        )

        EastWidgetSnapshotStore.publishSilence(defaults: defaults)
        XCTAssertTrue(
            persistedKeys().isSubset(of: originalKeys),
            "the legacy publishSilence(defaults:) overload must never create presentation keys"
        )
    }

    // 14. A presentation-aware write produces exactly the original content
    // keys plus the two new presentation keys -- no extra state.
    func testPresentationAwareOverloadsProduceExactlyContentPlusPresentationKeys() {
        EastWidgetSnapshotStore.publishRevealed(
            text: "Be water.",
            unlockAt: referenceNow.addingTimeInterval(3600),
            presentation: EastWidgetPresentation(appearanceMode: .dark, localeOverrideTag: "vi"),
            defaults: defaults
        )
        let expectedKeys: Set<String> = [
            "east_widget_state_v1",
            "east_widget_text_v1",
            "east_widget_unlock_at_v1",
            "east_widget_schema_version_v1",
            "east_widget_presentation_appearance_v1",
            "east_widget_presentation_locale_override_v1",
        ]
        XCTAssertEqual(
            persistedKeys(), expectedKeys,
            "a presentation-aware revealed write must produce exactly the content keys plus the two presentation keys"
        )
    }

    // 15. Expired content still resolves to silence while presentation is
    // still independently resolved (never coupled to content validity).
    func testExpiredContentResolvesToSilenceWithPresentationStillIndependentlyResolved() {
        let expiredUnlockAt = referenceNow.addingTimeInterval(-5)
        EastWidgetSnapshotStore.publishRevealed(
            text: "Be water.",
            unlockAt: expiredUnlockAt,
            presentation: EastWidgetPresentation(appearanceMode: .light, localeOverrideTag: "th"),
            defaults: defaults
        )
        let resolved = EastWidgetSnapshotStore.resolvedSnapshot(now: referenceNow, defaults: defaults)
        XCTAssertEqual(resolved.content, .silence)
        XCTAssertEqual(
            resolved.presentation,
            EastWidgetPresentation(appearanceMode: .light, localeOverrideTag: "th")
        )
    }

    // MARK: - Presentation write-time normalization (Slice 1 correction)
    //
    // `writePresentation` must never trust `localeOverrideTag` verbatim: an
    // invalid value must be normalized to `nil` *before* it is compared or
    // persisted, exactly mirroring the read-time `parseLocaleOverrideTag`
    // fallback these tests already exercise above.

    // An invalid presentation-aware locale write must never persist the
    // invalid raw value to the App Group at all.
    func testInvalidLocaleOverrideWriteNeverPersistsTheInvalidRawValue() {
        EastWidgetSnapshotStore.publishSilence(
            presentation: EastWidgetPresentation(appearanceMode: .system, localeOverrideTag: "xx"),
            defaults: defaults
        )
        XCTAssertNil(
            defaults.string(forKey: "east_widget_presentation_locale_override_v1"),
            "an invalid locale override must never be persisted verbatim"
        )
    }

    // Writing an invalid override must remove a previously valid
    // locale-override key -- never leave stale valid data sitting alongside
    // a rejected new value.
    func testInvalidLocaleOverrideWriteRemovesPreviouslyValidKey() {
        EastWidgetSnapshotStore.publishSilence(
            presentation: EastWidgetPresentation(appearanceMode: .system, localeOverrideTag: "de"),
            defaults: defaults
        )
        XCTAssertEqual(defaults.string(forKey: "east_widget_presentation_locale_override_v1"), "de")

        EastWidgetSnapshotStore.publishSilence(
            presentation: EastWidgetPresentation(appearanceMode: .system, localeOverrideTag: "xx"),
            defaults: defaults
        )
        XCTAssertNil(
            defaults.string(forKey: "east_widget_presentation_locale_override_v1"),
            "writing an invalid override must remove the previously valid key, never leave it in place"
        )
    }

    // Once an invalid override has been normalized to System on write,
    // repeating the exact same invalid write again -- with content also
    // unchanged -- must report no change, since both sides of the
    // comparison are normalized before comparing.
    func testRepeatingSameInvalidLocaleOverrideAfterNormalizationReportsChangeFalse() {
        let invalidPresentation = EastWidgetPresentation(appearanceMode: .system, localeOverrideTag: "xx")
        // First write: establishes normalized System/no-override state. May
        // itself report a change, since no presentation key existed before.
        EastWidgetSnapshotStore.publishSilence(presentation: invalidPresentation, defaults: defaults)

        let changed = EastWidgetSnapshotStore.publishSilence(presentation: invalidPresentation, defaults: defaults)
        XCTAssertFalse(
            changed,
            "repeating the same invalid override, already normalized to System, must report no change " +
                "once content is also unchanged"
        )
    }

    // `resolvedSnapshot` with no App Group at all must fail closed to
    // exactly `.silence` content and `.systemDefault` presentation.
    func testResolvedSnapshotWithNilDefaultsReturnsSilenceAndSystemDefault() {
        let snapshot = EastWidgetSnapshotStore.resolvedSnapshot(now: referenceNow, defaults: nil)
        XCTAssertEqual(snapshot.content, .silence)
        XCTAssertEqual(snapshot.presentation, .systemDefault)
    }

    // Both presentation-aware publish methods must report `false` -- never
    // throw or crash -- when `defaults` is `nil` (App Group unavailable).
    func testPresentationAwarePublishMethodsReturnFalseWhenDefaultsIsNil() {
        let presentation = EastWidgetPresentation(appearanceMode: .dark, localeOverrideTag: "ja")

        let revealedChanged = EastWidgetSnapshotStore.publishRevealed(
            text: "Be water.",
            unlockAt: referenceNow.addingTimeInterval(3600),
            presentation: presentation,
            defaults: nil
        )
        XCTAssertFalse(revealedChanged)

        let silenceChanged = EastWidgetSnapshotStore.publishSilence(presentation: presentation, defaults: nil)
        XCTAssertFalse(silenceChanged)
    }
}

/// EAST. 1.2 Slice 2A -- the native Flutter bridge's own pure decoding and
/// presentation-payload-detection helpers. Neither `EastWidgetSnapshotBridge
/// .presentation(from:)` nor `.containsPresentationPayload(_:)` touches
/// `FlutterMethodCall`, `WidgetCenter`, or the production App Group -- both
/// take a plain `Any?` (exactly what `FlutterMethodCall.arguments` is typed
/// as) so they can be exercised directly here without constructing a real
/// method call or reloading any real widget timeline.
final class EastWidgetSnapshotBridgeTests: XCTestCase {
    // MARK: - Presentation decoding

    // 1. `presentation(from: nil)` returns `.systemDefault`.
    func testPresentationFromNilArgumentsReturnsSystemDefault() {
        XCTAssertEqual(EastWidgetSnapshotBridge.presentation(from: nil), .systemDefault)
    }

    // 2. A non-map argument returns `.systemDefault`.
    func testPresentationFromNonMapArgumentReturnsSystemDefault() {
        XCTAssertEqual(EastWidgetSnapshotBridge.presentation(from: "not a map"), .systemDefault)
        XCTAssertEqual(EastWidgetSnapshotBridge.presentation(from: NSNumber(value: 42)), .systemDefault)
    }

    // 3. An empty/legacy map (only the existing content keys, or no keys at
    // all) returns `.systemDefault`.
    func testPresentationFromLegacyOrEmptyMapReturnsSystemDefault() {
        let legacyRevealedArguments: [String: Any] = [
            "text": "Be water.",
            "unlockAtMillis": 1_755_340_800_000,
        ]
        XCTAssertEqual(EastWidgetSnapshotBridge.presentation(from: legacyRevealedArguments), .systemDefault)
        XCTAssertEqual(EastWidgetSnapshotBridge.presentation(from: [String: Any]()), .systemDefault)
    }

    // 4. `light`, `dark`, and `system` decode correctly.
    func testPresentationDecodesEachExplicitAppearanceModeCorrectly() {
        let cases: [(raw: String, expected: EastWidgetAppearanceMode)] = [
            ("light", .light),
            ("dark", .dark),
            ("system", .system),
        ]
        for testCase in cases {
            let resolved = EastWidgetSnapshotBridge.presentation(from: ["appearanceMode": testCase.raw])
            XCTAssertEqual(resolved.appearanceMode, testCase.expected)
        }
    }

    // 5. All 15 canonical locale tags decode correctly through the bridge
    // helper.
    func testPresentationDecodesAllFifteenCanonicalLocaleTagsCorrectly() {
        let canonicalTags = [
            "en", "tr", "ja", "de", "fr", "ko", "zh-Hant", "ar", "es",
            "pt-BR", "it", "th", "nl", "pl", "vi",
        ]
        for tag in canonicalTags {
            let resolved = EastWidgetSnapshotBridge.presentation(from: ["localeOverrideTag": tag])
            XCTAssertEqual(resolved.localeOverrideTag, tag, "tag \(tag) must decode exactly")
        }
    }

    // 6. Bare `pt`, bare `zh`, wrong-case, malformed, unknown, and
    // wrong-type locale values all become `nil`.
    func testPresentationRejectsInvalidLocaleValuesToNil() {
        let invalidStringValues = [
            "pt", "zh", // bare technical fallback tags, never a valid override
            "PT-BR", "zh-hant", // wrong casing
            "fr-FR", "xx", // unsupported/unknown
            "", // malformed/empty
        ]
        for tag in invalidStringValues {
            let resolved = EastWidgetSnapshotBridge.presentation(from: ["localeOverrideTag": tag])
            XCTAssertNil(resolved.localeOverrideTag, "invalid tag '\(tag)' must decode to nil")
        }

        // Wrong-type value -- not a String at all.
        let wrongTypeResolved = EastWidgetSnapshotBridge.presentation(from: ["localeOverrideTag": 42])
        XCTAssertNil(wrongTypeResolved.localeOverrideTag)
    }

    // 7. Wrong-type/malformed appearance becomes `.system`.
    func testPresentationRejectsInvalidAppearanceValuesToSystem() {
        let malformedResolved = EastWidgetSnapshotBridge.presentation(from: ["appearanceMode": "not-a-mode"])
        XCTAssertEqual(malformedResolved.appearanceMode, .system)

        let wrongTypeResolved = EastWidgetSnapshotBridge.presentation(from: ["appearanceMode": 42])
        XCTAssertEqual(wrongTypeResolved.appearanceMode, .system)
    }

    // 8. One invalid field does not discard the other, valid field -- the
    // two fields are validated entirely independently.
    func testOneInvalidFieldDoesNotDiscardTheOtherValidField() {
        let invalidLocaleValidAppearance = EastWidgetSnapshotBridge.presentation(
            from: ["appearanceMode": "dark", "localeOverrideTag": "xx"]
        )
        XCTAssertEqual(invalidLocaleValidAppearance.appearanceMode, .dark)
        XCTAssertNil(invalidLocaleValidAppearance.localeOverrideTag)

        let validLocaleInvalidAppearance = EastWidgetSnapshotBridge.presentation(
            from: ["appearanceMode": "not-a-mode", "localeOverrideTag": "ko"]
        )
        XCTAssertEqual(validLocaleInvalidAppearance.appearanceMode, .system)
        XCTAssertEqual(validLocaleInvalidAppearance.localeOverrideTag, "ko")
    }

    // MARK: - Presentation-payload detection (legacy vs. presentation-aware)

    // 9. Legacy revealed arguments (only the existing content keys) are
    // detected as having no presentation payload.
    func testLegacyRevealedArgumentsHaveNoPresentationPayload() {
        let legacyRevealedArguments: [String: Any] = [
            "text": "Be water.",
            "unlockAtMillis": 1_755_340_800_000,
        ]
        XCTAssertFalse(EastWidgetSnapshotBridge.containsPresentationPayload(legacyRevealedArguments))
    }

    // 10. Legacy null silence arguments are detected as having no
    // presentation payload -- exactly what every existing Dart binary sends
    // today.
    func testLegacyNullSilenceArgumentsHaveNoPresentationPayload() {
        XCTAssertFalse(EastWidgetSnapshotBridge.containsPresentationPayload(nil))
    }

    // 11. A map containing only `appearanceMode` is presentation-aware.
    func testMapWithOnlyAppearanceModeIsPresentationAware() {
        XCTAssertTrue(EastWidgetSnapshotBridge.containsPresentationPayload(["appearanceMode": "light"]))
    }

    // 12. A map containing only `localeOverrideTag` is presentation-aware.
    func testMapWithOnlyLocaleOverrideTagIsPresentationAware() {
        XCTAssertTrue(EastWidgetSnapshotBridge.containsPresentationPayload(["localeOverrideTag": "de"]))
    }

    // 13. A map containing an explicit null `localeOverrideTag` (a present
    // key whose value is Dart `null`, arriving here as `NSNull`) is still
    // presentation-aware -- key presence, not value validity -- and
    // resolves to System locale behavior (`nil`).
    func testMapWithExplicitNullLocaleOverrideTagIsPresentationAwareAndResolvesToSystem() {
        let arguments: [String: Any] = ["localeOverrideTag": NSNull()]
        XCTAssertTrue(
            EastWidgetSnapshotBridge.containsPresentationPayload(arguments),
            "an explicit null is still a present key, distinct from an absent one"
        )
        let resolved = EastWidgetSnapshotBridge.presentation(from: arguments)
        XCTAssertNil(resolved.localeOverrideTag, "an explicit null must resolve to System locale behavior")
    }

    // 14. Store validation and bridge decoding use the same canonical
    // result -- the bridge never duplicates the store's own validation.
    func testBridgeDecodingMatchesStoreValidationExactly() {
        let arguments: [String: Any] = ["appearanceMode": "dark", "localeOverrideTag": "zh-Hant"]
        let fromBridge = EastWidgetSnapshotBridge.presentation(from: arguments)
        let fromStore = EastWidgetSnapshotStore.validatedPresentation(
            appearanceModeRaw: "dark",
            localeOverrideTagRaw: "zh-Hant"
        )
        XCTAssertEqual(fromBridge, fromStore)
    }
}
