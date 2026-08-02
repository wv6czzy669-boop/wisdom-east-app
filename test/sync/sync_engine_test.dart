// Build 26 Phase 4A: proves the FakeSyncEngine test double satisfies the
// SyncEngine port contract and behaves as a real implementation eventually
// must -- no network, no CloudKit, purely in-memory. See
// docs/architecture/EAST_CLOUDKIT_SYNC_V1.md §7/§8.9.
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/models/kept_record.dart';
import 'package:wisdom_app/sync/cloud_kept_wisdom_projection.dart';
import 'package:wisdom_app/sync/data_epoch.dart';
import 'package:wisdom_app/sync/sync_change.dart';
import 'package:wisdom_app/sync/sync_engine.dart';
import 'package:wisdom_app/sync/sync_status.dart';

import '../sync_engine_test_helpers.dart';

void main() {
  const revealId = 'c947bbb4-f86a-4db3-87c9-ed5e718bbd98';
  final epoch = DataEpoch.parse('11111111-1111-4111-8111-111111111111');
  final now = DateTime.utc(2026, 8, 1, 20, 0);

  CloudKeptWisdomProjection activeProjection() =>
      CloudKeptWisdomProjection.active(
        KeptRecord(
          id: 'local-id-1',
          revealId: revealId,
          wisdomText: 'Be still and know.',
          revealedAt: now,
          keptAt: now,
          updatedAt: now,
          mutationId: '22222222-2222-4222-8222-222222222222',
        ),
        dataEpoch: epoch,
      );

  test('1. FakeSyncEngine implements the SyncEngine interface', () {
    final engine = FakeSyncEngine();
    expect(engine, isA<SyncEngine>());
  });

  test('2. default account status is available unless overridden', () async {
    final engine = FakeSyncEngine();
    expect(await engine.accountStatus(), CloudAccountStatus.available);
  });

  test('3. setAccountStatus changes what accountStatus() returns', () async {
    final engine = FakeSyncEngine(
      initialAccountStatus: CloudAccountStatus.noAccount,
    );
    expect(await engine.accountStatus(), CloudAccountStatus.noAccount);
    engine.setAccountStatus(CloudAccountStatus.restricted);
    expect(await engine.accountStatus(), CloudAccountStatus.restricted);
  });

  test('4. configureZone/startSync/requestImmediateSync are counted', () async {
    final engine = FakeSyncEngine();
    await engine.configureZone();
    await engine.startSync();
    await engine.startSync();
    await engine.requestImmediateSync();

    expect(engine.configureZoneCallCount, 1);
    expect(engine.startSyncCallCount, 2);
    expect(engine.requestImmediateSyncCallCount, 1);
  });

  test('5. enqueueLocalChange records the change for inspection', () async {
    final engine = FakeSyncEngine();
    final change = SyncChange(
      kind: SyncChangeKind.create,
      projection: activeProjection(),
      enqueuedAt: now,
    );

    await engine.enqueueLocalChange(change);

    expect(engine.enqueuedChanges, hasLength(1));
    expect(engine.enqueuedChanges.single, change);
  });

  test('6. remoteChanges stream delivers what the test emits', () async {
    final engine = FakeSyncEngine();
    final received = <CloudKeptWisdomProjection>[];
    final subscription = engine.remoteChanges.listen(received.add);

    engine.emitRemoteChange(activeProjection());
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(1));
    await subscription.cancel();
    await engine.dispose();
  });

  test('7. statusChanges stream delivers what the test emits', () async {
    final engine = FakeSyncEngine();
    final received = <SyncEngineStatus>[];
    final subscription = engine.statusChanges.listen(received.add);

    engine.emitStatus(const SyncEngineStatus(phase: SyncPhase.syncing));
    await Future<void>.delayed(Duration.zero);

    expect(received.single.phase, SyncPhase.syncing);
    await subscription.cancel();
    await engine.dispose();
  });

  test('8. accountChangeEvents stream delivers what the test emits', () async {
    final engine = FakeSyncEngine();
    final received = <AccountChangeEvent>[];
    final subscription = engine.accountChangeEvents.listen(received.add);

    engine.emitAccountChange(const AccountChangeEvent(
      previousAccountToken: 'token-a',
      newAccountToken: 'token-b',
      requiresUserConfirmation: true,
    ));
    await Future<void>.delayed(Duration.zero);

    expect(received.single.requiresUserConfirmation, isTrue);
    await subscription.cancel();
    await engine.dispose();
  });
}
