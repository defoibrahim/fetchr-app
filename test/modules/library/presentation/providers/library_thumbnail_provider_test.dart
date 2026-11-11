import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/modules/library/di/library_providers.dart';
import 'package:grabby/modules/library/domain/usecases/get_library_thumbnail_usecase.dart';
import 'package:grabby/modules/library/presentation/providers/library_thumbnail_provider.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../support/mocks.dart';

void main() {
  const uri = 'content://media/external/video/media/7';
  const params = ThumbnailParams(uri: uri, widthPx: 480, heightPx: 300);

  late MockGetLibraryThumbnailUseCase getThumbnail;
  late ProviderContainer container;

  setUp(() {
    getThumbnail = MockGetLibraryThumbnailUseCase();
    container = ProviderContainer(
      overrides: [
        getLibraryThumbnailUseCaseProvider.overrideWithValue(getThumbnail),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<String?> thumbnail() {
    container.listen(libraryThumbnailProvider(uri), (_, _) {});
    return container.read(libraryThumbnailProvider(uri).future);
  }

  test('is the cached JPEG path, asked at 480 x 300 px', () async {
    when(
      () => getThumbnail(params),
    ).thenAnswer((_) async => const Ok('/cache/thumbs/7.jpg'));

    expect(await thumbnail(), '/cache/thumbs/7.jpg');
    verify(() => getThumbnail(params)).called(1);
  });

  test('is null when the file has no thumbnail', () async {
    when(() => getThumbnail(params)).thenAnswer((_) async => const Ok(null));

    expect(await thumbnail(), isNull);
  });

  test('is null on a failure, so the card keeps its stripes', () async {
    when(
      () => getThumbnail(params),
    ).thenAnswer((_) async => const Err(StorageFailure()));

    expect(await thumbnail(), isNull);
  });

  group('once the card stops listening', () {
    Future<String?> readAndRelease() async {
      final subscription = container.listen(
        libraryThumbnailProvider(uri),
        (_, _) {},
      );
      final value = await container.read(libraryThumbnailProvider(uri).future);
      subscription.close();
      await container.pump();
      return value;
    }

    test('a failure is not kept: the next read asks again', () async {
      when(
        () => getThumbnail(params),
      ).thenAnswer((_) async => const Err(StorageFailure()));
      expect(await readAndRelease(), isNull);

      when(
        () => getThumbnail(params),
      ).thenAnswer((_) async => const Ok('/cache/thumbs/7.jpg'));
      expect(await readAndRelease(), '/cache/thumbs/7.jpg');

      verify(() => getThumbnail(params)).called(2);
    });

    test('no thumbnail is kept for the session', () async {
      when(() => getThumbnail(params)).thenAnswer((_) async => const Ok(null));

      expect(await readAndRelease(), isNull);
      expect(await readAndRelease(), isNull);

      verify(() => getThumbnail(params)).called(1);
    });

    test('a path is kept for the session', () async {
      when(
        () => getThumbnail(params),
      ).thenAnswer((_) async => const Ok('/cache/thumbs/7.jpg'));

      expect(await readAndRelease(), '/cache/thumbs/7.jpg');
      expect(await readAndRelease(), '/cache/thumbs/7.jpg');

      verify(() => getThumbnail(params)).called(1);
    });
  });
}
