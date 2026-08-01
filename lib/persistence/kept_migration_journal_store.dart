import '../models/kept_migration_journal.dart';
import 'storage_preferences_adapter.dart';

/// Thrown by [KeptMigrationJournalStore] implementations on any failure to
/// read, decode, persist, or verify the migration journal.
class KeptMigrationJournalStoreException implements Exception {
  const KeptMigrationJournalStoreException(
    this.stage,
    this.message, [
    this.cause,
  ]);

  final String stage;
  final String message;
  final Object? cause;

  @override
  String toString() {
    final cause = this.cause;
    if (cause == null) {
      return 'KeptMigrationJournalStoreException[$stage]: $message';
    }
    return 'KeptMigrationJournalStoreException[$stage]: $message ($cause)';
  }
}

/// Boundary onto the durable migration-journal record.
abstract interface class KeptMigrationJournalStore {
  /// Returns the current journal, or `null` when migration has not started
  /// (no journal has ever been written).
  Future<KeptMigrationJournal?> load();

  /// Persists [journal] as a complete replacement, verifying the write by
  /// reading it back and comparing it by value. Never treats a failed or
  /// unverified write as successful.
  Future<void> save(KeptMigrationJournal journal);
}

/// Production [KeptMigrationJournalStore], backed by SharedPreferences via
/// the existing [StoragePreferencesAdapter].
final class SharedPreferencesKeptMigrationJournalStore
    implements KeptMigrationJournalStore {
  SharedPreferencesKeptMigrationJournalStore({
    StoragePreferencesAdapter? preferencesAdapter,
  }) : _preferencesAdapter = preferencesAdapter ?? StoragePreferencesAdapter();

  static const String journalKey = 'east_kept_storage_migration_v3_journal';

  final StoragePreferencesAdapter _preferencesAdapter;

  @override
  Future<KeptMigrationJournal?> load() async {
    final bool exists;
    try {
      exists = await _preferencesAdapter.containsKey(journalKey);
    } catch (error) {
      throw KeptMigrationJournalStoreException(
        'load',
        'Could not check for a migration journal.',
        error,
      );
    }
    if (!exists) return null;

    String? raw;
    try {
      raw = await _preferencesAdapter.getString(journalKey);
    } catch (error) {
      throw KeptMigrationJournalStoreException(
        'load',
        'Could not read the migration journal.',
        error,
      );
    }
    if (raw == null) {
      throw const KeptMigrationJournalStoreException(
        'load',
        'The migration journal key exists but could not be read as a '
            'string.',
      );
    }

    try {
      return KeptMigrationJournal.decodeString(raw);
    } catch (error) {
      throw KeptMigrationJournalStoreException(
        'load-decode',
        'The stored migration journal is malformed.',
        error,
      );
    }
  }

  @override
  Future<void> save(KeptMigrationJournal journal) async {
    final encoded = journal.encodeString();

    try {
      await _preferencesAdapter.setString(journalKey, encoded);
    } catch (error) {
      throw KeptMigrationJournalStoreException(
        'save',
        'Could not persist the migration journal.',
        error,
      );
    }

    String? rawBack;
    try {
      rawBack = await _preferencesAdapter.getString(journalKey);
    } catch (error) {
      throw KeptMigrationJournalStoreException(
        'save-verify',
        'Could not read back the migration journal.',
        error,
      );
    }
    if (rawBack == null) {
      throw const KeptMigrationJournalStoreException(
        'save-verify',
        'The migration journal could not be read back after saving.',
      );
    }

    final KeptMigrationJournal decodedBack;
    try {
      decodedBack = KeptMigrationJournal.decodeString(rawBack);
    } catch (error) {
      throw KeptMigrationJournalStoreException(
        'save-verify',
        'The migration journal read-back is malformed.',
        error,
      );
    }

    if (decodedBack != journal) {
      throw const KeptMigrationJournalStoreException(
        'save-verify',
        'The migration journal read-back did not match the intended value.',
      );
    }
  }
}
