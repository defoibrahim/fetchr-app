import 'dart:ui';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:grabby/app/shared/download_prefs_provider.dart';
import 'package:grabby/app/theme/accent_provider.dart';
import 'package:grabby/core/networking/network_info.dart';
import 'package:grabby/core/platform/fetchr_api.g.dart' as api;
import 'package:grabby/core/services/permissions/notification_permission.dart';
import 'package:grabby/modules/downloader/domain/repositories/i_downloader_repository.dart';
import 'package:grabby/modules/downloader/domain/usecases/cancel_download_usecase.dart';
import 'package:grabby/modules/downloader/domain/usecases/enqueue_downloads_usecase.dart';
import 'package:grabby/modules/downloader/domain/usecases/fetch_media_info_usecase.dart';
import 'package:grabby/modules/downloader/domain/usecases/get_free_space_usecase.dart';
import 'package:grabby/modules/downloader/domain/usecases/open_download_folder_usecase.dart';
import 'package:grabby/modules/downloader/domain/usecases/pause_all_downloads_usecase.dart';
import 'package:grabby/modules/downloader/domain/usecases/pause_download_usecase.dart';
import 'package:grabby/modules/downloader/domain/usecases/remove_download_usecase.dart';
import 'package:grabby/modules/downloader/domain/usecases/resume_all_downloads_usecase.dart';
import 'package:grabby/modules/downloader/domain/usecases/resume_download_usecase.dart';
import 'package:grabby/modules/downloader/domain/usecases/retry_download_usecase.dart';
import 'package:grabby/modules/downloader/domain/usecases/watch_downloads_usecase.dart';
import 'package:grabby/modules/library/domain/repositories/i_library_repository.dart';
import 'package:grabby/modules/library/domain/usecases/delete_library_items_usecase.dart';
import 'package:grabby/modules/library/domain/usecases/get_library_thumbnail_usecase.dart';
import 'package:grabby/modules/library/domain/usecases/get_library_usecase.dart';
import 'package:grabby/modules/library/domain/usecases/open_library_folder_usecase.dart';
import 'package:grabby/modules/library/domain/usecases/share_library_item_usecase.dart';
import 'package:grabby/modules/settings/domain/repositories/i_yt_dlp_repository.dart';
import 'package:grabby/modules/settings/domain/usecases/get_yt_dlp_status_usecase.dart';
import 'package:grabby/modules/settings/domain/usecases/set_yt_dlp_auto_update_usecase.dart';
import 'package:grabby/modules/settings/domain/usecases/update_yt_dlp_usecase.dart';
import 'package:mocktail/mocktail.dart';

class MockDownloaderRepository extends Mock implements IDownloaderRepository {}

class MockLibraryRepository extends Mock implements ILibraryRepository {}

class MockYtDlpRepository extends Mock implements IYtDlpRepository {}

class MockFetchMediaInfoUseCase extends Mock implements FetchMediaInfoUseCase {}

class MockEnqueueDownloadsUseCase extends Mock
    implements EnqueueDownloadsUseCase {}

class MockCancelDownloadUseCase extends Mock implements CancelDownloadUseCase {}

class MockRetryDownloadUseCase extends Mock implements RetryDownloadUseCase {}

class MockRemoveDownloadUseCase extends Mock implements RemoveDownloadUseCase {}

class MockOpenDownloadFolderUseCase extends Mock
    implements OpenDownloadFolderUseCase {}

class MockWatchDownloadsUseCase extends Mock implements WatchDownloadsUseCase {}

class MockPauseDownloadUseCase extends Mock implements PauseDownloadUseCase {}

class MockResumeDownloadUseCase extends Mock implements ResumeDownloadUseCase {}

class MockPauseAllDownloadsUseCase extends Mock
    implements PauseAllDownloadsUseCase {}

class MockResumeAllDownloadsUseCase extends Mock
    implements ResumeAllDownloadsUseCase {}

class MockGetFreeSpaceUseCase extends Mock implements GetFreeSpaceUseCase {}

class MockGetLibraryUseCase extends Mock implements GetLibraryUseCase {}

class MockGetLibraryThumbnailUseCase extends Mock
    implements GetLibraryThumbnailUseCase {}

class MockDeleteLibraryItemsUseCase extends Mock
    implements DeleteLibraryItemsUseCase {}

class MockShareLibraryItemUseCase extends Mock
    implements ShareLibraryItemUseCase {}

class MockOpenLibraryFolderUseCase extends Mock
    implements OpenLibraryFolderUseCase {}

class MockGetYtDlpStatusUseCase extends Mock implements GetYtDlpStatusUseCase {}

class MockUpdateYtDlpUseCase extends Mock implements UpdateYtDlpUseCase {}

class MockSetYtDlpAutoUpdateUseCase extends Mock
    implements SetYtDlpAutoUpdateUseCase {}

class MockNotificationPermission extends Mock
    implements NotificationPermission {}

class MockFetchrHostApi extends Mock implements api.FetchrHostApi {}

class MockNetworkInfo extends Mock implements INetworkInfo {}

class MockSecureStorage extends Mock implements FlutterSecureStorage {}

/// Pins the download preferences, so a test needs no storage.
class FixedPrefs extends DownloadPrefsNotifier {
  FixedPrefs(this._prefs);

  final DownloadPrefs _prefs;

  @override
  DownloadPrefs build() => _prefs;
}

/// Pins the accent, so a test needs no storage.
class FixedAccent extends AccentNotifier {
  FixedAccent(this._accent);

  final Color _accent;

  @override
  Color build() => _accent;
}
