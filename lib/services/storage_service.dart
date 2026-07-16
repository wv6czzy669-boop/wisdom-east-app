import '../persistence/storage_preferences_adapter.dart';

class StorageService {
  StorageService({
    StoragePreferencesAdapter? preferencesAdapter,
  }) : _preferencesAdapter = preferencesAdapter ?? StoragePreferencesAdapter();

  final StoragePreferencesAdapter _preferencesAdapter;

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
}
