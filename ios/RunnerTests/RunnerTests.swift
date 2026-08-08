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
    // field indicates corruption or tampering -- never tolerated.
    tombstoneRecord[CloudKitRecordSchema.KeptWisdomField.wisdomText] = "smuggled content" as CKRecordValue
    switch CloudKitKeptWisdomCodec.decode(
      tombstoneRecord, systemFields: sampleSystemFields(for: tombstoneRecord)
    ) {
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
    var zoneChangesDeletedRecordIDs: [(CKRecord.ID, String)] = []
    var zoneChangesFetchError: Error?
    var zoneChangesOverallError: Error?

    func fetch(
      withRecordZoneID zoneID: CKRecordZone.ID,
      completionHandler: @escaping (CKRecordZone?, Error?) -> Void
    ) {
      completionHandler(fetchOutcome.0, fetchOutcome.1)
    }

    func add(_ operation: CKDatabaseOperation) {
      addedOperations.append(operation)

      if let modifyOperation = operation as? CKModifyRecordsOperation {
        let records = modifyOperation.recordsToSave ?? []
        for (index, record) in records.enumerated() {
          guard index < perRecordModifyErrors.count else { continue }
          modifyOperation.perRecordCompletionBlock?(record, perRecordModifyErrors[index])
        }
        modifyOperation.modifyRecordsCompletionBlock?(nil, nil, modifyOverallError)
        return
      }

      if let fetchOperation = operation as? CKFetchRecordZoneChangesOperation {
        for record in zoneChangesRecordsToReport {
          fetchOperation.recordChangedBlock?(record)
        }
        for (recordID, recordType) in zoneChangesDeletedRecordIDs {
          fetchOperation.recordWithIDWasDeletedBlock?(recordID, recordType)
        }
        fetchOperation.recordZoneFetchCompletionBlock?(
          CloudKitRecordIdentity.zoneID, nil, nil, false, zoneChangesFetchError)
        fetchOperation.fetchRecordZoneChangesCompletionBlock?(zoneChangesOverallError)
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
      revealId: phase4CRevealIdA, wisdomText: "A", revealedAtMs: 1, keptAtMs: 1,
      reflectionText: nil, reflectedAtMs: nil, updatedAtMs: 1,
      mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)
    let recordB = try CloudKitKeptWisdomCodec.encodeActive(
      revealId: phase4CRevealIdB, wisdomText: "B", revealedAtMs: 1, keptAtMs: 1,
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
      revealId: phase4CRevealIdA, wisdomText: "A", revealedAtMs: 1, keptAtMs: 1,
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
      revealId: phase4CRevealIdA, wisdomText: "A", revealedAtMs: 1, keptAtMs: 1,
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
      revealId: phase4CRevealIdA, wisdomText: "A", revealedAtMs: 1, keptAtMs: 1,
      reflectionText: nil, reflectedAtMs: nil, updatedAtMs: 1,
      mutationId: phase4CMutationId, dataEpoch: phase4CDataEpoch)
    let recordB = try CloudKitKeptWisdomCodec.encodeActive(
      revealId: phase4CRevealIdB, wisdomText: "B", revealedAtMs: 1, keptAtMs: 1,
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
      revealId: phase4CRevealIdA, wisdomText: "A", revealedAtMs: 1, keptAtMs: 1,
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
      revealId: phase4CRevealIdA, wisdomText: "A", revealedAtMs: 1, keptAtMs: 1,
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

}
