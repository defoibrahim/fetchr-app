import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/modules/downloader/di/downloader_providers.dart';
import 'package:grabby/modules/downloader/domain/entities/download_task.dart';
import 'package:grabby/modules/downloader/domain/entities/playlist_download.dart';
import 'package:grabby/modules/downloader/presentation/providers/downloads_notifier.dart';
import 'package:grabby/modules/downloader/presentation/providers/playlist_download_provider.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../support/fixtures.dart';
import '../../../../support/mocks.dart';

void main() {
  late StreamController<List<DownloadTask>> tasks;
  late MockCancelDownloadUseCase cancel;
  late MockRetryDownloadUseCase retry;
  late MockPauseDownloadUseCase pause;
  late MockResumeDownloadUseCase resume;
  late MockRemoveDownloadUseCase remove;
  late MockReorderQueueUseCase reorder;
  late ProviderContainer container;
  late List<String> calls;

  DownloadsNotifier notifier() =>
      container.read(downloadsNotifierProvider.notifier);

  PlaylistDownload? playlist() =>
      container.read(playlistDownloadProvider('Road trip'));

  // 1 done, 2 running, 3 to 5 waiting.
  final snapshot = [
    playlistTask(1, status: TaskStatus.completed),
    playlistTask(2, status: TaskStatus.running, progress: .4),
    playlistTask(3),
    playlistTask(4),
    playlistTask(5),
  ];

  Future<void> emit(List<DownloadTask> list) async {
    tasks.add(list);
    await pumpEventQueue();
  }

  setUp(() async {
    calls = [];
    tasks = StreamController<List<DownloadTask>>();
    final watch = MockWatchDownloadsUseCase();
    when(() => watch()).thenAnswer((_) => tasks.stream);
    cancel = MockCancelDownloadUseCase();
    retry = MockRetryDownloadUseCase();
    pause = MockPauseDownloadUseCase();
    resume = MockResumeDownloadUseCase();
    remove = MockRemoveDownloadUseCase();
    reorder = MockReorderQueueUseCase();
    Future<Result<void>> Function(Invocation) log(String name) =>
        (invocation) async {
          calls.add('$name ${invocation.positionalArguments.first}');
          return const Ok(null);
        };
    when(() => cancel(any())).thenAnswer(log('cancel'));
    when(() => retry(any())).thenAnswer(log('retry'));
    when(() => pause(any())).thenAnswer(log('pause'));
    when(() => resume(any())).thenAnswer(log('resume'));
    when(() => reorder(any())).thenAnswer(log('reorder'));
    when(() => remove(any())).thenAnswer((invocation) async {
      calls.add('remove ${invocation.positionalArguments.first}');
      return const Ok(true);
    });
    container = ProviderContainer(
      overrides: [
        watchDownloadsUseCaseProvider.overrideWithValue(watch),
        cancelDownloadUseCaseProvider.overrideWithValue(cancel),
        retryDownloadUseCaseProvider.overrideWithValue(retry),
        pauseDownloadUseCaseProvider.overrideWithValue(pause),
        resumeDownloadUseCaseProvider.overrideWithValue(resume),
        removeDownloadUseCaseProvider.overrideWithValue(remove),
        reorderQueueUseCaseProvider.overrideWithValue(reorder),
      ],
    );
    container.listen(playlistDownloadProvider('Road trip'), (_, _) {});
    await emit(snapshot);
  });

  tearDown(() async {
    container.dispose();
    await tasks.close();
  });

  test('the provider reads the playlist off the task stream', () {
    final p = playlist()!;

    expect(p.done, 1);
    expect(p.remaining, 4);
    expect(p.current?.id, 'v2');
    expect(p.upNext.map((i) => i.id), ['v3', 'v4', 'v5']);
    expect(p.isPaused, isFalse);
  });

  test('pause holds the waiting videos before the running one, resume '
      'brings back only the paused ones', () async {
    await notifier().pausePlaylist('Road trip');
    expect(calls, ['pause v3', 'pause v4', 'pause v5', 'pause v2']);

    calls.clear();
    await emit([
      snapshot[0],
      playlistTask(2, status: TaskStatus.paused, progress: .4),
      playlistTask(3, status: TaskStatus.paused),
      playlistTask(4, status: TaskStatus.paused),
      playlistTask(5, status: TaskStatus.paused),
    ]);
    expect(playlist()!.isPaused, isTrue);
    expect(playlist()!.current?.id, 'v2');

    await notifier().resumePlaylist('Road trip');
    expect(calls, ['resume v2', 'resume v3', 'resume v4', 'resume v5']);
  });

  test('skip cancels the video; its undo queues it again in its old '
      'place', () async {
    final before = [for (final item in playlist()!.upNext) item.id];

    await notifier().skip('v4');
    await notifier().unskip('v4', order: before);

    expect(calls, ['cancel v4', 'retry v4', 'reorder [v3, v4, v5]']);
  });

  test('a failed retry does not reorder', () async {
    when(
      () => retry(any()),
    ).thenAnswer((_) async => const Err(YtDlpBusyFailure()));

    final result = await notifier().unskip('v4', order: const ['v4']);

    expect(result.isOk, isFalse);
    verifyNever(() => reorder(any()));
  });

  test('retry queues a failed video again', () async {
    await notifier().retry('v3');

    expect(calls, ['retry v3']);
  });

  test('reorder shows the new order at once and tells native', () async {
    await notifier().reorderQueue(['v5', 'v3', 'v4']);

    expect(playlist()!.upNext.map((i) => i.id), ['v5', 'v3', 'v4']);
    expect(calls, ['reorder [v5, v3, v4]']);
  });

  group('stop', () {
    test('pauses and hides what is left, keeping the finished '
        'videos', () async {
      final stop = (await notifier().stopPlaylist('Road trip')).valueOrNull!;

      expect(calls, ['pause v3', 'pause v4', 'pause v5', 'pause v2']);
      expect(stop.kept, 1);
      expect(stop.unfinished, ['v2', 'v3', 'v4', 'v5']);
      expect(playlist(), isNull);
      expect(container.read(downloadsNotifierProvider).requireValue, [
        snapshot[0],
      ]);
    });

    test('undo shows it again and resumes what stop paused', () async {
      final stop = (await notifier().stopPlaylist('Road trip')).valueOrNull!;
      calls.clear();

      await notifier().undoStop(stop);

      expect(calls, ['resume v2', 'resume v3', 'resume v4', 'resume v5']);
      expect(playlist()?.items.length, 5);
    });

    test('commit removes what it had left', () async {
      final stop = (await notifier().stopPlaylist('Road trip')).valueOrNull!;
      calls.clear();

      final result = await notifier().commitStop(stop);

      expect(result.valueOrNull, isTrue);
      expect(calls, ['remove v2', 'remove v3', 'remove v4', 'remove v5']);
    });
  });
}
