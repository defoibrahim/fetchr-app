import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/theme/theme_mode_provider.dart';
import 'package:grabby/core/logging/app_logger.dart';
import 'package:grabby/core/services/storage/app_storage.dart';

import '../../support/memory_storage.dart';

void main() {
  tearDown(AppLogger.reset);

  test('setMode changes the mode and persists its name', () async {
    final storage = MemoryStorage();
    final container = containerWith(storage);
    addTearDown(container.dispose);
    final notifier = container.read(themeModeProvider.notifier);

    expect(container.read(themeModeProvider), ThemeMode.system);

    await notifier.setMode(ThemeMode.light);
    expect(container.read(themeModeProvider), ThemeMode.light);
    expect(storage.values[StorageKeys.themeMode], 'light');

    await notifier.setMode(ThemeMode.dark);
    expect(container.read(themeModeProvider), ThemeMode.dark);
    expect(storage.values[StorageKeys.themeMode], 'dark');

    await notifier.setMode(ThemeMode.system);
    expect(container.read(themeModeProvider), ThemeMode.system);
    expect(storage.values[StorageKeys.themeMode], 'system');
  });

  test('load restores the saved mode', () async {
    final container = containerWith(
      MemoryStorage({StorageKeys.themeMode: 'dark'}),
    );
    addTearDown(container.dispose);

    await container.read(themeModeProvider.notifier).load();

    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  test('load falls back to system for a missing or unknown value', () async {
    final unknown = containerWith(
      MemoryStorage({StorageKeys.themeMode: 'sepia'}),
    );
    addTearDown(unknown.dispose);
    await unknown.read(themeModeProvider.notifier).load();
    expect(unknown.read(themeModeProvider), ThemeMode.system);

    final missing = containerWith(MemoryStorage());
    addTearDown(missing.dispose);
    await missing.read(themeModeProvider.notifier).load();
    expect(missing.read(themeModeProvider), ThemeMode.system);
  });

  test('a failing storage never throws and the mode still changes', () async {
    AppLogger.overrideForTesting(sink: (_, _, _) {});
    final container = containerWith(ThrowingStorage());
    addTearDown(container.dispose);
    final notifier = container.read(themeModeProvider.notifier);

    await notifier.load();
    await notifier.setMode(ThemeMode.dark);

    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  test('load after dispose changes nothing and logs nothing', () async {
    final lines = <String>[];
    AppLogger.overrideForTesting(sink: (_, message, _) => lines.add(message));
    final container = containerWith(
      MemoryStorage({StorageKeys.themeMode: 'dark'}),
    );
    final notifier = container.read(themeModeProvider.notifier);

    final loading = notifier.load();
    container.dispose();
    await loading;

    expect(lines, isEmpty);
  });
}
