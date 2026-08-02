// Build 26 Phase 4A: SyncChange -- the pending-outbox-mutation model. See
// docs/architecture/EAST_CLOUDKIT_SYNC_V1.md §8.5 / ADR-007's
// Deletion/outbox strategy.
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/models/kept_record.dart';
import 'package:wisdom_app/sync/cloud_kept_wisdom_projection.dart';
import 'package:wisdom_app/sync/data_epoch.dart';
import 'package:wisdom_app/sync/sync_change.dart';
import 'package:wisdom_app/sync/sync_tombstone.dart';

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

  CloudKeptWisdomProjection tombstoneProjection() =>
      CloudKeptWisdomProjection.tombstone(
        SyncTombstone(
          revealId: revealId,
          dataEpoch: epoch,
          updatedAt: now,
          deletedAt: now,
          mutationId: '22222222-2222-4222-8222-222222222222',
        ),
      );

  test('1. a create change accepts an active-form projection', () {
    expect(
      () => SyncChange(
        kind: SyncChangeKind.create,
        projection: activeProjection(),
        enqueuedAt: now,
      ),
      returnsNormally,
    );
  });

  test('2. an update change accepts an active-form projection', () {
    expect(
      () => SyncChange(
        kind: SyncChangeKind.update,
        projection: activeProjection(),
        enqueuedAt: now,
      ),
      returnsNormally,
    );
  });

  test('3. a delete change requires a tombstone-form projection', () {
    expect(
      () => SyncChange(
        kind: SyncChangeKind.delete,
        projection: activeProjection(),
        enqueuedAt: now,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('4. a delete change accepts a tombstone-form projection', () {
    expect(
      () => SyncChange(
        kind: SyncChangeKind.delete,
        projection: tombstoneProjection(),
        enqueuedAt: now,
      ),
      returnsNormally,
    );
  });

  test('5. a create/update change rejects a tombstone-form projection', () {
    expect(
      () => SyncChange(
        kind: SyncChangeKind.create,
        projection: tombstoneProjection(),
        enqueuedAt: now,
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => SyncChange(
        kind: SyncChangeKind.update,
        projection: tombstoneProjection(),
        enqueuedAt: now,
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
