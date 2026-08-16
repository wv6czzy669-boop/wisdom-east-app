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
}
