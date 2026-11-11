import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/modules/downloader/domain/entities/download_card_state.dart';
import 'package:grabby/modules/downloader/domain/entities/download_task.dart';
import 'package:grabby/modules/downloader/domain/extensions/download_task_extensions.dart';

import '../../../support/fixtures.dart';

void main() {
  group('groupedAt', () {
    final now = DateTime(2026, 10, 15, 16);

    List<String> ids(List<DownloadTask> tasks) =>
        tasks.map((t) => t.id).toList();

    test('splits by status and hides old completed', () {
      final g = [
        downloadTask(id: 'r', status: TaskStatus.running),
        downloadTask(id: 'p', status: TaskStatus.paused),
        downloadTask(id: 'c', status: TaskStatus.canceled),
        downloadTask(
          id: 'q1',
          status: TaskStatus.queued,
          createdAt: now.subtract(const Duration(minutes: 2)),
        ),
        downloadTask(
          id: 'q2',
          status: TaskStatus.queued,
          createdAt: now.subtract(const Duration(minutes: 1)),
        ),
        downloadTask(id: 'f', status: TaskStatus.failed),
        downloadTask(id: 'd', status: TaskStatus.completed, finishedAt: now),
        downloadTask(
          id: 'old',
          status: TaskStatus.completed,
          finishedAt: now.subtract(const Duration(days: 1)),
        ),
      ].groupedAt(now);

      expect(ids(g.active), ['r', 'p', 'c']);
      expect(ids(g.queued), ['q1', 'q2']);
      expect(ids(g.attention), ['f']);
      expect(ids(g.doneToday), ['d']);
      expect(g.isEmpty, isFalse);
    });

    test('keeps the snapshot order, which native sends newest first', () {
      final g = [
        downloadTask(id: 'r2', status: TaskStatus.running),
        downloadTask(id: 'f2', status: TaskStatus.failed),
        downloadTask(id: 'r1', status: TaskStatus.running),
        downloadTask(id: 'f1', status: TaskStatus.failed),
        downloadTask(id: 'd2', status: TaskStatus.completed, finishedAt: now),
        downloadTask(id: 'd1', status: TaskStatus.completed, finishedAt: now),
      ].groupedAt(now);

      expect(ids(g.active), ['r2', 'r1']);
      expect(ids(g.attention), ['f2', 'f1']);
      expect(ids(g.doneToday), ['d2', 'd1']);
    });

    test('queues the oldest batch first and keeps a batch in its order', () {
      // One enqueue call gives its tasks the same createdAt, and native lists
      // the newest batch first.
      final older = now.subtract(const Duration(minutes: 5));
      final g = [
        downloadTask(id: 'new1', status: TaskStatus.queued, createdAt: now),
        downloadTask(id: 'new2', status: TaskStatus.queued, createdAt: now),
        downloadTask(id: 'old1', status: TaskStatus.queued, createdAt: older),
        downloadTask(id: 'old2', status: TaskStatus.queued, createdAt: older),
        downloadTask(id: 'old3', status: TaskStatus.queued, createdAt: older),
      ].groupedAt(now);

      expect(ids(g.queued), ['old1', 'old2', 'old3', 'new1', 'new2']);
    });

    test('keeps a 500-task batch in its order', () {
      final g = [
        for (var i = 0; i < 500; i++)
          downloadTask(id: 'q$i', status: TaskStatus.queued, createdAt: now),
      ].groupedAt(now);

      expect(ids(g.queued), [for (var i = 0; i < 500; i++) 'q$i']);
    });

    test('falls back to createdAt when finishedAt is missing', () {
      final g = [
        downloadTask(
          id: 'today',
          status: TaskStatus.completed,
          createdAt: now.subtract(const Duration(hours: 1)),
        ),
        downloadTask(
          id: 'yesterday',
          status: TaskStatus.completed,
          createdAt: now.subtract(const Duration(days: 1)),
        ),
      ].groupedAt(now);

      expect(ids(g.doneToday), ['today']);
    });

    test('today ends at local midnight', () {
      final g = [
        downloadTask(
          id: 'late',
          status: TaskStatus.completed,
          finishedAt: DateTime(2026, 10, 15, 23, 59, 59),
        ),
        downloadTask(
          id: 'before',
          status: TaskStatus.completed,
          finishedAt: DateTime(2026, 10, 14, 23, 59, 59),
        ),
        downloadTask(
          id: 'after',
          status: TaskStatus.completed,
          finishedAt: DateTime(2026, 10, 16),
        ),
      ].groupedAt(now);

      expect(ids(g.doneToday), ['late']);
    });

    test('is empty with only old completed tasks', () {
      final g = [
        downloadTask(
          id: 'old',
          status: TaskStatus.completed,
          finishedAt: now.subtract(const Duration(days: 3)),
        ),
      ].groupedAt(now);

      expect(g.isEmpty, isTrue);
    });

    test('is empty with no tasks', () {
      expect(const <DownloadTask>[].groupedAt(now).isEmpty, isTrue);
    });

    test('equal groups are equal', () {
      final tasks = [downloadTask(id: 'r', status: TaskStatus.running)];

      expect(tasks.groupedAt(now), tasks.groupedAt(now));
    });
  });

  group('cardState', () {
    DownloadCardState of({
      TaskStatus status = TaskStatus.running,
      TaskStage stage = TaskStage.downloading,
    }) => downloadTask(status: status, stage: stage).cardState;

    test('a running task follows its stage', () {
      expect(of(stage: TaskStage.preparing), DownloadCardState.preparing);
      expect(of(stage: TaskStage.downloading), DownloadCardState.downloading);
      expect(of(stage: TaskStage.postProcessing), DownloadCardState.merging);
    });

    test('every other status has its own state', () {
      expect(of(status: TaskStatus.paused), DownloadCardState.paused);
      expect(of(status: TaskStatus.queued), DownloadCardState.queued);
      expect(of(status: TaskStatus.canceled), DownloadCardState.cancelled);
      expect(of(status: TaskStatus.failed), DownloadCardState.failed);
      expect(of(status: TaskStatus.completed), DownloadCardState.done);
    });

    test('a paused task ignores its stage', () {
      expect(
        of(status: TaskStatus.paused, stage: TaskStage.postProcessing),
        DownloadCardState.paused,
      );
    });
  });
}
