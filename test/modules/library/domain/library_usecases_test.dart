import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/modules/library/domain/entities/library_item.dart';
import 'package:grabby/modules/library/domain/usecases/delete_library_items_usecase.dart';
import 'package:grabby/modules/library/domain/usecases/get_library_thumbnail_usecase.dart';
import 'package:grabby/modules/library/domain/usecases/get_library_usecase.dart';
import 'package:grabby/modules/library/domain/usecases/open_library_folder_usecase.dart';
import 'package:grabby/modules/library/domain/usecases/share_library_item_usecase.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/fixtures.dart';
import '../../../support/mocks.dart';

void main() {
  final item = libraryItem();
  const failure = StorageFailure();

  late MockLibraryRepository repository;

  setUp(() => repository = MockLibraryRepository());

  test('GetLibraryUseCase lists the folder', () async {
    when(() => repository.list('Fetchr')).thenAnswer((_) async => Ok([item]));

    final result = await GetLibraryUseCase(repository)('Fetchr');

    expect(result.valueOrNull, [item]);
  });

  test('GetLibraryUseCase passes a failure through', () async {
    when(
      () => repository.list(any()),
    ).thenAnswer((_) async => const Err<List<LibraryItem>>(failure));

    final result = await GetLibraryUseCase(repository)('Fetchr');

    expect(result.failureOrNull, failure);
  });

  test('DeleteLibraryItemsUseCase deletes the uri', () async {
    when(() => repository.delete('a')).thenAnswer((_) async => const Ok(true));

    final result = await DeleteLibraryItemsUseCase(repository)('a');

    expect(result.valueOrNull, isTrue);
  });

  test('DeleteLibraryItemsUseCase passes a failure through', () async {
    when(
      () => repository.delete(any()),
    ).thenAnswer((_) async => const Err<bool>(failure));

    final result = await DeleteLibraryItemsUseCase(repository)('a');

    expect(result.failureOrNull, failure);
  });

  test('ShareLibraryItemUseCase shares the item', () async {
    when(
      () => repository.share(item),
    ).thenAnswer((_) async => const Ok<void>(null));

    final result = await ShareLibraryItemUseCase(repository)(item);

    expect(result.isOk, isTrue);
    verify(() => repository.share(item)).called(1);
  });

  test('ShareLibraryItemUseCase passes a failure through', () async {
    when(
      () => repository.share(item),
    ).thenAnswer((_) async => const Err<void>(failure));

    final result = await ShareLibraryItemUseCase(repository)(item);

    expect(result.failureOrNull, failure);
  });

  group('GetLibraryThumbnailUseCase', () {
    const params = ThumbnailParams(uri: 'a', widthPx: 480, heightPx: 300);

    test('forwards the uri and the size', () async {
      const path = '/cache/thumbs/a.jpg';
      when(
        () => repository.thumbnail('a', 480, 300),
      ).thenAnswer((_) async => const Ok<String?>(path));

      final result = await GetLibraryThumbnailUseCase(repository)(params);

      expect(result.valueOrNull, path);
      verify(() => repository.thumbnail('a', 480, 300)).called(1);
    });

    test('passes a failure through', () async {
      when(
        () => repository.thumbnail(any(), any(), any()),
      ).thenAnswer((_) async => const Err<String?>(failure));

      final result = await GetLibraryThumbnailUseCase(repository)(params);

      expect(result.failureOrNull, failure);
    });

    test('params compare by value', () {
      expect(
        params,
        const ThumbnailParams(uri: 'a', widthPx: 480, heightPx: 300),
      );
      expect(
        params,
        isNot(const ThumbnailParams(uri: 'a', widthPx: 96, heightPx: 60)),
      );
    });
  });

  group('OpenLibraryFolderUseCase', () {
    test('forwards the uri', () async {
      when(
        () => repository.openFolder(item.uri),
      ).thenAnswer((_) async => const Ok<void>(null));

      final result = await OpenLibraryFolderUseCase(repository)(item.uri);

      expect(result.isOk, isTrue);
      verify(() => repository.openFolder(item.uri)).called(1);
    });

    test('passes a failure through', () async {
      when(
        () => repository.openFolder(any()),
      ).thenAnswer((_) async => const Err<void>(failure));

      final result = await OpenLibraryFolderUseCase(repository)(item.uri);

      expect(result.failureOrNull, failure);
    });
  });
}
