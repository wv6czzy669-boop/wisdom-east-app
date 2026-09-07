import Flutter
import LocalAuthentication
import UIKit

@MainActor
protocol EastWritingAuthenticator: AnyObject {
  var available: Bool { get }
  func authenticate(reason: String, completion: @escaping (Bool) -> Void)
  func cancel()
}

@MainActor
final class EastDeviceOwnerAuthenticator: EastWritingAuthenticator {
  private var context: LAContext?

  var available: Bool {
    LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
  }

  func authenticate(reason: String, completion: @escaping (Bool) -> Void) {
    let context = LAContext()
    self.context = context
    guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
      completion(false)
      return
    }
    // System-owned Face ID / Touch ID, with the device passcode as recovery.
    // No biometric information or passcode enters Flutter or app storage.
    context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
      DispatchQueue.main.async { completion(success) }
    }
  }

  func cancel() {
    context?.invalidate()
    context = nil
  }
}

@MainActor
final class EastPrivateWritingLock {
  static let shared = EastPrivateWritingLock()
  static let channelName = "east/private_writing_lock"
  static let preferenceKey = "east.privateWritingLock.enabled"
  static let protectedFrameReady = Notification.Name("east.privateWriting.protectedFrameReady")

  private let preferences: UserDefaults
  private let authenticator: EastWritingAuthenticator
  private var pending: ((Bool) -> Void)?
  private var generation = 0
  private(set) var sensitive = false

  init(preferences: UserDefaults = .standard,
       authenticator: EastWritingAuthenticator? = nil) {
    self.preferences = preferences
    self.authenticator = authenticator ?? EastDeviceOwnerAuthenticator()
  }

  var enabled: Bool { preferences.bool(forKey: Self.preferenceKey) }
  var requiresProtectedFrame: Bool { enabled && sensitive }
  var status: [String: Any] {
    ["enabled": enabled, "available": authenticator.available]
  }

  func setSensitive(_ value: Bool) { sensitive = value }

  func authenticate(reason: String, changingEnabled: Bool? = nil,
                    completion: @escaping (Bool) -> Void) {
    guard pending == nil, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      completion(false)
      return
    }
    generation += 1
    let ticket = generation
    pending = completion
    authenticator.authenticate(reason: reason) { [weak self] success in
      guard let self, self.generation == ticket, let pending = self.pending else { return }
      self.pending = nil
      if success, let changingEnabled {
        self.preferences.set(changingEnabled, forKey: Self.preferenceKey)
      }
      pending(success)
    }
  }

  func didEnterBackground() {
    generation += 1
    let callback = pending
    pending = nil
    authenticator.cancel()
    callback?(false)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "status": result(status)
    case "sensitive":
      guard let value = args["value"] as? Bool else {
        result(FlutterError(code: "invalid_arguments", message: nil, details: nil)); return
      }
      setSensitive(value)
      result(nil)
    case "frameReady":
      if UIApplication.shared.applicationState == .active {
        NotificationCenter.default.post(name: Self.protectedFrameReady, object: nil)
      }
      result(nil)
    case "authenticate", "setEnabled":
      guard let reason = args["reason"] as? String,
        call.method != "setEnabled" || args["enabled"] is Bool else {
        result(FlutterError(code: "invalid_arguments", message: nil, details: nil)); return
      }
      authenticate(reason: reason, changingEnabled: call.method == "setEnabled" ? args["enabled"] as? Bool : nil) { [weak self] success in
        guard let self else { result(false); return }
        if call.method == "setEnabled" {
          result(self.status.merging(["authenticated": success]) { _, new in new })
        } else { result(success) }
      }
    default: result(FlutterMethodNotImplemented)
    }
  }
}
