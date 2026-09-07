import CloudKit
import CryptoKit
import Foundation

enum EastDailyRitualFailure: Error {
    case iCloudRequired, connectionRequired, unavailable, conflict, accountChanged
}

struct EastDailyRitualGrant: Codable, Equatable {
    let wisdomId: String
    let revealId: String
    let revealedAtMs: Int64
    let accountScope: String
    var unlockAtMs: Int64 { revealedAtMs + 86_400_000 }
    var validTimestamp: Bool { revealedAtMs >= 0 && revealedAtMs <= 8_640_000_000_000_000 - 86_400_000 }

    var payload: [String: Any] {
        ["wisdomId": wisdomId, "revealId": revealId,
         "revealedAtMs": revealedAtMs, "unlockAtMs": unlockAtMs,
         "accountScope": accountScope, "created": false]
    }

    static func validIdentity(_ wisdomId: String, _ revealId: String) -> Bool {
        wisdomId.range(of: "^east_wisdom_[0-9]{4}$", options: .regularExpression) != nil
            && revealId.range(of: "^[0-9a-f]{8}-[0-9a-f]{4}-[45][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$",
                              options: .regularExpression) != nil
    }
}

struct EastDailyRitualVersion {
    let grant: EastDailyRitualGrant
    let token: String
}

/// Narrow, injectable seam for concurrent-device and uncertain-response tests.
protocol EastDailyRitualTransport {
    func accountScope() async throws -> String
    func serverNowMs() async throws -> Int64
    func read(scope: String) async throws -> EastDailyRitualVersion?
    func save(wisdomId: String, revealId: String, legacyStartMs: Int64?,
              scope: String, previousToken: String?) async throws -> EastDailyRitualVersion
}

/// Account authority shared by Runner and the interactive widget. A grant is
/// acquired only by an explicit reveal. Device clocks never authorize a grant.
final class EastDailyRitualAuthority {
    private let transport: EastDailyRitualTransport
    init(transport: EastDailyRitualTransport) { self.transport = transport }

    func claim(wisdomId: String, legacy: EastDailyRitualGrant? = nil) async throws
        -> (grant: EastDailyRitualGrant, created: Bool) {
        let scope = try await transport.accountScope()
        for _ in 0..<4 {
            let serverNow = try await transport.serverNowMs()
            let current = try await transport.read(scope: scope)
            if let current, current.grant.unlockAtMs > serverNow {
                guard try await transport.accountScope() == scope else {
                    throw EastDailyRitualFailure.accountChanged
                }
                return (current.grant, false)
            }
            // An upgrade may seed its already-opened local wisdom only when
            // the account has no grant. Preserve its original Kept identity and
            // its remaining interval; never revive a stale legacy record.
            let migration = current == nil && legacy != nil
                && legacy!.validTimestamp && Self.validLegacyIdentity(legacy!)
                && legacy!.revealedAtMs <= serverNow
                && legacy!.unlockAtMs > serverNow ? legacy : nil
            guard try await transport.accountScope() == scope else {
                throw EastDailyRitualFailure.accountChanged
            }
            do {
                let saved = try await transport.save(
                    wisdomId: migration?.wisdomId ?? wisdomId,
                    revealId: migration?.revealId ?? UUID().uuidString.lowercased(),
                    legacyStartMs: migration?.revealedAtMs,
                    scope: scope, previousToken: current?.token
                )
                guard try await transport.accountScope() == scope else {
                    throw EastDailyRitualFailure.accountChanged
                }
                return (saved.grant, migration == nil)
            } catch EastDailyRitualFailure.conflict {
                // Another app/widget/device won. Fetch its exact occurrence,
                // including its UUID and server timestamp; never mint a second.
                continue
            }
        }
        throw EastDailyRitualFailure.unavailable
    }

    func refresh(legacy: EastDailyRitualGrant? = nil) async throws -> EastDailyRitualGrant? {
        let scope = try await transport.accountScope()
        for _ in 0..<4 {
            let current = try await transport.read(scope: scope)
            guard try await transport.accountScope() == scope else {
                throw EastDailyRitualFailure.accountChanged
            }
            if let current { return current.grant }
            // Register an already-opened legacy occurrence on upgrade, without
            // creating a fresh daily right in a background refresh.
            guard let legacy, legacy.validTimestamp,
                  Self.validLegacyIdentity(legacy) else { return nil }
            let now = try await transport.serverNowMs()
            guard legacy.revealedAtMs <= now, legacy.unlockAtMs > now else { return nil }
            do {
                let saved = try await transport.save(wisdomId: legacy.wisdomId,
                    revealId: legacy.revealId, legacyStartMs: legacy.revealedAtMs,
                    scope: scope, previousToken: nil)
                guard try await transport.accountScope() == scope else {
                    throw EastDailyRitualFailure.accountChanged
                }
                return saved.grant
            } catch EastDailyRitualFailure.conflict { continue }
        }
        throw EastDailyRitualFailure.unavailable
    }

