import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../core/services/storage/app_storage.dart';
import '../di/core_providers.dart';
import 'domain/entities/quality.dart';
import 'save_quietly.dart';

class DownloadPrefs extends Equatable {
  const DownloadPrefs({
    this.quality = Quality.best,
    this.folder = defaultFolder,
    this.useAria2c = false,
  });

  static const defaultFolder = 'Fetchr';

  final Quality quality;
  final String folder;
  final bool useAria2c;

  DownloadPrefs copyWith({Quality? quality, String? folder, bool? useAria2c}) =>
      DownloadPrefs(
        quality: quality ?? this.quality,
        folder: folder ?? this.folder,
        useAria2c: useAria2c ?? this.useAria2c,
      );

  @override
  List<Object?> get props => [quality, folder, useAria2c];
}

class DownloadPrefsNotifier extends Notifier<DownloadPrefs> {
  @override
  DownloadPrefs build() => const DownloadPrefs();

  Future<void> load() async {
    try {
      final storage = ref.read(appStorageProvider);
      final (quality, folder, aria2c) = await (
        storage.getString(StorageKeys.defaultQuality),
        storage.getString(StorageKeys.saveFolder),
        storage.getString(StorageKeys.useAria2c),
      ).wait;
      if (!ref.mounted) return;
      state = DownloadPrefs(
        quality: Quality.values.asNameMap()[quality] ?? Quality.best,
        folder: folder == null || folder.trim().isEmpty
            ? DownloadPrefs.defaultFolder
            : folder,
        useAria2c: aria2c == 'true',
      );
    } catch (e, s) {
      AppLogger.error('Could not read the saved download settings', e, s);
    }
  }

  Future<void> setQuality(Quality quality) {
    state = state.copyWith(quality: quality);
    return _save(StorageKeys.defaultQuality, quality.name);
  }

  Future<void> setFolder(String folder) {
    state = state.copyWith(folder: folder);
    return _save(StorageKeys.saveFolder, folder);
  }

  Future<void> setUseAria2c(bool enabled) {
    state = state.copyWith(useAria2c: enabled);
    return _save(StorageKeys.useAria2c, '$enabled');
  }

  Future<void> _save(String key, String value) =>
      saveQuietly(ref, key, value, 'the download settings');
}

final downloadPrefsProvider =
    NotifierProvider<DownloadPrefsNotifier, DownloadPrefs>(
      DownloadPrefsNotifier.new,
    );
