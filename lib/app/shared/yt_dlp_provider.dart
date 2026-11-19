import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/result.dart';
import '../../core/usecase/base_use_case.dart';
import '../../modules/settings/di/settings_providers.dart';
import 'domain/entities/yt_dlp_status.dart';
import 'platform_traits_provider.dart';

enum YtDlpUpdatePhase { idle, busy, done }

class YtDlpState extends Equatable {
  const YtDlpState(
    this.status, {
    this.phase = YtDlpUpdatePhase.idle,
    this.pendingVersion,
  });

  /// Null while an update runs after a failed status read.
  final YtDlpStatus? status;
  final YtDlpUpdatePhase phase;

  /// The version an update just installed for the next launch, when it is not
  /// the one running. Only a platform whose update needs a restart sets it.
  final String? pendingVersion;

  YtDlpState copyWith({YtDlpStatus? status, YtDlpUpdatePhase? phase}) =>
      YtDlpState(
        status ?? this.status,
        phase: phase ?? this.phase,
        pendingVersion: pendingVersion,
      );

  @override
  List<Object?> get props => [status, phase, pendingVersion];
}

class YtDlpNotifier extends AsyncNotifier<YtDlpState> {
  Future<Result<YtDlpStatus>>? _running;

  @override
  Future<YtDlpState> build() async {
    final result = await ref.watch(getYtDlpStatusUseCaseProvider)(
      const NoParams(),
    );
    return YtDlpState(result.getOrThrow());
  }

  /// Busy, then done with the new status, or idle on `Err`. A call while busy
  /// returns the running future.
  Future<Result<YtDlpStatus>> updateYtDlp() =>
      _running ??= _update().whenComplete(() => _running = null);

  Future<Result<YtDlpStatus>> _update() async {
    final current = state.value;
    state = AsyncData(
      YtDlpState(current?.status, phase: YtDlpUpdatePhase.busy),
    );
    final result = await ref.read(updateYtDlpUseCaseProvider)(const NoParams());
    if (!ref.mounted) return result;
    switch (result) {
      case Ok(:final value):
        state = AsyncData(_updated(current?.status, value));
      case Err() when current == null:
        ref.invalidateSelf();
      case Err():
        state = AsyncData(current!.copyWith(phase: YtDlpUpdatePhase.idle));
    }
    return result;
  }

  // Where an update runs only from the next launch, the version in use stays
  // the running one and the new one waits.
  YtDlpState _updated(YtDlpStatus? running, YtDlpStatus installed) {
    final version = installed.version;
    if (!ref.read(platformTraitsProvider).updateNeedsRestart ||
        running == null ||
        version == null ||
        version == running.version) {
      return YtDlpState(installed, phase: YtDlpUpdatePhase.done);
    }
    return YtDlpState(
      YtDlpStatus(
        version: running.version,
        checkedAt: installed.checkedAt,
        autoUpdate: installed.autoUpdate,
      ),
      phase: YtDlpUpdatePhase.done,
      pendingVersion: version,
    );
  }

  /// Optimistic: the switch flips at once and flips back on `Err`.
  Future<Result<void>> setAutoUpdate(bool enabled) async {
    final before = state.value?.status?.autoUpdate;
    _setAutoUpdate(enabled);
    final result = await ref.read(setYtDlpAutoUpdateUseCaseProvider)(enabled);
    if (result is Err && before != null && ref.mounted) _setAutoUpdate(before);
    return result;
  }

  void _setAutoUpdate(bool enabled) {
    final current = state.value;
    final status = current?.status;
    if (current == null || status == null) return;
    state = AsyncData(current.copyWith(status: status.withAutoUpdate(enabled)));
  }
}

// Not autoDispose: Home is always mounted, and Settings must see the phase an
// update started on Home. No auto-retry: a Failure is retried by hand.
final ytDlpProvider = AsyncNotifierProvider<YtDlpNotifier, YtDlpState>(
  YtDlpNotifier.new,
  retry: (_, _) => null,
);
