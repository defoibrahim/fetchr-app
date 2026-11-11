import '../../../../core/errors/result.dart';
import '../entities/download_request.dart';
import '../entities/download_task.dart';
import '../entities/media_info.dart';

abstract interface class IDownloaderRepository {
  Future<Result<MediaInfo>> fetchInfo(String url);

  Future<Result<void>> enqueue(List<DownloadRequest> requests);

  Future<Result<void>> cancel(String id);

  /// Resumes from the kept partial file, or starts over when none is left.
  Future<Result<void>> retry(String id);

  Future<Result<void>> pause(String id);

  Future<Result<void>> resume(String id);

  Future<Result<void>> pauseAll();

  Future<Result<void>> resumeAll();

  /// Free bytes on the volume downloads are saved to.
  Future<Result<int>> freeSpaceBytes();

  /// False, with the task kept, when the user declined the system delete
  /// dialog for its saved file.
  Future<Result<bool>> remove(String id);

  Future<Result<void>> openFolder(String uri);

  /// The system video picker; the picked video's uri, or null when the user
  /// backed out.
  Future<Result<String?>> pickVideo();

  /// Queues an MP3 of a video on the device; it runs, reports and saves like
  /// a download.
  Future<Result<void>> convertToMp3(String uri, String folder);

  /// Each listener gets the latest snapshot of the full task list; while a
  /// listener is paused only the latest one is kept.
  Stream<List<DownloadTask>> watchTasks();
}
