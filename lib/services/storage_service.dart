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

  Future<void> saveDailyArchive({
    required String text,
    required String today,
  }) async {
    final prefs = await getPrefs();

    final archive = prefs.getStringList("daily_wisdom_archive") ?? [];
    final entry = "$today|||$text";

    final alreadySavedToday = archive.any(
      (item) => item.startsWith("$today|||"),
    );

    if (!alreadySavedToday) {
      archive.insert(0, entry);

      await prefs.setStringList(
        "daily_wisdom_archive",
        archive.take(90).toList(),
      );
    }
  }

  Future<void> saveRewardedWisdom({
    required String text,
    required DateTime unlockTime,
  }) async {
    final prefs = await getPrefs();

    await prefs.setString(
      "daily_wisdom_text",
      text,
    );

    await prefs.setInt(
      "wisdom_unlock_time_ms",
      unlockTime.millisecondsSinceEpoch,
    );
  }

  Future<int?> getWisdomUnlockTimeMs() async {
    final prefs = await getPrefs();
    return prefs.getInt("wisdom_unlock_time_ms");
  }
}
