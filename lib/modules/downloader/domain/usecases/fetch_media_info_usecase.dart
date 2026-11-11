import '../../../../core/errors/result.dart';
import '../../../../core/usecase/base_use_case.dart';
import '../entities/media_info.dart';
import '../repositories/i_downloader_repository.dart';

class FetchMediaInfoUseCase implements BaseUseCase<MediaInfo, String> {
  const FetchMediaInfoUseCase(this._repository);

  final IDownloaderRepository _repository;

  @override
  Future<Result<MediaInfo>> call(String params) =>
      _repository.fetchInfo(params);
}
