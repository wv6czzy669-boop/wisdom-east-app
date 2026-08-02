import CloudKit
import Foundation

/// Build 26 Phase 4B-1: idempotent private-zone existence check/creation,
/// scoped to exactly the one Phase 4A custom zone
/// (`CloudKitSyncBridgeConstants.expectedZoneName`). Never touches the
/// public or shared database, never creates a subscription, never creates
/// a user-content record. Only ever invoked when the caller explicitly
/// requests it (`configurePrivateZone`) -- never from app startup, and
/// never automatically by this type itself.
final class CloudKitPrivateZoneCoordinator {
  struct ConfigurationResult {
    let success: Bool
    let zoneCreated: Bool
    let zoneAlreadyExisted: Bool
    let errorCode: String?
  }

  private let database: CKDatabase

  init(database: CKDatabase) {
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

    database.fetch(withRecordZoneID: zoneID) { [weak self] zone, error in
      guard let self = self else { return }

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
