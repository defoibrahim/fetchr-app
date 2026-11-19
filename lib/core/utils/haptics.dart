import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../logging/app_logger.dart';

/// The app's haptics, for things the user did, never for what happens on its
/// own (progress, a download finishing in the background, a scroll).
abstract final class AppHaptics {
  /// Android's API level once the app has asked native for it; null before
  /// that and off Android.
  static int? androidSdk;

  // Android's CONFIRM and REJECT constants are API 30; below that the engine
  // plays nothing for the notification types.
  static bool get _noNotifications =>
      defaultTargetPlatform == TargetPlatform.android &&
      (androidSdk ?? 30) < 30;

  /// A choice among options: a pill, a filter, a quality, Undo.
  static void select() => _play(HapticFeedback.selectionClick);

  /// Something the user asked for was accepted: a download queued.
  static void confirm() => _play(
    _noNotifications
        ? HapticFeedback.mediumImpact
        : HapticFeedback.successNotification,
  );

  /// A strong action that can still be undone: cancel, delete, stop.
  static void warn() => _play(HapticFeedback.mediumImpact);

  /// Something the user asked for failed.
  static void reject() => _play(
    _noNotifications
        ? HapticFeedback.heavyImpact
        : HapticFeedback.errorNotification,
  );

  static void _play(Future<void> Function() feedback) {
    unawaited(
      feedback().catchError((Object e, StackTrace s) {
        AppLogger.debug('Haptic feedback failed: $e');
      }),
    );
  }
}
