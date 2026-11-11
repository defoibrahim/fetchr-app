import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../core/services/storage/app_storage.dart';
import '../di/core_providers.dart';
import '../shared/save_quietly.dart';

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  Future<void> load() async {
    try {
      final saved = await ref
          .read(appStorageProvider)
          .getString(StorageKeys.themeMode);
      if (!ref.mounted) return;
      state = ThemeMode.values.asNameMap()[saved] ?? ThemeMode.system;
    } catch (e, s) {
      AppLogger.error('Could not read the saved theme mode', e, s);
    }
  }

  Future<void> setMode(ThemeMode mode) {
    state = mode;
    return saveQuietly(ref, StorageKeys.themeMode, mode.name, 'the theme mode');
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
