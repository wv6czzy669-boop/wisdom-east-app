// Build 26 Phase 3D-C production cutover: `SavedReflectionsService` is now a
// thin, additive-free delegation layer over `KeptRepository` — it no longer
// touches SharedPreferences, the legacy `favorites` key, or migration
// directly, and holds no storage state of its own. This suite therefore no
// longer re-verifies `KeptRepository`'s own migration/limit/duplicate/
// concurrency rules (those remain covered exhaustively by
// `test/kept_repository_test.dart`); it verifies only that this thin layer
// delegates correctly and maps `KeptRepository`'s result/exception shapes
// into `SavedReflectionsResult`/`RemovedSavedReflection` faithfully.
import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/models/kept_bootstrap_result.dart';
import 'package:wisdom_app/persistence/persistence_operation_coordinator.dart';
import 'package:wisdom_app/repositories/kept_repository.dart';
import 'package:wisdom_app/services/saved_reflections_service.dart';

import 'persistence_test_helpers.dart';

void main() {
  late KeptRepositoryTestGraph graph;
  late SavedReflectionsService service;

  setUp(() {
    graph = KeptRepositoryTestGraph(
      clock: () => DateTime.utc(2026, 8, 1, 12),
    );
    service = graph.service;
  });

  group('load', () {
    test('empty protected storage loads empty', () async {
      expect(await service.load(), isEmpty);
    });

    test('load reflects whatever KeptRepository currently holds', () async {
      await graph.repository.keepOccurrence(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        wisdomText: 'Be still.',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );

      final loaded = await service.load();

      expect(loaded, hasLength(1));
      expect(loaded.single.text, 'Be still.');
      expect(loaded.single.revealId, 'a5f3c111-1111-4111-8111-111111111111');
    });
  });

  group('toggle: new occurrence (no existingId)', () {
    test('keeps a new occurrence identified by revealId', () async {
      final result = await service.toggle(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        text: 'Be still.',
        date: 'August 1, 2026',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );

      expect(result.limitReached, isFalse);
      expect(result.items, hasLength(1));
      expect(result.items.single.text, 'Be still.');
      expect(
        result.items.single.revealId,
        'a5f3c111-1111-4111-8111-111111111111',
      );
      // Section 5 (b): `revealedAt` itself is not exposed on the
      // display-only `FavoriteItem`, so its exact passthrough is proven via
      // the underlying `KeptRecord` the same `KeptRepositoryTestGraph`'s
      // store now holds.
      expect(
        graph.store.envelope!.activeRecords.single.revealedAt,
        DateTime.utc(2026, 8, 1),
      );
    });

    test(
        'duplicate wisdom text with different revealIds remains two '
        'separate kept records', () async {
      const sharedText = 'A wisdom the pool repeats across two distinct days';
      final first = await service.toggle(
        revealId: 'a5f3c111-1111-4111-8111-111111111101',
        text: sharedText,
        date: 'August 1, 2026',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );
      final second = await service.toggle(
        revealId: 'a5f3c111-1111-4111-8111-111111111102',
        text: sharedText,
        date: 'August 1, 2026',
        revealedAt: DateTime.utc(2026, 8, 2),
        isKeeper: false,
      );

      expect(first.items, hasLength(1));
      expect(second.items, hasLength(2));
      final loaded = await service.load();
      expect(loaded.map((item) => item.revealId).toSet(), {
        'a5f3c111-1111-4111-8111-111111111101',
        'a5f3c111-1111-4111-8111-111111111102',
      });
      expect(loaded.every((item) => item.text == sharedText), isTrue);
    });

    test(
        'Toggle correction (1): date never determines or influences '
        'KeptRecord.revealedAt — it is compatibility-only and is never '
        'parsed', () async {
      // If `date` were parsed and used, this Y2K-era string would produce
      // a wildly different stored `revealedAt` than the authoritative
      // `revealedAt` argument below.
      final result = await service.toggle(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        text: 'Be still.',
        date: 'January 1, 2000',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );

      expect(result.items, hasLength(1));
      final stored = graph.store.envelope!.activeRecords.single;
      expect(stored.revealedAt, DateTime.utc(2026, 8, 1));
      expect(stored.revealedAt, isNot(DateTime.utc(2000, 1, 1)));
    });

    test(
        'Toggle correction (2 & 4): an already-kept revealId remains '
        'idempotent even when a later call supplies different text/date — '
        'neither text nor date participates in identity, and the original '
        'kept content is never overwritten by the second call\'s text',
        () async {
      const revealId = 'a5f3c111-1111-4111-8111-111111111111';

      final first = await service.toggle(
        revealId: revealId,
        text: 'The original wisdom text',
        date: 'August 1, 2026',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );
      final second = await service.toggle(
        revealId: revealId,
        text: 'A completely different piece of text',
        date: 'January 1, 2000',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );

      // Identity (revealId) alone determined this was already kept: no
      // second record was created despite the differing text/date.
      expect(first.items, hasLength(1));
      expect(second.items, hasLength(1));
      expect(await service.load(), hasLength(1));
      // The original call's content is untouched — the second call's
      // (different) text/date never overwrote it.
      final loaded = await service.load();
      expect(loaded.single.text, 'The original wisdom text');
    });

    test('toggling the exact same revealId twice is idempotent', () async {
      const revealId = 'a5f3c111-1111-4111-8111-111111111111';
      final revealedAt = DateTime.utc(2026, 8, 1);

      await service.toggle(
        revealId: revealId,
        text: 'Be still.',
        date: 'August 1, 2026',
        revealedAt: revealedAt,
        isKeeper: false,
      );
      final second = await service.toggle(
        revealId: revealId,
        text: 'Be still.',
        date: 'August 1, 2026',
        revealedAt: revealedAt,
        isKeeper: false,
      );

      expect(second.items, hasLength(1));
      expect(await service.load(), hasLength(1));
    });

    test('free users are blocked at the free Kept limit', () async {
      for (var i = 0; i < 3; i += 1) {
        final result = await service.toggle(
          revealId: 'a5f3c111-1111-4111-8111-11111111111$i',
          text: 'Wisdom $i',
          date: 'August 1, 2026',
          revealedAt: DateTime.utc(2026, 8, 1),
          isKeeper: false,
        );
        expect(result.limitReached, isFalse);
      }

      final fourth = await service.toggle(
        revealId: 'a5f3c111-1111-4111-8111-111111111999',
        text: 'Wisdom 4',
        date: 'August 1, 2026',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );

      expect(fourth.limitReached, isTrue);
      expect(fourth.items, hasLength(3));
    });

    test('Keeper users are not limited', () async {
      for (var i = 0; i < 5; i += 1) {
        final result = await service.toggle(
          revealId: 'a5f3c111-1111-4111-8111-11111111111$i',
          text: 'Wisdom $i',
          date: 'August 1, 2026',
          revealedAt: DateTime.utc(2026, 8, 1),
          isKeeper: true,
        );
        expect(result.limitReached, isFalse);
      }

      expect(await service.load(), hasLength(5));
    });
  });

  group('toggle: removal (existingId)', () {
    test('an existingId matching an active record removes it', () async {
      final kept = await service.toggle(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        text: 'Be still.',
        date: 'August 1, 2026',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );
      final itemId = kept.items.single.id;

      final removed = await service.toggle(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        text: 'Be still.',
        date: 'August 1, 2026',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
        existingId: itemId,
      );

      expect(removed.items, isEmpty);
      expect(await service.load(), isEmpty);
    });

    test(
        'an existingId with no matching active record is a no-op success '
        '(mirrors the pre-cutover toggle contract)', () async {
      final result = await service.toggle(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        text: 'Be still.',
        date: 'August 1, 2026',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
        existingId: 'does-not-exist',
      );

      expect(result.items, isEmpty);
      expect(result.limitReached, isFalse);
    });

    test(
        'an existingId removes only that record, leaving every other active '
        'record untouched', () async {
      final first = await service.toggle(
        revealId: 'a5f3c111-1111-4111-8111-111111111101',
        text: 'First wisdom',
        date: 'August 1, 2026',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );
      final second = await service.toggle(
        revealId: 'a5f3c111-1111-4111-8111-111111111102',
        text: 'Second wisdom',
        date: 'August 1, 2026',
        revealedAt: DateTime.utc(2026, 8, 2),
        isKeeper: false,
      );
      final firstId = first.items.single.id;
      final secondId =
          second.items.firstWhere((item) => item.text == 'Second wisdom').id;

      final afterRemoval = await service.toggle(
        revealId: 'a5f3c111-1111-4111-8111-111111111101',
        text: 'First wisdom',
        date: 'August 1, 2026',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
        existingId: firstId,
      );

      expect(afterRemoval.items, hasLength(1));
      expect(afterRemoval.items.single.id, secondId);
      expect(afterRemoval.items.single.text, 'Second wisdom');
      final loaded = await service.load();
      expect(loaded, hasLength(1));
      expect(loaded.single.id, secondId);
    });
  });

  group('saveReflection / deleteReflection', () {
    test('saveReflection delegates and maps the mutation result', () async {
      final kept = await service.toggle(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        text: 'Be still.',
        date: 'August 1, 2026',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );
      final itemId = kept.items.single.id;

      // Fixture correction: the graph's clock (and therefore this record's
      // `keptAt`) is fixed at `2026-08-01 12:00 UTC` (see `setUp` above).
      // `KeptRecord` requires `updatedAt` (which `saveReflection` sets from
      // this `reflectedAt`) to never be before `keptAt` — an explicit
      // `reflectedAt` must be after that fixed noon, not before it.
      final saved = await service.saveReflection(
        itemId: itemId,
        reflection: 'A quiet morning.',
        isKeeper: false,
        reflectedAt: DateTime.utc(2026, 8, 1, 15),
      );

      expect(saved.reflectionLimitReached, isFalse);
      expect(saved.items.single.reflection, 'A quiet morning.');
    });

    test('saveReflection propagates the free reflection limit', () async {
      // Fixture correction: the free *Kept* limit (`freeKeptLimit`, default
      // 3) is a separate, earlier gate from the free *reflection* limit
      // this test targets. Creating all four distinct occurrences with
      // `isKeeper: false` tripped the Kept limit on the fourth `toggle`
      // call instead — no fourth record was ever created, so
      // `kept.items.singleWhere((item) => item.text == 'Wisdom 3')` found
      // nothing. Creating as a Keeper here only bypasses the *Kept* limit
      // during setup; every `saveReflection` call below still passes
      // `isKeeper: false`, so the free *reflection* limit this test is
      // actually about still applies exactly as before.
      final ids = <String>[];
      for (var i = 0; i < 4; i += 1) {
        final kept = await service.toggle(
          revealId: 'a5f3c111-1111-4111-8111-11111111111$i',
          text: 'Wisdom $i',
          date: 'August 1, 2026',
          revealedAt: DateTime.utc(2026, 8, 1),
          isKeeper: true,
        );
        ids.add(
          kept.items.singleWhere((item) => item.text == 'Wisdom $i').id,
        );
      }
      expect(ids.toSet(), hasLength(4));

      for (var i = 0; i < 3; i += 1) {
        final result = await service.saveReflection(
          itemId: ids[i],
          reflection: 'Reflection $i',
          isKeeper: false,
        );
        expect(result.reflectionLimitReached, isFalse);
      }

      final blocked = await service.saveReflection(
        itemId: ids[3],
        reflection: 'Fourth reflection',
        isKeeper: false,
      );
      expect(blocked.reflectionLimitReached, isTrue);
      // The target record remains present and unchanged — blocked, not
      // dropped.
      final afterBlock = await service.load();
      expect(afterBlock, hasLength(4));
      final target = afterBlock.singleWhere((item) => item.id == ids[3]);
      expect(target.hasReflection, isFalse);
    });

    test('an invalid reflection throws (KeptRepository validates it)',
        () async {
      final kept = await service.toggle(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        text: 'Be still.',
        date: 'August 1, 2026',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );

      await expectLater(
        service.saveReflection(
          itemId: kept.items.single.id,
          reflection: '   ',
          isKeeper: false,
        ),
        throwsA(isA<KeptRepositoryException>()),
      );
    });

    test(
        'saveReflection for a missing item preserves KeptRepository\'s '
        '"missing-item" error, not a swallowed or generic one', () async {
      await expectLater(
        service.saveReflection(
          itemId: 'does-not-exist',
          reflection: 'A reflection for a record that is gone',
          isKeeper: false,
        ),
        throwsA(
          isA<KeptRepositoryException>().having(
            (error) => error.stage,
            'stage',
            'missing-item',
          ),
        ),
      );
    });

    test(
        'deleteReflection for a missing item preserves KeptRepository\'s '
        '"missing-item" error, not a swallowed or generic one', () async {
      await expectLater(
        service.deleteReflection(itemId: 'does-not-exist'),
        throwsA(
          isA<KeptRepositoryException>().having(
            (error) => error.stage,
            'stage',
            'missing-item',
          ),
        ),
      );
    });

    test('deleteReflection delegates and clears the reflection', () async {
      final kept = await service.toggle(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        text: 'Be still.',
        date: 'August 1, 2026',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );
      final itemId = kept.items.single.id;
      await service.saveReflection(
        itemId: itemId,
        reflection: 'A quiet morning.',
        isKeeper: false,
      );

      final afterDelete = await service.deleteReflection(itemId: itemId);

      expect(afterDelete.single.hasReflection, isFalse);
    });
  });

  group('remove / restore', () {
    test('remove returns null for an item that does not exist', () async {
      expect(await service.remove(itemId: 'missing'), isNull);
    });

    test('remove then restore round-trips the exact removed occurrence',
        () async {
      final kept = await service.toggle(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        text: 'Be still.',
        date: 'August 1, 2026',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );
      await service.saveReflection(
        itemId: kept.items.single.id,
        reflection: 'A quiet morning.',
        isKeeper: false,
      );
      final beforeRemoval = await service.load();

      final removed = await service.remove(itemId: kept.items.single.id);
      expect(removed, isNotNull);
      expect(await service.load(), isEmpty);

      final restored = await service.restore(removed!);

      expect(restored, hasLength(1));
      expect(
        restored.single.encode(),
        beforeRemoval.single.encode(),
      );
    });

    test(
        'remove then restore carries the exact RemovedKeptOccurrence, '
        'including its originalIndex among several active records', () async {
      for (var i = 0; i < 3; i += 1) {
        await service.toggle(
          revealId: 'a5f3c111-1111-4111-8111-11111111120$i',
          text: 'Wisdom $i',
          date: 'August 1, 2026',
          revealedAt: DateTime.utc(2026, 8, 1),
          isKeeper: false,
        );
      }
      final beforeRemoval = await service.load();
      final middle = beforeRemoval.firstWhere(
        (item) => item.text == 'Wisdom 1',
      );
      final middleIndex = beforeRemoval.indexOf(middle);

      final removed = await service.remove(itemId: middle.id);
      expect(removed, isNotNull);
      // `RemovedSavedReflection.items` (a pass-through to
      // `RemovedKeptOccurrence.items`) is the *remaining* active list after
      // removal, not the removed record itself — with 3 active records to
      // start, removing 1 always leaves 2, so `.single` here is always
      // wrong regardless of which record was targeted. The removed
      // record's own identity is proven instead by confirming it is no
      // longer present among what remains, and that the other two records
      // (in their original relative order) are untouched.
      expect(removed!.items, hasLength(2));
      expect(removed.items.any((item) => item.id == middle.id), isFalse);
      expect(
        removed.items.map((item) => item.text).toList(),
        beforeRemoval
            .where((item) => item.id != middle.id)
            .map((item) => item.text)
            .toList(),
      );
      expect(removed.originalIndex, middleIndex);

      final restored = await service.restore(removed);
      expect(restored, hasLength(3));
      final restoredMiddle = restored.firstWhere((i) => i.id == middle.id);
      // Restored to the exact original position, and with its exact prior
      // content/timestamps — not merely present somewhere in the list.
      expect(restored.indexOf(restoredMiddle), middleIndex);
      expect(restoredMiddle.encode(), middle.encode());
    });

    test('restoring an already-active occurrence twice is duplicate-safe',
        () async {
      final kept = await service.toggle(
        revealId: 'a5f3c111-1111-4111-8111-111111111111',
        text: 'Be still.',
        date: 'August 1, 2026',
        revealedAt: DateTime.utc(2026, 8, 1),
        isKeeper: false,
      );
      final removed = await service.remove(itemId: kept.items.single.id);

      final firstRestore = await service.restore(removed!);
      final secondRestore = await service.restore(removed);

      expect(firstRestore, hasLength(1));
      expect(secondRestore, hasLength(1));
    });
  });

  group('bootstrap-unavailable propagation', () {
    test('every operation throws when Kept storage is unavailable', () async {
      final unavailableGraph = KeptRepositoryTestGraph(
        bootstrap:
            KeptBootstrapResult.unavailable('protected-store-load-failed'),
      );
      final unavailableService = unavailableGraph.service;

      await expectLater(
        unavailableService.load(),
        throwsA(isA<KeptRepositoryException>()),
      );
      await expectLater(
        unavailableService.toggle(
          revealId: 'a5f3c111-1111-4111-8111-111111111111',
          text: 'Be still.',
          date: 'August 1, 2026',
          revealedAt: DateTime.utc(2026, 8, 1),
          isKeeper: false,
        ),
        throwsA(isA<KeptRepositoryException>()),
      );
    });
  });

  group('constructor', () {
    test('requires an explicit KeptRepository (no hidden default)', () {
      final repository = KeptRepository(
        store: InMemoryKeptStateStore(),
        bootstrap: const KeptBootstrapResult.ready(),
        operationCoordinator: PersistenceOperationCoordinator(),
      );

      expect(
        () => SavedReflectionsService(keptRepository: repository),
        returnsNormally,
      );
    });
  });
}
