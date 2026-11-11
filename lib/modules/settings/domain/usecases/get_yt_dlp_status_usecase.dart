import '../../../../app/shared/domain/entities/yt_dlp_status.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/usecase/base_use_case.dart';
import '../repositories/i_yt_dlp_repository.dart';

class GetYtDlpStatusUseCase implements BaseUseCase<YtDlpStatus, NoParams> {
  const GetYtDlpStatusUseCase(this._repository);

  final IYtDlpRepository _repository;

  @override
  Future<Result<YtDlpStatus>> call(NoParams params) => _repository.status();
}
