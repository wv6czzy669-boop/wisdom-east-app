import 'cloud_kit_account_change_event.dart';
import 'cloud_kit_account_snapshot.dart';
import 'cloud_kit_bridge_info.dart';
import 'cloud_kit_zone_configuration_result.dart';

/// Build 26 Phase 4B-1: the Dart-side contract for the native CloudKit
/// bridge foundation -- account snapshot, private-zone configuration, and
/// static bridge info only. See
/// `docs/architecture/EAST_CLOUDKIT_SYNC_V1.md`'s Phase 4B-1 section for
/// the exact channel contract this is the Dart-side shape of.
///
/// Deliberately **not** `lib/sync/sync_engine.dart`'s `SyncEngine`: that
/// interface's `startSync`/`requestImmediateSync`/`enqueueLocalChange`/
/// `remoteChanges` describe real record synchronization, which does not
/// exist yet in this subphase -- no record is ever uploaded, downloaded,
/// merged, or deleted by anything behind this interface. Implementing
/// `SyncEngine` now, with those methods missing or stubbed, would
/// misrepresent capability that is not actually present. A future phase's
/// real `SyncEngine` implementation may compose this bridge as one of its
/// collaborators; this interface never pretends to be that implementation
/// itself.
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
}
