import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/services/storage/app_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  late SharedPrefsAppStorage storage;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    storage = SharedPrefsAppStorage(SharedPreferencesAsync());
  });

  test('getString is null for a missing key', () async {
    expect(await storage.getString('missing'), isNull);
  });

  test('setString then getString round-trips', () async {
    await storage.setString(StorageKeys.themeMode, 'dark');

    expect(await storage.getString(StorageKeys.themeMode), 'dark');
  });

  test('remove deletes the key', () async {
    await storage.setString('k', 'v');
    await storage.remove('k');

    expect(await storage.getString('k'), isNull);
  });

  test('the theme mode key is theme_mode', () {
    expect(StorageKeys.themeMode, 'theme_mode');
  });
}
