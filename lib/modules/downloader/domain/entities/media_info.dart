import 'package:equatable/equatable.dart';

import '../../../../app/shared/domain/entities/quality.dart';
import 'format_option.dart';

class PlaylistEntry extends Equatable {
  const PlaylistEntry({
    required this.url,
    required this.title,
    this.thumbnail,
    this.durationSec,
  });

  final String url;
  final String title;
  final String? thumbnail;
  final int? durationSec;

  @override
  List<Object?> get props => [url, title, thumbnail, durationSec];
}

class MediaInfo extends Equatable {
  const MediaInfo({
    required this.url,
    required this.title,
    required this.isPlaylist,
    required this.options,
    required this.entries,
    this.thumbnail,
    this.durationSec,
    this.uploader,
    this.isLive = false,
  });

  final String url;
  final String title;
  final String? thumbnail;
  final int? durationSec;
  final String? uploader;
  final bool isPlaylist;
  final bool isLive;

  /// Never empty: the repository maps a source with none to best.
  final List<FormatOption> options;
  final List<PlaylistEntry> entries;

  /// The option for [quality], or null when this source does not offer it.
  FormatOption? optionFor(Quality quality) =>
      options.where((o) => o.quality == quality).firstOrNull;

  /// The option listed after [quality]'s, the next smaller download; null when
  /// [quality] is the last or not offered.
  FormatOption? optionBelow(Quality quality) {
    final at = options.indexWhere((o) => o.quality == quality);
    return at >= 0 && at + 1 < options.length ? options[at + 1] : null;
  }

  /// The option to highlight: the preferred quality when this source offers
  /// it. A 720p clip has no 1080p; the first option is the best it does have.
  FormatOption pick(Quality preferred) => optionFor(preferred) ?? options.first;

  @override
  List<Object?> get props => [
    url,
    title,
    thumbnail,
    durationSec,
    uploader,
    isPlaylist,
    isLive,
    options,
    entries,
  ];
}
