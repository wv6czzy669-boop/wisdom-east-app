import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/models/favorite_item.dart';
import 'package:wisdom_app/services/saved_reflections_service.dart';
import 'package:wisdom_app/services/storage_service.dart';

void main() {
  late SavedReflectionsService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = SavedReflectionsService(storageService: StorageService());
  });

  test('free users can save at most three reflections', () async {
    var items = <FavoriteItem>[];

    for (var index = 1; index <= 3; index++) {
      final result = await service.toggle(
        currentItems: items,
        text: 'Reflection $index',
        date: 'June 20, 2026',
        isKeeper: false,
      );
      expect(result.limitReached, isFalse);
      items = result.items;
    }

    final fourth = await service.toggle(
      currentItems: items,
      text: 'Reflection 4',
      date: 'June 20, 2026',
      isKeeper: false,
    );
    final persisted = await service.load(fallbackDate: 'June 20, 2026');

    expect(fourth.limitReached, isTrue);
    expect(fourth.items, hasLength(3));
    expect(persisted, hasLength(3));
    expect(persisted.any((item) => item.text == 'Reflection 4'), isFalse);
  });

  test('free users may remove a reflection and save a replacement', () async {
    var items = [
      FavoriteItem(text: 'One', date: 'Today'),
      FavoriteItem(text: 'Two', date: 'Today'),
      FavoriteItem(text: 'Three', date: 'Today'),
    ];
    await StorageService().saveFavorites(items);

    final removed = await service.toggle(
      currentItems: items,
      text: 'Two',
      date: 'Today',
      isKeeper: false,
    );
    final replacement = await service.toggle(
      currentItems: removed.items,
      text: 'Four',
      date: 'Today',
      isKeeper: false,
    );

    expect(replacement.limitReached, isFalse);
    expect(
        replacement.items.map((item) => item.text), ['One', 'Three', 'Four']);
  });

  test('Keeper users have unlimited kept reflections', () async {
    var items = <FavoriteItem>[];

    for (var index = 0; index < 12; index++) {
      final result = await service.toggle(
        currentItems: items,
        text: 'Reflection $index',
        date: 'June 20, 2026',
        isKeeper: true,
      );
      expect(result.limitReached, isFalse);
      items = result.items;
    }

    expect(items, hasLength(12));
  });

  test('free users preserve legacy over-limit items but cannot add more',
      () async {
    var items = [
      FavoriteItem(text: 'One', date: 'Today'),
      FavoriteItem(text: 'Two', date: 'Today'),
      FavoriteItem(text: 'Three', date: 'Today'),
      FavoriteItem(text: 'Legacy four', date: 'Today'),
    ];

    final blocked = await service.toggle(
      currentItems: items,
      text: 'Five',
      date: 'Today',
      isKeeper: false,
    );
    expect(blocked.limitReached, isTrue);
    expect(blocked.items, hasLength(4));

    final firstRemoval = await service.toggle(
      currentItems: items,
      text: 'Legacy four',
      date: 'Today',
      isKeeper: false,
    );
    items = firstRemoval.items;
    expect(items, hasLength(3));

    final stillBlocked = await service.toggle(
      currentItems: items,
      text: 'Replacement',
      date: 'Today',
      isKeeper: false,
    );
    expect(stillBlocked.limitReached, isTrue);

    final secondRemoval = await service.toggle(
      currentItems: items,
      text: 'Three',
      date: 'Today',
      isKeeper: false,
    );
    final replacement = await service.toggle(
      currentItems: secondRemoval.items,
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
    final originalItems = [
      FavoriteItem(text: 'Existing reflection', date: 'Today'),
    ];
    service = SavedReflectionsService(
      storageService: _FailingFavoritesStorageService(),
    );

    await expectLater(
      service.toggle(
        currentItems: originalItems,
        text: 'Unpersisted reflection',
        date: 'Today',
        isKeeper: false,
      ),
      throwsA(isA<StateError>()),
    );

    expect(originalItems.map((item) => item.text), ['Existing reflection']);
  });

  test('corrupted persisted reflections are skipped without deletion',
      () async {
    SharedPreferences.setMockInitialValues({
      'favorites': [
        'June 20, 2026|||Valid reflection',
        '',
        'June 21, 2026|||',
        'June 22, 2026|||Valid reflection',
        'Legacy valid reflection',
      ],
    });
    service = SavedReflectionsService(storageService: StorageService());

    final loaded = await service.load(fallbackDate: 'June 20, 2026');
    final prefs = await SharedPreferences.getInstance();

    expect(
      loaded.map((item) => item.text),
      ['Valid reflection', 'Valid reflection', 'Legacy valid reflection'],
    );
    expect(prefs.getStringList('favorites'), hasLength(5));
  });

  test('same text reflections are preserved as separate entries', () async {
    SharedPreferences.setMockInitialValues({
      'favorites': [
        'June 20, 2026|||Repeated reflection',
        'June 20, 2026|||Repeated reflection',
        'June 21, 2026|||Repeated reflection',
      ],
    });
    service = SavedReflectionsService(storageService: StorageService());

    final loaded = await service.load(fallbackDate: 'June 20, 2026');
    final prefs = await SharedPreferences.getInstance();

    expect(loaded, hasLength(3));
    expect(
      loaded.map((item) => item.date),
      ['June 20, 2026', 'June 20, 2026', 'June 21, 2026'],
    );
    expect(
      loaded.map((item) => item.text),
      [
        'Repeated reflection',
        'Repeated reflection',
        'Repeated reflection',
      ],
    );
    expect(prefs.getStringList('favorites'), hasLength(3));
  });

  test('delimiter inside reflection text remains decodable', () async {
    SharedPreferences.setMockInitialValues({
      'favorites': [
        'June 20, 2026|||A reflection ||| with delimiter',
        '   ',
      ],
    });
    service = SavedReflectionsService(storageService: StorageService());

    final loaded = await service.load(fallbackDate: 'June 20, 2026');
    final prefs = await SharedPreferences.getInstance();

    expect(loaded, hasLength(1));
    expect(loaded.single.text, 'A reflection ||| with delimiter');
    expect(prefs.getStringList('favorites'), hasLength(2));
  });
}

class _FailingFavoritesStorageService extends StorageService {
  @override
  Future<void> saveFavorites(List<FavoriteItem> favorites) {
    throw StateError('Simulated persistence failure.');
  }
}
