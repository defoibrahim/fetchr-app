import '../../../../core/utils/formatters.dart';
import '../../domain/entities/download_task.dart';
import '../../domain/entities/playlist_download.dart';
import 'download_task_formatter.dart';

extension PlaylistItemStatusFormat on PlaylistItemStatus {
  /// The screen reader's word for a tile: "Video 3, waiting".
  String get label => switch (this) {
    PlaylistItemStatus.done => 'done',
    PlaylistItemStatus.downloading => 'downloading',
    PlaylistItemStatus.queued => 'waiting',
    PlaylistItemStatus.failed => 'failed',
    PlaylistItemStatus.skipped => 'skipped',
  };
}

extension PlaylistDownloadFormat on PlaylistDownload {
  /// "Playlist · 480p · 36 videos".
  String get metaLine =>
      'Playlist · ${quality.shortLabel} · ${plural(items.length, 'video')}';

  /// "3.4 MB/s · ~18 min left", "Paused", or "Starting…" before any speed.
  String get statusLine {
    if (isPaused) return 'Paused';
    final speed = speedBytesPerSec;
    if (speed <= 0) return 'Starting…';
    final eta = etaSec;
    return eta == null
        ? formatSpeed(speed)
        : '${formatSpeed(speed)} · ${_minutes(eta)} left';
  }

  /// "112 MB of ~900 MB", or "112 MB" while no size is known.
  String get bytesLine {
    final total = bytesTotalEstimate;
    final done = formatBytes(bytesDone);
    return total == null ? done : '$done of ~${formatBytes(total)}';
  }

  /// "4 done · 1 failed · 31 to go"; a count of zero is left out.
  String get summary => [
    if (done > 0) '$done done',
    if (failed > 0) '$failed failed',
    if (skipped > 0) '$skipped skipped',
    if (remaining > 0) '$remaining to go',
  ].join(' · ');

  /// "~18 min" for the panel, or null while it is not known.
  String? get etaShort {
    final eta = etaSec;
    return eta == null || isPaused ? null : _minutes(eta);
  }

  /// The selected tile's line, by its status: "Saved · 24 MB", "Connection
  /// dropped at 61%", "Downloading · 38%", "Paused at 38%", "Waiting · 3
  /// ahead", "Queued again · resumes from 61%" or "Skipped · won’t download".
  String metaOf(PlaylistItem item) {
    final task = item.task;
    final percent = task.percentText;
    return switch (item.status) {
      PlaylistItemStatus.done => [
        'Saved',
        if (task.fileSize case final size? when size > 0) formatBytes(size),
      ].join(' · '),
      PlaylistItemStatus.failed => task.failureReason,
      PlaylistItemStatus.downloading =>
        task.isPaused ? 'Paused at $percent' : 'Downloading · $percent',
      PlaylistItemStatus.queued when item.progress > 0 => task.queuedText(),
      PlaylistItemStatus.queued => 'Waiting · ${_ahead(item)} ahead',
      PlaylistItemStatus.skipped => 'Skipped · won’t download',
    };
  }

  // The videos that start before this one: the ones on their way, then the
  // waiting ones in front of it.
  int _ahead(PlaylistItem item) =>
      count(PlaylistItemStatus.downloading) + upNext.indexOf(item);
}

extension PlaylistItemFormat on PlaylistItem {
  /// "#7 · 7:42 · ~21 MB"; what is not known is left out.
  String get queueMeta => [
    '#$index',
    if (durationSec case final duration?) formatDuration(duration),
    if (sizeEstimate case final size? when size > 0) '~${formatBytes(size)}',
  ].join(' · ');

  /// "5 of 36", where it sits in the playlist.
  String get place => task.playlistPlace ?? '#$index';

  /// "Downloading now", "Paused" or "Starting…".
  String get currentLabel => switch (task) {
    DownloadTask(isPaused: true) => 'Paused',
    DownloadTask(stage: TaskStage.preparing) => 'Starting…',
    DownloadTask(stage: TaskStage.postProcessing) =>
      task.stageText ?? 'Downloading now',
    _ => 'Downloading now',
  };
}

String _minutes(int seconds) {
  if (seconds < 60) return '<1 min';
  final minutes = (seconds / 60).ceil();
  if (minutes < 60) return '~$minutes min';
  final rest = minutes % 60;
  return rest == 0 ? '~${minutes ~/ 60} h' : '~${minutes ~/ 60} h $rest min';
}
