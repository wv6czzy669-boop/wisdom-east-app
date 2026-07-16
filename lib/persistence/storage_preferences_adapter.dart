import 'package:shared_preferences/shared_preferences.dart';

class PersistenceException implements Exception {
  const PersistenceException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() {
    final cause = this.cause;
    if (cause == null) return 'PersistenceException: $message';
    return 'PersistenceException: $message ($cause)';
  }
}

class StoragePreferencesAdapter {
  StoragePreferencesAdapter({
    Future<SharedPreferences> Function()? preferencesProvider,
  }) : _preferencesProvider =
            preferencesProvider ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _preferencesProvider;
  SharedPreferences? _cachedPreferences;

  Future<SharedPreferences> get preferences async {
    _cachedPreferences ??= await _preferencesProvider();
    return _cachedPreferences!;
  }

  Future<bool> containsKey(String key) async {
    try {
      return (await preferences).containsKey(key);
    } catch (error) {
      throw PersistenceException('Could not check key: $key', error);
    }
  }

  Future<String?> getString(String key) async {
    try {
      return (await preferences).getString(key);
    } catch (error) {
      throw PersistenceException('Could not read string: $key', error);
    }
  }

  Future<List<String>?> getStringList(String key) async {
    try {
      return (await preferences).getStringList(key);
    } catch (error) {
      throw PersistenceException('Could not read string list: $key', error);
    }
  }

  Future<bool?> getBool(String key) async {
    try {
      return (await preferences).getBool(key);
    } catch (error) {
      throw PersistenceException('Could not read bool: $key', error);
    }
  }

  Future<int?> getInt(String key) async {
    try {
      return (await preferences).getInt(key);
    } catch (error) {
      throw PersistenceException('Could not read int: $key', error);
    }
  }

  Future<void> setString(String key, String value) async {
    try {
      final saved = await (await preferences).setString(key, value);
      if (!saved) {
        throw PersistenceException('Could not persist string: $key');
      }
    } on PersistenceException {
      rethrow;
    } catch (error) {
      throw PersistenceException('Could not persist string: $key', error);
    }
  }

  Future<void> setStringList(String key, List<String> value) async {
    try {
      final saved = await (await preferences).setStringList(key, value);
      if (!saved) {
        throw PersistenceException('Could not persist string list: $key');
      }
    } on PersistenceException {
      rethrow;
    } catch (error) {
      throw PersistenceException('Could not persist string list: $key', error);
    }
  }

  Future<void> setBool(String key, bool value) async {
    try {
      final saved = await (await preferences).setBool(key, value);
      if (!saved) {
        throw PersistenceException('Could not persist bool: $key');
      }
    } on PersistenceException {
      rethrow;
    } catch (error) {
      throw PersistenceException('Could not persist bool: $key', error);
    }
  }

  Future<void> setInt(String key, int value) async {
    try {
      final saved = await (await preferences).setInt(key, value);
      if (!saved) {
        throw PersistenceException('Could not persist int: $key');
      }
    } on PersistenceException {
      rethrow;
    } catch (error) {
      throw PersistenceException('Could not persist int: $key', error);
    }
  }

  Future<void> remove(String key) async {
    try {
      final prefs = await preferences;
      if (!prefs.containsKey(key)) return;
      final removed = await prefs.remove(key);
      if (!removed && prefs.containsKey(key)) {
        throw PersistenceException('Could not remove key: $key');
      }
    } on PersistenceException {
      rethrow;
    } catch (error) {
      throw PersistenceException('Could not remove key: $key', error);
    }
  }
}
