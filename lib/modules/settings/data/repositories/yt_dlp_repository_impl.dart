import '../../../../app/shared/domain/entities/yt_dlp_status.dart';
import '../../../../core/errors/error_messages.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/errors/guard.dart';
import '../../../../core/errors/result.dart';
import '../../../../core/networking/network_info.dart';
import '../../../../core/platform/fetchr_api.g.dart' as api;
import '../../../../core/utils/dates.dart';
import '../../domain/repositories/i_yt_dlp_repository.dart';

class YtDlpRepositoryImpl implements IYtDlpRepository {
  const YtDlpRepositoryImpl(this._api, this._network);

  final api.FetchrHostApi _api;
  final INetworkInfo _network;

  static const _offline = NetworkFailure(ErrorMessages.ytDlpUpdateOffline);

  // Only the update downloads anything; reading the status is local.
  @override
  Future<Result<YtDlpStatus>> status() =>
      guard(() async => _toStatus(await _api.ytDlpStatus()));

  @override
  Future<Result<YtDlpStatus>> update() async {
    if (!await _network.isConnected) return const Err(_offline);
    final result = await guard(() async => _toStatus(await _api.updateYtDlp()));
    return result.failureOrNull is NetworkFailure
        ? const Err(_offline)
        : result;
  }

  @override
  Future<Result<void>> setAutoUpdate(bool enabled) =>
      guard(() => _api.setYtDlpAutoUpdate(enabled));
}

YtDlpStatus _toStatus(api.YtDlpStatus status) => YtDlpStatus(
  version: status.version,
  checkedAt: dateFromMs(status.checkedAtMs),
  autoUpdate: status.autoUpdate,
);
