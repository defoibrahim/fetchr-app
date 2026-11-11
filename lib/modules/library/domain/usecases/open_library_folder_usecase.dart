import '../../../../core/errors/result.dart';
import '../../../../core/usecase/base_use_case.dart';
import '../repositories/i_library_repository.dart';

class OpenLibraryFolderUseCase implements BaseUseCase<void, String> {
  const OpenLibraryFolderUseCase(this._repository);

  final ILibraryRepository _repository;

  @override
  Future<Result<void>> call(String params) => _repository.openFolder(params);
}
