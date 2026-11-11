import '../../../../core/errors/result.dart';
import '../../../../core/usecase/base_use_case.dart';
import '../repositories/i_library_repository.dart';

class DeleteLibraryItemsUseCase implements BaseUseCase<bool, String> {
  const DeleteLibraryItemsUseCase(this._repository);

  final ILibraryRepository _repository;

  @override
  Future<Result<bool>> call(String params) => _repository.delete(params);
}
