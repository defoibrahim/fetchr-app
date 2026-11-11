import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/shared/domain/entities/yt_dlp_status.dart';
import '../../../../../app/shared/formatters/yt_dlp_formatter.dart';
import '../../../../../app/shared/yt_dlp_provider.dart';
import '../../../../../core/gen/assets.gen.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/theme_extensions.dart';
import '../../../../../core/utils/scale.dart';
import '../../../../../core/widgets/app_button.dart';
import '../../../../../core/widgets/app_icon.dart';
import '../../../../../core/widgets/app_snackbar.dart';
import 'settings_section.dart';

const _versionSize = 14.0;
const _textGap = 3.0;
const _badgeGap = 6.0;
const _badgeIcon = 16.0;
const _groupGap = 14.0;

/// The Download engine section. The version and the update phase come from
/// [ytDlpProvider], so an update started on Home shows busy here too.
class YtDlpCard extends ConsumerWidget {
  const YtDlpCard({super.key});

  Future<void> _update(BuildContext context, WidgetRef ref) async {
    final result = await ref.read(ytDlpProvider.notifier).updateYtDlp();
    if (!context.mounted) return;
    await AppSnackbar.showFailure(context, result);
  }

  Future<void> _setAutoUpdate(
    BuildContext context,
    WidgetRef ref,
    bool enabled,
  ) async {
    final result = await ref
        .read(ytDlpProvider.notifier)
        .setAutoUpdate(enabled);
    if (!context.mounted) return;
    await AppSnackbar.showFailure(context, result);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final yt = ref.watch(ytDlpProvider);
    final state = yt.value;
    final status = state?.status;
    final phase = state?.phase ?? YtDlpUpdatePhase.idle;
    final busy = phase == YtDlpUpdatePhase.busy;
    final done = phase == YtDlpUpdatePhase.done;

    return SettingsSection(
      title: 'Download engine',
      rows: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: _groupGap.h,
          children: [
            _StatusRow(
              version: _versionText(yt),
              caption: ytDlpCaption(status, phase, DateTime.now()),
              upToDate: done,
            ),
            AppButton(
              label: phase.actionLabel,
              loadingLabel: ytDlpUpdatingLabel,
              isLoading: busy,
              size: AppButtonSize.medium,
              icon: Assets.icons.refresh,
              onPressed: () => unawaited(_update(context, ref)),
            ),
          ],
        ),
        SettingsSwitchRow(
          title: 'Check for updates daily',
          subtitle: 'On app start, at most once a day',
          value: status?.autoUpdate ?? false,
          // Without a status the switch has nothing true to show.
          onChanged: status == null
              ? null
              : (enabled) => unawaited(_setAutoUpdate(context, ref, enabled)),
        ),
      ],
    );
  }

  static String _versionText(AsyncValue<YtDlpState> yt) => switch (yt) {
    AsyncData(:final value) => switch (value.status) {
      null => 'Version unavailable',
      final YtDlpStatus status => status.versionLabel,
    },
    // A retry reloads from the error state: not unavailable yet.
    AsyncError() when !yt.isLoading => 'Version unavailable',
    _ => 'Checking…',
  };
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.version,
    required this.caption,
    required this.upToDate,
  });

  final String version;
  final String? caption;
  final bool upToDate;

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    final muted = context.tokens.textMuted;
    final accent = context.colors.primary;
    final line = caption;
    return Row(
      spacing: Gap.md.w,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: _textGap.h,
            children: [
              Text(
                version,
                style: type.mono.copyWith(
                  fontSize: _versionSize,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (line != null)
                Semantics(
                  liveRegion: true,
                  child: Text(line, style: type.caption.copyWith(color: muted)),
                ),
            ],
          ),
        ),
        if (upToDate)
          Row(
            spacing: _badgeGap.w,
            children: [
              AppIcon(Assets.icons.check, size: _badgeIcon.r, color: accent),
              Text('Up to date', style: type.caption.copyWith(color: accent)),
            ],
          ),
      ],
    );
  }
}
