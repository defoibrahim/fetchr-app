import '../../../../core/errors/result.dart';
import '../../../../core/usecase/base_use_case.dart';
import '../repositories/i_downloader_repository.dart';

class GetFreeSpaceUseCase implements BaseUseCase<int, NoParams> {
  const GetFreeSpaceUseCase(this._repository);

  final IDownloaderRepository _repository;

  @override
  Future<Result<int>> call(NoParams params) => _repository.freeSpaceBytes();
}
