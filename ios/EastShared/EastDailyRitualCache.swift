import Darwin
import Foundation

/// The same authorized occurrence is readable by the app and widget offline.
/// This cache is never a source of permission to acquire another occurrence.
enum EastDailyRitualCache {
    private static let processLock = NSLock()
    private static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: EastWidgetSnapshotStore.appGroupIdentifier)
    }

    static func read() -> EastDailyRitualGrant? {
        coordinated {
            guard let path = directory?.appendingPathComponent("east_daily_authorized_v1.json"),
                  let data = try? Data(contentsOf: path),
                  let grant = try? JSONDecoder().decode(EastDailyRitualGrant.self, from: data),
                  EastDailyRitualGrant.validIdentity(grant.wisdomId, grant.revealId),
                  grant.validTimestamp,
                  grant.accountScope.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
            else { return nil }
            return grant
        } ?? nil
    }

    static func write(_ grant: EastDailyRitualGrant) -> Bool {
        coordinated {
            guard let path = directory?.appendingPathComponent("east_daily_authorized_v1.json") else { return false }
            if let data = try? Data(contentsOf: path),
               let current = try? JSONDecoder().decode(EastDailyRitualGrant.self, from: data),
               current.accountScope == grant.accountScope,
               current.revealedAtMs > grant.revealedAtMs { return true }
            do {
                try JSONEncoder().encode(grant).write(to: path, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                return true
            } catch { return false }
        } ?? false
    }

    private static func coordinated<T>(_ operation: () -> T) -> T? {
        processLock.lock()
        defer { processLock.unlock() }
        guard let url = directory?.appendingPathComponent(".east_daily_authority.lock") else { return nil }
        let descriptor = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { return nil }
        defer { _ = flock(descriptor, LOCK_UN) }
        return operation()
    }
}

/// Public, reviewed catalog bundled identically in Runner and EastWidget.
/// CloudKit stores catalog IDs only; every device renders in its own language.
enum EastDailyWisdomCatalog {
    private static let catalogs: [String: [String: String]] = {
        guard let url = Bundle.main.url(forResource: "EastDailyWisdomCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              document["schemaVersion"] as? Int == 1,
              let catalogs = document["catalogs"] as? [String: [String: String]]
        else { return [:] }
        return catalogs
    }()

    static func text(for wisdomId: String, localeOverrideTag: String? = nil) -> String? {
        let tag = EastWidgetLocaleResolver.resolvedProductTag(
            localeOverrideTag: localeOverrideTag, preferredLanguages: Locale.preferredLanguages)
        return catalogs[tag]?[wisdomId] ?? catalogs["en"]?[wisdomId]
    }

    static func canonicalText(for wisdomId: String) -> String? { catalogs["en"]?[wisdomId] }
}

enum EastDailyRitualRuntime {
    static func claim(wisdomId: String, legacy: EastDailyRitualGrant? = nil) async throws
        -> (grant: EastDailyRitualGrant, created: Bool) {
        guard EastDailyWisdomCatalog.canonicalText(for: wisdomId) != nil else {
            throw EastDailyRitualFailure.unavailable
        }
        let result = try await EastDailyRitualAuthority(transport: EastDailyRitualCloudTransport())
            .claim(wisdomId: wisdomId, legacy: legacy)
        guard EastDailyRitualCache.write(result.grant) else { throw EastDailyRitualFailure.unavailable }
        return result
    }

    static func refresh(legacy: EastDailyRitualGrant? = nil) async throws -> EastDailyRitualGrant? {
        let grant = try await EastDailyRitualAuthority(transport: EastDailyRitualCloudTransport()).refresh(legacy: legacy)
        if let grant { _ = EastDailyRitualCache.write(grant) }
        return grant
    }
}
