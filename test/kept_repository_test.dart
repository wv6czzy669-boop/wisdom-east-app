import 'package:flutter_test/flutter_test.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/models/kept_bootstrap_result.dart';
import 'package:wisdom_app/models/kept_record.dart';
import 'package:wisdom_app/models/kept_state_envelope.dart';
import 'package:wisdom_app/persistence/kept_state_store.dart';
import 'package:wisdom_app/persistence/persistence_operation_coordinator.dart';
import 'package:wisdom_app/persistence/protected_file_kept_state_store.dart'
    show KeptStateStoreException;
import 'package:wisdom_app/repositories/kept_repository.dart';
import 'package:wisdom_app/utils/date_formatter.dart';
import 'package:wisdom_app/utils/legacy_kept_identity.dart';

import 'persistence_test_helpers.dart';

final RegExp _uuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

class _FakeKeptStateStore implements KeptStateStore {
  KeptStateEnvelope? envelope;
  bool loadShouldFail = false;
  bool replaceShouldFail = false;
  int loadCallCount = 0;
  int replaceCallCount = 0;

  @override
  Future<KeptStateEnvelope?> load() async {
    loadCallCount += 1;
    if (loadShouldFail) {
      throw const KeptStateStoreException(
        'load-decode',
        'Simulated corrupt kept-state file.',
      );
    }
    return envelope;
  }

  @override
  Future<void> replace(KeptStateEnvelope newEnvelope) async {
    replaceCallCount += 1;
    if (replaceShouldFail) {
      throw const KeptStateStoreException(
        'replace-verify-final',
        'Simulated replace failure.',
      );
    }
    envelope = newEnvelope;
  }
}

/// Deterministic, canonical-UUID-v4-shaped id generator so tests can assert
/// exact identities and exact call counts without depending on real
/// randomness.
class _SequentialIdFactory {
  int _counter = 0;

  String call() {
    _counter += 1;
    final suffix = _counter.toRadixString(16).padLeft(12, '0');
    return '00000000-0000-4000-8000-$suffix';
  }
}

