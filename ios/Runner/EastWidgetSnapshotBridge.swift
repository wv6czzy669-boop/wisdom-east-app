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
            handlePublishSilence(call, result: result)
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

        // EAST. 1.2 Slice 2A -- the required content contract above is
        // completely unchanged: optional presentation fields are read only
        // after `text`/`unlockAtMillis` have already been validated, and can
        // never make otherwise-valid revealed content fail.
        let unlockAt = Date(timeIntervalSince1970: unlockAtMillis.doubleValue / 1000.0)
        let changed: Bool
        if containsPresentationPayload(call.arguments) {
            changed = EastWidgetSnapshotStore.publishRevealed(
                text: text,
                unlockAt: unlockAt,
                presentation: presentation(from: call.arguments)
            )
        } else {
            // Legacy path, byte-for-byte unchanged: an old Dart binary
            // sending only `text`/`unlockAtMillis` never creates a
            // presentation key.
            changed = EastWidgetSnapshotStore.publishRevealed(text: text, unlockAt: unlockAt)
        }
        if changed {
            reloadTimelines()
        }
        result(nil)
    }

    private static func handlePublishSilence(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        let changed: Bool
        if containsPresentationPayload(call.arguments) {
            changed = EastWidgetSnapshotStore.publishSilence(presentation: presentation(from: call.arguments))
        } else {
            // Legacy path, byte-for-byte unchanged: old Dart code always
            // calls this with null arguments, which never creates a
            // presentation key.
            changed = EastWidgetSnapshotStore.publishSilence()
        }
        if changed {
            reloadTimelines()
        }
        result(nil)
    }

    /// EAST. 1.2 Slice 2A -- `true` only when at least one of the two
    /// optional presentation argument *keys* is present in `arguments`
    /// (even if its value is malformed, or an explicit Dart `null`, which
    /// arrives here as `NSNull`) -- key *presence*, not value validity, is
    /// what distinguishes a presentation-aware call from a legacy one. A
    /// non-`[String: Any]` argument (including `nil`, exactly what every
    /// legacy `publishSilence` call sends today) always resolves to `false`.
    /// No force casts.
    static func containsPresentationPayload(_ arguments: Any?) -> Bool {
        guard let map = arguments as? [String: Any] else { return false }
        return map[EastWidgetSnapshotBridgeConstants.argAppearanceMode] != nil
            || map[EastWidgetSnapshotBridgeConstants.argLocaleOverrideTag] != nil
    }

    /// EAST. 1.2 Slice 2A -- pure decoding only. Safely handles `nil`, a
    /// non-map argument, a map missing either or both presentation keys,
    /// and wrong-typed values (each simply fails its own `as? String` cast
    /// and falls through to the store's own safe default) -- no force
    /// casts anywhere. All validation itself -- the 15-locale allowlist and
    /// appearance parsing -- lives solely in
    /// `EastWidgetSnapshotStore.validatedPresentation`, never duplicated
    /// here.
    static func presentation(from arguments: Any?) -> EastWidgetPresentation {
        let map = arguments as? [String: Any]
        return EastWidgetSnapshotStore.validatedPresentation(
            appearanceModeRaw: map?[EastWidgetSnapshotBridgeConstants.argAppearanceMode] as? String,
            localeOverrideTagRaw: map?[EastWidgetSnapshotBridgeConstants.argLocaleOverrideTag] as? String
        )
    }

    private static func reloadTimelines() {
        if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadTimelines(ofKind: EastWidgetKind.kind)
        }
    }
}
