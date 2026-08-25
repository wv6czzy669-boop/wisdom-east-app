import 'storage_preferences_adapter.dart';

/// Device-local memory of recently selected canonical wisdom identities.
///
/// This is presentation quality state only. It never participates in the
/// rolling daily-access lock, Kept persistence, CloudKit, or analytics.
abstract interface class WisdomSelectionHistoryStore {
  Future<List<String>> loadRecentWisdomIds();

  Future<void> replaceRecentWisdomIds(List<String> wisdomIds);
}

class SharedPreferencesWisdomSelectionHistoryStore
    implements WisdomSelectionHistoryStore {
  SharedPreferencesWisdomSelectionHistoryStore({
    StoragePreferencesAdapter? storage,
  }) : _storage = storage ?? StoragePreferencesAdapter();

  static const String storageKey = 'east_recent_wisdom_ids_v1';

  final StoragePreferencesAdapter _storage;

  @override
  Future<List<String>> loadRecentWisdomIds() async =>
      await _storage.getStringList(storageKey) ?? const <String>[];

  @override
  Future<void> replaceRecentWisdomIds(List<String> wisdomIds) =>
      _storage.setStringList(
        storageKey,
        List<String>.unmodifiable(wisdomIds),
      );
}
