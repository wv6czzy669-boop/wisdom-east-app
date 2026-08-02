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

  // 1. Valid Kept encode/decode round trip (active form).
  func testKeptWisdomCodecRoundTripsActiveForm() throws {
    let record = try CloudKitKeptWisdomCodec.encodeActive(
      revealId: phase4CRevealIdA,
      wisdomText: "Be still and know.",
      revealedAtMs: 1_754_078_400_000,
      keptAtMs: 1_754_078_700_000,
      reflectionText: "A quiet thought.",
      reflectedAtMs: 1_754_078_700_000,
      updatedAtMs: 1_754_078_700_000,
      mutationId: phase4CMutationId,
      dataEpoch: phase4CDataEpoch
    )

    switch CloudKitKeptWisdomCodec.decode(record) {
    case .success(let envelope):
      XCTAssertFalse(envelope.isTombstone)
      XCTAssertEqual(envelope.revealId, phase4CRevealIdA)
      XCTAssertEqual(envelope.wisdomText, "Be still and know.")
      XCTAssertEqual(envelope.reflectionText, "A quiet thought.")
      XCTAssertEqual(envelope.mutationId, phase4CMutationId)
      XCTAssertEqual(envelope.dataEpoch, phase4CDataEpoch)
      XCTAssertEqual(envelope.schemaVersion, CloudKitRecordSchema.keptWisdomActiveSchemaVersion)
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

    switch CloudKitKeptWisdomCodec.decode(record) {
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

    switch CloudKitKeptWisdomCodec.decode(record) {
    case .success:
      XCTFail("Expected a malformed-field rejection")
    case .failure(let error):
      XCTAssertEqual(error, .malformedField(CloudKitRecordSchema.KeptWisdomField.wisdomText))
    }
  }

  // 8. A record-name/revealId mismatch is rejected.
  func testKeptWisdomCodecRejectsRecordNameMismatch() throws {
    let record = try CloudKitKeptWisdomCodec.encodeActive(
      revealId: phase4CRevealIdA,
      wisdomText: "Be still and know.",
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

    switch CloudKitKeptWisdomCodec.decode(record) {
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

    switch CloudKitKeptWisdomCodec.decode(tombstoneRecord) {
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
    // field indicates corruption or tampering -- never tolerated.
    tombstoneRecord[CloudKitRecordSchema.KeptWisdomField.wisdomText] = "smuggled content" as CKRecordValue
    switch CloudKitKeptWisdomCodec.decode(tombstoneRecord) {
    case .success:
      XCTFail("Expected rejection of a tombstone carrying forbidden content")
    case .failure(let error):
      XCTAssertEqual(error, .forbiddenFieldOnTombstone(CloudKitRecordSchema.KeptWisdomField.wisdomText))
    }
  }

  // 10. No content ever appears in safe error output -- a decode failure's
  // associated value is always one of this schema's own field-name
  // constants, never the malformed value itself.
  func testKeptWisdomCodecErrorsNeverExposeFieldContent() throws {
    let record = try CloudKitKeptWisdomCodec.encodeActive(
      revealId: phase4CRevealIdA,
      wisdomText: "This exact wisdom text must never appear in a decode error.",
      revealedAtMs: 1_754_078_400_000,
      keptAtMs: 1_754_078_700_000,
      reflectionText: "This exact reflection text must never appear either.",
      reflectedAtMs: 1_754_078_700_000,
      updatedAtMs: 1_754_078_700_000,
      mutationId: phase4CMutationId,
      dataEpoch: phase4CDataEpoch
    )
    record[CloudKitRecordSchema.KeptWisdomField.wisdomText] = 999 as CKRecordValue

    switch CloudKitKeptWisdomCodec.decode(record) {
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

}
