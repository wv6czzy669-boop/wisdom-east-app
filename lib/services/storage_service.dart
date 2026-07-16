import '../models/favorite_item.dart';
import '../persistence/storage_preferences_adapter.dart';

class StorageService {
  StorageService({
    StoragePreferencesAdapter? preferencesAdapter,
  }) : _preferencesAdapter = preferencesAdapter ?? StoragePreferencesAdapter();

  final StoragePreferencesAdapter _preferencesAdapter;

  Future<void> saveFavorites(List<FavoriteItem> favorites) async {
    final encodedFavorites = favorites.map((item) => item.encode()).toList();

    try {
      await _preferencesAdapter.setStringList(
        'favorites',
        encodedFavorites,
      );
    } catch (_) {
      throw StateError('Saved reflections could not be persisted.');
    }
  }

  Future<List<FavoriteItem>> loadFavorites({
    required String fallbackDate,
  }) async {
    final List<String> saved;
    try {
      saved = await _preferencesAdapter.getStringList('favorites') ?? [];
    } catch (_) {
      return [];
    }

    final List<FavoriteItem> validFavorites = [];

    for (final item in saved) {
      try {
        final favorite = FavoriteItem.decode(
          item,
          fallbackDate: fallbackDate,
        );
        validFavorites.add(favorite);
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
    late final List<String> archive;
    try {
      archive =
          await _preferencesAdapter.getStringList("daily_wisdom_archive") ?? [];
    } catch (_) {
      archive = [];
    }
    final entry = "$today|||$text";

    final alreadySavedToday = archive.any(
      (item) => item.startsWith("$today|||"),
    );

    if (!alreadySavedToday) {
      archive.insert(0, entry);

      try {
        await _preferencesAdapter.setStringList(
          "daily_wisdom_archive",
          archive.take(90).toList(),
        );
      } catch (_) {
        throw StateError('Daily wisdom archive could not be persisted.');
      }
    }
  }

  Future<bool> getKeeperStatus() async {
    try {
      return await _preferencesAdapter.getBool("is_premium") ?? false;
    } catch (_) {
      return false;
    }
  }
}