    private static func validLegacyIdentity(_ grant: EastDailyRitualGrant) -> Bool {
        grant.accountScope.isEmpty && EastDailyRitualGrant.validIdentity(grant.wisdomId, grant.revealId)
    }
}

/// A separate private zone, not part of the Kept/Reflection sync or deletion
/// pipeline. Its two records contain public catalog IDs and daily-right metadata.
final class EastDailyRitualCloudTransport: EastDailyRitualTransport {
    static let containerIdentifier = "iCloud.com.dogukan.dailywisdom"
    static let zoneName = "EASTDailyRitualZone"
    static let grantType = "CKEastDailyRitual"
    static let clockType = "CKEastDailyRitualClock"
    private lazy var container = CKContainer(identifier: Self.containerIdentifier)
    private var database: CKDatabase { container.privateCloudDatabase }
    private var zoneReady = false
    private var versions: [String: CKRecord] = [:]
    private let identityLock = NSLock()
    private var cachedScope: String?
    private var accountChanged = false
    private var accountObserver: NSObjectProtocol?

    init() {
        accountObserver = NotificationCenter.default.addObserver(
            forName: .CKAccountChanged, object: nil, queue: nil
        ) { [weak self] _ in self?.invalidateAccount() }
    }

    deinit {
        if let accountObserver { NotificationCenter.default.removeObserver(accountObserver) }
    }

    private func invalidateAccount() {
        identityLock.lock()
        defer { identityLock.unlock() }
        accountChanged = true
    }

    private func resolvedScope(_ newValue: String? = nil) throws -> String? {
        identityLock.lock()
        defer { identityLock.unlock() }
        if accountChanged { throw EastDailyRitualFailure.accountChanged }
        if let newValue { cachedScope = newValue }
        return cachedScope
    }
    private var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    func accountScope() async throws -> String {
        // Reuse the verified identity only within this one request. Account
        // changes invalidate it, avoiding repeated network identity lookups.
        if let cached = try resolvedScope() { return cached }
        let status: CKAccountStatus = try await withCheckedThrowingContinuation { continuation in
            container.accountStatus { status, error in
                if let error { continuation.resume(throwing: Self.classify(error)) }
                else { continuation.resume(returning: status) }
            }
        }
        guard status == .available else {
            throw status == .noAccount || status == .restricted
                ? EastDailyRitualFailure.iCloudRequired : EastDailyRitualFailure.connectionRequired
        }
        let id: CKRecord.ID = try await withCheckedThrowingContinuation { continuation in
            container.fetchUserRecordID { id, error in
                if let id { continuation.resume(returning: id) }
                else { continuation.resume(throwing: Self.classify(error)) }
            }
        }
        let bytes = Data("com.dogukan.dailywisdom.cloudkit.account.v1:\(id.recordName)".utf8)
        let scope = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        _ = try resolvedScope(scope)
        return scope
    }

    func serverNowMs() async throws -> Int64 {
        try await configureZone()
        let probe = CKRecord(recordType: Self.clockType,
            recordID: CKRecord.ID(recordName: "clock", zoneID: zoneID))
        probe["nonce"] = UUID().uuidString as CKRecordValue
        // This disposable clock probe has no access-control state. Overwriting
        // it cannot grant a wisdom; only the CAS on the grant record can do so.
        let saved = try await modify(probe, policy: .allKeys)
        guard let date = saved.modificationDate else { throw EastDailyRitualFailure.unavailable }
        return Self.millis(date)
    }

    func read(scope: String) async throws -> EastDailyRitualVersion? {
        try await configureZone()
        let id = CKRecord.ID(recordName: "current", zoneID: zoneID)
        let record: CKRecord? = try await withCheckedThrowingContinuation { continuation in
            let operation = CKFetchRecordsOperation(recordIDs: [id])
            var item: Result<CKRecord, Error>?
            operation.perRecordResultBlock = { _, result in item = result }
            operation.fetchRecordsResultBlock = { result in
                if let item {
                    switch item {
                    case .success(let record): continuation.resume(returning: record)
                    case .failure(let error):
                        if (error as? CKError)?.code == .unknownItem { continuation.resume(returning: nil) }
                        else { continuation.resume(throwing: Self.classify(error)) }
                    }
                } else {
                    switch result {
                    case .failure(let error): continuation.resume(throwing: Self.classify(error))
                    case .success: continuation.resume(throwing: EastDailyRitualFailure.unavailable)
                    }
                }
            }
            configure(operation)
            database.add(operation)
        }
        guard let record else { return nil }
        return try version(record, scope: scope)
    }

