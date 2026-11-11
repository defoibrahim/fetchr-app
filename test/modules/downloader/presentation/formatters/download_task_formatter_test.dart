import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/shared/domain/entities/quality.dart';
import 'package:grabby/core/utils/formatters.dart';
import 'package:grabby/modules/downloader/domain/entities/download_task.dart';
import 'package:grabby/modules/downloader/presentation/formatters/download_task_formatter.dart';

import '../../../../support/fixtures.dart';

String _left(DownloadTask task) {
  final stats = task.stats;
  return '${stats.percent ?? ''}${stats.rest}';
}

void main() {
  group('stats', () {
    test('full stats', () {
      expect(
        downloadTask(
          progress: .64,
          downloadedBytes: 118 * mb,
          totalBytes: 184 * mb,
          speed: (4.2 * mb).round(),
          etaSec: 16,
        ).stats,
        (
          percent: '64%',
          rest: ' · 118 / 184 MB',
          right: '4.2 MB/s · 0:16 left',
        ),
      );
    });

    test('no speed yet', () {
      expect(downloadTask(progress: .1).stats.right, '—');
    });

    test('a zero speed is no speed', () {
      expect(downloadTask(progress: .1, speed: 0).stats.right, '—');
    });

    test('stalled', () {
      expect(
        downloadTask(stalled: true, speed: 0).stats.right,
        'Waiting for network…',
      );
    });

    test('stalled wins over a stale speed', () {
      expect(
        downloadTask(stalled: true, speed: 1000, etaSec: 5).stats.right,
        'Waiting for network…',
      );
    });

    test('ETA over a day is hidden', () {
      expect(downloadTask(speed: 10, etaSec: 90000).stats.right, '10 B/s');
    });

    test('a day exactly still shows', () {
      expect(
        downloadTask(speed: 10, etaSec: 86400).stats.right,
        '10 B/s · 24:00:00 left',
      );
    });

    test('an unknown ETA is hidden', () {
      expect(downloadTask(speed: 10).stats.right, '10 B/s');
      expect(downloadTask(speed: 10, etaSec: -1).stats.right, '10 B/s');
    });

    test('unknown total shows bytes so far', () {
      expect(
        _left(downloadTask(progress: -1, downloadedBytes: 118 * mb)),
        '118 MB',
      );
    });

    test('the percent is its own part', () {
      expect(
        downloadTask(progress: -1, downloadedBytes: mb).stats.percent,
        isNull,
      );
      expect(downloadTask(progress: .64).stats.percent, '64%');
    });

    test('percent alone when no bytes are known', () {
      expect(_left(downloadTask(progress: .64)), '64%');
    });

    test('percent alone when only the total is missing', () {
      expect(
        _left(downloadTask(progress: .64, downloadedBytes: 118 * mb)),
        '64%',
      );
    });

    test('nothing to say before anything is known', () {
      expect(_left(downloadTask(progress: -1)), '');
    });

    test('the percent is clamped to 0 to 100', () {
      expect(_left(downloadTask(progress: 1.4)), '100%');
    });
  });

  group('pausedText', () {
    test('names the percent and bytes it stopped at', () {
      expect(
        downloadTask(
          status: TaskStatus.paused,
          progress: .64,
          downloadedBytes: 118 * mb,
          totalBytes: 184 * mb,
        ).pausedText,
        'Paused at 64% · 118 / 184 MB',
      );
    });

    test('is just "Paused" when nothing is known', () {
      expect(
        downloadTask(status: TaskStatus.paused, progress: -1).pausedText,
        'Paused',
      );
    });
  });

  group('stageText', () {
    String? of(Quality quality, TaskStage stage) => downloadTask(
      stage: stage,
      request: downloadRequest(quality: quality),
    ).stageText;

    test('preparing is Starting for every quality', () {
      for (final quality in Quality.values) {
        expect(of(quality, TaskStage.preparing), 'Starting…');
      }
    });

    test('downloading needs no words', () {
      expect(of(Quality.p720, TaskStage.downloading), isNull);
    });

    test('post-processing is worded by what is being made', () {
      const merging = 'Merging video and audio…';
      expect(of(Quality.p720, TaskStage.postProcessing), merging);
      expect(of(Quality.best, TaskStage.postProcessing), merging);
      expect(of(Quality.mp3, TaskStage.postProcessing), 'Converting to MP3…');
      expect(of(Quality.cover, TaskStage.postProcessing), 'Saving cover…');
    });
  });

  group('stagePercent', () {
    test('is what ffmpeg has converted', () {
      expect(
        downloadTask(
          stage: TaskStage.postProcessing,
          progress: .42,
        ).stagePercent,
        '42%',
      );
    });

    test('is null until ffmpeg reports, and while downloading', () {
      expect(
        downloadTask(
          stage: TaskStage.postProcessing,
          progress: -1,
        ).stagePercent,
        isNull,
      );
      expect(downloadTask(progress: .42).stagePercent, isNull);
    });
  });

  group('queuedText', () {
    final fresh = downloadTask(status: TaskStatus.queued);
    final resumed = downloadTask(status: TaskStatus.queued, progress: .41);

    test('a lone task is just Queued', () {
      expect(fresh.queuedText(), 'Queued');
    });

    test('counts what waits behind it', () {
      expect(fresh.queuedText(more: 15), 'Queued · 15 more after this');
    });

    test('a task with progress resumes from it', () {
      expect(resumed.queuedText(), 'Queued again · resumes from 41%');
    });

    test('resuming wins over the count', () {
      expect(resumed.queuedText(more: 2), 'Queued again · resumes from 41%');
    });
  });

  group('failureReason', () {
    String of(String? code, {double progress = 0}) => downloadTask(
      status: TaskStatus.failed,
      errorCode: code,
      progress: progress,
    ).failureReason;

    test('every native code has its short reason', () {
      expect(of('network', progress: .41), 'Connection dropped at 41%');
      expect(of('unavailable'), 'Video unavailable');
      expect(of('private_video'), 'Private video');
      expect(of('unsupported_site'), 'Site not supported');
      expect(of('invalid_url'), 'Site not supported');
      expect(of('no_storage'), 'Not enough storage');
      expect(of('permission_denied'), "Fetchr can't save files");
      expect(of('busy'), 'yt-dlp was updating');
      expect(of('unknown'), 'Download failed');
    });

    test('a dropped connection before any progress has no percent', () {
      expect(of('network', progress: 0), 'Connection dropped');
      expect(of('network', progress: -1), 'Connection dropped');
    });

    test('a code no one knows is a plain failure', () {
      expect(of('something_new'), 'Download failed');
    });

    test('no failure at all is a plain failure', () {
      expect(of(null), 'Download failed');
    });
  });

  group('metaText', () {
    String of(Quality quality, {int? index, int? count}) => downloadTask(
      request: downloadRequest(
        quality: quality,
        playlistIndex: index,
        playlistCount: count,
      ),
    ).metaText;

    test('a video names its container', () {
      expect(of(Quality.p720), '720p · MP4');
      expect(of(Quality.best), 'Best · MP4');
    });

    test('audio and a cover name their own format', () {
      expect(of(Quality.mp3), 'MP3');
      expect(of(Quality.cover), 'Cover · JPG');
    });

    test('a playlist entry names its place', () {
      expect(
        of(Quality.p720, index: 3, count: 18),
        '720p · 3 of 18 in playlist',
      );
      expect(of(Quality.mp3, index: 1, count: 2), 'MP3 · 1 of 2 in playlist');
    });

    test('a half-known place is ignored', () {
      expect(of(Quality.p720, index: 3), '720p · MP4');
      expect(of(Quality.p720, count: 18), '720p · MP4');
    });
  });

  group('doneMeta', () {
    String of(
      Quality quality, {
      String folder = 'Fetchr',
      int? total,
      int? done,
    }) => downloadTask(
      status: TaskStatus.completed,
      request: downloadRequest(quality: quality, folder: folder),
      totalBytes: total,
      downloadedBytes: done,
    ).doneMeta;

    test('a video is under Movies', () {
      expect(of(Quality.p720, total: 96 * mb), 'Movies/Fetchr · 96 MB');
    });

    test('audio is under Music and a cover under Pictures', () {
      expect(
        of(Quality.mp3, total: (6.2 * mb).round()),
        'Music/Fetchr · 6.2 MB',
      );
      expect(of(Quality.cover, total: 200 * 1024), 'Pictures/Fetchr · 200 KB');
    });

    test('uses the request folder', () {
      expect(
        of(Quality.best, folder: 'Clips', total: mb),
        'Movies/Clips · 1.0 MB',
      );
    });

    test('falls back to the bytes written when the total was never known', () {
      expect(of(Quality.best, done: 50 * mb), 'Movies/Fetchr · 50 MB');
    });

    test('is just the path when no size is known', () {
      expect(of(Quality.best), 'Movies/Fetchr');
    });
  });

  group('recentMeta', () {
    String meta(Quality quality, {int? totalBytes}) => downloadTask(
      request: downloadRequest(quality: quality),
      totalBytes: totalBytes,
    ).recentMeta;

    test('video: the quality, MP4 and the size', () {
      expect(
        meta(Quality.p1080, totalBytes: 193 * 1024 * 1024),
        '1080p · MP4 · ${formatBytes(193 * 1024 * 1024)}',
      );
      expect(
        meta(Quality.best, totalBytes: 5 * 1024 * 1024),
        'Best · MP4 · ${formatBytes(5 * 1024 * 1024)}',
      );
    });

    test('audio reads Audio, MP3 and the size', () {
      expect(
        meta(Quality.mp3, totalBytes: 6500000),
        'Audio · MP3 · ${formatBytes(6500000)}',
      );
    });

    test('a cover reads Cover and JPG', () {
      expect(
        meta(Quality.cover, totalBytes: 45000),
        'Cover · JPG · ${formatBytes(45000)}',
      );
    });

    test('the size is left out when native did not report one', () {
      expect(meta(Quality.p720), '720p · MP4');
      expect(meta(Quality.mp3), 'Audio · MP3');
    });
  });

  group('fileSize', () {
    test('prefers the total over the bytes written', () {
      expect(downloadTask(totalBytes: 10, downloadedBytes: 5).fileSize, 10);
      expect(downloadTask(downloadedBytes: 5).fileSize, 5);
      expect(downloadTask().fileSize, isNull);
    });
  });
}
