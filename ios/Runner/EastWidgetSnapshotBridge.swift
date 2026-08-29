import Flutter
import WidgetKit

/// EAST. Phase 11 -- the native side of the Home Screen widget's snapshot
/// bridge. Stateless, mirroring `EastFileProtection`'s shape: a single
/// `handle(_:result:)` entry point, registered once from
/// `AppDelegate.didInitializeImplicitFlutterEngine`.
///
/// Flutter's `DailyWisdomAccessService` remains the sole authority on the
/// canonical daily occurrence. The original free-widget methods still only
/// mirror that authority. Keeper-only methods additionally stage a candidate
/// and reconcile the interactive widget's provisional reveal; they never
/// bypass the Dart repository's final commit. WidgetKit reloads only when the
/// relevant persisted snapshot actually changes, preventing ordinary resume
/// reconciliation from producing reload spam.
enum EastWidgetSnapshotBridge {
    static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case EastWidgetSnapshotBridgeConstants.methodPublishRevealed:
            handlePublishRevealed(call, result: result)
        case EastWidgetSnapshotBridgeConstants.methodPublishSilence:
            handlePublishSilence(call, result: result)
        case EastWidgetSnapshotBridgeConstants.methodReadKeeperRitualSnapshot:
            result(EastKeeperRitualStore.bridgePayload(now: Date()))
        case EastWidgetSnapshotBridgeConstants.methodSetKeeperEntitlement:
            handleSetKeeperEntitlement(call, result: result)
        case EastWidgetSnapshotBridgeConstants.methodPublishKeeperPrepared:
            handlePublishKeeperPrepared(call, result: result)
        case EastWidgetSnapshotBridgeConstants.methodPublishKeeperActive:
            handlePublishKeeperActive(call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private static func handleSetKeeperEntitlement(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let arguments = call.arguments as? [String: Any],
              let isKeeper = arguments[EastWidgetSnapshotBridgeConstants.argIsKeeper] as? Bool
        else {
            result(invalidArguments("setKeeperEntitlement requires isKeeper"))
            return
        }
        if EastKeeperRitualStore.setKeeperEntitlement(isKeeper) {
            reloadKeeperTimelines()
        }
        result(nil)
    }

    private static func handlePublishKeeperPrepared(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let arguments = call.arguments as? [String: Any],
              let candidateId = arguments[EastWidgetSnapshotBridgeConstants.argCandidateId] as? String,
              let canonicalText = arguments[EastWidgetSnapshotBridgeConstants.argCanonicalText] as? String,
              let displayText = arguments[EastWidgetSnapshotBridgeConstants.argDisplayText] as? String,
              let wisdomId = arguments[EastWidgetSnapshotBridgeConstants.argWisdomId] as? String,
              let preparedAtMillis = milliseconds(arguments, EastWidgetSnapshotBridgeConstants.argPreparedAtMillis),
              let activationAtMillis = milliseconds(arguments, EastWidgetSnapshotBridgeConstants.argActivationAtMillis)
        else {
            result(invalidArguments("publishKeeperPrepared received an invalid candidate"))
            return
        }

        let candidate = EastKeeperRitualCandidate(
            candidateId: candidateId,
            canonicalText: canonicalText,
            displayText: displayText,
            wisdomId: wisdomId,
            preparedAt: date(milliseconds: preparedAtMillis),
            activationAt: date(milliseconds: activationAtMillis)
        )
        let changed = EastKeeperRitualStore.publishPrepared(
            candidate: candidate,
            presentation: presentation(from: arguments),
            now: Date()
        )
        if changed { reloadKeeperTimelines() }
        result(nil)
    }

    private static func handlePublishKeeperActive(
        _ call: FlutterMethodCall,
        result: @escaping FlutterResult
    ) {
        guard let arguments = call.arguments as? [String: Any],
              let candidateId = arguments[EastWidgetSnapshotBridgeConstants.argCandidateId] as? String,
              let canonicalText = arguments[EastWidgetSnapshotBridgeConstants.argCanonicalText] as? String,
              let displayText = arguments[EastWidgetSnapshotBridgeConstants.argDisplayText] as? String,
              let wisdomId = arguments[EastWidgetSnapshotBridgeConstants.argWisdomId] as? String,
              let revealedAtMillis = milliseconds(arguments, EastWidgetSnapshotBridgeConstants.argRevealedAtMillis),
              let unlockAtMillis = milliseconds(arguments, EastWidgetSnapshotBridgeConstants.argUnlockAtMillis)
        else {
            result(invalidArguments("publishKeeperActive received an invalid reveal"))
            return
        }

        let reveal = EastKeeperRitualReveal(
            candidateId: candidateId,
            canonicalText: canonicalText,
            displayText: displayText,
            wisdomId: wisdomId,
            revealedAt: date(milliseconds: revealedAtMillis),
            unlockAt: date(milliseconds: unlockAtMillis),
            revealId: arguments[EastWidgetSnapshotBridgeConstants.argRevealId] as? String,
            needsAppCommit: false
        )
        let changed = EastKeeperRitualStore.publishActive(
            reveal: reveal,
            presentation: presentation(from: arguments),
            now: Date()
        )
        if changed { reloadKeeperTimelines() }
        result(nil)
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

    private static func reloadKeeperTimelines() {
        if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadTimelines(ofKind: EastWidgetKind.keeperRitualKind)
        }
    }

    private static func milliseconds(
        _ arguments: [String: Any],
        _ key: String
    ) -> Double? {
        guard let value = arguments[key] as? NSNumber else { return nil }
        let milliseconds = value.doubleValue
        return milliseconds.isFinite && milliseconds >= 0 ? milliseconds : nil
    }

    private static func date(milliseconds: Double) -> Date {
        Date(timeIntervalSince1970: milliseconds / 1000.0)
    }

    private static func invalidArguments(_ message: String) -> FlutterError {
        FlutterError(code: "invalid_arguments", message: message, details: nil)
    }
}
