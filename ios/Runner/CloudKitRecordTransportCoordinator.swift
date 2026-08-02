import CloudKit
import Foundation

/// Build 26 Phase 4C-2: the narrow native transport for the two private
/// CloudKit record operations this phase adds -- atomically saving
/// validated `CKKeptWisdom`/`CKEastSyncState` records, and fetching
/// `EASTKeptZone`'s changes since an opaque prior server token. Built
/// directly on `CKModifyRecordsOperation`/`CKFetchRecordZoneChangesOperation`
/// (never `CKSyncEngine`, unavailable below iOS 17 -- this app's deployment
/// target is iOS 13 per `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md` §6),
/// using only the legacy completion-block API surface (`perRecordCompletionBlock`,
/// `modifyRecordsCompletionBlock`, `recordChangedBlock`,
/// `recordWithIDWasDeletedBlock`, `recordZoneFetchCompletionBlock`,
/// `fetchRecordZoneChangesCompletionBlock`) that has been available since
/// long before iOS 13, exactly like
/// `CloudKitPrivateZoneCoordinator`'s existing `modifyRecordZonesCompletionBlock`
/// usage.
///
/// Reuses `CloudKitPrivateZoneCoordinator.swift`'s existing
/// `CloudKitZoneOperationDatabase` seam (`fetch(withRecordZoneID:completionHandler:)`
/// + `add(_ operation: CKDatabaseOperation)`) rather than inventing a
/// second injectable database protocol -- both new operation types here are
/// `CKDatabaseOperation` subclasses, so the existing `add(_:)` requirement
/// already covers them; this file adds no new production dependency on
/// `CKDatabase` beyond what that protocol already narrows to.
///
/// **Save-policy decision (architecture does not yet name one explicitly;
/// disclosed here rather than silently chosen):** `.ifServerRecordUnchanged`.
/// This is the only policy consistent with "never silently overwrite a
/// server version when conflict detection requires a change tag" and with
/// §4.2's explicit reliance on `CKError.serverRecordChanged` as the signal
/// to re-run conflict resolution -- `.changedKeys`/`.allKeys` both bypass
/// that detection entirely and were rejected for that reason.
///
/// **Deletion (architecture already answers this, not a gap):** never
/// physical. §4.2 is explicit that "a delete is represented as a
/// tombstone-form update to the same record... not a native CloudKit record
/// deletion" -- `recordIDsToDelete` is therefore always `nil` on every
/// `CKModifyRecordsOperation` this coordinator builds (see
/// `testModifyRecordsNeverUsesPhysicalDeletion` in `RunnerTests.swift`).
///
/// Build 26 Phase 4C-2 correction: a fetch never surfaces a list of
/// deleted record names, even defensively -- the successful-fetch contract
/// (native and Dart alike) carries no such field at all. If
/// `CKFetchRecordZoneChangesOperation` ever calls
/// `recordWithIDWasDeletedBlock` regardless (this transport itself never
/// causes one, per §4.2 above; only an out-of-band actor -- e.g. a manual
/// CloudKit Dashboard deletion -- could produce one), that is treated as
/// evidence this architecture's tombstone-only invariant has been violated
/// out of band, and the entire fetch fails closed with the distinct,
/// stable `ZoneChangesOutcome.unexpectedPhysicalDeletion` outcome: no
/// changed records are returned as if the fetch had succeeded, no token is
/// returned, and the deleted record's own name is never captured, logged,
/// or exposed anywhere in the result -- only the fact that this occurred.
/// This is not a real record identity anyone downstream should ever see
/// through this transport; it is refused, not reported.
///
/// **`changeTokenExpired` (a genuine, disclosed gap fill):** the
/// architecture document does not yet define a vocabulary entry for
/// `CKError.Code.changeTokenExpired`. This coordinator intercepts it before
/// it would otherwise fall through to a generic errorCode, and reports it
/// as a first-class `ZoneChangesOutcome.tokenExpired` instead -- its only
/// correct handling (discard the token, resync from `nil`) is categorically
/// different from an ordinary retryable/permanent failure, so folding it
/// into the generic error vocabulary would misrepresent what a caller must
/// actually do about it.
final class CloudKitRecordTransportCoordinator {
  // MARK: - Modify (save)

