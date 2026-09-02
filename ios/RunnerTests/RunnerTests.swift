import CloudKit
import Flutter
import UIKit
import XCTest

@testable import Runner

class RunnerTests: XCTestCase {
  // MARK: - App-switcher privacy shield

  @MainActor
  func testPrivacyShieldCoversIdempotentlyAndRevealsOnReturn() {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    let sensitiveContent = UILabel(frame: window.bounds)
    sensitiveContent.text = "A private Reflection"
    window.addSubview(sensitiveContent)

    let controller = EastPrivacyShieldController()
    controller.cover(window: window)

    XCTAssertTrue(controller.isCovering)
    XCTAssertEqual(window.subviews.last?.tag, EastPrivacyShieldController.shieldViewTag)
    XCTAssertEqual(
      window.subviews.filter { $0.tag == EastPrivacyShieldController.shieldViewTag }.count,
      1
    )

    // Background notifications can arrive more than once. Re-covering must
    // neither stack duplicate surfaces nor expose the content beneath.
    controller.cover(window: window)
    XCTAssertEqual(
      window.subviews.filter { $0.tag == EastPrivacyShieldController.shieldViewTag }.count,
      1
    )
    XCTAssertEqual(window.subviews.last?.tag, EastPrivacyShieldController.shieldViewTag)

    controller.reveal()
    XCTAssertFalse(controller.isCovering)
    XCTAssertNil(window.viewWithTag(EastPrivacyShieldController.shieldViewTag))
    XCTAssertTrue(window.subviews.contains(sensitiveContent))
  }

  @MainActor
  func testPrivacyShieldMatchesTheResponsiveLaunchMarkComposition() throws {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    let controller = EastPrivacyShieldController()

    controller.cover(window: window)
    let shield = try XCTUnwrap(
      window.viewWithTag(EastPrivacyShieldController.shieldViewTag)
    )
    shield.layoutIfNeeded()

    let ring = try XCTUnwrap(
      shield.descendant(withAccessibilityIdentifier: "east-privacy-launch-ring")
    )
    let title = try XCTUnwrap(
      shield.descendant(withAccessibilityIdentifier: "east-privacy-launch-title") as? UILabel
    )

    let safeBounds = shield.bounds.inset(by: shield.safeAreaInsets)
    let expectedDiameter = min(window.bounds.width * 0.585, safeBounds.height)
    XCTAssertEqual(ring.bounds.width, expectedDiameter, accuracy: 0.001)
    XCTAssertEqual(ring.bounds.height, expectedDiameter, accuracy: 0.001)
    XCTAssertEqual(ring.center.x, safeBounds.midX, accuracy: 0.001)
    XCTAssertEqual(ring.center.y, safeBounds.midY, accuracy: 0.001)
    XCTAssertEqual(ring.layer.cornerRadius, expectedDiameter / 2, accuracy: 0.001)
    XCTAssertEqual(ring.layer.borderWidth, 0.85, accuracy: 0.001)
    XCTAssertTrue(title.superview === ring)
    XCTAssertEqual(title.center.x, ring.bounds.midX, accuracy: 0.001)
    XCTAssertEqual(title.center.y, ring.bounds.midY - 2.5, accuracy: 0.001)
    XCTAssertEqual(title.font.pointSize, 21.5, accuracy: 0.001)
    XCTAssertEqual(title.font.fontName, "EBGaramond-Regular")
    XCTAssertEqual(title.bounds.height, 21.5 * 1.28, accuracy: 0.001)
    let letterSpacing = try XCTUnwrap(
      title.attributedText?.attribute(
        .kern,
        at: 0,
        effectiveRange: nil
      ) as? CGFloat,
      "Privacy title must retain Flutter's exact 0.5pt letter spacing"
    )
    XCTAssertEqual(letterSpacing, 0.5, accuracy: 0.001)
  }

  func testRunnerUsesThePrivacyAwareSceneDelegate() throws {
    let sceneManifest = try XCTUnwrap(
      Bundle.main.object(forInfoDictionaryKey: "UIApplicationSceneManifest")
        as? [String: Any]
    )
    let configurations = try XCTUnwrap(
      sceneManifest["UISceneConfigurations"] as? [String: Any]
    )
    let applicationConfigurations = try XCTUnwrap(
      configurations["UIWindowSceneSessionRoleApplication"] as? [[String: Any]]
    )
    let delegateClass = try XCTUnwrap(
      applicationConfigurations.first?["UISceneDelegateClassName"] as? String
    )

    XCTAssertTrue(delegateClass.hasSuffix(".SceneDelegate"))
    XCTAssertNotEqual(delegateClass, "FlutterSceneDelegate")
  }

  // MARK: - Release privacy-manifest coverage

  private func loadPrivacyManifest(at url: URL) throws -> [String: Any] {
    let data = try Data(contentsOf: url)
    return try XCTUnwrap(
      PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    )
  }

