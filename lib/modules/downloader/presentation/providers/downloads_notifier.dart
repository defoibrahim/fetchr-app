import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/result.dart';
import '../../di/downloader_providers.dart';
import '../../domain/entities/download_task.dart';

class DownloadsNotifier extends StreamNotifier<List<DownloadTask>> {
  /// Tasks the user deleted and may still undo. They stay out of the state
  /// until native stops reporting them or [unhide] brings them back.
  Set<String> _hidden = const {};
  List<DownloadTask>? _snapshot;

  @override
  Stream<List<DownloadTask>> build() {
    _snapshot = null;
    return ref.watch(watchDownloadsUseCaseProvider)().map((tasks) {
      _snapshot = tasks;
      if (_hidden.isNotEmpty) {
        _hidden = _hidden.intersection({for (final task in tasks) task.id});
      }
      return _visible(tasks);
    });
  }

  void hide(String id) {
    _hidden = {..._hidden, id};
    _publish();
  }

  void unhide(String id) {
    _hidden = _hidden.difference({id});
    _publish();
  }

  Future<Result<void>> cancel(String id) =>
      ref.read(cancelDownloadUseCaseProvider)(id);

  Future<Result<void>> retry(String id) =>
      ref.read(retryDownloadUseCaseProvider)(id);

  Future<Result<void>> pause(String id) =>
      ref.read(pauseDownloadUseCaseProvider)(id);

  Future<Result<void>> resume(String id) =>
      ref.read(resumeDownloadUseCaseProvider)(id);

  // The undo flow commits five seconds after the tap; a disposed notifier
  // deletes nothing, like an app killed during the window.
  Future<Result<bool>> remove(String id) async {
    if (!ref.mounted) return const Ok(false);
    return ref.read(removeDownloadUseCaseProvider)(id);
  }

  Future<Result<void>> openFolder(String uri) =>
      ref.read(openDownloadFolderUseCaseProvider)(uri);

  List<DownloadTask> _visible(List<DownloadTask> tasks) => _hidden.isEmpty
      ? tasks
      : [
          for (final task in tasks)
            if (!_hidden.contains(task.id)) task,
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
