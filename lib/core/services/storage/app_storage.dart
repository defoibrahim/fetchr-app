import 'package:shared_preferences/shared_preferences.dart';

abstract interface class AppStorage {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
  Future<void> remove(String key);
}

class SharedPrefsAppStorage implements AppStorage {
  SharedPrefsAppStorage(this._prefs);

  final SharedPreferencesAsync _prefs;

  @override
  Future<String?> getString(String key) => _prefs.getString(key);

  @override
  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);

  @override
  Future<void> remove(String key) => _prefs.remove(key);
}

abstract final class StorageKeys {
  static const themeMode = 'theme_mode';
  static const accent = 'accent';
  static const defaultQuality = 'default_quality';
  static const saveFolder = 'save_folder';
  static const useAria2c = 'use_aria2c';
}
