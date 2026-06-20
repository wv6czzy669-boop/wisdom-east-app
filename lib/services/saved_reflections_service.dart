import '../models/favorite_item.dart';
import 'storage_service.dart';

class SavedReflectionsResult {
  const SavedReflectionsResult({
    required this.items,
    required this.limitReached,
  });

  final List<FavoriteItem> items;
  final bool limitReached;
}

class SavedReflectionsService {
  SavedReflectionsService({
    required StorageService storageService,
    this.freeLimit = 3,
  }) : _storageService = storageService;

  final StorageService _storageService;
  final int freeLimit;

  Future<List<FavoriteItem>> load({required String fallbackDate}) {
    return _storageService.loadFavorites(fallbackDate: fallbackDate);
  }

  Future<SavedReflectionsResult> toggle({
    required List<FavoriteItem> currentItems,
    required String text,
    required String date,
    required bool isKeeper,
  }) async {
    final items = List<FavoriteItem>.from(currentItems);
    final existingIndex = items.indexWhere((item) => item.text == text);

    if (existingIndex >= 0) {
      items.removeAt(existingIndex);
    } else {
      // Preserve legacy items without silently deleting user data. Free users
      // may remove entries, but cannot add until the list is below the limit.
      if (!isKeeper && items.length >= freeLimit) {
        return SavedReflectionsResult(
          items: List.unmodifiable(items),
          limitReached: true,
        );
      }

      items.add(FavoriteItem(text: text, date: date));
    }

    await _storageService.saveFavorites(items);
    return SavedReflectionsResult(
      items: List.unmodifiable(items),
      limitReached: false,
    );
  }
}
