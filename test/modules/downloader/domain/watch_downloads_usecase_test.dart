import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/modules/downloader/domain/entities/download_task.dart';
import 'package:grabby/modules/downloader/domain/usecases/watch_downloads_usecase.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/fixtures.dart';
import '../../../support/mocks.dart';

void main() {
  test('exposes the repository task stream', () async {
    final tasks = [downloadTask(progress: 0.5)];
    final repository = MockDownloaderRepository();
    when(
      () => repository.watchTasks(),
    ).thenAnswer((_) => Stream.fromIterable([const <DownloadTask>[], tasks]));

    final emitted = await WatchDownloadsUseCase(repository)().toList();

    expect(emitted, [const <DownloadTask>[], tasks]);
    verify(() => repository.watchTasks()).called(1);
  });
}
