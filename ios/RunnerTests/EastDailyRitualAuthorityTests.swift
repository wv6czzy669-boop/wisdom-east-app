import XCTest
@testable import Runner

final class EastDailyRitualAuthorityTests: XCTestCase {
    private let scopeA = String(repeating: "a", count: 64)
    private let scopeB = String(repeating: "b", count: 64)
    private let start: Int64 = 1_800_000_000_000

    func testTwoSimultaneousDevicesReceiveOneOccurrence() async throws {
        let server = DailyAuthorityTestServer(now: start)
        let first = EastDailyRitualAuthority(transport: DailyAuthorityTestTransport(server: server, scope: scopeA))
        let second = EastDailyRitualAuthority(transport: DailyAuthorityTestTransport(server: server, scope: scopeA))
        async let a = first.claim(wisdomId: "east_wisdom_0001")
        async let b = second.claim(wisdomId: "east_wisdom_0002")
        let results = try await [a, b]
        XCTAssertEqual(results[0].grant, results[1].grant)
        XCTAssertEqual(results.filter { $0.created }.count, 1)
        let writes = await server.writes
        XCTAssertEqual(writes, 1)
    }

    func testASecondDeviceCannotAcquireBeforeExactlyTwentyFourHours() async throws {
        let server = DailyAuthorityTestServer(now: start)
        let authority = EastDailyRitualAuthority(transport: DailyAuthorityTestTransport(server: server, scope: scopeA))
        let first = try await authority.claim(wisdomId: "east_wisdom_0001")
        await server.setTime(start + 86_400_000 - 1)
        let stillLocked = try await authority.claim(wisdomId: "east_wisdom_0002")
        XCTAssertEqual(first.grant, stillLocked.grant)
        XCTAssertFalse(stillLocked.created)
        await server.setTime(start + 86_400_000)
        let next = try await authority.claim(wisdomId: "east_wisdom_0002")
        XCTAssertTrue(next.created)
        XCTAssertNotEqual(first.grant.revealId, next.grant.revealId)
        XCTAssertEqual(next.grant.revealedAtMs, start + 86_400_000)
    }

    func testOfflineDeviceCannotCreateAGrant() async {
        let server = DailyAuthorityTestServer(now: start)
        let transport = DailyAuthorityTestTransport(server: server, scope: scopeA)
        transport.offline = true
        do {
            _ = try await EastDailyRitualAuthority(transport: transport).claim(wisdomId: "east_wisdom_0001")
            XCTFail("An offline request must not grant a local fallback")
        } catch EastDailyRitualFailure.connectionRequired {} catch { XCTFail("Unexpected failure") }
        let writes = await server.writes
        XCTAssertEqual(writes, 0)
    }

    func testLostSuccessResponseReusesTheSavedOccurrenceOnRetry() async throws {
        let server = DailyAuthorityTestServer(now: start)
        let transport = DailyAuthorityTestTransport(server: server, scope: scopeA)
        transport.dropNextSaveResponse = true
        let authority = EastDailyRitualAuthority(transport: transport)
        do {
            _ = try await authority.claim(wisdomId: "east_wisdom_0001")
            XCTFail("Simulate an ambiguous network result")
        } catch EastDailyRitualFailure.connectionRequired {}
        let retry = try await authority.claim(wisdomId: "east_wisdom_0002")
        XCTAssertFalse(retry.created)
        XCTAssertEqual(retry.grant.wisdomId, "east_wisdom_0001")
        let writes = await server.writes
        XCTAssertEqual(writes, 1)
    }

    func testDifferentAccountsHaveSeparateDailyRights() async throws {
        let server = DailyAuthorityTestServer(now: start)
        let a = try await EastDailyRitualAuthority(transport: DailyAuthorityTestTransport(server: server, scope: scopeA))
            .claim(wisdomId: "east_wisdom_0001")
        let b = try await EastDailyRitualAuthority(transport: DailyAuthorityTestTransport(server: server, scope: scopeB))
            .claim(wisdomId: "east_wisdom_0002")
        XCTAssertTrue(a.created && b.created)
        XCTAssertNotEqual(a.grant.revealId, b.grant.revealId)
    }

    func testAccountChangeDuringRequestNeverReturnsThePreviousAccountGrant() async throws {
        let server = DailyAuthorityTestServer(now: start)
        let transport = DailyAuthorityTestTransport(server: server, scope: scopeA)
        transport.changeAccountAfterSave = scopeB
        do {
            _ = try await EastDailyRitualAuthority(transport: transport).claim(wisdomId: "east_wisdom_0001")
            XCTFail("A stale account response must not reach presentation")
        } catch EastDailyRitualFailure.accountChanged {}
    }

    func testLegacyActiveWisdomKeepsItsIdentityAndOriginalUnlockTime() async throws {
        let server = DailyAuthorityTestServer(now: start)
        let legacy = EastDailyRitualGrant(wisdomId: "east_wisdom_0001",
            revealId: "11111111-2222-4333-8444-555555555555",
            revealedAtMs: start - 3_600_000, accountScope: "")
        let result = try await EastDailyRitualAuthority(transport: DailyAuthorityTestTransport(server: server, scope: scopeA))
            .claim(wisdomId: "east_wisdom_0002", legacy: legacy)
        XCTAssertFalse(result.created)
        XCTAssertEqual(result.grant.revealId, legacy.revealId)
        XCTAssertEqual(result.grant.unlockAtMs, legacy.unlockAtMs)
    }

