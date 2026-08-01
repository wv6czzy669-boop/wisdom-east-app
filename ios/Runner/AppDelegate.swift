import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
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
      assertionFailure(
        "EAST file-protection registrar could not be created."
      )
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
private enum EastFileProtection {
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
      result(
        FlutterError(
          code: verificationFailedCode,
          message: "Failed to read back file protection attributes.",
          details: nil
        )
      )
      return
    }

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
  }
}
