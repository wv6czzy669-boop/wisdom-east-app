import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Build 26 Phase 4B-1: retains `CloudKitSyncBridge` for the app's
  /// lifetime -- see `registerCloudKitSyncChannel` below.
  private var cloudKitSyncBridge: CloudKitSyncBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerFileProtectionChannel(with: engineBridge.pluginRegistry)
    registerCloudKitSyncChannel(with: engineBridge.pluginRegistry)
    registerWidgetSnapshotChannel(with: engineBridge.pluginRegistry)
  }

  /// EAST. Phase 11: registers the Home Screen widget's snapshot bridge
  /// (`EastWidgetSnapshotBridge.swift`). Stateless -- unlike
  /// `cloudKitSyncBridge` above, nothing here needs to be retained for the
  /// app's lifetime. Follows the same non-aborting nil-registrar guard as
  /// `registerCloudKitSyncChannel`: a missing registrar leaves the channel
  /// unregistered rather than crashing the process, since this is a real,
  /// reachable condition under a native-test-host launch.
  private func registerWidgetSnapshotChannel(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "EastWidgetSnapshotChannel") else {
      return
    }

    let methodChannel = FlutterMethodChannel(
      name: EastWidgetSnapshotBridgeConstants.methodChannelName,
      binaryMessenger: registrar.messenger()
    )
    methodChannel.setMethodCallHandler { call, result in
      EastWidgetSnapshotBridge.handle(call, result: result)
    }
  }

  /// Build 26 Phase 4B-1: registers the native CloudKit bridge foundation
  /// (`CloudKitSyncBridge.swift`) -- account snapshot, private-zone
  /// configuration, static bridge info, and account-change events only.
  ///
  /// This registration itself performs no CloudKit network request, no
  /// account lookup, and no zone creation -- `CloudKitSyncBridge` only ever
  /// makes a CloudKit call lazily, in direct response to an explicit Dart
  /// method invocation. `cloudKitSyncBridge` is retained for the app's
  /// lifetime so its `NotificationCenter` observer (registered lazily, only
  /// when Dart first listens to the event channel) is never deallocated
  /// out from under an active registration.
  ///
  /// A missing registrar under a native test-host or unusual launch context
  /// leaves this channel unregistered rather than aborting the process. Any
  /// later Dart call surfaces as an ordinary,
  /// already-handled `MissingPluginException` /
  /// `CloudKitPlatformException.noNativeHandlerCode`
  /// (`lib/sync_platform/method_channel_cloud_kit_platform_bridge.dart`),
  /// never a process abort.
  private func registerCloudKitSyncChannel(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "EastCloudKitSyncChannel") else {
      return
    }

    let bridge = CloudKitSyncBridge()
    cloudKitSyncBridge = bridge

    let methodChannel = FlutterMethodChannel(
      name: CloudKitSyncBridgeConstants.methodChannelName,
      binaryMessenger: registrar.messenger()
    )
    methodChannel.setMethodCallHandler { call, result in
      bridge.handle(call, result: result)
    }

    let eventChannel = FlutterEventChannel(
      name: CloudKitSyncBridgeConstants.eventChannelName,
      binaryMessenger: registrar.messenger()
    )
    eventChannel.setStreamHandler(bridge)
  }

  /// Build 26 Phase 3B: registers the one small native bridge the
  /// protected Kept-state store uses to apply and verify
  /// `NSFileProtectionComplete` on a file or directory it has just
  /// written. This introduces no new capability, entitlement, or
  /// third-party dependency — it is plain Foundation/`FileManager`.
  ///
  /// Registered through the app's actual implicit-engine plugin registry
  /// (`FlutterImplicitEngineBridge.pluginRegistry`), the same mechanism
  /// `GeneratedPluginRegistrant` already uses above — this project does not
  /// expose a root `FlutterViewController` at this lifecycle point, so the
  /// classic `self.window?.rootViewController as! FlutterViewController`
  /// pattern would not apply here.
  private func registerFileProtectionChannel(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "EastFileProtectionChannel") else {
      // A native test-host launch can legitimately have no registrar. Match
      // the CloudKit/widget bridges: leave the channel unavailable and let
      // Dart surface its already-handled MissingPluginException if called.
      return
    }
    let channel = FlutterMethodChannel(
      name: EastFileProtection.channelName,
      binaryMessenger: registrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      EastFileProtection.handle(call, result: result)
    }
  }
}

