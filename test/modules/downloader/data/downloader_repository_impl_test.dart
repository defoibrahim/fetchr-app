import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/shared/domain/entities/quality.dart';
import 'package:grabby/core/errors/error_messages.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/core/platform/fetchr_api.g.dart' as api;
import 'package:grabby/modules/downloader/data/repositories/downloader_repository_impl.dart';
import 'package:grabby/modules/downloader/domain/entities/download_request.dart';
import 'package:grabby/modules/downloader/domain/entities/download_task.dart';
import 'package:grabby/modules/downloader/domain/entities/format_option.dart';
import 'package:grabby/modules/downloader/domain/entities/media_info.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/mocks.dart';

const _qualities = {
  api.Quality.best: Quality.best,
  api.Quality.p1080: Quality.p1080,
  api.Quality.p720: Quality.p720,
  api.Quality.p480: Quality.p480,
  api.Quality.mp3: Quality.mp3,
  api.Quality.cover: Quality.cover,
};

const _statuses = {
  api.TaskStatus.queued: TaskStatus.queued,
  api.TaskStatus.running: TaskStatus.running,
  api.TaskStatus.completed: TaskStatus.completed,
  api.TaskStatus.failed: TaskStatus.failed,
  api.TaskStatus.canceled: TaskStatus.canceled,
  api.TaskStatus.paused: TaskStatus.paused,
};

const _stages = {
  api.TaskStage.preparing: TaskStage.preparing,
  api.TaskStage.downloading: TaskStage.downloading,
  api.TaskStage.postProcessing: TaskStage.postProcessing,
};

const _url = 'https://example.com/v';

api.DownloadRequest _apiRequest([api.Quality quality = api.Quality.p720]) =>
    api.DownloadRequest(
      url: _url,
      title: 'Title',
      thumbnail: 'https://example.com/t.jpg',
      quality: quality,
      folder: 'Fetchr',
      useAria2c: true,
    );

DownloadRequest _request([Quality quality = Quality.p720]) => DownloadRequest(
  url: _url,
  title: 'Title',
  thumbnail: 'https://example.com/t.jpg',
  quality: quality,
  folder: 'Fetchr',
  useAria2c: true,
);

api.DownloadTask _apiTask({
  String id = 'task-1',
  api.TaskStatus status = api.TaskStatus.running,
  double progress = 0.5,
  int etaSeconds = 12,
  String? errorCode,
  String? errorMessage,
  String? savedUri,
  api.DownloadRequest? request,
  api.TaskStage stage = api.TaskStage.preparing,
  int? downloadedBytes,
  int? totalBytes,
  int? speedBytesPerSec,
  bool stalled = false,
  int? finishedAtMs,
}) => api.DownloadTask(
  id: id,
  request: request ?? _apiRequest(),
  status: status,
  progress: progress,
  etaSeconds: etaSeconds,
  errorCode: errorCode,
  errorMessage: errorMessage,
  savedUri: savedUri,
  createdAtMs: 1700000000000,
  stage: stage,
  downloadedBytes: downloadedBytes,
  totalBytes: totalBytes,
  speedBytesPerSec: speedBytesPerSec,
  stalled: stalled,
  finishedAtMs: finishedAtMs,
);

