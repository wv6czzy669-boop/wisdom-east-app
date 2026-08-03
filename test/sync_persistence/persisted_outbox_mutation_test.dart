// Build 26 Phase 4D-1: PersistedOutboxMutation -- the durable outbox-entry
// wire shape. Synthetic content only.
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/sync/cloud_kept_wisdom_projection.dart';
import 'package:wisdom_app/sync/data_epoch.dart';
import 'package:wisdom_app/sync/sync_change.dart';
import 'package:wisdom_app/sync/sync_tombstone.dart';
import 'package:wisdom_app/sync_persistence/persisted_outbox_mutation.dart';

void main() {
  const revealId = 'aaaaaaaa-1111-4111-8111-111111111111';
  final epoch = DataEpoch.parse('bbbbbbbb-2222-4222-8222-222222222222');

  CloudKeptWisdomProjection activeProjection({
    String revealIdValue = revealId,
    String wisdomText = 'Synthetic wisdom text for testing only.',
  }) {
    return CloudKeptWisdomProjection.tryParseRemote({
      'recordName': 'east-kept-$revealIdValue',
      'isTombstone': false,
      'revealId': revealIdValue,
      'wisdomText': wisdomText,
      'revealedAtMs': 1000,
      'keptAtMs': 2000,
      'updatedAtMs': 3000,
      'mutationId': 'cccccccc-3333-4333-8333-333333333333',
      'dataEpoch': epoch.value,
      'schemaVersion': 3,
    })!;
  }

  CloudKeptWisdomProjection tombstoneProjection() {
    return CloudKeptWisdomProjection.tombstone(
      SyncTombstone(
        revealId: revealId,
        dataEpoch: epoch,
        updatedAt: DateTime.utc(2026, 8, 1),
        deletedAt: DateTime.utc(2026, 8, 1),
        mutationId: 'dddddddd-4444-4444-8444-444444444444',
      ),
    );
  }

  SyncChange createChange() => SyncChange(
        kind: SyncChangeKind.create,
        projection: activeProjection(),
        enqueuedAt: DateTime.utc(2026, 8, 1, 10),
      );

  test('encode/tryDecode round-trips an active-form mutation exactly', () {
    final entry = PersistedOutboxMutation(change: createChange());
    final decoded = PersistedOutboxMutation.tryDecode(entry.encode());

    expect(decoded, isNotNull);
    expect(decoded, entry);
    expect(decoded!.mutationId, entry.mutationId);
    expect(decoded.recordName, entry.recordName);
  });

  test('encode/tryDecode round-trips a tombstone-form mutation exactly', () {
    final change = SyncChange(
      kind: SyncChangeKind.delete,
      projection: tombstoneProjection(),
      enqueuedAt: DateTime.utc(2026, 8, 1, 11),
    );
    final entry = PersistedOutboxMutation(change: change);
    final decoded = PersistedOutboxMutation.tryDecode(entry.encode());

    expect(decoded, entry);
  });

  test('tryDecode rejects an unrecognized top-level key', () {
    final entry = PersistedOutboxMutation(change: createChange());
    final raw = entry.encode()..['somethingUnexpected'] = true;

    expect(PersistedOutboxMutation.tryDecode(raw), isNull);
  });

  test('tryDecode rejects an unrecognized kind value', () {
    final entry = PersistedOutboxMutation(change: createChange());
    final raw = entry.encode()..['kind'] = 'archive';

    expect(PersistedOutboxMutation.tryDecode(raw), isNull);
  });

  test('tryDecode rejects an unrecognized status value', () {
    final entry = PersistedOutboxMutation(change: createChange());
    final raw = entry.encode()..['status'] = 'unknownStatus';

    expect(PersistedOutboxMutation.tryDecode(raw), isNull);
  });

  test('tryDecode rejects a negative enqueuedAtMs', () {
    final entry = PersistedOutboxMutation(change: createChange());
    final raw = entry.encode()..['enqueuedAtMs'] = -1;

    expect(PersistedOutboxMutation.tryDecode(raw), isNull);
  });

  test(
      'tryDecode rejects an impossible active/tombstone combination '
      '(delete kind, active-form record)', () {
    final raw = {
      'kind': 'delete',
      'status': 'pending',
      'enqueuedAtMs': 1000,
      'record': _PersistedProjectionLike.activeMap(revealId),
    };

    expect(PersistedOutboxMutation.tryDecode(raw), isNull);
  });

  test(
      'tryDecode rejects a persisted record map carrying a platform wire-tag '
      'key (recordType/zoneName) -- this store persists the domain '
      'projection only, never the platform-bridge wire shape', () {
    final entry = PersistedOutboxMutation(change: createChange());
    final raw = Map<String, Object?>.from(entry.encode());
    final record =
        Map<Object?, Object?>.from(raw['record']! as Map<Object?, Object?>)
          ..['recordType'] = 'CKKeptWisdom';
    raw['record'] = record;

    expect(PersistedOutboxMutation.tryDecode(raw), isNull);
  });

  test('toLogSafeSummary never includes wisdom text', () {
    final entry = PersistedOutboxMutation(
      change: SyncChange(
        kind: SyncChangeKind.create,
        projection: activeProjection(
          wisdomText: 'A secret reflection that must never be logged.',
        ),
        enqueuedAt: DateTime.utc(2026, 8, 1),
      ),
    );

    final summary = entry.toLogSafeSummary().toString();
    expect(summary, isNot(contains('secret reflection')));
  });

  test('copyWith changes only status', () {
    final entry = PersistedOutboxMutation(change: createChange());
    final updated =
        entry.copyWith(status: PersistedOutboxMutationStatus.failed);

    expect(updated.status, PersistedOutboxMutationStatus.failed);
    expect(updated.change, entry.change);
    expect(entry.status, PersistedOutboxMutationStatus.pending);
  });
}

/// A minimal hand-built persisted-record map matching this store's own
/// domain-projection shape (see `persisted_outbox_mutation.dart`'s private
/// `_encodeProjection`/`_persistedProjectionKeys`) -- deliberately never the
/// platform-bridge wire envelope's shape (no `recordType`/`zoneName` tags),
/// since this store must never depend on that layer at all. Used only to
/// prove the impossible-combination rejection test above without depending
/// on `PersistedOutboxMutation.encode`'s own field ordering.
class _PersistedProjectionLike {
  static Map<Object?, Object?> activeMap(String revealId) => {
        'recordName': 'east-kept-$revealId',
        'isTombstone': false,
        'revealId': revealId,
        'wisdomText': 'Synthetic.',
        'revealedAtMs': 1000,
        'keptAtMs': 2000,
        'updatedAtMs': 3000,
        'mutationId': 'cccccccc-3333-4333-8333-333333333333',
        'dataEpoch': 'bbbbbbbb-2222-4222-8222-222222222222',
        'schemaVersion': 3,
      };
}
