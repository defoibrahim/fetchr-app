import '../../../../core/errors/result.dart';
import '../../../../core/usecase/base_use_case.dart';
import '../entities/download_request.dart';
import '../repositories/i_downloader_repository.dart';

class EnqueueDownloadsUseCase
    implements BaseUseCase<void, List<DownloadRequest>> {
  const EnqueueDownloadsUseCase(this._repository);

  final IDownloaderRepository _repository;

  @override
  Future<Result<void>> call(List<DownloadRequest> params) =>
      _repository.enqueue(params);
}
