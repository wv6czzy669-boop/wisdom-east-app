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

}
