import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/persistence/legacy_favorites_store.dart';
import 'package:wisdom_app/persistence/storage_preferences_adapter.dart';

class _FailingRemoveAdapter extends StoragePreferencesAdapter {
  @override
  Future<void> remove(String key) {
    throw StateError('Simulated remove failure.');
  }
}

/// Simulates a platform that reports `remove` succeeded (no exception) but
/// the key is somehow still present afterward.
class _FalseSuccessRemoveAdapter extends StoragePreferencesAdapter {
  @override
  Future<void> remove(String key) async {
    // Does nothing: the key remains present, but no exception is thrown,
    // simulating a platform that silently no-ops instead of reporting
    // failure.
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('11. absent key returns null', () async {
    final store = SharedPreferencesLegacyFavoritesStore();

    expect(await store.containsLegacyData(), isFalse);
    expect(await store.readRawEntries(), isNull);
  });

  test('12. present empty StringList returns an empty list', () async {
    SharedPreferences.setMockInitialValues({'favorites': <String>[]});
    final store = SharedPreferencesLegacyFavoritesStore();

    expect(await store.containsLegacyData(), isTrue);
    expect(await store.readRawEntries(), isEmpty);
  });

  test('13. raw order and strings are preserved exactly', () async {
    final entries = [
      'first|||text one',
      '{"id":"a","date":"d","text":"t"}',
      ''
    ];
    SharedPreferences.setMockInitialValues({'favorites': entries});
    final store = SharedPreferencesLegacyFavoritesStore();

    final raw = await store.readRawEntries();

    expect(raw, entries);
  });

  test('14. a wrongly-typed stored value throws rather than coercing',
      () async {
    SharedPreferences.setMockInitialValues({'favorites': 'not-a-list'});
    final store = SharedPreferencesLegacyFavoritesStore();

    expect(
      () => store.readRawEntries(),
      throwsA(isA<LegacyFavoritesStoreException>()),
    );
  });

  test('15. successful removal is verified and reported', () async {
    SharedPreferences.setMockInitialValues({
      'favorites': ['a'],
    });
    final store = SharedPreferencesLegacyFavoritesStore();

    await store.removeAndVerify();

    expect(await store.containsLegacyData(), isFalse);
  });

  test('16. a remove failure throws', () async {
    SharedPreferences.setMockInitialValues({
      'favorites': ['a'],
    });
    final store = SharedPreferencesLegacyFavoritesStore(
      preferencesAdapter: _FailingRemoveAdapter(),
    );

    expect(
      () => store.removeAndVerify(),
      throwsA(isA<LegacyFavoritesStoreException>()),
    );
  });

  test('17. the key still present after remove throws', () async {
    SharedPreferences.setMockInitialValues({
      'favorites': ['a'],
    });
    final store = SharedPreferencesLegacyFavoritesStore(
      preferencesAdapter: _FalseSuccessRemoveAdapter(),
    );

    expect(
      () => store.removeAndVerify(),
      throwsA(isA<LegacyFavoritesStoreException>()),
    );
  });
}
