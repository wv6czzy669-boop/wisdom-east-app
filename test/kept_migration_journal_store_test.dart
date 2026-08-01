import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/models/kept_migration_journal.dart';
import 'package:wisdom_app/persistence/kept_migration_journal_store.dart';
import 'package:wisdom_app/persistence/storage_preferences_adapter.dart';

class _FailingSetStringAdapter extends StoragePreferencesAdapter {
  @override
  Future<void> setString(String key, String value) {
    throw StateError('Simulated journal persistence failure.');
  }
}

/// Writes normally, but always reads back a fixed, different (though
/// validly-decodable) journal string — simulating a storage layer whose
/// read-back does not reflect what was just written.
class _MismatchedReadBackAdapter extends StoragePreferencesAdapter {
  _MismatchedReadBackAdapter(this.wrongValue);

  final String wrongValue;

  @override
  Future<String?> getString(String key) async => wrongValue;
}

void main() {
  const migrationId = '123e4567-e89b-4d3a-a456-426614174000';
  final startedAt = DateTime.utc(2026, 8, 1, 9, 0);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('18. an absent journal returns null', () async {
    final store = SharedPreferencesKeptMigrationJournalStore();

    expect(await store.load(), isNull);
  });

  test('19. write/read-back round-trips exactly', () async {
    final store = SharedPreferencesKeptMigrationJournalStore();
    final journal = KeptMigrationJournal(
      state: KeptMigrationState.writing,
      migrationId: migrationId,
      startedAt: startedAt,
      updatedAt: startedAt,
    );

    await store.save(journal);
    final loaded = await store.load();

    expect(loaded, journal);
  });

  test('20. a setString failure throws', () async {
    final store = SharedPreferencesKeptMigrationJournalStore(
      preferencesAdapter: _FailingSetStringAdapter(),
    );
    final journal = KeptMigrationJournal(
      state: KeptMigrationState.writing,
      migrationId: migrationId,
      startedAt: startedAt,
      updatedAt: startedAt,
    );

    expect(
      () => store.save(journal),
      throwsA(isA<KeptMigrationJournalStoreException>()),
    );
  });

  test('21. a read-back mismatch throws', () async {
    final journal = KeptMigrationJournal(
      state: KeptMigrationState.writing,
      migrationId: migrationId,
      startedAt: startedAt,
      updatedAt: startedAt,
    );
    final differentJournal = KeptMigrationJournal(
      state: KeptMigrationState.writing,
      migrationId: '223e4567-e89b-4d3a-a456-426614174001',
      startedAt: startedAt,
      updatedAt: startedAt,
    );
    final store = SharedPreferencesKeptMigrationJournalStore(
      preferencesAdapter:
          _MismatchedReadBackAdapter(differentJournal.encodeString()),
    );

    expect(
      () => store.save(journal),
      throwsA(isA<KeptMigrationJournalStoreException>()),
    );
  });

  test('22. a malformed persisted journal throws on load', () async {
    SharedPreferences.setMockInitialValues({
      'east_kept_storage_migration_v3_journal': 'not valid json',
    });
    final store = SharedPreferencesKeptMigrationJournalStore();

    expect(
      () => store.load(),
      throwsA(isA<KeptMigrationJournalStoreException>()),
    );
  });
}
