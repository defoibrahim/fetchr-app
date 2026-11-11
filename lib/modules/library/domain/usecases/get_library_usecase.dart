import '../../../../core/errors/result.dart';
import '../../../../core/usecase/base_use_case.dart';
import '../entities/library_item.dart';
import '../repositories/i_library_repository.dart';

class GetLibraryUseCase implements BaseUseCase<List<LibraryItem>, String> {
  const GetLibraryUseCase(this._repository);

  final ILibraryRepository _repository;

  @override
  Future<Result<List<LibraryItem>>> call(String params) =>
      _repository.list(params);
}
