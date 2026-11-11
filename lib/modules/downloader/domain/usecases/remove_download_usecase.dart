import '../../../../core/errors/result.dart';
import '../../../../core/usecase/base_use_case.dart';
import '../repositories/i_downloader_repository.dart';

class RemoveDownloadUseCase implements BaseUseCase<bool, String> {
  const RemoveDownloadUseCase(this._repository);

  final IDownloaderRepository _repository;

  @override
  Future<Result<bool>> call(String params) => _repository.remove(params);
}
