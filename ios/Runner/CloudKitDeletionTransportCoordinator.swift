import CloudKit
import Foundation

/// Build 26 Phase 5 (slice 2): the narrow surface
/// `CloudKitDeletionTransportCoordinator` needs from a CloudKit database --
/// a single-record fetch (for the epoch-barrier read) plus `add(_:)` (both
/// the listing query and the batched delete are `CKDatabaseOperation`
/// subclasses). Deliberately a new, separate protocol from
/// `CloudKitPrivateZoneCoordinator.swift`'s existing
/// `CloudKitZoneOperationDatabase` -- rather than widening that shared
/// protocol (which every existing `CloudKitPrivateZoneCoordinator`/
/// `CloudKitRecordTransportCoordinator` test fake would then also have to
/// implement) -- this keeps this phase's addition fully isolated from the
/// two already-locked, already-tested coordinators it must never regress.
/// `CKDatabase` conforms below via a plain, empty extension -- it already
/// implements both requirements with matching signatures, so this is not a
/// behavior change for any production caller
/// (`CloudKitSyncBridge.swift` is otherwise unmodified by this addition).
protocol CloudKitDeletionTransportDatabase {
  func fetch(
    withRecordID recordID: CKRecord.ID,
    completionHandler: @escaping (CKRecord?, Error?) -> Void
  )
  func add(_ operation: CKDatabaseOperation)
}

extension CKDatabase: CloudKitDeletionTransportDatabase {}

/// Build 26 Phase 5 (slice 2): the narrow native transport for the Phase 5
/// remote deletion runner's three CloudKit operations -- reading the
/// `CKEastSyncState` singleton's current epoch, listing every `CKKeptWisdom`
/// record's identity (content-free), and physically deleting named
/// `CKKeptWisdom` records.
///
/// **Deliberately separate from `CloudKitRecordTransportCoordinator`:**
/// that coordinator's own `modifyRecords` has a locked, tested invariant
/// (`testModifyRecordsNeverUsesPhysicalDeletion`) that it never issues a
/// physical CloudKit record deletion -- normal sync remains tombstone-only.
/// This coordinator's entire purpose is the opposite: Phase 5's "Remove
/// from iCloud" is a genuine physical purge of every `CKKeptWisdom` record,
/// which must never be reachable through, or confused with, normal sync's
/// save-only transport. Keeping this as an entirely separate type -- never
/// a mode flag or parameter added to `CloudKitRecordTransportCoordinator`
/// -- keeps that existing invariant provably unweakened.
///
/// Only ever invoked by `CloudKitSyncBridge`'s three new
/// `handleFetchSyncStateEpoch`/`handleListKeptWisdomRecordNames`/
/// `handleDeleteKeptWisdomRecords` methods, exactly like
/// `CloudKitRecordTransportCoordinator` is only ever invoked by its own two
/// existing handlers -- this coordinator performs no `CKDatabase` operation
/// on its own initiative.
final class CloudKitDeletionTransportCoordinator {
  // MARK: - Sync-state epoch read

  enum SyncStateEpochOutcome: String {
    case found
    case notFound
    case failure
  }

  struct SyncStateEpochResult {
    let outcome: SyncStateEpochOutcome
    let dataEpoch: String?
    let systemFields: String?
    let errorCode: String?
  }

  // MARK: - Kept-wisdom record-name listing

  enum RecordNamesOutcome: String {
    case success
    case failure
  }

  struct RecordNamesResult {
    let outcome: RecordNamesOutcome
    let recordNames: [String]
    let errorCode: String?
  }

  // MARK: - Kept-wisdom physical deletion

  struct DeleteOutcome {
    let recordName: String
    let success: Bool
    let errorCode: String?
  }

  enum DeleteOverallStatus: String {
    case allSucceeded
    case partialFailure
    case transportFailure
  }

  struct DeleteResult {
    let overallStatus: DeleteOverallStatus
    let outcomes: [DeleteOutcome]
    let errorCode: String?
  }

  private let database: CloudKitDeletionTransportDatabase

  init(database: CloudKitDeletionTransportDatabase) {
    self.database = database
  }

  /// Reads the `CKEastSyncState` singleton directly by its fixed identity
  /// (`CloudKitRecordIdentity.syncStateRecordID()`) -- never bundled with
  /// any `CKKeptWisdom` content, unlike `fetchPrivateZoneChanges`. `.
  /// unknownItem` (the record has never been created) is reported as
  /// `.notFound`, never as `.failure` -- an ordinary, expected state, not an
  /// error.
  func fetchSyncStateEpoch(completion: @escaping (SyncStateEpochResult) -> Void) {
    let recordID = CloudKitRecordIdentity.syncStateRecordID()
    database.fetch(withRecordID: recordID) { record, error in
      if let ckError = error as? CKError, ckError.code == .unknownItem {
        completion(
          SyncStateEpochResult(outcome: .notFound, dataEpoch: nil, systemFields: nil, errorCode: nil))
        return
      }
      if let error = error {
        completion(
          SyncStateEpochResult(
            outcome: .failure, dataEpoch: nil, systemFields: nil,
            errorCode: CloudKitErrorClassifier.symbolicCode(for: error)))
        return
      }
      guard let record = record else {
        completion(
          SyncStateEpochResult(
            outcome: .failure, dataEpoch: nil, systemFields: nil,
            errorCode: CloudKitErrorClassifier.unrecognizedNativeError))
        return
      }
      switch CloudKitSyncStateCodec.decode(record) {
      case .success(let envelope):
        guard let systemFields = CloudKitOpaqueArchive.archiveSystemFields(of: record),
          !systemFields.isEmpty
        else {
          completion(
            SyncStateEpochResult(
              outcome: .failure, dataEpoch: nil, systemFields: nil,
              errorCode: CloudKitErrorClassifier.unrecognizedNativeError))
          return
        }
        completion(
          SyncStateEpochResult(
            outcome: .found, dataEpoch: envelope.dataEpoch, systemFields: systemFields,
            errorCode: nil))
      case .failure:
        completion(
          SyncStateEpochResult(
            outcome: .failure, dataEpoch: nil, systemFields: nil,
            errorCode: CloudKitErrorClassifier.unrecognizedNativeError))
      }
    }
  }

