import 'package:equatable/equatable.dart';

import '../../../../app/shared/domain/entities/quality.dart';
import 'download_task.dart';

enum PlaylistItemStatus { done, downloading, queued, failed, skipped }

/// One video of a playlist download: its task, read as the playlist sees it.
class PlaylistItem extends Equatable {
  const PlaylistItem(this.task);

  final DownloadTask task;

  String get id => task.id;
  String get title => task.request.title;
  String? get thumbnailUrl => task.request.thumbnail;
  int? get durationSec => task.request.durationSec;
  int? get sizeEstimate => task.totalBytes;

  /// Its place in the playlist, from 1; 0 when native never reported one.
  int get index => task.request.playlistIndex ?? 0;

  /// 0..1; 0 while it is unknown.
  double get progress => task.progress.clamp(0.0, 1.0);

  /// A paused video that had started holds its place as the one on its way;
  /// one paused before it started is still waiting.
  PlaylistItemStatus get status => switch (task.status) {
    TaskStatus.completed => PlaylistItemStatus.done,
    TaskStatus.running => PlaylistItemStatus.downloading,
    TaskStatus.paused when _started => PlaylistItemStatus.downloading,
    TaskStatus.queued || TaskStatus.paused => PlaylistItemStatus.queued,
    TaskStatus.failed => PlaylistItemStatus.failed,
    TaskStatus.canceled => PlaylistItemStatus.skipped,
  };

  bool get _started => task.progress > 0 || (task.downloadedBytes ?? 0) > 0;

  @override
  List<Object?> get props => [task];
}

/// The videos of one playlist the user queued together, with what the card
/// and the detail screen show about them as a whole.
class PlaylistDownload extends Equatable {
  const PlaylistDownload({required this.title, required this.items});

  // ponytail: the title is the id, so two playlists with one name merge; a
  // batch id on the native request if that ever happens.
  String get id => title;

  final String title;

  /// In the order they start, which the user can change; never empty.
  final List<PlaylistItem> items;

  /// In playlist order, as the tile grid shows them.
  List<PlaylistItem> get tiles =>
      [...items]..sort((a, b) => a.index.compareTo(b.index));

  Quality get quality => items.first.task.request.quality;

  int count(PlaylistItemStatus status) =>
      items.where((item) => item.status == status).length;

  int get done => count(PlaylistItemStatus.done);
  int get failed => count(PlaylistItemStatus.failed);
  int get skipped => count(PlaylistItemStatus.skipped);

  /// Still to download: waiting or on its way.
  int get remaining =>
      count(PlaylistItemStatus.queued) + count(PlaylistItemStatus.downloading);

  /// The video on its way, the first to start when two run at once.
  PlaylistItem? get current {
    for (final item in items) {
      if (item.status == PlaylistItemStatus.downloading) return item;
    }
    return null;
  }

  /// Waiting to start, in the order they will.
  List<PlaylistItem> get upNext => [
    for (final item in items)
      if (item.status == PlaylistItemStatus.queued) item,
  ];

  /// Videos are held and none is moving or waiting.
  bool get isPaused =>
      !items.any((item) => item.task.isActive) &&
      items.any((item) => item.task.isPaused);

  int get bytesDone => items.fold(
    0,
    (sum, item) => item.status == PlaylistItemStatus.skipped
        ? sum
        : sum + (item.task.downloadedBytes ?? 0),
  );

  /// The videos not started yet count as the average of those whose size is
  /// known (a flat playlist reports none up front); null until one is.
  int? get bytesTotalEstimate {
    var known = 0;
    var sized = 0;
    var unsized = 0;
    for (final item in items) {
      if (item.status == PlaylistItemStatus.skipped) continue;
      final total = item.task.totalBytes;
      if (total != null && total > 0) {
        known += total;
        sized++;
      } else {
        unsized++;
      }
    }
    return sized == 0 ? null : known + (known ~/ sized) * unsized;
  }

  int get speedBytesPerSec => items.fold(
    0,
    (sum, item) => item.task.status == TaskStatus.running
        ? sum + (item.task.speedBytesPerSec ?? 0)
        : sum,
  );

  /// Null while the size or the speed is not known.
  int? get etaSec {
    final total = bytesTotalEstimate;
    final speed = speedBytesPerSec;
    if (total == null || speed <= 0) return null;
    final left = total - bytesDone;
    return left <= 0 ? 0 : left ~/ speed;
  }

  @override
  List<Object?> get props => [title, items];
}
