import '../../../../app/shared/domain/entities/quality.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/entities/download_task.dart';
import 'quality_formatter.dart';

const _maxEtaSec = 24 * 60 * 60;

extension DownloadTaskFormat on DownloadTask {
  /// The left side split so the card can set the percent apart: "64%" then
  /// " · 118 / 184 MB" (or ""), or no percent and "118 MB" (unknown total).
  /// Right: "Waiting for network…" (stalled), "—" (no speed yet),
  /// "4.2 MB/s · 0:16 left", or "4.2 MB/s" (ETA unknown or over 24 h).
  ({String? percent, String rest, String right}) get stats {
    final (percent, rest) = _left;
    return (percent: percent, rest: rest, right: _right);
  }

  /// "Paused at 64% · 118 / 184 MB", or "Paused" when nothing is known.
  String get pausedText {
    final (percent, rest) = _left;
    final left = '${percent ?? ''}$rest';
    return left.isEmpty ? 'Paused' : 'Paused at $left';
  }

  /// What the task is doing before and after the bytes arrive, or null while
  /// it downloads.
  String? get stageText => switch (stage) {
    TaskStage.preparing => 'Starting…',
    TaskStage.downloading => null,
    TaskStage.postProcessing => switch (request.quality) {
      Quality.mp3 => 'Converting to MP3…',
      Quality.cover => 'Saving cover…',
      _ => 'Merging video and audio…',
    },
  };

  /// ffmpeg's percent while an MP3 converts; null while nothing measures the
  /// work.
  String? get stagePercent =>
      stage == TaskStage.postProcessing && progress >= 0 ? '$_percent%' : null;

  /// "Queued", "Queued · 3 more after this", or, for a task that already has
  /// progress, "Queued again · resumes from 41%". [more] is how many wait
  /// behind this one.
  String queuedText({int more = 0}) {
    final percent = _percent;
    if (percent > 0) return 'Queued again · resumes from $percent%';
    return more > 0 ? 'Queued · $more more after this' : 'Queued';
  }

  /// The copy table's short reason for a failed task.
  String get failureReason => switch (failure) {
    NetworkFailure() =>
      _percent > 0 ? 'Connection dropped at $_percent%' : 'Connection dropped',
    MediaUnavailableFailure() => 'Video unavailable',
    PrivateVideoFailure() => 'Private video',
    UnsupportedSiteFailure() => 'Site not supported',
    StorageFailure() => 'Not enough storage',
    StoragePermissionFailure() => "Fetchr can't save files",
    YtDlpBusyFailure() => 'yt-dlp was updating',
    _ => 'Download failed',
  };

  /// "720p · MP4", or "720p · 3 of 18 in playlist".
  String get metaText {
    final index = request.playlistIndex;
    final count = request.playlistCount;
    return index != null && count != null
        ? '${request.quality.shortLabel} · $index of $count in playlist'
        : request.quality.formatLabel;
  }

  /// Bytes of a finished file: the total, else what was written.
  int? get fileSize => totalBytes ?? downloadedBytes;

  /// "Movies/Fetchr · 96 MB".
  String get doneMeta {
    final size = fileSize;
    return [
      request.quality.savePath(request.folder),
      if (size != null && size > 0) formatBytes(size),
    ].join(' · ');
  }

  /// "{quality} · {container} · {size}" for a finished download, for example
  /// "1080p · MP4 · 184 MB" or "Audio · MP3 · 6.2 MB". The size is left out
  /// when native never reported one.
  String get recentMeta {
    final quality = request.quality;
    final (label, container) = switch (quality) {
      Quality.mp3 => ('Audio', 'MP3'),
      Quality.cover => (quality.shortLabel, 'JPG'),
      _ => (quality.shortLabel, 'MP4'),
    };
    final size = totalBytes;
    return [label, container, if (size != null) formatBytes(size)].join(' · ');
  }

  int get _percent => (progress.clamp(0.0, 1.0) * 100).round();

  (String?, String) get _left {
    final done = downloadedBytes;
    final total = totalBytes;
    if (progress >= 0) {
      final bytes = done != null && total != null && total > 0
          ? ' · ${formatBytesPair(done, total)}'
          : '';
      return ('$_percent%', bytes);
    }
    return (null, done == null ? '' : formatBytes(done));
  }

  String get _right {
    if (stalled) return 'Waiting for network…';
    final speed = speedBytesPerSec;
    if (speed == null || speed <= 0) return '—';
    final eta = etaSec;
    return eta != null && eta >= 0 && eta <= _maxEtaSec
        ? '${formatSpeed(speed)} · ${formatDuration(eta)} left'
        : formatSpeed(speed);
  }
}
