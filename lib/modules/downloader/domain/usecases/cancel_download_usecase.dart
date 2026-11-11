import '../../../../core/errors/result.dart';
import '../../../../core/usecase/base_use_case.dart';
import '../repositories/i_downloader_repository.dart';

class CancelDownloadUseCase implements BaseUseCase<void, String> {
  const CancelDownloadUseCase(this._repository);

  final IDownloaderRepository _repository;

  @override
  Future<Result<void>> call(String params) => _repository.cancel(params);
}
