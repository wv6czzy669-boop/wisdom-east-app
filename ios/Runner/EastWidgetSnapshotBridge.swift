import Flutter
import WidgetKit

/// EAST. Phase 11 -- the native side of the Home Screen widget's snapshot
/// bridge. Stateless, mirroring `EastFileProtection`'s shape: a single
/// `handle(_:result:)` entry point, registered once from
/// `AppDelegate.didInitializeImplicitFlutterEngine`.
///
/// Flutter's `DailyWisdomAccessService` remains the sole authority on what
/// wisdom exists and when it unlocks -- this bridge never selects, generates,
/// or reveals anything. It only writes exactly what it is told into
/// `EastWidgetSnapshotStore` and, only when that write actually changed the
/// persisted snapshot, asks WidgetKit to reload this one widget kind's
/// timelines. An unchanged republish (e.g. a resume-time reconciliation that
/// finds nothing new) is a deliberate no-op -- this is the guard against
/// reload spam on ordinary rebuilds.
enum EastWidgetSnapshotBridge {
    static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case EastWidgetSnapshotBridgeConstants.methodPublishRevealed:
            handlePublishRevealed(call, result: result)
        case EastWidgetSnapshotBridgeConstants.methodPublishSilence:
            handlePublishSilence(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private static func handlePublishRevealed(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let arguments = call.arguments as? [String: Any],
              let text = arguments[EastWidgetSnapshotBridgeConstants.argText] as? String,
              let unlockAtMillis = arguments[
                EastWidgetSnapshotBridgeConstants.argUnlockAtMillis
              ] as? NSNumber
        else {
            result(FlutterError(
                code: "invalid_arguments",
                message: "publishRevealed requires text and unlockAtMillis",
                details: nil
            ))
            return
        }

        let unlockAt = Date(timeIntervalSince1970: unlockAtMillis.doubleValue / 1000.0)
        let changed = EastWidgetSnapshotStore.publishRevealed(text: text, unlockAt: unlockAt)
        if changed {
            reloadTimelines()
        }
        result(nil)
    }

    private static func handlePublishSilence(result: @escaping FlutterResult) {
        let changed = EastWidgetSnapshotStore.publishSilence()
        if changed {
            reloadTimelines()
        }
        result(nil)
    }

    private static func reloadTimelines() {
        if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadTimelines(ofKind: EastWidgetKind.kind)
        }
    }
}
