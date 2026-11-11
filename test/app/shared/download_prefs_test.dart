import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/shared/domain/entities/quality.dart';
import 'package:grabby/app/shared/download_prefs_provider.dart';
import 'package:grabby/core/logging/app_logger.dart';
import 'package:grabby/core/services/storage/app_storage.dart';

import '../../support/memory_storage.dart';

void main() {
  tearDown(AppLogger.reset);

  test('starts with best quality, the Fetchr folder and aria2c off', () {
    final container = containerWith(MemoryStorage());
    addTearDown(container.dispose);

    expect(
      container.read(downloadPrefsProvider),
      const DownloadPrefs(
        quality: Quality.best,
        folder: 'Fetchr',
        useAria2c: false,
      ),
    );
  });

  test('each setter updates the state and persists its own key', () async {
    final storage = MemoryStorage();
    final container = containerWith(storage);
    addTearDown(container.dispose);
    final notifier = container.read(downloadPrefsProvider.notifier);

    await notifier.setQuality(Quality.p720);
    await notifier.setFolder('Clips');
    await notifier.setUseAria2c(true);

    expect(
      container.read(downloadPrefsProvider),
      const DownloadPrefs(
        quality: Quality.p720,
        folder: 'Clips',
        useAria2c: true,
      ),
    );
    expect(storage.values, {
      StorageKeys.defaultQuality: 'p720',
      StorageKeys.saveFolder: 'Clips',
      StorageKeys.useAria2c: 'true',
    });
  });

  test('load restores what the setters saved', () async {
    final storage = MemoryStorage();
    final first = containerWith(storage);
    final setter = first.read(downloadPrefsProvider.notifier);
    await setter.setQuality(Quality.mp3);
    await setter.setFolder('Music clips');
    await setter.setUseAria2c(true);
    first.dispose();

    final second = containerWith(storage);
    addTearDown(second.dispose);
    await second.read(downloadPrefsProvider.notifier).load();

    expect(
      second.read(downloadPrefsProvider),
      const DownloadPrefs(
        quality: Quality.mp3,
        folder: 'Music clips',
        useAria2c: true,
      ),
    );
  });

  test('load falls back to the defaults for missing or bad values', () async {
    final empty = containerWith(MemoryStorage());
    addTearDown(empty.dispose);
    await empty.read(downloadPrefsProvider.notifier).load();
    expect(empty.read(downloadPrefsProvider), const DownloadPrefs());

    final bad = containerWith(
      MemoryStorage({
        StorageKeys.defaultQuality: '4k',
        StorageKeys.saveFolder: '   ',
        StorageKeys.useAria2c: 'yes',
      }),
    );
    addTearDown(bad.dispose);
    await bad.read(downloadPrefsProvider.notifier).load();
    expect(bad.read(downloadPrefsProvider), const DownloadPrefs());
  });

  test('a failing storage never throws and the state still changes', () async {
    AppLogger.overrideForTesting(sink: (_, _, _) {});
    final container = containerWith(ThrowingStorage());
    addTearDown(container.dispose);
    final notifier = container.read(downloadPrefsProvider.notifier);

    await notifier.load();
    await notifier.setQuality(Quality.p480);
    await notifier.setFolder('Clips');
    await notifier.setUseAria2c(true);

    expect(
      container.read(downloadPrefsProvider),
      const DownloadPrefs(
        quality: Quality.p480,
        folder: 'Clips',
        useAria2c: true,
      ),
    );
  });

  test('load after dispose changes nothing and logs nothing', () async {
    final lines = <String>[];
    AppLogger.overrideForTesting(sink: (_, message, _) => lines.add(message));
    final container = containerWith(
      MemoryStorage({StorageKeys.defaultQuality: 'p1080'}),
    );
    final notifier = container.read(downloadPrefsProvider.notifier);

    final loading = notifier.load();
    container.dispose();
    await loading;

    expect(lines, isEmpty);
  });
}
