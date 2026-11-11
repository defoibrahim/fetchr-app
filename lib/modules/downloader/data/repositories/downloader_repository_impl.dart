import 'dart:async';

import '../../../../app/shared/domain/entities/quality.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/errors/failure_mapper.dart';
import '../../../../core/errors/guard.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/networking/network_info.dart';
import '../../../../core/platform/fetchr_api.g.dart' as api;
import '../../../../core/utils/dates.dart';
import '../../domain/entities/download_request.dart';
import '../../domain/entities/download_task.dart';
import '../../domain/entities/format_option.dart';
import '../../domain/entities/media_info.dart';
import '../../domain/repositories/i_downloader_repository.dart';

class DownloaderRepositoryImpl implements IDownloaderRepository {
  DownloaderRepositoryImpl(this._api, this._network, this._downloads);

  final api.FetchrHostApi _api;
  final INetworkInfo _network;
  final Stream<api.DownloadsSnapshot> Function() _downloads;

  // The generated factory opens a new EventChannel per call; open it once.
  late final Stream<List<DownloadTask>> _tasks = _downloads().map(
    (snapshot) => snapshot.tasks.map(_toTask).toList(),
  );

  @override
  Future<Result<MediaInfo>> fetchInfo(String url) async {
    if (!await _network.isConnected) return const Err(NetworkFailure());
    return guard(() async => _toInfo(await _api.fetchInfo(url)));
  }

  @override
  Future<Result<void>> enqueue(List<DownloadRequest> requests) =>
      guard(() => _api.enqueue(requests.map(_toApiRequest).toList()));

  @override
  Future<Result<void>> cancel(String id) => guard(() => _api.cancel(id));

  @override
  Future<Result<void>> retry(String id) => guard(() => _api.retry(id));

  @override
  Future<Result<void>> pause(String id) => guard(() => _api.pause(id));

  @override
  Future<Result<void>> resume(String id) => guard(() => _api.resume(id));

  @override
  Future<Result<void>> pauseAll() => guard(_api.pauseAll);

  @override
  Future<Result<void>> resumeAll() => guard(_api.resumeAll);

  @override
  Future<Result<int>> freeSpaceBytes() => guard(_api.freeSpaceBytes);

  @override
  Future<Result<String?>> pickVideo() => guard(_api.pickVideo);

  @override
  Future<Result<void>> convertToMp3(String uri, String folder) =>
      guard(() => _api.convertToMp3(uri, folder));

  @override
  Future<Result<bool>> remove(String id) => guard(() => _api.remove(id));

  @override
  Future<Result<void>> openFolder(String uri) =>
      guard(() => _api.openFolder(uri));

  // Riverpod pauses the subscription while the screen sits on a hidden tab; a
  // paused broadcast subscription buffers every event, so keep only the latest.
  @override
  Stream<List<DownloadTask>> watchTasks() {
    StreamSubscription<List<DownloadTask>>? upstream;
    List<DownloadTask>? latest;
    late final StreamController<List<DownloadTask>> out;
    out = StreamController(
      onListen: () {
        upstream = _tasks.listen(
          (tasks) {
            if (out.isPaused) {
              latest = tasks;
            } else {
              out.add(tasks);
            }
          },
          onError: out.addError,
          onDone: out.close,
        );
      },
      onResume: () {
        if (latest case final tasks?) {
          latest = null;
          out.add(tasks);
        }
      },
      onCancel: () => upstream?.cancel(),
    );
    return out.stream;
  }
}

MediaInfo _toInfo(api.VideoInfo info) => MediaInfo(
  url: info.url,
  title: info.title,
  thumbnail: info.thumbnail,
  durationSec: info.durationSeconds,
  uploader: info.uploader,
  isPlaylist: info.isPlaylist,
  isLive: info.isLive,
  // Every picker needs one option to select; native always sends one, and a
  // source it could not read still downloads as best.
  options: info.options.isEmpty
      ? const [FormatOption(quality: Quality.best)]
      : info.options.map(_toOption).toList(),
  entries: info.entries.map(_toEntry).toList(),
);

