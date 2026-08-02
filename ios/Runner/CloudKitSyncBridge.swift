import CloudKit
import Flutter
import Foundation

/// Build 26 Phase 4B-1: the native CloudKit bridge foundation. Exposes
/// exactly three methods (`getAccountSnapshot`, `configurePrivateZone`,
/// `getBridgeInfo`) and one event stream (account-change notifications) --
/// no record upload/download, no schema deployment, no capability
/// activation. See `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md`'s
/// Phase 4B-1 section for the full contract.
///
/// Registering this bridge (`AppDelegate.registerCloudKitSyncChannel`)
/// performs no CloudKit network request, no account lookup, and no zone
/// creation -- every CloudKit call happens lazily, only when Dart
/// explicitly invokes a method. This now extends to constructing the
/// `CKContainer` itself (see `containerProvider`/`container` below) --
/// nothing in this file touches `CloudKit.framework` at all until Dart
/// first invokes a method.
final class CloudKitSyncBridge: NSObject, FlutterStreamHandler {
  private let containerProvider: () -> CKContainer
  private var resolvedContainer: CKContainer?
  private var accountChangeObserver: NSObjectProtocol?
  private var eventSink: FlutterEventSink?

  /// `containerProvider` is a factory, not a value, and is never invoked by
  /// `init` itself -- only lazily, on first access of `container` below, in
  /// direct response to an explicit Dart method call. Build 26 Phase 4B-1
  /// native-test-host correction: this was previously an eagerly-evaluated
  /// default parameter (`container: CKContainer = .default()`), so
  /// constructing this bridge -- which happens unconditionally on every
  /// app launch, in `AppDelegate.registerCloudKitSyncChannel` -- also
  /// unconditionally constructed a real `CKContainer` before Dart, Flutter,
  /// or XCTest had done anything at all. Deferring this removes an entire
  /// class of risk (this code path had only ever been compiled before this
  /// phase, never actually executed) from the unconditional app-launch
  /// path. Tests inject a fake provider instead of a real `CKContainer`.
  init(containerProvider: @escaping () -> CKContainer = { .default() }) {
    self.containerProvider = containerProvider
    super.init()
  }

  /// Resolves (and caches) the real `CKContainer` on first access only.
  private var container: CKContainer {
    if let resolvedContainer = resolvedContainer {
      return resolvedContainer
    }
    let container = containerProvider()
    resolvedContainer = container
    return container
  }

  // MARK: - Method channel

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case CloudKitSyncBridgeConstants.methodGetAccountSnapshot:
      handleGetAccountSnapshot(result: result)
    case CloudKitSyncBridgeConstants.methodConfigurePrivateZone:
      handleConfigurePrivateZone(result: result)
    case CloudKitSyncBridgeConstants.methodGetBridgeInfo:
      result(bridgeInfoPayload())
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleGetAccountSnapshot(result: @escaping FlutterResult) {
    container.accountStatus { [weak self] status, _ in
      guard let self = self else { return }
      let normalizedStatus = CloudKitAccountStatusMapper.normalize(status)

      guard status == .available else {
        // Identity lookup is only ever attempted when the account is
        // available -- an unavailable/unknown account never falsely
        // reports a resolved fingerprint.
        DispatchQueue.main.async {
          result(
            self.accountSnapshotPayload(
              status: normalizedStatus,
              isPrivateDatabaseUsable: false,
              fingerprint: nil,
              fingerprintResolved: false
            ))
        }
        return
      }

      self.container.fetchUserRecordID { recordID, error in
        DispatchQueue.main.async {
          guard let recordID = recordID, error == nil else {
            // An identity-fetch failure must never be reported as if it
            // proved a different account -- fingerprintResolved simply
            // stays false; the account status itself (already
            // known-good here) is unaffected.
            result(
              self.accountSnapshotPayload(
                status: normalizedStatus,
                isPrivateDatabaseUsable: true,
                fingerprint: nil,
                fingerprintResolved: false
              ))
            return
          }
          let fingerprint = CloudKitAccountFingerprintUtility.fingerprint(for: recordID)
          result(
            self.accountSnapshotPayload(
              status: normalizedStatus,
              isPrivateDatabaseUsable: true,
              fingerprint: fingerprint,
              fingerprintResolved: true
            ))
        }
      }
    }
  }