void main() {
  late MockFetchrHostApi hostApi;
  late MockNetworkInfo network;
  late StreamController<api.DownloadsSnapshot> snapshots;
  late int downloadsCalls;
  late DownloaderRepositoryImpl repository;

  setUp(() {
    hostApi = MockFetchrHostApi();
    network = MockNetworkInfo();
    snapshots = StreamController<api.DownloadsSnapshot>.broadcast();
    downloadsCalls = 0;
    when(() => network.isConnected).thenAnswer((_) async => true);
    repository = DownloaderRepositoryImpl(hostApi, network, () {
      downloadsCalls++;
      return snapshots.stream;
    });
  });

  tearDown(() => snapshots.close());

  group('fetchInfo', () {
    test('offline returns NetworkFailure without calling native', () async {
      when(() => network.isConnected).thenAnswer((_) async => false);

      final result = await repository.fetchInfo(_url);

      expect(result.failureOrNull, const NetworkFailure());
      verifyNever(() => hostApi.fetchInfo(any()));
    });

    test('maps every field of a single video', () async {
      when(() => hostApi.fetchInfo(_url)).thenAnswer(
        (_) async => api.VideoInfo(
          url: _url,
          title: 'Title',
          thumbnail: 'https://example.com/t.jpg',
          durationSeconds: 125,
          uploader: 'Someone',
          isPlaylist: false,
          isLive: false,
          options: [
            api.FormatOption(
              quality: api.Quality.best,
              width: 1920,
              height: 1080,
              fps: 59.94,
              sizeBytes: 13800000,
              sizeIsEstimate: true,
            ),
            api.FormatOption(quality: api.Quality.mp3, sizeIsEstimate: false),
            api.FormatOption(
              quality: api.Quality.cover,
              width: 720,
              height: 1280,
              sizeIsEstimate: false,
            ),
          ],
          entries: [],
        ),
      );

      final result = await repository.fetchInfo(_url);

      expect(
        result,
        const Ok(
          MediaInfo(
            url: _url,
            title: 'Title',
            thumbnail: 'https://example.com/t.jpg',
            durationSec: 125,
            uploader: 'Someone',
            isPlaylist: false,
            options: [
              FormatOption(
                quality: Quality.best,
                width: 1920,
                height: 1080,
                fps: 59.94,
                sizeBytes: 13800000,
                sizeIsEstimate: true,
              ),
              FormatOption(quality: Quality.mp3),
              FormatOption(quality: Quality.cover, width: 720, height: 1280),
            ],
            entries: [],
          ),
        ),
      );
    });

    test('maps a playlist with its entries and keeps nulls null', () async {
      when(() => hostApi.fetchInfo(_url)).thenAnswer(
        (_) async => api.VideoInfo(
          url: _url,
          title: 'List',
          isPlaylist: true,
          isLive: false,
          options: [
            api.FormatOption(quality: api.Quality.best, sizeIsEstimate: false),
          ],
          entries: [
            api.PlaylistEntry(
              url: 'https://example.com/1',
              title: 'One',
              thumbnail: 'https://example.com/1.jpg',
              durationSeconds: 60,
            ),
            api.PlaylistEntry(url: 'https://example.com/2', title: 'Two'),
          ],
        ),
      );

      final result = await repository.fetchInfo(_url);

      expect(
        result,
        const Ok(
          MediaInfo(
            url: _url,
            title: 'List',
            isPlaylist: true,
            options: [FormatOption(quality: Quality.best)],
            entries: [
              PlaylistEntry(
                url: 'https://example.com/1',
                title: 'One',
                thumbnail: 'https://example.com/1.jpg',
                durationSec: 60,
              ),
              PlaylistEntry(url: 'https://example.com/2', title: 'Two'),
            ],
          ),
        ),
      );
    });

    test('maps isLive', () async {
      when(() => hostApi.fetchInfo(_url)).thenAnswer(
        (_) async => api.VideoInfo(
          url: _url,
          title: 'Live',
          isPlaylist: false,
          isLive: true,
          options: [],
          entries: [],
        ),
      );

      final result = await repository.fetchInfo(_url);

      expect(result.valueOrNull?.isLive, isTrue);
    });

    test('a source with no options downloads as best', () async {
      when(() => hostApi.fetchInfo(_url)).thenAnswer(
        (_) async => api.VideoInfo(
          url: _url,
          title: 'Bare',
          isPlaylist: false,
          isLive: false,
          options: [],
          entries: [],
        ),
      );

      final result = await repository.fetchInfo(_url);

      expect(result.valueOrNull?.options, const [
        FormatOption(quality: Quality.best),
      ]);
    });

    test('maps every Quality value', () async {
      when(() => hostApi.fetchInfo(_url)).thenAnswer(
        (_) async => api.VideoInfo(
          url: _url,
          title: 'Title',
          isPlaylist: false,
          isLive: false,
          options: [
            for (final q in _qualities.keys)
              api.FormatOption(quality: q, sizeIsEstimate: false),
          ],
          entries: [],
        ),
      );

      final result = await repository.fetchInfo(_url);

      expect(
        result.valueOrNull?.options.map((o) => o.quality),
        _qualities.values.toList(),
      );
    });

    test('maps a PlatformException', () async {
      when(
        () => hostApi.fetchInfo(_url),
      ).thenThrow(PlatformException(code: 'private_video', message: 'native'));

      final result = await repository.fetchInfo(_url);

      expect(result.failureOrNull, const PrivateVideoFailure());
    });

    test('a non-platform error becomes UnexpectedFailure', () async {
      when(() => hostApi.fetchInfo(_url)).thenThrow(StateError('boom'));

      final result = await repository.fetchInfo(_url);

      expect(result.failureOrNull, const UnexpectedFailure());
    });
  });

  group('enqueue', () {
    test('maps every request field and quality to the pigeon DTO', () async {
      when(() => hostApi.enqueue(any())).thenAnswer((_) async {});

      final requests = [for (final q in _qualities.values) _request(q)];
      final result = await repository.enqueue(requests);

      expect(result.isOk, isTrue);
      verify(
        () =>
            hostApi.enqueue([for (final q in _qualities.keys) _apiRequest(q)]),
      ).called(1);
    });

    test('keeps a missing thumbnail null', () async {
      when(() => hostApi.enqueue(any())).thenAnswer((_) async {});

      await repository.enqueue(const [
        DownloadRequest(
          url: _url,
          title: 'Title',
          quality: Quality.best,
          folder: 'Music',
          useAria2c: false,
        ),
      ]);

      verify(
        () => hostApi.enqueue([
          api.DownloadRequest(
            url: _url,
            title: 'Title',
            quality: api.Quality.best,
            folder: 'Music',
            useAria2c: false,
          ),
        ]),
      ).called(1);
    });

    test('maps the uploader, duration and playlist position', () async {
      when(() => hostApi.enqueue(any())).thenAnswer((_) async {});

      await repository.enqueue(const [
        DownloadRequest(
          url: _url,
          title: 'Title',
          quality: Quality.p720,
          folder: 'Fetchr',
          useAria2c: false,
          uploader: 'Someone',
          durationSec: 125,
          playlistTitle: 'Mix',
          playlistIndex: 3,
          playlistCount: 18,
        ),
      ]);

      verify(
        () => hostApi.enqueue([
          api.DownloadRequest(
            url: _url,
            title: 'Title',
            quality: api.Quality.p720,
            folder: 'Fetchr',
            useAria2c: false,
            uploader: 'Someone',
            durationSeconds: 125,
            playlistTitle: 'Mix',
            playlistIndex: 3,
            playlistCount: 18,
          ),
        ]),
      ).called(1);
    });

    test('does not check connectivity', () async {
      when(() => hostApi.enqueue(any())).thenAnswer((_) async {});

      await repository.enqueue([_request()]);

      verifyNever(() => network.isConnected);
    });

    test('maps a PlatformException', () async {
      when(
        () => hostApi.enqueue(any()),
      ).thenThrow(PlatformException(code: 'no_storage'));

      final result = await repository.enqueue([_request()]);

      expect(result.failureOrNull, const StorageFailure());
    });

    test('permission_denied is a StoragePermissionFailure', () async {
      when(
        () => hostApi.enqueue(any()),
      ).thenThrow(PlatformException(code: 'permission_denied'));

      final result = await repository.enqueue([_request()]);

      expect(result.failureOrNull, const StoragePermissionFailure());
    });
  });

  group('cancel, retry, pause and resume', () {
    final operations =
        <
          String,
          ({
            Future<Result<void>> Function(String) run,
            Future<void> Function() native,
          })
        >{
          'cancel': (
            run: (id) => repository.cancel(id),
            native: () => hostApi.cancel('task-1'),
          ),
          'retry': (
            run: (id) => repository.retry(id),
            native: () => hostApi.retry('task-1'),
          ),
          'pause': (
            run: (id) => repository.pause(id),
            native: () => hostApi.pause('task-1'),
          ),
          'resume': (
            run: (id) => repository.resume(id),
            native: () => hostApi.resume('task-1'),
          ),
        };

    for (final name in operations.keys) {
      test('$name calls native once with the id, offline or not', () async {
        final op = operations[name]!;
        when(op.native).thenAnswer((_) async {});

        final result = await op.run('task-1');

        expect(result.isOk, isTrue);
        verify(op.native).called(1);
        verifyNever(() => network.isConnected);
      });

      test('$name maps a PlatformException', () async {
        final op = operations[name]!;
        when(op.native).thenThrow(PlatformException(code: 'unavailable'));

        final result = await op.run('task-1');

        expect(result.failureOrNull, const MediaUnavailableFailure());
      });
    }
  });

  group('pauseAll and resumeAll', () {
    final operations =
        <
          String,
          ({
            Future<Result<void>> Function() run,
            Future<void> Function() native,
          })
        >{
          'pauseAll': (
            run: () => repository.pauseAll(),
            native: () => hostApi.pauseAll(),
          ),
          'resumeAll': (
            run: () => repository.resumeAll(),
            native: () => hostApi.resumeAll(),
          ),
        };

    for (final name in operations.keys) {
      test('$name calls native once, offline or not', () async {
        final op = operations[name]!;
        when(op.native).thenAnswer((_) async {});

        final result = await op.run();

        expect(result.isOk, isTrue);
        verify(op.native).called(1);
        verifyNever(() => network.isConnected);
      });

      test('$name maps a PlatformException', () async {
        final op = operations[name]!;
        when(op.native).thenThrow(PlatformException(code: 'unknown'));

        final result = await op.run();

        expect(result.failureOrNull, isA<UnexpectedFailure>());
      });
    }
  });

  group('freeSpaceBytes', () {
    test(
      'returns the native byte count without a connectivity check',
      () async {
        when(
          () => hostApi.freeSpaceBytes(),
        ).thenAnswer((_) async => 5000000000);

        final result = await repository.freeSpaceBytes();

        expect(result.valueOrNull, 5000000000);
        verifyNever(() => network.isConnected);
      },
    );

    test('maps a PlatformException', () async {
      when(
        () => hostApi.freeSpaceBytes(),
      ).thenThrow(PlatformException(code: 'no_storage'));

      final result = await repository.freeSpaceBytes();

      expect(result.failureOrNull, const StorageFailure());
    });
  });

  group('remove', () {
    test('returns true when native deleted the file and the task', () async {
      when(() => hostApi.remove('task-1')).thenAnswer((_) async => true);

      final result = await repository.remove('task-1');

      expect(result.valueOrNull, isTrue);
      verify(() => hostApi.remove('task-1')).called(1);
    });

    test('returns false when the user declined the system dialog', () async {
      when(() => hostApi.remove('task-1')).thenAnswer((_) async => false);

      final result = await repository.remove('task-1');

      expect(result.valueOrNull, isFalse);
    });

    test('does not check connectivity', () async {
      when(() => hostApi.remove(any())).thenAnswer((_) async => true);

      await repository.remove('task-1');

      verifyNever(() => network.isConnected);
    });

    test('maps a PlatformException', () async {
      when(
        () => hostApi.remove('task-1'),
      ).thenThrow(PlatformException(code: 'no_storage'));

      final result = await repository.remove('task-1');

      expect(result.failureOrNull, const StorageFailure());
    });
  });

  group('pickVideo', () {
    test('returns the picked uri, or null when the user backed out', () async {
      when(() => hostApi.pickVideo()).thenAnswer((_) async => 'content://v/1');
      expect((await repository.pickVideo()).valueOrNull, 'content://v/1');

      when(() => hostApi.pickVideo()).thenAnswer((_) async => null);
      final closed = await repository.pickVideo();
      expect(closed.isOk, isTrue);
      expect(closed.valueOrNull, isNull);
      verifyNever(() => network.isConnected);
    });
  });

  group('convertToMp3', () {
    test('hands the uri and the folder to native, offline too', () async {
      when(
        () => hostApi.convertToMp3('content://v/1', 'Fetchr'),
      ).thenAnswer((_) async {});

      final result = await repository.convertToMp3('content://v/1', 'Fetchr');

      expect(result.isOk, isTrue);
      verify(() => hostApi.convertToMp3('content://v/1', 'Fetchr')).called(1);
      verifyNever(() => network.isConnected);
    });

    test('maps a PlatformException', () async {
      when(
        () => hostApi.convertToMp3(any(), any()),
      ).thenThrow(PlatformException(code: 'unavailable'));

      final result = await repository.convertToMp3('content://v/1', 'Fetchr');

      expect(result.failureOrNull, const MediaUnavailableFailure());
    });
  });

  group('openFolder', () {
    const uri = 'content://media/external/video/media/7';

    test('passes the uri to native', () async {
      when(() => hostApi.openFolder(uri)).thenAnswer((_) async {});

      final result = await repository.openFolder(uri);

      expect(result.isOk, isTrue);
      verify(() => hostApi.openFolder(uri)).called(1);
    });

    test('no_folder_app becomes the no folder app failure', () async {
      when(
        () => hostApi.openFolder(uri),
      ).thenThrow(PlatformException(code: 'no_folder_app'));

      final result = await repository.openFolder(uri);

      expect(
        result.failureOrNull,
        const UnexpectedFailure(ErrorMessages.noFolderApp),
      );
    });

    test('does not check connectivity', () async {
      when(() => hostApi.openFolder(any())).thenAnswer((_) async {});

      await repository.openFolder(uri);

      verifyNever(() => network.isConnected);
    });

    test('maps a PlatformException', () async {
      when(
        () => hostApi.openFolder(uri),
      ).thenThrow(PlatformException(code: 'unknown'));

      final result = await repository.openFolder(uri);

      expect(result.failureOrNull, isA<UnexpectedFailure>());
    });
  });

  group('watchTasks', () {
    test('maps every field of a snapshot task', () async {
      final tasks = repository.watchTasks().first;

      snapshots.add(
        api.DownloadsSnapshot(
          tasks: [
            _apiTask(
              status: api.TaskStatus.completed,
              progress: 1,
              etaSeconds: 0,
              savedUri: 'content://media/1',
            ),
          ],
        ),
      );

      expect(await tasks, [
        DownloadTask(
          id: 'task-1',
          request: _request(),
          status: TaskStatus.completed,
          progress: 1,
          etaSec: 0,
          savedUri: 'content://media/1',
          createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        ),
      ]);
    });

    test('maps progress stats, stage, stalled and the finish time', () async {
      final tasks = repository.watchTasks().first;

      snapshots.add(
        api.DownloadsSnapshot(
          tasks: [
            _apiTask(
              stage: api.TaskStage.downloading,
              downloadedBytes: 40000000,
              totalBytes: 100000000,
              speedBytesPerSec: 4200000,
              stalled: true,
              finishedAtMs: 1700000100000,
            ),
          ],
        ),
      );

      final task = (await tasks).single;
      expect(task.stage, TaskStage.downloading);
      expect(task.downloadedBytes, 40000000);
      expect(task.totalBytes, 100000000);
      expect(task.speedBytesPerSec, 4200000);
      expect(task.stalled, isTrue);
      expect(
        task.finishedAt,
        DateTime.fromMillisecondsSinceEpoch(1700000100000),
      );
    });

    test('unknown bytes, speed and finish time stay null', () async {
      final tasks = repository.watchTasks().first;

      snapshots.add(api.DownloadsSnapshot(tasks: [_apiTask()]));

      final task = (await tasks).single;
      expect(task.downloadedBytes, isNull);
      expect(task.totalBytes, isNull);
      expect(task.speedBytesPerSec, isNull);
      expect(task.finishedAt, isNull);
      expect(task.stalled, isFalse);
    });

    test('maps every TaskStage value', () async {
      final tasks = repository.watchTasks().first;

      snapshots.add(
        api.DownloadsSnapshot(
          tasks: [for (final s in _stages.keys) _apiTask(id: s.name, stage: s)],
        ),
      );

      expect((await tasks).map((t) => t.stage), _stages.values);
    });

    test('maps the request uploader, duration and playlist position', () async {
      final tasks = repository.watchTasks().first;

      snapshots.add(
        api.DownloadsSnapshot(
          tasks: [
            _apiTask(
              request: api.DownloadRequest(
                url: _url,
                title: 'Title',
                quality: api.Quality.p720,
                folder: 'Fetchr',
                useAria2c: false,
                uploader: 'Someone',
                durationSeconds: 125,
                playlistTitle: 'Mix',
                playlistIndex: 3,
                playlistCount: 18,
              ),
            ),
          ],
        ),
      );

      final request = (await tasks).single.request;
      expect(request.uploader, 'Someone');
      expect(request.durationSec, 125);
      expect(request.playlistTitle, 'Mix');
      expect(request.playlistIndex, 3);
      expect(request.playlistCount, 18);
    });

    test('a paused task keeps its progress and is not active', () async {
      final tasks = repository.watchTasks().first;

      snapshots.add(
        api.DownloadsSnapshot(
          tasks: [
            _apiTask(
              status: api.TaskStatus.paused,
              progress: 0.4,
              downloadedBytes: 40,
            ),
          ],
        ),
      );

      final task = (await tasks).single;
      expect(task.status, TaskStatus.paused);
      expect(task.isPaused, isTrue);
      expect(task.isActive, isFalse);
      expect(task.progress, 0.4);
      expect(task.downloadedBytes, 40);
    });

    test('maps every TaskStatus value', () async {
      final tasks = repository.watchTasks().first;

      snapshots.add(
        api.DownloadsSnapshot(
          tasks: [
            for (final s in _statuses.keys)
              _apiTask(
                id: s.name,
                status: s,
                errorCode: s == api.TaskStatus.failed ? 'network' : null,
              ),
          ],
        ),
      );

      expect((await tasks).map((t) => t.status), _statuses.values);
    });

    test('unknown progress and eta stay unknown', () async {
      final tasks = repository.watchTasks().first;

      snapshots.add(
        api.DownloadsSnapshot(tasks: [_apiTask(progress: -1, etaSeconds: -1)]),
      );

      final task = (await tasks).single;
      expect(task.progress, -1);
      expect(task.etaSec, isNull);
    });

    test('a failed task maps its code and drops the raw message', () async {
      final tasks = repository.watchTasks().first;

      snapshots.add(
        api.DownloadsSnapshot(
          tasks: [
            _apiTask(
              status: api.TaskStatus.failed,
              errorCode: 'network',
              errorMessage: 'ERROR: last yt-dlp line',
            ),
          ],
        ),
      );

      final task = (await tasks).single;
      expect(task.status, TaskStatus.failed);
      expect(task.failure, const NetworkFailure());
      expect(task.errorMessage, isNull);
    });

    test('a failed task without a code keeps the raw yt-dlp line', () async {
      final tasks = repository.watchTasks().first;

      snapshots.add(
        api.DownloadsSnapshot(
          tasks: [
            _apiTask(
              status: api.TaskStatus.failed,
              errorMessage: 'ERROR: last yt-dlp line',
            ),
          ],
        ),
      );

      final task = (await tasks).single;
      expect(
        task.failure,
        const UnexpectedFailure(ErrorMessages.downloadUnknown),
      );
      expect(task.errorMessage, 'ERROR: last yt-dlp line');
    });

    test('a task that has not failed carries no failure', () async {
      final tasks = repository.watchTasks().first;

      snapshots.add(
        api.DownloadsSnapshot(
          tasks: [
            _apiTask(status: api.TaskStatus.canceled, errorCode: 'unknown'),
          ],
        ),
      );

      expect((await tasks).single.failure, isNull);
    });

    test('emits an empty list for an empty snapshot', () async {
      final tasks = repository.watchTasks().first;

      snapshots.add(api.DownloadsSnapshot(tasks: []));

      expect(await tasks, isEmpty);
    });

    test('opens the native stream once however often it is watched', () async {
      final first = repository.watchTasks().first;
      final second = repository.watchTasks().first;

      snapshots.add(api.DownloadsSnapshot(tasks: [_apiTask()]));

      expect(await first, hasLength(1));
      expect(await second, hasLength(1));
      expect(downloadsCalls, 1);
    });

    test('a paused listener gets only the latest snapshot on resume', () async {
      final seen = <int>[];
      final sub = repository.watchTasks().listen((t) => seen.add(t.length));
      addTearDown(sub.cancel);
      snapshots.add(api.DownloadsSnapshot(tasks: [_apiTask()]));
      await pumpEventQueue();

      sub.pause();
      for (var n = 2; n <= 4; n++) {
        snapshots.add(
          api.DownloadsSnapshot(
            tasks: [for (var i = 0; i < n; i++) _apiTask(id: 'task-$i')],
          ),
        );
      }
      await pumpEventQueue();
      expect(seen, [1]);

      sub.resume();
      await pumpEventQueue();
      expect(seen, [1, 4]);
    });

    test('stops listening to the native stream when cancelled', () async {
      final sub = repository.watchTasks().listen((_) {});
      expect(snapshots.hasListener, isTrue);

      await sub.cancel();

      expect(snapshots.hasListener, isFalse);
    });

    test('does not open the native stream until watched', () {
      expect(downloadsCalls, 0);
    });
  });
}
