import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../core/services/storage/app_storage.dart';
import '../../core/theme/app_palette.dart';
import '../di/core_providers.dart';
import '../shared/save_quietly.dart';

class AccentNotifier extends Notifier<Color> {
  @override
  Color build() => AppPalette.defaultAccent;

  Future<void> load() async {
    try {
      final saved = await ref
          .read(appStorageProvider)
          .getString(StorageKeys.accent);
      if (!ref.mounted) return;
      state = AppPalette.accents
          .map((o) => o.color)
          .firstWhere(
            (c) => '${c.toARGB32()}' == saved,
            orElse: () => AppPalette.defaultAccent,
          );
    } catch (e, s) {
      AppLogger.error('Could not read the saved accent', e, s);
    }
  }

  Future<void> setAccent(Color accent) async {
    state = accent;
    // Neither call throws, so one failing never skips the other.
    await Future.wait([
      saveQuietly(
        ref,
        StorageKeys.accent,
        '${accent.toARGB32()}',
        'the accent',
      ),
      sendToNative(),
    ]);
  }

  /// Tells native the current accent, which tints its notifications. A failure
  /// is logged and costs only the tint.
  Future<void> sendToNative() async {
    try {
      await ref.read(fetchrHostApiProvider).setAccentColor(state.toARGB32());
    } catch (e, s) {
      AppLogger.error('Could not send the accent to native', e, s);
    }
  }
}

final accentProvider = NotifierProvider<AccentNotifier, Color>(
  AccentNotifier.new,
);
