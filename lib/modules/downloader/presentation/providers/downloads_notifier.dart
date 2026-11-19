import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';
import '../../di/downloader_providers.dart';
import '../../domain/entities/download_task.dart';
import '../../domain/extensions/download_task_extensions.dart';

/// What a stopped playlist had left, kept for its Undo.
typedef PlaylistStop = ({
  List<String> unfinished,
  List<String> paused,
  int kept,
});

/// A pause, resume or cancel the user asked for that native has not shown
/// yet: the status the task shows meanwhile, and whether native answered.
/// Compared by identity, so a later tap on the same task is never mistaken
/// for this one.
final class _Pending {
  const _Pending(this.shown, {this.answered = false});

  final TaskStatus shown;
  final bool answered;
}

class DownloadsNotifier extends StreamNotifier<List<DownloadTask>> {
  /// Tasks the user deleted and may still undo. They stay out of the state
  /// until native stops reporting them or [unhide] brings them back.
  Set<String> _hidden = const {};
  Map<String, _Pending> _pending = const {};
  List<DownloadTask>? _snapshot;

  @override
  Stream<List<DownloadTask>> build() {
    _snapshot = null;
    _pending = const {};
    return ref.watch(watchDownloadsUseCaseProvider)().map((tasks) {
      _snapshot = tasks;
      if (_hidden.isNotEmpty) {
        _hidden = _hidden.intersection({for (final task in tasks) task.id});
      }
      if (_pending.isNotEmpty) _pending = _reconciled(tasks);
      return _visible(tasks);
    });
  }

  /// True while a pause, resume or cancel of [id] shows ahead of native: its
  /// buttons wait for the snapshot that confirms it.
  bool isSettling(String id) => _pending.containsKey(id);

  void hide(String id) {
    _hidden = {..._hidden, id};
    _publish();
  }

  void unhide(String id) {
    _hidden = _hidden.difference({id});
    _publish();
  }

  Future<Result<void>> cancel(String id) => _ahead(
    id,
    TaskStatus.canceled,
    ref.read(cancelDownloadUseCaseProvider).call,
  );

  Future<Result<void>> retry(String id) =>
      ref.read(retryDownloadUseCaseProvider)(id);

  Future<Result<void>> pause(String id) => _ahead(
    id,
    TaskStatus.paused,
    ref.read(pauseDownloadUseCaseProvider).call,
  );

  Future<Result<void>> resume(String id) => _ahead(
    id,
    TaskStatus.running,
    ref.read(resumeDownloadUseCaseProvider).call,
  );

  /// Shows the task as [shown] at once, then asks native. An [Err] puts the
  /// task back as native has it; otherwise the next snapshot, which comes
  /// after native has applied it, replaces the guess.
  Future<Result<void>> _ahead(
    String id,
    TaskStatus shown,
    Future<Result<void>> Function(String id) action,
  ) async {
    final pending = _Pending(shown);
    _pending = {..._pending, id: pending};
    _publish();
    final result = await action(id);
    // A newer tap on the same task owns the entry now.
    if (!ref.mounted || !identical(_pending[id], pending)) return result;
    final task = _snapshot?.where((t) => t.id == id).firstOrNull;
    _pending = {..._pending}..remove(id);
    if (result is Ok && task != null && !_reached(task.status, shown)) {
      _pending[id] = _Pending(shown, answered: true);
    }
    _publish();
    return result;
  }

  Map<String, _Pending> _reconciled(List<DownloadTask> tasks) {
    final byId = {for (final task in tasks) task.id: task};
    return {
      for (final MapEntry(key: id, value: pending) in _pending.entries)
        if (byId[id] case final task?
            when !pending.answered && !_reached(task.status, pending.shown))
          id: pending,
    };
  }

  /// Whether native shows the task past what the user asked for: any status
  /// the request could have led to, not only the one it aims at.
  static bool _reached(TaskStatus actual, TaskStatus shown) => switch (shown) {
    TaskStatus.paused => !_isLive(actual),
    TaskStatus.running => actual != TaskStatus.paused,
    _ => !_isLive(actual) && actual != TaskStatus.paused,
  };

  static bool _isLive(TaskStatus status) =>
      status == TaskStatus.queued || status == TaskStatus.running;

  // The undo flow commits five seconds after the tap; a disposed notifier
  // deletes nothing, like an app killed during the window.
  Future<Result<bool>> remove(String id) async {
    if (!ref.mounted) return const Ok(false);
    return ref.read(removeDownloadUseCaseProvider)(id);
  }

  /// Holds every video of the playlist that is running or waiting.
  Future<Result<void>> pausePlaylist(String id) =>
      _each(_live(_items(id)), ref.read(pauseDownloadUseCaseProvider).call);

