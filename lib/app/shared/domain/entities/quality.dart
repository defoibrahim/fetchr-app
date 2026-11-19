enum Quality {
  best('Best'),
  p1080('1080p'),
  p720('720p'),
  p480('480p'),
  mp3('MP3'),
  cover('Cover');

  const Quality(this.shortLabel);

  /// The pill text in Settings and the playlist page.
  final String shortLabel;

  bool get isAudio => this == mp3;

  /// The shared folder native saves into, as `MediaKind` picks it.
  String get saveRoot => switch (this) {
    mp3 => 'Music',
    cover => 'Pictures',
    _ => 'Movies',
  };

  /// Where a download of this quality lands: "Movies/Fetchr", or
  /// "Movies/Fetchr/Road trip" for a video of that playlist.
  String savePath(String folder, {String? playlist}) {
    final sub = playlist == null ? '' : _playlistFolder(playlist);
    return sub.isEmpty ? '$saveRoot/$folder' : '$saveRoot/$folder/$sub';
  }
}

// Mirrors RequestBuilder.saveFolder on the native side, which names the folder.
final _forbidden = RegExp(r'[\\/:*?"<>|\x00-\x1f\x7f-\x9f]');
final _leading = RegExp(r'^[.\s]+');
const _maxName = 150;

String _playlistFolder(String title) {
  final clean = title.replaceAll(_forbidden, '').replaceFirst(_leading, '');
  return (clean.length > _maxName ? clean.substring(0, _maxName) : clean)
      .trimRight();
}