  private func assertAppGroupUserDefaultsDeclaration(
    _ manifest: [String: Any],
    expectsFileTimestamp: Bool,
    file: StaticString = #filePath,
    line: UInt = #line
  ) throws {
    XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false, file: file, line: line)
    XCTAssertEqual(
      (manifest["NSPrivacyTrackingDomains"] as? [String])?.count,
      0,
      file: file,
      line: line
    )
    XCTAssertEqual(
      (manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])?.count,
      0,
      file: file,
      line: line
    )

    let accessedTypes = try XCTUnwrap(
      manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]],
      file: file,
      line: line
    )
    XCTAssertEqual(accessedTypes.count, expectsFileTimestamp ? 2 : 1, file: file, line: line)
    let typesByCategory = Dictionary(
      uniqueKeysWithValues: accessedTypes.compactMap { entry in
        (entry["NSPrivacyAccessedAPIType"] as? String).map { ($0, entry) }
      }
    )
    let userDefaults = try XCTUnwrap(
      typesByCategory["NSPrivacyAccessedAPICategoryUserDefaults"],
      file: file,
      line: line
    )
    XCTAssertEqual(
      userDefaults["NSPrivacyAccessedAPIType"] as? String,
      "NSPrivacyAccessedAPICategoryUserDefaults",
      file: file,
      line: line
    )
    if expectsFileTimestamp {
      let fileTimestamp = try XCTUnwrap(
        typesByCategory["NSPrivacyAccessedAPICategoryFileTimestamp"],
        file: file,
        line: line
      )
      XCTAssertEqual(
        fileTimestamp["NSPrivacyAccessedAPITypeReasons"] as? [String],
        ["C617.1"],
        file: file,
        line: line
      )
    }
    XCTAssertEqual(
      userDefaults["NSPrivacyAccessedAPITypeReasons"] as? [String],
      ["1C8F.1"],
      file: file,
      line: line
    )
  }

  func testRunnerBundlesItsAppGroupPrivacyManifest() throws {
    let url = try XCTUnwrap(
      Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy")
    )
    try assertAppGroupUserDefaultsDeclaration(
      loadPrivacyManifest(at: url),
      expectsFileTimestamp: true
    )
  }

  func testWidgetBundlesItsAppGroupPrivacyManifest() throws {
    let plugInsURL = try XCTUnwrap(Bundle.main.builtInPlugInsURL)
    let extensionURL = plugInsURL.appendingPathComponent("EastWidgetExtension.appex")
    let bundle = try XCTUnwrap(Bundle(url: extensionURL))
    let manifestURL = try XCTUnwrap(
      bundle.url(forResource: "PrivacyInfo", withExtension: "xcprivacy")
    )
    try assertAppGroupUserDefaultsDeclaration(
      loadPrivacyManifest(at: manifestURL),
      expectsFileTimestamp: false
    )
  }

  // MARK: - Build 26 Phase 4B-1: CloudKit bridge pure-mapping unit tests
  //
  // These exercise only pure functions (no CloudKit network call, no
  // account lookup, no zone creation) -- exactly the kind of native logic
  // Phase 4B-1 asks to be made unit-testable without a real device,
  // simulator network access, or a real iCloud account.

  func testAccountStatusMapperNormalizesKnownCases() {
    XCTAssertEqual(CloudKitAccountStatusMapper.normalize(.available), "available")
    XCTAssertEqual(CloudKitAccountStatusMapper.normalize(.noAccount), "noAccount")
    XCTAssertEqual(CloudKitAccountStatusMapper.normalize(.restricted), "restricted")
    XCTAssertEqual(
      CloudKitAccountStatusMapper.normalize(.couldNotDetermine), "couldNotDetermine")
  }

  @available(iOS 15.0, *)
  func testAccountStatusMapperNormalizesTemporarilyUnavailable() {
    XCTAssertEqual(
      CloudKitAccountStatusMapper.normalize(.temporarilyUnavailable),
      "temporarilyUnavailable")
  }

  func testErrorClassifierMapsKnownCKErrorCodes() {
    XCTAssertEqual(
      CloudKitErrorClassifier.symbolicCode(for: CKError(.networkUnavailable)),
      CloudKitErrorClassifier.networkUnavailable)
    XCTAssertEqual(
      CloudKitErrorClassifier.symbolicCode(for: CKError(.notAuthenticated)),
      CloudKitErrorClassifier.notAuthenticated)
    XCTAssertEqual(
      CloudKitErrorClassifier.symbolicCode(for: CKError(.serverRecordChanged)),
      CloudKitErrorClassifier.serverRecordChanged)
    XCTAssertEqual(
      CloudKitErrorClassifier.symbolicCode(for: CKError(.zoneBusy)),
      CloudKitErrorClassifier.zoneBusy)
    XCTAssertEqual(
      CloudKitErrorClassifier.symbolicCode(for: CKError(.limitExceeded)),
      CloudKitErrorClassifier.limitExceeded)
  }

  func testErrorClassifierMapsNonCKErrorToUnrecognized() {
    struct SomeOtherError: Error {}
    XCTAssertEqual(
      CloudKitErrorClassifier.symbolicCode(for: SomeOtherError()),
      CloudKitErrorClassifier.unrecognizedNativeError)
  }

  func testKeeperEntitlementAcceptsOnlyCurrentKeeperProduct() {
    XCTAssertTrue(
      EastKeeperEntitlement.isCurrentKeeperTransaction(
        productID: EastKeeperEntitlement.keeperProductID,
        revocationDate: nil
      )
    )
    XCTAssertFalse(
      EastKeeperEntitlement.isCurrentKeeperTransaction(
        productID: "another.product",
        revocationDate: nil
      )
    )
    XCTAssertFalse(
      EastKeeperEntitlement.isCurrentKeeperTransaction(
        productID: EastKeeperEntitlement.keeperProductID,
        revocationDate: Date()
      )
    )
  }

  private func invokeProductionDiagnostics(
    method: String = EastProductionDiagnostics.methodName,
    arguments: Any?
  ) -> Any? {
    let call = FlutterMethodCall(methodName: method, arguments: arguments)
    let calledOnce = expectation(description: "EastProductionDiagnostics result called")
    var capturedResult: Any?
    EastProductionDiagnostics().handle(call) { value in
      capturedResult = value
      calledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)
    return capturedResult
  }

  func testProductionDiagnosticsAcceptsClosedSignal() {
    XCTAssertNil(
      invokeProductionDiagnostics(arguments: ["signal": "syncTerminalFailure"])
    )
  }

  func testProductionDiagnosticsRejectsUnknownSignal() {
    let result = invokeProductionDiagnostics(arguments: ["signal": "private-data"])
    XCTAssertEqual((result as? FlutterError)?.code, "invalid_arguments")
  }

  func testProductionDiagnosticsRejectsExtraPayloadFields() {
    let result = invokeProductionDiagnostics(
      arguments: ["signal": "syncCompleted", "details": "must-not-cross"]
    )
    XCTAssertEqual((result as? FlutterError)?.code, "invalid_arguments")
  }

  func testProductionDiagnosticsRejectsUnsupportedMethod() {
    let result = invokeProductionDiagnostics(
      method: "recordDetails",
      arguments: ["signal": "syncCompleted"]
    )
    XCTAssertTrue((result as AnyObject) === FlutterMethodNotImplemented)
  }

  func testAccountFingerprintUtilityIsDeterministicAndDistinct() {
    let zoneID = CKRecordZone.ID(zoneName: "EASTKeptZone", ownerName: CKCurrentUserDefaultName)
    let recordIDA = CKRecord.ID(recordName: "user-record-a", zoneID: zoneID)
    let recordIDB = CKRecord.ID(recordName: "user-record-b", zoneID: zoneID)

    let fingerprintA1 = CloudKitAccountFingerprintUtility.fingerprint(for: recordIDA)
    let fingerprintA2 = CloudKitAccountFingerprintUtility.fingerprint(for: recordIDA)
    let fingerprintB = CloudKitAccountFingerprintUtility.fingerprint(for: recordIDB)

    XCTAssertEqual(fingerprintA1, fingerprintA2)
    XCTAssertNotEqual(fingerprintA1, fingerprintB)
    // Never the raw record name itself.
    XCTAssertNotEqual(fingerprintA1, recordIDA.recordName)
  }

  func testBridgeConstantsMatchPhase4ADomainConstants() {
    XCTAssertEqual(CloudKitSyncBridgeConstants.expectedZoneName, "EASTKeptZone")
    XCTAssertEqual(
      CloudKitSyncBridgeConstants.expectedRecordTypes, ["CKKeptWisdom", "CKEastSyncState"])
    XCTAssertEqual(
      CloudKitSyncBridgeConstants.methodChannelName, "com.dogukan.dailywisdom/cloudkit_sync")
    XCTAssertEqual(
      CloudKitSyncBridgeConstants.eventChannelName,
      "com.dogukan.dailywisdom/cloudkit_sync_events")
    XCTAssertGreaterThanOrEqual(CloudKitSyncBridgeConstants.bridgeVersion, 1)
  }

  // Build 26 Phase 4C-2 correction: the private record transport
  // (`CloudKitSyncBridge.transportContainer`) constructs
  // `CKContainer(identifier: CloudKitSyncBridgeConstants.containerIdentifier)`
  // explicitly -- this locks the exact identifier value that source
  // constructs with. `transportContainer` itself is `private` and cannot be
  // introspected directly even via `@testable import` (Swift access control
  // is unaffected by `@testable`), so the accompanying `grep -RIn
  // "CKContainer(identifier:"` / `grep -RIn "CKContainer.default()"` source
  // checks in this correction's completion report are the authoritative
  // proof that only `CloudKitSyncBridge.transportContainer` (never
  // `handleModifyPrivateRecords`/`handleFetchPrivateZoneChanges` calling
  // `container` instead) is what the two transport handlers actually use.
  func testTransportContainerIdentifierConstantIsExact() {
    XCTAssertEqual(
      CloudKitSyncBridgeConstants.containerIdentifier, "iCloud.com.dogukan.dailywisdom")
  }

  func testErrorClassifierMapsServerRejectedRequest() {
    XCTAssertEqual(
      CloudKitErrorClassifier.symbolicCode(for: CKError(.serverRejectedRequest)),
      CloudKitErrorClassifier.serverRejectedRequest)
    XCTAssertEqual(CloudKitErrorClassifier.serverRejectedRequest, "serverRejectedRequest")
  }

  // MARK: - Build 26 Phase 4B-2: CloudKitPrivateZoneCoordinator fetch/fallback tests
  //
  // `FakeZoneOperationDatabase` implements `CloudKitZoneOperationDatabase`
  // entirely in-memory and synchronously -- no real CloudKit network call,
  // no real iCloud account, no real zone. `add(_:)` invokes the supplied
  // `CKModifyRecordZonesOperation`'s own completion block directly instead
  // of enqueuing it against a real database, so every test below is
  // deterministic and requires no waiting for real network I/O.

  private final class FakeZoneOperationDatabase: CloudKitZoneOperationDatabase {
    enum FetchOutcome {
      case zoneExists
      case error(CKError)
    }

    var fetchOutcome: FetchOutcome = .error(CKError(.zoneNotFound))
    /// `nil` means the create/save operation succeeds.
    var createOutcome: Error?
    private(set) var fetchCallCount = 0
    private(set) var addCallCount = 0

    func fetch(
      withRecordZoneID zoneID: CKRecordZone.ID,
      completionHandler: @escaping @Sendable (CKRecordZone?, Error?) -> Void
    ) {
      fetchCallCount += 1
      switch fetchOutcome {
      case .zoneExists:
        completionHandler(CKRecordZone(zoneID: zoneID), nil)
      case .error(let error):
        completionHandler(nil, error)
      }
    }

    func add(_ operation: CKDatabaseOperation) {
      addCallCount += 1
      guard let modifyOperation = operation as? CKModifyRecordZonesOperation else {
        return
      }
      if let error = createOutcome {
        modifyOperation.modifyRecordZonesResultBlock?(.failure(error))
      } else {
        modifyOperation.modifyRecordZonesResultBlock?(.success(()))
      }
    }
  }

  // 1. Existing zone -> alreadyExisted success; no create attempt.
  func testConfigureZoneReportsSuccessWhenZoneAlreadyExists() {
    let fakeDatabase = FakeZoneOperationDatabase()
    fakeDatabase.fetchOutcome = .zoneExists
    let coordinator = CloudKitPrivateZoneCoordinator(database: fakeDatabase)

    let calledOnce = expectation(description: "completion called")
    coordinator.configureZone { result in
      XCTAssertTrue(result.success)
      XCTAssertFalse(result.zoneCreated)
      XCTAssertTrue(result.zoneAlreadyExisted)
      XCTAssertNil(result.errorCode)
      calledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)
    XCTAssertEqual(fakeDatabase.addCallCount, 0)
  }

  // 2. zoneNotFound -> create succeeds -> success, zoneCreated.
  func testConfigureZoneCreatesZoneWhenFetchReturnsZoneNotFound() {
    let fakeDatabase = FakeZoneOperationDatabase()
    fakeDatabase.fetchOutcome = .error(CKError(.zoneNotFound))
    fakeDatabase.createOutcome = nil
    let coordinator = CloudKitPrivateZoneCoordinator(database: fakeDatabase)

    let calledOnce = expectation(description: "completion called")
    coordinator.configureZone { result in
      XCTAssertTrue(result.success)
      XCTAssertTrue(result.zoneCreated)
      XCTAssertFalse(result.zoneAlreadyExisted)
      XCTAssertNil(result.errorCode)
      calledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)
    XCTAssertEqual(fakeDatabase.addCallCount, 1)
  }

  // 3. serverRejectedRequest fetch -> guarded create fallback succeeds.
  func testConfigureZoneFallsBackToCreateWhenFetchReturnsServerRejectedRequest() {
    let fakeDatabase = FakeZoneOperationDatabase()
    fakeDatabase.fetchOutcome = .error(CKError(.serverRejectedRequest))
    fakeDatabase.createOutcome = nil
    let coordinator = CloudKitPrivateZoneCoordinator(database: fakeDatabase)

    let calledOnce = expectation(description: "completion called")
    coordinator.configureZone { result in
      XCTAssertTrue(result.success)
      XCTAssertTrue(result.zoneCreated)
      XCTAssertFalse(result.zoneAlreadyExisted)
      XCTAssertNil(result.errorCode)
      calledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)
    XCTAssertEqual(fakeDatabase.addCallCount, 1)
  }

  // 4. serverRejectedRequest fetch -> fallback create itself fails -> the
  //    create operation's own error is reported, never the original fetch
  //    error hidden behind it.
  func testConfigureZoneReportsCreateErrorWhenFallbackCreateFails() {
    let fakeDatabase = FakeZoneOperationDatabase()
    fakeDatabase.fetchOutcome = .error(CKError(.serverRejectedRequest))
    fakeDatabase.createOutcome = CKError(.networkFailure)
    let coordinator = CloudKitPrivateZoneCoordinator(database: fakeDatabase)

    let calledOnce = expectation(description: "completion called")
    coordinator.configureZone { result in
      XCTAssertFalse(result.success)
      XCTAssertFalse(result.zoneCreated)
      XCTAssertFalse(result.zoneAlreadyExisted)
      XCTAssertEqual(result.errorCode, CloudKitErrorClassifier.networkFailure)
      XCTAssertNotEqual(result.errorCode, CloudKitErrorClassifier.serverRejectedRequest)
      calledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)
    XCTAssertEqual(fakeDatabase.addCallCount, 1)
  }

  // 5. An unrelated fetch error must never trigger a create attempt.
  func testConfigureZoneDoesNotAttemptCreateForUnrelatedFetchError() {
    let fakeDatabase = FakeZoneOperationDatabase()
    fakeDatabase.fetchOutcome = .error(CKError(.networkUnavailable))
    let coordinator = CloudKitPrivateZoneCoordinator(database: fakeDatabase)

    let calledOnce = expectation(description: "completion called")
    coordinator.configureZone { result in
      XCTAssertFalse(result.success)
      XCTAssertFalse(result.zoneCreated)
      XCTAssertFalse(result.zoneAlreadyExisted)
      XCTAssertEqual(result.errorCode, CloudKitErrorClassifier.networkUnavailable)
      calledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)
    XCTAssertEqual(fakeDatabase.addCallCount, 0)
  }

  // 6. Every branch invokes completion exactly once, across every outcome
  //    exercised above plus their create-side variants.
  func testConfigureZoneCompletesExactlyOnceForEveryOutcome() {
    let scenarios: [(FakeZoneOperationDatabase.FetchOutcome, Error?)] = [
      (.zoneExists, nil),
      (.error(CKError(.zoneNotFound)), nil),
      (.error(CKError(.zoneNotFound)), CKError(.networkFailure)),
      (.error(CKError(.serverRejectedRequest)), nil),
      (.error(CKError(.serverRejectedRequest)), CKError(.networkFailure)),
      (.error(CKError(.networkUnavailable)), nil),
    ]

    for (fetchOutcome, createOutcome) in scenarios {
      let fakeDatabase = FakeZoneOperationDatabase()
      fakeDatabase.fetchOutcome = fetchOutcome
      fakeDatabase.createOutcome = createOutcome
      let coordinator = CloudKitPrivateZoneCoordinator(database: fakeDatabase)

      var completionCount = 0
      let calledOnce = expectation(description: "completion called exactly once")
      coordinator.configureZone { _ in
        completionCount += 1
        calledOnce.fulfill()
      }
      waitForExpectations(timeout: 1)
      XCTAssertEqual(completionCount, 1)
    }
  }

  // 8. Every errorCode ever surfaced by `configureZone` is drawn only from
  //    the small known symbolic vocabulary -- never a localized CloudKit
  //    message, `debugDescription`, or other free-form/raw content (which
  //    would not exactly equal one of these constants, and would contain
  //    whitespace).
  func testConfigureZoneErrorCodesNeverExposeLocalizedOrRawContent() {
    let fakeDatabase = FakeZoneOperationDatabase()
    fakeDatabase.fetchOutcome = .error(CKError(.serverRejectedRequest))
    fakeDatabase.createOutcome = CKError(.networkFailure)
    let coordinator = CloudKitPrivateZoneCoordinator(database: fakeDatabase)

    let knownCodes: Set<String> = [
      CloudKitErrorClassifier.networkUnavailable,
      CloudKitErrorClassifier.networkFailure,
      CloudKitErrorClassifier.serviceUnavailable,
      CloudKitErrorClassifier.requestRateLimited,
      CloudKitErrorClassifier.zoneBusy,
      CloudKitErrorClassifier.serverRecordChanged,
      CloudKitErrorClassifier.accountTemporarilyUnavailable,
      CloudKitErrorClassifier.notAuthenticated,
      CloudKitErrorClassifier.invalidArguments,
      CloudKitErrorClassifier.unknownItem,
      CloudKitErrorClassifier.incompatibleVersion,
      CloudKitErrorClassifier.quotaExceeded,
      CloudKitErrorClassifier.limitExceeded,
      CloudKitErrorClassifier.serverRejectedRequest,
      CloudKitErrorClassifier.unrecognizedNativeError,
    ]

    let calledOnce = expectation(description: "completion called")
    coordinator.configureZone { result in
      let code = result.errorCode ?? ""
      XCTAssertTrue(knownCodes.contains(code))
      XCTAssertFalse(code.contains(" "))
      calledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  // MARK: - Build 26 Phase 4C-1: CKKeptWisdom / CKEastSyncState schema and
  // codec tests
  //
  // Every `CKRecord` here is a plain, locally-constructed value -- no
  // `CKDatabase`, no network call, no real iCloud account. Synthetic test
  // values only, exactly as this phase requires.

  private let phase4CRevealIdA = "c947bbb4-f86a-4db3-87c9-ed5e718bbd98"
  private let phase4CRevealIdB = "affbc527-29c4-5d19-b678-1bc7f9dfb7d4"
  private let phase4CMutationId = "22222222-2222-4222-8222-222222222222"
  private let phase4CDataEpoch = "11111111-1111-4111-8111-111111111111"

  // Phase 5E: a deterministic canonical wisdomId, in the same
  // `east_wisdom_NNNN` shape `lib/data/wisdoms.dart` assigns real catalog
  // entries -- used only where a test's fixture stands in for a genuine
  // reveal of a known catalog wisdom. Every other `encodeActive` fixture in
  // this file passes `wisdomId: nil`, exercising the same optional/legacy
  // code path a pre-canonical-identity 1.0 record already relies on.
  private let phase4CWisdomIdA = "east_wisdom_0001"

  // Build 26 Phase 4E-3a: `CloudKitKeptWisdomCodec.decode` now requires the
  // caller to have already archived `record`'s own system fields (exactly
  // as `CloudKitRecordTransportCoordinator.fetchZoneChanges` itself does)
  // before decoding it. Every pre-existing decode test below uses this
  // helper -- the *real* `CloudKitOpaqueArchive.archiveSystemFields(of:)`
  // mechanism, never a fabricated placeholder string -- so these tests
  // continue to exercise the exact production archiving path.
  private func sampleSystemFields(for record: CKRecord, file: StaticString = #filePath, line: UInt = #line) -> String {
    guard let systemFields = CloudKitOpaqueArchive.archiveSystemFields(of: record) else {
      XCTFail("Expected archiveSystemFields to succeed for a synthetic CKRecord", file: file, line: line)
      return ""
    }
    return systemFields
  }

  // 1. Valid Kept encode/decode round trip (active form).
  func testKeptWisdomCodecRoundTripsActiveForm() throws {
    let record = try CloudKitKeptWisdomCodec.encodeActive(
      revealId: phase4CRevealIdA,
      wisdomText: "Be still and know.",
      wisdomId: phase4CWisdomIdA,
      revealedAtMs: 1_754_078_400_000,
      keptAtMs: 1_754_078_700_000,
      reflectionText: "A quiet thought.",
      reflectedAtMs: 1_754_078_700_000,
      updatedAtMs: 1_754_078_700_000,
      mutationId: phase4CMutationId,
      dataEpoch: phase4CDataEpoch
    )

    switch CloudKitKeptWisdomCodec.decode(record, systemFields: sampleSystemFields(for: record)) {
    case .success(let envelope):
      XCTAssertFalse(envelope.isTombstone)
      XCTAssertEqual(envelope.revealId, phase4CRevealIdA)
      XCTAssertEqual(envelope.wisdomText, "Be still and know.")
      XCTAssertEqual(envelope.wisdomId, phase4CWisdomIdA)
      XCTAssertEqual(envelope.reflectionText, "A quiet thought.")
      XCTAssertEqual(envelope.mutationId, phase4CMutationId)
      XCTAssertEqual(envelope.dataEpoch, phase4CDataEpoch)
      XCTAssertEqual(envelope.schemaVersion, CloudKitRecordSchema.keptWisdomActiveSchemaVersion)
    case .failure(let error):
      XCTFail("Expected successful decode, got \(error)")
    }
  }

  // 1b. A legacy 1.0 Kept record with no canonical wisdomId (pre-Phase-5E
  // catalog identity) must still round-trip cleanly -- `wisdomId` stays
  // `nil` end to end, never guessed or backfilled by the codec itself.
  func testKeptWisdomCodecRoundTripsActiveFormWithoutWisdomId() throws {
    let record = try CloudKitKeptWisdomCodec.encodeActive(
      revealId: phase4CRevealIdA,
      wisdomText: "Be still and know.",
      wisdomId: nil,
      revealedAtMs: 1_754_078_400_000,
      keptAtMs: 1_754_078_700_000,
      reflectionText: nil,
      reflectedAtMs: nil,
      updatedAtMs: 1_754_078_700_000,
      mutationId: phase4CMutationId,
      dataEpoch: phase4CDataEpoch
    )

    switch CloudKitKeptWisdomCodec.decode(record, systemFields: sampleSystemFields(for: record)) {
    case .success(let envelope):
      XCTAssertFalse(envelope.isTombstone)
      XCTAssertEqual(envelope.revealId, phase4CRevealIdA)
      XCTAssertEqual(envelope.wisdomText, "Be still and know.")
      XCTAssertNil(envelope.wisdomId)
    case .failure(let error):
      XCTFail("Expected successful decode, got \(error)")
    }
  }

  // 2. Valid sync-state encode/decode round trip.
  func testSyncStateCodecRoundTrips() {
    let record = CloudKitSyncStateCodec.encode(
      dataEpoch: phase4CDataEpoch,
      resetAtMs: 1_754_078_400_000,
      mutationId: phase4CMutationId
    )

    switch CloudKitSyncStateCodec.decode(record) {
    case .success(let envelope):
      XCTAssertEqual(envelope.dataEpoch, phase4CDataEpoch)
      XCTAssertEqual(envelope.resetAtMs, 1_754_078_400_000)
      XCTAssertEqual(envelope.mutationId, phase4CMutationId)
      XCTAssertEqual(envelope.schemaVersion, CloudKitRecordSchema.syncStateSchemaVersion)
    case .failure(let error):
      XCTFail("Expected successful decode, got \(error)")
    }
  }

  // 3. Deterministic record ID -- the same revealId always produces the
  // same CKRecord.ID, on every call.
  func testKeptWisdomRecordIdentityIsDeterministic() throws {
    let first = try CloudKitRecordIdentity.keptWisdomRecordID(revealId: phase4CRevealIdA)
    let second = try CloudKitRecordIdentity.keptWisdomRecordID(revealId: phase4CRevealIdA)
    XCTAssertEqual(first.recordName, second.recordName)
    XCTAssertEqual(first.zoneID, second.zoneID)
    XCTAssertEqual(first.recordName, "east-kept-\(phase4CRevealIdA)")
  }

  // 4. Different revealIds never collide, even with identical wisdom text.
  func testDifferentRevealIdsProduceDifferentRecordIdentities() throws {
    let recordA = try CloudKitKeptWisdomCodec.encodeActive(
      revealId: phase4CRevealIdA,
      wisdomText: "Be still and know.",
      wisdomId: nil,
      revealedAtMs: 1_754_078_400_000,
      keptAtMs: 1_754_078_700_000,
      reflectionText: nil,
      reflectedAtMs: nil,
      updatedAtMs: 1_754_078_700_000,
      mutationId: phase4CMutationId,
      dataEpoch: phase4CDataEpoch
    )
    let recordB = try CloudKitKeptWisdomCodec.encodeActive(
      revealId: phase4CRevealIdB,
      wisdomText: "Be still and know.",
      wisdomId: nil,
      revealedAtMs: 1_754_078_400_000,
      keptAtMs: 1_754_078_700_000,
      reflectionText: nil,
      reflectedAtMs: nil,
      updatedAtMs: 1_754_078_700_000,
      mutationId: phase4CMutationId,
      dataEpoch: phase4CDataEpoch
    )

    XCTAssertNotEqual(recordA.recordID.recordName, recordB.recordID.recordName)
  }

  // 5. A record in the wrong (including default) zone is rejected.
  func testKeptWisdomCodecRejectsWrongZone() throws {
    let wrongZoneID = CKRecordZone.default().zoneID
    let recordID = CKRecord.ID(recordName: "east-kept-\(phase4CRevealIdA)", zoneID: wrongZoneID)
    let record = CKRecord(recordType: CloudKitRecordSchema.keptWisdomRecordType, recordID: recordID)
    record[CloudKitRecordSchema.KeptWisdomField.revealId] = phase4CRevealIdA as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.wisdomText] = "Be still and know." as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.revealedAtMs] = Int64(1_754_078_400_000) as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.keptAtMs] = Int64(1_754_078_700_000) as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.updatedAtMs] = Int64(1_754_078_700_000) as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.mutationId] = phase4CMutationId as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.dataEpoch] = phase4CDataEpoch as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.schemaVersion] =
      CloudKitRecordSchema.keptWisdomActiveSchemaVersion as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.isTombstone] = false as CKRecordValue

    switch CloudKitKeptWisdomCodec.decode(record, systemFields: sampleSystemFields(for: record)) {
    case .success:
      XCTFail("Expected a wrong-zone rejection")
    case .failure(let error):
      XCTAssertEqual(error, .wrongZone)
    }
  }

  // 6. An unrecognized/wrong record type is rejected.
  func testSyncStateCodecRejectsWrongRecordType() {
    let recordID = CloudKitRecordIdentity.syncStateRecordID()
    let record = CKRecord(recordType: CloudKitRecordSchema.keptWisdomRecordType, recordID: recordID)
    record[CloudKitRecordSchema.SyncStateField.dataEpoch] = phase4CDataEpoch as CKRecordValue
    record[CloudKitRecordSchema.SyncStateField.mutationId] = phase4CMutationId as CKRecordValue
    record[CloudKitRecordSchema.SyncStateField.schemaVersion] =
      CloudKitRecordSchema.syncStateSchemaVersion as CKRecordValue

    switch CloudKitSyncStateCodec.decode(record) {
    case .success:
      XCTFail("Expected a wrong-record-type rejection")
    case .failure(let error):
      XCTAssertEqual(error, .wrongRecordType)
    }
  }

  // 7. A malformed field type is rejected.
  func testKeptWisdomCodecRejectsMalformedFieldType() throws {
    let record = try CloudKitKeptWisdomCodec.encodeActive(
      revealId: phase4CRevealIdA,
      wisdomText: "Be still and know.",
      wisdomId: nil,
      revealedAtMs: 1_754_078_400_000,
      keptAtMs: 1_754_078_700_000,
      reflectionText: nil,
      reflectedAtMs: nil,
      updatedAtMs: 1_754_078_700_000,
      mutationId: phase4CMutationId,
      dataEpoch: phase4CDataEpoch
    )
    // wisdomText is required to be a String; store a number instead.
    record[CloudKitRecordSchema.KeptWisdomField.wisdomText] = 12345 as CKRecordValue

    switch CloudKitKeptWisdomCodec.decode(record, systemFields: sampleSystemFields(for: record)) {
    case .success:
      XCTFail("Expected a malformed-field rejection")
    case .failure(let error):
      XCTAssertEqual(error, .malformedField(CloudKitRecordSchema.KeptWisdomField.wisdomText))
    }
  }

  // 7b. Build 26 Phase 4H-2: a fetched record carrying `reflectionText`
  // without a matching `reflectedAtMs` (or vice versa) is rejected, never
  // silently coerced into a one-sided Reflection. This is the exact shape
  // this phase's own real-device investigation identified as the one
  // structurally new condition a second device's Reflection edit could
  // introduce that the original uploading device's own records never
  // exercised before.
  func testKeptWisdomCodecRejectsInconsistentReflectionFieldsOnDecode() throws {
    let record = try CloudKitKeptWisdomCodec.encodeActive(
      revealId: phase4CRevealIdA,
      wisdomText: "Be still and know.",
      wisdomId: nil,
      revealedAtMs: 1_754_078_400_000,
      keptAtMs: 1_754_078_700_000,
      reflectionText: nil,
      reflectedAtMs: nil,
      updatedAtMs: 1_754_078_700_000,
      mutationId: phase4CMutationId,
      dataEpoch: phase4CDataEpoch
    )
    // Simulate a record that only ever set `reflectionText` -- bypassing
    // `encodeActive`'s own paired-fields guard, exactly as a differently
    // written (or partially failed) save from another device could
    // theoretically produce on the server.
    record[CloudKitRecordSchema.KeptWisdomField.reflectionText] = "A quiet thought." as CKRecordValue

    switch CloudKitKeptWisdomCodec.decode(record, systemFields: sampleSystemFields(for: record)) {
    case .success:
      XCTFail("Expected an inconsistent-reflection-fields rejection")
    case .failure(let error):
      XCTAssertEqual(error, .inconsistentReflectionFields)
    }
  }

  // 8. A record-name/revealId mismatch is rejected.
  func testKeptWisdomCodecRejectsRecordNameMismatch() throws {
    let record = try CloudKitKeptWisdomCodec.encodeActive(
      revealId: phase4CRevealIdA,
      wisdomText: "Be still and know.",
      wisdomId: nil,
      revealedAtMs: 1_754_078_400_000,
      keptAtMs: 1_754_078_700_000,
      reflectionText: nil,
      reflectedAtMs: nil,
      updatedAtMs: 1_754_078_700_000,
      mutationId: phase4CMutationId,
      dataEpoch: phase4CDataEpoch
    )
    // The record's own identity (recordName) still says revealIdA, but the
    // revealId field now claims to be a different, equally-valid occurrence.
    record[CloudKitRecordSchema.KeptWisdomField.revealId] = phase4CRevealIdB as CKRecordValue

    switch CloudKitKeptWisdomCodec.decode(record, systemFields: sampleSystemFields(for: record)) {
    case .success:
      XCTFail("Expected a record-name-mismatch rejection")
    case .failure(let error):
      XCTAssertEqual(error, .recordNameMismatch)
    }
  }

  // 9. Tombstone behavior: encodes with no content field at all, decodes
  // back with every content field nil, and a real tombstone carrying a
  // forbidden content field is itself rejected.
  func testKeptWisdomCodecTombstoneBehavior() throws {
    let tombstoneRecord = try CloudKitKeptWisdomCodec.encodeTombstone(
      revealId: phase4CRevealIdA,
      deletedAtMs: 1_754_078_800_000,
      updatedAtMs: 1_754_078_800_000,
      mutationId: phase4CMutationId,
      dataEpoch: phase4CDataEpoch
    )

    XCTAssertNil(tombstoneRecord[CloudKitRecordSchema.KeptWisdomField.wisdomText])
    XCTAssertNil(tombstoneRecord[CloudKitRecordSchema.KeptWisdomField.revealId])

    switch CloudKitKeptWisdomCodec.decode(
      tombstoneRecord, systemFields: sampleSystemFields(for: tombstoneRecord)
    ) {
    case .success(let envelope):
      XCTAssertTrue(envelope.isTombstone)
      XCTAssertNil(envelope.wisdomText)
      XCTAssertNil(envelope.revealId)
      XCTAssertNotNil(envelope.deletedAtMs)
      XCTAssertEqual(envelope.recordName, "east-kept-\(phase4CRevealIdA)")
    case .failure(let error):
      XCTFail("Expected successful tombstone decode, got \(error)")
    }

    // A tombstone-shaped record that also carries a forbidden content
    // field indicates corruption or tampering -- never tolerated. This
    // deliberately only re-adds `wisdomText` (not the other three core
    // legacy fields `legacyActivePayloadShape` also inspects), so the
    // record is *also* a partial/incoherent legacy-shape subset -- by
    // that function's own documented, deliberate check order (identity
    // via `revealId` is validated before `wisdomText`), the specific
    // field named in the resulting error is `revealId`, not `wisdomText`.
    // This assertion intentionally only proves the fail-closed error
    // *category*, not which of possibly several simultaneously-forbidden
    // fields is named first -- that ordering is `legacyActivePayloadShape`'s
    // own implementation detail, not part of this test's contract.
    tombstoneRecord[CloudKitRecordSchema.KeptWisdomField.wisdomText] = "smuggled content" as CKRecordValue
    switch CloudKitKeptWisdomCodec.decode(
      tombstoneRecord, systemFields: sampleSystemFields(for: tombstoneRecord)
    ) {
    case .success:
      XCTFail("Expected rejection of a tombstone carrying forbidden content")
    case .failure(let error):
      guard case .forbiddenFieldOnTombstone = error else {
        return XCTFail("Expected a forbiddenFieldOnTombstone rejection, got \(error)")
      }
    }
  }

  // MARK: - Build 26 Phase 4H-4: tombstone field-retention writer bug +
  // legacy full-form tombstone compatibility tests.
  //
  // Supersedes the earlier, narrower Phase 4H-3 "redundant revealId only"
  // rule (real CloudKit Dashboard evidence proved the already-stored
  // Development tombstone retains its entire historical active payload --
  // `revealId`, `wisdomText`, `revealedAtMs`, `keptAtMs` -- not merely
  // `revealId`). Root cause, proven below: `CloudKitRecordTransportCoordinator
  // .modifyRecords`'s baseline-merge step (used whenever a save carries a
  // `previousSystemFields` value, i.e. updating an already-synced record)
  // reconstructs `baseline` from system fields alone (no user field
  // values), then previously copied only `input.record.allKeys()` onto
  // it. Because `encodeTombstone` merely never *mentioned* the forbidden
  // active fields (rather than explicitly clearing them), those fields
  // never appeared in `allKeys()` either, so the removal was silently
  // never sent to CloudKit at all, leaving the server's old values intact.
  // Fixed by (1) `encodeTombstone` now explicitly assigning `nil` to every
  // forbidden field, and (2) the merge loop now iterating
  // `changedKeys()`, which -- unlike `allKeys()` -- includes explicitly
  // cleared keys.

  // 9b. Build 26 Phase 4H-5 Task 2.A: a freshly `encodeTombstone`d record
  // contains only the allowed tombstone fields, and -- critically, this is
  // what actually makes the writer fix effective -- every field that must
  // be removed from an existing active server record (`revealId`,
  // `wisdomText`, `revealedAtMs`, `keptAtMs`, `reflectionText`,
  // `reflectedAtMs`) is registered in the record's own `changedKeys()` as
  // an explicit removal. `allKeys()` correctly does NOT need to (and does
  // not) contain a nil'd field at all -- `allKeys()` and `changedKeys()`
  // are proven here to disagree on exactly these six keys, which is the
  // whole reason the transport's baseline-merge loop had to switch from
  // one to the other.
  func testKeptWisdomCodecTombstoneEncodeExplicitlyClearsForbiddenFields() throws {
    let record = try CloudKitKeptWisdomCodec.encodeTombstone(
      revealId: phase4CRevealIdA, deletedAtMs: 1, updatedAtMs: 1,
      mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)

    for field in CloudKitRecordSchema.KeptWisdomField.forbiddenOnTombstone {
      XCTAssertNil(record[field], "Expected '\(field)' to be absent from a freshly encoded tombstone")
      XCTAssertTrue(
        record.changedKeys().contains(field),
        "Expected '\(field)' to be an explicit removal (changedKeys), not merely untouched")
      XCTAssertFalse(
        record.allKeys().contains(field),
        "Expected '\(field)' to be absent from allKeys() -- a nil'd field never needs to appear there")
    }
    XCTAssertEqual(record[CloudKitRecordSchema.KeptWisdomField.isTombstone] as? Bool, true)
    XCTAssertNotNil(record[CloudKitRecordSchema.KeptWisdomField.deletedAtMs])
    XCTAssertNotNil(record[CloudKitRecordSchema.KeptWisdomField.updatedAtMs])
    XCTAssertNotNil(record[CloudKitRecordSchema.KeptWisdomField.mutationId])
    XCTAssertNotNil(record[CloudKitRecordSchema.KeptWisdomField.dataEpoch])
    XCTAssertNotNil(record[CloudKitRecordSchema.KeptWisdomField.schemaVersion])
  }

  // 9b-i. Build 26 Phase 4H-5 Task 2.B: active encode WITH a Reflection --
  // the Reflection fields are present with their real values (the
  // already-correct path, unaffected by this fix, kept as an explicit
  // sibling assertion alongside 9b-ii below for direct comparison).
  func testKeptWisdomCodecActiveEncodeWithReflectionSetsReflectionFields() throws {
    let record = try CloudKitKeptWisdomCodec.encodeActive(
      revealId: phase4CRevealIdA, wisdomText: "Be still and know.",
      wisdomId: nil,
      revealedAtMs: 1, keptAtMs: 2,
      reflectionText: "A quiet thought.", reflectedAtMs: 3,
      updatedAtMs: 3, mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)

    XCTAssertEqual(record[CloudKitRecordSchema.KeptWisdomField.reflectionText] as? String, "A quiet thought.")
    XCTAssertEqual(record[CloudKitRecordSchema.KeptWisdomField.reflectedAtMs] as? Int64, 3)
    XCTAssertTrue(record.changedKeys().contains(CloudKitRecordSchema.KeptWisdomField.reflectionText))
    XCTAssertTrue(record.changedKeys().contains(CloudKitRecordSchema.KeptWisdomField.reflectedAtMs))
  }

  // 9b-ii. Build 26 Phase 4H-5 Task 2.C: active encode WITHOUT a
  // Reflection -- `reflectionText`/`reflectedAtMs` are nil (unchanged
  // observable behavior) AND now explicit removals in `changedKeys()`
  // (the actual fix), never merely absent from `allKeys()`. This is the
  // exact sibling of the tombstone writer fix, applied to the "Reflection
  // removed from an active occurrence" case your own prior audit flagged
  // as the same bug class.
  func testKeptWisdomCodecActiveEncodeWithoutReflectionExplicitlyClearsReflectionFields() throws {
    let record = try CloudKitKeptWisdomCodec.encodeActive(
      revealId: phase4CRevealIdA, wisdomText: "Be still and know.",
      wisdomId: nil,
      revealedAtMs: 1, keptAtMs: 2,
      reflectionText: nil, reflectedAtMs: nil,
      updatedAtMs: 3, mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)

    XCTAssertNil(record[CloudKitRecordSchema.KeptWisdomField.reflectionText])
    XCTAssertNil(record[CloudKitRecordSchema.KeptWisdomField.reflectedAtMs])
    XCTAssertTrue(
      record.changedKeys().contains(CloudKitRecordSchema.KeptWisdomField.reflectionText),
      "Expected reflectionText to be an explicit removal (changedKeys), not merely untouched")
    XCTAssertTrue(
      record.changedKeys().contains(CloudKitRecordSchema.KeptWisdomField.reflectedAtMs),
      "Expected reflectedAtMs to be an explicit removal (changedKeys), not merely untouched")
    XCTAssertFalse(record.allKeys().contains(CloudKitRecordSchema.KeptWisdomField.reflectionText))
    XCTAssertFalse(record.allKeys().contains(CloudKitRecordSchema.KeptWisdomField.reflectedAtMs))
  }

  // 9c. Tombstone identity remains tied to the correct occurrence -- two
  // different revealIds never produce the same tombstone recordName.
  func testKeptWisdomCodecDifferentRevealIdsProduceDifferentTombstoneRecordNames() throws {
    let recordA = try CloudKitKeptWisdomCodec.encodeTombstone(
      revealId: phase4CRevealIdA, deletedAtMs: 1, updatedAtMs: 1,
      mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)
    let recordB = try CloudKitKeptWisdomCodec.encodeTombstone(
      revealId: phase4CRevealIdB, deletedAtMs: 1, updatedAtMs: 1,
      mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)

    XCTAssertNotEqual(recordA.recordID.recordName, recordB.recordID.recordName)
  }

  // 9d. THE decisive live-writer-bug proof (Task 2): starts from an
  // EXISTING, already-synced active `CKRecord` (with a Reflection, so
  // every forbidden field has a real, non-nil historical value), archives
  // its system fields exactly as a real prior save would have left them,
  // then runs the exact production tombstone-conversion path --
  // `CloudKitRecordTransportCoordinator.modifyRecords` with that archived
  // value as `previousSystemFields`. Inspects the *actual* `CKRecord`
  // hand ed to `CKModifyRecordsOperation` (via `FakeRecordTransportDatabase
  // .addedOperations`) to prove every forbidden field is both nil AND
  // registered in `changedKeys()` -- i.e. this fix's baseline-merge
  // `changedKeys()` correctly propagates `encodeTombstone`'s explicit
  // removals onto the record actually sent over the network. Before this
  // turn's fix, none of these six keys would have appeared in the merged
  // record's `changedKeys()` at all, which is precisely how the old
  // active values survived on the real tombstone this phase investigated.
  func testModifyRecordsBaselineMergePropagatesTombstoneFieldRemovalsOntoSavedRecord() throws {
    let existingActiveRecord = try CloudKitKeptWisdomCodec.encodeActive(
      revealId: phase4CRevealIdA,
      wisdomText: "Be still and know.",
      wisdomId: nil,
      revealedAtMs: 1, keptAtMs: 1,
      reflectionText: "A quiet thought.", reflectedAtMs: 2,
      updatedAtMs: 2, mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)
    let previousSystemFields = sampleSystemFields(for: existingActiveRecord)

    let tombstoneRecord = try CloudKitKeptWisdomCodec.encodeTombstone(
      revealId: phase4CRevealIdA, deletedAtMs: 3, updatedAtMs: 3,
      mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)

    let fakeDatabase = FakeRecordTransportDatabase()
    fakeDatabase.perRecordModifyErrors = [nil]
    let coordinator = CloudKitRecordTransportCoordinator(database: fakeDatabase)

    let calledOnce = expectation(description: "completion called")
    coordinator.modifyRecords(
      [
        CloudKitRecordTransportCoordinator.ModifyInput(
          record: tombstoneRecord, previousSystemFields: previousSystemFields)
      ]
    ) { _ in calledOnce.fulfill() }
    waitForExpectations(timeout: 1)

    guard let modifyOperation = fakeDatabase.addedOperations.first as? CKModifyRecordsOperation,
      let savedRecord = modifyOperation.recordsToSave?.first
    else {
      return XCTFail("Expected a CKModifyRecordsOperation carrying the merged tombstone record")
    }

    for field in CloudKitRecordSchema.KeptWisdomField.forbiddenOnTombstone {
      XCTAssertNil(savedRecord[field], "Expected '\(field)' to be nil on the record actually saved")
      XCTAssertTrue(
        savedRecord.changedKeys().contains(field),
        "Expected '\(field)' to be an explicit removal on the record actually sent to CloudKit")
    }
    XCTAssertEqual(savedRecord[CloudKitRecordSchema.KeptWisdomField.isTombstone] as? Bool, true)
    XCTAssertEqual(savedRecord.recordID.recordName, existingActiveRecord.recordID.recordName)
  }

  // 9d-i. Build 26 Phase 4H-5 Task 2.D (sibling case): the exact same
  // baseline-merge proof as immediately above, but for "Reflection removed
  // from an already-synced active occurrence" rather than "active
  // deleted." Starts from an existing active record WITH a Reflection,
  // archives its system fields, then saves a fresh active encode WITHOUT a
  // Reflection over that baseline via the real `modifyRecords` path.
  // Inspects the actual `CKRecord` hand ed to `CKModifyRecordsOperation` --
  // not just the standalone `encodeActive` output -- to prove the
  // Reflection removal survives the same baseline-merge step the
  // tombstone fix already had to correct.
  func testModifyRecordsBaselineMergePropagatesReflectionRemovalOntoSavedRecord() throws {
    let existingActiveRecordWithReflection = try CloudKitKeptWisdomCodec.encodeActive(
      revealId: phase4CRevealIdA,
      wisdomText: "Be still and know.",
      wisdomId: nil,
      revealedAtMs: 1, keptAtMs: 1,
      reflectionText: "A quiet thought.", reflectedAtMs: 2,
      updatedAtMs: 2, mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)
    let previousSystemFields = sampleSystemFields(for: existingActiveRecordWithReflection)

    let updatedActiveRecordWithoutReflection = try CloudKitKeptWisdomCodec.encodeActive(
      revealId: phase4CRevealIdA,
      wisdomText: "Be still and know.",
      wisdomId: nil,
      revealedAtMs: 1, keptAtMs: 1,
      reflectionText: nil, reflectedAtMs: nil,
      updatedAtMs: 3, mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)

    let fakeDatabase = FakeRecordTransportDatabase()
    fakeDatabase.perRecordModifyErrors = [nil]
    let coordinator = CloudKitRecordTransportCoordinator(database: fakeDatabase)

    let calledOnce = expectation(description: "completion called")
    coordinator.modifyRecords(
      [
        CloudKitRecordTransportCoordinator.ModifyInput(
          record: updatedActiveRecordWithoutReflection, previousSystemFields: previousSystemFields)
      ]
    ) { _ in calledOnce.fulfill() }
    waitForExpectations(timeout: 1)

    guard let modifyOperation = fakeDatabase.addedOperations.first as? CKModifyRecordsOperation,
      let savedRecord = modifyOperation.recordsToSave?.first
    else {
      return XCTFail("Expected a CKModifyRecordsOperation carrying the merged active record")
    }

    XCTAssertNil(savedRecord[CloudKitRecordSchema.KeptWisdomField.reflectionText])
    XCTAssertNil(savedRecord[CloudKitRecordSchema.KeptWisdomField.reflectedAtMs])
    XCTAssertTrue(
      savedRecord.changedKeys().contains(CloudKitRecordSchema.KeptWisdomField.reflectionText),
      "Expected reflectionText to be an explicit removal on the record actually sent to CloudKit")
    XCTAssertTrue(
      savedRecord.changedKeys().contains(CloudKitRecordSchema.KeptWisdomField.reflectedAtMs),
      "Expected reflectedAtMs to be an explicit removal on the record actually sent to CloudKit")
    // The rest of the active payload is untouched by this fix.
    XCTAssertEqual(savedRecord[CloudKitRecordSchema.KeptWisdomField.wisdomText] as? String, "Be still and know.")
    XCTAssertEqual(savedRecord[CloudKitRecordSchema.KeptWisdomField.isTombstone] as? Bool, false)
  }

  // 9e. Canonical tombstone (no retained legacy payload) still decodes
  // successfully -- the expanded legacy rule below must not regress the
  // ordinary, already-fixed case.
  func testKeptWisdomCodecDecodesCanonicalTombstoneWithNoLegacyPayload() throws {
    let record = try CloudKitKeptWisdomCodec.encodeTombstone(
      revealId: phase4CRevealIdA, deletedAtMs: 1, updatedAtMs: 1,
      mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)

    switch CloudKitKeptWisdomCodec.decode(record, systemFields: sampleSystemFields(for: record)) {
    case .success(let envelope):
      XCTAssertTrue(envelope.isTombstone)
      XCTAssertNil(envelope.revealId)
      XCTAssertNil(envelope.wisdomText)
    case .failure(let error):
      XCTFail("Expected the canonical tombstone shape to decode successfully, got \(error)")
    }
  }

  // 9f. The proven legacy full-form shape (no Reflection at deletion time,
  // matching the actual CloudKit Dashboard evidence this phase
  // investigated: revealId/wisdomText/revealedAtMs/keptAtMs all present
  // and coherent, Reflection fields empty) decodes successfully, and
  // none of the retained historical payload reaches the envelope: no
  // resurrection risk.
  func testKeptWisdomCodecAcceptsLegacyFullFormTombstoneWithoutReflection() throws {
    let record = try CloudKitKeptWisdomCodec.encodeTombstone(
      revealId: phase4CRevealIdA, deletedAtMs: 1_754_078_800_000, updatedAtMs: 1_754_078_800_000,
      mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)
    // Simulate the already-stored legacy record: the writer bug retained
    // the entire historical active payload this occurrence had, minus
    // Reflection (this occurrence never had one before deletion).
    record[CloudKitRecordSchema.KeptWisdomField.revealId] = phase4CRevealIdA as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.wisdomText] = "Be still and know." as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.revealedAtMs] = Int64(1) as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.keptAtMs] = Int64(2) as CKRecordValue

    switch CloudKitKeptWisdomCodec.decode(record, systemFields: sampleSystemFields(for: record)) {
    case .success(let envelope):
      XCTAssertTrue(envelope.isTombstone)
      XCTAssertEqual(envelope.recordName, "east-kept-\(phase4CRevealIdA)")
      XCTAssertNotNil(envelope.deletedAtMs)
      // No resurrection: none of the retained legacy payload reaches the
      // decoded envelope.
      XCTAssertNil(envelope.revealId)
      XCTAssertNil(envelope.wisdomText)
      XCTAssertNil(envelope.revealedAtMs)
      XCTAssertNil(envelope.keptAtMs)
      XCTAssertNil(envelope.reflectionText)
      XCTAssertNil(envelope.reflectedAtMs)
    case .failure(let error):
      XCTFail("Expected the known legacy full-form tombstone shape to decode successfully, got \(error)")
    }
  }

  // 9g. Task 4's explicit question: a Reflection-bearing historical
  // snapshot is a legitimate consequence of the same writer bug (if a
  // Reflection existed at deletion time), so it must also be accepted --
  // as one coherent snapshot, both Reflection fields present and valid,
  // never resurrected.
  func testKeptWisdomCodecAcceptsLegacyFullFormTombstoneWithReflection() throws {
    let record = try CloudKitKeptWisdomCodec.encodeTombstone(
      revealId: phase4CRevealIdA, deletedAtMs: 1, updatedAtMs: 1,
      mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)
    record[CloudKitRecordSchema.KeptWisdomField.revealId] = phase4CRevealIdA as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.wisdomText] = "Be still and know." as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.revealedAtMs] = Int64(1) as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.keptAtMs] = Int64(2) as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.reflectionText] = "A quiet thought." as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.reflectedAtMs] = Int64(3) as CKRecordValue

    switch CloudKitKeptWisdomCodec.decode(record, systemFields: sampleSystemFields(for: record)) {
    case .success(let envelope):
      XCTAssertTrue(envelope.isTombstone)
      XCTAssertNil(envelope.reflectionText)
      XCTAssertNil(envelope.reflectedAtMs)
      XCTAssertNil(envelope.wisdomText)
      XCTAssertNil(envelope.revealId)
    case .failure(let error):
      XCTFail(
        "Expected the known legacy full-form-with-Reflection tombstone shape to decode "
          + "successfully, got \(error)")
    }
  }

  // 9h. Fail-closed against tampering/corruption: a mismatched revealId
  // (not the one this record's own recordName derives from) is still
  // rejected even when the rest of the legacy payload is otherwise
  // internally coherent.
  func testKeptWisdomCodecRejectsLegacyFullFormTombstoneWithMismatchedRevealId() throws {
    let record = try CloudKitKeptWisdomCodec.encodeTombstone(
      revealId: phase4CRevealIdA, deletedAtMs: 1, updatedAtMs: 1,
      mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)
    record[CloudKitRecordSchema.KeptWisdomField.revealId] = phase4CRevealIdB as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.wisdomText] = "Be still and know." as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.revealedAtMs] = Int64(1) as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.keptAtMs] = Int64(2) as CKRecordValue

    switch CloudKitKeptWisdomCodec.decode(record, systemFields: sampleSystemFields(for: record)) {
    case .success:
      XCTFail("Expected rejection of a tombstone whose revealId does not match its own recordName")
    case .failure(let error):
      XCTAssertEqual(error, .forbiddenFieldOnTombstone(CloudKitRecordSchema.KeptWisdomField.revealId))
    }
  }

  // 9i. "Do not add one forbidden-field exception at a time": a *partial*
  // legacy shape -- only some of the four core fields present -- is never
  // a coherent historical snapshot (the writer bug always retains all
  // four together, since `encodeActive` always sets them together), so it
  // fails closed, never silently tolerated.
  func testKeptWisdomCodecRejectsPartialLegacyTombstonePayload() throws {
    let record = try CloudKitKeptWisdomCodec.encodeTombstone(
      revealId: phase4CRevealIdA, deletedAtMs: 1, updatedAtMs: 1,
      mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)
    // Only revealId and wisdomText retained -- never a shape the real
    // writer bug (or a valid active record) could produce alone.
    record[CloudKitRecordSchema.KeptWisdomField.revealId] = phase4CRevealIdA as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.wisdomText] = "Be still and know." as CKRecordValue

    switch CloudKitKeptWisdomCodec.decode(record, systemFields: sampleSystemFields(for: record)) {
    case .success:
      XCTFail("Expected rejection of a partial legacy payload")
    case .failure(let error):
      XCTAssertEqual(error, .forbiddenFieldOnTombstone(CloudKitRecordSchema.KeptWisdomField.revealedAtMs))
    }
  }

  // 9j. An unpaired Reflection field alongside an otherwise-coherent
  // legacy snapshot still fails closed -- the same internal-consistency
  // rule `decodeActive` already applies to `reflectionText`/`reflectedAtMs`
  // is not relaxed for the legacy path.
  func testKeptWisdomCodecRejectsLegacyTombstoneWithUnpairedReflectionField() throws {
    let record = try CloudKitKeptWisdomCodec.encodeTombstone(
      revealId: phase4CRevealIdA, deletedAtMs: 1, updatedAtMs: 1,
      mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)
    record[CloudKitRecordSchema.KeptWisdomField.revealId] = phase4CRevealIdA as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.wisdomText] = "Be still and know." as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.revealedAtMs] = Int64(1) as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.keptAtMs] = Int64(2) as CKRecordValue
    // reflectionText present without a matching reflectedAtMs.
    record[CloudKitRecordSchema.KeptWisdomField.reflectionText] = "A quiet thought." as CKRecordValue

    switch CloudKitKeptWisdomCodec.decode(record, systemFields: sampleSystemFields(for: record)) {
    case .success:
      XCTFail("Expected rejection of an unpaired Reflection field on a legacy tombstone")
    case .failure(let error):
      XCTAssertEqual(error, .forbiddenFieldOnTombstone(CloudKitRecordSchema.KeptWisdomField.reflectionText))
    }
  }

  // 9k. A coherent legacy core payload alongside a genuinely unrelated
  // forbidden combination (a mismatched revealId, which independently
  // fails the identity check) still fails closed -- accepting the known
  // legacy shape never broadens into a generic "ignore forbidden fields"
  // rule.
  func testKeptWisdomCodecRejectsLegacyTombstoneWithUnrelatedForbiddenCombination() throws {
    let record = try CloudKitKeptWisdomCodec.encodeTombstone(
      revealId: phase4CRevealIdA, deletedAtMs: 1, updatedAtMs: 1,
      mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)
    record[CloudKitRecordSchema.KeptWisdomField.revealId] = phase4CRevealIdA as CKRecordValue
    // A malformed (non-String) wisdomText -- never tolerated regardless of
    // the rest of the payload's coherence.
    record[CloudKitRecordSchema.KeptWisdomField.wisdomText] = 12345 as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.revealedAtMs] = Int64(1) as CKRecordValue
    record[CloudKitRecordSchema.KeptWisdomField.keptAtMs] = Int64(2) as CKRecordValue

    switch CloudKitKeptWisdomCodec.decode(record, systemFields: sampleSystemFields(for: record)) {
    case .success:
      XCTFail("Expected rejection of a malformed field within an otherwise legacy-shaped payload")
    case .failure(let error):
      XCTAssertEqual(error, .forbiddenFieldOnTombstone(CloudKitRecordSchema.KeptWisdomField.wisdomText))
    }
  }

  // 9l. Cross-device flow at the exact archive-then-decode sequence
  // `CloudKitRecordTransportCoordinator.fetchZoneChanges`'s own
  // `recordWasChangedBlock` runs for a `CKKeptWisdom` record (see this file's
  // own disclosed `FakeRecordTransportDatabase` limitation earlier --
  // `CKServerChangeToken` cannot be constructed offline, and neither a
  // genuinely successful fetch nor this specific decode-success case can
  // be asserted through that fake's result, because both a truly
  // undecodable record and a missing final token collapse to the exact
  // same `unrecognizedNativeError` string): "device A" deletes an
  // occurrence (producing, via the now-fixed writer, a canonical
  // tombstone with no retained payload); "device B"'s fetch-callback
  // archive-then-decode sequence must not treat it as undecodable.
  func testKeptWisdomCodecFetchDecodesTombstoneWithoutUnrecognizedNativeError() throws {
    // "Device A": deletes revealId A via the fixed writer.
    let record = try CloudKitKeptWisdomCodec.encodeTombstone(
      revealId: phase4CRevealIdA, deletedAtMs: 1, updatedAtMs: 1,
      mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)

    // "Device B": exactly `recordWasChangedBlock`'s own sequence for a
    // CKKeptWisdom record.
    guard let systemFields = CloudKitOpaqueArchive.archiveSystemFields(of: record) else {
      return XCTFail("Expected archiveSystemFields to succeed for a well-formed tombstone record")
    }
    switch CloudKitKeptWisdomCodec.decode(record, systemFields: systemFields) {
    case .success(let envelope):
      XCTAssertTrue(envelope.isTombstone)
    case .failure(let error):
      XCTFail(
        "Expected device B's fetch to decode device A's tombstone without "
          + "collapsing to unrecognizedNativeError, got \(error)")
    }
  }

  // 10. No content ever appears in safe error output -- a decode failure's
  // associated value is always one of this schema's own field-name
  // constants, never the malformed value itself.
  func testKeptWisdomCodecErrorsNeverExposeFieldContent() throws {
    let record = try CloudKitKeptWisdomCodec.encodeActive(
      revealId: phase4CRevealIdA,
      wisdomText: "This exact wisdom text must never appear in a decode error.",
      wisdomId: nil,
      revealedAtMs: 1_754_078_400_000,
      keptAtMs: 1_754_078_700_000,
      reflectionText: "This exact reflection text must never appear either.",
      reflectedAtMs: 1_754_078_700_000,
      updatedAtMs: 1_754_078_700_000,
      mutationId: phase4CMutationId,
      dataEpoch: phase4CDataEpoch
    )
    record[CloudKitRecordSchema.KeptWisdomField.wisdomText] = 999 as CKRecordValue

    switch CloudKitKeptWisdomCodec.decode(record, systemFields: sampleSystemFields(for: record)) {
    case .success:
      XCTFail("Expected a malformed-field rejection")
    case .failure(let error):
      guard case .malformedField(let fieldName) = error else {
        XCTFail("Expected .malformedField, got \(error)")
        return
      }
      // The error carries only the field's *name* -- one of this file's
      // own known constants -- never any field's actual (or malformed)
      // value.
      XCTAssertEqual(fieldName, CloudKitRecordSchema.KeptWisdomField.wisdomText)
      XCTAssertFalse(fieldName.contains("wisdom text must never appear"))
    }
  }

  // MARK: - Build 26 Phase 4E-3a: fetched CloudKit system-fields tests
  //
  // These prove the archive/decode mechanism itself (fully offline-testable:
  // `CloudKitOpaqueArchive.archiveSystemFields`/`unarchiveSystemFields` need
  // only a locally-constructed `CKRecord`, never a real `CKServerChangeToken`
  // or a live CloudKit fetch). A genuine end-to-end
  // `fetchZoneChanges(...) -> .success` assertion carrying these values is
  // not reachable from this offline test target for the same, already
  // disclosed reason noted at the top of the Phase 4C-2 transport section
  // below (`CKServerChangeToken` has no public initializer) -- these tests
  // instead exercise every step up to and including
  // `CloudKitKeptWisdomCodec.decode(_:systemFields:)`, which is exactly
  // where `CloudKitRecordTransportCoordinator.fetchZoneChanges` itself calls
  // this mechanism.

  // 1. An active CKKeptWisdom record's system fields archive successfully
  // and are non-empty -- the same precondition `fetchZoneChanges` itself
  // requires before it will ever decode a changed record.
  func testActiveKeptWisdomRecordSystemFieldsAreArchiveable() throws {
    let record = try CloudKitKeptWisdomCodec.encodeActive(
      revealId: phase4CRevealIdA, wisdomText: "Be still and know.",
      wisdomId: nil,
      revealedAtMs: 1, keptAtMs: 1, reflectionText: nil, reflectedAtMs: nil,
      updatedAtMs: 1, mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)

    guard let systemFields = CloudKitOpaqueArchive.archiveSystemFields(of: record) else {
      return XCTFail("Expected archiveSystemFields to succeed for an active record")
    }
    XCTAssertFalse(systemFields.isEmpty)
  }

  // 2. A soft-tombstone CKKeptWisdom record is still a real, addressable
  // CKRecord -- its system fields archive identically to an active record's.
  func testSoftTombstoneKeptWisdomRecordSystemFieldsAreArchiveable() throws {
    let record = try CloudKitKeptWisdomCodec.encodeTombstone(
      revealId: phase4CRevealIdA, deletedAtMs: 1, updatedAtMs: 1,
      mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)

    guard let systemFields = CloudKitOpaqueArchive.archiveSystemFields(of: record) else {
      return XCTFail("Expected archiveSystemFields to succeed for a soft-tombstone record")
    }
    XCTAssertFalse(systemFields.isEmpty)
  }

  // 3. The archived system-fields blob round-trips through the existing
  // opaque archive mechanism -- unarchiving it recovers a CKRecord carrying
  // the exact same identity, for both the active and soft-tombstone forms.
  func testKeptWisdomSystemFieldsRoundTripThroughOpaqueArchiveForBothForms() throws {
    let activeRecord = try CloudKitKeptWisdomCodec.encodeActive(
      revealId: phase4CRevealIdA, wisdomText: "Be still and know.",
      wisdomId: nil,
      revealedAtMs: 1, keptAtMs: 1, reflectionText: nil, reflectedAtMs: nil,
      updatedAtMs: 1, mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)
    guard let archivedActive = CloudKitOpaqueArchive.archiveSystemFields(of: activeRecord) else {
      return XCTFail("Expected archiveSystemFields to succeed for an active record")
    }
    guard let unarchivedActive = CloudKitOpaqueArchive.unarchiveSystemFields(archivedActive) else {
      return XCTFail("Expected unarchiveSystemFields to succeed for a valid active archive")
    }
    XCTAssertEqual(unarchivedActive.recordID.recordName, activeRecord.recordID.recordName)

    let tombstoneRecord = try CloudKitKeptWisdomCodec.encodeTombstone(
      revealId: phase4CRevealIdA, deletedAtMs: 1, updatedAtMs: 1,
      mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)
    guard let archivedTombstone = CloudKitOpaqueArchive.archiveSystemFields(of: tombstoneRecord) else {
      return XCTFail("Expected archiveSystemFields to succeed for a soft-tombstone record")
    }
    guard let unarchivedTombstone = CloudKitOpaqueArchive.unarchiveSystemFields(archivedTombstone) else {
      return XCTFail("Expected unarchiveSystemFields to succeed for a valid tombstone archive")
    }
    XCTAssertEqual(unarchivedTombstone.recordID.recordName, tombstoneRecord.recordID.recordName)
  }

  // 4. CloudKitKeptWisdomCodec.decode threads the caller-supplied,
  // already-archived systemFields value onto the resulting envelope
  // unchanged, for both forms, with no effect on any existing
  // identity/content field.
  func testKeptWisdomCodecDecodeAttachesGivenSystemFieldsOnBothForms() throws {
    let activeRecord = try CloudKitKeptWisdomCodec.encodeActive(
      revealId: phase4CRevealIdA, wisdomText: "Be still and know.",
      wisdomId: nil,
      revealedAtMs: 1, keptAtMs: 1, reflectionText: nil, reflectedAtMs: nil,
      updatedAtMs: 1, mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)
    let activeSystemFields = sampleSystemFields(for: activeRecord)

    switch CloudKitKeptWisdomCodec.decode(activeRecord, systemFields: activeSystemFields) {
    case .success(let envelope):
      XCTAssertEqual(envelope.systemFields, activeSystemFields)
      XCTAssertFalse(envelope.systemFields.isEmpty)
      XCTAssertEqual(envelope.revealId, phase4CRevealIdA)
    case .failure(let error):
      XCTFail("Expected successful decode, got \(error)")
    }

    let tombstoneRecord = try CloudKitKeptWisdomCodec.encodeTombstone(
      revealId: phase4CRevealIdA, deletedAtMs: 1, updatedAtMs: 1,
      mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)
    let tombstoneSystemFields = sampleSystemFields(for: tombstoneRecord)

    switch CloudKitKeptWisdomCodec.decode(tombstoneRecord, systemFields: tombstoneSystemFields) {
    case .success(let envelope):
      XCTAssertEqual(envelope.systemFields, tombstoneSystemFields)
      XCTAssertFalse(envelope.systemFields.isEmpty)
      XCTAssertTrue(envelope.isTombstone)
    case .failure(let error):
      XCTFail("Expected successful tombstone decode, got \(error)")
    }
  }

  // 5. `CloudKitKeptWisdomWireEnvelope.systemFields` is a non-optional
  // `String`, never `String?` -- this is a compile-time, type-system-level
  // guarantee (not merely a runtime check) that no successfully-constructed
  // envelope can ever carry a missing system-fields value. Combined with
  // `CloudKitRecordTransportCoordinator.fetchZoneChanges`'s own
  // `guard let systemFields = ..., !systemFields.isEmpty else { ... return }`
  // (which fails that one record closed via the same `sawUndecodableRecord`
  // path a malformed record already uses, *before* ever calling `decode`),
  // an archive failure structurally cannot become a successful changed
  // record with missing system fields. Forcing a genuine
  // `CloudKitOpaqueArchive.archiveSystemFields` failure is not possible from
  // this offline test target -- `NSKeyedArchiver`/`CKRecord
  // .encodeSystemFields` expose no way to make it fail for a real,
  // in-memory `CKRecord` -- this is a disclosed limitation of this test
  // target, exactly like this section's own pre-existing note on
  // `CKServerChangeToken` above.
  func testKeptWisdomWireEnvelopeSystemFieldsIsNonOptionalByConstruction() throws {
    let record = try CloudKitKeptWisdomCodec.encodeActive(
      revealId: phase4CRevealIdA, wisdomText: "Be still and know.",
      wisdomId: nil,
      revealedAtMs: 1, keptAtMs: 1, reflectionText: nil, reflectedAtMs: nil,
      updatedAtMs: 1, mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)
    guard case .success(let envelope) =
      CloudKitKeptWisdomCodec.decode(record, systemFields: sampleSystemFields(for: record))
    else {
      return XCTFail("Expected successful decode")
    }
    // This line's mere existence is the proof: `systemFields` has static
    // type `String`, not `String?` -- the compiler would reject any attempt
    // to treat it as optional.
    let systemFields: String = envelope.systemFields
    XCTAssertFalse(systemFields.isEmpty)
  }

  // MARK: - Build 26 Phase 4C-2: private CloudKit record transport tests
  //
  // `FakeRecordTransportDatabase` implements `CloudKitZoneOperationDatabase`
  // (the same seam `CloudKitPrivateZoneCoordinator` already uses --
  // reused, not duplicated) entirely in-memory and synchronously. No real
  // CloudKit network call, no real iCloud account, no real zone.
  //
  // One disclosed, unavoidable limitation of this test file: `CKServerChangeToken`
  // has no public initializer anywhere in the CloudKit SDK -- it can only
  // ever be produced by CloudKit itself, never constructed in an offline
  // unit test. Every test below that exercises `CloudKitRecordTransportCoordinator
  // .fetchZoneChanges` therefore validates every behavior that does not
  // require asserting on a genuinely successful outcome's own `serverToken`
  // value (record decoding/aggregation ordering, deletion pass-through,
  // token-expiry precedence, corrupt-archive rejection, zone/database
  // scoping) -- a true success-path round trip additionally requires a
  // real device/simulator fetch against actual iCloud, which is out of
  // scope for this offline test target and is called out explicitly in
  // this phase's completion report as not directly verified here.

  private final class FakeRecordTransportDatabase: CloudKitZoneOperationDatabase {
    var fetchOutcome: (CKRecordZone?, Error?) = (nil, CKError(.zoneNotFound))
    private(set) var addedOperations: [CKDatabaseOperation] = []

    /// One entry per record in the `CKModifyRecordsOperation`'s own
    /// `recordsToSave` order -- `nil` means that record's save succeeds.
    /// Fewer entries than records simulates a truncated/cancelled
    /// operation (some records never receive a per-record callback).
    var perRecordModifyErrors: [Error?] = []
    var modifyOverallError: Error?

    var zoneChangesRecordsToReport: [CKRecord] = []
    var zoneChangesRecordErrorsToReport: [(CKRecord.ID, Error)] = []
    var zoneChangesDeletedRecordIDs: [(CKRecord.ID, String)] = []
    var zoneChangesFetchError: Error?
    var zoneChangesOverallError: Error?

    func fetch(
      withRecordZoneID zoneID: CKRecordZone.ID,
      completionHandler: @escaping @Sendable (CKRecordZone?, Error?) -> Void
    ) {
      completionHandler(fetchOutcome.0, fetchOutcome.1)
    }

    func add(_ operation: CKDatabaseOperation) {
      addedOperations.append(operation)

      if let modifyOperation = operation as? CKModifyRecordsOperation {
        let records = modifyOperation.recordsToSave ?? []
        for (index, record) in records.enumerated() {
          guard index < perRecordModifyErrors.count else { continue }
          if let error = perRecordModifyErrors[index] {
            modifyOperation.perRecordSaveBlock?(record.recordID, .failure(error))
          } else {
            modifyOperation.perRecordSaveBlock?(record.recordID, .success(record))
          }
        }
        if let modifyOverallError {
          modifyOperation.modifyRecordsResultBlock?(.failure(modifyOverallError))
        } else {
          modifyOperation.modifyRecordsResultBlock?(.success(()))
        }
        return
      }

      if let fetchOperation = operation as? CKFetchRecordZoneChangesOperation {
        for record in zoneChangesRecordsToReport {
          fetchOperation.recordWasChangedBlock?(record.recordID, .success(record))
        }
        for (recordID, error) in zoneChangesRecordErrorsToReport {
          fetchOperation.recordWasChangedBlock?(recordID, .failure(error))
        }
        for (recordID, recordType) in zoneChangesDeletedRecordIDs {
          fetchOperation.recordWithIDWasDeletedBlock?(recordID, recordType)
        }
        if let zoneChangesFetchError {
          fetchOperation.recordZoneFetchResultBlock?(
            CloudKitRecordIdentity.zoneID, .failure(zoneChangesFetchError))
        }
        if let zoneChangesOverallError {
          fetchOperation.fetchRecordZoneChangesResultBlock?(.failure(zoneChangesOverallError))
        } else {
          fetchOperation.fetchRecordZoneChangesResultBlock?(.success(()))
        }
        return
      }
    }
  }

  private func validKeptWisdomChannelEntry(revealId: String) -> [String: Any] {
    [
      "recordType": CloudKitRecordSchema.keptWisdomRecordType,
      "fields": [
        "recordType": CloudKitRecordSchema.keptWisdomRecordType,
        "zoneName": CloudKitRecordSchema.zoneName,
        "recordName": "east-kept-\(revealId)",
        "isTombstone": false,
        "revealId": revealId,
        "wisdomText": "Be still and know.",
        "revealedAtMs": Int64(1_754_078_400_000),
        "keptAtMs": Int64(1_754_078_700_000),
        "updatedAtMs": Int64(1_754_078_700_000),
        "mutationId": phase4CMutationId,
        "dataEpoch": phase4CDataEpoch,
        "schemaVersion": CloudKitRecordSchema.keptWisdomActiveSchemaVersion,
      ],
    ]
  }

  // 1. Valid record modification request construction.
  func testArgumentParserBuildsValidKeptWisdomRecord() {
    let entry = validKeptWisdomChannelEntry(revealId: phase4CRevealIdA)
    switch CloudKitRecordEnvelopeArgumentParser.buildRecord(fromChannelEntry: entry) {
    case .success(let record):
      XCTAssertEqual(record.recordType, CloudKitRecordSchema.keptWisdomRecordType)
      XCTAssertEqual(record.recordID.recordName, "east-kept-\(phase4CRevealIdA)")
    case .failure(let error):
      XCTFail("Expected a successfully-built record, got \(error)")
    }
  }

  // 2. Private database and correct zone enforcement.
  func testArgumentParserBuiltRecordIsAlwaysInEASTKeptZone() {
    let entry = validKeptWisdomChannelEntry(revealId: phase4CRevealIdA)
    guard case .success(let record) = CloudKitRecordEnvelopeArgumentParser.buildRecord(fromChannelEntry: entry)
    else {
      return XCTFail("Expected a successfully-built record")
    }
    XCTAssertEqual(record.recordID.zoneID.zoneName, CloudKitRecordSchema.zoneName)
  }

  // 3. Wrong-zone request rejection (defense-in-depth at the transport
  // coordinator itself, not only at the argument parser).
  func testModifyRecordsRejectsARecordConstructedInTheWrongZone() {
    let wrongZoneID = CKRecordZone.default().zoneID
    let recordID = CKRecord.ID(recordName: "east-kept-\(phase4CRevealIdA)", zoneID: wrongZoneID)
    let wrongZoneRecord = CKRecord(recordType: CloudKitRecordSchema.keptWisdomRecordType, recordID: recordID)

    let fakeDatabase = FakeRecordTransportDatabase()
    let coordinator = CloudKitRecordTransportCoordinator(database: fakeDatabase)

    let calledOnce = expectation(description: "completion called")
    coordinator.modifyRecords(
      [CloudKitRecordTransportCoordinator.ModifyInput(record: wrongZoneRecord, previousSystemFields: nil)]
    ) { result in
      XCTAssertEqual(result.outcomes.count, 1)
      XCTAssertFalse(result.outcomes[0].success)
      calledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)
    // No CKModifyRecordsOperation was ever created -- the only record
    // requested was rejected before an operation could be built.
    XCTAssertEqual(fakeDatabase.addedOperations.count, 0)
  }

  // 4. Invalid codec payload rejected before operation creation.
  func testArgumentParserRejectsAMalformedPayloadAndNoOperationIsEverCreated() {
    var malformedEntry = validKeptWisdomChannelEntry(revealId: phase4CRevealIdA)
    var fields = malformedEntry["fields"] as! [String: Any]
    fields.removeValue(forKey: "wisdomText")
    malformedEntry["fields"] = fields

    switch CloudKitRecordEnvelopeArgumentParser.buildRecord(fromChannelEntry: malformedEntry) {
    case .success:
      XCTFail("Expected a missing-required-field rejection")
    case .failure(let error):
      XCTAssertEqual(error, .missingRequiredField("wisdomText"))
    }

    // With zero valid inputs, the coordinator never creates an operation.
    let fakeDatabase = FakeRecordTransportDatabase()
    let coordinator = CloudKitRecordTransportCoordinator(database: fakeDatabase)
    let calledOnce = expectation(description: "completion called")
    coordinator.modifyRecords([]) { result in
      XCTAssertEqual(result.overallStatus, .allSucceeded)
      calledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)
    XCTAssertEqual(fakeDatabase.addedOperations.count, 0)
  }

  // 5. Successful record result mapping.
  func testModifyRecordsMapsASuccessfulSaveToASuccessOutcomeWithSystemFields() throws {
    let record = try CloudKitKeptWisdomCodec.encodeActive(
      revealId: phase4CRevealIdA,
      wisdomText: "Be still and know.",
      wisdomId: nil,
      revealedAtMs: 1_754_078_400_000,
      keptAtMs: 1_754_078_700_000,
      reflectionText: nil,
      reflectedAtMs: nil,
      updatedAtMs: 1_754_078_700_000,
      mutationId: phase4CMutationId,
      dataEpoch: phase4CDataEpoch
    )
    let fakeDatabase = FakeRecordTransportDatabase()
    fakeDatabase.perRecordModifyErrors = [nil]
    let coordinator = CloudKitRecordTransportCoordinator(database: fakeDatabase)

    let calledOnce = expectation(description: "completion called")
    coordinator.modifyRecords(
      [CloudKitRecordTransportCoordinator.ModifyInput(record: record, previousSystemFields: nil)]
    ) { result in
      XCTAssertEqual(result.overallStatus, .allSucceeded)
      XCTAssertEqual(result.outcomes.count, 1)
      XCTAssertTrue(result.outcomes[0].success)
      XCTAssertNotNil(result.outcomes[0].systemFields)
      calledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  // 6. Partial failure mapping.
  func testModifyRecordsMapsMixedOutcomesToPartialFailure() throws {
    let recordA = try CloudKitKeptWisdomCodec.encodeActive(
      revealId: phase4CRevealIdA, wisdomText: "A", wisdomId: nil, revealedAtMs: 1, keptAtMs: 1,
      reflectionText: nil, reflectedAtMs: nil, updatedAtMs: 1,
      mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)
    let recordB = try CloudKitKeptWisdomCodec.encodeActive(
      revealId: phase4CRevealIdB, wisdomText: "B", wisdomId: nil, revealedAtMs: 1, keptAtMs: 1,
      reflectionText: nil, reflectedAtMs: nil, updatedAtMs: 1,
      mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)

    let fakeDatabase = FakeRecordTransportDatabase()
    fakeDatabase.perRecordModifyErrors = [nil, CKError(.networkFailure)]
    let coordinator = CloudKitRecordTransportCoordinator(database: fakeDatabase)

    let calledOnce = expectation(description: "completion called")
    coordinator.modifyRecords([
      CloudKitRecordTransportCoordinator.ModifyInput(record: recordA, previousSystemFields: nil),
      CloudKitRecordTransportCoordinator.ModifyInput(record: recordB, previousSystemFields: nil),
    ]) { result in
      XCTAssertEqual(result.overallStatus, .partialFailure)
      XCTAssertEqual(result.outcomes.count, 2)
      XCTAssertTrue(result.outcomes[0].success)
      XCTAssertFalse(result.outcomes[1].success)
      calledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  // 7. Server-record-changed mapping.
  func testModifyRecordsMapsServerRecordChangedAsADistinctPerRecordFailure() throws {
    let record = try CloudKitKeptWisdomCodec.encodeActive(
      revealId: phase4CRevealIdA, wisdomText: "A", wisdomId: nil, revealedAtMs: 1, keptAtMs: 1,
      reflectionText: nil, reflectedAtMs: nil, updatedAtMs: 1,
      mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)

    let fakeDatabase = FakeRecordTransportDatabase()
    fakeDatabase.perRecordModifyErrors = [CKError(.serverRecordChanged)]
    let coordinator = CloudKitRecordTransportCoordinator(database: fakeDatabase)

    let calledOnce = expectation(description: "completion called")
    coordinator.modifyRecords(
      [CloudKitRecordTransportCoordinator.ModifyInput(record: record, previousSystemFields: nil)]
    ) { result in
      XCTAssertEqual(result.overallStatus, .partialFailure)
      XCTAssertEqual(result.outcomes[0].errorCode, CloudKitErrorClassifier.serverRecordChanged)
      calledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  // 8. Retry-after classification without leaking raw metadata.
  func testModifyRecordsClassifiesRequestRateLimitedWithoutRawMetadata() throws {
    let record = try CloudKitKeptWisdomCodec.encodeActive(
      revealId: phase4CRevealIdA, wisdomText: "A", wisdomId: nil, revealedAtMs: 1, keptAtMs: 1,
      reflectionText: nil, reflectedAtMs: nil, updatedAtMs: 1,
      mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)

    let fakeDatabase = FakeRecordTransportDatabase()
    fakeDatabase.perRecordModifyErrors = [
      CKError(.requestRateLimited, userInfo: [CKErrorRetryAfterKey: 30.0])
    ]
    let coordinator = CloudKitRecordTransportCoordinator(database: fakeDatabase)

    let calledOnce = expectation(description: "completion called")
    coordinator.modifyRecords(
      [CloudKitRecordTransportCoordinator.ModifyInput(record: record, previousSystemFields: nil)]
    ) { result in
      let code = result.outcomes[0].errorCode ?? ""
      XCTAssertEqual(code, CloudKitErrorClassifier.requestRateLimited)
      XCTAssertFalse(code.contains("30"))
      XCTAssertFalse(code.contains(" "))
      calledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  // 9. Initial zone-change fetch (no prior token).
  func testFetchZoneChangesConfiguresNoPreviousTokenForAnInitialFetch() {
    let fakeDatabase = FakeRecordTransportDatabase()
    let coordinator = CloudKitRecordTransportCoordinator(database: fakeDatabase)

    let calledOnce = expectation(description: "completion called")
    coordinator.fetchZoneChanges(previousServerToken: nil) { _ in
      calledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)

    guard
      let fetchOperation = fakeDatabase.addedOperations.first as? CKFetchRecordZoneChangesOperation
    else {
      return XCTFail("Expected a CKFetchRecordZoneChangesOperation to have been added")
    }
    let configuration = fetchOperation.configurationsByRecordZoneID?[CloudKitRecordIdentity.zoneID]
    XCTAssertNil(configuration?.previousServerChangeToken)
  }

  // 10. Ordering/aggregation correctness across multiple changed-record
  // callbacks -- see this section's own top comment for why this validates
  // ordering (via changeTokenExpired precedence) rather than a successful
  // result's own content, given CKServerChangeToken cannot be constructed
  // in this offline test target.
  func testFetchZoneChangesNeverReportsPartialDataWhenTokenExpiresAfterRecordCallbacks() throws {
    let recordA = try CloudKitKeptWisdomCodec.encodeActive(
      revealId: phase4CRevealIdA, wisdomText: "A", wisdomId: nil, revealedAtMs: 1, keptAtMs: 1,
      reflectionText: nil, reflectedAtMs: nil, updatedAtMs: 1,
      mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)
    let recordB = try CloudKitKeptWisdomCodec.encodeActive(
      revealId: phase4CRevealIdB, wisdomText: "B", wisdomId: nil, revealedAtMs: 1, keptAtMs: 1,
      reflectionText: nil, reflectedAtMs: nil, updatedAtMs: 1,
      mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)
    let syncStateRecord = CloudKitSyncStateCodec.encode(
      dataEpoch: phase4CDataEpoch, resetAtMs: nil, mutationId: phase4CMutationId)

    let fakeDatabase = FakeRecordTransportDatabase()
    fakeDatabase.zoneChangesRecordsToReport = [recordA, recordB, syncStateRecord]
    fakeDatabase.zoneChangesOverallError = CKError(.changeTokenExpired)
    let coordinator = CloudKitRecordTransportCoordinator(database: fakeDatabase)

    // previousServerToken: nil (an initial fetch) is used here deliberately,
    // not a fabricated non-nil string -- `CKServerChangeToken` has no public
    // initializer (see this section's own top comment), so any non-nil
    // string this test could supply would have to be a plain, non-archived
    // fixture, which `CloudKitOpaqueArchive.unarchiveServerChangeToken`
    // correctly (and must continue to) reject before this coordinator ever
    // constructs a `CKFetchRecordZoneChangesOperation` at all -- that
    // rejection is itself covered by `testCorruptArchivesAreRejectedSafely`
    // and must never be weakened to make a fixture "pass." Passing `nil`
    // instead sidesteps that unrelated decode step entirely (the `guard let
    // previousServerToken = previousServerToken` branch in
    // `fetchZoneChanges` is simply never entered), so the operation is
    // actually constructed and handed to `fakeDatabase.add(_:)`, which is
    // what lets this test reach and assert on the scripted
    // `.changeTokenExpired` completion this test is actually about.
    let calledOnce = expectation(description: "completion called")
    coordinator.fetchZoneChanges(previousServerToken: nil) { result in
      // Every fed record was processed (no crash, no early abort), but the
      // final outcome is tokenExpired -- never a success carrying whatever
      // was collected before the expiry was discovered.
      XCTAssertEqual(result.outcome, .tokenExpired)
      XCTAssertNil(result.errorCode)
      XCTAssertNil(result.serverToken)
      XCTAssertTrue(result.changedKeptWisdomRecords.isEmpty)
      XCTAssertTrue(result.changedSyncStateRecords.isEmpty)
      calledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  // 11. Changed-record strict decoding -- a malformed changed record is
  // never silently dropped in favor of reporting an empty successful
  // change set.
  func testFetchZoneChangesFailsClosedWhenACallbackRecordIsMalformed() {
    let recordID = try! CloudKitRecordIdentity.keptWisdomRecordID(revealId: phase4CRevealIdA)
    let malformedRecord = CKRecord(recordType: CloudKitRecordSchema.keptWisdomRecordType, recordID: recordID)
    // Missing every required field -- decode must fail.

    let fakeDatabase = FakeRecordTransportDatabase()
    fakeDatabase.zoneChangesRecordsToReport = [malformedRecord]
    let coordinator = CloudKitRecordTransportCoordinator(database: fakeDatabase)

    let calledOnce = expectation(description: "completion called")
    coordinator.fetchZoneChanges(previousServerToken: nil) { result in
      XCTAssertEqual(result.outcome, .failure)
      calledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  func testFetchZoneChangesFailsClosedOnPerRecordCallbackFailure() throws {
    let recordID = try CloudKitRecordIdentity.keptWisdomRecordID(revealId: phase4CRevealIdA)
    let fakeDatabase = FakeRecordTransportDatabase()
    fakeDatabase.zoneChangesRecordErrorsToReport = [(recordID, CKError(.networkFailure))]
    let coordinator = CloudKitRecordTransportCoordinator(database: fakeDatabase)

    let calledOnce = expectation(description: "completion called")
    coordinator.fetchZoneChanges(previousServerToken: nil) { result in
      XCTAssertEqual(result.outcome, .failure)
      XCTAssertEqual(result.errorCode, CloudKitErrorClassifier.networkFailure)
      XCTAssertTrue(result.changedKeptWisdomRecords.isEmpty)
      XCTAssertTrue(result.changedSyncStateRecords.isEmpty)
      XCTAssertNil(result.serverToken)
      calledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  // 11b. Build 26 Phase 4H-2: a changed record legitimately carrying a
  // Reflection added *after* this device's own last fetch (e.g. by another
  // device) decodes successfully -- the mere presence of
  // `reflectionText`/`reflectedAtMs` on an incremental fetch is not, by
  // itself, a failure condition.
  //
  // Deliberately NOT routed through `FakeRecordTransportDatabase`/
  // `CloudKitRecordTransportCoordinator.fetchZoneChanges` here: as this
  // section's own top comment already discloses, that fake can never
  // report a genuine `.success` outcome for `fetchZoneChanges` at all --
  // `CKServerChangeToken` has no public initializer anywhere in the
  // CloudKit SDK, so `FakeRecordTransportDatabase.add(_:)` always invokes
  // no successful zone-fetch result carrying a token, which fails the
  // coordinator's own `guard let finalToken = finalToken, let archivedToken
  // = ...` closed with `unrecognizedNativeError`, regardless of whether
  // every changed record decoded perfectly. Asserting `.success` through
  // that fake was this test's own defect (a real-device diagnostic run
  // confirmed the root cause), not a production bug -- fixed here, not in
  // `CloudKitRecordTransportCoordinator`.
  //
  // Proving this record's own decode succeeds is instead done exactly like
  // every other decode assertion in this file (e.g.
  // `testKeptWisdomCodecRoundTripsActiveForm`,
  // `testKeptWisdomCodecDecodeAttachesGivenSystemFieldsOnBothForms` above):
  // by calling `CloudKitOpaqueArchive.archiveSystemFields(of:)` followed by
  // `CloudKitKeptWisdomCodec.decode(_:systemFields:)` directly -- exactly
  // the same two calls, in the same order, that `fetchZoneChanges`'s own
  // `recordWasChangedBlock` makes for a `CKKeptWisdom` record. Named
  // `testKeptWisdomCodec...` (not `testFetchZoneChanges...`) to match: this
  // test exercises the codec's archive-then-decode path directly, never
  // `fetchZoneChanges` itself.
  func testKeptWisdomCodecDecodesAChangedRecordCarryingANewlyAddedReflection() throws {
    let record = try CloudKitKeptWisdomCodec.encodeActive(
      revealId: phase4CRevealIdA,
      wisdomText: "Be still and know.",
      wisdomId: nil,
      revealedAtMs: 1, keptAtMs: 1,
      reflectionText: "A quiet thought added on another device.",
      reflectedAtMs: 2,
      updatedAtMs: 2,
      mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)

    guard let systemFields = CloudKitOpaqueArchive.archiveSystemFields(of: record) else {
      return XCTFail("Expected archiveSystemFields to succeed for a well-formed active record")
    }

    switch CloudKitKeptWisdomCodec.decode(record, systemFields: systemFields) {
    case .success(let envelope):
      XCTAssertFalse(envelope.isTombstone)
      XCTAssertEqual(envelope.reflectionText, "A quiet thought added on another device.")
      XCTAssertEqual(envelope.reflectedAtMs, 2)
      XCTAssertEqual(envelope.systemFields, systemFields)
    case .failure(let error):
      XCTFail(
        "Expected a well-formed, paired-Reflection changed record to decode successfully, "
          + "got \(error)")
    }
  }

  // 11c. Build 26 Phase 4H-2: the incremental-fetch counterpart to
  // `testKeptWisdomCodecRejectsInconsistentReflectionFieldsOnDecode` above
  // -- proves the *whole fetch* fails closed (never a partial/successful
  // result silently omitting the bad record) when a changed record another
  // device wrote carries a one-sided Reflection. This is the exact
  // `errorCode=unrecognizedNativeError` shape this phase's physical-device
  // log showed.
  func testFetchZoneChangesFailsClosedWhenAChangedRecordHasInconsistentReflectionFields() throws {
    let record = try CloudKitKeptWisdomCodec.encodeActive(
      revealId: phase4CRevealIdA,
      wisdomText: "Be still and know.",
      wisdomId: nil,
      revealedAtMs: 1, keptAtMs: 1,
      reflectionText: nil, reflectedAtMs: nil,
      updatedAtMs: 1,
      mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)
    record[CloudKitRecordSchema.KeptWisdomField.reflectionText] = "A quiet thought." as CKRecordValue

    let fakeDatabase = FakeRecordTransportDatabase()
    fakeDatabase.zoneChangesRecordsToReport = [record]
    let coordinator = CloudKitRecordTransportCoordinator(database: fakeDatabase)

    let calledOnce = expectation(description: "completion called")
    coordinator.fetchZoneChanges(previousServerToken: nil) { result in
      XCTAssertEqual(result.outcome, .failure)
      XCTAssertEqual(result.errorCode, CloudKitErrorClassifier.unrecognizedNativeError)
      XCTAssertTrue(result.changedKeptWisdomRecords.isEmpty)
      XCTAssertTrue(result.changedSyncStateRecords.isEmpty)
      calledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  // 12. Physical deletion handling per architecture: this transport never
  // issues one (recordIDsToDelete is always nil), but a deletion
  // notification CloudKit itself reports is still surfaced defensively,
  // never silently discarded.
  func testModifyRecordsNeverUsesPhysicalDeletion() throws {
    let record = try CloudKitKeptWisdomCodec.encodeTombstone(
      revealId: phase4CRevealIdA, deletedAtMs: 1, updatedAtMs: 1,
      mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)
    let fakeDatabase = FakeRecordTransportDatabase()
    fakeDatabase.perRecordModifyErrors = [nil]
    let coordinator = CloudKitRecordTransportCoordinator(database: fakeDatabase)

    let calledOnce = expectation(description: "completion called")
    coordinator.modifyRecords(
      [CloudKitRecordTransportCoordinator.ModifyInput(record: record, previousSystemFields: nil)]
    ) { _ in calledOnce.fulfill() }
    waitForExpectations(timeout: 1)

    guard let modifyOperation = fakeDatabase.addedOperations.first as? CKModifyRecordsOperation else {
      return XCTFail("Expected a CKModifyRecordsOperation to have been added")
    }
    XCTAssertNil(modifyOperation.recordIDsToDelete)
  }

  func testFetchZoneChangesFailsClosedOnAnOutOfBandPhysicalDeletion() {
    let recordID = try! CloudKitRecordIdentity.keptWisdomRecordID(revealId: phase4CRevealIdA)
    let fakeDatabase = FakeRecordTransportDatabase()
    fakeDatabase.zoneChangesDeletedRecordIDs = [(recordID, CloudKitRecordSchema.keptWisdomRecordType)]
    // A concurrent, otherwise-normal error is also scripted here on
    // purpose: this proves the unexpected-physical-deletion outcome takes
    // priority over every other outcome this fetch could have reported,
    // per this coordinator's own doc comment ("checked first, before every
    // other outcome").
    fakeDatabase.zoneChangesOverallError = CKError(.networkFailure)
    let coordinator = CloudKitRecordTransportCoordinator(database: fakeDatabase)

    let calledOnce = expectation(description: "completion called")
    coordinator.fetchZoneChanges(previousServerToken: nil) { result in
      XCTAssertEqual(result.outcome, .unexpectedPhysicalDeletion)
      XCTAssertNil(result.errorCode)
      XCTAssertNil(result.serverToken)
      XCTAssertTrue(result.changedKeptWisdomRecords.isEmpty)
      XCTAssertTrue(result.changedSyncStateRecords.isEmpty)
      calledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  // The deleted record's own identity must never be capturable through
  // this coordinator's public result -- not even indirectly. There is no
  // API on `ZoneChangesResult` that could expose it (no `deletedRecordNames`
  // field exists at all), so this test proves that structurally: the
  // result type's own stored properties, enumerated by name, contain
  // nothing deletion-identity-shaped.
  func testUnexpectedPhysicalDeletionResultExposesNoRecordIdentity() {
    let recordID = try! CloudKitRecordIdentity.keptWisdomRecordID(revealId: phase4CRevealIdA)
    let fakeDatabase = FakeRecordTransportDatabase()
    fakeDatabase.zoneChangesDeletedRecordIDs = [(recordID, CloudKitRecordSchema.keptWisdomRecordType)]
    let coordinator = CloudKitRecordTransportCoordinator(database: fakeDatabase)

    let calledOnce = expectation(description: "completion called")
    coordinator.fetchZoneChanges(previousServerToken: nil) { result in
      let mirror = Mirror(reflecting: result)
      for child in mirror.children {
        XCTAssertFalse(
          "\(child.value)".contains(recordID.recordName),
          "Expected no field of the result to contain the deleted record's name")
      }
      calledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  // Build 26 Phase 4E-3a: the physical-deletion callback receives only a
  // `CKRecordID` (never a full `CKRecord`), so there is no system-fields
  // value it could possibly report -- this path remains exactly as
  // fail-closed as before, and this phase adds nothing to it. Reuses the
  // same structural, no-record-identity-exposed proof style as
  // `testUnexpectedPhysicalDeletionResultExposesNoRecordIdentity` above,
  // scoped specifically to system fields.
  func testUnexpectedPhysicalDeletionResultCarriesNoSystemFields() {
    let recordID = try! CloudKitRecordIdentity.keptWisdomRecordID(revealId: phase4CRevealIdA)
    let fakeDatabase = FakeRecordTransportDatabase()
    fakeDatabase.zoneChangesDeletedRecordIDs = [(recordID, CloudKitRecordSchema.keptWisdomRecordType)]
    let coordinator = CloudKitRecordTransportCoordinator(database: fakeDatabase)

    let calledOnce = expectation(description: "completion called")
    coordinator.fetchZoneChanges(previousServerToken: nil) { result in
      XCTAssertEqual(result.outcome, .unexpectedPhysicalDeletion)
      // No changed CKKeptWisdom record -- and therefore no system-fields
      // entry of any kind -- is ever reported once a physical deletion has
      // been observed, regardless of what else this fetch may have
      // otherwise collected.
      XCTAssertTrue(result.changedKeptWisdomRecords.isEmpty)
      calledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  // 13. System-fields secure archive round trip (CKRecord's own
  // NSSecureCoding conformance -- unlike CKServerChangeToken, a CKRecord
  // can be constructed directly in a test).
  func testSystemFieldsArchiveRoundTripsRecordIdentity() throws {
    let record = try CloudKitKeptWisdomCodec.encodeActive(
      revealId: phase4CRevealIdA, wisdomText: "A", wisdomId: nil, revealedAtMs: 1, keptAtMs: 1,
      reflectionText: nil, reflectedAtMs: nil, updatedAtMs: 1,
      mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)

    guard let archived = CloudKitOpaqueArchive.archiveSystemFields(of: record) else {
      return XCTFail("Expected system-fields archiving to succeed")
    }
    guard let restored = CloudKitOpaqueArchive.unarchiveSystemFields(archived) else {
      return XCTFail("Expected system-fields unarchiving to succeed")
    }
    XCTAssertEqual(restored.recordID.recordName, record.recordID.recordName)
    XCTAssertEqual(restored.recordID.zoneID, record.recordID.zoneID)
    XCTAssertEqual(restored.recordType, record.recordType)
  }

  // 14. Corrupt archive rejection -- both token and system-fields
  // unarchiving fail closed on garbage input, never crash.
  func testCorruptArchivesAreRejectedSafely() {
    XCTAssertNil(CloudKitOpaqueArchive.unarchiveServerChangeToken("not-valid-base64!!!"))
    XCTAssertNil(CloudKitOpaqueArchive.unarchiveServerChangeToken(""))
    XCTAssertNil(CloudKitOpaqueArchive.unarchiveSystemFields("not-valid-base64!!!"))
    XCTAssertNil(CloudKitOpaqueArchive.unarchiveSystemFields(""))
  }

  // 15. Change-token-expired mapping is a distinct outcome, never a
  // generic errorCode.
  func testFetchZoneChangesMapsChangeTokenExpiredToADistinctOutcome() {
    let fakeDatabase = FakeRecordTransportDatabase()
    fakeDatabase.zoneChangesOverallError = CKError(.changeTokenExpired)
    let coordinator = CloudKitRecordTransportCoordinator(database: fakeDatabase)

    // previousServerToken: nil, not a fabricated non-nil string -- see the
    // matching comment on
    // testFetchZoneChangesNeverReportsPartialDataWhenTokenExpiresAfterRecordCallbacks
    // for why: a plain string like "stale-token" is correctly rejected by
    // CloudKitOpaqueArchive.unarchiveServerChangeToken (it is not a securely
    // archived CKServerChangeToken, and CKServerChangeToken has no public
    // initializer this test could use to build a real one), which returns
    // .failure/invalidArguments *before* this coordinator ever constructs a
    // CKFetchRecordZoneChangesOperation -- never reaching, let alone
    // exercising, the changeTokenExpired mapping this test exists to prove.
    // `nil` (an initial fetch) skips that unrelated decode step entirely so
    // the fake database's scripted completion is actually reached.
    let calledOnce = expectation(description: "completion called")
    coordinator.fetchZoneChanges(previousServerToken: nil) { result in
      XCTAssertEqual(result.outcome, .tokenExpired)
      XCTAssertNil(result.errorCode)
      XCTAssertNil(result.serverToken)
      calledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  // 16. Operation completion exactly once, across modify and fetch.
  func testModifyAndFetchEachCompleteExactlyOnce() throws {
    let record = try CloudKitKeptWisdomCodec.encodeActive(
      revealId: phase4CRevealIdA, wisdomText: "A", wisdomId: nil, revealedAtMs: 1, keptAtMs: 1,
      reflectionText: nil, reflectedAtMs: nil, updatedAtMs: 1,
      mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)

    let modifyDatabase = FakeRecordTransportDatabase()
    modifyDatabase.perRecordModifyErrors = [nil]
    let modifyCoordinator = CloudKitRecordTransportCoordinator(database: modifyDatabase)
    var modifyCompletionCount = 0
    let modifyCalledOnce = expectation(description: "modify completion called exactly once")
    modifyCoordinator.modifyRecords(
      [CloudKitRecordTransportCoordinator.ModifyInput(record: record, previousSystemFields: nil)]
    ) { _ in
      modifyCompletionCount += 1
      modifyCalledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)
    XCTAssertEqual(modifyCompletionCount, 1)

    let fetchDatabase = FakeRecordTransportDatabase()
    fetchDatabase.zoneChangesOverallError = CKError(.networkUnavailable)
    let fetchCoordinator = CloudKitRecordTransportCoordinator(database: fetchDatabase)
    var fetchCompletionCount = 0
    let fetchCalledOnce = expectation(description: "fetch completion called exactly once")
    fetchCoordinator.fetchZoneChanges(previousServerToken: nil) { _ in
      fetchCompletionCount += 1
      fetchCalledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)
    XCTAssertEqual(fetchCompletionCount, 1)
  }

  // 17. No content ever appears in safe error output for the transport
  // operations -- only known symbolic codes, never localized/raw content.
  func testTransportErrorCodesNeverExposeLocalizedOrRawContent() throws {
    let record = try CloudKitKeptWisdomCodec.encodeActive(
      revealId: phase4CRevealIdA,
      wisdomText: "This exact wisdom text must never appear in an errorCode.",
      wisdomId: nil,
      revealedAtMs: 1, keptAtMs: 1, reflectionText: nil, reflectedAtMs: nil,
      updatedAtMs: 1, mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)

    let knownCodes: Set<String> = [
      CloudKitErrorClassifier.networkUnavailable,
      CloudKitErrorClassifier.networkFailure,
      CloudKitErrorClassifier.serviceUnavailable,
      CloudKitErrorClassifier.requestRateLimited,
      CloudKitErrorClassifier.zoneBusy,
      CloudKitErrorClassifier.serverRecordChanged,
      CloudKitErrorClassifier.accountTemporarilyUnavailable,
      CloudKitErrorClassifier.notAuthenticated,
      CloudKitErrorClassifier.invalidArguments,
      CloudKitErrorClassifier.unknownItem,
      CloudKitErrorClassifier.incompatibleVersion,
      CloudKitErrorClassifier.quotaExceeded,
      CloudKitErrorClassifier.limitExceeded,
      CloudKitErrorClassifier.serverRejectedRequest,
      CloudKitErrorClassifier.permissionFailure,
      CloudKitErrorClassifier.zoneNotFound,
      CloudKitErrorClassifier.badContainer,
      CloudKitErrorClassifier.badDatabase,
      CloudKitErrorClassifier.changeTokenExpired,
      CloudKitErrorClassifier.unrecognizedNativeError,
    ]

    let fakeDatabase = FakeRecordTransportDatabase()
    fakeDatabase.perRecordModifyErrors = [
      CKError(.serverRejectedRequest, userInfo: [NSLocalizedDescriptionKey: "raw localized text"])
    ]
    let coordinator = CloudKitRecordTransportCoordinator(database: fakeDatabase)

    let calledOnce = expectation(description: "completion called")
    coordinator.modifyRecords(
      [CloudKitRecordTransportCoordinator.ModifyInput(record: record, previousSystemFields: nil)]
    ) { result in
      let code = result.outcomes[0].errorCode ?? ""
      XCTAssertTrue(knownCodes.contains(code))
      XCTAssertFalse(code.contains(" "))
      XCTAssertFalse(code.contains("raw localized text"))
      XCTAssertFalse(code.contains("wisdom text must never appear"))
      calledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  // 18. Existing account/zone bridge tests continue passing -- proven by
  // reusing the exact same FakeZoneOperationDatabase-conforming seam for
  // both CloudKitPrivateZoneCoordinator (Phase 4B-2, unmodified) and the
  // new CloudKitRecordTransportCoordinator side by side, showing this
  // phase's addition does not interfere with the existing coordinator.
  func testExistingZoneConfigurationCoordinatorStillWorksAlongsideTheNewTransportCoordinator() {
    let fakeZoneDatabase = FakeZoneOperationDatabase()
    fakeZoneDatabase.fetchOutcome = .zoneExists
    let zoneCoordinator = CloudKitPrivateZoneCoordinator(database: fakeZoneDatabase)

    let zoneCalledOnce = expectation(description: "zone completion called")
    zoneCoordinator.configureZone { result in
      XCTAssertTrue(result.success)
      zoneCalledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)

    let fakeTransportDatabase = FakeRecordTransportDatabase()
    let transportCoordinator = CloudKitRecordTransportCoordinator(database: fakeTransportDatabase)
    let transportCalledOnce = expectation(description: "transport completion called")
    transportCoordinator.modifyRecords([]) { result in
      XCTAssertEqual(result.overallStatus, .allSucceeded)
      transportCalledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  // MARK: - Build 26 Phase 4H: EastFileProtection (native file-protection
  // bridge) tests
  //
  // `EastFileProtection` was widened from `private` to `internal`
  // (AppDelegate.swift) solely so this suite can exercise
  // `handle(_:result:)` directly via `@testable import Runner` -- no other
  // behavior change. These construct a real temporary file/directory under
  // the test process's own tmp directory; no CloudKit, no network, no app
  // data of any kind is touched or deleted.
  //
  // This suite deliberately contains no Simulator-vs-device branching of
  // its own: XCTest always runs under whichever destination the test
  // target is built for, so `handle(_:result:)`'s own
  // `#if targetEnvironment(simulator)` branch resolves naturally to
  // whichever destination is actually running these tests. Running this
  // suite on the iOS Simulator is itself the regression proof for the
  // Simulator compatibility fix: before that fix,
  // `testFileProtectionHandleSucceedsForARegularFile` and
  // `testFileProtectionHandleSucceedsForADirectory` would fail on Simulator
  // with `protection_verification_failed`; after it, they pass there, while
  // remaining exactly as strict on physical hardware as before (the
  // `#else` branch is byte-for-byte unchanged from its pre-fix form).

  private func makeFileProtectionTempFile() throws -> String {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("east-file-protection-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let fileURL = directory.appendingPathComponent("sample.txt")
    try "east-file-protection-test".write(to: fileURL, atomically: true, encoding: .utf8)
    return fileURL.path
  }

  private func makeFileProtectionTempDirectory() throws -> String {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("east-file-protection-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.path
  }

  private func invokeFileProtectionHandle(
    method: String = "protectAndVerifyComplete",
    arguments: Any?
  ) -> Any? {
    let call = FlutterMethodCall(methodName: method, arguments: arguments)
    let calledOnce = expectation(description: "EastFileProtection.handle result called")
    var capturedResult: Any?
    EastFileProtection.handle(call) { value in
      capturedResult = value
      calledOnce.fulfill()
    }
    waitForExpectations(timeout: 2)
    return capturedResult
  }

  // 1. A regular file succeeds. On Simulator this exercises the new
  // compatibility branch; on physical hardware it exercises the unchanged
  // strict branch -- both are expected to report success.
  func testFileProtectionHandleSucceedsForARegularFile() throws {
    let path = try makeFileProtectionTempFile()
    let capturedResult = invokeFileProtectionHandle(arguments: ["path": path])
    XCTAssertEqual(capturedResult as? Bool, true)
  }

  // 2. A directory succeeds identically -- `setAttributes`/`attributesOfItem`
  // are exercised exactly the same way for a directory as for a file under
  // the existing contract; this is not redesigned by this fix.
  func testFileProtectionHandleSucceedsForADirectory() throws {
    let path = try makeFileProtectionTempDirectory()
    let capturedResult = invokeFileProtectionHandle(arguments: ["path": path])
    XCTAssertEqual(capturedResult as? Bool, true)
  }

  // 3. An unrelated/unsupported method name still surfaces its own
  // unchanged error code on both platforms.
  func testFileProtectionHandleRejectsUnsupportedMethod() {
    let capturedResult = invokeFileProtectionHandle(
      method: "someOtherMethod", arguments: ["path": "/tmp"])
    guard let error = capturedResult as? FlutterError else {
      return XCTFail("Expected a FlutterError for an unsupported method")
    }
    XCTAssertEqual(error.code, "unsupported_method")
  }

  // 4. Missing arguments still fail on both platforms.
  func testFileProtectionHandleRejectsMissingArguments() {
    let capturedResult = invokeFileProtectionHandle(arguments: nil)
    guard let error = capturedResult as? FlutterError else {
      return XCTFail("Expected a FlutterError for missing arguments")
    }
    XCTAssertEqual(error.code, "invalid_arguments")
  }

  // 5. A blank path still fails on both platforms.
  func testFileProtectionHandleRejectsBlankPath() {
    let capturedResult = invokeFileProtectionHandle(arguments: ["path": "   "])
    guard let error = capturedResult as? FlutterError else {
      return XCTFail("Expected a FlutterError for a blank path")
    }
    XCTAssertEqual(error.code, "invalid_arguments")
  }

  // 6. A relative path still fails on both platforms.
  func testFileProtectionHandleRejectsRelativePath() {
    let capturedResult = invokeFileProtectionHandle(arguments: ["path": "relative/path.txt"])
    guard let error = capturedResult as? FlutterError else {
      return XCTFail("Expected a FlutterError for a relative path")
    }
    XCTAssertEqual(error.code, "invalid_arguments")
  }

  // 7. A well-formed but nonexistent path still fails on both platforms --
  // the Simulator compatibility branch only ever relaxes the *final*
  // protection-class comparison; it never bypasses path existence.
  func testFileProtectionHandleRejectsNonexistentPath() {
    let missingPath = FileManager.default.temporaryDirectory
      .appendingPathComponent("east-file-protection-missing-\(UUID().uuidString)")
      .path
    let capturedResult = invokeFileProtectionHandle(arguments: ["path": missingPath])
    guard let error = capturedResult as? FlutterError else {
      return XCTFail("Expected a FlutterError for a nonexistent path")
    }
    XCTAssertEqual(error.code, "path_not_found")
  }

  // MARK: - Build 26 Phase 5 (slice 2): CloudKitDeletionTransportCoordinator
  // native validation hardening.
  //
  // `FakeDeletionTransportDatabase` implements `CloudKitDeletionTransportDatabase`
  // entirely in-memory and synchronously -- no real CloudKit network call, no
  // real iCloud account, no real zone -- mirroring `FakeZoneOperationDatabase`/
  // `FakeRecordTransportDatabase`'s own established convention above.
  //
  // One deliberate, disclosed limitation: `CKQueryOperation.Cursor` has no
  // public initializer anywhere in the CloudKit SDK, so this fake (like every
  // other CloudKit unit-test fake in this codebase, and in the wider
  // ecosystem) cannot synthesize a real multi-page cursor continuation. True
  // multi-page pagination is therefore proven only structurally below
  // (`testListKeptWisdomRecordNamesRecursesOnNonNilCursor`), not dynamically
  // -- this is an Apple SDK constraint, not a gap in this fake or in
  // `CloudKitDeletionTransportCoordinator` itself.

  private final class FakeDeletionTransportDatabase: CloudKitDeletionTransportDatabase {
    // fetch(withRecordID:) -- fetchSyncStateEpoch
    var fetchRecordResult: (CKRecord?, Error?) = (nil, CKError(.unknownItem))
    private(set) var fetchedRecordIDs: [CKRecord.ID] = []

    // CKQueryOperation -- listKeptWisdomRecordNames. A single configured
    // page: the record names reported via `recordMatchedBlock` before
    // `queryResultBlock` fires with a `nil` cursor (i.e. "last page").
    var queryPageRecordNames: [String] = []
    var queryRecordMatchErrors: [(CKRecord.ID, Error)] = []
    var queryError: Error?
    private(set) var queryOperationsAdded: [CKQueryOperation] = []

    // CKModifyRecordsOperation(recordIDsToDelete:) -- deleteKeptWisdomRecords
    var deletedRecordIDsToReport: [CKRecord.ID] = []
    var deleteCompletionError: Error?
    private(set) var modifyOperationsAdded: [CKModifyRecordsOperation] = []

    func fetch(
      withRecordID recordID: CKRecord.ID,
      completionHandler: @escaping @Sendable (CKRecord?, Error?) -> Void
    ) {
      fetchedRecordIDs.append(recordID)
      completionHandler(fetchRecordResult.0, fetchRecordResult.1)
    }

    func add(_ operation: CKDatabaseOperation) {
      if let queryOperation = operation as? CKQueryOperation {
        queryOperationsAdded.append(queryOperation)
        for name in queryPageRecordNames {
          let recordID = CKRecord.ID(recordName: name, zoneID: CloudKitRecordIdentity.zoneID)
          let record = CKRecord(recordType: CloudKitRecordSchema.keptWisdomRecordType, recordID: recordID)
          queryOperation.recordMatchedBlock?(recordID, .success(record))
        }
        for (recordID, error) in queryRecordMatchErrors {
          queryOperation.recordMatchedBlock?(recordID, .failure(error))
        }
        if let queryError {
          queryOperation.queryResultBlock?(.failure(queryError))
        } else {
          queryOperation.queryResultBlock?(.success(nil))
        }
        return
      }
      if let modifyOperation = operation as? CKModifyRecordsOperation {
        modifyOperationsAdded.append(modifyOperation)
        let successfulIDs = Set(deletedRecordIDsToReport)
        let perItemErrors =
          (deleteCompletionError as? CKError)?.partialErrorsByItemID as? [CKRecord.ID: Error]
        for recordID in modifyOperation.recordIDsToDelete ?? [] {
          if successfulIDs.contains(recordID) {
            modifyOperation.perRecordDeleteBlock?(recordID, .success(()))
          } else if let error = perItemErrors?[recordID] {
            modifyOperation.perRecordDeleteBlock?(recordID, .failure(error))
          }
        }
        if let deleteCompletionError {
          modifyOperation.modifyRecordsResultBlock?(.failure(deleteCompletionError))
        } else {
          modifyOperation.modifyRecordsResultBlock?(.success(()))
        }
        return
      }
    }
  }

  private let phase5DeletionEpoch = "33333333-3333-4333-8333-333333333333"
  private let phase5DeletionMutationId = "44444444-4444-4444-8444-444444444444"

  // 1. fetch sync-state epoch returns the current CKEastSyncState epoch.
  func testFetchSyncStateEpochReturnsCurrentEpoch() {
    let record = CloudKitSyncStateCodec.encode(
      dataEpoch: phase5DeletionEpoch, resetAtMs: nil, mutationId: phase5DeletionMutationId)
    let fakeDatabase = FakeDeletionTransportDatabase()
    fakeDatabase.fetchRecordResult = (record, nil)
    let coordinator = CloudKitDeletionTransportCoordinator(database: fakeDatabase)

    let calledOnce = expectation(description: "completion called")
    coordinator.fetchSyncStateEpoch { result in
      XCTAssertEqual(result.outcome, .found)
      XCTAssertEqual(result.dataEpoch, self.phase5DeletionEpoch)
      XCTAssertNotNil(result.systemFields)
      calledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)
    // Reads exactly, and only, the fixed CKEastSyncState singleton identity.
    XCTAssertEqual(fakeDatabase.fetchedRecordIDs, [CloudKitRecordIdentity.syncStateRecordID()])
  }

  // 2. missing CKEastSyncState is represented safely (`.notFound`, never
  // `.failure`) -- an ordinary, expected state for a device whose bucket has
  // never been bootstrapped, matching the Dart contract's own documented
  // distinction (`CloudKitSyncStateEpochOutcome.notFound` vs `.failure`).
  func testFetchSyncStateEpochReportsNotFoundForUnknownItem() {
    let fakeDatabase = FakeDeletionTransportDatabase()
    fakeDatabase.fetchRecordResult = (nil, CKError(.unknownItem))
    let coordinator = CloudKitDeletionTransportCoordinator(database: fakeDatabase)

    let calledOnce = expectation(description: "completion called")
    coordinator.fetchSyncStateEpoch { result in
      XCTAssertEqual(result.outcome, .notFound)
      XCTAssertNil(result.dataEpoch)
      XCTAssertNil(result.errorCode)
      calledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  // 3. malformed/missing epoch field fails closed -- a record that exists
  // but does not decode as a valid CKEastSyncState is `.failure`, never
  // `.found` with a guessed/default epoch.
  func testFetchSyncStateEpochFailsClosedOnMalformedRecord() {
    let record = CloudKitSyncStateCodec.encode(
      dataEpoch: phase5DeletionEpoch, resetAtMs: nil, mutationId: phase5DeletionMutationId)
    // Corrupt the required dataEpoch field's type.
    record[CloudKitRecordSchema.SyncStateField.dataEpoch] = 12345 as CKRecordValue
    let fakeDatabase = FakeDeletionTransportDatabase()
    fakeDatabase.fetchRecordResult = (record, nil)
    let coordinator = CloudKitDeletionTransportCoordinator(database: fakeDatabase)

    let calledOnce = expectation(description: "completion called")
    coordinator.fetchSyncStateEpoch { result in
      XCTAssertEqual(result.outcome, .failure)
      XCTAssertNil(result.dataEpoch)
      XCTAssertNotNil(result.errorCode)
      calledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  // 4. listKeptWisdomRecordNames returns only CKKeptWisdom identities -- the
  // underlying CKQuery is itself scoped to `keptWisdomRecordType`, which is
  // precisely what makes it structurally impossible for this query to ever
  // return the CKEastSyncState singleton's own identity (see test 11 below).
  func testListKeptWisdomRecordNamesReturnsOnlyRequestedNames() {
    let fakeDatabase = FakeDeletionTransportDatabase()
    fakeDatabase.queryPageRecordNames = ["east-kept-a", "east-kept-b"]
    let coordinator = CloudKitDeletionTransportCoordinator(database: fakeDatabase)

    let calledOnce = expectation(description: "completion called")
    coordinator.listKeptWisdomRecordNames { result in
      XCTAssertEqual(result.outcome, .success)
      XCTAssertEqual(Set(result.recordNames), Set(["east-kept-a", "east-kept-b"]))
      calledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)

    guard let query = fakeDatabase.queryOperationsAdded.first?.query else {
      return XCTFail("Expected a CKQueryOperation carrying a CKQuery")
    }
    XCTAssertEqual(query.recordType, CloudKitRecordSchema.keptWisdomRecordType)
  }

  // 5. Pagination/continuation: structural proof only, not dynamic --
  // `CKQueryOperation.Cursor` has no public initializer, so no fake can
  // synthesize a real non-nil cursor to drive a genuine second page through
  // `queryResultBlock`. This inspects the coordinator's own source text
  // to confirm the recursive continuation path
  // (`runQuery(cursor: nextCursor)` guarded by `if let nextCursor = ...`)
  // is present exactly once and reachable from `queryResultBlock`,
  // mirroring this codebase's own established precedent (the Dart layering
  // tests) of a structural source check standing in for a dynamic one where
  // the platform itself makes dynamic testing impossible.
  func testListKeptWisdomRecordNamesRecursesOnNonNilCursor() throws {
    let sourceURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Runner/CloudKitDeletionTransportCoordinator.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    XCTAssertTrue(
      source.contains("if let nextCursor {"),
      "Expected the coordinator to check for a non-nil next cursor before deciding a query is complete")
    XCTAssertTrue(
      source.contains("runQuery(cursor: nextCursor)"),
      "Expected the coordinator to recurse with the next cursor rather than stopping at one page")
  }

  // 6. Zero records returns an empty, successful result -- an empty zone is
  // a well-defined success, never an error.
  func testListKeptWisdomRecordNamesReturnsEmptySuccessForZeroRecords() {
    let fakeDatabase = FakeDeletionTransportDatabase()
    fakeDatabase.queryPageRecordNames = []
    let coordinator = CloudKitDeletionTransportCoordinator(database: fakeDatabase)

    let calledOnce = expectation(description: "completion called")
    coordinator.listKeptWisdomRecordNames { result in
      XCTAssertEqual(result.outcome, .success)
      XCTAssertTrue(result.recordNames.isEmpty)
      calledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  func testListKeptWisdomRecordNamesFailsClosedOnPerRecordMatchFailure() {
    let fakeDatabase = FakeDeletionTransportDatabase()
    fakeDatabase.queryPageRecordNames = ["east-kept-valid"]
    let failedID = CKRecord.ID(
      recordName: "east-kept-failed", zoneID: CloudKitRecordIdentity.zoneID)
    fakeDatabase.queryRecordMatchErrors = [(failedID, CKError(.networkFailure))]
    let coordinator = CloudKitDeletionTransportCoordinator(database: fakeDatabase)

    let calledOnce = expectation(description: "completion called")
    coordinator.listKeptWisdomRecordNames { result in
      XCTAssertEqual(result.outcome, .failure)
      XCTAssertTrue(result.recordNames.isEmpty)
      XCTAssertEqual(result.errorCode, CloudKitErrorClassifier.networkFailure)
      calledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  // 13 (part 1). No wisdom text / Reflection content / revealId is required
  // or returned by the listing query -- `desiredKeys = []` means CloudKit
  // itself is never asked to fetch any field data for this query.
  func testListKeptWisdomRecordNamesRequestsNoFieldData() {
    let fakeDatabase = FakeDeletionTransportDatabase()
    fakeDatabase.queryPageRecordNames = ["east-kept-a"]
    let coordinator = CloudKitDeletionTransportCoordinator(database: fakeDatabase)

    let calledOnce = expectation(description: "completion called")
    coordinator.listKeptWisdomRecordNames { _ in calledOnce.fulfill() }
    waitForExpectations(timeout: 1)

    XCTAssertEqual(fakeDatabase.queryOperationsAdded.first?.desiredKeys, [])
  }

  // 7. deleteKeptWisdomRecords physically deletes the requested identities.
  func testDeleteKeptWisdomRecordsDeletesRequestedIdentities() {
    let zoneID = CloudKitRecordIdentity.zoneID
    let recordIDs = [
      CKRecord.ID(recordName: "east-kept-a", zoneID: zoneID),
      CKRecord.ID(recordName: "east-kept-b", zoneID: zoneID),
    ]
    let fakeDatabase = FakeDeletionTransportDatabase()
    fakeDatabase.deletedRecordIDsToReport = recordIDs
    let coordinator = CloudKitDeletionTransportCoordinator(database: fakeDatabase)

    let calledOnce = expectation(description: "completion called")
    coordinator.deleteKeptWisdomRecords(recordNames: ["east-kept-a", "east-kept-b"]) { result in
      XCTAssertEqual(result.overallStatus, .allSucceeded)
      XCTAssertEqual(Set(result.outcomes.map { $0.recordName }), Set(["east-kept-a", "east-kept-b"]))
      XCTAssertTrue(result.outcomes.allSatisfy { $0.success })
      calledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)

    guard let modifyOperation = fakeDatabase.modifyOperationsAdded.first else {
      return XCTFail("Expected a CKModifyRecordsOperation")
    }
    XCTAssertNil(modifyOperation.recordsToSave)
    XCTAssertEqual(
      Set(modifyOperation.recordIDsToDelete?.map { $0.recordName } ?? []),
      Set(["east-kept-a", "east-kept-b"]))
  }

  // 8. Multiple delete batches are supported: calling deleteKeptWisdomRecords
  // more than once against the same coordinator instance (exactly how the
  // Dart deletion runner drives >300-name purges, one CloudKit-safe batch
  // per call) produces one independent, correctly-scoped operation per call.
  func testDeleteKeptWisdomRecordsSupportsMultipleIndependentBatchCalls() {
    let zoneID = CloudKitRecordIdentity.zoneID
    let fakeDatabase = FakeDeletionTransportDatabase()
    let coordinator = CloudKitDeletionTransportCoordinator(database: fakeDatabase)

    fakeDatabase.deletedRecordIDsToReport = [CKRecord.ID(recordName: "east-kept-batch1-a", zoneID: zoneID)]
    let firstCalled = expectation(description: "first batch completion called")
    coordinator.deleteKeptWisdomRecords(recordNames: ["east-kept-batch1-a"]) { result in
      XCTAssertEqual(result.overallStatus, .allSucceeded)
      firstCalled.fulfill()
    }
    waitForExpectations(timeout: 1)

    fakeDatabase.deletedRecordIDsToReport = [CKRecord.ID(recordName: "east-kept-batch2-a", zoneID: zoneID)]
    let secondCalled = expectation(description: "second batch completion called")
    coordinator.deleteKeptWisdomRecords(recordNames: ["east-kept-batch2-a"]) { result in
      XCTAssertEqual(result.overallStatus, .allSucceeded)
      secondCalled.fulfill()
    }
    waitForExpectations(timeout: 1)

    XCTAssertEqual(fakeDatabase.modifyOperationsAdded.count, 2)
    XCTAssertEqual(
      fakeDatabase.modifyOperationsAdded[0].recordIDsToDelete?.map { $0.recordName },
      ["east-kept-batch1-a"])
    XCTAssertEqual(
      fakeDatabase.modifyOperationsAdded[1].recordIDsToDelete?.map { $0.recordName },
      ["east-kept-batch2-a"])
  }

  // 9. An already-absent record (`CKError.unknownItem`) is reported here as
  // an ordinary, per-record FAILURE outcome carrying that exact errorCode --
  // this coordinator never itself decides "already absent" means "success".
  // That idempotency decision is the Dart deletion runner's own policy
  // (`_deleteAllIdempotently`'s `errorCode == syncErrorCodeUnknownItem`
  // check) -- "Swift only reports what happened," exactly as
  // `cloud_kit_delete_records_contract.dart`'s own doc comment states. This
  // is the locked Slice 2 contract this test proves at the native boundary.
  func testDeleteKeptWisdomRecordsReportsUnknownItemAsPerRecordFailureNeverAsSuccess() {
    let zoneID = CloudKitRecordIdentity.zoneID
    let missingID = CKRecord.ID(recordName: "east-kept-already-gone", zoneID: zoneID)
    let fakeDatabase = FakeDeletionTransportDatabase()
    fakeDatabase.deletedRecordIDsToReport = []
    fakeDatabase.deleteCompletionError = CKError(
      .partialFailure,
      userInfo: [CKPartialErrorsByItemIDKey: [missingID: CKError(.unknownItem) as Error]])
    let coordinator = CloudKitDeletionTransportCoordinator(database: fakeDatabase)

    let calledOnce = expectation(description: "completion called")
    coordinator.deleteKeptWisdomRecords(recordNames: ["east-kept-already-gone"]) { result in
      XCTAssertEqual(result.overallStatus, .partialFailure)
      guard let outcome = result.outcomes.first else {
        return XCTFail("Expected one per-record outcome")
      }
      XCTAssertEqual(outcome.recordName, "east-kept-already-gone")
      XCTAssertFalse(
        outcome.success,
        "The native layer must never itself treat an already-absent record as a success")
      XCTAssertEqual(outcome.errorCode, CloudKitErrorClassifier.unknownItem)
      calledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  // 10. A genuine partial failure (one record succeeds, one genuinely fails
  // for a different reason) is surfaced as `.partialFailure` with a typed,
  // safe per-record errorCode -- never coerced into `.allSucceeded`.
  func testDeleteKeptWisdomRecordsSurfacesPartialFailureNeverAsFalseSuccess() {
    let zoneID = CloudKitRecordIdentity.zoneID
    let succeededID = CKRecord.ID(recordName: "east-kept-ok", zoneID: zoneID)
    let failedID = CKRecord.ID(recordName: "east-kept-failed", zoneID: zoneID)
    let fakeDatabase = FakeDeletionTransportDatabase()
    fakeDatabase.deletedRecordIDsToReport = [succeededID]
    fakeDatabase.deleteCompletionError = CKError(
      .partialFailure,
      userInfo: [CKPartialErrorsByItemIDKey: [failedID: CKError(.networkFailure) as Error]])
    let coordinator = CloudKitDeletionTransportCoordinator(database: fakeDatabase)

    let calledOnce = expectation(description: "completion called")
    coordinator.deleteKeptWisdomRecords(recordNames: ["east-kept-ok", "east-kept-failed"]) { result in
      XCTAssertEqual(result.overallStatus, .partialFailure)
      XCTAssertEqual(result.outcomes.count, 2)
      let succeeded = result.outcomes.first { $0.recordName == "east-kept-ok" }
      let failed = result.outcomes.first { $0.recordName == "east-kept-failed" }
      XCTAssertEqual(succeeded?.success, true)
      XCTAssertEqual(failed?.success, false)
      XCTAssertEqual(failed?.errorCode, CloudKitErrorClassifier.networkFailure)
      calledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  // 10b. A total transport failure (no per-record outcome could be attempted
  // at all, e.g. no network) is reported as `.transportFailure` -- distinct
  // from `.partialFailure`, and still never `.allSucceeded`.
  func testDeleteKeptWisdomRecordsReportsTransportFailureWhenNoRecordWasAttempted() {
    let fakeDatabase = FakeDeletionTransportDatabase()
    fakeDatabase.deletedRecordIDsToReport = []
    fakeDatabase.deleteCompletionError = CKError(.networkFailure)
    let coordinator = CloudKitDeletionTransportCoordinator(database: fakeDatabase)

    let calledOnce = expectation(description: "completion called")
    coordinator.deleteKeptWisdomRecords(recordNames: ["east-kept-a"]) { result in
      XCTAssertEqual(result.overallStatus, .transportFailure)
      XCTAssertTrue(result.outcomes.isEmpty)
      XCTAssertEqual(result.errorCode, CloudKitErrorClassifier.networkFailure)
      calledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  // 11. CKEastSyncState is never deleted by the deletion transport. Proven
  // two ways: (a) the listing query that discovers what to purge is itself
  // scoped to `keptWisdomRecordType` (test 4 above), so it can never return
  // the CKEastSyncState singleton's own recordName in the first place; and
  // (b) `deleteKeptWisdomRecords` operates purely on whatever opaque names
  // it is given -- in this coordinator's own real, only usage pattern (the
  // Dart deletion runner always feeds it exactly what
  // `listKeptWisdomRecordNames` returned), the canonical sync-state
  // recordName can therefore structurally never appear in a delete request.
  func testCanonicalSyncStateRecordNameNeverAppearsInADiscoveredDeleteRequest() {
    let fakeDatabase = FakeDeletionTransportDatabase()
    fakeDatabase.queryPageRecordNames = ["east-kept-a", "east-kept-b"]
    let coordinator = CloudKitDeletionTransportCoordinator(database: fakeDatabase)

    let listCalled = expectation(description: "list completion called")
    var discoveredNames: [String] = []
    coordinator.listKeptWisdomRecordNames { result in
      discoveredNames = result.recordNames
      listCalled.fulfill()
    }
    waitForExpectations(timeout: 1)

    let syncStateRecordName = CloudKitRecordIdentity.syncStateRecordID().recordName
    XCTAssertFalse(discoveredNames.contains(syncStateRecordName))

    fakeDatabase.deletedRecordIDsToReport = discoveredNames.map {
      CKRecord.ID(recordName: $0, zoneID: CloudKitRecordIdentity.zoneID)
    }
    let deleteCalled = expectation(description: "delete completion called")
    coordinator.deleteKeptWisdomRecords(recordNames: discoveredNames) { result in
      XCTAssertFalse(result.outcomes.map { $0.recordName }.contains(syncStateRecordName))
      deleteCalled.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  // 12. EASTKeptZone itself is never deleted -- structural proof: the
  // coordinator's own source never references a zone-deletion API at all
  // (`CKModifyRecordZonesOperation` with `recordZoneIDsToDelete`, or any
  // other zone-delete entry point). Mirrors test 5's own structural-scan
  // precedent for exactly the same reason (there is nothing at this
  // coordinator's public interface capable of deleting a zone to begin
  // with, so this is the correct way to prove a negative).
  func testDeletionTransportCoordinatorSourceNeverReferencesZoneDeletion() throws {
    let sourceURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Runner/CloudKitDeletionTransportCoordinator.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    XCTAssertFalse(source.contains("recordZoneIDsToDelete"))
    XCTAssertFalse(source.contains("deleteRecordZone"))
    XCTAssertFalse(source.contains("CKModifyRecordZonesOperation"))
  }

  // 14. Native diagnostics/errors do not expose recordName or private record
  // content -- every errorCode this coordinator ever surfaces is drawn only
  // from `CloudKitErrorClassifier`'s known symbolic vocabulary, mirroring
  // `testConfigureZoneErrorCodesNeverExposeLocalizedOrRawContent`'s own
  // established pattern for the zone coordinator.
  func testDeletionTransportErrorCodesNeverExposeRecordNameOrRawContent() {
    let zoneID = CloudKitRecordIdentity.zoneID
    let secretRecordName = "east-kept-\(UUID().uuidString)"
    let failedID = CKRecord.ID(recordName: secretRecordName, zoneID: zoneID)
    let fakeDatabase = FakeDeletionTransportDatabase()
    fakeDatabase.deletedRecordIDsToReport = []
    fakeDatabase.deleteCompletionError = CKError(
      .partialFailure,
      userInfo: [CKPartialErrorsByItemIDKey: [failedID: CKError(.networkFailure) as Error]])
    let coordinator = CloudKitDeletionTransportCoordinator(database: fakeDatabase)

    let knownCodes: Set<String> = [
      CloudKitErrorClassifier.networkUnavailable,
      CloudKitErrorClassifier.networkFailure,
      CloudKitErrorClassifier.serviceUnavailable,
      CloudKitErrorClassifier.requestRateLimited,
      CloudKitErrorClassifier.zoneBusy,
      CloudKitErrorClassifier.serverRecordChanged,
      CloudKitErrorClassifier.accountTemporarilyUnavailable,
      CloudKitErrorClassifier.notAuthenticated,
      CloudKitErrorClassifier.invalidArguments,
      CloudKitErrorClassifier.unknownItem,
      CloudKitErrorClassifier.incompatibleVersion,
      CloudKitErrorClassifier.quotaExceeded,
      CloudKitErrorClassifier.limitExceeded,
      CloudKitErrorClassifier.serverRejectedRequest,
      CloudKitErrorClassifier.unrecognizedNativeError,
    ]

    let calledOnce = expectation(description: "completion called")
    coordinator.deleteKeptWisdomRecords(recordNames: [secretRecordName]) { result in
      for outcome in result.outcomes {
        let code = outcome.errorCode ?? ""
        XCTAssertTrue(knownCodes.contains(code))
        XCTAssertFalse(code.contains(secretRecordName))
      }
      calledOnce.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  // 15. The epoch-barrier read targets CKEastSyncState only and preserves
  // the canonical, fixed record identity -- this coordinator's own read
  // side of the epoch barrier (`fetchSyncStateEpoch`, test 1 above already
  // asserts the exact recordID requested). The corresponding *write* goes
  // through the pre-existing, unmodified `CloudKitRecordTransportCoordinator`
  // / `CloudKitSyncStateCodec` path (already covered by
  // `testSyncStateCodecRoundTrips` and
  // `testTransportContainerIdentifierConstantIsExact` above) -- restated
  // here as an explicit, dedicated assertion that this coordinator's own
  // read never targets any identity other than the fixed singleton, even
  // across repeated calls.
  func testFetchSyncStateEpochAlwaysTargetsTheFixedCanonicalIdentity() {
    let fakeDatabase = FakeDeletionTransportDatabase()
    fakeDatabase.fetchRecordResult = (nil, CKError(.unknownItem))
    let coordinator = CloudKitDeletionTransportCoordinator(database: fakeDatabase)

    for _ in 0..<3 {
      let calledOnce = expectation(description: "completion called")
      coordinator.fetchSyncStateEpoch { _ in calledOnce.fulfill() }
      waitForExpectations(timeout: 1)
    }

    XCTAssertEqual(fakeDatabase.fetchedRecordIDs.count, 3)
    XCTAssertTrue(fakeDatabase.fetchedRecordIDs.allSatisfy { $0 == CloudKitRecordIdentity.syncStateRecordID() })
  }

}

private extension UIView {
  func descendant(withAccessibilityIdentifier identifier: String) -> UIView? {
    if accessibilityIdentifier == identifier { return self }
    for subview in subviews {
      if let match = subview.descendant(withAccessibilityIdentifier: identifier) {
        return match
      }
    }
    return nil
  }
}