    func save(wisdomId: String, revealId: String, legacyStartMs: Int64?,
              scope: String, previousToken: String?) async throws -> EastDailyRitualVersion {
        try await configureZone()
        let record: CKRecord
        if let previousToken {
            guard let existing = versions[previousToken] else { throw EastDailyRitualFailure.unavailable }
            record = existing
        } else {
            record = CKRecord(recordType: Self.grantType,
                recordID: CKRecord.ID(recordName: "current", zoneID: zoneID))
        }
        record["wisdomId"] = wisdomId as CKRecordValue
        record["revealId"] = revealId as CKRecordValue
        record["schemaVersion"] = 1 as CKRecordValue
        record["legacyRevealedAtMs"] = legacyStartMs.map(NSNumber.init(value:))
        let saved = try await modify(record, policy: .ifServerRecordUnchanged)
        return try version(saved, scope: scope)
    }

    private func version(_ record: CKRecord, scope: String) throws -> EastDailyRitualVersion {
        guard record.recordType == Self.grantType,
              record["schemaVersion"] as? Int == 1,
              let wisdomId = record["wisdomId"] as? String,
              let revealId = record["revealId"] as? String,
              EastDailyRitualGrant.validIdentity(wisdomId, revealId),
              let date = record.modificationDate,
              let token = record.recordChangeTag
        else { throw EastDailyRitualFailure.unavailable }
        let start = (record["legacyRevealedAtMs"] as? NSNumber)?.int64Value ?? Self.millis(date)
        guard start >= 0, start <= Self.millis(date),
              start <= 8_640_000_000_000_000 - 86_400_000 else { throw EastDailyRitualFailure.unavailable }
        versions[token] = record
        return EastDailyRitualVersion(grant: EastDailyRitualGrant(
            wisdomId: wisdomId, revealId: revealId, revealedAtMs: start, accountScope: scope), token: token)
    }

    private func configureZone() async throws {
        if zoneReady { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordZonesOperation(recordZonesToSave: [CKRecordZone(zoneID: zoneID)])
            operation.modifyRecordZonesResultBlock = { result in
                switch result {
                case .success: continuation.resume()
                case .failure(let error): continuation.resume(throwing: Self.classify(error))
                }
            }
            configure(operation)
            database.add(operation)
        }
        zoneReady = true
    }

    private func modify(_ record: CKRecord, policy: CKModifyRecordsOperation.RecordSavePolicy) async throws -> CKRecord {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordsToSave: [record])
            operation.savePolicy = policy
            operation.isAtomic = true
            var item: Result<CKRecord, Error>?
            operation.perRecordSaveBlock = { _, result in item = result }
            operation.modifyRecordsResultBlock = { result in
                if let item {
                    switch item {
                    case .success(let record): continuation.resume(returning: record)
                    case .failure(let error): continuation.resume(throwing: Self.classify(error))
                    }
                } else {
                    switch result {
                    case .failure(let error): continuation.resume(throwing: Self.classify(error))
                    case .success: continuation.resume(throwing: EastDailyRitualFailure.unavailable)
                    }
                }
            }
            configure(operation)
            database.add(operation)
        }
    }

    private func configure(_ operation: CKOperation) {
        operation.configuration.timeoutIntervalForRequest = 4
        operation.configuration.timeoutIntervalForResource = 6
        operation.qualityOfService = .userInitiated
    }

    static func millis(_ date: Date) -> Int64 { Int64(floor(date.timeIntervalSince1970 * 1000)) }

    static func classify(_ error: Error?) -> EastDailyRitualFailure {
        guard let error = error as? CKError else { return .unavailable }
        if error.code == .partialFailure,
           let nested = error.partialErrorsByItemID?.values.first {
            return classify(nested)
        }
        switch error.code {
        case .serverRecordChanged: return .conflict
        case .notAuthenticated: return .iCloudRequired
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited,
             .zoneBusy, .operationCancelled: return .connectionRequired
        default: return .unavailable
        }
    }
}
