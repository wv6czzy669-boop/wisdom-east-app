import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/sync_integration/kept_sync_bootstrap_coordinator.dart';
import 'sync_device_harness.dart';
import 'synthetic_cloudkit_server.dart';

const reveal = 'aaaaaaaa-0000-4000-8000-000000000001';
const thoughtA = 'aaaaaaaa-0000-4000-8000-000000000011';
const thoughtB = 'bbbbbbbb-0000-4000-8000-000000000012';
final account = '1'.padLeft(64, '0');
void main() {
  test(
      'independent devices keep both offline thoughts, converge, and do not re-upload forever',
      () async {
    var now = DateTime.utc(2026, 9, 1, 10);
    final server = SyntheticCloudKitServer();
    final a =
        SyncDeviceHarness(deviceLabel: 'A', server: server, clock: () => now)
          ..setAccountFingerprint(account);
    await a.bootstrap();
    final idA = (await a.keep(
            revealId: reveal,
            wisdomText: 'Peace enters slowly.',
            revealedAt: now))
        .items
        .single
        .id;
    await a.saveReflection(
        itemId: idA, reflection: 'Original.', reflectedAt: now);
    await a.runOutgoingAndIncomingSync();
    final b =
        SyncDeviceHarness(deviceLabel: 'B', server: server, clock: () => now)
          ..setAccountFingerprint(account);
    expect((await b.bootstrap()).status, BootstrapRunStatus.completed);
    final idB = (await b.loadAllRecords()).single.id;
    now = now.add(const Duration(days: 1));
    await a.syncCoordinator.recordReflectionSave(
        itemId: idA,
        thoughtId: thoughtA,
        reflection: 'Thought from A.',
        isKeeper: true);
    await b.syncCoordinator.recordReflectionSave(
        itemId: idB,
        thoughtId: thoughtB,
        reflection: 'Thought from B.',
        isKeeper: true);
    for (var i = 0; i < 4; i++) {
      await a.runOutgoingAndIncomingSync();
      await b.runOutgoingAndIncomingSync();
    }
    final ar = (await a.loadAllRecords()).single;
    final br = (await b.loadAllRecords()).single;
    expect(ar.reflectionText, 'Original.');
    expect(ar.reflectionHistory.thoughts.map((t) => t.text).toSet(),
        {'Thought from A.', 'Thought from B.'});
    expect(ar.reflectionHistoryJson, br.reflectionHistoryJson);
    expect(ar.mutationId, br.mutationId);
    expect((await a.syncPersistenceStore.loadAccountState(account))!.outbox,
        isEmpty);
    expect((await b.syncPersistenceStore.loadAccountState(account))!.outbox,
        isEmpty);

    now = now.add(const Duration(days: 1));
    await a.deleteReflection(itemId: idA);
    await a.runOutgoingAndIncomingSync();
    await b.runOutgoingAndIncomingSync();
    expect(
        (await b.loadAllRecords()).single.reflectionHistory.thoughts, isEmpty);
    now = now.add(const Duration(days: 1));
    await b.saveReflection(
        itemId: idB, reflection: 'A fresh start.', reflectedAt: now);
    await b.runOutgoingAndIncomingSync();
    await a.runOutgoingAndIncomingSync();
    final fresh = (await a.loadAllRecords()).single;
    expect(fresh.reflectionText, 'A fresh start.');
    expect(fresh.reflectionHistory.thoughts, isEmpty);
    expect((await b.loadAllRecords()).single.mutationId, fresh.mutationId);
  });

  test(
      'first account association merges local and remote thoughts before completing bootstrap',
      () async {
    var now = DateTime.utc(2026, 9, 1, 10);
    final server = SyntheticCloudKitServer();
    final a =
        SyncDeviceHarness(deviceLabel: 'A', server: server, clock: () => now)
          ..setAccountFingerprint(account);
    await a.bootstrap();
    final id = (await a.keep(
            revealId: reveal,
            wisdomText: 'Peace enters slowly.',
            revealedAt: now))
        .items
        .single
        .id;
    await a.saveReflection(
        itemId: id, reflection: 'Original.', reflectedAt: now);
    final baseline = (await a.loadAllRecords()).single;
    now = now.add(const Duration(days: 1));
    await a.syncCoordinator.recordReflectionSave(
        itemId: id,
        thoughtId: thoughtA,
        reflection: 'Remote later thought.',
        isKeeper: true);
    await a.runOutgoingAndIncomingSync();
    final b =
        SyncDeviceHarness(deviceLabel: 'B', server: server, clock: () => now)
          ..setAccountFingerprint(account);
    await b.keptRepository.replaceAllRecords([baseline]);
    await b.syncCoordinator.recordReflectionSave(
        itemId: baseline.id,
        thoughtId: thoughtB,
        reflection: 'Local later thought.',
        isKeeper: true);
    await b.authorizeAssociation(account);
    expect((await b.bootstrap()).isSuccessful, isTrue);
    for (var i = 0; i < 3; i++) {
      await b.runOutgoingAndIncomingSync();
      await a.runOutgoingAndIncomingSync();
    }
    final aRecord = (await a.loadAllRecords()).single;
    final bRecord = (await b.loadAllRecords()).single;
    expect(aRecord.reflectionHistory.thoughts, hasLength(2));
    expect(aRecord.reflectionHistoryJson, bRecord.reflectionHistoryJson);
  });
}
