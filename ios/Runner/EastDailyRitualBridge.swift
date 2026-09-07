import Flutter
import Foundation

enum EastDailyRitualBridge {
    static let channelName = "com.dogukan.dailywisdom/daily_ritual"

    static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "readCached" {
            result(EastDailyRitualCache.read()?.payload)
            return
        }
        guard call.method == "claim" || call.method == "refresh" else {
            result(FlutterMethodNotImplemented)
            return
        }
        // Flutter also launches inside the native unit-test host. Those tests
        // inject the authority transport and must not use a real Apple account
        // or instantiate CloudKit from an unsigned XCTest runner.
        if NSClassFromString("XCTestCase") != nil {
            result(FlutterError(code: "unavailable", message: nil, details: nil))
            return
        }
        let arguments = call.arguments as? [String: Any]
        if call.method == "claim", arguments?["wisdomId"] as? String == nil {
            result(FlutterError(code: "unavailable", message: nil, details: nil))
            return
        }
        Task {
            do {
                let payload: [String: Any]?
                if call.method == "claim", let wisdomId = arguments?["wisdomId"] as? String {
                    let authorized = try await EastDailyRitualRuntime.claim(
                        wisdomId: wisdomId, legacy: legacy(arguments?["legacyRecord"]))
                    var fields = authorized.grant.payload
                    fields["created"] = authorized.created
                    payload = fields
                } else {
                    payload = try await EastDailyRitualRuntime.refresh(legacy: legacy(arguments?["legacyRecord"]))?.payload
                }
                await MainActor.run { result(payload) }
            } catch {
                let code: String
                switch error as? EastDailyRitualFailure {
                case .iCloudRequired: code = "icloud_required"
                case .connectionRequired: code = "connection_required"
                default: code = "unavailable"
                }
                await MainActor.run { result(FlutterError(code: code, message: nil, details: nil)) }
            }
        }
    }

    private static func legacy(_ value: Any?) -> EastDailyRitualGrant? {
        guard let map = value as? [String: Any],
              let wisdomId = map["wisdomId"] as? String,
              let revealId = map["revealId"] as? String,
              EastDailyRitualGrant.validIdentity(wisdomId, revealId),
              EastDailyWisdomCatalog.canonicalText(for: wisdomId) != nil,
              let start = map["revealedAtMs"] as? Int64,
              let end = map["unlockAtMs"] as? Int64,
              start >= 0, end > start, end - start == 86_400_000
        else { return nil }
        return EastDailyRitualGrant(wisdomId: wisdomId, revealId: revealId,
            revealedAtMs: start, accountScope: "")
    }
}
