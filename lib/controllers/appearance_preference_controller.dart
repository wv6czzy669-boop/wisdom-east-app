import 'package:flutter/material.dart';

import '../persistence/storage_preferences_adapter.dart';

/// EAST.'s three Appearance options. Persisted as the lowercase enum name
/// (`system`/`light`/`dark`) -- see [AppearancePreferenceController.load].
enum EastAppearanceMode { system, light, dark }

/// Owns EAST.'s explicit Appearance override, independent of
/// [LocalePreferenceController] (see `locale_preference_controller.dart`,
/// this class's direct architectural template).
///
/// [EastAppearanceMode.light] is the durable default for a user who has
/// never chosen -- a fresh install, and any absent or unrecognized/corrupt
/// stored value, both resolve to Light, never crashing startup. This is a
/// deliberate product decision distinct from [ThemeMode.system]:
/// [EastAppearanceMode.system] is still a real, selectable option (and,
/// once explicitly chosen, is itself durably persisted -- see [setMode] --
/// so it is never silently collapsed back into Light), it is simply no
/// longer the *default* a never-chosen user gets.
class AppearancePreferenceController extends ChangeNotifier {
  AppearancePreferenceController({StoragePreferencesAdapter? storage})
      : _storage = storage ?? StoragePreferencesAdapter();

  static const String preferenceKey = 'east_appearance_preference';

  final StoragePreferencesAdapter _storage;

  EastAppearanceMode _mode = EastAppearanceMode.light;
  Future<void>? _loadFuture;
  bool _changedDuringLoad = false;

  EastAppearanceMode get mode => _mode;

  bool get isSystemDefault => _mode == EastAppearanceMode.system;

  /// Flutter's [ThemeMode] equivalent of [mode], for direct use as
  /// `MaterialApp.themeMode`.
  ThemeMode get themeMode {
    switch (_mode) {
      case EastAppearanceMode.system:
        return ThemeMode.system;
      case EastAppearanceMode.light:
        return ThemeMode.light;
      case EastAppearanceMode.dark:
        return ThemeMode.dark;
    }
  }

  /// Restores the saved override once, safely treating a missing/malformed
  /// stored value as Light.
  Future<void> load() {
    return _loadFuture ??= _load();
  }

  Future<void> _load() async {
    String? raw;
    try {
      raw = await _storage.getString(preferenceKey);
    } catch (_) {
      // An appearance preference must never block application startup.
      return;
    }

    if (_changedDuringLoad) return;

    final resolved = _parse(raw);
    if (resolved == _mode) return;

    _mode = resolved;
    notifyListeners();
  }

  /// Applies [mode] immediately, then persists it without allowing a
  /// storage failure to interrupt the active session.
  ///
  /// Every one of the three options -- including System Default -- is
  /// written out explicitly. System Default is a real, durable user
  /// choice, not merely "no preference yet" (that absent-key state now
  /// means Light -- see [_parse]), so choosing it must never be
  /// indistinguishable from never having chosen anything.
  Future<void> setMode(EastAppearanceMode mode) async {
    _changedDuringLoad = true;

    if (_mode != mode) {
      _mode = mode;
      notifyListeners();
    }

    try {
      await _storage.setString(preferenceKey, _encode(mode));
    } catch (_) {
      // The in-memory choice remains stable for this session. A future
      // launch simply falls back to the safely readable stored value.
    }
  }

  static EastAppearanceMode _parse(String? raw) {
    switch (raw) {
      case 'light':
        return EastAppearanceMode.light;
      case 'dark':
        return EastAppearanceMode.dark;
      case 'system':
        return EastAppearanceMode.system;
      default:
        // Absent (never chosen) or unrecognized/corrupt (null, a future
        // value this build does not know about): EAST.'s locked default
        // is Light, never a crash.
        return EastAppearanceMode.light;
    }
  }

  static String _encode(EastAppearanceMode mode) {
    switch (mode) {
      case EastAppearanceMode.light:
        return 'light';
      case EastAppearanceMode.dark:
        return 'dark';
      case EastAppearanceMode.system:
        return 'system';
    }
  }
}
