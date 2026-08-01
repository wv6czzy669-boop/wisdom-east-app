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

    test('14b. a v5 revealId is rejected for a new keep (v4 required)',
        () async {
      final repository = buildRepository();
      const v5 = '6fa459ea-ee8a-5ca4-894e-db77e160355e';

      await expectLater(
        repository.keepOccurrence(
          revealId: v5,
          wisdomText: 'Be still.',
          revealedAt: now,
          isKeeper: false,
        ),
        throwsA(isA<KeptRepositoryException>()),
      );
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
}