  struct ModifyOutcome {
    let recordName: String
    let success: Bool
    let systemFields: String?
    let errorCode: String?
  }

  enum ModifyOverallStatus: String {
    case allSucceeded
    case partialFailure
    case transportFailure
  }

  struct ModifyResult {
    let overallStatus: ModifyOverallStatus
    let outcomes: [ModifyOutcome]
    let errorCode: String?
  }

  /// One record to save: an already-built `CKRecord` (via
  /// `CloudKitRecordEnvelopeArgumentParser.buildRecord`, which itself
  /// already passed the Phase 4C-1 codec's own encode validation), plus the
  /// opaque, previously-observed system-fields blob to save it against, if
  /// any.
  struct ModifyInput {
    let record: CKRecord
    let previousSystemFields: String?
  }

  // MARK: - Fetch (zone changes)

  enum ZoneChangesOutcome: String {
    case success
    case tokenExpired

    /// Build 26 Phase 4C-2 correction: a physical CloudKit record deletion
    /// was observed inside `EASTKeptZone`. This architecture is
    /// tombstone-only (§4.2) -- this transport never issues a physical
    /// deletion itself, so observing one indicates an out-of-band actor
    /// bypassed that invariant. Fails the whole fetch closed: never a
    /// success carrying otherwise-valid changed records, never a token,
    /// never the deleted record's own name.
    case unexpectedPhysicalDeletion

    case failure
  }

  struct ZoneChangesResult {
    let outcome: ZoneChangesOutcome
    let changedKeptWisdomRecords: [CloudKitKeptWisdomWireEnvelope]
    let changedSyncStateRecords: [CloudKitSyncStateWireEnvelope]
    let serverToken: String?
    let errorCode: String?
  }

  private let database: CloudKitZoneOperationDatabase

  init(database: CloudKitZoneOperationDatabase) {
    self.database = database
  }

