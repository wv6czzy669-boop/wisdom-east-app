import '../models/favorite_item.dart';
import '../persistence/persistence_operation_coordinator.dart';
import '../persistence/storage_preferences_adapter.dart';

class SavedReflectionsResult {
  const SavedReflectionsResult({
    required this.items,
    required this.limitReached,
    this.reflectionLimitReached = false,
  });

  final List<FavoriteItem> items;
  final bool limitReached;
  final bool reflectionLimitReached;
}

class RemovedSavedReflection {
  const RemovedSavedReflection({
    required this.item,
    required this.originalIndex,
    required this.items,
  });

  final FavoriteItem item;
  final int originalIndex;
  final List<FavoriteItem> items;
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
  static const int maximumReflectionLength = 250;
  static const int freeReflectionLimit = 3;

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

  Future<SavedReflectionsResult> saveReflection({
    required String itemId,
    required String reflection,
    required bool isKeeper,
    DateTime? reflectedAt,
  }) {
    return _operationCoordinator.runExclusive<SavedReflectionsResult>(
      resourceKey: resourceKey,
      operation: () async {
        final normalized = reflection.trim();
        if (normalized.isEmpty) {
          throw ArgumentError.value(
            reflection,
            'reflection',
            'Reflection cannot be empty.',
          );
        }
        if (normalized.length > maximumReflectionLength) {
          throw ArgumentError.value(
            reflection,
            'reflection',
            'Reflection cannot exceed $maximumReflectionLength characters.',
          );
        }

        final items = await _loadAndMigrate();
        final itemIndex = items.indexWhere((item) => item.id == itemId);
        if (itemIndex < 0) {
          throw StateError('The kept wisdom no longer exists.');
        }

        final existing = items[itemIndex];
        if (!existing.hasReflection &&
            !isKeeper &&
            items.where((item) => item.hasReflection).length >=
                freeReflectionLimit) {
          return SavedReflectionsResult(
            items: List.unmodifiable(items),
            limitReached: false,
            reflectionLimitReached: true,
          );
        }

        items[itemIndex] = existing.copyWith(
          reflection: normalized,
          reflectedAt: (reflectedAt ?? DateTime.now()).toIso8601String(),
        );
        await _persist(items);
        return SavedReflectionsResult(
          items: List.unmodifiable(items),
          limitReached: false,
        );
      },
    );
  }

  Future<List<FavoriteItem>> deleteReflection({
    required String itemId,
  }) {
    return _operationCoordinator.runExclusive<List<FavoriteItem>>(
      resourceKey: resourceKey,
      operation: () async {
        final items = await _loadAndMigrate();
        final itemIndex = items.indexWhere((item) => item.id == itemId);
        if (itemIndex < 0) {
          throw StateError('The kept wisdom no longer exists.');
        }

        if (!items[itemIndex].hasReflection) {
          return List.unmodifiable(items);
        }

        items[itemIndex] = items[itemIndex].copyWith(clearReflection: true);
        await _persist(items);
        return List.unmodifiable(items);
      },
    );
  }

  Future<RemovedSavedReflection?> remove({
    required String itemId,
  }) {
    return _operationCoordinator.runExclusive<RemovedSavedReflection?>(
      resourceKey: resourceKey,
      operation: () async {
        final items = await _loadAndMigrate();
        final itemIndex = items.indexWhere((item) => item.id == itemId);
        if (itemIndex < 0) return null;

        final removed = items.removeAt(itemIndex);
        await _persist(items);
        return RemovedSavedReflection(
          item: removed,
          originalIndex: itemIndex,
          items: List.unmodifiable(items),
        );
      },
    );
  }

  Future<List<FavoriteItem>> restore(RemovedSavedReflection removed) {
    return _operationCoordinator.runExclusive<List<FavoriteItem>>(
      resourceKey: resourceKey,
      operation: () async {
        final items = await _loadAndMigrate();
        if (items.any((item) => item.id == removed.item.id)) {
          return List.unmodifiable(items);
        }

        final insertionIndex = removed.originalIndex.clamp(0, items.length);
        items.insert(insertionIndex, removed.item);
        await _persist(items);
        return List.unmodifiable(items);
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
