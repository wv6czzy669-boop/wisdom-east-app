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
  /// Used only by the Phase 4B-1 account-status/zone-configuration
  /// handlers below -- unmodified by the Phase 4C-2 correction that added
  /// `transportContainer`.
  private var container: CKContainer {
    if let resolvedContainer = resolvedContainer {
      return resolvedContainer
    }
    let container = containerProvider()
    resolvedContainer = container
    return container
  }

  private var resolvedTransportContainer: CKContainer?

  /// Build 26 Phase 4C-2 correction: the private record transport
  /// (`modifyPrivateRecords`/`fetchPrivateZoneChanges`) resolves its own,
  /// explicitly-identified `CKContainer` -- never `container`'s
  /// `CKContainer.default()` above. Resolved lazily, once, only on first
  /// use by one of the two transport handlers, exactly like `container`
  /// is -- constructing `CKContainer(identifier:)` performs no network
  /// request by itself, so this remains consistent with this file's
  /// existing "nothing touches `CloudKit.framework` until Dart explicitly
  /// invokes a method" rule.
  private var transportContainer: CKContainer {
    if let resolvedTransportContainer = resolvedTransportContainer {
      return resolvedTransportContainer
    }
    let transportContainer = CKContainer(
      identifier: CloudKitSyncBridgeConstants.containerIdentifier)
    resolvedTransportContainer = transportContainer
    return transportContainer
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
    case CloudKitSyncBridgeConstants.methodModifyPrivateRecords:
      handleModifyPrivateRecords(call: call, result: result)
    case CloudKitSyncBridgeConstants.methodFetchPrivateZoneChanges:
      handleFetchPrivateZoneChanges(call: call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Build 26 Phase 4C-2: record transport (modify / fetch)

  private func handleModifyPrivateRecords(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any] else {
      result(FlutterError(code: CloudKitErrorClassifier.invalidArguments, message: nil, details: nil))
      return
    }
    let allowedTopLevelKeys: Set<String> = ["records"]
    guard Set(arguments.keys).isSubset(of: allowedTopLevelKeys) else {
      result(FlutterError(code: CloudKitErrorClassifier.invalidArguments, message: nil, details: nil))
      return
    }
    guard let rawRecords = arguments["records"] as? [[String: Any]] else {
      result(FlutterError(code: CloudKitErrorClassifier.invalidArguments, message: nil, details: nil))
      return
    }

    let allowedEntryKeys: Set<String> = ["recordType", "fields", "previousSystemFields"]
    var inputs: [CloudKitRecordTransportCoordinator.ModifyInput] = []
    for entry in rawRecords {
      guard Set(entry.keys).isSubset(of: allowedEntryKeys) else {
        result(FlutterError(code: CloudKitErrorClassifier.invalidArguments, message: nil, details: nil))
        return
      }
      var previousSystemFields: String?
      if let rawPreviousSystemFields = entry["previousSystemFields"] {
        guard let stringValue = rawPreviousSystemFields as? String else {
          result(FlutterError(code: CloudKitErrorClassifier.invalidArguments, message: nil, details: nil))
          return
        }
        previousSystemFields = stringValue
      }

      switch CloudKitRecordEnvelopeArgumentParser.buildRecord(fromChannelEntry: entry) {
      case .success(let record):
        inputs.append(
          CloudKitRecordTransportCoordinator.ModifyInput(
            record: record, previousSystemFields: previousSystemFields))
      case .failure:
        // A malformed/invalid record envelope fails the entire call closed
        // before any CKModifyRecordsOperation is ever created -- never a
        // partial attempt against only the valid entries.
        result(FlutterError(code: CloudKitErrorClassifier.invalidArguments, message: nil, details: nil))
        return
      }
    }

    let coordinator = CloudKitRecordTransportCoordinator(
      database: transportContainer.privateCloudDatabase)
    coordinator.modifyRecords(inputs) { transportResult in
      DispatchQueue.main.async {
        result(self.modifyRecordsPayload(transportResult))
      }
    }
  }

  private func handleFetchPrivateZoneChanges(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let arguments = call.arguments as? [String: Any] else {
      result(FlutterError(code: CloudKitErrorClassifier.invalidArguments, message: nil, details: nil))
      return
    }
    let allowedKeys: Set<String> = ["previousServerToken"]
    guard Set(arguments.keys).isSubset(of: allowedKeys) else {
      result(FlutterError(code: CloudKitErrorClassifier.invalidArguments, message: nil, details: nil))
      return
    }

    var previousServerToken: String?
    if let rawValue = arguments["previousServerToken"], !(rawValue is NSNull) {
      guard let stringValue = rawValue as? String else {
        result(FlutterError(code: CloudKitErrorClassifier.invalidArguments, message: nil, details: nil))
        return
      }
      previousServerToken = stringValue
    }

    let coordinator = CloudKitRecordTransportCoordinator(
      database: transportContainer.privateCloudDatabase)
    coordinator.fetchZoneChanges(previousServerToken: previousServerToken) { transportResult in
      DispatchQueue.main.async {
        result(self.zoneChangesPayload(transportResult))
      }
    }
  }

  private func modifyRecordsPayload(
    _ transportResult: CloudKitRecordTransportCoordinator.ModifyResult
  ) -> [String: Any?] {
    [
      "overallStatus": transportResult.overallStatus.rawValue,
      "outcomes": transportResult.outcomes.map { outcome -> [String: Any?] in
        [
          "recordName": outcome.recordName,
          "success": outcome.success,
          "systemFields": outcome.systemFields,
          "errorCode": outcome.errorCode,
        ]
      },
      "errorCode": transportResult.errorCode,
    ]
  }

  private func zoneChangesPayload(
    _ transportResult: CloudKitRecordTransportCoordinator.ZoneChangesResult
  ) -> [String: Any?] {
    [
      "outcome": transportResult.outcome.rawValue,
      "changedKeptWisdomRecords": transportResult.changedKeptWisdomRecords.map {
        keptWisdomWirePayload($0)
      },
      "changedSyncStateRecords": transportResult.changedSyncStateRecords.map {
        syncStateWirePayload($0)
      },
      "serverToken": transportResult.serverToken,
      "errorCode": transportResult.errorCode,
    ]
  }

  /// Re-serializes a decoded native envelope back into the exact wire `Map`
  /// shape `CloudKeptWisdomWireEnvelope.encode`/`.tryDecode` already define
  /// on the Dart side (`lib/sync_platform/cloud_kept_wisdom_wire_envelope.dart`)
  /// -- never a second, competing wire shape.
  private func keptWisdomWirePayload(_ envelope: CloudKitKeptWisdomWireEnvelope) -> [String: Any?] {
    if envelope.isTombstone {
      return [
        "recordType": CloudKitRecordSchema.keptWisdomRecordType,
        "zoneName": CloudKitRecordSchema.zoneName,
        "recordName": envelope.recordName,
        "isTombstone": true,
        "deletedAtMs": envelope.deletedAtMs,
        "updatedAtMs": envelope.updatedAtMs,
        "mutationId": envelope.mutationId,
        "dataEpoch": envelope.dataEpoch,
        "schemaVersion": envelope.schemaVersion,
      ]
    }

    var payload: [String: Any?] = [
      "recordType": CloudKitRecordSchema.keptWisdomRecordType,
      "zoneName": CloudKitRecordSchema.zoneName,
      "recordName": envelope.recordName,
      "isTombstone": false,
      "revealId": envelope.revealId,
      "wisdomText": envelope.wisdomText,
      "revealedAtMs": envelope.revealedAtMs,
      "keptAtMs": envelope.keptAtMs,
      "updatedAtMs": envelope.updatedAtMs,
      "mutationId": envelope.mutationId,
      "dataEpoch": envelope.dataEpoch,
      "schemaVersion": envelope.schemaVersion,
    ]
    if let reflectionText = envelope.reflectionText {
      payload["reflectionText"] = reflectionText
    }
    if let reflectedAtMs = envelope.reflectedAtMs {
      payload["reflectedAtMs"] = reflectedAtMs
    }
    return payload
  }

  /// Mirrors `CloudEastSyncStateWireEnvelope.encode` exactly.
  private func syncStateWirePayload(_ envelope: CloudKitSyncStateWireEnvelope) -> [String: Any?] {
    [
      "recordType": CloudKitRecordSchema.syncStateRecordType,
      "zoneName": CloudKitRecordSchema.zoneName,
      "recordName": CloudKitRecordSchema.syncStateRecordName,
      "dataEpoch": envelope.dataEpoch,
      "resetAtMs": envelope.resetAtMs,
      "mutationId": envelope.mutationId,
      "schemaVersion": envelope.schemaVersion,
    ]
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
