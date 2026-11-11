import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/modules/downloader/domain/entities/download_task.dart';

import '../../../support/fixtures.dart';

void main() {
  group('DownloadTask', () {
    const active = {TaskStatus.queued, TaskStatus.running};

    for (final status in TaskStatus.values) {
      test('${status.name}: isActive only while queued or running', () {
        expect(downloadTask(status: status).isActive, active.contains(status));
      });
    }

    test('isPaused only while paused, and a paused task is not active', () {
      for (final status in TaskStatus.values) {
        expect(
          downloadTask(status: status).isPaused,
          status == TaskStatus.paused,
        );
      }
      expect(downloadTask(status: TaskStatus.paused).isActive, isFalse);
    });

    test('a new task is preparing, not stalled, with no stats', () {
      final task = downloadTask();

      expect(task.stage, TaskStage.preparing);
      expect(task.stalled, isFalse);
      expect(task.downloadedBytes, isNull);
      expect(task.totalBytes, isNull);
      expect(task.speedBytesPerSec, isNull);
      expect(task.finishedAt, isNull);
    });

    test('fileUri is the saved uri only once completed', () {
      const uri = 'content://media/external/video/media/1';

      expect(
        downloadTask(status: TaskStatus.completed, savedUri: uri).fileUri,
        uri,
      );
      expect(downloadTask(status: TaskStatus.completed).fileUri, isNull);
      for (final status in TaskStatus.values) {
        if (status == TaskStatus.completed) continue;
        expect(downloadTask(status: status, savedUri: uri).fileUri, isNull);
      }
    });

    test('compares by value', () {
      expect(
        downloadTask(status: TaskStatus.running),
        downloadTask(status: TaskStatus.running),
      );
      expect(
        downloadTask(status: TaskStatus.running),
        isNot(downloadTask(status: TaskStatus.failed)),
      );
    });
  });
}
