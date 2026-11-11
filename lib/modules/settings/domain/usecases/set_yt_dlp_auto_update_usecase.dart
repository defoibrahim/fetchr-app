import '../../../../core/errors/result.dart';
import '../../../../core/usecase/base_use_case.dart';
import '../repositories/i_yt_dlp_repository.dart';

class SetYtDlpAutoUpdateUseCase implements BaseUseCase<void, bool> {
  const SetYtDlpAutoUpdateUseCase(this._repository);

  final IYtDlpRepository _repository;

  @override
  Future<Result<void>> call(bool params) => _repository.setAutoUpdate(params);
}
