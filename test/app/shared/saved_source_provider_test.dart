import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/shared/saved_source_provider.dart';
import 'package:grabby/modules/downloader/di/downloader_providers.dart';
import 'package:grabby/modules/downloader/domain/entities/download_task.dart';
import 'package:grabby/modules/downloader/presentation/providers/downloads_notifier.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fixtures.dart';
import '../../support/mocks.dart';

void main() {
  const savedUri = 'content://media/external/video/media/7';

  late StreamController<List<DownloadTask>> tasks;
  late ProviderContainer container;

  setUp(() {
    tasks = StreamController<List<DownloadTask>>();
    final downloader = MockDownloaderRepository();
    when(downloader.watchTasks).thenAnswer((_) => tasks.stream);
    container = ProviderContainer(
      overrides: [downloaderRepositoryProvider.overrideWithValue(downloader)],
    );
    addTearDown(container.dispose);
    addTearDown(tasks.close);
  });

  DownloadTask completed({
    String id = 'a',
    String url = 'https://www.youtube.com/watch?v=1',
    String? uploader = 'Open Road Films',
    String? uri = savedUri,
  }) => downloadTask(
    id: id,
    status: TaskStatus.completed,
    savedUri: uri,
    request: downloadRequest(url: url, uploader: uploader),
  );

  // The provider is autoDispose and the tasks arrive on a stream.
  Future<String?> sourceAfter(List<DownloadTask> snapshot) async {
    container.listen(savedSourceProvider(savedUri), (_, _) {});
    tasks.add(snapshot);
    await container.read(downloadsNotifierProvider.future);
    return container.read(savedSourceProvider(savedUri));
  }

  test('is null until the downloads have loaded', () {
    container.listen(savedSourceProvider(savedUri), (_, _) {});

    expect(container.read(savedSourceProvider(savedUri)), isNull);
  });

  test(
    'is the site and the uploader of the task that saved the file',
    () async {
      expect(await sourceAfter([completed()]), 'youtube.com · Open Road Films');
    },
  );

  test('is just the site when the uploader is unknown or blank', () async {
    expect(await sourceAfter([completed(uploader: null)]), 'youtube.com');
    tasks.add([completed(uploader: '  ')]);
    await container.pump();
    expect(container.read(savedSourceProvider(savedUri)), 'youtube.com');
  });

  test('is null when no completed task saved that file', () async {
    final others = [
      completed(id: 'b', uri: 'content://media/external/video/media/8'),
      downloadTask(
        id: 'c',
        status: TaskStatus.running,
        savedUri: savedUri,
        request: downloadRequest(uploader: 'Someone'),
      ),
    ];

    expect(await sourceAfter(others), isNull);
  });

  test('picks the matching task out of several', () async {
    final snapshot = [
      completed(id: 'b', url: 'https://vimeo.com/2', uri: 'content://other'),
      completed(),
    ];

    expect(await sourceAfter(snapshot), 'youtube.com · Open Road Films');
  });

  test('follows the downloads as they change', () async {
    expect(await sourceAfter([completed()]), isNotNull);

    tasks.add(const []);
    await container.pump();

    expect(container.read(savedSourceProvider(savedUri)), isNull);
  });
}
