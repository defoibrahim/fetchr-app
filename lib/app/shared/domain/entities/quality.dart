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

  /// Where a download of this quality lands: "Movies/Fetchr".
  String savePath(String folder) => '$saveRoot/$folder';
}
