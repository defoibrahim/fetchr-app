import '../../../../core/utils/dates.dart';
import '../entities/download_groups.dart';
import '../entities/download_task.dart';
import '../entities/playlist_download.dart';

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
    final playlists = playlistDownloads;
    final folded = {for (final playlist in playlists) playlist.title};
    for (final task in this) {
      if (folded.contains(task.request.playlistTitle)) continue;
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
      playlists: playlists,
      active: active,
      queued: _oldestFirst(queued),
      attention: attention,
      doneToday: doneToday,
    );
  }

  /// The playlists that still have a video queued, running, paused or
  /// failed, in list order, each with all its videos in start order. A
  /// playlist whose videos all finished or were skipped is not one any more:
  /// its tasks go back to being plain ones.
  List<PlaylistDownload> get playlistDownloads {
    final byTitle = <String, List<DownloadTask>>{};
    for (final task in this) {
      final title = task.request.playlistTitle;
      if (title != null) byTitle.putIfAbsent(title, () => []).add(task);
    }
    return [
      for (final MapEntry(key: title, value: tasks) in byTitle.entries)
        if (tasks.any(_keepsPlaylistOpen))
          PlaylistDownload(
            title: title,
            items: [for (final task in tasks) PlaylistItem(task)],
          ),
    ];
  }

  /// The queued tasks of [ids] swap the places they hold so they come in the
  /// order of [ids]; everything else stays where it is. The same rule as
  /// native's `DownloadRepository.reorder`, applied ahead of its snapshot.
  List<DownloadTask> reorderedQueue(List<String> ids) {
    final rank = {for (final (index, id) in ids.indexed) id: index};
    final slots = [
      for (final (index, task) in indexed)
        if (task.status == TaskStatus.queued && rank.containsKey(task.id))
          index,
    ];
    final moved = [for (final slot in slots) this[slot]]
      ..sort((a, b) => rank[a.id]!.compareTo(rank[b.id]!));
    final result = [...this];
    for (final (index, slot) in slots.indexed) {
      result[slot] = moved[index];
    }
    return result;
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

bool _keepsPlaylistOpen(DownloadTask task) =>
    task.isActive || task.isPaused || task.status == TaskStatus.failed;

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
