import 'package:equatable/equatable.dart';

import 'download_task.dart';
import 'playlist_download.dart';

class DownloadGroups extends Equatable {
  const DownloadGroups({
    this.playlists = const [],
    required this.active,
    required this.queued,
    required this.attention,
    required this.doneToday,
  });

  /// Playlists with videos still to finish. Their tasks are in no other
  /// group: the playlist's card stands for all of them.
  final List<PlaylistDownload> playlists;

  /// Running, paused and canceled, newest first.
  final List<DownloadTask> active;

  /// Oldest first: the next to run leads.
  final List<DownloadTask> queued;

  /// Failed, newest first.
  final List<DownloadTask> attention;

  /// Completed and finished today (local), newest first.
  final List<DownloadTask> doneToday;

  bool get isEmpty =>
      playlists.isEmpty &&
      active.isEmpty &&
      queued.isEmpty &&
      attention.isEmpty &&
      doneToday.isEmpty;

  @override
  List<Object?> get props => [playlists, active, queued, attention, doneToday];
}
