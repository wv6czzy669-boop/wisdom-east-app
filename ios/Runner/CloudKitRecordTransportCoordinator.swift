import CloudKit
import Foundation

/// Build 26 Phase 4C-2: the narrow native transport for the two private
/// CloudKit record operations this phase adds -- atomically saving
/// validated `CKKeptWisdom`/`CKEastSyncState` records, and fetching
/// `EASTKeptZone`'s changes since an opaque prior server token. Built
/// directly on `CKModifyRecordsOperation`/`CKFetchRecordZoneChangesOperation`
/// (never `CKSyncEngine`, unavailable below iOS 17 -- this app's deployment
/// target is iOS 15), using CloudKit's typed iOS 15 result callbacks.
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
///
/// **Build 26 Phase 4E-3a (fetched system-fields transport hardening):**
/// every changed `CKKeptWisdom` record this coordinator returns (active or
/// soft-tombstone alike) now also carries that exact `CKRecord`'s own
/// archived system fields (`CloudKitOpaqueArchive.archiveSystemFields(of:)`
/// -- the same mechanism `modifyRecords`'s `perRecordSaveBlock`
/// already uses on the save path), so a future local edit to a
/// remotely-adopted record can use CloudKit's own
/// `.ifServerRecordUnchanged` optimistic-concurrency precondition instead
/// of an unconditional overwrite. Archiving happens in `fetchZoneChanges`
/// itself, immediately inside `recordWasChangedBlock`, *before* handing the
/// record to `CloudKitKeptWisdomCodec.decode` -- if archiving ever fails or
/// produces an empty value, that one record fails closed via the same
/// `sawUndecodableRecord` mechanism an undecodable record already uses;
/// this coordinator never emits a changed `CKKeptWisdom` record with
/// missing or fabricated system fields. `CKEastSyncState` records and the
/// physical-deletion path are unaffected by this change.
final class CloudKitRecordTransportCoordinator {
  private final class LockedState<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
      self.value = value
    }

    func withValue<Result>(_ body: (inout Value) -> Result) -> Result {
      lock.lock()
      defer { lock.unlock() }
      return body(&value)
    }

    func snapshot() -> Value {
      withValue { $0 }
    }
  }

  private struct ZoneChangesAccumulator {
    var changedKeptWisdomRecords: [CloudKitKeptWisdomWireEnvelope] = []
    var changedSyncStateRecords: [CloudKitSyncStateWireEnvelope] = []
    var sawUndecodableRecord = false
    var sawUnexpectedPhysicalDeletion = false
    var finalToken: CKServerChangeToken?
    var zoneFetchError: Error?
    var recordChangeError: Error?
  }

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
      // Build 26 Phase 4H-4 (real-device + CloudKit-dashboard
      // investigation): this must iterate `changedKeys()`, never
      // `allKeys()`. `allKeys()` returns only the keys `input.record`
      // *currently holds a value for* -- a field `input.record` explicitly
      // cleared via `= nil` (e.g. `CloudKitKeptWisdomCodec.encodeTombstone`
      // removing every forbidden-on-tombstone field) is, by definition, no
      // longer "currently set," so it would never appear in `allKeys()`
      // and that removal would silently never reach `baseline` at all --
      // `baseline` (reconstructed from system fields only, per
      // `CloudKitOpaqueArchive.unarchiveSystemFields`'s own contract, "no
      // user field values -- there were none to restore") would then still
      // have no local knowledge of that field either way, so CloudKit's
      // save would leave the server's existing value for it completely
      // untouched. `changedKeys()` instead returns every key
      // `input.record` has *touched* since its own creation, additions and
      // explicit removals alike, which is exactly what must be copied onto
      // `baseline` for a removal to actually propagate. This was proven,
      // via real-device and CloudKit Dashboard evidence, to be why an
      // already-synced active record's fields survived, unwanted, on its
      // tombstone after this exact save path.
      for key in input.record.changedKeys() {
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
    let outcomeState = LockedState(outcomes)
    let operation = CKModifyRecordsOperation(recordsToSave: recordsToSave, recordIDsToDelete: nil)
    operation.savePolicy = .ifServerRecordUnchanged
    operation.perRecordSaveBlock = { recordID, result in
      switch result {
      case .failure(let error):
        outcomeState.withValue {
          $0.append(
            ModifyOutcome(
              recordName: recordID.recordName,
              success: false,
              systemFields: nil,
              errorCode: CloudKitErrorClassifier.symbolicCode(for: error)
            ))
        }
      case .success(let record):
        let systemFields = CloudKitOpaqueArchive.archiveSystemFields(of: record)
        outcomeState.withValue {
          $0.append(
            ModifyOutcome(
              recordName: record.recordID.recordName,
              success: true,
              systemFields: systemFields,
              errorCode: nil
            ))
        }
      }
    }
    operation.modifyRecordsResultBlock = { result in
      let outcomes = outcomeState.snapshot()
      // No per-record outcome was ever collected -- the operation itself
      // never got to attempt a single record (e.g. no network). Reported
      // as a transport-level failure, never as every record individually
      // failing (which would misrepresent that CloudKit never actually
      // tried them).
      if outcomes.isEmpty, case .failure(let error) = result {
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

    let state = LockedState(ZoneChangesAccumulator())

    operation.recordWasChangedBlock = { _, result in
      guard case .success(let record) = result else {
        if case .failure(let error) = result {
          state.withValue { $0.recordChangeError = error }
        }
        return
      }
      state.withValue { accumulator in
        guard record.recordID.zoneID.zoneName == CloudKitRecordSchema.zoneName else {
          accumulator.sawUndecodableRecord = true
          return
        }
        switch record.recordType {
        case CloudKitRecordSchema.keptWisdomRecordType:
          // Archive before decode so every accepted remote record retains
          // the exact optimistic-concurrency baseline CloudKit returned.
          guard let systemFields = CloudKitOpaqueArchive.archiveSystemFields(of: record),
            !systemFields.isEmpty
          else {
            accumulator.sawUndecodableRecord = true
            return
          }
          switch CloudKitKeptWisdomCodec.decode(record, systemFields: systemFields) {
          case .success(let envelope):
            accumulator.changedKeptWisdomRecords.append(envelope)
          case .failure:
            accumulator.sawUndecodableRecord = true
          }
        case CloudKitRecordSchema.syncStateRecordType:
          switch CloudKitSyncStateCodec.decode(record) {
          case .success(let envelope):
            accumulator.changedSyncStateRecords.append(envelope)
          case .failure:
            accumulator.sawUndecodableRecord = true
          }
        default:
          accumulator.sawUndecodableRecord = true
        }
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
      state.withValue { $0.sawUnexpectedPhysicalDeletion = true }
    }

    operation.recordZoneFetchResultBlock = { _, result in
      switch result {
      case .success(let value):
        state.withValue { $0.finalToken = value.serverChangeToken }
      case .failure(let error):
        state.withValue { $0.zoneFetchError = error }
      }
    }

    operation.fetchRecordZoneChangesResultBlock = { result in
      let state = state.snapshot()
      // Checked first, before every other outcome: an out-of-band physical
      // deletion is treated as more significant than a concurrent token
      // expiry, transport error, or decode failure -- whatever else this
      // fetch observed, it must never be reported as if it had succeeded
      // (or as any outcome other than this one) once this has happened.
      if state.sawUnexpectedPhysicalDeletion {
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
      let operationError: Error?
      if case .failure(let error) = result {
        operationError = error
      } else {
        operationError = nil
      }
      let effectiveError = operationError ?? state.zoneFetchError ?? state.recordChangeError
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
        let symbolicErrorCode = CloudKitErrorClassifier.symbolicCode(for: effectiveError)
        completion(
          ZoneChangesResult(
            outcome: .failure,
            changedKeptWisdomRecords: [],
            changedSyncStateRecords: [],
            serverToken: nil,
            errorCode: symbolicErrorCode
          ))
        return
      }
      if state.sawUndecodableRecord {
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
      guard let finalToken = state.finalToken,
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
          changedKeptWisdomRecords: state.changedKeptWisdomRecords,
          changedSyncStateRecords: state.changedSyncStateRecords,
          serverToken: archivedToken,
          errorCode: nil
        ))
    }

    operation.qualityOfService = .userInitiated
    database.add(operation)
  }
}
