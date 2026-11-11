import 'dart:async';

import 'package:flutter/material.dart';

import '../errors/result.dart';
import '../gen/assets.gen.dart';
import '../theme/app_spacing.dart';
import '../theme/theme_extensions.dart';
import '../utils/scale.dart';
import 'app_icon.dart';

enum SnackType { info, success, error }

/// Colour, border, shape and text style come from `SnackBarThemeData`; this
/// only lays out the icon and the message.
abstract final class AppSnackbar {
  static const undoDuration = Duration(seconds: 5);
  static const _defaultDuration = Duration(seconds: 4);

  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> show(
    BuildContext context,
    String message, {
    SnackType type = SnackType.info,
    (String, VoidCallback)? action,
    Duration duration = _defaultDuration,
  }) {
    final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
    final (label, onSelected) = action ?? (null, null);
    return messenger.showSnackBar(
      SnackBar(
        duration: duration,
        // Flutter defaults persist to true when there is an action, which would
        // keep the snackbar up until it is dismissed by hand.
        persist: false,
        content: _content(context, message, type),
        action: label == null
            ? null
            : SnackBarAction(label: label, onPressed: onSelected!),
      ),
    );
  }

  /// True only when the user tapped Undo; a timeout, a swipe or another
  /// snackbar replacing this one all give false.
  static Future<bool> showUndo(BuildContext context, String message) async {
    final closed = show(
      context,
      message,
      action: ('Undo', () {}),
      duration: undoDuration,
    ).closed;
    return await closed == SnackBarClosedReason.action;
  }

  static Widget _content(BuildContext context, String message, SnackType type) {
    final tokens = context.tokens;
    final (icon, tint) = switch (type) {
      SnackType.info => (Assets.icons.alertCircle, tokens.textMuted),
      SnackType.success => (Assets.icons.check, tokens.accent),
      SnackType.error => (Assets.icons.alertCircle, tokens.error),
    };
    return Row(
      spacing: Gap.md.w,
      children: [
        AppIcon(icon, size: AppSizes.iconStatus.r, color: tint),
        Expanded(child: Text(message)),
      ],
    );
  }

  // The context can be gone by the time the action finishes.
  static Future<void> showFailure(
    BuildContext context,
    FutureOr<Result<Object?>> result,
  ) async {
    final resolved = await result;
    if (!context.mounted) return;
    if (resolved case Err(:final failure)) {
      show(context, failure.message, type: SnackType.error);
    }
  }
}