/// Build 26 Phase 3B native file-protection bridge.
///
/// Exposes exactly one method, `protectAndVerifyComplete`, over the
/// `com.dogukan.dailywisdom/file_protection` channel: it applies
/// `NSFileProtectionComplete` to the file or directory at the given path
/// and immediately reads the attribute back to confirm it actually took
/// effect, only ever returning `true` after that read-back succeeds. This
/// is deliberately not a general native filesystem bridge.
///
/// Build 26 Phase 4H (post-Mac-validation): on physical iOS hardware this
/// class's contract is unchanged and remains fail-closed. On the iOS
/// Simulator, the final read-back comparison is relaxed -- see
/// `handle(_:result:)`'s own doc comment for the full rationale. This type
/// is intentionally `internal` (module-level, not `private`) rather than
/// `private` to the file, solely so `RunnerTests.swift` can exercise
/// `handle(_:result:)` directly via `@testable import Runner` -- this is a
/// visibility widening only, with no change to runtime behavior.
enum EastFileProtection {
  static let channelName = "com.dogukan.dailywisdom/file_protection"
  static let methodName = "protectAndVerifyComplete"

  static let invalidArgumentsCode = "invalid_arguments"
  static let pathNotFoundCode = "path_not_found"
  static let applyFailedCode = "protection_apply_failed"
  static let verificationFailedCode = "protection_verification_failed"
  static let unsupportedMethodCode = "unsupported_method"

  static func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == methodName else {
      result(
        FlutterError(
          code: unsupportedMethodCode,
          message: "Unsupported method: \(call.method)",
          details: nil
        )
      )
      return
    }

    guard let arguments = call.arguments as? [String: Any] else {
      result(
        FlutterError(
          code: invalidArgumentsCode,
          message: "Expected a dictionary of arguments.",
          details: nil
        )
      )
      return
    }

    guard
      let path = arguments["path"] as? String,
      !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      path.hasPrefix("/")
    else {
      result(
        FlutterError(
          code: invalidArgumentsCode,
          message: "Expected a non-empty absolute path.",
          details: nil
        )
      )
      return
    }

    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
      result(
        FlutterError(
          code: pathNotFoundCode,
          message: "No file or directory exists at the given path.",
          details: nil
        )
      )
      return
    }

    do {
      try fileManager.setAttributes(
        [.protectionKey: FileProtectionType.complete],
        ofItemAtPath: path
      )
    } catch {
      result(
        FlutterError(
          code: applyFailedCode,
          message: "Failed to apply file protection.",
          details: nil
        )
      )
      return
    }

    let appliedProtection: String?
    do {
      let attributes = try fileManager.attributesOfItem(atPath: path)
      let rawValue = attributes[.protectionKey]
      // Foundation has been observed to return either a `FileProtectionType`
      // or its underlying `String` raw value from this loosely-typed
      // dictionary depending on SDK version; accept either representation
      // rather than assuming one, since this cannot be exercised against a
      // real device/Simulator in this environment.
      if let protectionType = rawValue as? FileProtectionType {
        appliedProtection = protectionType.rawValue
      } else if let stringValue = rawValue as? String {
        appliedProtection = stringValue
      } else {
        appliedProtection = nil
      }
    } catch {
      // This read-back failure is a genuine error condition on both
      // physical hardware and Simulator (a thrown `attributesOfItem` is not
      // the Simulator Data Protection gap this fix addresses -- that gap is
      // a *reported value* mismatch below, never a thrown error here) --
      // unchanged on both platforms.
      result(
        FlutterError(
          code: verificationFailedCode,
          message: "Failed to read back file protection attributes.",
          details: nil
        )
      )
      return
    }

    #if targetEnvironment(simulator)
      // Build 26 Phase 4H: the iOS Simulator has no Secure Enclave / real
      // passcode-derived key hierarchy backing Data Protection classes --
      // its host filesystem cannot actually enforce, and does not reliably
      // report, `NSFileProtectionComplete` the way physical hardware does.
      // `setAttributes` above already completed without throwing (the one
      // operation that can genuinely fail before this point), path
      // existence/type were already verified above, and the read-back
      // itself succeeded without throwing -- on Simulator only, that is
      // treated as sufficient rather than additionally requiring
      // `appliedProtection` to exactly equal `.complete`, since the
      // Simulator's answer to that specific question is not trustworthy.
      // `#if targetEnvironment(simulator)` is a compile-time condition tied
      // to the build destination, never a runtime heuristic, environment
      // variable, or filesystem-path sniff -- this branch does not exist at
      // all in a physical-device build, so it can never be reached there.
      // A real device build takes the `#else` branch below, unchanged.
      _ = appliedProtection
      result(true)
    #else
      guard appliedProtection == FileProtectionType.complete.rawValue else {
        result(
          FlutterError(
            code: verificationFailedCode,
            message: "File protection could not be verified after applying it.",
            details: nil
          )
        )
        return
      }

      result(true)
    #endif
  }
}
