import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/shared/download_prefs_provider.dart';
import '../../../../core/errors/result.dart';
import '../../di/library_providers.dart';
import '../../domain/entities/library_item.dart';

class LibraryNotifier extends AsyncNotifier<List<LibraryItem>> {
  // Uris waiting out their Undo window or already deleted. They live here, not
  // in state, so a reload does not bring them back; a deleted uri never returns
  // from MediaStore, so it stays in the set.
  var _hidden = const <String>{};
  List<LibraryItem>? _loaded;

  @override
  Future<List<LibraryItem>> build() async {
    final folder = ref.watch(downloadPrefsProvider.select((p) => p.folder));
    final result = await ref.watch(getLibraryUseCaseProvider)(folder);
    final loaded = _loaded = result.getOrThrow();
    return _visible(loaded);
  }

  // The list stays on screen until the reload lands. A failed reload is in
  // state for the view to show, so it must not also throw into the refresh
  // indicator.
  Future<void> refresh() async {
    ref.invalidateSelf();
    try {
      await future;
    } catch (_) {}
  }

  void hide(LibraryItem item) {
    _hidden = {..._hidden, item.uri};
    _publish();
  }

  void restore(LibraryItem item) {
    _hidden = _hidden.difference({item.uri});
    _publish();
  }

  // Ok(false) means the user declined the system dialog: the file is still
  // there. The item stays hidden either way; the caller restores it.
  Future<Result<bool>> delete(LibraryItem item) async {
    if (!ref.mounted) return const Ok(false);
    return ref.read(deleteLibraryItemsUseCaseProvider)(item.uri);
  }

  Future<Result<void>> share(LibraryItem item) =>
      ref.read(shareLibraryItemUseCaseProvider)(item);

  Future<Result<void>> openFolder(LibraryItem item) =>
      ref.read(openLibraryFolderUseCaseProvider)(item.uri);

  List<LibraryItem> _visible(List<LibraryItem> items) => _hidden.isEmpty
      ? items
      : [
          for (final item in items)
            if (!_hidden.contains(item.uri)) item,
        ];

  // Called after awaits by the undo flow, when the provider may be gone. A
  // failed reload keeps its error for the view; the next reload applies
  // _hidden itself.
  void _publish() {
    final loaded = _loaded;
    if (loaded == null || !ref.mounted || state.hasError) return;
    state = AsyncData(_visible(loaded));
  }
}

// No auto-retry: a Failure is retried by hand (see AGENTS.md).
final libraryNotifierProvider =
    AsyncNotifierProvider.autoDispose<LibraryNotifier, List<LibraryItem>>(
      LibraryNotifier.new,
      retry: (_, _) => null,
    );
