import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/core_providers.dart';
import '../data/repositories/yt_dlp_repository_impl.dart';
import '../domain/repositories/i_yt_dlp_repository.dart';
import '../domain/usecases/get_yt_dlp_status_usecase.dart';
import '../domain/usecases/set_yt_dlp_auto_update_usecase.dart';
import '../domain/usecases/update_yt_dlp_usecase.dart';

final ytDlpRepositoryProvider = Provider<IYtDlpRepository>(
  (ref) => YtDlpRepositoryImpl(
    ref.watch(fetchrHostApiProvider),
    ref.watch(networkInfoProvider),
  ),
);

final getYtDlpStatusUseCaseProvider = Provider<GetYtDlpStatusUseCase>(
  (ref) => GetYtDlpStatusUseCase(ref.watch(ytDlpRepositoryProvider)),
);

final updateYtDlpUseCaseProvider = Provider<UpdateYtDlpUseCase>(
  (ref) => UpdateYtDlpUseCase(ref.watch(ytDlpRepositoryProvider)),
);

final setYtDlpAutoUpdateUseCaseProvider = Provider<SetYtDlpAutoUpdateUseCase>(
  (ref) => SetYtDlpAutoUpdateUseCase(ref.watch(ytDlpRepositoryProvider)),
);
