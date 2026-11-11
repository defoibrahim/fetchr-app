import 'package:grabby/app/shared/domain/entities/quality.dart';
import 'package:grabby/app/shared/domain/entities/yt_dlp_status.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/failure_mapper.dart';
import 'package:grabby/modules/downloader/domain/entities/download_request.dart';
import 'package:grabby/modules/downloader/domain/entities/download_task.dart';
import 'package:grabby/modules/downloader/domain/entities/format_option.dart';
import 'package:grabby/modules/downloader/domain/entities/media_info.dart';
import 'package:grabby/modules/library/domain/entities/library_item.dart';

const mb = 1024 * 1024;
const gb = 1024 * mb;

DownloadRequest downloadRequest({
  String url = 'https://example.com/v',
  String title = 'Video',
  String? thumbnail,
  Quality quality = Quality.best,
  String folder = 'Fetchr',
  bool useAria2c = false,
  String? uploader,
  int? durationSec,
  String? playlistTitle,
  int? playlistIndex,
  int? playlistCount,
}) => DownloadRequest(
  url: url,
  title: title,
  thumbnail: thumbnail,
  quality: quality,
  folder: folder,
  useAria2c: useAria2c,
  uploader: uploader,
  durationSec: durationSec,
  playlistTitle: playlistTitle,
  playlistIndex: playlistIndex,
  playlistCount: playlistCount,
);

/// Without a [request], the task asks for `https://example.com/<id>` titled
/// `Video <id>`, so tasks with different ids stay distinct.
/// [errorCode] gives the [failure] a native error code maps to; an explicit
/// [failure] wins. [speed] is bytes per second.
DownloadTask downloadTask({
  String id = 'a',
  DownloadRequest? request,
  TaskStatus status = TaskStatus.running,
  TaskStage stage = TaskStage.preparing,
  double progress = 0,
  int? etaSec,
  int? downloadedBytes,
  int? totalBytes,
  int? speed,
  bool stalled = false,
  Failure? failure,
  String? errorCode,
  String? errorMessage,
  String? savedUri,
  DateTime? createdAt,
  DateTime? finishedAt,
}) => DownloadTask(
  id: id,
  request:
      request ??
      downloadRequest(url: 'https://example.com/$id', title: 'Video $id'),
  status: status,
  stage: stage,
  progress: progress,
  etaSec: etaSec,
  downloadedBytes: downloadedBytes,
  totalBytes: totalBytes,
  speedBytesPerSec: speed,
  stalled: stalled,
  failure: failure ?? (errorCode == null ? null : failureFromCode(errorCode)),
  errorMessage: errorMessage,
  savedUri: savedUri,
  createdAt: createdAt ?? DateTime.utc(2026),
  finishedAt: finishedAt,
);

/// One bare option per quality, for tests that only care which are offered.
List<FormatOption> formatOptions(Iterable<Quality> qualities) => [
  for (final quality in qualities) FormatOption(quality: quality),
];

MediaInfo mediaInfo({
  String url = 'https://example.com/v',
  String title = 'v',
  String? thumbnail,
  int? durationSec,
  String? uploader,
  bool isPlaylist = false,
  bool isLive = false,
  // What the repository gives a source with no options of its own.
  List<FormatOption> options = const [FormatOption(quality: Quality.best)],
  List<PlaylistEntry> entries = const [],
}) => MediaInfo(
  url: url,
  title: title,
  thumbnail: thumbnail,
  durationSec: durationSec,
  uploader: uploader,
  isPlaylist: isPlaylist,
  isLive: isLive,
  options: options,
  entries: entries,
);

LibraryItem libraryItem({
  String uri = 'content://media/external/video/media/7',
  String name = 'Clip.mp4',
  String mimeType = 'video/mp4',
  bool isAudio = false,
  int sizeBytes = 1024,
  int? durationMs,
  int? width,
  int? height,
  String? relativePath,
  DateTime? dateAdded,
}) => LibraryItem(
  uri: uri,
  name: name,
  mimeType: mimeType,
  isAudio: isAudio,
  sizeBytes: sizeBytes,
  durationMs: durationMs,
  width: width,
  height: height,
  relativePath: relativePath,
  dateAdded: dateAdded ?? DateTime.utc(2026),
);

/// With no [version], native could not report one and the bundled copy is in
/// use.
YtDlpStatus ytDlpStatus({
  String? version,
  DateTime? checkedAt,
  bool autoUpdate = true,
}) =>
    YtDlpStatus(version: version, checkedAt: checkedAt, autoUpdate: autoUpdate);
