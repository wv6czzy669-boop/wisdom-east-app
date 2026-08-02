import CloudKit
import Flutter
import UIKit
import XCTest

@testable import Runner

class RunnerTests: XCTestCase {

  func testExample() {
    // If you add code to the Runner application, consider adding tests here.
    // See https://developer.apple.com/documentation/xctest for more information about using XCTest.
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
  }

  func testErrorClassifierMapsNonCKErrorToUnrecognized() {
    struct SomeOtherError: Error {}
    XCTAssertEqual(
      CloudKitErrorClassifier.symbolicCode(for: SomeOtherError()),
      CloudKitErrorClassifier.unrecognizedNativeError)
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
      completionHandler: @escaping (CKRecordZone?, Error?) -> Void
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
        modifyOperation.modifyRecordZonesCompletionBlock?(nil, nil, error)
      } else {
        modifyOperation.modifyRecordZonesCompletionBlock?([], nil, nil)
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

}
