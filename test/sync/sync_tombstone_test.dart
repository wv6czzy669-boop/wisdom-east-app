// Build 26 Phase 4A: SyncTombstone -- the local, sync-only deletion marker.
// See docs/architecture/EAST_CLOUDKIT_SYNC_V1.md §2.4.
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/sync/data_epoch.dart';
import 'package:wisdom_app/sync/sync_tombstone.dart';

void main() {
  const revealId = 'c947bbb4-f86a-4db3-87c9-ed5e718bbd98';
  const mutationId = '22222222-2222-4222-8222-222222222222';
  final epoch = DataEpoch.parse('11111111-1111-4111-8111-111111111111');
  final deletedAt = DateTime.utc(2026, 8, 1, 12, 0);

  SyncTombstone build({DateTime? updatedAt}) => SyncTombstone(
        revealId: revealId,
        dataEpoch: epoch,
        updatedAt: updatedAt ?? deletedAt,
        deletedAt: deletedAt,
        mutationId: mutationId,
      );

  test('1. a valid tombstone constructs successfully', () {
    expect(build, returnsNormally);
  });

  test('2. rejects a noncanonical revealId', () {
    expect(
      () => SyncTombstone(
        revealId: 'not-a-uuid',
        dataEpoch: epoch,
        updatedAt: deletedAt,
        deletedAt: deletedAt,
        mutationId: mutationId,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('3. rejects a noncanonical mutationId', () {
    expect(
      () => SyncTombstone(
        revealId: revealId,
        dataEpoch: epoch,
        updatedAt: deletedAt,
        deletedAt: deletedAt,
        mutationId: 'not-a-uuid',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('4. rejects updatedAt before deletedAt', () {
    expect(
      () => build(updatedAt: deletedAt.subtract(const Duration(minutes: 1))),
      throwsA(isA<FormatException>()),
    );
  });

  test('5. accepts updatedAt exactly equal to deletedAt', () {
    expect(() => build(updatedAt: deletedAt), returnsNormally);
  });

  test(
      '6. accepts updatedAt after deletedAt (a later Reflection edit before '
      'the eventual delete became final)', () {
    expect(
      () => build(updatedAt: deletedAt.add(const Duration(minutes: 5))),
      returnsNormally,
    );
  });

  test('7. sub-millisecond precision is canonicalized away', () {
    final withMicros = SyncTombstone(
      revealId: revealId,
      dataEpoch: epoch,
      updatedAt: deletedAt.add(const Duration(microseconds: 500)),
      deletedAt: deletedAt.add(const Duration(microseconds: 500)),
      mutationId: mutationId,
    );
    expect(withMicros.updatedAt.microsecond, 0);
    expect(withMicros.deletedAt.microsecond, 0);
  });

  test('8. equality is field-based, including localId', () {
    final a = build();
    final b = build();
    expect(a, b);
    final withLocalId = SyncTombstone(
      revealId: revealId,
      dataEpoch: epoch,
      updatedAt: deletedAt,
      deletedAt: deletedAt,
      mutationId: mutationId,
      localId: 'local-id-1',
    );
    expect(withLocalId, isNot(a));
  });

  test(
      '9. never carries wisdom or reflection content -- no such field '
      'exists on this type at all (structural proof via reflection-free '
      'toString containing only identifiers/timestamps)', () {
    final tombstone = build();
    final rendered = tombstone.toString();
    expect(rendered, isNot(contains('wisdomText')));
    expect(rendered, isNot(contains('reflectionText')));
  });

  test('10. localId is optional and defaults to null', () {
    final tombstone = build();
    expect(tombstone.localId, isNull);
  });
}
