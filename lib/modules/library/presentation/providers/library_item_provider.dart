import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/library_item.dart';
import 'library_notifier.dart';

/// The library item with this uri: null while the library loads or fails, and
/// for a file the library does not list (a player opened on another folder's
/// file still plays). Selecting the one item keeps a list change that does not
/// touch it from rebuilding the player.
final libraryItemProvider = Provider.autoDispose.family<LibraryItem?, String>(
  (ref, uri) => ref.watch(
    libraryNotifierProvider.select((library) {
      for (final item in library.value ?? const <LibraryItem>[]) {
        if (item.uri == uri) return item;
      }
      return null;
    }),
  ),
);
