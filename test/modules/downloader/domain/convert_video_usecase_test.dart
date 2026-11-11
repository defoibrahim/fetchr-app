import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/modules/downloader/domain/usecases/convert_video_usecase.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/mocks.dart';

void main() {
  const uri = 'content://media/picker/0/v/7';
  late MockDownloaderRepository repository;
  late ConvertVideoUseCase useCase;

  setUp(() {
    repository = MockDownloaderRepository();
    useCase = ConvertVideoUseCase(repository);
  });

  test('queues the picked video in the folder', () async {
    when(() => repository.pickVideo()).thenAnswer((_) async => const Ok(uri));
    when(
      () => repository.convertToMp3(uri, 'Fetchr'),
    ).thenAnswer((_) async => const Ok<void>(null));

    expect(await useCase('Fetchr'), const Ok(true));
    verify(() => repository.convertToMp3(uri, 'Fetchr')).called(1);
  });

  test('a closed picker queues nothing', () async {
    when(
      () => repository.pickVideo(),
    ).thenAnswer((_) async => const Ok<String?>(null));

    expect(await useCase('Fetchr'), const Ok(false));
    verifyNever(() => repository.convertToMp3(any(), any()));
  });

  test('passes a failure of either step through', () async {
    const failure = UnexpectedFailure('x');
    when(
      () => repository.pickVideo(),
    ).thenAnswer((_) async => const Err<String?>(failure));
    expect(await useCase('Fetchr'), const Err<bool>(failure));

    when(() => repository.pickVideo()).thenAnswer((_) async => const Ok(uri));
    when(
      () => repository.convertToMp3(any(), any()),
    ).thenAnswer((_) async => const Err<void>(MediaUnavailableFailure()));
    expect(await useCase('Fetchr'), const Err<bool>(MediaUnavailableFailure()));
  });
}
