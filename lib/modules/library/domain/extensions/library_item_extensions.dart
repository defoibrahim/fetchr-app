import '../entities/library_item.dart';

// The "03 - " native puts before a playlist file so the folder sorts in order.
final _numbered = RegExp(r'^(\d+) - ');

extension LibraryItemPlaylist on LibraryItem {
  /// The playlist folder the file was saved into
  /// (`Movies/Fetchr/<playlist>/`), or null for a file saved on its own.
  String? get playlist {
    final parts = [
      for (final part in (relativePath ?? '').split('/'))
        if (part.isNotEmpty) part,
    ];
    return parts.length >= 3 ? parts[2] : null;
  }

  /// "03" for "03 - Title.mp4"; null for a file with no number.
  String? get playlistNumber => _numbered.firstMatch(name)?.group(1);

  /// The name without its playlist number.
  String get nameInPlaylist => name.replaceFirst(_numbered, '');
}

extension LibraryItemList on List<LibraryItem> {
  /// The files of [playlist] in playlist order: their numbered names sort.
  List<LibraryItem> inPlaylist(String playlist) => [
    for (final item in this)
      if (item.playlist == playlist) item,
  ]..sort(_byName);

  /// The files of every playlist folder, by its name, in playlist order.
  Map<String, List<LibraryItem>> get byPlaylist {
    final files = <String, List<LibraryItem>>{};
    for (final item in this) {
      if (item.playlist case final playlist?) {
        (files[playlist] ??= []).add(item);
      }
    }
    for (final list in files.values) {
      list.sort(_byName);
    }
    return files;
  }

  int get totalBytes => fold(0, (sum, item) => sum + item.sizeBytes);
}

int _byName(LibraryItem a, LibraryItem b) => a.name.compareTo(b.name);