    func testRefreshNeverCreatesOrConsumesADailyRight() async throws {
        let server = DailyAuthorityTestServer(now: start)
        let result = try await EastDailyRitualAuthority(transport: DailyAuthorityTestTransport(server: server, scope: scopeA)).refresh()
        XCTAssertNil(result)
        let writes = await server.writes
        XCTAssertEqual(writes, 0)
    }

    func testUpgradeRefreshRegistersOnlyTheExistingLegacyInterval() async throws {
        let server = DailyAuthorityTestServer(now: start)
        let authority = EastDailyRitualAuthority(transport: DailyAuthorityTestTransport(server: server, scope: scopeA))
        let legacy = EastDailyRitualGrant(wisdomId: "east_wisdom_0001",
            revealId: "11111111-2222-4333-8444-555555555555",
            revealedAtMs: start - 3_600_000, accountScope: "")
        let migrated = try await authority.refresh(legacy: legacy)
        XCTAssertEqual(migrated?.revealId, legacy.revealId)
        XCTAssertEqual(migrated?.unlockAtMs, legacy.unlockAtMs)
        let otherDevice = try await authority.claim(wisdomId: "east_wisdom_0059")
        XCTAssertFalse(otherDevice.created)
        XCTAssertEqual(otherDevice.grant, migrated)
    }

    func testUpgradeRefreshNeverRevivesAnExpiredLegacyWisdom() async throws {
        let server = DailyAuthorityTestServer(now: start)
        let authority = EastDailyRitualAuthority(transport: DailyAuthorityTestTransport(server: server, scope: scopeA))
        let legacy = EastDailyRitualGrant(wisdomId: "east_wisdom_0001",
            revealId: "11111111-2222-4333-8444-555555555555",
            revealedAtMs: start - 86_400_000, accountScope: "")
        let refreshed = try await authority.refresh(legacy: legacy)
        XCTAssertNil(refreshed)
        let writes = await server.writes
        XCTAssertEqual(writes, 0)
    }

    func testPersistentConflictsStopWithoutAnOfflineFallback() async throws {
        let server = DailyAuthorityTestServer(now: start)
        let transport = DailyAuthorityTestTransport(server: server, scope: scopeA)
        transport.alwaysConflict = true
        do {
            _ = try await EastDailyRitualAuthority(transport: transport).claim(wisdomId: "east_wisdom_0001")
            XCTFail("An unresolved conflict must not grant a second occurrence")
        } catch EastDailyRitualFailure.unavailable {}
        XCTAssertEqual(transport.saveAttempts, 4)
    }
}

private actor DailyAuthorityTestServer {
    var now: Int64
    var records: [String: EastDailyRitualVersion] = [:]
    var writes = 0
    init(now: Int64) { self.now = now }
    func setTime(_ value: Int64) { now = value }
    func read(_ scope: String) -> EastDailyRitualVersion? { records[scope] }
    func save(wisdomId: String, revealId: String, legacyStartMs: Int64?, scope: String,
              previousToken: String?) throws -> EastDailyRitualVersion {
        guard records[scope]?.token == previousToken else { throw EastDailyRitualFailure.conflict }
        writes += 1
        let record = EastDailyRitualVersion(grant: EastDailyRitualGrant(wisdomId: wisdomId,
            revealId: revealId, revealedAtMs: legacyStartMs ?? now, accountScope: scope), token: "\(writes)")
        records[scope] = record
        return record
    }
}

private final class DailyAuthorityTestTransport: EastDailyRitualTransport {
    let server: DailyAuthorityTestServer
    var scope: String
    var offline = false
    var dropNextSaveResponse = false
    var alwaysConflict = false
    var changeAccountAfterSave: String?
    var saveAttempts = 0
    init(server: DailyAuthorityTestServer, scope: String) { self.server = server; self.scope = scope }
    func accountScope() async throws -> String {
        if offline { throw EastDailyRitualFailure.connectionRequired }
        return scope
    }
    func serverNowMs() async throws -> Int64 { await server.now }
    func read(scope: String) async throws -> EastDailyRitualVersion? {
        let record = await server.read(scope)
        await Task.yield()
        return record
    }
    func save(wisdomId: String, revealId: String, legacyStartMs: Int64?, scope: String,
              previousToken: String?) async throws -> EastDailyRitualVersion {
        saveAttempts += 1
        if alwaysConflict { throw EastDailyRitualFailure.conflict }
        let record = try await server.save(wisdomId: wisdomId, revealId: revealId,
            legacyStartMs: legacyStartMs, scope: scope, previousToken: previousToken)
        if let next = changeAccountAfterSave { self.scope = next }
        if dropNextSaveResponse { dropNextSaveResponse = false; throw EastDailyRitualFailure.connectionRequired }
        return record
    }
}
