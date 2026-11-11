import '../../../../core/errors/result.dart';
import '../../../../core/usecase/base_use_case.dart';
import '../repositories/i_downloader_repository.dart';

class PauseAllDownloadsUseCase implements BaseUseCase<void, NoParams> {
  const PauseAllDownloadsUseCase(this._repository);

  final IDownloaderRepository _repository;

  @override
  Future<Result<void>> call(NoParams params) => _repository.pauseAll();
}
