import 'package:shared_preferences/shared_preferences.dart';

import '../models/favorite_item.dart';

class StorageService {
  SharedPreferences? _cachedPrefs;

  Future<SharedPreferences> getPrefs() async {
    _cachedPrefs ??= await SharedPreferences.getInstance();
    return _cachedPrefs!;
  }

  Future<void> saveFavorites(List<FavoriteItem> favorites) async {
    final prefs = await getPrefs();

    final encodedFavorites = favorites.map((item) => item.encode()).toList();

    await prefs.setStringList(
      'favorites',
      encodedFavorites,
    );
  }

  Future<List<FavoriteItem>> loadFavorites({
    required String fallbackDate,
  }) async {
    final prefs = await getPrefs();

    final saved = prefs.getStringList('favorites') ?? [];

    return saved
        .map(
          (item) => FavoriteItem.decode(
            item,
            fallbackDate: fallbackDate,
          ),
        )
        .toList();
  }
}
