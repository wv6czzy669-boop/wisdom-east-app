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

  test('Keeper users have unlimited saved reflections', () async {
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
}
