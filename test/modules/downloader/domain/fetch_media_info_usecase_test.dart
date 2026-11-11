import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/modules/downloader/domain/usecases/fetch_media_info_usecase.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/fixtures.dart';
import '../../../support/mocks.dart';

void main() {
  const url = 'https://example.com/v';
  late MockDownloaderRepository repository;
  late FetchMediaInfoUseCase useCase;

  setUp(() {
    repository = MockDownloaderRepository();
    useCase = FetchMediaInfoUseCase(repository);
  });

  test('returns the repository info for the url', () async {
    final info = mediaInfo(url: url);
    when(() => repository.fetchInfo(url)).thenAnswer((_) async => Ok(info));

    final result = await useCase(url);

    expect(result, Ok(info));
    verify(() => repository.fetchInfo(url)).called(1);
  });

  test('passes a failure through unchanged', () async {
    const failure = UnsupportedSiteFailure();
    when(
      () => repository.fetchInfo(url),
    ).thenAnswer((_) async => const Err(failure));

    final result = await useCase(url);

    expect(result.failureOrNull, failure);
  });
}
