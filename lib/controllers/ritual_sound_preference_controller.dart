import 'package:flutter/foundation.dart';
import '../persistence/storage_preferences_adapter.dart';

enum RitualSoundMode { sound, silent }

/// Device-local preference. Applies immediately; ordered writes keep the last
/// selection durable even when the user changes it quickly.
class RitualSoundPreferenceController extends ChangeNotifier {
  RitualSoundPreferenceController({StoragePreferencesAdapter? storage})
      : _storage = storage ?? StoragePreferencesAdapter();
  static const preferenceKey = 'east_ritual_sound';
  final StoragePreferencesAdapter _storage;
  RitualSoundMode _mode = RitualSoundMode.sound;
  Future<void>? _loadFuture;
  Future<void> _writeTail = Future.value();
  bool _changedDuringLoad = false;
  bool _loaded = false;
  bool _saveFailed = false;
  int _revision = 0;
  bool _disposed = false;

  RitualSoundMode get mode => _mode;
  bool get canPlay => _loaded && _mode == RitualSoundMode.sound;
  bool get saveFailed => _saveFailed;

  Future<void> load() => _loadFuture ??= _load();
  Future<void> _load() async {
    try {
      final raw = await _storage.getString(preferenceKey);
      if (!_changedDuringLoad) {
        _mode =
            raw == 'silent' ? RitualSoundMode.silent : RitualSoundMode.sound;
      }
    } catch (_) {
      // A missing preference never blocks the ritual.
    }
    _loaded = true;
    if (!_disposed) notifyListeners();
  }

  Future<void> setMode(RitualSoundMode mode) {
    _changedDuringLoad = true;
    _loaded = true;
    _mode = mode;
    _saveFailed = false;
    final revision = ++_revision;
    notifyListeners();
    return _writeTail = _writeTail.then((_) async {
      try {
        await _storage.setString(preferenceKey, mode.name);
      } catch (_) {
        if (!_disposed && revision == _revision) {
          _saveFailed = true;
          notifyListeners();
        }
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
