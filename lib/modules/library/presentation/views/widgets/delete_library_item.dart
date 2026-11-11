import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/utils/formatters.dart';
import '../../../../../core/widgets/confirm_dialog.dart';
import '../../../../../core/widgets/undoable_delete.dart';
import '../../../domain/entities/library_item.dart';
import '../../formatters/library_item_formatter.dart';
import '../../providers/library_notifier.dart';

/// Asks first, then hides the item and offers Undo for five seconds before the
/// file goes. The Library card and the Player share it. [onConfirmed] runs
/// once the user has said yes and before the item is hidden: the Player leaves
/// its screen there.
Future<void> deleteLibraryItem(
  BuildContext context,
  WidgetRef ref,
  LibraryItem item, {
  VoidCallback? onConfirmed,
}) async {
  final confirmed = await confirmDeleteFile(
    context,
    item.name,
    meta: (item.formatLabel, formatBytes(item.sizeBytes)),
  );
  if (!confirmed || !context.mounted) return;

  // Both come before onConfirmed, which can unmount the caller and with it the
  // ref. The container's listener (not the widget's, which dies with it) keeps
  // the autoDispose notifier alive through the Undo window; without it a
  // Player opened from another tab would delete nothing.
  final notifier = ref.read(libraryNotifierProvider.notifier);
  final keepAlive = ProviderScope.containerOf(
    context,
    listen: false,
  ).listen(libraryNotifierProvider, (_, _) {});
  onConfirmed?.call();
  try {
    await runUndoableDelete(
      context,
      message: 'Deleted',
      hide: () => notifier.hide(item),
      restore: () => notifier.restore(item),
      commit: () => notifier.delete(item),
    );
  } finally {
    keepAlive.close();
  }
}
