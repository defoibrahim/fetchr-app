import '../../../../core/errors/result.dart';
import '../../../../core/usecase/base_use_case.dart';
import '../repositories/i_downloader_repository.dart';

class ReorderQueueUseCase implements BaseUseCase<void, List<String>> {
  const ReorderQueueUseCase(this._repository);

  final IDownloaderRepository _repository;

  @override
  Future<Result<void>> call(List<String> params) => _repository.reorder(params);
}
