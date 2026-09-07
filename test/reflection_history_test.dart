import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/models/kept_record.dart';
import 'package:wisdom_app/models/reflection_history.dart';
import 'package:wisdom_app/sync/cloud_kept_wisdom_projection.dart';
import 'package:wisdom_app/sync/data_epoch.dart';
import 'package:wisdom_app/sync/sync_change.dart';
import 'package:wisdom_app/sync_integration/kept_sync_integration_coordinator.dart';
import 'package:wisdom_app/sync_integration/local_sync_intent.dart';
import 'package:wisdom_app/sync_platform/cloud_kept_wisdom_wire_envelope.dart';
import 'package:wisdom_app/sync_persistence/persisted_outbox_mutation.dart';
import 'persistence_test_helpers.dart';

const reveal = 'aaaaaaaa-0000-4000-8000-000000000001';
String thoughtId(int n) =>
    'bbbbbbbb-0000-4000-8000-${n.toString().padLeft(12, '0')}';
void main() {
  late DateTime now;
  late KeptRepositoryTestGraph graph;
  late String itemId;
  setUp(() async {
    now = DateTime.utc(2026, 9, 1, 10);
    graph = KeptRepositoryTestGraph(clock: () => now);
    itemId = (await graph.repository.keepOccurrence(
            revealId: reveal,
            wisdomText: 'Peace enters slowly.',
            revealedAt: now,
            isKeeper: true))
        .items
        .single
        .id;
    await graph.service.saveReflection(
        itemId: itemId, reflection: 'My original words.', isKeeper: true);
  });

  test(
      'later thoughts retain the original and their dates across durable encodings',
      () async {
    final original = (await graph.service.load()).single;
    now = now.add(const Duration(days: 1));
    final createdAt = now.millisecondsSinceEpoch;
    await graph.service.saveThought(
        itemId: itemId,
        thoughtId: thoughtId(1),
        reflection: 'A second thought.',
        isKeeper: true);
    now = now.add(const Duration(hours: 2));
    await graph.service.saveThought(
        itemId: itemId,
        thoughtId: thoughtId(1),
        reflection: 'A second thought, finished.',
        isKeeper: true);
    now = now.add(const Duration(days: 1));
    await graph.service.saveThought(
        itemId: itemId,
        thoughtId: thoughtId(2),
        reflection: 'A third thought.',
        isKeeper: true);
    final record = (await graph.repository.loadAllRecords()).single;
    expect(record.reflectionText, original.reflection);
    expect(record.reflectedAt!.toIso8601String(), original.reflectedAt);
    expect(record.reflectionHistory.thoughts, hasLength(2));
    expect(record.reflectionHistory.thoughts.first.createdAtMs, createdAt);
    expect(KeptRecord.decodeString(record.encodeString()), record);
    final item = (await graph.service.load()).single;
    expect(FavoriteItem.decodeCurrent(item.encode()).reflectionHistoryJson,
        record.reflectionHistoryJson);
    final projection = CloudKeptWisdomProjection.active(record,
        dataEpoch: DataEpoch.parse('cccccccc-0000-4000-8000-000000000001'));
    expect(
        CloudKeptWisdomWireEnvelope.tryDecode(
            CloudKeptWisdomWireEnvelope.encode(projection)),
        projection);
    final outbox = PersistedOutboxMutation(
        change: SyncChange(
            kind: SyncChangeKind.update,
            projection: projection,
            enqueuedAt: now),
        status: PersistedOutboxMutationStatus.pending);
    expect(
        PersistedOutboxMutation.tryDecode(outbox.encode())!.change.projection,
        projection);
    final intent = (await graph.intentStore.loadIntents()).single;
    expect(
        LocalSyncIntentPayload.tryDecode(intent.payload.encode())!
            .reflectionHistoryJson,
        record.reflectionHistoryJson);
    expect(projection.toLogSafeSummary().toString(),
        isNot(contains('third thought')));
  });

  test(
      'a failed write replays the complete history once without duplicating a thought',
      () async {
    now = now.add(const Duration(days: 1));
    graph.store.failReplace = StateError('simulated disk failure');
    await expectLater(
        graph.service.saveThought(
            itemId: itemId,
            thoughtId: thoughtId(1),
            reflection: 'Recover this thought.',
            isKeeper: true),
        throwsException);
    expect(
        (await graph.repository.loadAllRecords())
            .single
            .reflectionHistory
            .thoughts,
        isEmpty);
    final pending = (await graph.intentStore.loadIntents()).single;
    expect(pending.stage, LocalSyncIntentStage.pendingLocalApplication);
    graph.store.failReplace = null;
    now = now.add(const Duration(days: 5));
    const context = AssociatedSyncAccountContext(
        accountFingerprint:
            '0000000000000000000000000000000000000000000000000000000000000000');
    await graph.syncCoordinator.reconcileForAssociatedAccount(context);
    await graph.syncCoordinator.reconcileForAssociatedAccount(context);
    final record = (await graph.repository.loadAllRecords()).single;
    expect(
        record.reflectionHistory.thoughts.single.text, 'Recover this thought.');
    expect(record.mutationId, pending.payload.mutationId);
    expect(record.reflectionText, 'My original words.');
  });

  test(
      'deleting a reflection clears all writing and keeps a deletion watermark',
      () async {
    now = now.add(const Duration(days: 1));
    await graph.service.saveThought(
        itemId: itemId,
        thoughtId: thoughtId(1),
        reflection: 'Later.',
        isKeeper: true);
    now = now.add(const Duration(days: 1));
    await graph.service.deleteReflection(itemId: itemId);
    final record = (await graph.repository.loadAllRecords()).single;
    expect(record.reflectionText, isNull);
    expect(record.reflectionHistory.thoughts, isEmpty);
    expect(record.reflectionHistory.clearedAtMs, now.millisecondsSinceEpoch);
    expect(KeptRecord.decodeString(record.encodeString()), record);
  });

  test(
      'older app deletion clears a residual remote history without rejecting the record',
      () async {
    now = now.add(const Duration(days: 1));
    await graph.service.saveThought(
        itemId: itemId,
        thoughtId: thoughtId(1),
        reflection: 'Later.',
        isKeeper: true);
    final projection = CloudKeptWisdomProjection.active(
        (await graph.repository.loadAllRecords()).single,
        dataEpoch: DataEpoch.parse('cccccccc-0000-4000-8000-000000000001'));
    now = now.add(const Duration(days: 1));
    final wire = CloudKeptWisdomWireEnvelope.encode(projection)
      ..remove('reflectionText')
      ..remove('reflectedAtMs')
      ..['updatedAtMs'] = now.millisecondsSinceEpoch;
    final deleted = CloudKeptWisdomWireEnvelope.tryDecode(wire)!;
    final history = ReflectionHistory.decode(deleted.reflectionHistoryJson);
    expect(deleted.reflectionText, isNull);
    expect(history.thoughts, isEmpty);
    expect(history.clearedAtMs, now.millisecondsSinceEpoch);
    expect(
        ReflectionHistory.decode(
                deleted.mergingThoughts([projection]).reflectionHistoryJson)
            .thoughts,
        isEmpty);
    wire['reflectionHistoryJson'] = '{"broken":true}';
    expect(CloudKeptWisdomWireEnvelope.tryDecode(wire), isNull);
  });

  test(
      'legacy records need no history migration and malformed histories fail closed',
      () async {
    final record = (await graph.repository.loadAllRecords()).single;
    expect(record.encode().containsKey('reflectionHistoryJson'), isFalse);
    expect(KeptRecord.decode(record.encode()).reflectionText,
        'My original words.');
    final corrupt = record.encode()
      ..['reflectionHistoryJson'] =
          '{"version":1,"clearedAtMs":0,"thoughts":[{}]}';
    expect(() => KeptRecord.decode(corrupt), throwsFormatException);
    expect(
        () => ReflectionHistory.decode('{"version":2}'), throwsFormatException);
  });
}
