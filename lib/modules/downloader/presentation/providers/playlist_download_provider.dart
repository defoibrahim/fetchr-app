import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/download_task.dart';
import '../../domain/entities/playlist_download.dart';
import '../../domain/extensions/download_task_extensions.dart';
import 'downloads_notifier.dart';

/// The playlist download with this id: null while the list loads, and once
/// the playlist has nothing left to finish. It is a view onto the task
/// stream, which native already holds to four snapshots a second.
final playlistDownloadProvider = Provider.autoDispose
    .family<PlaylistDownload?, String>((ref, id) {
      final tasks =
          ref.watch(downloadsNotifierProvider).value ?? const <DownloadTask>[];
      return tasks.playlistDownloads.where((p) => p.id == id).firstOrNull;
    });
