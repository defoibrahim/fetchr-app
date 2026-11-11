import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/core_providers.dart';
import '../../../core/platform/fetchr_api.g.dart' as api;
import '../data/repositories/downloader_repository_impl.dart';
import '../domain/repositories/i_downloader_repository.dart';
import '../domain/usecases/cancel_download_usecase.dart';
import '../domain/usecases/convert_video_usecase.dart';
import '../domain/usecases/enqueue_downloads_usecase.dart';
import '../domain/usecases/fetch_media_info_usecase.dart';
import '../domain/usecases/get_free_space_usecase.dart';
import '../domain/usecases/open_download_folder_usecase.dart';
import '../domain/usecases/pause_all_downloads_usecase.dart';
import '../domain/usecases/pause_download_usecase.dart';
import '../domain/usecases/remove_download_usecase.dart';
import '../domain/usecases/resume_all_downloads_usecase.dart';
import '../domain/usecases/resume_download_usecase.dart';
import '../domain/usecases/retry_download_usecase.dart';
import '../domain/usecases/watch_downloads_usecase.dart';

final downloaderRepositoryProvider = Provider<IDownloaderRepository>(
  (ref) => DownloaderRepositoryImpl(
    ref.watch(fetchrHostApiProvider),
    ref.watch(networkInfoProvider),
    api.downloads,
  ),
);

final fetchMediaInfoUseCaseProvider = Provider<FetchMediaInfoUseCase>(
  (ref) => FetchMediaInfoUseCase(ref.watch(downloaderRepositoryProvider)),
);

final enqueueDownloadsUseCaseProvider = Provider<EnqueueDownloadsUseCase>(
  (ref) => EnqueueDownloadsUseCase(ref.watch(downloaderRepositoryProvider)),
);

final cancelDownloadUseCaseProvider = Provider<CancelDownloadUseCase>(
  (ref) => CancelDownloadUseCase(ref.watch(downloaderRepositoryProvider)),
);

final retryDownloadUseCaseProvider = Provider<RetryDownloadUseCase>(
  (ref) => RetryDownloadUseCase(ref.watch(downloaderRepositoryProvider)),
);

final pauseDownloadUseCaseProvider = Provider<PauseDownloadUseCase>(
  (ref) => PauseDownloadUseCase(ref.watch(downloaderRepositoryProvider)),
);

final resumeDownloadUseCaseProvider = Provider<ResumeDownloadUseCase>(
  (ref) => ResumeDownloadUseCase(ref.watch(downloaderRepositoryProvider)),
);

final pauseAllDownloadsUseCaseProvider = Provider<PauseAllDownloadsUseCase>(
  (ref) => PauseAllDownloadsUseCase(ref.watch(downloaderRepositoryProvider)),
);

final resumeAllDownloadsUseCaseProvider = Provider<ResumeAllDownloadsUseCase>(
  (ref) => ResumeAllDownloadsUseCase(ref.watch(downloaderRepositoryProvider)),
);

final getFreeSpaceUseCaseProvider = Provider<GetFreeSpaceUseCase>(
  (ref) => GetFreeSpaceUseCase(ref.watch(downloaderRepositoryProvider)),
);

final removeDownloadUseCaseProvider = Provider<RemoveDownloadUseCase>(
  (ref) => RemoveDownloadUseCase(ref.watch(downloaderRepositoryProvider)),
);

final openDownloadFolderUseCaseProvider = Provider<OpenDownloadFolderUseCase>(
  (ref) => OpenDownloadFolderUseCase(ref.watch(downloaderRepositoryProvider)),
);

final convertVideoUseCaseProvider = Provider<ConvertVideoUseCase>(
  (ref) => ConvertVideoUseCase(ref.watch(downloaderRepositoryProvider)),
);

final watchDownloadsUseCaseProvider = Provider<WatchDownloadsUseCase>(
  (ref) => WatchDownloadsUseCase(ref.watch(downloaderRepositoryProvider)),
);
