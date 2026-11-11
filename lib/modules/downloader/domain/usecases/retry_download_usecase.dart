import '../../../../core/errors/result.dart';
import '../../../../core/usecase/base_use_case.dart';
import '../repositories/i_downloader_repository.dart';

class RetryDownloadUseCase implements BaseUseCase<void, String> {
  const RetryDownloadUseCase(this._repository);

  final IDownloaderRepository _repository;

  @override
  Future<Result<void>> call(String params) => _repository.retry(params);
}
