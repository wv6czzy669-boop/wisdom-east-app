import 'storage_preferences_adapter.dart';

/// Thrown by [LegacyFavoritesStore] implementations on any failure to read,
/// inspect, or remove the legacy Build 25 `favorites` data.
class LegacyFavoritesStoreException implements Exception {
  const LegacyFavoritesStoreException(this.stage, this.message, [this.cause]);

  final String stage;
  final String message;
  final Object? cause;

  @override
  String toString() {
    final cause = this.cause;
    if (cause == null) return 'LegacyFavoritesStoreException[$stage]: $message';
    return 'LegacyFavoritesStoreException[$stage]: $message ($cause)';
  }
}

/// Narrow boundary onto the legacy Build 25 `favorites` SharedPreferences
/// StringList, used only by the Phase 3C migration engine.
///
/// Deliberately does not expose parsed [FavoriteItem]s — the migration
/// coordinator inspects every raw entry independently (so it can classify
/// each one as usable, corrupt, or conflicting on its own), not through the
/// original app's own load-and-migrate-in-place logic.
abstract interface class LegacyFavoritesStore {
  /// Whether the legacy `favorites` key currently exists at all (regardless
  /// of whether it holds any entries).
  Future<bool> containsLegacyData();

  /// The raw legacy StringList, in original order, byte-exact.
  ///
  /// Returns `null` only when the key is absent. Returns an empty list when
  /// the key exists as an empty StringList. Throws when the key exists but
  /// does not hold a string list — this never coerces another stored type
  /// into a list.
  Future<List<String>?> readRawEntries();

  /// Removes the legacy `favorites` key and confirms it is actually gone
  /// afterward. Throws unless removal is independently confirmed —
  /// including when the underlying platform reports success but the key
  /// is somehow still present.
  Future<void> removeAndVerify();
}

/// Production [LegacyFavoritesStore], backed by the same
/// [StoragePreferencesAdapter] the rest of the app uses, against the exact
/// Build 25 key `SavedReflectionsService.storageKey` also uses.
final class SharedPreferencesLegacyFavoritesStore
    implements LegacyFavoritesStore {
  SharedPreferencesLegacyFavoritesStore({
    StoragePreferencesAdapter? preferencesAdapter,
  }) : _preferencesAdapter = preferencesAdapter ?? StoragePreferencesAdapter();

  /// Matches `SavedReflectionsService.storageKey` exactly. Duplicated as a
  /// literal (not imported) so this store has no compile-time dependency on
  /// the Build 25 service — the value itself is the actual Build 25
  /// contract, verified against the live source before this file was
  /// written.
  static const String legacyKey = 'favorites';

  final StoragePreferencesAdapter _preferencesAdapter;

  @override
  Future<bool> containsLegacyData() async {
    try {
      return await _preferencesAdapter.containsKey(legacyKey);
    } catch (error) {
      throw LegacyFavoritesStoreException(
        'contains',
        'Could not check for legacy favorites data.',
        error,
      );
    }
  }

  @override
  Future<List<String>?> readRawEntries() async {
    final bool exists;
    try {
      exists = await _preferencesAdapter.containsKey(legacyKey);
    } catch (error) {
      throw LegacyFavoritesStoreException(
        'read',
        'Could not check for legacy favorites data.',
        error,
      );
    }
    if (!exists) return null;

    List<String>? raw;
    try {
      raw = await _preferencesAdapter.getStringList(legacyKey);
    } catch (error) {
      throw LegacyFavoritesStoreException(
        'read',
        'The legacy favorites key does not hold a string list.',
        error,
      );
    }
    if (raw == null) {
      throw const LegacyFavoritesStoreException(
        'read',
        'The legacy favorites key exists but could not be read as a '
            'string list.',
      );
    }

    return List<String>.unmodifiable(raw);
  }

  @override
  Future<void> removeAndVerify() async {
    try {
      await _preferencesAdapter.remove(legacyKey);
    } catch (error) {
      throw LegacyFavoritesStoreException(
        'remove',
        'Could not remove the legacy favorites key.',
        error,
      );
    }

    final bool stillPresent;
    try {
      stillPresent = await _preferencesAdapter.containsKey(legacyKey);
    } catch (error) {
      throw LegacyFavoritesStoreException(
        'remove-verify',
        'Could not verify legacy favorites removal.',
        error,
      );
    }
    if (stillPresent) {
      throw const LegacyFavoritesStoreException(
        'remove-verify',
        'The legacy favorites key is still present after removal.',
      );
    }
  }
}
