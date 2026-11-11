import '../../../../core/errors/result.dart';
import '../../../../core/usecase/base_use_case.dart';
import '../entities/library_item.dart';
import '../repositories/i_library_repository.dart';

class ShareLibraryItemUseCase implements BaseUseCase<void, LibraryItem> {
  const ShareLibraryItemUseCase(this._repository);

  final ILibraryRepository _repository;

  @override
  Future<Result<void>> call(LibraryItem params) => _repository.share(params);
}
