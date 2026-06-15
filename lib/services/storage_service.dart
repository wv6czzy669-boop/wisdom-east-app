import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  SharedPreferences? _cachedPrefs;

  Future<SharedPreferences> getPrefs() async {
    _cachedPrefs ??= await SharedPreferences.getInstance();
    return _cachedPrefs!;
  }
}
