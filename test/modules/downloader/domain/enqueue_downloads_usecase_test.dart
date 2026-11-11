import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/shared/domain/entities/quality.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/modules/downloader/domain/usecases/enqueue_downloads_usecase.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/fixtures.dart';
import '../../../support/mocks.dart';

void main() {
  final requests = [
    downloadRequest(title: 'v', quality: Quality.p720, useAria2c: true),
  ];
  late MockDownloaderRepository repository;
  late EnqueueDownloadsUseCase useCase;

  setUp(() {
    repository = MockDownloaderRepository();
    useCase = EnqueueDownloadsUseCase(repository);
  });

  test('hands the requests to the repository', () async {
    when(
      () => repository.enqueue(requests),
    ).thenAnswer((_) async => const Ok<void>(null));

    final result = await useCase(requests);

    expect(result.isOk, isTrue);
    verify(() => repository.enqueue(requests)).called(1);
  });

  test('passes a failure through unchanged', () async {
    const failure = StorageFailure();
    when(
      () => repository.enqueue(requests),
    ).thenAnswer((_) async => const Err<void>(failure));

    final result = await useCase(requests);

    expect(result.failureOrNull, failure);
  });
}
