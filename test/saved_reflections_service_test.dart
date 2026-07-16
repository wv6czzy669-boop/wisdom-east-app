import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/persistence/persistence_operation_coordinator.dart';
import 'package:wisdom_app/persistence/storage_preferences_adapter.dart';
import 'package:wisdom_app/services/saved_reflections_service.dart';

void main() {
  late SavedReflectionsService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = SavedReflectionsService();
  });

  test('empty storage loads empty', () async {
    expect(await service.load(), isEmpty);
  });

  test('one valid current record round-trips', () async {
    await seedRaw([currentRecord(id: 'one', text: 'One')]);

    final loaded = await service.load();
    final afterLoad = await rawFavorites();

    expect(loaded, hasLength(1));
    expect(loaded.single.id, 'one');
    expect(loaded.single.text, 'One');
    expect(afterLoad, [currentRecord(id: 'one', text: 'One')]);
  });

  test('multiple records preserve ordering', () async {
    await seedRaw([
      currentRecord(id: 'first', text: 'First'),
      currentRecord(id: 'second', text: 'Second'),
      currentRecord(id: 'third', text: 'Third'),
    ]);

    final loaded = await service.load();

    expect(loaded.map((item) => item.text), ['First', 'Second', 'Third']);
  });

  test('stable ID survives restart', () async {
    await seedRaw(['June 20, 2026|||Legacy reflection']);

    final firstLoad = await service.load();
    final restarted = SavedReflectionsService();
    final secondLoad = await restarted.load();

    expect(firstLoad.single.id, secondLoad.single.id);
    expect(secondLoad.single.text, 'Legacy reflection');
  });

  test('identical text entries retain distinct IDs', () async {
    await seedRaw([
      'June 20, 2026|||Repeated reflection',
      'June 20, 2026|||Repeated reflection',
      'June 21, 2026|||Repeated reflection',
    ]);

    final loaded = await service.load();

    expect(loaded, hasLength(3));
    expect(loaded.map((item) => item.text).toSet(), {'Repeated reflection'});
    expect(loaded.map((item) => item.id).toSet(), hasLength(3));
  });

  test('deletion removes only targeted ID', () async {
    await seedRaw([
      currentRecord(id: 'first', text: 'Repeated reflection'),
      currentRecord(id: 'second', text: 'Repeated reflection'),
    ]);

    final result = await service.toggle(
      text: 'Repeated reflection',
      date: 'June 20, 2026',
      isKeeper: true,
      existingId: 'second',
    );

    expect(result.items.map((item) => item.id), ['first']);
    expect(result.items.single.text, 'Repeated reflection');
  });

  test('deletion after restart works by stable ID', () async {
    await seedRaw(['June 20, 2026|||Legacy reflection']);
    final migrated = await service.load();
    final restarted = SavedReflectionsService();

    final result = await restarted.toggle(
      text: 'Legacy reflection',
      date: 'June 20, 2026',
      isKeeper: false,
      existingId: migrated.single.id,
    );

    expect(result.items, isEmpty);
    expect(await restarted.load(), isEmpty);
  });

  test('malformed entry does not drop valid siblings', () async {
    await seedRaw([
      currentRecord(id: 'valid-one', text: 'Valid one'),
      '',
      currentRecord(id: 'valid-two', text: 'Valid two'),
    ]);

    final loaded = await service.load();

    expect(loaded.map((item) => item.text), ['Valid one', 'Valid two']);
  });

  test('invalid JSON is skipped safely', () async {
    await seedRaw([
      '{"schemaVersion":1,"id":"broken"',
      currentRecord(id: 'valid', text: 'Valid reflection'),
    ]);

    final loaded = await service.load();

    expect(loaded.map((item) => item.text), ['Valid reflection']);
  });

  test('wrong field types are skipped safely', () async {
    await seedRaw([
      jsonEncode({
        'schemaVersion': 1,
        'id': 7,
        'date': 'June 20, 2026',
        'text': 'Wrong ID type',
      }),
      currentRecord(id: 'valid', text: 'Valid reflection'),
    ]);

    final loaded = await service.load();

    expect(loaded.map((item) => item.text), ['Valid reflection']);
  });

  test('missing text is skipped', () async {
    await seedRaw([
      jsonEncode({
        'schemaVersion': 1,
        'id': 'missing-text',
        'date': 'June 20, 2026',
      }),
      currentRecord(id: 'valid', text: 'Valid reflection'),
    ]);

    final loaded = await service.load();

    expect(loaded.map((item) => item.text), ['Valid reflection']);
  });

  test('empty text is skipped', () async {
    await seedRaw([
      currentRecord(id: 'empty-text', text: ''),
      currentRecord(id: 'valid', text: 'Valid reflection'),
    ]);

    final loaded = await service.load();

    expect(loaded.map((item) => item.text), ['Valid reflection']);
  });

  test('invalid date is skipped', () async {
    await seedRaw([
      currentRecord(id: 'empty-date', date: '', text: 'No date'),
      currentRecord(id: 'valid', text: 'Valid reflection'),
    ]);

    final loaded = await service.load();

    expect(loaded.map((item) => item.text), ['Valid reflection']);
  });

  test('legacy record migrates once', () async {
    await seedRaw(['June 20, 2026|||Legacy reflection']);

    final loaded = await service.load();
    final migrated = await rawFavorites();

    expect(loaded.single.text, 'Legacy reflection');
    expect(FavoriteItem.looksLikeCurrentSchema(migrated!.single), isTrue);
    expect(FavoriteItem.decodeCurrent(migrated.single).id, loaded.single.id);
  });

  test('repeated migration is idempotent', () async {
    await seedRaw(['June 20, 2026|||Legacy reflection']);

    await service.load();
    final afterFirstLoad = await rawFavorites();
    await service.load();
    final afterSecondLoad = await rawFavorites();

    expect(afterSecondLoad, afterFirstLoad);
  });

  test('migration preserves date', () async {
    await seedRaw(['June 21, 2026|||Legacy reflection']);

    final loaded = await service.load();

    expect(loaded.single.date, 'June 21, 2026');
  });

  test('migration preserves ordering', () async {
    await seedRaw([
      'June 20, 2026|||First',
      'June 21, 2026|||Second',
      'June 22, 2026|||Third',
    ]);

    final loaded = await service.load();

    expect(loaded.map((item) => item.text), ['First', 'Second', 'Third']);
  });

  test('migration preserves duplicates', () async {
    await seedRaw([
      'June 20, 2026|||Repeated',
      'June 20, 2026|||Repeated',
    ]);

    final loaded = await service.load();

    expect(loaded.map((item) => item.text), ['Repeated', 'Repeated']);
    expect(loaded.map((item) => item.id).toSet(), hasLength(2));
  });

  test('duplicate persisted IDs are repaired deterministically', () async {
    await seedRaw([
      currentRecord(id: 'duplicate', text: 'First'),
      currentRecord(id: 'duplicate', text: 'Second'),
      currentRecord(id: 'duplicate', text: 'Third'),
    ]);

    final loaded = await service.load();
    final restarted = SavedReflectionsService();
    final reloaded = await restarted.load();

    expect(loaded.map((item) => item.id).toSet(), hasLength(3));
    expect(reloaded.map((item) => item.id), loaded.map((item) => item.id));
    expect(reloaded.map((item) => item.text), ['First', 'Second', 'Third']);
  });

  test('mixed legacy/current records load safely', () async {
    await seedRaw([
      currentRecord(id: 'current', text: 'Current'),
      'June 21, 2026|||Legacy',
      '{',
      currentRecord(id: 'another-current', text: 'Another current'),
    ]);

    final loaded = await service.load();

    expect(
      loaded.map((item) => item.text),
      ['Current', 'Legacy', 'Another current'],
    );
  });

  test('current record missing ID is migrated without losing data', () async {
    await seedRaw([
      jsonEncode({
        'schemaVersion': 1,
        'date': 'June 20, 2026',
        'text': 'Missing ID',
      }),
    ]);

    final loaded = await service.load();
    final persisted =
        FavoriteItem.decodeCurrent((await rawFavorites())!.single);

    expect(loaded.single.text, 'Missing ID');
    expect(loaded.single.id, isNotEmpty);
    expect(persisted.id, loaded.single.id);
  });

  test('delimiter inside reflection text remains decodable', () async {
    await seedRaw([
      'June 20, 2026|||A reflection ||| with delimiter',
    ]);

    final loaded = await service.load();

    expect(loaded.single.text, 'A reflection ||| with delimiter');
  });

  test('free users can save at most three reflections', () async {
    for (var index = 1; index <= 3; index += 1) {
      final result = await service.toggle(
        text: 'Reflection $index',
        date: 'June 20, 2026',
        isKeeper: false,
      );
      expect(result.limitReached, isFalse);
    }

    final fourth = await service.toggle(
      text: 'Reflection 4',
      date: 'June 20, 2026',
      isKeeper: false,
    );
    final persisted = await service.load();

    expect(fourth.limitReached, isTrue);
    expect(fourth.items, hasLength(3));
    expect(persisted, hasLength(3));
    expect(persisted.any((item) => item.text == 'Reflection 4'), isFalse);
  });

  test('free users may remove a reflection and save a replacement', () async {
    await seedRaw([
      currentRecord(id: 'one', text: 'One', date: 'Today'),
      currentRecord(id: 'two', text: 'Two', date: 'Today'),
      currentRecord(id: 'three', text: 'Three', date: 'Today'),
    ]);

    final removed = await service.toggle(
      text: 'Two',
      date: 'Today',
      isKeeper: false,
      existingId: 'two',
    );
    final replacement = await service.toggle(
      text: 'Four',
      date: 'Today',
      isKeeper: false,
    );

    expect(removed.items.map((item) => item.text), ['One', 'Three']);
    expect(replacement.limitReached, isFalse);
    expect(
      replacement.items.map((item) => item.text),
      ['One', 'Three', 'Four'],
    );
  });

  test('Keeper users have unlimited kept reflections', () async {
    for (var index = 0; index < 12; index += 1) {
      final result = await service.toggle(
        text: 'Reflection $index',
        date: 'June 20, 2026',
        isKeeper: true,
      );
      expect(result.limitReached, isFalse);
    }

    expect(await service.load(), hasLength(12));
  });

  test('free users preserve legacy over-limit items but cannot add more',
      () async {
    await seedRaw([
      currentRecord(id: 'one', text: 'One', date: 'Today'),
      currentRecord(id: 'two', text: 'Two', date: 'Today'),
      currentRecord(id: 'three', text: 'Three', date: 'Today'),
      currentRecord(id: 'legacy-four', text: 'Legacy four', date: 'Today'),
    ]);

    final blocked = await service.toggle(
      text: 'Five',
      date: 'Today',
      isKeeper: false,
    );
    expect(blocked.limitReached, isTrue);
    expect(blocked.items, hasLength(4));

    await service.toggle(
      text: 'Legacy four',
      date: 'Today',
      isKeeper: false,
      existingId: 'legacy-four',
    );
    final stillBlocked = await service.toggle(
      text: 'Replacement',
      date: 'Today',
      isKeeper: false,
    );
    expect(stillBlocked.limitReached, isTrue);

    await service.toggle(
      text: 'Three',
      date: 'Today',
      isKeeper: false,
      existingId: 'three',
    );
    final replacement = await service.toggle(
      text: 'Replacement',
      date: 'Today',
      isKeeper: false,
    );

    expect(replacement.limitReached, isFalse);
    expect(replacement.items, hasLength(3));
    expect(
      replacement.items.any((item) => item.text == 'Replacement'),
      isTrue,
    );
  });

  test('failed persistence does not report a changed reflection list',
      () async {
    service = SavedReflectionsService(
      preferencesAdapter: _FailingStringListAdapter(),
    );

    await expectLater(
      service.toggle(
        text: 'Unpersisted reflection',
        date: 'Today',
        isKeeper: false,
      ),
      throwsA(isA<StateError>()),
    );

    expect(await rawFavorites(), isNull);
  });

  test('failed write does not corrupt subsequent operations', () async {
    final adapter = _FailingOnceStringListAdapter();
    service = SavedReflectionsService(preferencesAdapter: adapter);

    await expectLater(
      service.toggle(
        text: 'First attempt',
        date: 'Today',
        isKeeper: false,
      ),
      throwsA(isA<StateError>()),
    );

    final retry = await service.toggle(
      text: 'Second attempt',
      date: 'Today',
      isKeeper: false,
    );

    expect(retry.items.map((item) => item.text), ['Second attempt']);
    expect(await service.load(), hasLength(1));
  });

  test('concurrent save/save loses no valid write', () async {
    final first = service.toggle(
      text: 'First',
      date: 'Today',
      isKeeper: true,
    );
    final second = service.toggle(
      text: 'Second',
      date: 'Today',
      isKeeper: true,
    );

    await Future.wait([first, second]);
    final persisted = await service.load();

    expect(persisted.map((item) => item.text), ['First', 'Second']);
  });

  test('concurrent save/delete does not resurrect deleted record', () async {
    await seedRaw([currentRecord(id: 'delete-me', text: 'Delete me')]);

    final delete = service.toggle(
      text: 'Delete me',
      date: 'June 20, 2026',
      isKeeper: true,
      existingId: 'delete-me',
    );
    final save = service.toggle(
      text: 'Keep me',
      date: 'June 20, 2026',
      isKeeper: true,
    );

    await Future.wait([delete, save]);
    final persisted = await service.load();

    expect(persisted.map((item) => item.text), ['Keep me']);
  });

  test('concurrent delete/delete is deterministic', () async {
    await seedRaw([currentRecord(id: 'delete-once', text: 'Delete once')]);

    final first = service.toggle(
      text: 'Delete once',
      date: 'June 20, 2026',
      isKeeper: true,
      existingId: 'delete-once',
    );
    final second = service.toggle(
      text: 'Delete once',
      date: 'June 20, 2026',
      isKeeper: true,
      existingId: 'delete-once',
    );

    await Future.wait([first, second]);

    expect(await service.load(), isEmpty);
  });

  test('free user concurrent saves cannot exceed three', () async {
    await seedRaw([
      currentRecord(id: 'one', text: 'One'),
      currentRecord(id: 'two', text: 'Two'),
    ]);

    final first = service.toggle(
      text: 'Three',
      date: 'Today',
      isKeeper: false,
    );
    final second = service.toggle(
      text: 'Four',
      date: 'Today',
      isKeeper: false,
    );

    final results = await Future.wait([first, second]);
    final persisted = await service.load();

    expect(persisted, hasLength(3));
    expect(results.where((result) => result.limitReached), hasLength(1));
  });

  test('Keeper concurrent saves are not limited to three', () async {
    await seedRaw([
      currentRecord(id: 'one', text: 'One'),
      currentRecord(id: 'two', text: 'Two'),
      currentRecord(id: 'three', text: 'Three'),
    ]);

    await Future.wait([
      service.toggle(text: 'Four', date: 'Today', isKeeper: true),
      service.toggle(text: 'Five', date: 'Today', isKeeper: true),
    ]);

    expect(await service.load(), hasLength(5));
  });

  test('separate test instances do not share hidden static state', () async {
    final firstService = SavedReflectionsService(
      preferencesAdapter: StoragePreferencesAdapter(),
      operationCoordinator: PersistenceOperationCoordinator(),
    );
    final secondService = SavedReflectionsService(
      preferencesAdapter: StoragePreferencesAdapter(),
      operationCoordinator: PersistenceOperationCoordinator(),
    );

    await firstService.toggle(
      text: 'First',
      date: 'Today',
      isKeeper: true,
    );
    await secondService.toggle(
      text: 'Second',
      date: 'Today',
      isKeeper: true,
    );

    expect(await service.load(), hasLength(2));
  });

  test('text toggle still prevents duplicate current wisdom saves', () async {
    final saved = await service.toggle(
      text: 'Current wisdom',
      date: 'Today',
      isKeeper: true,
    );
    final removed = await service.toggle(
      text: 'Current wisdom',
      date: 'Today',
      isKeeper: true,
      existingId: saved.items.single.id,
    );

    expect(removed.items, isEmpty);
  });
}

String currentRecord({
  required String id,
  String date = 'June 20, 2026',
  required String text,
}) {
  return FavoriteItem(id: id, date: date, text: text).encode();
}

Future<void> seedRaw(List<String> entries) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(SavedReflectionsService.storageKey, entries);
}

Future<List<String>?> rawFavorites() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getStringList(SavedReflectionsService.storageKey);
}

class _FailingStringListAdapter extends StoragePreferencesAdapter {
  @override
  Future<void> setStringList(String key, List<String> value) {
    throw StateError('Simulated saved reflection persistence failure.');
  }
}

class _FailingOnceStringListAdapter extends StoragePreferencesAdapter {
  var _shouldFail = true;

  @override
  Future<void> setStringList(String key, List<String> value) {
    if (_shouldFail) {
      _shouldFail = false;
      throw StateError('Simulated one-time persistence failure.');
    }

    return super.setStringList(key, value);
  }
}
