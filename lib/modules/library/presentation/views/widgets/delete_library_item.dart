import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/shared/platform_traits_provider.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../core/widgets/app_snackbar.dart';
import '../../../../../core/widgets/confirm_dialog.dart';
import '../../../../../core/widgets/undoable_delete.dart';
import '../../../domain/entities/library_item.dart';
import '../../../domain/extensions/library_item_extensions.dart';
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
  final traits = ref.read(platformTraitsProvider);
  final confirmed = await confirmDeleteFile(
    context,
    item.name,
    deviceWord: traits.deviceWord,
    galleryWord: traits.galleryWord,
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

/// One question for the whole playlist, then every file goes. No Undo: a
/// playlist is too much to hold back for five seconds.
Future<void> deleteLibraryPlaylist(
  BuildContext context,
  WidgetRef ref,
  String name,
  List<LibraryItem> items,
) async {
  final confirmed = await showConfirmDialog(
    context,
    title: 'Delete this playlist?',
    message:
        'All ${plural(items.length, 'file')} of "$name" will be removed from '
        'your ${ref.read(platformTraitsProvider).deviceWord}. '
        "This can't be undone.",
    confirmLabel: 'Delete',
    meta: (plural(items.length, 'file'), formatBytes(items.totalBytes)),
  );
  if (!confirmed || !context.mounted) return;
  await AppSnackbar.showFailure(
    context,
    ref.read(libraryNotifierProvider.notifier).deleteAll(items),
  );
}
