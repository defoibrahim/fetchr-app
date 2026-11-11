import '../../../../core/errors/result.dart';
import '../entities/library_item.dart';

abstract interface class ILibraryRepository {
  Future<Result<List<LibraryItem>>> list(String folder);

  /// False when the user declined the system dialog: the file is still there.
  Future<Result<bool>> delete(String uri);

  Future<Result<void>> share(LibraryItem item);

  Future<Result<void>> openFolder(String uri);

  /// Path of a cached JPEG, or null when the file has no thumbnail. A path
  /// rather than bytes so `FileImage` lets the image cache hit on scroll-back.
  Future<Result<String?>> thumbnail(String uri, int widthPx, int heightPx);
}
