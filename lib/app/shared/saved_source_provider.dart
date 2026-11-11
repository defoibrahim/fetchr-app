import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../modules/downloader/domain/entities/download_task.dart';
import '../../modules/downloader/presentation/providers/downloads_notifier.dart';

/// "{site} · {uploader}" of the completed download that saved the file at this
/// uri, or null when no task did (a file from an earlier install). The Player
/// reads it: the library has the file but not where it came from.
final savedSourceProvider = Provider.autoDispose.family<String?, String>(
  (ref, uri) => ref.watch(
    downloadsNotifierProvider.select((tasks) {
      for (final task in tasks.value ?? const <DownloadTask>[]) {
        if (task.fileUri == uri) {
          return sourceLine(task.request.url, task.request.uploader);
        }
      }
      return null;
    }),
  ),
);