  /// Lists every `CKKeptWisdom` record currently in `EASTKeptZone`, by
  /// `recordName` only (`desiredKeys = []` -- no field data is ever fetched
  /// from CloudKit for this query), aggregating every page via cursor
  /// before this coordinator ever calls back once, exactly like
  /// `CloudKitRecordTransportCoordinator.fetchZoneChanges`'s own
  /// `fetchAllChanges = true` aggregates internally for its own read.
  func listKeptWisdomRecordNames(completion: @escaping (RecordNamesResult) -> Void) {
    var recordNames: [String] = []

    func runQuery(cursor: CKQueryOperation.Cursor?) {
      let operation: CKQueryOperation
      if let cursor = cursor {
        operation = CKQueryOperation(cursor: cursor)
      } else {
        let query = CKQuery(
          recordType: CloudKitRecordSchema.keptWisdomRecordType, predicate: NSPredicate(value: true))
        operation = CKQueryOperation(query: query)
        operation.zoneID = CloudKitRecordIdentity.zoneID
      }
      operation.desiredKeys = []
      operation.recordFetchedBlock = { record in
        recordNames.append(record.recordID.recordName)
      }
      operation.queryCompletionBlock = { nextCursor, error in
        if let error = error {
          completion(
            RecordNamesResult(
              outcome: .failure, recordNames: [],
              errorCode: CloudKitErrorClassifier.symbolicCode(for: error)))
          return
        }
        if let nextCursor = nextCursor {
          runQuery(cursor: nextCursor)
          return
        }
        completion(RecordNamesResult(outcome: .success, recordNames: recordNames, errorCode: nil))
      }
      operation.qualityOfService = .userInitiated
      database.add(operation)
    }

    runQuery(cursor: nil)
  }

  /// Physically deletes exactly the named records from `EASTKeptZone` in
  /// one `CKModifyRecordsOperation(recordIDsToDelete:)`. The caller (the
  /// Dart-side deletion runner) is responsible for keeping `recordNames`
  /// within a single CloudKit-safe batch size -- this coordinator performs
  /// no internal chunking of its own, mirroring
  /// `CloudKitRecordTransportCoordinator.modifyRecords`'s own "one call, one
  /// operation" shape.
  ///
  /// Uses only the legacy completion-block API (deployment target iOS 13,
  /// same constraint as every other coordinator in this file): per-record
  /// delete outcomes are recovered from `modifyRecordsCompletionBlock`'s own
  /// `deletedRecordIDs` (successes) and, for failures, from a
  /// `CKError.partialFailure`'s `partialErrorsByItemID` dictionary -- the
  /// legacy API has no `perRecordDeleteBlock` (that is an iOS 15+
  /// addition).
  func deleteKeptWisdomRecords(
    recordNames: [String], completion: @escaping (DeleteResult) -> Void
  ) {
    if recordNames.isEmpty {
      completion(DeleteResult(overallStatus: .allSucceeded, outcomes: [], errorCode: nil))
      return
    }

    let zoneID = CloudKitRecordIdentity.zoneID
    let recordIDs = recordNames.map { CKRecord.ID(recordName: $0, zoneID: zoneID) }

    let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIDs)
    operation.modifyRecordsCompletionBlock = { _, deletedRecordIDs, error in
      var outcomes: [DeleteOutcome] = []
      var succeededNames = Set<String>()
      for recordID in deletedRecordIDs ?? [] {
        succeededNames.insert(recordID.recordName)
        outcomes.append(DeleteOutcome(recordName: recordID.recordName, success: true, errorCode: nil))
      }

      if let ckError = error as? CKError, ckError.code == .partialFailure,
        let perItem = ckError.partialErrorsByItemID as? [CKRecord.ID: Error]
      {
        for (recordID, itemError) in perItem {
          if succeededNames.contains(recordID.recordName) { continue }
          outcomes.append(
            DeleteOutcome(
              recordName: recordID.recordName, success: false,
              errorCode: CloudKitErrorClassifier.symbolicCode(for: itemError)))
        }
        let allSucceeded = outcomes.count == recordIDs.count && outcomes.allSatisfy { $0.success }
        completion(
          DeleteResult(
            overallStatus: allSucceeded ? .allSucceeded : .partialFailure, outcomes: outcomes,
            errorCode: nil))
        return
      }

      if let error = error {
        // No per-record outcome was ever collected -- the operation itself
        // never got to attempt a single record (e.g. no network). Reported
        // as a transport-level failure, never as every record individually
        // failing.
        if outcomes.isEmpty {
          completion(
            DeleteResult(
              overallStatus: .transportFailure, outcomes: [],
              errorCode: CloudKitErrorClassifier.symbolicCode(for: error)))
          return
        }
        completion(DeleteResult(overallStatus: .partialFailure, outcomes: outcomes, errorCode: nil))
        return
      }

      let allSucceeded = outcomes.count == recordIDs.count && outcomes.allSatisfy { $0.success }
      completion(
        DeleteResult(
          overallStatus: allSucceeded ? .allSucceeded : .partialFailure, outcomes: outcomes,
          errorCode: nil))
    }
    operation.qualityOfService = .userInitiated
    database.add(operation)
  }
}
