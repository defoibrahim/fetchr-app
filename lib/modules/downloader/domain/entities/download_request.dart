import 'package:equatable/equatable.dart';

import '../../../../app/shared/domain/entities/quality.dart';

class DownloadRequest extends Equatable {
  const DownloadRequest({
    required this.url,
    required this.title,
    required this.quality,
    required this.folder,
    required this.useAria2c,
    this.thumbnail,
    this.uploader,
    this.durationSec,
    this.playlistTitle,
    this.playlistIndex,
    this.playlistCount,
  });

  final String url;
  final String title;
  final String? thumbnail;
  final Quality quality;
  final String folder;
  final bool useAria2c;
  final String? uploader;
  final int? durationSec;
  final String? playlistTitle;

  /// 1-based.
  final int? playlistIndex;
  final int? playlistCount;

  @override
  List<Object?> get props => [
    url,
    title,
    thumbnail,
    quality,
    folder,
    useAria2c,
    uploader,
    durationSec,
    playlistTitle,
    playlistIndex,
    playlistCount,
  ];
}
