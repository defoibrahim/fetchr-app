import '../../../../core/errors/guard.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/platform/fetchr_api.g.dart' as api;
import '../../domain/entities/library_item.dart';
import '../../domain/repositories/i_library_repository.dart';

class LibraryRepositoryImpl implements ILibraryRepository {
  const LibraryRepositoryImpl(this._api);

  final api.FetchrHostApi _api;

  @override
  Future<Result<List<LibraryItem>>> list(String folder) =>
      guard(() async => (await _api.listLibrary(folder)).map(_toItem).toList());

  @override
  Future<Result<bool>> delete(String uri) =>
      guard(() => _api.deleteFromLibrary(uri));

  @override
  Future<Result<void>> share(LibraryItem item) =>
      guard(() => _api.share(item.uri, item.mimeType));

  @override
  Future<Result<void>> openFolder(String uri) =>
      guard(() => _api.openFolder(uri));

  @override
  Future<Result<String?>> thumbnail(String uri, int widthPx, int heightPx) =>
      guard(() => _api.thumbnail(uri, widthPx, heightPx));
}

LibraryItem _toItem(api.LibraryItem item) => LibraryItem(
  uri: item.uri,
  name: item.name,
  mimeType: item.mimeType,
  isAudio: item.isAudio,
  sizeBytes: item.sizeBytes,
  durationMs: item.durationMs,
  dateAdded: DateTime.fromMillisecondsSinceEpoch(item.dateAddedMs),
  width: item.width,
  height: item.height,
  relativePath: item.relativePath,
);