  Future<Result<void>> resumePlaylist(String id) => _each(
    _items(id).where((t) => t.isPaused),
    ref.read(resumeDownloadUseCaseProvider).call,
  );

  /// The video will not download; [unskip] brings it back.
  Future<Result<void>> skip(String id) => cancel(id);

  /// Queues a skipped video again. With [order], the up-next ids from before
  /// the skip, it goes back to its place instead of the end of the queue.
  Future<Result<void>> unskip(String id, {List<String>? order}) async {
    final reorder = ref.read(reorderQueueUseCaseProvider);
    final result = await retry(id);
    if (order == null || result is Err) return result;
    return reorder(order);
  }

  /// Starts the waiting videos of [order] in that order. The list shows it at
  /// once; native's next snapshot confirms it, or puts back the old one.
  Future<Result<void>> reorderQueue(List<String> order) {
    final snapshot = _snapshot;
    if (snapshot != null) {
      _snapshot = snapshot.reorderedQueue(order);
      _publish();
    }
    return ref.read(reorderQueueUseCaseProvider)(order);
  }

  /// Stops the playlist at once and hides what it had left; the finished
  /// videos stay. [undoStop] goes back, [commitStop] drops the rest for good.
  Future<Result<PlaylistStop>> stopPlaylist(String id) async {
    final items = _items(id).toList();
    final paused = [for (final task in _live(items)) task.id];
    final result = await pausePlaylist(id);
    if (result case Err(:final failure)) return Err(failure);
    final unfinished = [
      for (final task in items)
        if (task.status != TaskStatus.completed) task.id,
    ];
    final stop = (
      unfinished: unfinished,
      paused: paused,
      kept: items.length - unfinished.length,
    );
    _hidden = {..._hidden, ...stop.unfinished};
    _publish();
    return Ok(stop);
  }

  // Also the restore of a failed [commitStop], which may land on a disposed
  // notifier.
  Future<Result<void>> undoStop(PlaylistStop stop) async {
    if (!ref.mounted) return const Ok(null);
    final resume = ref.read(resumeDownloadUseCaseProvider);
    _hidden = _hidden.difference(stop.unfinished.toSet());
    _publish();
    final paused = stop.paused.toSet();
    return _each([
      for (final task in _snapshot ?? const <DownloadTask>[])
        if (paused.contains(task.id)) task,
    ], resume.call);
  }

  // Five seconds after the tap, like [remove]: a disposed notifier drops
  // nothing, and the paused videos wait for the user.
  Future<Result<bool>> commitStop(PlaylistStop stop) async {
    if (!ref.mounted) return const Ok(false);
    final unfinished = stop.unfinished.toSet();
    final result = await _each([
      for (final task in _snapshot ?? const <DownloadTask>[])
        if (unfinished.contains(task.id)) task,
    ], ref.read(removeDownloadUseCaseProvider).call);
    return result.fold(Err.new, (_) => const Ok(true));
  }

  Iterable<DownloadTask> _items(String playlist) => [
    for (final task in _snapshot ?? const <DownloadTask>[])
      if (task.request.playlistTitle == playlist) task,
  ];

  // Waiting ones first: pausing a running one would start the next in line.
  static List<DownloadTask> _live(Iterable<DownloadTask> tasks) => [
    ...tasks.where((t) => t.status == TaskStatus.queued),
    ...tasks.where((t) => t.status == TaskStatus.running),
  ];

  // The use case is read by the caller, before the first await: the provider
  // may be gone by the second task.
  Future<Result<void>> _each(
    Iterable<DownloadTask> tasks,
    Future<Result<Object?>> Function(String id) action,
  ) async {
    for (final task in tasks.toList()) {
      final result = await action(task.id);
      if (result case Err(:final failure)) return Err(failure);
    }
    return const Ok(null);
  }

  Future<Result<void>> openFolder(String uri) =>
      ref.read(openDownloadFolderUseCaseProvider)(uri);

  List<DownloadTask> _visible(List<DownloadTask> tasks) =>
      _hidden.isEmpty && _pending.isEmpty
      ? tasks
      : [
          for (final task in tasks)
            if (!_hidden.contains(task.id))
              switch (_pending[task.id]) {
                final pending? => task.withStatus(pending.shown),
                null => task,
              },
        ];

  // Called after awaits by the undo flow, when the provider may be gone.
  void _publish() {
    final snapshot = _snapshot;
    if (snapshot == null || !ref.mounted || state.hasError) return;
    state = AsyncData(_visible(snapshot));
  }
}

final downloadsNotifierProvider =
    StreamNotifierProvider.autoDispose<DownloadsNotifier, List<DownloadTask>>(
      DownloadsNotifier.new,
      retry: (_, _) => null,
    );
