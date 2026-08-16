import 'cloud_kit_account_change_event.dart';
import 'cloud_kit_account_snapshot.dart';
import 'cloud_kit_bridge_info.dart';
import 'cloud_kit_delete_records_contract.dart';
import 'cloud_kit_kept_wisdom_record_names_contract.dart';
import 'cloud_kit_modify_records_contract.dart';
import 'cloud_kit_sync_state_epoch_contract.dart';
import 'cloud_kit_zone_changes_contract.dart';
import 'cloud_kit_zone_configuration_result.dart';

/// Build 26 Phase 4B-1: the Dart-side contract for the native CloudKit
/// bridge foundation -- account snapshot, private-zone configuration, and
/// static bridge info only. See
/// `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md`'s Phase 4B-1 section for
/// the exact channel contract this is the Dart-side shape of.
///
/// Build 26 Phase 4C-2 extends this interface, narrowly, with the two
/// record-transport operations ([modifyPrivateRecords]/
/// [fetchPrivateZoneChanges]) -- still **not** `lib/sync/sync_engine.dart`'s
/// `SyncEngine`: neither new method here starts a sync cycle, applies a
/// remote change locally, resolves a conflict, or persists a change token --
/// they are narrow, one-shot record-transport primitives a future
/// `SyncEngine` implementation may compose, exactly as
/// [configurePrivateZone] already is. Nothing behind this interface is
/// called from application/repository/startup code in this phase (see
/// `test/sync_platform/cloud_kit_platform_privacy_test.dart`).
abstract interface class CloudKitPlatformBridge {
  /// A content-free snapshot of the current CloudKit account state. Never
  /// throws for "no account" or "restricted" -- those are ordinary,
  /// expected values (design doc §5), reflected in
  /// [CloudKitAccountSnapshot.availability].
  Future<CloudKitAccountSnapshot> getAccountSnapshot();

  /// Ensures the Phase 4A custom zone (`keptRecordZoneName`) exists in the
  /// private database. Idempotent -- calling this when the zone already
  /// exists is success, not an error. No production code invokes this in
  /// Phase 4B-1; it is never called automatically by app startup.
  Future<CloudKitZoneConfigurationResult> configurePrivateZone();

  /// Static, content-free bridge/build information for validation --
  /// expected zone name, expected record types, and whether capability
  /// activation is expected (always `false` until Phase 4B-2).
  Future<CloudKitBridgeInfo> getBridgeInfo();

  /// Emits a content-free marker whenever the platform detects the
  /// signed-in iCloud account has changed. Never carries the new/old
  /// account identity -- callers must explicitly call [getAccountSnapshot]
  /// afterward (design doc §5). Never itself triggers any sync operation.
  Stream<CloudKitAccountChangeEvent> get accountChangeEvents;

  /// Build 26 Phase 4C-2: atomically saves [request.records] in
  /// `EASTKeptZone`, using the already-frozen Phase 4C-1 record schema and
  /// codecs. Never called automatically -- there is no outbox, retry
  /// scheduler, or startup/repository call site behind this interface in
  /// this phase; a caller (outside this phase's scope) decides when to
  /// invoke it and what to do with the result.
  Future<CloudKitModifyRecordsResult> modifyPrivateRecords(
    CloudKitModifyRecordsRequest request,
  );

  /// Build 26 Phase 4C-2: fetches every `EASTKeptZone` record change since
  /// [request.previousServerToken] (or every record currently in the zone,
  /// for an initial `null`-token request), aggregating every page CloudKit
  /// reports internally before returning once. Never applies a returned
  /// change to local storage, never persists the returned token, and never
  /// resolves a conflict -- purely a read primitive.
  Future<CloudKitZoneChangesResult> fetchPrivateZoneChanges(
    CloudKitZoneChangesRequest request,
  );

  /// Build 26 Phase 5 (slice 2): a narrow, single-record, content-minimal
  /// read of the `CKEastSyncState` singleton -- used only by the Phase 5
  /// remote deletion runner (`lib/sync_deletion/`) to read the current
  /// authoritative epoch before establishing its replacement. Never called
  /// by [modifyPrivateRecords]/[fetchPrivateZoneChanges]'s own callers
  /// (`SyncOrchestrator`/`KeptSyncBootstrapCoordinator`), and never mutates
  /// anything itself. See `cloud_kit_sync_state_epoch_contract.dart` for why
  /// this exists separately from [fetchPrivateZoneChanges].
  Future<CloudKitSyncStateEpochResult> fetchSyncStateEpoch();

  /// Build 26 Phase 5 (slice 2): lists every `CKKeptWisdom` record currently
  /// in `EASTKeptZone`, by `recordName` only -- never wisdom/Reflection
  /// content, never a `revealId` decoded from the name. Used only by the
  /// Phase 5 remote deletion runner, to discover which records to purge and
  /// again afterward to verify zero remain. Aggregates every page CloudKit
  /// reports internally before returning once, exactly like
  /// [fetchPrivateZoneChanges] already does for its own read.
  Future<CloudKitKeptWisdomRecordNamesResult> listKeptWisdomRecordNames();

  /// Build 26 Phase 5 (slice 2): physically deletes the named `CKKeptWisdom`
  /// records from `EASTKeptZone`. Used only by the Phase 5 remote deletion
  /// runner. Deliberately a distinct method from [modifyPrivateRecords],
  /// whose own native transport has a locked, tested invariant that it
  /// never issues a physical CloudKit record deletion (normal sync remains
  /// tombstone-only, exactly as before this phase) -- see
  /// `cloud_kit_delete_records_contract.dart`.
  Future<CloudKitDeleteKeptWisdomRecordsResult> deleteKeptWisdomRecords(
    CloudKitDeleteKeptWisdomRecordsRequest request,
  );
}
