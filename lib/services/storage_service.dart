import 'package:shared_preferences/shared_preferences.dart';

import '../models/favorite_item.dart';
import '../models/daily_wisdom_record.dart';

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

    final List<FavoriteItem> validFavorites = [];

    for (final item in saved) {
      try {
        validFavorites.add(
          FavoriteItem.decode(
            item,
            fallbackDate: fallbackDate,
          ),
        );
      } catch (_) {
        continue;
      }
    }

    return validFavorites;
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

  Future<DailyWisdomRecord?> loadDailyWisdomRecord({
    required Duration lockDuration,
  }) async {
    final prefs = await getPrefs();
    final encodedRecord = prefs.getString("daily_wisdom_access");

    if (encodedRecord != null) {
      try {
        return DailyWisdomRecord.decode(encodedRecord);
      } catch (_) {
        return null;
      }
    }

    final legacyText = prefs.getString("daily_wisdom_text");
    final legacyUnlockTimeMs = prefs.getInt("wisdom_unlock_time_ms");
    if (legacyText == null || legacyUnlockTimeMs == null) return null;

    final unlockAt = DateTime.fromMillisecondsSinceEpoch(legacyUnlockTimeMs);
    final migratedRecord = DailyWisdomRecord(
      text: legacyText,
      revealedAt: unlockAt.subtract(lockDuration),
      unlockAt: unlockAt,
    );

    await saveDailyWisdomRecord(migratedRecord);
    return migratedRecord;
  }

  Future<void> saveDailyWisdomRecord(DailyWisdomRecord record) async {
    final prefs = await getPrefs();
    final saved = await prefs.setString("daily_wisdom_access", record.encode());
    if (!saved) {
      throw StateError('Daily wisdom lock could not be persisted.');
    }

    await prefs.remove("daily_wisdom_text");
    await prefs.remove("wisdom_unlock_time_ms");
  }

  Future<bool> getKeeperStatus() async {
    final prefs = await getPrefs();
    return prefs.getBool("is_premium") ?? false;
  }
}
