import XCTest

@testable import Runner

final class EastKeeperRitualStoreTests: XCTestCase {
    private static let suiteName = "east-keeper-ritual-store-tests"

    private var defaults: UserDefaults!
    private var coordinationLockURL: URL!
    private let now = Date(timeIntervalSince1970: 1_777_777_000)

    override func setUp() {
        super.setUp()
        let handle = UserDefaults(suiteName: Self.suiteName)!
        handle.removePersistentDomain(forName: Self.suiteName)
        defaults = handle
        coordinationLockURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("east-keeper-ritual-\(UUID().uuidString).lock")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: Self.suiteName)
        defaults = nil
        try? FileManager.default.removeItem(at: coordinationLockURL)
        coordinationLockURL = nil
        super.tearDown()
    }

    func testMissingDocumentRequiresKeeperWithSystemPresentation() {
        XCTAssertEqual(
            EastKeeperRitualStore.resolvedSnapshot(now: now, defaults: defaults),
            EastKeeperRitualSnapshot(
                content: .keeperRequired,
                presentation: .systemDefault
            )
        )
    }

    func testKeeperWithoutCandidateWaits() {
        XCTAssertTrue(EastKeeperRitualStore.setKeeperEntitlement(true, defaults: defaults))
        XCTAssertEqual(
            EastKeeperRitualStore.resolvedSnapshot(now: now, defaults: defaults).content,
            .waiting(activationAt: nil)
        )
    }

    func testPreparedCandidateStartsAtPauseAndPreservesPresentation() {
        EastKeeperRitualStore.setKeeperEntitlement(true, defaults: defaults)
        let candidate = makeCandidate()
        let presentation = EastWidgetPresentation(
            appearanceMode: .dark,
            localeOverrideTag: "tr"
        )

        XCTAssertTrue(EastKeeperRitualStore.publishPrepared(
            candidate: candidate,
            presentation: presentation,
            now: now,
            defaults: defaults
        ))
        XCTAssertEqual(
            EastKeeperRitualStore.resolvedSnapshot(now: now, defaults: defaults),
            EastKeeperRitualSnapshot(content: .pause, presentation: presentation)
        )
    }

    func testThreeAdvancesRevealTheExactPreparedCandidate() {
        prepareKeeperCandidate()

        let feel = EastKeeperRitualStore.advance(now: now, defaults: defaults)
        XCTAssertEqual(feel.snapshot.content, .feel)
        XCTAssertNil(feel.newlyRevealed)

        let heart = EastKeeperRitualStore.advance(
            now: now.addingTimeInterval(1),
            defaults: defaults
        )
        XCTAssertEqual(heart.snapshot.content, .heart)
        XCTAssertNil(heart.newlyRevealed)

        let revealMoment = now.addingTimeInterval(2)
        let result = EastKeeperRitualStore.advance(
            now: revealMoment,
            defaults: defaults
        )
        guard let reveal = result.newlyRevealed else {
            return XCTFail("the third advance must reveal")
        }
        XCTAssertEqual(reveal.candidateId, "east_wisdom_0001:1777777000000")
        XCTAssertEqual(reveal.canonicalText, "Be still.")
        XCTAssertEqual(reveal.displayText, "Sakin ol.")
        XCTAssertEqual(reveal.wisdomId, "east_wisdom_0001")
        XCTAssertEqual(reveal.revealedAt, revealMoment)
        XCTAssertEqual(
            reveal.unlockAt,
            revealMoment.addingTimeInterval(EastKeeperRitualStore.lockDuration)
        )
        XCTAssertNil(reveal.revealId)
        XCTAssertTrue(reveal.needsAppCommit)
        XCTAssertEqual(result.snapshot.content, .revealed(reveal))
    }

    func testProvisionalRevealExpiresAtExactlyTwentyFourHours() {
        prepareKeeperCandidate()
        EastKeeperRitualStore.advance(now: now, defaults: defaults)
        EastKeeperRitualStore.advance(now: now, defaults: defaults)
        let result = EastKeeperRitualStore.advance(now: now, defaults: defaults)
        let beforeUnlock = now.addingTimeInterval(EastKeeperRitualStore.lockDuration - 0.001)
        XCTAssertEqual(
            EastKeeperRitualStore.resolvedSnapshot(now: beforeUnlock, defaults: defaults).content,
            result.snapshot.content
        )
        XCTAssertEqual(
            EastKeeperRitualStore.resolvedSnapshot(
                now: now.addingTimeInterval(EastKeeperRitualStore.lockDuration),
                defaults: defaults
            ).content,
            .waiting(activationAt: nil)
        )
    }

    func testAuthoritativePublishReplacesProvisionalReveal() {
        prepareKeeperCandidate()
        EastKeeperRitualStore.advance(now: now, defaults: defaults)
        EastKeeperRitualStore.advance(now: now, defaults: defaults)
        let provisional = EastKeeperRitualStore.advance(now: now, defaults: defaults)
            .newlyRevealed!
        let authoritative = EastKeeperRitualReveal(
            candidateId: provisional.candidateId,
            canonicalText: provisional.canonicalText,
            displayText: provisional.displayText,
            wisdomId: provisional.wisdomId,
            revealedAt: provisional.revealedAt,
            unlockAt: provisional.unlockAt,
            revealId: "11111111-2222-4333-8444-555555555555",
            needsAppCommit: false
        )

        XCTAssertTrue(EastKeeperRitualStore.publishActive(
            reveal: authoritative,
            presentation: .systemDefault,
            now: now,
            defaults: defaults
        ))
        XCTAssertEqual(
            EastKeeperRitualStore.resolvedSnapshot(now: now, defaults: defaults).content,
            .revealed(authoritative)
        )
        XCTAssertFalse(EastKeeperRitualStore.publishActive(
            reveal: authoritative,
            presentation: .systemDefault,
            now: now,
            defaults: defaults
        ))
    }

    func testFutureCandidateActivatesOnlyAfterActiveRevealExpires() {
        let active = makeReveal()
        EastKeeperRitualStore.publishActive(
            reveal: active,
            presentation: .systemDefault,
            now: now,
            defaults: defaults
        )
        let next = makeCandidate(
            wisdomId: "east_wisdom_0002",
            activationAt: active.unlockAt
        )
        XCTAssertTrue(EastKeeperRitualStore.publishPrepared(
            candidate: next,
            presentation: .systemDefault,
            now: now,
            defaults: defaults
        ))
        XCTAssertEqual(
            EastKeeperRitualStore.resolvedSnapshot(now: now, defaults: defaults).content,
            .revealed(active)
        )

        let promoted = EastKeeperRitualStore.advance(
            now: active.unlockAt,
            defaults: defaults
        )
        XCTAssertTrue(promoted.changed)
        XCTAssertEqual(promoted.snapshot.content, .feel)
    }

    func testInvalidCandidateNeverPersists() {
        EastKeeperRitualStore.setKeeperEntitlement(true, defaults: defaults)
        let invalid = EastKeeperRitualCandidate(
            candidateId: "contains spaces",
            canonicalText: "Be still.",
            displayText: "Be still.",
            wisdomId: "not-canonical",
            preparedAt: now,
            activationAt: now
        )
        XCTAssertFalse(EastKeeperRitualStore.publishPrepared(
            candidate: invalid,
            presentation: .systemDefault,
            now: now,
            defaults: defaults
        ))
        XCTAssertEqual(
            EastKeeperRitualStore.resolvedSnapshot(now: now, defaults: defaults).content,
            .waiting(activationAt: nil)
        )
    }

    func testIdenticalPreparedWriteIsIdempotent() {
        EastKeeperRitualStore.setKeeperEntitlement(true, defaults: defaults)
        let candidate = makeCandidate()
        XCTAssertTrue(EastKeeperRitualStore.publishPrepared(
            candidate: candidate,
            presentation: .systemDefault,
            now: now,
            defaults: defaults
        ))
        XCTAssertFalse(EastKeeperRitualStore.publishPrepared(
            candidate: candidate,
            presentation: .systemDefault,
            now: now,
            defaults: defaults
        ))
    }

    func testNonKeeperCannotAdvancePreparedCandidate() {
        EastKeeperRitualStore.publishPrepared(
            candidate: makeCandidate(),
            presentation: .systemDefault,
            now: now,
            defaults: defaults
        )
        let result = EastKeeperRitualStore.advance(now: now, defaults: defaults)
        XCTAssertFalse(result.changed)
        XCTAssertNil(result.newlyRevealed)
        XCTAssertEqual(result.snapshot.content, .keeperRequired)
    }

    func testBridgePayloadCarriesProvisionalRevealWithoutInventingRevealId() {
        prepareKeeperCandidate()
        EastKeeperRitualStore.advance(now: now, defaults: defaults)
        EastKeeperRitualStore.advance(now: now, defaults: defaults)
        EastKeeperRitualStore.advance(now: now, defaults: defaults)

        let payload = EastKeeperRitualStore.bridgePayload(now: now, defaults: defaults)
        XCTAssertEqual(payload["isKeeper"] as? Bool, true)
        XCTAssertEqual(payload["state"] as? String, "revealed")
        let reveal = payload["reveal"] as? [String: Any]
        XCTAssertEqual(reveal?["wisdomId"] as? String, "east_wisdom_0001")
        XCTAssertEqual(reveal?["needsAppCommit"] as? Bool, true)
        XCTAssertNil(reveal?["revealId"])
    }

    func testCoordinatedConcurrentAdvancesNeverLoseARitualPhase() {
        prepareKeeperCandidate(coordinationLockURL: coordinationLockURL)
        let results = LockedResults<EastKeeperRitualAdvanceResult>()
        let sharedLockURL = coordinationLockURL!
        let revealMoment = now

        DispatchQueue.concurrentPerform(iterations: 3) { _ in
            // Separate handles mirror the Runner and widget-extension
            // processes more closely than sharing one UserDefaults object.
            let processDefaults = UserDefaults(suiteName: Self.suiteName)!
            results.append(EastKeeperRitualStore.advance(
                now: revealMoment,
                defaults: processDefaults,
                coordinationLockURL: sharedLockURL
            ))
        }

        let captured = results.values
        XCTAssertEqual(captured.count, 3)
        XCTAssertEqual(captured.filter { $0.newlyRevealed != nil }.count, 1)
        XCTAssertTrue(captured.allSatisfy(\.changed))
        guard case .revealed = EastKeeperRitualStore.resolvedSnapshot(
            now: revealMoment,
            defaults: defaults,
            coordinationLockURL: coordinationLockURL
        ).content else {
            return XCTFail("three coordinated advances must complete the ritual exactly once")
        }
    }

    func testCoordinatedPresentationWriteCannotRollBackAnAdvance() {
        prepareKeeperCandidate(coordinationLockURL: coordinationLockURL)
        let sharedLockURL = coordinationLockURL!
        let candidate = makeCandidate()
        let presentation = EastWidgetPresentation(
            appearanceMode: .dark,
            localeOverrideTag: "tr"
        )

        DispatchQueue.concurrentPerform(iterations: 2) { index in
            if index == 0 {
                _ = EastKeeperRitualStore.advance(
                    now: now,
                    defaults: UserDefaults(suiteName: Self.suiteName),
                    coordinationLockURL: sharedLockURL
                )
            } else {
                _ = EastKeeperRitualStore.publishPrepared(
                    candidate: candidate,
                    presentation: presentation,
                    now: now,
                    defaults: UserDefaults(suiteName: Self.suiteName),
                    coordinationLockURL: sharedLockURL
                )
            }
        }

        XCTAssertEqual(
            EastKeeperRitualStore.resolvedSnapshot(
                now: now,
                defaults: defaults,
                coordinationLockURL: coordinationLockURL
            ),
            EastKeeperRitualSnapshot(content: .feel, presentation: presentation)
        )
    }

    private func prepareKeeperCandidate(coordinationLockURL: URL? = nil) {
        EastKeeperRitualStore.setKeeperEntitlement(
            true,
            defaults: defaults,
            coordinationLockURL: coordinationLockURL
        )
        EastKeeperRitualStore.publishPrepared(
            candidate: makeCandidate(),
            presentation: .systemDefault,
            now: now,
            defaults: defaults,
            coordinationLockURL: coordinationLockURL
        )
    }

    private func makeCandidate(
        wisdomId: String = "east_wisdom_0001",
        activationAt: Date? = nil
    ) -> EastKeeperRitualCandidate {
        let activation = activationAt ?? now
        return EastKeeperRitualCandidate(
            candidateId: "\(wisdomId):\(Int64(activation.timeIntervalSince1970 * 1000))",
            canonicalText: "Be still.",
            displayText: "Sakin ol.",
            wisdomId: wisdomId,
            preparedAt: now,
            activationAt: activation
        )
    }

    private func makeReveal() -> EastKeeperRitualReveal {
        EastKeeperRitualReveal(
            candidateId: "east_wisdom_0001:1777777000000",
            canonicalText: "Be still.",
            displayText: "Sakin ol.",
            wisdomId: "east_wisdom_0001",
            revealedAt: now,
            unlockAt: now.addingTimeInterval(EastKeeperRitualStore.lockDuration),
            revealId: "11111111-2222-4333-8444-555555555555",
            needsAppCommit: false
        )
    }
}

private final class LockedResults<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Element] = []

    func append(_ value: Element) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    var values: [Element] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
