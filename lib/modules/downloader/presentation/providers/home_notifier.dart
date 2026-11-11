import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/shared/domain/entities/quality.dart';
import '../../../../app/shared/download_prefs_provider.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/usecase/base_use_case.dart';
import '../../di/downloader_providers.dart';
import '../../domain/entities/download_request.dart';
import '../../domain/entities/media_info.dart';

class HomeNotifier extends AsyncNotifier<MediaInfo?> {
  // Bumped by every fetch and clear; a fetch that finds it moved on is stale
  // and writes nothing.
  int _generation = 0;

  @override
  FutureOr<MediaInfo?> build() => null;

  Future<void> fetch(String url) async {
    final generation = ++_generation;
    state = const AsyncLoading();
    final result = await ref.read(fetchMediaInfoUseCaseProvider)(url);
    if (!ref.mounted || generation != _generation) return;
    state = switch (result) {
      Ok(:final value) => AsyncData(value),
      Err(:final failure) => AsyncError(failure, StackTrace.current),
    };
  }

  /// One video; a playlist goes through [downloadPlaylist].
  Future<Result<void>> download(MediaInfo info, Quality quality) {
    return ref.read(enqueueDownloadsUseCaseProvider)([
      _request(
        quality,
        url: info.url,
        title: info.title,
        thumbnail: info.thumbnail,
        uploader: info.uploader,
        durationSec: info.durationSec,
      ),
    ]);
  }

  /// Ok(false) when the user closed the picker without a video.
  Future<Result<bool>> convertVideo() => ref.read(convertVideoUseCaseProvider)(
    ref.read(downloadPrefsProvider).folder,
  );

  /// The sizes to show when the [quality] pick would not fit on the volume
  /// downloads are saved to; null when it fits, when its size is unknown, or
  /// when free space could not be read: a failed probe never blocks a download.
  Future<({int needed, int free})?> storageShortfall(
    MediaInfo info,
    Quality quality,
  ) async {
    final needed = info.optionFor(quality)?.sizeBytes;
    if (needed == null) return null;
    final free = (await ref.read(getFreeSpaceUseCaseProvider)(
      const NoParams(),
    )).valueOrNull;
    return free != null && needed > free ? (needed: needed, free: free) : null;
  }

  /// [picked] are 0-based indexes into `info.entries`. Returns how many were
  /// enqueued.
  Future<Result<int>> downloadPlaylist(
    MediaInfo info,
    Quality quality,
    List<int> picked,
  ) async {
    // Nothing selected is nothing to start; native would still spin up the
    // foreground service for an empty batch.
    if (picked.isEmpty) return const Ok(0);
    final requests = [
      for (final i in picked)
        _request(
          quality,
          url: info.entries[i].url,
          title: info.entries[i].title,
          thumbnail: info.entries[i].thumbnail,
          uploader: info.uploader,
          durationSec: info.entries[i].durationSec,
          playlistTitle: info.title,
          playlistIndex: i + 1,
          playlistCount: info.entries.length,
        ),
    ];
    final result = await ref.read(enqueueDownloadsUseCaseProvider)(requests);
    return result.map((_) => requests.length);
  }

  DownloadRequest _request(
    Quality quality, {
    required String url,
    required String title,
    String? thumbnail,
    String? uploader,
    int? durationSec,
    String? playlistTitle,
    int? playlistIndex,
    int? playlistCount,
  }) {
    final prefs = ref.read(downloadPrefsProvider);
    return DownloadRequest(
      url: url,
      title: title,
      thumbnail: thumbnail,
      quality: quality,
      folder: prefs.folder,
      useAria2c: prefs.useAria2c,
      uploader: uploader,
      durationSec: durationSec,
      playlistTitle: playlistTitle,
      playlistIndex: playlistIndex,
      playlistCount: playlistCount,
    );
  }

  /// Drops the result, an error and any fetch still in flight.
  void clear() {
    _generation++;
    state = const AsyncData(null);
  }
}

// Failures are retried by hand, see AGENTS.md "Pitfalls".
final homeNotifierProvider =
    AsyncNotifierProvider.autoDispose<HomeNotifier, MediaInfo?>(
      HomeNotifier.new,
      retry: (_, _) => null,
    );