FormatOption _toOption(api.FormatOption option) => FormatOption(
  quality: _toQuality(option.quality),
  width: option.width,
  height: option.height,
  fps: option.fps,
  sizeBytes: option.sizeBytes,
  sizeIsEstimate: option.sizeIsEstimate,
);

PlaylistEntry _toEntry(api.PlaylistEntry entry) => PlaylistEntry(
  url: entry.url,
  title: entry.title,
  thumbnail: entry.thumbnail,
  durationSec: entry.durationSeconds,
);

DownloadRequest _toRequest(api.DownloadRequest request) => DownloadRequest(
  url: request.url,
  title: request.title,
  thumbnail: request.thumbnail,
  quality: _toQuality(request.quality),
  folder: request.folder,
  useAria2c: request.useAria2c,
  uploader: request.uploader,
  durationSec: request.durationSeconds,
  playlistTitle: request.playlistTitle,
  playlistIndex: request.playlistIndex,
  playlistCount: request.playlistCount,
);

api.DownloadRequest _toApiRequest(DownloadRequest request) =>
    api.DownloadRequest(
      url: request.url,
      title: request.title,
      thumbnail: request.thumbnail,
      quality: _toApiQuality(request.quality),
      folder: request.folder,
      useAria2c: request.useAria2c,
      uploader: request.uploader,
      durationSeconds: request.durationSec,
      playlistTitle: request.playlistTitle,
      playlistIndex: request.playlistIndex,
      playlistCount: request.playlistCount,
    );

DownloadTask _toTask(api.DownloadTask task) {
  final failure = task.status == api.TaskStatus.failed
      ? failureFromCode(task.errorCode)
      : null;
  return DownloadTask(
    id: task.id,
    request: _toRequest(task.request),
    status: _toStatus(task.status),
    progress: task.progress,
    etaSec: task.etaSeconds < 0 ? null : task.etaSeconds,
    failure: failure,
    // The raw yt-dlp line is only worth showing when no mapped message exists.
    errorMessage: failure == null || failure is UnexpectedFailure
        ? task.errorMessage
        : null,
    savedUri: task.savedUri,
    createdAt: DateTime.fromMillisecondsSinceEpoch(task.createdAtMs),
    stage: _toStage(task.stage),
    downloadedBytes: task.downloadedBytes,
    totalBytes: task.totalBytes,
    speedBytesPerSec: task.speedBytesPerSec,
    stalled: task.stalled,
    finishedAt: dateFromMs(task.finishedAtMs),
  );
}

Quality _toQuality(api.Quality quality) => switch (quality) {
  api.Quality.best => Quality.best,
  api.Quality.p1080 => Quality.p1080,
  api.Quality.p720 => Quality.p720,
  api.Quality.p480 => Quality.p480,
  api.Quality.mp3 => Quality.mp3,
  api.Quality.cover => Quality.cover,
};

api.Quality _toApiQuality(Quality quality) => switch (quality) {
  Quality.best => api.Quality.best,
  Quality.p1080 => api.Quality.p1080,
  Quality.p720 => api.Quality.p720,
  Quality.p480 => api.Quality.p480,
  Quality.mp3 => api.Quality.mp3,
  Quality.cover => api.Quality.cover,
};

TaskStatus _toStatus(api.TaskStatus status) => switch (status) {
  api.TaskStatus.queued => TaskStatus.queued,
  api.TaskStatus.running => TaskStatus.running,
  api.TaskStatus.completed => TaskStatus.completed,
  api.TaskStatus.failed => TaskStatus.failed,
  api.TaskStatus.canceled => TaskStatus.canceled,
  api.TaskStatus.paused => TaskStatus.paused,
};

TaskStage _toStage(api.TaskStage stage) => switch (stage) {
  api.TaskStage.preparing => TaskStage.preparing,
  api.TaskStage.downloading => TaskStage.downloading,
  api.TaskStage.postProcessing => TaskStage.postProcessing,
};
