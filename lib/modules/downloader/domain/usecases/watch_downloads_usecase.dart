import '../entities/download_task.dart';
import '../repositories/i_downloader_repository.dart';

class WatchDownloadsUseCase {
  const WatchDownloadsUseCase(this._repository);

  final IDownloaderRepository _repository;

  Stream<List<DownloadTask>> call() => _repository.watchTasks();
}