  /// Atomically saves every input's record. An empty `inputs` array is a
  /// well-defined no-op: completes immediately with `.allSucceeded` and no
  /// outcomes, never creates a `CKModifyRecordsOperation` at all.
  func modifyRecords(_ inputs: [ModifyInput], completion: @escaping (ModifyResult) -> Void) {
    if inputs.isEmpty {
      completion(ModifyResult(overallStatus: .allSucceeded, outcomes: [], errorCode: nil))
      return
    }

    var outcomes: [ModifyOutcome] = []
    var recordsToSave: [CKRecord] = []

    for input in inputs {
      // Defense-in-depth: every record this coordinator ever adds to a
      // save operation is re-verified to be in EASTKeptZone here, even
      // though `CloudKitRecordEnvelopeArgumentParser` already guarantees
      // this for anything it successfully built -- never trusted
      // transitively without a second check at the transport boundary
      // itself (native test: "wrong-zone request rejection").
      guard input.record.recordID.zoneID.zoneName == CloudKitRecordSchema.zoneName else {
        outcomes.append(
          ModifyOutcome(
            recordName: input.record.recordID.recordName,
            success: false,
            systemFields: nil,
            errorCode: CloudKitErrorClassifier.invalidArguments
          ))
        continue
      }

      guard let previousSystemFields = input.previousSystemFields else {
        recordsToSave.append(input.record)
        continue
      }

      guard let baseline = CloudKitOpaqueArchive.unarchiveSystemFields(previousSystemFields) else {
        // A corrupt/foreign previousSystemFields blob fails this one
        // record closed -- never silently ignored, never treated as "no
        // prior version known" (which would defeat the conflict-detection
        // guarantee this exists to provide).
        outcomes.append(
          ModifyOutcome(
            recordName: input.record.recordID.recordName,
            success: false,
            systemFields: nil,
            errorCode: CloudKitErrorClassifier.invalidArguments
          ))
        continue
      }
      for key in input.record.allKeys() {
        baseline[key] = input.record[key]
      }
      recordsToSave.append(baseline)
    }

    guard !recordsToSave.isEmpty else {
      // Every input failed a pre-operation check above -- no operation is
      // ever created (native test: "invalid codec payload rejected before
      // operation creation").
      completion(ModifyResult(overallStatus: .partialFailure, outcomes: outcomes, errorCode: nil))
      return
    }

    let expectedTotal = outcomes.count + recordsToSave.count
    let operation = CKModifyRecordsOperation(recordsToSave: recordsToSave, recordIDsToDelete: nil)
    operation.savePolicy = .ifServerRecordUnchanged
    operation.perRecordCompletionBlock = { record, error in
      if let error = error {
        outcomes.append(
          ModifyOutcome(
            recordName: record.recordID.recordName,
            success: false,
            systemFields: nil,
            errorCode: CloudKitErrorClassifier.symbolicCode(for: error)
          ))
        return
      }
      let systemFields = CloudKitOpaqueArchive.archiveSystemFields(of: record)
      outcomes.append(
        ModifyOutcome(
          recordName: record.recordID.recordName,
          success: true,
          systemFields: systemFields,
          errorCode: nil
        ))
    }
    operation.modifyRecordsCompletionBlock = { _, _, error in
      // No per-record outcome was ever collected -- the operation itself
      // never got to attempt a single record (e.g. no network). Reported
      // as a transport-level failure, never as every record individually
      // failing (which would misrepresent that CloudKit never actually
      // tried them).
      if outcomes.isEmpty, let error = error {
        completion(
          ModifyResult(
            overallStatus: .transportFailure,
            outcomes: [],
            errorCode: CloudKitErrorClassifier.symbolicCode(for: error)
          ))
        return
      }

      let allSucceeded = outcomes.count == expectedTotal && outcomes.allSatisfy { $0.success }
      completion(
        ModifyResult(
          overallStatus: allSucceeded ? .allSucceeded : .partialFailure,
          outcomes: outcomes,
          errorCode: nil
        ))
    }
    operation.qualityOfService = .userInitiated
    database.add(operation)
  }

