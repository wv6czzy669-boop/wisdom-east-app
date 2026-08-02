// Build 26 Phase 4A: the pure, deterministic conflict-resolution policy.
// See docs/architecture/EAST_CLOUDKIT_SYNC_V1.md §4.
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/models/kept_record.dart';
import 'package:wisdom_app/sync/cloud_kept_wisdom_projection.dart';
import 'package:wisdom_app/sync/conflict_resolution.dart';
import 'package:wisdom_app/sync/data_epoch.dart';
import 'package:wisdom_app/sync/sync_tombstone.dart';

void main() {
  const revealId = 'c947bbb4-f86a-4db3-87c9-ed5e718bbd98';
  const mutationIdA = '22222222-2222-4222-8222-222222222222';
  const mutationIdB = '33333333-3333-4333-8333-333333333333';
  final currentEpoch = DataEpoch.parse('11111111-1111-4111-8111-111111111111');
  final staleEpoch = DataEpoch.parse('44444444-4444-4444-8444-444444444444');
  final revealedAt = DateTime.utc(2026, 8, 1, 20, 0);
  final keptAt = DateTime.utc(2026, 8, 1, 20, 5);

  CloudKeptWisdomProjection active({
    DataEpoch? epoch,
    DateTime? updatedAt,
    String? reflectionText,
    String mutationId = mutationIdA,
    String wisdomText = 'Be still and know.',
  }) {
    final record = KeptRecord(
      id: 'local-id-1',
      revealId: revealId,
      wisdomText: wisdomText,
      revealedAt: revealedAt,
      keptAt: keptAt,
      reflectionText: reflectionText,
      reflectedAt: reflectionText == null ? null : updatedAt ?? keptAt,
      updatedAt: updatedAt ?? keptAt,
      mutationId: mutationId,
    );
    return CloudKeptWisdomProjection.active(
      record,
      dataEpoch: epoch ?? currentEpoch,
    );
  }

  CloudKeptWisdomProjection tombstone({
    DataEpoch? epoch,
    DateTime? updatedAt,
    String mutationId = mutationIdA,
  }) {
    final at = updatedAt ?? keptAt;
    return CloudKeptWisdomProjection.tombstone(
      SyncTombstone(
        revealId: revealId,
        dataEpoch: epoch ?? currentEpoch,
        updatedAt: at,
        deletedAt: at,
        mutationId: mutationId,
      ),
    );
  }

  test('1. an active record with a newer updatedAt wins over an older one', () {
    final older = active(updatedAt: keptAt);
    final newer = active(updatedAt: keptAt.add(const Duration(minutes: 5)));

    final outcome = resolveKeptWisdomConflict(
      local: older,
      remote: newer,
      authoritativeEpoch: currentEpoch,
    );

    expect(outcome.reason, ConflictReason.newerUpdatedAt);
    expect(outcome.winner, newer);
  });

  test(
      '2. Reflection updates merge deterministically -- the newer edit wins '
      'in full, never a field-level merge of both texts', () {
    final older = active(
      updatedAt: keptAt,
      reflectionText: 'Older reflection.',
    );
    final newer = active(
      updatedAt: keptAt.add(const Duration(minutes: 10)),
      reflectionText: 'Newer reflection.',
    );

    final outcome = resolveKeptWisdomConflict(
      local: newer,
      remote: older,
      authoritativeEpoch: currentEpoch,
    );

    expect(outcome.winner!.reflectionText, 'Newer reflection.');
  });

  test('3. a newer tombstone defeats an older active edit', () {
    final olderEdit = active(updatedAt: keptAt);
    final newerTombstone =
        tombstone(updatedAt: keptAt.add(const Duration(minutes: 5)));

    final outcome = resolveKeptWisdomConflict(
      local: olderEdit,
      remote: newerTombstone,
      authoritativeEpoch: currentEpoch,
    );

    expect(outcome.winner!.isTombstone, isTrue);
  });

  test(
      '4. an older tombstone does not defeat a newer valid change '
      '(same epoch, no equal-timestamp tie)', () {
    final olderTombstone = tombstone(updatedAt: keptAt);
    final newerEdit = active(updatedAt: keptAt.add(const Duration(minutes: 5)));

    final outcome = resolveKeptWisdomConflict(
      local: olderTombstone,
      remote: newerEdit,
      authoritativeEpoch: currentEpoch,
    );

    expect(outcome.winner!.isTombstone, isFalse);
    expect(outcome.reason, ConflictReason.newerUpdatedAt);
  });

  test(
      '5. equal timestamps: an active record and a tombstone -- the '
      'tombstone wins on tie, deletion is never silently undone', () {
    final tie = keptAt;
    final activeAtTie = active(updatedAt: tie);
    final tombstoneAtTie = tombstone(updatedAt: tie);

    final outcome = resolveKeptWisdomConflict(
      local: activeAtTie,
      remote: tombstoneAtTie,
      authoritativeEpoch: currentEpoch,
    );

    expect(outcome.reason, ConflictReason.tombstoneWinsOnTie);
    expect(outcome.winner!.isTombstone, isTrue);
  });

  test(
      '6. equal timestamps, both active: the lexicographically greater '
      'mutationId is the stable, deterministic tie-breaker', () {
    final a = active(updatedAt: keptAt, mutationId: mutationIdA);
    final b = active(
      updatedAt: keptAt,
      mutationId: mutationIdB,
      reflectionText: 'Different content, same timestamp.',
    );

    final outcome = resolveKeptWisdomConflict(
      local: a,
      remote: b,
      authoritativeEpoch: currentEpoch,
    );

    // mutationIdB > mutationIdA lexicographically.
    expect(outcome.reason, ConflictReason.mutationIdTiebreak);
    expect(outcome.winner!.mutationId, mutationIdB);
  });

  test(
      '7. the mutationId tie-break is stable regardless of which side is '
      'passed as local vs. remote (order-independent outcome)', () {
    final a = active(updatedAt: keptAt, mutationId: mutationIdA);
    final b = active(
      updatedAt: keptAt,
      mutationId: mutationIdB,
      reflectionText: 'Different content, same timestamp.',
    );

    final first = resolveKeptWisdomConflict(
      local: a,
      remote: b,
      authoritativeEpoch: currentEpoch,
    );
    final second = resolveKeptWisdomConflict(
      local: b,
      remote: a,
      authoritativeEpoch: currentEpoch,
    );

    expect(first.winner!.mutationId, second.winner!.mutationId);
  });

  test(
      '8. clock-skew handling is deterministic: whichever device labeled '
      '"local" holds the objectively later updatedAt always wins, '
      'independent of role labeling', () {
    final deviceX = active(updatedAt: keptAt.add(const Duration(hours: 2)));
    final deviceY = active(updatedAt: keptAt);

    final asLocal = resolveKeptWisdomConflict(
      local: deviceX,
      remote: deviceY,
      authoritativeEpoch: currentEpoch,
    );
    final asRemote = resolveKeptWisdomConflict(
      local: deviceY,
      remote: deviceX,
      authoritativeEpoch: currentEpoch,
    );

    expect(asLocal.winner, deviceX);
    expect(asRemote.winner, deviceX);
  });

  test(
      '9. a stale-epoch record cannot resurrect data even with a newer '
      'updatedAt than the authoritative-epoch record', () {
    final staleButNewer = active(
      epoch: staleEpoch,
      updatedAt: keptAt.add(const Duration(days: 1)),
    );
    final currentButOlder = active(epoch: currentEpoch, updatedAt: keptAt);

    final outcome = resolveKeptWisdomConflict(
      local: staleButNewer,
      remote: currentButOlder,
      authoritativeEpoch: currentEpoch,
    );

    expect(outcome.reason, ConflictReason.epochSupersedes);
    expect(outcome.winner, currentButOlder);
  });

  test(
      '10. a stale-epoch tombstone cannot resurrect data either -- epoch '
      'outranks the tombstone-wins-on-tie rule too', () {
    final staleTombstone = tombstone(
      epoch: staleEpoch,
      updatedAt: keptAt.add(const Duration(days: 1)),
    );
    final currentActive = active(epoch: currentEpoch, updatedAt: keptAt);

    final outcome = resolveKeptWisdomConflict(
      local: staleTombstone,
      remote: currentActive,
      authoritativeEpoch: currentEpoch,
    );

    expect(outcome.winner!.isTombstone, isFalse);
  });

  test(
      '11. when neither side matches the authoritative epoch, resolution '
      'fails closed with no winner', () {
    final other1 = DataEpoch.parse('55555555-5555-4555-8555-555555555555');
    final other2 = DataEpoch.parse('66666666-6666-4666-8666-666666666666');

    final outcome = resolveKeptWisdomConflict(
      local: active(epoch: other1),
      remote: active(epoch: other2),
      authoritativeEpoch: currentEpoch,
    );

    expect(outcome.reason, ConflictReason.bothEpochsStale);
    expect(outcome.isRejected, isTrue);
    expect(outcome.winner, isNull);
  });

  test(
      '12. immutable-field mismatch between two active claims of the same '
      'recordName fails closed rather than silently picking one', () {
    final recordA = active();
    final recordBDifferentText = active(wisdomText: 'A different wisdom.');

    final outcome = resolveKeptWisdomConflict(
      local: recordA,
      remote: recordBDifferentText,
      authoritativeEpoch: currentEpoch,
    );

    expect(outcome.reason, ConflictReason.immutableFieldMismatch);
    expect(outcome.isRejected, isTrue);
  });

  test(
      '13. keptAt/revealedAt never influence the outcome -- two records '
      'differing only in updatedAt/mutationId (identity fields identical) '
      'resolve purely on those, never on keptAt/revealedAt, since neither '
      'is even a parameter to this function', () {
    final a = active(updatedAt: keptAt);
    final b = active(updatedAt: keptAt.add(const Duration(minutes: 1)));

    final outcome = resolveKeptWisdomConflict(
      local: a,
      remote: b,
      authoritativeEpoch: currentEpoch,
    );

    expect(outcome.winner!.keptAtMs, a.keptAtMs);
    expect(outcome.winner!.revealedAtMs, a.revealedAtMs);
  });

  test(
      '14. field-for-field identical candidates resolve as identical, '
      'not as an arbitrary tie-break', () {
    final a = active(updatedAt: keptAt);
    final b = active(updatedAt: keptAt);

    final outcome = resolveKeptWisdomConflict(
      local: a,
      remote: b,
      authoritativeEpoch: currentEpoch,
    );

    expect(outcome.reason, ConflictReason.identical);
  });

  test(
      '15. throws ArgumentError when local and remote do not share a '
      'recordName -- this function never compares two different '
      'occurrences', () {
    const otherRevealId = 'affbc527-29c4-5d19-b678-1bc7f9dfb7d4';
    final record = KeptRecord(
      id: 'local-id-2',
      revealId: otherRevealId,
      wisdomText: 'A different occurrence entirely.',
      revealedAt: revealedAt,
      keptAt: keptAt,
      updatedAt: keptAt,
      mutationId: mutationIdA,
    );
    final differentOccurrence =
        CloudKeptWisdomProjection.active(record, dataEpoch: currentEpoch);

    expect(
      () => resolveKeptWisdomConflict(
        local: active(),
        remote: differentOccurrence,
        authoritativeEpoch: currentEpoch,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