void main() {
  late DateTime now;
  late _FakeKeptStateStore store;
  late PersistenceOperationCoordinator coordinator;
  late _SequentialIdFactory idFactory;

  setUp(() {
    now = DateTime.utc(2026, 8, 1, 9, 0);
    store = _FakeKeptStateStore();
    coordinator = PersistenceOperationCoordinator();
    idFactory = _SequentialIdFactory();
  });

  KeptRepository buildRepository({
    KeptBootstrapResult? bootstrap,
    int freeKeptLimit = 3,
    int freeReflectionLimit = 3,
  }) {
    return KeptRepository(
      store: store,
      bootstrap: bootstrap ?? const KeptBootstrapResult.ready(),
      operationCoordinator: coordinator,
      idFactory: idFactory.call,
      clock: () => now,
      freeKeptLimit: freeKeptLimit,
      freeReflectionLimit: freeReflectionLimit,
    );
  }

  KeptRecord buildRecord({
    required String id,
    required String revealId,
    String wisdomText = 'Be still.',
    DateTime? revealedAt,
    DateTime? keptAt,
    String? reflectionText,
    DateTime? reflectedAt,
    DateTime? updatedAt,
    String mutationId = '00000000-0000-4000-8000-0000000000ff',
  }) {
    final effectiveKeptAt = keptAt ?? now;
    return KeptRecord(
      id: id,
      revealId: revealId,
      wisdomText: wisdomText,
      revealedAt: revealedAt ?? now,
      keptAt: effectiveKeptAt,
      reflectionText: reflectionText,
      reflectedAt: reflectedAt,
      updatedAt: updatedAt ?? effectiveKeptAt,
      mutationId: mutationId,
    );
  }

  const revealA = '11111111-1111-4111-8111-111111111111';
  const revealB = '22222222-2222-4222-8222-222222222222';
  const revealC = '33333333-3333-4333-8333-333333333333';
  const revealD = '44444444-4444-4444-8444-444444444444';

  group('Bootstrap/failure gate', () {
    test('1. unavailable load throws before store access', () async {
      final repository = buildRepository(
        bootstrap: KeptBootstrapResult.unavailable('load-failed'),
      );

      await expectLater(
        repository.load(),
        throwsA(isA<KeptRepositoryException>()),
      );
      expect(store.loadCallCount, 0);
    });

    test('2. unavailable mutation throws before store access', () async {
      final repository = buildRepository(
        bootstrap: KeptBootstrapResult.unavailable('load-failed'),
      );

      await expectLater(
        repository.keepOccurrence(
          revealId: revealA,
          wisdomText: 'Be still.',
          revealedAt: now,
          isKeeper: false,
        ),
        throwsA(isA<KeptRepositoryException>()),
      );
      expect(store.loadCallCount, 0);
      expect(store.replaceCallCount, 0);
    });

    test('3. unavailable never creates an empty envelope', () async {
      final repository = buildRepository(
        bootstrap: KeptBootstrapResult.unavailable('load-failed'),
      );

      try {
        await repository.load();
      } catch (_) {
        // Expected.
      }

      expect(store.envelope, isNull);
    });

    test('4. ready + null store loads as empty', () async {
      final repository = buildRepository();

      final items = await repository.load();

      expect(items, isEmpty);
    });

    test('5. load failure propagates safely', () async {
      store.loadShouldFail = true;
      final repository = buildRepository();

      await expectLater(
        repository.load(),
        throwsA(isA<KeptRepositoryException>()),
      );
    });

    test('6. replace failure propagates safely', () async {
      store.replaceShouldFail = true;
      final repository = buildRepository();

      await expectLater(
        repository.keepOccurrence(
          revealId: revealA,
          wisdomText: 'Be still.',
          revealedAt: now,
          isKeeper: false,
        ),
        throwsA(isA<KeptRepositoryException>()),
      );
    });

    test('7. corruption/load exception never becomes an empty list', () async {
      store.loadShouldFail = true;
      final repository = buildRepository();

      Object? caught;
      List<FavoriteItem>? result;
      try {
        result = await repository.load();
      } catch (error) {
        caught = error;
      }

      expect(result, isNull);
      expect(caught, isA<KeptRepositoryException>());
    });
  });

  group('Identity', () {
    test('8. new record uses fresh UUID v4 id', () async {
      final repository = buildRepository();

      final result = await repository.keepOccurrence(
        revealId: revealA,
        wisdomText: 'Be still.',
        revealedAt: now,
        isKeeper: false,
      );

      expect(result.items.single.id, matches(_uuidV4Pattern));
    });

    test('9. authoritative revealId is preserved', () async {
      final repository = buildRepository();

      final result = await repository.keepOccurrence(
        revealId: revealA,
        wisdomText: 'Be still.',
        revealedAt: now,
        isKeeper: false,
      );

      expect(result.items.single.revealId, revealA);
    });

    test('10. new mutationId is UUID v4', () async {
      final repository = buildRepository();

      await repository.keepOccurrence(
        revealId: revealA,
        wisdomText: 'Be still.',
        revealedAt: now,
        isKeeper: false,
      );

      expect(store.envelope!.activeRecords.single.mutationId,
          matches(_uuidV4Pattern));
    });

    test('11. same revealId is idempotent', () async {
      final repository = buildRepository();

      final first = await repository.keepOccurrence(
        revealId: revealA,
        wisdomText: 'Be still.',
        revealedAt: now,
        isKeeper: false,
      );
      final second = await repository.keepOccurrence(
        revealId: revealA,
        wisdomText: 'Be still.',
        revealedAt: now,
        isKeeper: false,
      );

      expect(second.items.single.id, first.items.single.id);
      expect(second.items, hasLength(1));
    });

    test('12. same revealId no-op does not call replace', () async {
      final repository = buildRepository();
      await repository.keepOccurrence(
        revealId: revealA,
        wisdomText: 'Be still.',
        revealedAt: now,
        isKeeper: false,
      );
      final callsAfterFirst = store.replaceCallCount;

      await repository.keepOccurrence(
        revealId: revealA,
        wisdomText: 'Be still.',
        revealedAt: now,
        isKeeper: false,
      );

      expect(store.replaceCallCount, callsAfterFirst);
    });

    test('13. duplicate text with distinct revealIds creates two records',
        () async {
      final repository = buildRepository();

      await repository.keepOccurrence(
        revealId: revealA,
        wisdomText: 'Be still.',
        revealedAt: now,
        isKeeper: false,
      );
      final result = await repository.keepOccurrence(
        revealId: revealB,
        wisdomText: 'Be still.',
        revealedAt: now,
        isKeeper: false,
      );

      expect(result.items, hasLength(2));
      expect(result.items[0].revealId, isNot(result.items[1].revealId));
      expect(result.items[0].text, result.items[1].text);
    });

    test('14. invalid revealId is rejected', () async {
      final repository = buildRepository();

      await expectLater(
        repository.keepOccurrence(
          revealId: 'not-a-uuid',
          wisdomText: 'Be still.',
          revealedAt: now,
          isKeeper: false,
        ),
        throwsA(isA<KeptRepositoryException>()),
      );
      expect(store.replaceCallCount, 0);
    });

    // Build 26 Phase 3D-E (safety-gap correction, round 4): this test
    // previously asserted the *opposite* -- that a v5 revealId was rejected
    // here. That was correct in isolation, but combined with
    // `DailyAccessRepository.reconcileRevealIdForOccurrence` adopting a
    // genuine migrated v5 onto the Daily Access side, it meant a user who
    // deleted a reconciled legacy occurrence from Kept could never re-keep
    // it: `HomeScreen`'s Keep action always calls `keepOccurrence` with the
    // *current* `DailyWisdomRecord.revealId`, which for that occurrence is
    // now permanently v5. The policy is intentionally widened: a v5 is
    // accepted here specifically so that case works, while a malformed or
    // otherwise-unsupported-version string remains rejected (see test 14
    // above and test 15 below), and freshly-generated `id`/`mutationId`
    // values remain their own, separate, v4-only contract (`_generateId`,
    // unaffected by this change).
    test(
        '14b. a genuine migrated v5 revealId is accepted for keepOccurrence '
        '(re-keeping a reconciled legacy occurrence after deletion must not '
        'fail solely because its revealId is v5)', () async {
      final repository = buildRepository();
      const v5 = '6fa459ea-ee8a-5ca4-894e-db77e160355e';

      final result = await repository.keepOccurrence(
        revealId: v5,
        wisdomText: 'Be still.',
        revealedAt: now,
        isKeeper: false,
      );

      expect(result.limitReached, isFalse);
      final favorites = await repository.load();
      expect(favorites.single.revealId, v5);
    });

    test('15. generated invalid UUID is rejected', () async {
      final repository = KeptRepository(
        store: store,
        bootstrap: const KeptBootstrapResult.ready(),
        operationCoordinator: coordinator,
        idFactory: () => 'not-a-uuid',
        clock: () => now,
      );

      await expectLater(
        repository.keepOccurrence(
          revealId: revealA,
          wisdomText: 'Be still.',
          revealedAt: now,
          isKeeper: false,
        ),
        throwsA(isA<KeptRepositoryException>()),
      );
      expect(store.replaceCallCount, 0);
    });
  });

  group('Limits', () {
    test('16. free user can keep up to 3', () async {
      final repository = buildRepository();

      await repository.keepOccurrence(
          revealId: revealA, wisdomText: 'A', revealedAt: now, isKeeper: false);
      await repository.keepOccurrence(
          revealId: revealB, wisdomText: 'B', revealedAt: now, isKeeper: false);
      final result = await repository.keepOccurrence(
          revealId: revealC, wisdomText: 'C', revealedAt: now, isKeeper: false);

      expect(result.items, hasLength(3));
      expect(result.limitReached, isFalse);
    });

    test('17. fourth free keep is blocked', () async {
      final repository = buildRepository();
      await repository.keepOccurrence(
          revealId: revealA, wisdomText: 'A', revealedAt: now, isKeeper: false);
      await repository.keepOccurrence(
          revealId: revealB, wisdomText: 'B', revealedAt: now, isKeeper: false);
      await repository.keepOccurrence(
          revealId: revealC, wisdomText: 'C', revealedAt: now, isKeeper: false);

      final result = await repository.keepOccurrence(
          revealId: revealD, wisdomText: 'D', revealedAt: now, isKeeper: false);

      expect(result.limitReached, isTrue);
      expect(result.items, hasLength(3));
    });

    test('18. Keeper can exceed 3', () async {
      final repository = buildRepository();
      await repository.keepOccurrence(
          revealId: revealA, wisdomText: 'A', revealedAt: now, isKeeper: true);
      await repository.keepOccurrence(
          revealId: revealB, wisdomText: 'B', revealedAt: now, isKeeper: true);
      await repository.keepOccurrence(
          revealId: revealC, wisdomText: 'C', revealedAt: now, isKeeper: true);

      final result = await repository.keepOccurrence(
          revealId: revealD, wisdomText: 'D', revealedAt: now, isKeeper: true);

      expect(result.limitReached, isFalse);
      expect(result.items, hasLength(4));
    });

    test('19. migrated over-limit records remain visible', () async {
      store.envelope = KeptStateEnvelope(
        activeRecords: [
          buildRecord(id: 'm1', revealId: revealA),
          buildRecord(id: 'm2', revealId: revealB),
          buildRecord(id: 'm3', revealId: revealC),
          buildRecord(id: 'm4', revealId: revealD),
        ],
      );
      final repository = buildRepository();

      final items = await repository.load();

      expect(items, hasLength(4));
    });

    test('20. over-limit free user cannot add another', () async {
      store.envelope = KeptStateEnvelope(
        activeRecords: [
          buildRecord(id: 'm1', revealId: revealA),
          buildRecord(id: 'm2', revealId: revealB),
          buildRecord(id: 'm3', revealId: revealC),
          buildRecord(id: 'm4', revealId: revealD),
        ],
      );
      final repository = buildRepository();
      const revealE = '55555555-5555-4555-8555-555555555555';

      final result = await repository.keepOccurrence(
        revealId: revealE,
        wisdomText: 'E',
        revealedAt: now,
        isKeeper: false,
      );

      expect(result.limitReached, isTrue);
      expect(result.items, hasLength(4));
    });

    test('21. deleting below limit permits a later addition', () async {
      final repository = buildRepository();
      await repository.keepOccurrence(
          revealId: revealA, wisdomText: 'A', revealedAt: now, isKeeper: false);
      await repository.keepOccurrence(
          revealId: revealB, wisdomText: 'B', revealedAt: now, isKeeper: false);
      final third = await repository.keepOccurrence(
          revealId: revealC, wisdomText: 'C', revealedAt: now, isKeeper: false);
      final idOfFirst = third.items.first.id;

      await repository.remove(itemId: idOfFirst);
      final result = await repository.keepOccurrence(
          revealId: revealD, wisdomText: 'D', revealedAt: now, isKeeper: false);

      expect(result.limitReached, isFalse);
      expect(result.items, hasLength(3));
    });

    test('22. concurrent free saves cannot exceed 3', () async {
      final repository = buildRepository();
      const revealE = '55555555-5555-4555-8555-555555555555';

      final results = await Future.wait([
        repository.keepOccurrence(
            revealId: revealA,
            wisdomText: 'A',
            revealedAt: now,
            isKeeper: false),
        repository.keepOccurrence(
            revealId: revealB,
            wisdomText: 'B',
            revealedAt: now,
            isKeeper: false),
        repository.keepOccurrence(
            revealId: revealC,
            wisdomText: 'C',
            revealedAt: now,
            isKeeper: false),
        repository.keepOccurrence(
            revealId: revealD,
            wisdomText: 'D',
            revealedAt: now,
            isKeeper: false),
        repository.keepOccurrence(
            revealId: revealE,
            wisdomText: 'E',
            revealedAt: now,
            isKeeper: false),
      ]);

      final finalItems = await repository.load();
      expect(finalItems, hasLength(3));
      expect(results.where((r) => r.limitReached).length, 2);
    });

    test('23. concurrent Keeper saves lose no valid write', () async {
      final repository = buildRepository();
      const revealE = '55555555-5555-4555-8555-555555555555';

      await Future.wait([
        repository.keepOccurrence(
            revealId: revealA,
            wisdomText: 'A',
            revealedAt: now,
            isKeeper: true),
        repository.keepOccurrence(
            revealId: revealB,
            wisdomText: 'B',
            revealedAt: now,
            isKeeper: true),
        repository.keepOccurrence(
            revealId: revealC,
            wisdomText: 'C',
            revealedAt: now,
            isKeeper: true),
        repository.keepOccurrence(
            revealId: revealD,
            wisdomText: 'D',
            revealedAt: now,
            isKeeper: true),
        repository.keepOccurrence(
            revealId: revealE,
            wisdomText: 'E',
            revealedAt: now,
            isKeeper: true),
      ]);

      final finalItems = await repository.load();
      expect(finalItems, hasLength(5));
      expect(
        finalItems.map((item) => item.revealId).toSet(),
        {revealA, revealB, revealC, revealD, revealE},
      );
    });
  });

  group('Atomicity/order', () {
    test('24. concurrent distinct saves lose no update', () async {
      final repository = buildRepository();
      await repository.keepOccurrence(
          revealId: revealA, wisdomText: 'A', revealedAt: now, isKeeper: true);
      final afterFirst = await repository.load();
      final itemId = afterFirst.single.id;

      await Future.wait([
        repository.saveReflection(
          itemId: itemId,
          reflection: 'Reflection one',
          isKeeper: true,
        ),
        repository.keepOccurrence(
            revealId: revealB,
            wisdomText: 'B',
            revealedAt: now,
            isKeeper: true),
      ]);

      final finalItems = await repository.load();
      expect(finalItems, hasLength(2));
      expect(
        finalItems.firstWhere((item) => item.id == itemId).reflection,
        'Reflection one',
      );
    });

    test('25. insertion order is preserved', () async {
      final repository = buildRepository();
      await repository.keepOccurrence(
          revealId: revealA, wisdomText: 'A', revealedAt: now, isKeeper: true);
      await repository.keepOccurrence(
          revealId: revealB, wisdomText: 'B', revealedAt: now, isKeeper: true);
      final result = await repository.keepOccurrence(
          revealId: revealC, wisdomText: 'C', revealedAt: now, isKeeper: true);

      expect(result.items.map((i) => i.text).toList(), ['A', 'B', 'C']);
    });

    test('26. new records append', () async {
      store.envelope = KeptStateEnvelope(
        activeRecords: [buildRecord(id: 'm1', revealId: revealA)],
      );
      final repository = buildRepository();

      final result = await repository.keepOccurrence(
          revealId: revealB, wisdomText: 'B', revealedAt: now, isKeeper: true);

      expect(result.items.last.revealId, revealB);
      expect(result.items.first.id, 'm1');
    });

    test('27. restart/read-back returns identical active records', () async {
      final repository = buildRepository();
      await repository.keepOccurrence(
          revealId: revealA, wisdomText: 'A', revealedAt: now, isKeeper: true);

      final restarted = buildRepository();
      final items = await restarted.load();

      expect(items, hasLength(1));
      expect(items.single.revealId, revealA);
    });

    test('28. no-op does not rewrite the store', () async {
      final repository = buildRepository();
      await repository.keepOccurrence(
          revealId: revealA, wisdomText: 'A', revealedAt: now, isKeeper: true);
      final callsAfterFirst = store.replaceCallCount;

      await repository.keepOccurrence(
          revealId: revealA, wisdomText: 'A', revealedAt: now, isKeeper: true);

      expect(store.replaceCallCount, callsAfterFirst);
    });
  });

  group('Reflection', () {
    test('29. add reflection', () async {
      final repository = buildRepository();
      final kept = await repository.keepOccurrence(
          revealId: revealA, wisdomText: 'A', revealedAt: now, isKeeper: true);
      final id = kept.items.single.id;

      final result = await repository.saveReflection(
        itemId: id,
        reflection: 'A quiet morning.',
        isKeeper: true,
      );

      expect(result.items.single.reflection, 'A quiet morning.');
      expect(result.items.single.reflectedAt, isNotNull);
    });

    test('30. edit reflection', () async {
      final repository = buildRepository();
      final kept = await repository.keepOccurrence(
          revealId: revealA, wisdomText: 'A', revealedAt: now, isKeeper: true);
      final id = kept.items.single.id;
      await repository.saveReflection(
          itemId: id, reflection: 'Old.', isKeeper: true);

      final result = await repository.saveReflection(
        itemId: id,
        reflection: 'New.',
        isKeeper: true,
      );

      expect(result.items.single.reflection, 'New.');
    });

    test('31. same reflection no-op does not refresh mutationId', () async {
      final repository = buildRepository();
      final kept = await repository.keepOccurrence(
          revealId: revealA, wisdomText: 'A', revealedAt: now, isKeeper: true);
      final id = kept.items.single.id;
      await repository.saveReflection(
          itemId: id, reflection: 'Same.', isKeeper: true);
      final mutationIdAfterFirst =
          store.envelope!.activeRecords.single.mutationId;

      await repository.saveReflection(
          itemId: id, reflection: 'Same.', isKeeper: true);

      expect(
        store.envelope!.activeRecords.single.mutationId,
        mutationIdAfterFirst,
      );
    });

    test('32. reflection add refreshes mutationId', () async {
      final repository = buildRepository();
      final kept = await repository.keepOccurrence(
          revealId: revealA, wisdomText: 'A', revealedAt: now, isKeeper: true);
      final id = kept.items.single.id;
      final mutationIdBeforeReflection =
          store.envelope!.activeRecords.single.mutationId;

      await repository.saveReflection(
          itemId: id, reflection: 'New reflection.', isKeeper: true);

      expect(
        store.envelope!.activeRecords.single.mutationId,
        isNot(mutationIdBeforeReflection),
      );
    });

    test('33. reflection edit refreshes mutationId', () async {
      final repository = buildRepository();
      final kept = await repository.keepOccurrence(
          revealId: revealA, wisdomText: 'A', revealedAt: now, isKeeper: true);
      final id = kept.items.single.id;
      await repository.saveReflection(
          itemId: id, reflection: 'Old.', isKeeper: true);
      final mutationIdAfterFirst =
          store.envelope!.activeRecords.single.mutationId;

      await repository.saveReflection(
          itemId: id, reflection: 'New.', isKeeper: true);

      expect(
        store.envelope!.activeRecords.single.mutationId,
        isNot(mutationIdAfterFirst),
      );
    });

    test('34. reflection delete refreshes mutationId', () async {
      final repository = buildRepository();
      final kept = await repository.keepOccurrence(
          revealId: revealA, wisdomText: 'A', revealedAt: now, isKeeper: true);
      final id = kept.items.single.id;
      await repository.saveReflection(
          itemId: id, reflection: 'To be deleted.', isKeeper: true);
      final mutationIdAfterReflection =
          store.envelope!.activeRecords.single.mutationId;

      await repository.deleteReflection(itemId: id);

      expect(
        store.envelope!.activeRecords.single.mutationId,
        isNot(mutationIdAfterReflection),
      );
    });

    test('35. delete when absent is a no-op', () async {
      final repository = buildRepository();
      final kept = await repository.keepOccurrence(
          revealId: revealA, wisdomText: 'A', revealedAt: now, isKeeper: true);
      final id = kept.items.single.id;
      final callsBefore = store.replaceCallCount;

      final result = await repository.deleteReflection(itemId: id);

      expect(result.single.reflection, isNull);
      expect(store.replaceCallCount, callsBefore);
    });

    test('36. free reflection limit is 3', () async {
      final repository = buildRepository();
      final a = (await repository.keepOccurrence(
              revealId: revealA,
              wisdomText: 'A',
              revealedAt: now,
              isKeeper: false))
          .items
          .first;
      final b = await repository.keepOccurrence(
          revealId: revealB, wisdomText: 'B', revealedAt: now, isKeeper: false);
      final c = await repository.keepOccurrence(
          revealId: revealC, wisdomText: 'C', revealedAt: now, isKeeper: false);

      await repository.saveReflection(
          itemId: a.id, reflection: 'R1', isKeeper: false);
      await repository.saveReflection(
          itemId: b.items[1].id, reflection: 'R2', isKeeper: false);
      final result = await repository.saveReflection(
          itemId: c.items[2].id, reflection: 'R3', isKeeper: false);

      expect(result.reflectionLimitReached, isFalse);
      expect(
        result.items.where((item) => item.hasReflection).length,
        3,
      );
    });

    test('37. editing an existing reflection remains allowed over limit',
        () async {
      final repository = buildRepository();
      final a = (await repository.keepOccurrence(
              revealId: revealA,
              wisdomText: 'A',
              revealedAt: now,
              isKeeper: false))
          .items
          .first;
      final b = await repository.keepOccurrence(
          revealId: revealB, wisdomText: 'B', revealedAt: now, isKeeper: false);
      final c = await repository.keepOccurrence(
          revealId: revealC, wisdomText: 'C', revealedAt: now, isKeeper: false);
      await repository.saveReflection(
          itemId: a.id, reflection: 'R1', isKeeper: false);
      await repository.saveReflection(
          itemId: b.items[1].id, reflection: 'R2', isKeeper: false);
      await repository.saveReflection(
          itemId: c.items[2].id, reflection: 'R3', isKeeper: false);

      final result = await repository.saveReflection(
        itemId: a.id,
        reflection: 'R1 edited',
        isKeeper: false,
      );

      expect(result.reflectionLimitReached, isFalse);
      expect(
        result.items.firstWhere((item) => item.id == a.id).reflection,
        'R1 edited',
      );
    });

    test('38. Keeper reflections are unlimited', () async {
      final repository = buildRepository();
      final ids = <String>[];
      for (final reveal in [revealA, revealB, revealC, revealD]) {
        final kept = await repository.keepOccurrence(
          revealId: reveal,
          wisdomText: reveal,
          revealedAt: now,
          isKeeper: true,
        );
        ids.add(kept.items.last.id);
      }

      for (final id in ids) {
        await repository.saveReflection(
          itemId: id,
          reflection: 'Reflection for $id',
          isKeeper: true,
        );
      }

      final items = await repository.load();
      expect(items.where((item) => item.hasReflection).length, 4);
    });

    test('39. deleting a reflection restores a free slot', () async {
      final repository = buildRepository();
      final a = (await repository.keepOccurrence(
              revealId: revealA,
              wisdomText: 'A',
              revealedAt: now,
              isKeeper: false))
          .items
          .first;
      final b = await repository.keepOccurrence(
          revealId: revealB, wisdomText: 'B', revealedAt: now, isKeeper: false);
      final c = await repository.keepOccurrence(
          revealId: revealC, wisdomText: 'C', revealedAt: now, isKeeper: false);
      await repository.saveReflection(
          itemId: a.id, reflection: 'R1', isKeeper: false);
      await repository.saveReflection(
          itemId: b.items[1].id, reflection: 'R2', isKeeper: false);
      await repository.saveReflection(
          itemId: c.items[2].id, reflection: 'R3', isKeeper: false);

      await repository.deleteReflection(itemId: a.id);
      final result = await repository.saveReflection(
        itemId: a.id,
        reflection: 'R1 again',
        isKeeper: false,
      );

      expect(result.reflectionLimitReached, isFalse);
    });

    test('40. missing item fails safely', () async {
      final repository = buildRepository();

      await expectLater(
        repository.saveReflection(
          itemId: 'does-not-exist',
          reflection: 'x',
          isKeeper: true,
        ),
        throwsA(isA<KeptRepositoryException>()),
      );

      await expectLater(
        repository.deleteReflection(itemId: 'does-not-exist'),
        throwsA(isA<KeptRepositoryException>()),
      );
    });

    test('41. reflection length validation remains exact', () async {
      final repository = buildRepository();
      final kept = await repository.keepOccurrence(
          revealId: revealA, wisdomText: 'A', revealedAt: now, isKeeper: true);
      final id = kept.items.single.id;

      await expectLater(
        repository.saveReflection(itemId: id, reflection: '', isKeeper: true),
        throwsA(isA<KeptRepositoryException>()),
      );

      final maxLength = 'x' * KeptRecord.maximumReflectionLength;
      final atLimit = await repository.saveReflection(
        itemId: id,
        reflection: maxLength,
        isKeeper: true,
      );
      expect(atLimit.items.single.reflection, maxLength);

      final overLimit = 'x' * (KeptRecord.maximumReflectionLength + 1);
      await expectLater(
        repository.saveReflection(
          itemId: id,
          reflection: overLimit,
          isKeeper: true,
        ),
        throwsA(isA<KeptRepositoryException>()),
      );

      final emojiAtLimit = List.filled(
        KeptRecord.maximumReflectionLength,
        '👨‍👩‍👧‍👦',
      ).join();
      final emojiResult = await repository.saveReflection(
        itemId: id,
        reflection: emojiAtLimit,
        isKeeper: true,
      );
      expect(emojiResult.items.single.reflection, emojiAtLimit);

      final emojiOverLimit = List.filled(
        KeptRecord.maximumReflectionLength + 1,
        '👨‍👩‍👧‍👦',
      ).join();
      await expectLater(
        repository.saveReflection(
          itemId: id,
          reflection: emojiOverLimit,
          isKeeper: true,
        ),
        throwsA(isA<KeptRepositoryException>()),
      );
    });
  });

  group('Remove/restore', () {
    test('42. remove deletes only the targeted id', () async {
      final repository = buildRepository();
      await repository.keepOccurrence(
          revealId: revealA, wisdomText: 'A', revealedAt: now, isKeeper: true);
      final b = await repository.keepOccurrence(
          revealId: revealB, wisdomText: 'B', revealedAt: now, isKeeper: true);
      final targetId = b.items.first.id;

      final removed = await repository.remove(itemId: targetId);

      expect(removed, isNotNull);
      expect(removed!.items, hasLength(1));
      expect(removed.items.single.revealId, revealB);
    });

    test('43. remove returns original index and full protected record',
        () async {
      final repository = buildRepository();
      await repository.keepOccurrence(
          revealId: revealA, wisdomText: 'A', revealedAt: now, isKeeper: true);
      final kept = await repository.keepOccurrence(
          revealId: revealB, wisdomText: 'B', revealedAt: now, isKeeper: true);
      final targetId = kept.items.first.id;

      final removed = await repository.remove(itemId: targetId);

      expect(removed!.originalIndex, 0);
      expect(removed.record.id, targetId);
      expect(removed.record.revealId, revealA);
    });

    test('44. remove absent returns null', () async {
      final repository = buildRepository();

      final removed = await repository.remove(itemId: 'does-not-exist');

      expect(removed, isNull);
    });

    test('45. restore returns to original index', () async {
      final repository = buildRepository();
      final first = await repository.keepOccurrence(
          revealId: revealA, wisdomText: 'A', revealedAt: now, isKeeper: true);
      await repository.keepOccurrence(
          revealId: revealB, wisdomText: 'B', revealedAt: now, isKeeper: true);
      final firstId = first.items.first.id;
      final removed = await repository.remove(itemId: firstId);

      final restored = await repository.restore(removed!);

      expect(restored.first.id, firstId);
      expect(restored.map((i) => i.revealId).toList(), [revealA, revealB]);
    });

    test('46. restore preserves id/revealId/content timestamps', () async {
      final repository = buildRepository();
      final kept = await repository.keepOccurrence(
          revealId: revealA, wisdomText: 'A', revealedAt: now, isKeeper: true);
      final id = kept.items.single.id;
      final removed = await repository.remove(itemId: id);
      final originalRecord = removed!.record;

      now = now.add(const Duration(hours: 1));
      await repository.restore(removed);

      final restoredRecord = store.envelope!.activeRecords.single;
      expect(restoredRecord.id, originalRecord.id);
      expect(restoredRecord.revealId, originalRecord.revealId);
      expect(restoredRecord.wisdomText, originalRecord.wisdomText);
      expect(restoredRecord.revealedAt, originalRecord.revealedAt);
      expect(restoredRecord.keptAt, originalRecord.keptAt);
    });

    test('47. restore creates fresh mutationId/updatedAt', () async {
      final repository = buildRepository();
      final kept = await repository.keepOccurrence(
          revealId: revealA, wisdomText: 'A', revealedAt: now, isKeeper: true);
      final id = kept.items.single.id;
      final removed = await repository.remove(itemId: id);
      final originalMutationId = removed!.record.mutationId;

      now = now.add(const Duration(hours: 1));
      await repository.restore(removed);

      final restoredRecord = store.envelope!.activeRecords.single;
      expect(restoredRecord.mutationId, isNot(originalMutationId));
      expect(
        restoredRecord.updatedAt.millisecondsSinceEpoch,
        now.millisecondsSinceEpoch,
      );
    });

    test('48. restore duplicate id/revealId is a no-op', () async {
      final repository = buildRepository();
      final kept = await repository.keepOccurrence(
          revealId: revealA, wisdomText: 'A', revealedAt: now, isKeeper: true);
      final id = kept.items.single.id;
      final removed = await repository.remove(itemId: id);

      // Re-add a fresh occurrence for the same revealId before restoring.
      await repository.keepOccurrence(
          revealId: revealA, wisdomText: 'A', revealedAt: now, isKeeper: true);
      final callsBeforeRestore = store.replaceCallCount;

      final result = await repository.restore(removed!);

      expect(result, hasLength(1));
      expect(store.replaceCallCount, callsBeforeRestore);
    });

    test('49. restore does not apply free limit', () async {
      final repository = buildRepository();
      final a = await repository.keepOccurrence(
          revealId: revealA, wisdomText: 'A', revealedAt: now, isKeeper: false);
      await repository.keepOccurrence(
          revealId: revealB, wisdomText: 'B', revealedAt: now, isKeeper: false);
      await repository.keepOccurrence(
          revealId: revealC, wisdomText: 'C', revealedAt: now, isKeeper: false);
      final removed = await repository.remove(itemId: a.items.first.id);
      // Re-fill the free slot so we are back at the limit.
      await repository.keepOccurrence(
          revealId: revealD, wisdomText: 'D', revealedAt: now, isKeeper: false);

      final restored = await repository.restore(removed!);

      // Restore is not gated by the free limit: it succeeds and adds a
      // fourth active record even though a free user is already at the
      // limit -- this is an undo, not a new keep.
      expect(restored, hasLength(4));
    });
  });

  group('Mapping', () {
    test('50. KeptRecord maps to FavoriteItem id/text/revealId', () async {
      store.envelope = KeptStateEnvelope(
        activeRecords: [
          buildRecord(id: 'm1', revealId: revealA, wisdomText: 'Mapped text.')
        ],
      );
      final repository = buildRepository();

      final items = await repository.load();

      expect(items.single.id, 'm1');
      expect(items.single.text, 'Mapped text.');
      expect(items.single.revealId, revealA);
    });

    test('51. keptAt maps through formatFavoriteDisplayDate(toLocal())',
        () async {
      final keptAtUtc = DateTime.utc(2026, 8, 1, 9, 0);
      store.envelope = KeptStateEnvelope(
        activeRecords: [
          buildRecord(id: 'm1', revealId: revealA, keptAt: keptAtUtc),
        ],
      );
      final repository = buildRepository();

      final items = await repository.load();

      expect(
        items.single.date,
        formatFavoriteDisplayDate(keptAtUtc.toLocal()),
      );
    });

    test('52. reflection and reflectedAt map correctly', () async {
      final reflectedAt = DateTime.utc(2026, 8, 1, 10, 0);
      store.envelope = KeptStateEnvelope(
        activeRecords: [
          buildRecord(
            id: 'm1',
            revealId: revealA,
            reflectionText: 'A reflection.',
            reflectedAt: reflectedAt,
            updatedAt: reflectedAt,
          ),
        ],
      );
      final repository = buildRepository();

      final items = await repository.load();

      expect(items.single.reflection, 'A reflection.');
      expect(items.single.reflectedAt, reflectedAt.toIso8601String());
    });

    test('53. record order is unchanged', () async {
      store.envelope = KeptStateEnvelope(
        activeRecords: [
          buildRecord(id: 'm1', revealId: revealA),
          buildRecord(id: 'm2', revealId: revealB),
          buildRecord(id: 'm3', revealId: revealC),
        ],
      );
      final repository = buildRepository();

      final items = await repository.load();

      expect(items.map((i) => i.id).toList(), ['m1', 'm2', 'm3']);
    });

    test('54. mutationId is never exposed through FavoriteItem', () async {
      final repository = buildRepository();

      final result = await repository.keepOccurrence(
        revealId: revealA,
        wisdomText: 'A',
        revealedAt: now,
        isKeeper: true,
      );

      // FavoriteItem has no mutationId field at all -- this is a static
      // compile-time guarantee, exercised here for documentation: the
      // mapped item exposes only id/text/date/reflection/reflectedAt/
      // revealId.
      final item = result.items.single;
      expect(item.id, isNotEmpty);
      expect(item.revealId, revealA);
    });
  });

  group(
      'Phase 3D-D addendum: normal-runtime timestamps are canonicalized '
      'before reaching a protected write', () {
    // Every group above this one uses _FakeKeptStateStore, which stores the
    // KeptStateEnvelope *object* directly on replace() -- it never actually
    // serializes to JSON, so it can never reproduce a defect that only
    // manifests through genuine encode/decode (KeptRecord.encode() only
    // serializes millisecondsSinceEpoch, while KeptRecord.operator== compares
    // exactly, down to the microsecond). JsonRoundTrippingKeptStateStore
    // (persistence_test_helpers.dart) round-trips every replace() through
    // real JSON, exactly mirroring ProtectedFileKeptStateStore's own
    // mandatory post-write verification -- this is what actually proves the
    // fix.
    late JsonRoundTrippingKeptStateStore roundTrippingStore;

    // A clock shaped like a real device's DateTime.now(): non-zero
    // milliseconds *and* microseconds, exactly like the recovered Build 25
    // payload's ".484133" reflectedAt that originally exposed this defect.
    final microsecondClock = DateTime.utc(2026, 8, 1, 9, 0, 0, 484, 133);
    final canonicalClockInstant = DateTime.utc(2026, 8, 1, 9, 0, 0, 484);

    setUp(() {
      roundTrippingStore = JsonRoundTrippingKeptStateStore();
    });

    KeptRepository buildRoundTrippingRepository({
      KeptClock? clock,
      KeptIdFactory? idFactory,
      int freeKeptLimit = 3,
      int freeReflectionLimit = 3,
    }) {
      return KeptRepository(
        store: roundTrippingStore,
        bootstrap: const KeptBootstrapResult.ready(),
        operationCoordinator: PersistenceOperationCoordinator(),
        idFactory: idFactory ?? (_SequentialIdFactory()).call,
        clock: clock ?? (() => microsecondClock),
        freeKeptLimit: freeKeptLimit,
        freeReflectionLimit: freeReflectionLimit,
      );
    }

    test(
        '1/2/3. keepOccurrence succeeds with a microsecond-bearing clock and '
        'a microsecond-bearing supplied revealedAt, storing both truncated '
        'to the same canonical millisecond instant, and the envelope '
        'survives encode/decode equality verification', () async {
      final repository = buildRoundTrippingRepository();
      final suppliedRevealedAt = DateTime.utc(2026, 7, 31, 20, 0, 0, 250, 750);

      final result = await repository.keepOccurrence(
        revealId: revealA,
        wisdomText: 'A wisdom kept on a real device.',
        revealedAt: suppliedRevealedAt,
        isKeeper: false,
      );

      expect(result.limitReached, isFalse);
      expect(result.items, hasLength(1));

      // A fresh, independent load() (simulating a later read) proves the
      // write actually persisted through real JSON encode/decode, not
      // merely that an in-memory reference survived.
      final reloaded = await roundTrippingStore.load();
      expect(reloaded, isNotNull);
      final record = reloaded!.activeRecords.single;
      expect(record.keptAt, canonicalClockInstant);
      expect(
        record.revealedAt,
        DateTime.utc(2026, 7, 31, 20, 0, 0, 250),
      );
      expect(record.updatedAt, canonicalClockInstant);
    });

    test(
        '4. saveReflection succeeds when reflectedAt has non-zero '
        'microseconds', () async {
      final repository = buildRoundTrippingRepository();
      await repository.keepOccurrence(
        revealId: revealA,
        wisdomText: 'Be still.',
        revealedAt: microsecondClock,
        isKeeper: false,
      );
      final keptId = (await roundTrippingStore.load())!.activeRecords.single.id;

      final result = await repository.saveReflection(
        itemId: keptId,
        reflection: 'A reflection with a real clock.',
        isKeeper: false,
        reflectedAt: DateTime.utc(2026, 8, 1, 10, 0, 0, 999, 999),
      );

      expect(result.limitReached, isFalse);
      final record = (await roundTrippingStore.load())!.activeRecords.single;
      expect(record.reflectionText, 'A reflection with a real clock.');
      expect(record.reflectedAt, DateTime.utc(2026, 8, 1, 10, 0, 0, 999));
      expect(record.updatedAt, record.reflectedAt);
    });

    test(
        '5. deleteReflection succeeds with a microsecond-bearing mutation '
        'clock', () async {
      final repository = buildRoundTrippingRepository(
        clock: () => microsecondClock,
      );
      await repository.keepOccurrence(
        revealId: revealA,
        wisdomText: 'Be still.',
        revealedAt: microsecondClock,
        isKeeper: false,
      );
      final keptId = (await roundTrippingStore.load())!.activeRecords.single.id;
      await repository.saveReflection(
        itemId: keptId,
        reflection: 'Temporary.',
        isKeeper: false,
      );

      final items = await repository.deleteReflection(itemId: keptId);

      expect(items.single.reflection, isNull);
      final record = (await roundTrippingStore.load())!.activeRecords.single;
      expect(record.reflectionText, isNull);
      expect(record.updatedAt, canonicalClockInstant);
    });

    test(
        '6. remove and restore succeed with a microsecond-bearing clock and '
        'preserve the exact removed record payload/order', () async {
      final repository = buildRoundTrippingRepository(
        clock: () => microsecondClock,
      );
      await repository.keepOccurrence(
        revealId: revealA,
        wisdomText: 'First.',
        revealedAt: microsecondClock,
        isKeeper: false,
      );
      await repository.keepOccurrence(
        revealId: revealB,
        wisdomText: 'Second.',
        revealedAt: microsecondClock,
        isKeeper: false,
      );
      final idB = (await roundTrippingStore.load())!.activeRecords[1].id;

      final removed = await repository.remove(itemId: idB);
      expect(removed, isNotNull);
      expect(removed!.items, hasLength(1));
      expect(
        (await roundTrippingStore.load())!.activeRecords,
        hasLength(1),
      );

      final restored = await repository.restore(removed);

      expect(restored, hasLength(2));
      expect(restored[1].id, idB);
      final reloaded = (await roundTrippingStore.load())!.activeRecords;
      expect(reloaded, hasLength(2));
      expect(reloaded[1].wisdomText, 'Second.');
      expect(reloaded[1].revealId, revealB);
      expect(reloaded[1].updatedAt, canonicalClockInstant);
    });

    test(
        '7. repeated same revealId remains idempotent after '
        'canonicalization', () async {
      final repository = buildRoundTrippingRepository();

      await repository.keepOccurrence(
        revealId: revealA,
        wisdomText: 'Be still.',
        revealedAt: microsecondClock,
        isKeeper: false,
      );
      final result = await repository.keepOccurrence(
        revealId: revealA,
        wisdomText: 'Be still.',
        revealedAt: microsecondClock,
        isKeeper: false,
      );

      expect(result.items, hasLength(1));
      expect(roundTrippingStore.replaceCallCount, 1);
    });

    test(
        '8. same wisdom text with different revealIds remains two distinct '
        'records', () async {
      final repository = buildRoundTrippingRepository();

      await repository.keepOccurrence(
        revealId: revealA,
        wisdomText: 'Identical text.',
        revealedAt: microsecondClock,
        isKeeper: false,
      );
      await repository.keepOccurrence(
        revealId: revealB,
        wisdomText: 'Identical text.',
        revealedAt: microsecondClock,
        isKeeper: false,
      );

      final records = (await roundTrippingStore.load())!.activeRecords;
      expect(records, hasLength(2));
      expect(records.map((r) => r.revealId).toSet(), {revealA, revealB});
    });

    test('9. free 3/3 limits remain unchanged', () async {
      final repository = buildRoundTrippingRepository(freeKeptLimit: 3);
      for (final reveal in [revealA, revealB, revealC]) {
        await repository.keepOccurrence(
          revealId: reveal,
          wisdomText: 'Text for $reveal.',
          revealedAt: microsecondClock,
          isKeeper: false,
        );
      }

      final blocked = await repository.keepOccurrence(
        revealId: revealD,
        wisdomText: 'A fourth wisdom.',
        revealedAt: microsecondClock,
        isKeeper: false,
      );

      expect(blocked.limitReached, isTrue);
      expect(
        (await roundTrippingStore.load())!.activeRecords,
        hasLength(3),
      );
    });

    test('10. Keeper unlimited behavior remains unchanged', () async {
      final repository = buildRoundTrippingRepository(freeKeptLimit: 3);
      for (final reveal in [revealA, revealB, revealC]) {
        await repository.keepOccurrence(
          revealId: reveal,
          wisdomText: 'Text for $reveal.',
          revealedAt: microsecondClock,
          isKeeper: true,
        );
      }

      final fourth = await repository.keepOccurrence(
        revealId: revealD,
        wisdomText: 'A fourth wisdom, unlimited for Keeper.',
        revealedAt: microsecondClock,
        isKeeper: true,
      );

      expect(fourth.limitReached, isFalse);
      expect(
        (await roundTrippingStore.load())!.activeRecords,
        hasLength(4),
      );
    });
  });

  group(
      'Phase 3D-E (safety-gap correction, round 3 -- direction inversion): '
      'resolveLegacyMigratedRevealIdForOccurrence', () {
    // Deliberately before the outer `now` (2026-08-01T09:00Z, this file's
    // fixed repository clock) -- this group never mutates the store, so,
    // unlike the old mutation-based design, nothing here actually depends on
    // `now`/`updatedAt` any more. Kept anyway for continuity with the
    // fixture ids/windows the previous round already established.
    final committedRevealedAt = DateTime.utc(2026, 7, 30, 9, 0);
    final committedUnlockAt =
        committedRevealedAt.add(const Duration(hours: 24));

    /// Builds a Build 25 `sr-v1-<microseconds>-<serial>` legacy id whose
    /// embedded save instant is exactly [savedAt] — the only id shape
    /// [parseLegacySavedReflectionId] recognizes as carrying a genuine,
    /// timezone-independent instant. See `legacy_kept_identity.dart` for the
    /// exact real Build 25 `SavedReflectionsService._createId()` source
    /// this mirrors.
    String srV1Id(DateTime savedAt, {int serial = 0}) =>
        'sr-v1-${savedAt.microsecondsSinceEpoch}-$serial';

    test(
        '55. exactly one text+window, migration-provenanced candidate '
        'resolves to its own already-existing revealId', () async {
      final legacyId =
          srV1Id(committedRevealedAt.add(const Duration(hours: 2)));
      final migrated = buildRecord(
        id: legacyId,
        revealId: deriveLegacyMigrationRevealId(legacyId),
        wisdomText: 'Some doors open after surrender.',
        keptAt: DateTime.utc(2026, 7, 30, 1, 13, 7, 484),
        reflectionText: 'A reflection worth keeping.',
        reflectedAt: DateTime.utc(2026, 7, 30, 1, 13, 7, 484),
      );
      store.envelope = KeptStateEnvelope(activeRecords: [migrated]);
      final repository = buildRepository();

      final resolved =
          await repository.resolveLegacyMigratedRevealIdForOccurrence(
        wisdomText: 'Some doors open after surrender.',
        committedRevealedAt: committedRevealedAt,
        committedUnlockAt: committedUnlockAt,
      );

      expect(resolved, migrated.revealId);
      // Read-only: never touches the store.
      expect(store.replaceCallCount, 0);
      expect(store.envelope!.activeRecords.single, migrated);
    });

    test('56. zero matching candidates (different text) resolves to null',
        () async {
      final legacyId = srV1Id(committedRevealedAt);
      final unrelated = buildRecord(
        id: legacyId,
        revealId: deriveLegacyMigrationRevealId(legacyId),
        wisdomText: 'A completely different wisdom.',
        keptAt: committedRevealedAt,
      );
      store.envelope = KeptStateEnvelope(activeRecords: [unrelated]);
      final repository = buildRepository();

      final resolved =
          await repository.resolveLegacyMigratedRevealIdForOccurrence(
        wisdomText: 'Some doors open after surrender.',
        committedRevealedAt: committedRevealedAt,
        committedUnlockAt: committedUnlockAt,
      );

      expect(resolved, isNull);
      expect(store.replaceCallCount, 0);
    });

    test(
        '57. two ambiguous migration-provenanced candidates, both with a '
        'save instant inside the window, resolve to null -- ambiguity is '
        'never guessed at', () async {
      final idOne = srV1Id(committedRevealedAt.add(const Duration(hours: 1)));
      final idTwo = srV1Id(committedRevealedAt.add(const Duration(hours: 2)));
      final candidateOne = buildRecord(
        id: idOne,
        revealId: deriveLegacyMigrationRevealId(idOne),
        wisdomText: 'Some doors open after surrender.',
        keptAt: committedRevealedAt,
      );
      final candidateTwo = buildRecord(
        id: idTwo,
        revealId: deriveLegacyMigrationRevealId(idTwo),
        wisdomText: 'Some doors open after surrender.',
        keptAt: committedRevealedAt.add(const Duration(hours: 2)),
      );
      store.envelope =
          KeptStateEnvelope(activeRecords: [candidateOne, candidateTwo]);
      final repository = buildRepository();

      final resolved =
          await repository.resolveLegacyMigratedRevealIdForOccurrence(
        wisdomText: 'Some doors open after surrender.',
        committedRevealedAt: committedRevealedAt,
        committedUnlockAt: committedUnlockAt,
      );

      expect(resolved, isNull);
      expect(store.replaceCallCount, 0);
      expect(store.envelope!.activeRecords[0], candidateOne);
      expect(store.envelope!.activeRecords[1], candidateTwo);
    });

    test(
        '58. a duplicate wisdom text whose legacy save instant is *before* '
        'the committed window resolves to null', () async {
      final legacyId =
          srV1Id(committedRevealedAt.subtract(const Duration(minutes: 1)));
      final olderOccurrence = buildRecord(
        id: legacyId,
        revealId: deriveLegacyMigrationRevealId(legacyId),
        wisdomText: 'Some doors open after surrender.',
        keptAt: committedRevealedAt.subtract(const Duration(days: 3)),
      );
      store.envelope = KeptStateEnvelope(activeRecords: [olderOccurrence]);
      final repository = buildRepository();

      final resolved =
          await repository.resolveLegacyMigratedRevealIdForOccurrence(
        wisdomText: 'Some doors open after surrender.',
        committedRevealedAt: committedRevealedAt,
        committedUnlockAt: committedUnlockAt,
      );

      expect(resolved, isNull);
      expect(store.replaceCallCount, 0);
    });

    test(
        '59. a duplicate wisdom text whose legacy save instant is at or '
        'after the committed unlockAt (right-exclusive boundary) resolves '
        'to null', () async {
      final legacyId = srV1Id(committedUnlockAt);
      final laterOccurrence = buildRecord(
        id: legacyId,
        revealId: deriveLegacyMigrationRevealId(legacyId),
        wisdomText: 'Some doors open after surrender.',
        keptAt: committedRevealedAt,
      );
      store.envelope = KeptStateEnvelope(activeRecords: [laterOccurrence]);
      final repository = buildRepository();

      final resolved =
          await repository.resolveLegacyMigratedRevealIdForOccurrence(
        wisdomText: 'Some doors open after surrender.',
        committedRevealedAt: committedRevealedAt,
        committedUnlockAt: committedUnlockAt,
      );

      expect(resolved, isNull);
      expect(store.replaceCallCount, 0);
    });

    test(
        '60. an invalid window (committedUnlockAt not after '
        'committedRevealedAt) is safely rejected, resolving to null', () async {
      final legacyId = srV1Id(committedRevealedAt);
      final migrated = buildRecord(
        id: legacyId,
        revealId: deriveLegacyMigrationRevealId(legacyId),
        wisdomText: 'Some doors open after surrender.',
        keptAt: committedRevealedAt,
      );
      store.envelope = KeptStateEnvelope(activeRecords: [migrated]);
      final repository = buildRepository();

      final resolved =
          await repository.resolveLegacyMigratedRevealIdForOccurrence(
        wisdomText: 'Some doors open after surrender.',
        committedRevealedAt: committedRevealedAt,
        committedUnlockAt: committedRevealedAt,
      );

      expect(resolved, isNull);
      expect(store.replaceCallCount, 0);
    });

    test('61. throws when the bootstrap result is unavailable', () async {
      final repository = buildRepository(
        bootstrap: KeptBootstrapResult.unavailable('snapshot-write'),
      );

      await expectLater(
        repository.resolveLegacyMigratedRevealIdForOccurrence(
          wisdomText: 'Some doors open after surrender.',
          committedRevealedAt: committedRevealedAt,
          committedUnlockAt: committedUnlockAt,
        ),
        throwsA(isA<KeptRepositoryException>()),
      );
    });

    test(
        '62. only the matching record is ever considered; unrelated active '
        "records' identity, content, and position are never touched", () async {
      final before = buildRecord(
        id: 'before-1',
        revealId: '33333333-3333-4333-8333-333333333333',
        wisdomText: 'An unrelated earlier wisdom.',
        keptAt: committedRevealedAt.subtract(const Duration(days: 10)),
      );
      final legacyId = srV1Id(committedRevealedAt);
      final migrated = buildRecord(
        id: legacyId,
        revealId: deriveLegacyMigrationRevealId(legacyId),
        wisdomText: 'Some doors open after surrender.',
        keptAt: committedRevealedAt,
      );
      final after = buildRecord(
        id: 'after-1',
        revealId: '44444444-4444-4444-8444-444444444444',
        wisdomText: 'An unrelated later wisdom.',
        keptAt: committedRevealedAt.add(const Duration(days: 10)),
      );
      final seededEnvelope =
          KeptStateEnvelope(activeRecords: [before, migrated, after]);
      store.envelope = seededEnvelope;
      final repository = buildRepository();

      final resolved =
          await repository.resolveLegacyMigratedRevealIdForOccurrence(
        wisdomText: 'Some doors open after surrender.',
        committedRevealedAt: committedRevealedAt,
        committedUnlockAt: committedUnlockAt,
      );

      expect(resolved, migrated.revealId);
      expect(store.replaceCallCount, 0);
      // Byte-for-byte/value-equal to the seeded envelope -- resolution
      // never wrote anything, to any record.
      expect(store.envelope, seededEnvelope);
      expect(store.envelope!.activeRecords, [before, migrated, after]);
    });

    test(
        '63. calling twice returns the identical result both times, and '
        'never calls store.replace() either time (pure, idempotent, '
        'read-only)', () async {
      final legacyId = srV1Id(committedRevealedAt);
      final migrated = buildRecord(
        id: legacyId,
        revealId: deriveLegacyMigrationRevealId(legacyId),
        wisdomText: 'Some doors open after surrender.',
        keptAt: committedRevealedAt,
      );
      store.envelope = KeptStateEnvelope(activeRecords: [migrated]);
      final repository = buildRepository();

      final first = await repository.resolveLegacyMigratedRevealIdForOccurrence(
        wisdomText: 'Some doors open after surrender.',
        committedRevealedAt: committedRevealedAt,
        committedUnlockAt: committedUnlockAt,
      );
      final second =
          await repository.resolveLegacyMigratedRevealIdForOccurrence(
        wisdomText: 'Some doors open after surrender.',
        committedRevealedAt: committedRevealedAt,
        committedUnlockAt: committedUnlockAt,
      );

      expect(first, migrated.revealId);
      expect(second, first);
      expect(store.replaceCallCount, 0);
      expect(store.envelope!.activeRecords.single, migrated);
    });

    test(
        '64. (Gap 2) a normal, non-migrated Build 26 record with matching '
        "text and a save instant inside the window is never returned as a "
        "candidate -- the provenance gate rejects a match by text/window "
        'alone', () async {
      // A genuine random UUID v4, exactly what `keepOccurrence` always
      // assigns for an ordinary (non-migrated) Kept record -- never the
      // deterministic v5 the migration coordinator mints, and its own `id`
      // is a fresh UUID v4 too, never a parseable `sr-v1-...` id.
      const ordinaryRevealId = '55555555-5555-4555-8555-555555555555';
      final ordinary = buildRecord(
        id: '00000000-0000-4000-8000-0000000000aa',
        revealId: ordinaryRevealId,
        wisdomText: 'Some doors open after surrender.',
        keptAt: committedRevealedAt,
      );
      store.envelope = KeptStateEnvelope(activeRecords: [ordinary]);
      final repository = buildRepository();

      final resolved =
          await repository.resolveLegacyMigratedRevealIdForOccurrence(
        wisdomText: 'Some doors open after surrender.',
        committedRevealedAt: committedRevealedAt,
        committedUnlockAt: committedUnlockAt,
      );

      expect(resolved, isNull);
      expect(store.replaceCallCount, 0);
    });

    test(
        '65. (Gap 2) a tampered/unrelated v5 revealId -- matching text and '
        'window, and even a valid sr-v1 id, but not the deterministic '
        "derivation for *this* record's own id -- is never returned as a "
        'candidate', () async {
      final legacyId = srV1Id(committedRevealedAt);
      // A genuine UUID v5 value (correct version/variant bits), but
      // derived from a *different* legacy id than this record's own --
      // simulating a tampered, corrupted, or otherwise-unrelated v5 value
      // that happens to still look structurally like a migration revealId.
      final unrelatedV5 = deriveLegacyMigrationRevealId('some-other-legacy-id');
      final tampered = buildRecord(
        id: legacyId,
        revealId: unrelatedV5,
        wisdomText: 'Some doors open after surrender.',
        keptAt: committedRevealedAt,
      );
      store.envelope = KeptStateEnvelope(activeRecords: [tampered]);
      final repository = buildRepository();

      final resolved =
          await repository.resolveLegacyMigratedRevealIdForOccurrence(
        wisdomText: 'Some doors open after surrender.',
        committedRevealedAt: committedRevealedAt,
        committedUnlockAt: committedUnlockAt,
      );

      expect(resolved, isNull);
      expect(store.replaceCallCount, 0);
    });

    test(
        '66. a `legacy-v1-<index>-<hash>` id -- carrying no timestamp at '
        'all -- is never returned as a candidate, even when its revealId '
        'already satisfies the provenance gate', () async {
      const legacyV1Id = 'legacy-v1-3-abcd1234';
      final noTimestamp = buildRecord(
        id: legacyV1Id,
        revealId: deriveLegacyMigrationRevealId(legacyV1Id),
        wisdomText: 'Some doors open after surrender.',
        keptAt: committedRevealedAt,
      );
      store.envelope = KeptStateEnvelope(activeRecords: [noTimestamp]);
      final repository = buildRepository();

      final resolved =
          await repository.resolveLegacyMigratedRevealIdForOccurrence(
        wisdomText: 'Some doors open after surrender.',
        committedRevealedAt: committedRevealedAt,
        committedUnlockAt: committedUnlockAt,
      );

      expect(resolved, isNull);
      expect(store.replaceCallCount, 0);
    });

    test(
        '67. a `duplicate-v1-<index>-<hash>` id -- also carrying no '
        'timestamp -- is never returned as a candidate, even when its '
        'revealId already satisfies the provenance gate', () async {
      const duplicateV1Id = 'duplicate-v1-2-deadbeef';
      final noTimestamp = buildRecord(
        id: duplicateV1Id,
        revealId: deriveLegacyMigrationRevealId(duplicateV1Id),
        wisdomText: 'Some doors open after surrender.',
        keptAt: committedRevealedAt,
      );
      store.envelope = KeptStateEnvelope(activeRecords: [noTimestamp]);
      final repository = buildRepository();

      final resolved =
          await repository.resolveLegacyMigratedRevealIdForOccurrence(
        wisdomText: 'Some doors open after surrender.',
        committedRevealedAt: committedRevealedAt,
        committedUnlockAt: committedUnlockAt,
      );

      expect(resolved, isNull);
      expect(store.replaceCallCount, 0);
    });

    test(
        '68. a malformed sr-v1-shaped id with a non-numeric microsecond '
        'component is never returned as a candidate', () async {
      const malformedId = 'sr-v1-not-a-number-0';
      final malformed = buildRecord(
        id: malformedId,
        revealId: deriveLegacyMigrationRevealId(malformedId),
        wisdomText: 'Some doors open after surrender.',
        keptAt: committedRevealedAt,
      );
      store.envelope = KeptStateEnvelope(activeRecords: [malformed]);
      final repository = buildRepository();

      final resolved =
          await repository.resolveLegacyMigratedRevealIdForOccurrence(
        wisdomText: 'Some doors open after surrender.',
        committedRevealedAt: committedRevealedAt,
        committedUnlockAt: committedUnlockAt,
      );

      expect(resolved, isNull);
      expect(store.replaceCallCount, 0);
    });

    test(
        '69. a malformed sr-v1-shaped id missing its serial segment is '
        'never returned as a candidate', () async {
      final malformedId = 'sr-v1-${committedRevealedAt.microsecondsSinceEpoch}';
      final malformed = buildRecord(
        id: malformedId,
        revealId: deriveLegacyMigrationRevealId(malformedId),
        wisdomText: 'Some doors open after surrender.',
        keptAt: committedRevealedAt,
      );
      store.envelope = KeptStateEnvelope(activeRecords: [malformed]);
      final repository = buildRepository();

      final resolved =
          await repository.resolveLegacyMigratedRevealIdForOccurrence(
        wisdomText: 'Some doors open after surrender.',
        committedRevealedAt: committedRevealedAt,
        committedUnlockAt: committedUnlockAt,
      );

      expect(resolved, isNull);
      expect(store.replaceCallCount, 0);
    });

    test(
        '70. a save instant exactly at committedRevealedAt (inclusive left '
        'boundary) resolves to the candidate', () async {
      final legacyId = srV1Id(committedRevealedAt);
      final migrated = buildRecord(
        id: legacyId,
        revealId: deriveLegacyMigrationRevealId(legacyId),
        wisdomText: 'Some doors open after surrender.',
        keptAt: committedRevealedAt,
      );
      store.envelope = KeptStateEnvelope(activeRecords: [migrated]);
      final repository = buildRepository();

      final resolved =
          await repository.resolveLegacyMigratedRevealIdForOccurrence(
        wisdomText: 'Some doors open after surrender.',
        committedRevealedAt: committedRevealedAt,
        committedUnlockAt: committedUnlockAt,
      );

      expect(resolved, migrated.revealId);
      expect(store.replaceCallCount, 0);
    });

    test(
        '71. a save instant exactly at committedUnlockAt (exclusive right '
        'boundary) resolves to null', () async {
      final legacyId = srV1Id(committedUnlockAt);
      final migrated = buildRecord(
        id: legacyId,
        revealId: deriveLegacyMigrationRevealId(legacyId),
        wisdomText: 'Some doors open after surrender.',
        keptAt: committedRevealedAt,
      );
      store.envelope = KeptStateEnvelope(activeRecords: [migrated]);
      final repository = buildRepository();

      final resolved =
          await repository.resolveLegacyMigratedRevealIdForOccurrence(
        wisdomText: 'Some doors open after surrender.',
        committedRevealedAt: committedRevealedAt,
        committedUnlockAt: committedUnlockAt,
      );

      expect(resolved, isNull);
      expect(store.replaceCallCount, 0);
    });

    test(
        '72. a save instant one microsecond before committedUnlockAt '
        'resolves to the candidate (boundary-adjacent proof)', () async {
      final legacyId = srV1Id(
        committedUnlockAt.subtract(const Duration(microseconds: 1)),
      );
      final migrated = buildRecord(
        id: legacyId,
        revealId: deriveLegacyMigrationRevealId(legacyId),
        wisdomText: 'Some doors open after surrender.',
        keptAt: committedRevealedAt,
      );
      store.envelope = KeptStateEnvelope(activeRecords: [migrated]);
      final repository = buildRepository();

      final resolved =
          await repository.resolveLegacyMigratedRevealIdForOccurrence(
        wisdomText: 'Some doors open after surrender.',
        committedRevealedAt: committedRevealedAt,
        committedUnlockAt: committedUnlockAt,
      );

      expect(resolved, migrated.revealId);
      expect(store.replaceCallCount, 0);
    });

    test(
        '73. a save instant strictly before committedRevealedAt resolves '
        'to null', () async {
      final legacyId = srV1Id(
        committedRevealedAt.subtract(const Duration(microseconds: 1)),
      );
      final migrated = buildRecord(
        id: legacyId,
        revealId: deriveLegacyMigrationRevealId(legacyId),
        wisdomText: 'Some doors open after surrender.',
        keptAt: committedRevealedAt,
      );
      store.envelope = KeptStateEnvelope(activeRecords: [migrated]);
      final repository = buildRepository();

      final resolved =
          await repository.resolveLegacyMigratedRevealIdForOccurrence(
        wisdomText: 'Some doors open after surrender.',
        committedRevealedAt: committedRevealedAt,
        committedUnlockAt: committedUnlockAt,
      );

      expect(resolved, isNull);
      expect(store.replaceCallCount, 0);
    });

    test(
        '74. the real physical-device fixture id resolves through its '
        'actual embedded save instant, expressed with the literal micros '
        'value from the reported evidence', () async {
      const physicalLegacyId = 'sr-v1-1785622374122602-0';
      final savedAt = DateTime.fromMicrosecondsSinceEpoch(
        1785622374122602,
        isUtc: true,
      );
      final windowRevealedAt = savedAt.subtract(const Duration(hours: 2));
      final windowUnlockAt = windowRevealedAt.add(const Duration(hours: 24));
      final migrated = buildRecord(
        id: physicalLegacyId,
        revealId: deriveLegacyMigrationRevealId(physicalLegacyId),
        wisdomText: 'Some doors open after surrender.',
        keptAt: DateTime.utc(2026, 8, 2, 1, 13, 7, 484),
      );
      store.envelope = KeptStateEnvelope(activeRecords: [migrated]);
      final repository = buildRepository();

      final resolved =
          await repository.resolveLegacyMigratedRevealIdForOccurrence(
        wisdomText: 'Some doors open after surrender.',
        committedRevealedAt: windowRevealedAt,
        committedUnlockAt: windowUnlockAt,
      );

      expect(resolved, migrated.revealId);
      expect(store.replaceCallCount, 0);
    });

    test(
        '75. the resolver never calls store.replace() across every '
        'scenario above -- an aggregate proof that this method is '
        'genuinely read-only, never a mutation with a lucky no-op path',
        () async {
      final legacyId = srV1Id(committedRevealedAt);
      final migrated = buildRecord(
        id: legacyId,
        revealId: deriveLegacyMigrationRevealId(legacyId),
        wisdomText: 'Some doors open after surrender.',
        keptAt: committedRevealedAt,
      );
      store.envelope = KeptStateEnvelope(activeRecords: [migrated]);
      final repository = buildRepository();

      // A match, a non-match (different text), an ambiguous scenario, and
      // an invalid window -- every branch this method can take.
      await repository.resolveLegacyMigratedRevealIdForOccurrence(
        wisdomText: 'Some doors open after surrender.',
        committedRevealedAt: committedRevealedAt,
        committedUnlockAt: committedUnlockAt,
      );
      await repository.resolveLegacyMigratedRevealIdForOccurrence(
        wisdomText: 'A completely different wisdom.',
        committedRevealedAt: committedRevealedAt,
        committedUnlockAt: committedUnlockAt,
      );

      final secondLegacyId =
          srV1Id(committedRevealedAt.add(const Duration(hours: 3)));
      final secondCandidate = buildRecord(
        id: secondLegacyId,
        revealId: deriveLegacyMigrationRevealId(secondLegacyId),
        wisdomText: 'Some doors open after surrender.',
        keptAt: committedRevealedAt.add(const Duration(hours: 3)),
      );
      store.envelope = KeptStateEnvelope(
        activeRecords: [migrated, secondCandidate],
      );
      final ambiguous =
          await repository.resolveLegacyMigratedRevealIdForOccurrence(
        wisdomText: 'Some doors open after surrender.',
        committedRevealedAt: committedRevealedAt,
        committedUnlockAt: committedUnlockAt,
      );
      expect(ambiguous, isNull);

      await repository.resolveLegacyMigratedRevealIdForOccurrence(
        wisdomText: 'Some doors open after surrender.',
        committedRevealedAt: committedRevealedAt,
        committedUnlockAt: committedRevealedAt,
      );

      expect(store.replaceCallCount, 0);
    });

    test(
        '76. the protected envelope (KeptRecord field-for-field, including '
        'mutationId/updatedAt) remains byte-for-byte identical before and '
        'after resolution -- a migrated KeptRecord is never touched by '
        'this lookup', () async {
      final legacyId = srV1Id(committedRevealedAt);
      final migrated = buildRecord(
        id: legacyId,
        revealId: deriveLegacyMigrationRevealId(legacyId),
        wisdomText: 'Some doors open after surrender.',
        keptAt: committedRevealedAt,
        reflectionText: 'Ibne galatasaray',
        reflectedAt: committedRevealedAt.add(const Duration(hours: 3)),
      );
      final before = KeptStateEnvelope(activeRecords: [migrated]);
      store.envelope = before;
      final repository = buildRepository();

      final resolved =
          await repository.resolveLegacyMigratedRevealIdForOccurrence(
        wisdomText: 'Some doors open after surrender.',
        committedRevealedAt: committedRevealedAt,
        committedUnlockAt: committedUnlockAt,
      );

      expect(resolved, migrated.revealId);
      final after = store.envelope!;
      expect(after, before);
      expect(after.activeRecords.single.id, migrated.id);
      expect(after.activeRecords.single.revealId, migrated.revealId);
      expect(after.activeRecords.single.wisdomText, migrated.wisdomText);
      expect(after.activeRecords.single.revealedAt, migrated.revealedAt);
      expect(after.activeRecords.single.keptAt, migrated.keptAt);
      expect(
        after.activeRecords.single.reflectionText,
        migrated.reflectionText,
      );
      expect(after.activeRecords.single.reflectedAt, migrated.reflectedAt);
      expect(after.activeRecords.single.updatedAt, migrated.updatedAt);
      expect(after.activeRecords.single.mutationId, migrated.mutationId);
    });
  });
}