  /// Fetches every `EASTKeptZone` change since `previousServerToken`
  /// (`nil` for an initial, full fetch), aggregating every page CloudKit
  /// reports internally (`fetchAllChanges = true`) before this coordinator
  /// ever calls back once.
  func fetchZoneChanges(
    previousServerToken: String?, completion: @escaping (ZoneChangesResult) -> Void
  ) {
    var previousToken: CKServerChangeToken?
    if let previousServerToken = previousServerToken {
      guard let token = CloudKitOpaqueArchive.unarchiveServerChangeToken(previousServerToken) else {
        completion(
          ZoneChangesResult(
            outcome: .failure,
            changedKeptWisdomRecords: [],
            changedSyncStateRecords: [],
            serverToken: nil,
            errorCode: CloudKitErrorClassifier.invalidArguments
          ))
        return
      }
      previousToken = token
    }

    let zoneID = CloudKitRecordIdentity.zoneID
    let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
    configuration.previousServerChangeToken = previousToken

    let operation = CKFetchRecordZoneChangesOperation(
      recordZoneIDs: [zoneID],
      configurationsByRecordZoneID: [zoneID: configuration]
    )
    operation.fetchAllChanges = true

    var changedKeptWisdomRecords: [CloudKitKeptWisdomWireEnvelope] = []
    var changedSyncStateRecords: [CloudKitSyncStateWireEnvelope] = []
    var sawUndecodableRecord = false
    // Deliberately a Bool, never a collected list of names or record IDs --
    // the deleted record's own identity must never be captured anywhere in
    // this coordinator, including in memory pending completion. See this
    // file's own top doc comment ("Deletion") for the full rationale.
    var sawUnexpectedPhysicalDeletion = false
    var finalToken: CKServerChangeToken?
    var zoneFetchError: Error?

    operation.recordChangedBlock = { record in
      guard record.recordID.zoneID.zoneName == CloudKitRecordSchema.zoneName else {
        sawUndecodableRecord = true
        return
      }
      switch record.recordType {
      case CloudKitRecordSchema.keptWisdomRecordType:
        switch CloudKitKeptWisdomCodec.decode(record) {
        case .success(let envelope):
          changedKeptWisdomRecords.append(envelope)
        case .failure:
          // Fails this one record closed, never the whole fetch -- but
          // this transport also never claims a fully-successful fetch
          // happened while silently discarding a record it could not
          // trust (native test: "malformed returned record rejected").
          sawUndecodableRecord = true
        }
      case CloudKitRecordSchema.syncStateRecordType:
        switch CloudKitSyncStateCodec.decode(record) {
        case .success(let envelope):
          changedSyncStateRecords.append(envelope)
        case .failure:
          sawUndecodableRecord = true
        }
      default:
        sawUndecodableRecord = true
      }
    }

    operation.recordWithIDWasDeletedBlock = { recordID, _ in
      // This transport itself never issues a physical deletion (§4.2).
      // Observing one at all -- in this zone -- is treated as an
      // out-of-band architecture violation, never silently accepted and
      // never merely noted: the deleted record's own name is intentionally
      // discarded (never read, never stored, never logged) and only the
      // fact that this happened is recorded, so a caller can never recover
      // or infer which record was deleted through this transport.
      guard recordID.zoneID.zoneName == CloudKitRecordSchema.zoneName else { return }
      sawUnexpectedPhysicalDeletion = true
    }

    operation.recordZoneFetchCompletionBlock = { _, token, _, _, error in
      finalToken = token
      zoneFetchError = error
    }

    operation.fetchRecordZoneChangesCompletionBlock = { operationError in
      // Checked first, before every other outcome: an out-of-band physical
      // deletion is treated as more significant than a concurrent token
      // expiry, transport error, or decode failure -- whatever else this
      // fetch observed, it must never be reported as if it had succeeded
      // (or as any outcome other than this one) once this has happened.
      if sawUnexpectedPhysicalDeletion {
        completion(
          ZoneChangesResult(
            outcome: .unexpectedPhysicalDeletion,
            changedKeptWisdomRecords: [],
            changedSyncStateRecords: [],
            serverToken: nil,
            errorCode: nil
          ))
        return
      }
      let effectiveError = operationError ?? zoneFetchError
      if let ckError = effectiveError as? CKError, ckError.code == .changeTokenExpired {
        completion(
          ZoneChangesResult(
            outcome: .tokenExpired,
            changedKeptWisdomRecords: [],
            changedSyncStateRecords: [],
            serverToken: nil,
            errorCode: nil
          ))
        return
      }
      if let effectiveError = effectiveError {
        completion(
          ZoneChangesResult(
            outcome: .failure,
            changedKeptWisdomRecords: [],
            changedSyncStateRecords: [],
            serverToken: nil,
            errorCode: CloudKitErrorClassifier.symbolicCode(for: effectiveError)
          ))
        return
      }
      if sawUndecodableRecord {
        completion(
          ZoneChangesResult(
            outcome: .failure,
            changedKeptWisdomRecords: [],
            changedSyncStateRecords: [],
            serverToken: nil,
            errorCode: CloudKitErrorClassifier.unrecognizedNativeError
          ))
        return
      }
      guard let finalToken = finalToken,
        let archivedToken = CloudKitOpaqueArchive.archiveServerChangeToken(finalToken)
      else {
        completion(
          ZoneChangesResult(
            outcome: .failure,
            changedKeptWisdomRecords: [],
            changedSyncStateRecords: [],
            serverToken: nil,
            errorCode: CloudKitErrorClassifier.unrecognizedNativeError
          ))
        return
      }
      completion(
        ZoneChangesResult(
          outcome: .success,
          changedKeptWisdomRecords: changedKeptWisdomRecords,
          changedSyncStateRecords: changedSyncStateRecords,
          serverToken: archivedToken,
          errorCode: nil
        ))
    }

    operation.qualityOfService = .userInitiated
    database.add(operation)
  }
}
