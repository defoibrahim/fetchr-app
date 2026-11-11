import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/modules/downloader/di/downloader_providers.dart';
import 'package:grabby/modules/downloader/domain/entities/download_task.dart';
import 'package:grabby/modules/downloader/presentation/providers/downloads_notifier.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../support/fixtures.dart';
import '../../../../support/mocks.dart';

void main() {
  const failure = YtDlpBusyFailure();

  late StreamController<List<DownloadTask>> tasks;
  late MockCancelDownloadUseCase cancel;
  late MockRetryDownloadUseCase retry;
  late MockPauseDownloadUseCase pause;
  late MockResumeDownloadUseCase resume;
  late MockRemoveDownloadUseCase remove;
  late MockOpenDownloadFolderUseCase openFolder;
  late ProviderContainer container;

  AsyncValue<List<DownloadTask>> state() =>
      container.read(downloadsNotifierProvider);

  DownloadsNotifier notifier() =>
      container.read(downloadsNotifierProvider.notifier);

  setUp(() {
    tasks = StreamController<List<DownloadTask>>();
    final watch = MockWatchDownloadsUseCase();
    when(() => watch()).thenAnswer((_) => tasks.stream);
    cancel = MockCancelDownloadUseCase();
    retry = MockRetryDownloadUseCase();
    pause = MockPauseDownloadUseCase();
    resume = MockResumeDownloadUseCase();
    remove = MockRemoveDownloadUseCase();
    openFolder = MockOpenDownloadFolderUseCase();
    container = ProviderContainer(
      overrides: [
        watchDownloadsUseCaseProvider.overrideWithValue(watch),
        cancelDownloadUseCaseProvider.overrideWithValue(cancel),
        retryDownloadUseCaseProvider.overrideWithValue(retry),
        pauseDownloadUseCaseProvider.overrideWithValue(pause),
        resumeDownloadUseCaseProvider.overrideWithValue(resume),
        removeDownloadUseCaseProvider.overrideWithValue(remove),
        openDownloadFolderUseCaseProvider.overrideWithValue(openFolder),
      ],
    );
    // An autoDispose provider lives only while something listens to it.
    container.listen(downloadsNotifierProvider, (_, _) {});
  });

  tearDown(() async {
    container.dispose();
    await tasks.close();
  });

  test('is loading until the first snapshot', () {
    expect(state().isLoading, isTrue);
  });

  test('every snapshot replaces the list', () async {
    final running = downloadTask(id: 'a', status: TaskStatus.running);
    final done = downloadTask(id: 'a', status: TaskStatus.completed);

    tasks.add([running]);
    await pumpEventQueue();
    expect(state().requireValue, [running]);

    tasks.add([done, downloadTask(id: 'b', status: TaskStatus.queued)]);
    await pumpEventQueue();
    expect(state().requireValue.map((t) => t.id), ['a', 'b']);
    expect(state().requireValue.first.status, TaskStatus.completed);
  });

  test('a stream error is shown, not retried', () async {
    tasks.addError(failure);
    await pumpEventQueue();

    expect(state().error, failure);
  });

  group('hiding a task for Undo', () {
    final a = downloadTask(id: 'a', status: TaskStatus.completed);
    final b = downloadTask(id: 'b', status: TaskStatus.completed);

    Future<void> emit(List<DownloadTask> snapshot) async {
      tasks.add(snapshot);
      await pumpEventQueue();
    }

    test(
      'hide drops the task from the state and unhide brings it back',
      () async {
        await emit([a, b]);

        notifier().hide('a');
        expect(state().requireValue, [b]);

        notifier().unhide('a');
        expect(state().requireValue, [a, b]);
      },
    );

    test('a snapshot while hidden keeps the task hidden', () async {
      await emit([a, b]);
      notifier().hide('a');

      await emit([a, b, downloadTask(id: 'c', status: TaskStatus.queued)]);

      expect(state().requireValue.map((t) => t.id), ['b', 'c']);
    });

    test('hiding before the first snapshot hides it once it lands', () async {
      notifier().hide('a');
      expect(state().isLoading, isTrue);

      await emit([a, b]);

      expect(state().requireValue, [b]);
    });

    test('forgets the id once native stops reporting the task', () async {
      await emit([a, b]);
      notifier().hide('a');

      await emit([b]);
      await emit([a, b]);

      expect(state().requireValue, [a, b]);
    });

    test('unhide after a stream error keeps the error', () async {
      await emit([a]);
      notifier().hide('a');
      tasks.addError(failure);
      await pumpEventQueue();

      notifier().unhide('a');

      expect(state().error, failure);
    });

    test('hide and unhide after dispose do nothing', () async {
      await emit([a]);
      final disposed = notifier();
      container.dispose();

      expect(() => disposed.hide('a'), returnsNormally);
      expect(() => disposed.unhide('a'), returnsNormally);
    });
  });

  group('actions', () {
    test('cancel passes the id and returns the result', () async {
      when(() => cancel('a')).thenAnswer((_) async => const Ok<void>(null));

      expect(await notifier().cancel('a'), const Ok<void>(null));
      verify(() => cancel('a')).called(1);
    });

    test('retry passes the id and returns the failure', () async {
      when(() => retry('a')).thenAnswer((_) async => const Err(failure));

      expect(await notifier().retry('a'), const Err<void>(failure));
      verify(() => retry('a')).called(1);
    });

    test('pause passes the id and returns the result', () async {
      when(() => pause('a')).thenAnswer((_) async => const Ok<void>(null));

      expect(await notifier().pause('a'), const Ok<void>(null));
      verify(() => pause('a')).called(1);
      verifyNever(() => resume(any()));
    });

    test('resume passes the id and returns the failure', () async {
      when(() => resume('a')).thenAnswer((_) async => const Err(failure));

      expect(await notifier().resume('a'), const Err<void>(failure));
      verify(() => resume('a')).called(1);
      verifyNever(() => pause(any()));
    });

    test('remove passes the id and returns the result', () async {
      when(() => remove('a')).thenAnswer((_) async => const Ok(true));

      expect(await notifier().remove('a'), const Ok(true));
      verify(() => remove('a')).called(1);
    });

    test('remove after dispose deletes nothing', () async {
      final disposed = notifier();
      container.dispose();

      expect(await disposed.remove('a'), const Ok(false));
      verifyNever(() => remove(any()));
    });

    test('openFolder passes the uri and returns the result', () async {
      when(
        () => openFolder('uri'),
      ).thenAnswer((_) async => const Ok<void>(null));

      expect(await notifier().openFolder('uri'), const Ok<void>(null));
      verify(() => openFolder('uri')).called(1);
    });
  });
}
