import 'package:shared_preferences/shared_preferences.dart';

import '../models/favorite_item.dart';
import '../models/daily_wisdom_record.dart';
import '../models/pending_daily_wisdom_reveal.dart';

class CorruptDailyWisdomRecordException implements Exception {
  const CorruptDailyWisdomRecordException();
}

class StorageService {
  StorageService({
    Future<void> Function(SharedPreferences prefs, String key)?
        obsoleteKeyRemover,
    Future<void> Function(SharedPreferences prefs, String key)?
        pendingRevealRemover,
  })  : _obsoleteKeyRemover = obsoleteKeyRemover,
        _pendingRevealRemover = pendingRevealRemover;

  static const String _dailyWisdomAccessKey = 'daily_wisdom_access';
  static const String _pendingDailyWisdomRevealKey =
      'pending_daily_wisdom_reveal';
  static const String _legacyDailyWisdomTextKey = 'daily_wisdom_text';
  static const String _legacyWisdomUnlockTimeKey = 'wisdom_unlock_time_ms';
  static const String _obsoleteKeeperDailyWisdomKey =
      'keeper_daily_wisdom_state';
  static const List<String> _obsoleteAccessKeys = [
    _legacyDailyWisdomTextKey,
    _legacyWisdomUnlockTimeKey,
    _obsoleteKeeperDailyWisdomKey,
  ];

  final Future<void> Function(SharedPreferences prefs, String key)?
      _obsoleteKeyRemover;
  final Future<void> Function(SharedPreferences prefs, String key)?
      _pendingRevealRemover;

  SharedPreferences? _cachedPrefs;

  Future<SharedPreferences> getPrefs() async {
    _cachedPrefs ??= await SharedPreferences.getInstance();
    return _cachedPrefs!;
  }

  Future<void> saveFavorites(List<FavoriteItem> favorites) async {
    final prefs = await getPrefs();

    final encodedFavorites = favorites.map((item) => item.encode()).toList();

    final saved = await prefs.setStringList(
      'favorites',
      encodedFavorites,
    );
    if (!saved) {
      throw StateError('Saved reflections could not be persisted.');
    }
  }

  Future<List<FavoriteItem>> loadFavorites({
    required String fallbackDate,
  }) async {
    final prefs = await getPrefs();

    final List<String> saved;
    try {
      saved = prefs.getStringList('favorites') ?? [];
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
    final prefs = await getPrefs();

    late final List<String> archive;
    try {
      archive = prefs.getStringList("daily_wisdom_archive") ?? [];
    } catch (_) {
      archive = [];
    }
    final entry = "$today|||$text";

    final alreadySavedToday = archive.any(
      (item) => item.startsWith("$today|||"),
    );

    if (!alreadySavedToday) {
      archive.insert(0, entry);

      final saved = await prefs.setStringList(
        "daily_wisdom_archive",
        archive.take(90).toList(),
      );
      if (!saved) {
        throw StateError('Daily wisdom archive could not be persisted.');
      }
    }
  }

  Future<DailyWisdomRecord?> loadDailyWisdomRecord({
    required Duration lockDuration,
  }) async {
    final prefs = await getPrefs();
    final String? encodedRecord;
    try {
      encodedRecord = prefs.getString(_dailyWisdomAccessKey);
    } catch (_) {
      throw const CorruptDailyWisdomRecordException();
    }

    if (encodedRecord != null) {
      try {
        final record = DailyWisdomRecord.decode(encodedRecord);
        await _removeObsoleteAccessStateBestEffort(prefs);
        return record;
      } catch (_) {
        throw const CorruptDailyWisdomRecordException();
      }
    }

    await _removeObsoleteAccessStateBestEffort(prefs);
    return null;
  }

  Future<void> saveDailyWisdomRecord(DailyWisdomRecord record) async {
    final prefs = await getPrefs();
    final saved = await prefs.setString(_dailyWisdomAccessKey, record.encode());
    if (!saved) {
      throw StateError('Daily wisdom lock could not be persisted.');
    }

    await _removeObsoleteAccessStateBestEffort(prefs);
  }

  Future<void> clearDailyWisdomRecordBestEffort() async {
    final prefs = await getPrefs();
    try {
      await prefs.remove(_dailyWisdomAccessKey);
    } catch (_) {
      // Corrupt authoritative state should not crash recovery.
    }
  }

  Future<PendingDailyWisdomReveal?> loadPendingDailyWisdomReveal() async {
    final prefs = await getPrefs();
    final String? encodedReveal;

    try {
      encodedReveal = prefs.getString(_pendingDailyWisdomRevealKey);
    } catch (_) {
      await _clearPendingDailyWisdomRevealBestEffort(prefs);
      return null;
    }

    if (encodedReveal == null) return null;

    try {
      return PendingDailyWisdomReveal.decode(encodedReveal);
    } catch (_) {
      await _clearPendingDailyWisdomRevealBestEffort(prefs);
      return null;
    }
  }

  Future<void> savePendingDailyWisdomReveal(
    PendingDailyWisdomReveal reveal,
  ) async {
    final prefs = await getPrefs();
    final saved = await prefs.setString(
      _pendingDailyWisdomRevealKey,
      reveal.encode(),
    );
    if (!saved) {
      throw StateError('Pending daily wisdom reveal could not be persisted.');
    }
  }

  Future<void> clearPendingDailyWisdomReveal() async {
    final prefs = await getPrefs();
    final remover = _pendingRevealRemover;
    if (remover == null) {
      if (!prefs.containsKey(_pendingDailyWisdomRevealKey)) return;
      final removed = await prefs.remove(_pendingDailyWisdomRevealKey);
      if (!removed && prefs.containsKey(_pendingDailyWisdomRevealKey)) {
        throw StateError('Pending daily wisdom reveal could not be cleared.');
      }
    } else {
      await remover(prefs, _pendingDailyWisdomRevealKey);
    }
  }

  Future<bool> getKeeperStatus() async {
    final prefs = await getPrefs();
    try {
      return prefs.getBool("is_premium") ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _clearPendingDailyWisdomRevealBestEffort(
    SharedPreferences prefs,
  ) async {
    try {
      final remover = _pendingRevealRemover;
      if (remover == null) {
        await prefs.remove(_pendingDailyWisdomRevealKey);
      } else {
        await remover(prefs, _pendingDailyWisdomRevealKey);
      }
    } catch (_) {
      // Corrupt pending reveal state is never authoritative access state.
    }
  }

  Future<void> _removeObsoleteAccessStateBestEffort(
    SharedPreferences prefs,
  ) async {
    for (final key in _obsoleteAccessKeys) {
      try {
        final remover = _obsoleteKeyRemover;
        if (remover == null) {
          await prefs.remove(key);
        } else {
          await remover(prefs, key);
        }
      } catch (_) {
        // Obsolete access state must never block the authoritative daily
        // record from loading.
      }
    }
  }
}
