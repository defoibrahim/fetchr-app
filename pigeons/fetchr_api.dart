import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/core/platform/fetchr_api.g.dart',
    dartPackageName: 'grabby',
    kotlinOut:
        'android/app/src/main/kotlin/com/defo/fetchr/pigeon/FetchrApi.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'com.defo.fetchr.pigeon',
      errorClassName: 'FetchrError',
    ),
  ),
)
enum Quality { best, p1080, p720, p480, mp3, cover }

enum TaskStatus { queued, running, completed, failed, canceled, paused }

// What a running task is doing; Dart words it from this and the quality.
enum TaskStage { preparing, downloading, postProcessing }

class PlaylistEntry {
  PlaylistEntry({
    required this.url,
    required this.title,
    this.thumbnail,
    this.durationSeconds,
  });
  String url;
  String title;
  String? thumbnail;
  int? durationSeconds;
}

// width/height describe the file the option would produce; for cover, the
// thumbnail when known.
class FormatOption {
  FormatOption({
    required this.quality,
    this.width,
    this.height,
    this.fps,
    this.sizeBytes,
    required this.sizeIsEstimate,
  });
  Quality quality;
  int? width;
  int? height;
  double? fps;
  int? sizeBytes;
  bool sizeIsEstimate;
}

class VideoInfo {
  VideoInfo({
    required this.url,
    required this.title,
    this.thumbnail,
    this.durationSeconds,
    this.uploader,
    required this.isPlaylist,
    required this.options,
    required this.entries,
    required this.isLive,
  });
  String url;
  String title;
  String? thumbnail;
  int? durationSeconds;
  String? uploader;
  bool isPlaylist;
  List<FormatOption> options;
  List<PlaylistEntry> entries;
  bool isLive;
}

class DownloadRequest {
  DownloadRequest({
    required this.url,
    required this.title,
    this.thumbnail,
    required this.quality,
    required this.folder,
    required this.useAria2c,
    this.uploader,
    this.durationSeconds,
    this.playlistTitle,
    this.playlistIndex,
    this.playlistCount,
  });
  String url;
  String title;
  String? thumbnail;
  Quality quality;
  String folder;
  bool useAria2c;
  String? uploader;
  int? durationSeconds;
  String? playlistTitle;
  int? playlistIndex; // 1-based
  int? playlistCount;
}

class DownloadTask {
  DownloadTask({
    required this.id,
    required this.request,
    required this.status,
    required this.progress,
    required this.etaSeconds,
    this.errorCode,
    this.errorMessage,
    this.savedUri,
    required this.createdAtMs,
    required this.stage,
    this.downloadedBytes,
    this.totalBytes,
    this.speedBytesPerSec,
    required this.stalled,
    this.finishedAtMs,
  });
  String id;
  DownloadRequest request;
  TaskStatus status;
  double progress; // 0..1, -1 = unknown (e.g. merging)
  int etaSeconds; // -1 = unknown
  String? errorCode; // same snake_case codes as FetchrError.code
  String? errorMessage;
  String? savedUri;
  int createdAtMs;
  TaskStage stage;
  int? downloadedBytes;
  int? totalBytes; // null when yt-dlp does not know it
  int? speedBytesPerSec; // null until the first sample
  bool stalled; // running with no progress line for 30 s
  int? finishedAtMs; // set on completed, failed and canceled
}

class DownloadsSnapshot {
  DownloadsSnapshot({required this.tasks});
  List<DownloadTask> tasks;
}

class LibraryItem {
  LibraryItem({
    required this.uri,
    required this.name,
    required this.mimeType,
    required this.isAudio,
    required this.sizeBytes,
    this.durationMs,
    required this.dateAddedMs,
    this.width,
    this.height,
    this.relativePath,
  });
  String uri;
  String name;
  String mimeType;
  bool isAudio;
  int sizeBytes;
  int? durationMs;
  int dateAddedMs;
  int? width;
  int? height;
  String? relativePath; // e.g. "Movies/Fetchr/"
}

class YtDlpStatus {
  YtDlpStatus({this.version, this.checkedAtMs, required this.autoUpdate});
  String? version;
  int? checkedAtMs; // last successful update
  bool autoUpdate;
}

@HostApi()
abstract class FetchrHostApi {
  @async
  VideoInfo fetchInfo(String url);
  void enqueue(List<DownloadRequest> requests);
  void cancel(String id);
  void retry(String id);
  void pause(String id);
  void resume(String id);
  void pauseAll();
  void resumeAll();
  // Deletes the saved file, then the task; false keeps both if user declines.
  @async
  bool remove(String id);
  @async
  List<LibraryItem> listLibrary(String folder);
  @async
  bool deleteFromLibrary(String uri);
  void share(String uri, String mimeType);
  void openFile(String uri, String mimeType);
  // Opens the item's folder in the Files app; throws no_folder_app when
  // nothing can open it.
  @async
  void openFolder(String uri);
  @async
  int freeSpaceBytes();
  // The system video picker: the photo picker where the device has one, else
  // the Files app. Null when the user backs out.
  @async
  String? pickVideo();
  // Queues an MP3 of a video on the device (a picked or saved content: or
  // file: uri); it runs, reports and saves like a download.
  @async
  void convertToMp3(String uri, String folder);
  // Path of a cached JPEG, so Flutter's image cache can hit on scroll-back;
  // null when the file has no thumbnail.
  @async
  String? thumbnail(String uri, int widthPx, int heightPx);
  @async
  YtDlpStatus ytDlpStatus(); // waits for init and a running startup update
  @async
  YtDlpStatus updateYtDlp();
  void setYtDlpAutoUpdate(bool enabled);
  void setAccentColor(int argb);
  // Completes once the launch splash has played its icon animation and gone,
  // so the Flutter intro starts from the same frame; at once on Android 8-11.
  @async
  void awaitLaunchSplash();
}

@EventChannelApi()
abstract class FetchrEvents {
  DownloadsSnapshot downloads();
}
