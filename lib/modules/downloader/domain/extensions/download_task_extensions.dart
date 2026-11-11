import '../../../../core/utils/dates.dart';
import '../entities/download_groups.dart';
import '../entities/download_task.dart';

extension DownloadTaskList on List<DownloadTask> {
  /// Splits the tasks for the Downloads screen. Native lists tasks newest
  /// first, so every group but the queue keeps the snapshot order.
  DownloadGroups groupedAt(DateTime now) {
    // Two instant compares per task, not a time zone conversion on every
    // tick. The upper bound keeps out a task stamped after a clock change.
    final today = localDay(now);
    final tomorrow = DateTime(today.year, today.month, today.day + 1);
    final active = <DownloadTask>[];
    final queued = <DownloadTask>[];
    final attention = <DownloadTask>[];
    final doneToday = <DownloadTask>[];
    for (final task in this) {
      switch (task.status) {
        case TaskStatus.running || TaskStatus.paused || TaskStatus.canceled:
          active.add(task);
        case TaskStatus.queued:
          queued.add(task);
        case TaskStatus.failed:
          attention.add(task);
        case TaskStatus.completed:
          final at = task.finishedOrCreatedAt;
          if (!at.isBefore(today) && at.isBefore(tomorrow)) doneToday.add(task);
      }
    }
    return DownloadGroups(
      active: active,
      queued: _oldestFirst(queued),
      attention: attention,
      doneToday: doneToday,
    );
  }

  /// The [count] newest finished downloads that left a file behind.
  List<DownloadTask> recentlySaved(int count) {
    final saved = [
      for (final task in this)
        if (task.fileUri != null) task,
    ]..sort((a, b) => b.finishedOrCreatedAt.compareTo(a.finishedOrCreatedAt));
    return saved.take(count).toList();
  }
}

// Stable on purpose: one enqueue call gives all its tasks the same createdAt,
// and a playlist must keep running in the order it was added.
List<DownloadTask> _oldestFirst(List<DownloadTask> tasks) {
  final indexed = tasks.indexed.toList()
    ..sort((a, b) {
      final byAge = a.$2.createdAt.compareTo(b.$2.createdAt);
      return byAge != 0 ? byAge : a.$1.compareTo(b.$1);
    });
  return [for (final (_, task) in indexed) task];
}
