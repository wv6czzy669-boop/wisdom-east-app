import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisdom_app/persistence/storage_preferences_adapter.dart';
import 'package:wisdom_app/services/journal_owner_service.dart';

import 'journal_owner_test_helpers.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('no name and prompt unhandled before anything is saved', () async {
    final service =
        JournalOwnerService(ownerStore: InMemoryJournalOwnerStore());

    expect(await service.loadName(), isNull);
    expect(await service.hasHandledNamePrompt(), isFalse);
  });

  test(
      'saveName trims surrounding whitespace, persists it, and marks the '
      'prompt handled', () async {
    final service =
        JournalOwnerService(ownerStore: InMemoryJournalOwnerStore());

    await service.saveName('  Doğukan Işık  ');

    expect(await service.loadName(), 'Doğukan Işık');
    expect(await service.hasHandledNamePrompt(), isTrue);
  });

  test(
      'saveName with a blank/whitespace-only name behaves exactly like '
      'skip -- no name is ever stored', () async {
    final service =
        JournalOwnerService(ownerStore: InMemoryJournalOwnerStore());

    await service.saveName('   ');

    expect(await service.loadName(), isNull);
    expect(await service.hasHandledNamePrompt(), isTrue);
  });

  test('skip marks the prompt handled with no name saved', () async {
    final service =
        JournalOwnerService(ownerStore: InMemoryJournalOwnerStore());

    await service.skip();

    expect(await service.loadName(), isNull);
    expect(await service.hasHandledNamePrompt(), isTrue);
  });

  test(
      'clearName removes a saved name without affecting whether the '
      'prompt has been handled', () async {
    final service =
        JournalOwnerService(ownerStore: InMemoryJournalOwnerStore());
    await service.saveName('A Name');

    await service.clearName();

    expect(await service.loadName(), isNull);
    expect(await service.hasHandledNamePrompt(), isTrue);
  });

  test(
      'a fresh instance backed by the same persisted store sees the same '
      'state -- survives relaunch', () async {
    final ownerStore = InMemoryJournalOwnerStore();
    final first = JournalOwnerService(ownerStore: ownerStore);
    await first.saveName('Persisted Name');

    final relaunched = JournalOwnerService(ownerStore: ownerStore);

    expect(await relaunched.loadName(), 'Persisted Name');
    expect(await relaunched.hasHandledNamePrompt(), isTrue);
  });

  test(
      'the name is never CloudKit-synced or analytics-tracked -- it is '
      'migrates out of SharedPreferences after protected persistence is '
      'verified', () async {
    final ownerStore = InMemoryJournalOwnerStore();
    final service = JournalOwnerService(ownerStore: ownerStore);
    await service.saveName('Private Name');

    final prefs = await SharedPreferences.getInstance();
    expect(ownerStore.name, 'Private Name');
    expect(prefs.containsKey(JournalOwnerService.nameKey), isFalse);
  });

  test('legacy name is deleted only after protected migration verifies',
      () async {
    SharedPreferences.setMockInitialValues({
      JournalOwnerService.nameKey: 'Legacy Name',
    });
    final ownerStore = InMemoryJournalOwnerStore();
    final service = JournalOwnerService(ownerStore: ownerStore);

    expect(await service.loadName(), 'Legacy Name');
    expect(ownerStore.name, 'Legacy Name');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(JournalOwnerService.nameKey), isFalse);
  });

  test('failed protected migration preserves and returns the legacy name',
      () async {
    SharedPreferences.setMockInitialValues({
      JournalOwnerService.nameKey: 'Only Copy',
    });
    final ownerStore = InMemoryJournalOwnerStore()..failWrites = true;
    final service = JournalOwnerService(ownerStore: ownerStore);

    expect(await service.loadName(), 'Only Copy');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(JournalOwnerService.nameKey), 'Only Copy');
  });

  group('persistence failures never throw', () {
    test(
        'loadName/hasHandledNamePrompt/saveName/skip/clearName all fail '
        'safe on a throwing adapter', () async {
      final service = JournalOwnerService(
        preferencesAdapter: _ThrowingPreferencesAdapter(),
        ownerStore: InMemoryJournalOwnerStore()..failReads = true,
      );

      expect(await service.loadName(), isNull);
      expect(await service.hasHandledNamePrompt(), isFalse);
      await expectLater(service.saveName('Name'), completes);
      await expectLater(service.skip(), completes);
      await expectLater(service.clearName(), completes);
    });
  });
}

class _ThrowingPreferencesAdapter extends StoragePreferencesAdapter {
  @override
  Future<String?> getString(String key) async {
    throw StateError('read failure');
  }

  @override
  Future<void> setString(String key, String value) async {
    throw StateError('write failure');
  }

  @override
  Future<bool?> getBool(String key) async {
    throw StateError('read failure');
  }

  @override
  Future<void> setBool(String key, bool value) async {
    throw StateError('write failure');
  }

  @override
  Future<void> remove(String key) async {
    throw StateError('remove failure');
  }
}
