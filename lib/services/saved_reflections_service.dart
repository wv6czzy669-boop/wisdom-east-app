import '../models/favorite_item.dart';
import '../persistence/persistence_operation_coordinator.dart';
import '../persistence/storage_preferences_adapter.dart';

class SavedReflectionsResult {
  const SavedReflectionsResult({
    required this.items,
    required this.limitReached,
  });

  final List<FavoriteItem> items;
  final bool limitReached;
}

class SavedReflectionsService {
  SavedReflectionsService({
    StoragePreferencesAdapter? preferencesAdapter,
    PersistenceOperationCoordinator? operationCoordinator,
    this.freeLimit = 3,
  })  : _preferencesAdapter = preferencesAdapter ?? StoragePreferencesAdapter(),
        _operationCoordinator =
            operationCoordinator ?? PersistenceOperationCoordinator();

  static const String storageKey = 'favorites';
  static const String resourceKey = 'saved_reflections';

  final StoragePreferencesAdapter _preferencesAdapter;
  final PersistenceOperationCoordinator _operationCoordinator;
  final int freeLimit;

  int _generatedIdSerial = 0;

  Future<List<FavoriteItem>> load() {
    return _operationCoordinator.runExclusive<List<FavoriteItem>>(
      resourceKey: resourceKey,
      operation: _loadAndMigrate,
    );
  }

  Future<SavedReflectionsResult> toggle({
    required String text,
    required String date,
    required bool isKeeper,
    String? existingId,
  }) {
    return _operationCoordinator.runExclusive<SavedReflectionsResult>(
      resourceKey: resourceKey,
      operation: () async {
        final items = await _loadAndMigrate();
        final existingIndex = _findExistingIndex(
          items: items,
          text: text,
          existingId: existingId,
        );

        if (existingIndex >= 0) {
          items.removeAt(existingIndex);
        } else if (existingId != null) {
          return SavedReflectionsResult(
            items: List.unmodifiable(items),
            limitReached: false,
          );
        } else {
          // Preserve legacy items without silently deleting user data. Free
          // users may remove entries, but cannot add until below the limit.
          if (!isKeeper && items.length >= freeLimit) {
            return SavedReflectionsResult(
              items: List.unmodifiable(items),
              limitReached: true,
            );
          }

          items.add(
            FavoriteItem(
              id: _createId(),
              text: text,
              date: date,
            ),
          );
        }

        await _persist(items);
        return SavedReflectionsResult(
          items: List.unmodifiable(items),
          limitReached: false,
        );
      },
    );
  }

  int _findExistingIndex({
    required List<FavoriteItem> items,
    required String text,
    required String? existingId,
  }) {
    if (existingId != null) {
      return items.indexWhere((item) => item.id == existingId);
    }

    return items.indexWhere((item) => item.text == text);
  }

  Future<List<FavoriteItem>> _loadAndMigrate() async {
    final saved = await _readRaw();
    if (saved.isEmpty) return <FavoriteItem>[];

    final items = <FavoriteItem>[];
    final usedIds = <String>{};
    var shouldPersistMigrated = false;

    for (var index = 0; index < saved.length; index += 1) {
      final raw = saved[index];
      final decoded = _decodeEntry(raw, index: index);
      if (decoded == null) {
        shouldPersistMigrated = true;
        continue;
      }

      var item = decoded.item;
      if (usedIds.contains(item.id)) {
        item = item.copyWith(
          id: _duplicateIdFor(
            item: item,
            index: index,
          ),
        );
        shouldPersistMigrated = true;
      }

      usedIds.add(item.id);
      items.add(item);
      shouldPersistMigrated =
          shouldPersistMigrated || decoded.requiresMigration;
    }

    if (shouldPersistMigrated) {
      await _persist(items);
    }

    return items;
  }

  Future<List<String>> _readRaw() async {
    try {
      return await _preferencesAdapter.getStringList(storageKey) ?? [];
    } catch (_) {
      return [];
    }
  }

  _DecodedSavedReflection? _decodeEntry(String raw, {required int index}) {
    try {
      if (FavoriteItem.looksLikeCurrentSchema(raw)) {
        return _decodeCurrentEntry(raw, index: index);
      }

      final item = FavoriteItem.decodeLegacy(
        raw,
        id: _legacyIdFor(raw: raw, index: index),
      );
      return _DecodedSavedReflection(
        item: item,
        requiresMigration: true,
      );
    } catch (_) {
      return null;
    }
  }

  _DecodedSavedReflection? _decodeCurrentEntry(
    String raw, {
    required int index,
  }) {
    try {
      final item = FavoriteItem.decodeCurrent(
        raw,
        fallbackId: _legacyIdFor(raw: raw, index: index),
      );
      return _DecodedSavedReflection(
        item: item,
        requiresMigration: item.encode() != raw,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _persist(List<FavoriteItem> items) async {
    try {
      await _preferencesAdapter.setStringList(
        storageKey,
        items.map((item) => item.encode()).toList(growable: false),
      );
    } catch (_) {
      throw StateError('Saved reflections could not be persisted.');
    }
  }

  String _createId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final serial = _generatedIdSerial++;
    return 'sr-v1-$now-$serial';
  }

  String _legacyIdFor({
    required String raw,
    required int index,
  }) {
    return 'legacy-v1-$index-${_stableHash(raw)}';
  }

  String _duplicateIdFor({
    required FavoriteItem item,
    required int index,
  }) {
    return 'duplicate-v1-$index-${_stableHash(item.encode())}';
  }

  String _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}

class _DecodedSavedReflection {
  const _DecodedSavedReflection({
    required this.item,
    required this.requiresMigration,
  });

  final FavoriteItem item;
  final bool requiresMigration;
}
