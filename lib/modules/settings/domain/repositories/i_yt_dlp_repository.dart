import '../../../../app/shared/domain/entities/yt_dlp_status.dart';
import '../../../../core/errors/result.dart';

abstract interface class IYtDlpRepository {
  /// Waits for native init, and for a startup update that is still running.
  Future<Result<YtDlpStatus>> status();

  /// A `NetworkFailure` here carries `ErrorMessages.ytDlpUpdateOffline`, for
  /// the offline probe and for a native network error alike.
  Future<Result<YtDlpStatus>> update();

  Future<Result<void>> setAutoUpdate(bool enabled);
}
