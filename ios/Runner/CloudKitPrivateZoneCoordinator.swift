import CloudKit
import Foundation

/// Build 26 Phase 4B-2: the narrow surface `CloudKitPrivateZoneCoordinator`
/// needs from a CloudKit database -- exactly the two calls it makes, no
/// more. Exists solely so automated tests can inject a fake and exercise
/// every branch of `configureZone` deterministically, without a real
/// CloudKit network call or a real iCloud account. `CKDatabase` conforms
/// below via a plain, empty extension -- it already implements both
/// requirements with matching signatures, so this is not a behavior
/// change for any production caller (`CloudKitSyncBridge.swift` is
/// unmodified and unaffected).
protocol CloudKitZoneOperationDatabase {
  func fetch(
    withRecordZoneID zoneID: CKRecordZone.ID,
    completionHandler: @escaping (CKRecordZone?, Error?) -> Void
  )
  func add(_ operation: CKDatabaseOperation)
}

extension CKDatabase: CloudKitZoneOperationDatabase {}

/// Build 26 Phase 4B-2: idempotent private-zone existence check/creation,
/// scoped to exactly the one Phase 4A custom zone
/// (`CloudKitSyncBridgeConstants.expectedZoneName`). Never touches the
/// public or shared database, never creates a subscription, never creates
/// a user-content record. Only ever invoked when the caller explicitly
/// requests it (`configurePrivateZone`) -- never from app startup, and
/// never automatically by this type itself.
///
/// Includes one guarded fallback, scoped only to this zone-configuration
/// operation: a fetch that fails with `CKError.serverRejectedRequest` is
/// treated as a signal to attempt zone creation/save directly (confirmed
/// on a physical device to succeed even when the preceding fetch itself
/// fails), never as success on its own -- the create/save attempt must
/// still succeed for this call to report success.
final class CloudKitPrivateZoneCoordinator {
  struct ConfigurationResult {
    let success: Bool
    let zoneCreated: Bool
    let zoneAlreadyExisted: Bool
    let errorCode: String?
  }

  private let database: CloudKitZoneOperationDatabase

  init(database: CloudKitZoneOperationDatabase) {
    self.database = database
  }

  /// Fetches the zone if it already exists; otherwise creates it with
  /// `CKModifyRecordZonesOperation`. Treats "already exists" as success --
  /// never an error -- and never partially applies: either the zone ends
  /// up existing and this reports success, or it reports one specific
  /// failure and nothing was created.
  func configureZone(completion: @escaping (ConfigurationResult) -> Void) {
    let zoneID = CKRecordZone.ID(
      zoneName: CloudKitSyncBridgeConstants.expectedZoneName,
      ownerName: CKCurrentUserDefaultName
    )

    // Strong `self` capture is intentional here, not an oversight: this
    // coordinator is a one-shot helper with no external owner between
    // `configureZone` returning and CloudKit invoking this completion --
    // `self` was previously captured `weak`, which let ARC deallocate the
    // coordinator before CloudKit ever called back, silently dropping
    // `completion` and leaving the Flutter `MethodChannel` Future pending
    // forever. A strong capture here creates no retention cycle (this
    // object holds no reference back to whatever constructed it), and is
    // exactly what keeps the coordinator alive for the duration of its own
    // single asynchronous operation.
    database.fetch(withRecordZoneID: zoneID) { zone, error in
      if zone != nil {
        completion(
          ConfigurationResult(
            success: true, zoneCreated: false, zoneAlreadyExisted: true, errorCode: nil))
        return
      }

      if let ckError = error as? CKError, ckError.code == .zoneNotFound {
        self.createZone(zoneID: zoneID, completion: completion)
        return
      }

      if let ckError = error as? CKError, ckError.code == .serverRejectedRequest {
        // Guarded fallback, scoped only to this custom-zone configuration
        // operation -- never used anywhere else. On a physical device,
        // fetching `EASTKeptZone` before it exists has been observed to
        // fail with `.serverRejectedRequest` (CloudKit Console: database
        // PRIVATE, zone EASTKeptZone, operation ZoneFetch, overall status
        // SERVER_ERROR, error INTERNAL_ERROR), even though directly saving
        // the same custom zone via `CKModifyRecordZonesOperation` succeeds
        // -- confirmed reproducible on a second attempt. This branch does
        // not claim success by itself: `createZone` below still has to
        // succeed, and if it fails, its own normalized error is reported
        // -- the original `.serverRejectedRequest` fetch error is never
        // hidden behind, nor substituted for, that failure.
        self.createZone(zoneID: zoneID, completion: completion)
        return
      }

      if let error = error {
        completion(
          ConfigurationResult(
            success: false,
            zoneCreated: false,
            zoneAlreadyExisted: false,
            errorCode: CloudKitErrorClassifier.symbolicCode(for: error)
          ))
        return
      }

      // Defensive: no zone and no error should not occur per CloudKit's own
      // contract, but this is never silently guessed as either outcome.
      completion(
        ConfigurationResult(
          success: false,
          zoneCreated: false,
          zoneAlreadyExisted: false,
          errorCode: CloudKitErrorClassifier.unrecognizedNativeError
        ))
    }
  }

  private func createZone(
    zoneID: CKRecordZone.ID, completion: @escaping (ConfigurationResult) -> Void
  ) {
    let zone = CKRecordZone(zoneID: zoneID)
    let operation = CKModifyRecordZonesOperation(
      recordZonesToSave: [zone], recordZoneIDsToDelete: nil)
    operation.modifyRecordZonesCompletionBlock = {
      (_ savedZones: [CKRecordZone]?, _ deletedZoneIDs: [CKRecordZone.ID]?, _ error: Error?) in
      if let error = error {
        completion(
          ConfigurationResult(
            success: false,
            zoneCreated: false,
            zoneAlreadyExisted: false,
            errorCode: CloudKitErrorClassifier.symbolicCode(for: error)
          ))
        return
      }
      completion(
        ConfigurationResult(
          success: true, zoneCreated: true, zoneAlreadyExisted: false, errorCode: nil))
    }
    operation.qualityOfService = QualityOfService.userInitiated
    database.add(operation)
  }
}
