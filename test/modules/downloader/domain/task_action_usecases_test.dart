import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/core/usecase/base_use_case.dart';
import 'package:grabby/modules/downloader/domain/repositories/i_downloader_repository.dart';
import 'package:grabby/modules/downloader/domain/usecases/cancel_download_usecase.dart';
import 'package:grabby/modules/downloader/domain/usecases/get_free_space_usecase.dart';
import 'package:grabby/modules/downloader/domain/usecases/open_download_folder_usecase.dart';
import 'package:grabby/modules/downloader/domain/usecases/pause_all_downloads_usecase.dart';
import 'package:grabby/modules/downloader/domain/usecases/pause_download_usecase.dart';
import 'package:grabby/modules/downloader/domain/usecases/remove_download_usecase.dart';
import 'package:grabby/modules/downloader/domain/usecases/resume_all_downloads_usecase.dart';
import 'package:grabby/modules/downloader/domain/usecases/resume_download_usecase.dart';
import 'package:grabby/modules/downloader/domain/usecases/retry_download_usecase.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/mocks.dart';

typedef _Call = Future<Result<void>> Function(IDownloaderRepository, String);

class _Action {
  /// [repositoryCall] is the repository method the use case must forward to;
  /// [useCaseCall] runs the use case over that repository.
  _Action(this.name, this.repositoryCall, this.useCaseCall);

  final String name;
  final _Call repositoryCall;
  final _Call useCaseCall;
}

void main() {
  final actions = [
    _Action(
      'CancelDownloadUseCase',
      (repository, id) => repository.cancel(id),
      (repository, id) => CancelDownloadUseCase(repository)(id),
    ),
    _Action(
      'RetryDownloadUseCase',
      (repository, id) => repository.retry(id),
      (repository, id) => RetryDownloadUseCase(repository)(id),
    ),
    _Action(
      'PauseDownloadUseCase',
      (repository, id) => repository.pause(id),
      (repository, id) => PauseDownloadUseCase(repository)(id),
    ),
    _Action(
      'ResumeDownloadUseCase',
      (repository, id) => repository.resume(id),
      (repository, id) => ResumeDownloadUseCase(repository)(id),
    ),
    // These two act on every task and ignore the id.
    _Action(
      'PauseAllDownloadsUseCase',
      (repository, _) => repository.pauseAll(),
      (repository, _) => PauseAllDownloadsUseCase(repository)(const NoParams()),
    ),
    _Action(
      'ResumeAllDownloadsUseCase',
      (repository, _) => repository.resumeAll(),
      (repository, _) =>
          ResumeAllDownloadsUseCase(repository)(const NoParams()),
    ),
  ];

  late MockDownloaderRepository repository;

  setUp(() => repository = MockDownloaderRepository());

  for (final action in actions) {
    group(action.name, () {
      test('forwards to the repository', () async {
        when(
          () => action.repositoryCall(repository, 'task-1'),
        ).thenAnswer((_) async => const Ok<void>(null));

        final result = await action.useCaseCall(repository, 'task-1');

        expect(result.isOk, isTrue);
        verify(() => action.repositoryCall(repository, 'task-1')).called(1);
      });

      test('passes a failure through unchanged', () async {
        const failure = UnexpectedFailure();
        when(
          () => action.repositoryCall(repository, 'task-1'),
        ).thenAnswer((_) async => const Err<void>(failure));

        final result = await action.useCaseCall(repository, 'task-1');

        expect(result.failureOrNull, failure);
      });
    });
  }

  group('GetFreeSpaceUseCase', () {
    test('returns the free bytes', () async {
      when(
        () => repository.freeSpaceBytes(),
      ).thenAnswer((_) async => const Ok(5000000000));

      final result = await GetFreeSpaceUseCase(repository)(const NoParams());

      expect(result.valueOrNull, 5000000000);
    });

    test('passes a failure through unchanged', () async {
      const failure = StorageFailure();
      when(
        () => repository.freeSpaceBytes(),
      ).thenAnswer((_) async => const Err<int>(failure));

      final result = await GetFreeSpaceUseCase(repository)(const NoParams());

      expect(result.failureOrNull, failure);
    });
  });

  group('RemoveDownloadUseCase', () {
    test('forwards the id and returns true when deleted', () async {
      when(
        () => repository.remove('task-1'),
      ).thenAnswer((_) async => const Ok(true));

      final result = await RemoveDownloadUseCase(repository)('task-1');

      expect(result.valueOrNull, isTrue);
      verify(() => repository.remove('task-1')).called(1);
    });

    test('returns false when the user declined', () async {
      when(
        () => repository.remove('task-1'),
      ).thenAnswer((_) async => const Ok(false));

      final result = await RemoveDownloadUseCase(repository)('task-1');

      expect(result.valueOrNull, isFalse);
    });

    test('passes a failure through unchanged', () async {
      const failure = UnexpectedFailure();
      when(
        () => repository.remove('task-1'),
      ).thenAnswer((_) async => const Err<bool>(failure));

      final result = await RemoveDownloadUseCase(repository)('task-1');

      expect(result.failureOrNull, failure);
    });
  });

  group('OpenDownloadFolderUseCase', () {
    const uri = 'content://media/external/video/media/7';

    test('forwards the uri', () async {
      when(
        () => repository.openFolder(uri),
      ).thenAnswer((_) async => const Ok<void>(null));

      final result = await OpenDownloadFolderUseCase(repository)(uri);

      expect(result.isOk, isTrue);
      verify(() => repository.openFolder(uri)).called(1);
    });

    test('passes a failure through unchanged', () async {
      const failure = UnexpectedFailure();
      when(
        () => repository.openFolder(uri),
      ).thenAnswer((_) async => const Err<void>(failure));

      final result = await OpenDownloadFolderUseCase(repository)(uri);

      expect(result.failureOrNull, failure);
    });
  });
}