  private func handleConfigurePrivateZone(result: @escaping FlutterResult) {
    container.accountStatus { [weak self] status, _ in
      guard let self = self else { return }
      let normalizedStatus = CloudKitAccountStatusMapper.normalize(status)

      guard status == .available else {
        DispatchQueue.main.async {
          result(
            self.zoneConfigurationPayload(
              success: false,
              zoneCreated: false,
              zoneAlreadyExisted: false,
              accountStatus: normalizedStatus,
              errorCode: CloudKitErrorClassifier.accountTemporarilyUnavailable
            ))
        }
        return
      }

      let coordinator = CloudKitPrivateZoneCoordinator(
        database: self.container.privateCloudDatabase)
      coordinator.configureZone { zoneResult in
        DispatchQueue.main.async {
          result(
            self.zoneConfigurationPayload(
              success: zoneResult.success,
              zoneCreated: zoneResult.zoneCreated,
              zoneAlreadyExisted: zoneResult.zoneAlreadyExisted,
              accountStatus: normalizedStatus,
              errorCode: zoneResult.errorCode
            ))
        }
      }
    }
  }

  private func bridgeInfoPayload() -> [String: Any] {
    [
      "bridgeVersion": CloudKitSyncBridgeConstants.bridgeVersion,
      "expectedZoneName": CloudKitSyncBridgeConstants.expectedZoneName,
      "expectedRecordTypes": CloudKitSyncBridgeConstants.expectedRecordTypes,
      "privateDatabaseOnly": true,
      "capabilityActivationExpected": false,
    ]
  }

  private func accountSnapshotPayload(
    status: String,
    isPrivateDatabaseUsable: Bool,
    fingerprint: String?,
    fingerprintResolved: Bool
  ) -> [String: Any?] {
    [
      "status": status,
      "isPrivateDatabaseUsable": isPrivateDatabaseUsable,
      "accountFingerprint": fingerprint,
      "fingerprintResolved": fingerprintResolved,
      "bridgeVersion": CloudKitSyncBridgeConstants.bridgeVersion,
    ]
  }

  private func zoneConfigurationPayload(
    success: Bool,
    zoneCreated: Bool,
    zoneAlreadyExisted: Bool,
    accountStatus: String,
    errorCode: String?
  ) -> [String: Any?] {
    [
      "success": success,
      "zoneCreated": zoneCreated,
      "zoneAlreadyExisted": zoneAlreadyExisted,
      "accountStatus": accountStatus,
      "errorCode": errorCode,
    ]
  }

  // MARK: - Event channel (account-change notifications)

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    eventSink = events
    // Idempotent: remove any prior observer before registering a new one,
    // so a second onListen call (without an intervening onCancel) never
    // registers a duplicate observer.
    removeObserverIfNeeded()
    accountChangeObserver = NotificationCenter.default.addObserver(
      forName: .CKAccountChanged,
      object: nil,
      queue: nil
    ) { [weak self] _ in
      // Delivered on whatever queue CloudKit posts from -- always hop to
      // the main thread before touching the Flutter event sink.
      DispatchQueue.main.async {
        self?.eventSink?([
          CloudKitSyncBridgeConstants.eventPayloadKey: CloudKitSyncBridgeConstants
            .accountChangedEventName
        ])
      }
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    removeObserverIfNeeded()
    eventSink = nil
    return nil
  }

  private func removeObserverIfNeeded() {
    if let observer = accountChangeObserver {
      NotificationCenter.default.removeObserver(observer)
      accountChangeObserver = nil
    }
  }
}
