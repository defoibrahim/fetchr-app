import 'package:flutter/material.dart';

import '../errors/result.dart';
import 'app_snackbar.dart';

/// Hides the item at once, offers Undo for five seconds and commits the delete
/// when the snackbar closes any other way. A declined commit or an [Err]
/// restores the item; an [Err] also shows its message.
///
/// Hiding usually unmounts the caller's tile, so [context] is dead after
/// [hide]. Every snackbar goes through the root navigator's context instead: it
/// outlives the tile and sits below the theme and the ScaffoldMessenger (a
/// ScaffoldMessengerState's own context cannot find its own scope).
Future<void> runUndoableDelete(
  BuildContext context, {
  required String message,
  required VoidCallback hide,
  required VoidCallback restore,
  required Future<Result<bool>> Function() commit,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  hide();
  if (await AppSnackbar.showUndo(navigator.context, message)) {
    restore();
    return;
  }
  switch (await commit()) {
    case Ok(value: true):
      break;
    case Ok():
      restore();
    case Err(:final failure):
      restore();
      if (navigator.mounted) {
        AppSnackbar.show(
          navigator.context,
          failure.message,
          type: SnackType.error,
        );
      }
  }
}
