import '../../../../core/errors/result.dart';
import '../../../../core/usecase/base_use_case.dart';
import '../repositories/i_downloader_repository.dart';

/// Picks a video on the phone and queues its MP3, saved to the folder in
/// [call]'s params. Ok(false) when the picker closed without a video.
class ConvertVideoUseCase implements BaseUseCase<bool, String> {
  const ConvertVideoUseCase(this._repository);

  final IDownloaderRepository _repository;

  @override
  Future<Result<bool>> call(String params) async {
    switch (await _repository.pickVideo()) {
      case Err(:final failure):
        return Err(failure);
      case Ok(value: null):
        return const Ok(false);
      case Ok(value: final uri?):
        return (await _repository.convertToMp3(uri, params)).map((_) => true);
    }
  }
}
