import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/logging/app_logger.dart';
import '../../core/networking/interceptors.dart';
import '../di/core_providers.dart';
import '../shared/download_prefs_provider.dart';
import '../theme/accent_provider.dart';
import '../theme/theme_mode_provider.dart';

/// Everything async that must finish before the first frame.
abstract final class AppInitializer {
  static Future<void> init(ProviderContainer container) async {
    AppInterceptors.onUnauthorized = () =>
        unawaited(_handleUnauthorized(container));

    await (
      container.read(themeModeProvider.notifier).load(),
      container.read(accentProvider.notifier).load(),
      container.read(downloadPrefsProvider.notifier).load(),
    ).wait;
    // Native tints its notifications with it; the first frame never waits for
    // that.
    unawaited(container.read(accentProvider.notifier).sendToNative());

    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_requestPermissions()),
    );
  }

  // Asked once the first frame is up so the system dialogs don't delay it.
  // Denial is fine: downloads still run, and Android 10+ needs no storage
  // access to save through MediaStore.
  static Future<void> _requestPermissions() async {
    try {
      await [
        Permission.notification,
        Permission.storage,
        Permission.videos,
        Permission.audio,
      ].request();
    } catch (e, s) {
      AppLogger.error('Could not request permissions', e, s);
    }
  }

  static Future<void> _handleUnauthorized(ProviderContainer container) async {
    // Navigate to login here once an auth module exists.
    try {
      await container.read(tokenStoreProvider).clear();
      AppLogger.warning('Unauthorized response: stored token cleared.');
    } catch (e, s) {
      AppLogger.error('Could not clear the token after a 401', e, s);
    }
  }
}
