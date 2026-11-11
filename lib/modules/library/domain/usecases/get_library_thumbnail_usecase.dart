import 'package:equatable/equatable.dart';

import '../../../../core/errors/result.dart';
import '../../../../core/usecase/base_use_case.dart';
import '../repositories/i_library_repository.dart';

class ThumbnailParams extends Equatable {
  const ThumbnailParams({
    required this.uri,
    required this.widthPx,
    required this.heightPx,
  });

  final String uri;
  final int widthPx;
  final int heightPx;

  @override
  List<Object?> get props => [uri, widthPx, heightPx];
}

class GetLibraryThumbnailUseCase
    implements BaseUseCase<String?, ThumbnailParams> {
  const GetLibraryThumbnailUseCase(this._repository);

  final ILibraryRepository _repository;

  @override
  Future<Result<String?>> call(ThumbnailParams params) =>
      _repository.thumbnail(params.uri, params.widthPx, params.heightPx);
}
