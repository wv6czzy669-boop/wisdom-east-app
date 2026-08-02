import 'dart:async';

import 'package:wisdom_app/sync/cloud_kept_wisdom_projection.dart';
import 'package:wisdom_app/sync/sync_change.dart';
import 'package:wisdom_app/sync/sync_engine.dart';
import 'package:wisdom_app/sync/sync_status.dart';

/// Build 26 Phase 4A: an in-memory, fully-controllable [SyncEngine] fake for
/// tests — the only implementation of that interface anywhere in this
/// repository at this phase (no production `lib/` code implements it yet).
///
/// Never performs real CloudKit calls, never touches the network, and
/// never persists anything beyond this instance's own in-memory lifetime.
/// Test code drives its behavior directly (e.g. `emitRemoteChange`,
/// `emitStatus`) rather than this fake trying to simulate real CloudKit
/// timing on its own.
class FakeSyncEngine implements SyncEngine {
  FakeSyncEngine(
      {CloudAccountStatus initialAccountStatus = CloudAccountStatus.available})
      : _accountStatus = initialAccountStatus;

  CloudAccountStatus _accountStatus;

  int configureZoneCallCount = 0;
  int startSyncCallCount = 0;
  int requestImmediateSyncCallCount = 0;

  final List<SyncChange> enqueuedChanges = [];

  final StreamController<CloudKeptWisdomProjection> _remoteChangesController =
      StreamController<CloudKeptWisdomProjection>.broadcast();
  final StreamController<SyncEngineStatus> _statusController =
      StreamController<SyncEngineStatus>.broadcast();
  final StreamController<AccountChangeEvent> _accountChangeController =
      StreamController<AccountChangeEvent>.broadcast();

  @override
  Future<CloudAccountStatus> accountStatus() async => _accountStatus;

  /// Test-only: changes the account status the next [accountStatus] call
  /// returns. Does not itself emit an [AccountChangeEvent] — call
  /// [emitAccountChange] separately when a test needs to simulate that.
  void setAccountStatus(CloudAccountStatus status) {
    _accountStatus = status;
  }

  @override
  Future<void> configureZone() async {
    configureZoneCallCount += 1;
  }

  @override
  Future<void> startSync() async {
    startSyncCallCount += 1;
  }

  @override
  Future<void> requestImmediateSync() async {
    requestImmediateSyncCallCount += 1;
  }

  @override
  Future<void> enqueueLocalChange(SyncChange change) async {
    enqueuedChanges.add(change);
  }

  @override
  Stream<CloudKeptWisdomProjection> get remoteChanges =>
      _remoteChangesController.stream;

  @override
  Stream<SyncEngineStatus> get statusChanges => _statusController.stream;

  @override
  Stream<AccountChangeEvent> get accountChangeEvents =>
      _accountChangeController.stream;

  /// Test-only: simulates a remote change arriving from a pull cycle.
  void emitRemoteChange(CloudKeptWisdomProjection projection) {
    _remoteChangesController.add(projection);
  }

  /// Test-only: simulates a status transition.
  void emitStatus(SyncEngineStatus status) {
    _statusController.add(status);
  }

  /// Test-only: simulates the platform detecting an account change.
  void emitAccountChange(AccountChangeEvent event) {
    _accountChangeController.add(event);
  }

  Future<void> dispose() async {
    await _remoteChangesController.close();
    await _statusController.close();
    await _accountChangeController.close();
  }
}
