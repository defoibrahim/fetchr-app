import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../core/gen/assets.gen.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/theme.dart';
import '../../../../../core/utils/scale.dart';
import '../../../../../core/widgets/app_button.dart';
import '../../../../../core/widgets/app_icon_button.dart';
import '../../../../../core/widgets/app_progress_bar.dart';
import '../../../../../core/widgets/dashed_border.dart';
import '../../../domain/entities/download_card_state.dart';
import '../../../domain/entities/download_task.dart';
import '../../formatters/download_task_formatter.dart';
import 'download_parts.dart';

const _padding = 14.0;
const _titleGap = 3.0;

/// A download in flight (preparing, downloading, merging or paused), or the
/// dashed card a cancelled one leaves behind. Queued, failed and finished
/// tasks have their own rows.
class DownloadCard extends StatelessWidget {
  DownloadCard({
    super.key,
    required this.task,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
    required this.onRestart,
    required this.onRemove,
  }) : assert(
         _isCardState(task.cardState),
         'DownloadCard shows live and cancelled tasks, not ${task.status}',
       );

  final DownloadTask task;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;
  final VoidCallback onRestart;
  final VoidCallback onRemove;

  static bool _isCardState(DownloadCardState state) => switch (state) {
    DownloadCardState.queued ||
    DownloadCardState.failed ||
    DownloadCardState.done => false,
    _ => true,
  };

  @override
  Widget build(BuildContext context) {
    final state = task.cardState;
    return state == DownloadCardState.cancelled
        ? _CancelledCard(task: task, onRestart: onRestart, onRemove: onRemove)
        : _LiveCard(
            task: task,
            state: state,
            onPause: onPause,
            onResume: onResume,
            onCancel: onCancel,
          );
  }
}

class _LiveCard extends StatelessWidget {
  const _LiveCard({
    required this.task,
    required this.state,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
  });

  final DownloadTask task;
  final DownloadCardState state;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;

  bool get _paused => state == DownloadCardState.paused;

  /// Null shows the sliding segment: nothing to measure while starting or
  /// merging, or when the size is unknown. An MP3 conversion is measured.
  double? get _value => switch (state) {
    DownloadCardState.downloading ||
    DownloadCardState.merging => task.progress >= 0 ? task.progress : null,
    DownloadCardState.paused => math.max(task.progress, 0),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final stage = task.stageText;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: EdgeInsets.all(_padding.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Gap.md.h,
          children: [
            Row(
              spacing: Gap.md.w,
              children: [
                DownloadThumb(task: task),
                Expanded(child: _Title(task: task)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: Gap.sm.w,
                  children: [
                    if (_paused)
                      AppIconButton(
                        icon: Assets.icons.play,
                        tooltip: 'Resume download',
                        onPressed: onResume,
                        bordered: true,
                      )
                    else
                      AppIconButton(
                        icon: Assets.icons.pause,
                        tooltip: 'Pause download',
                        onPressed: onPause,
                        bordered: true,
                      ),
                    AppIconButton(
                      icon: Assets.icons.close,
                      tooltip: 'Cancel download',
                      onPressed: onCancel,
                      bordered: true,
                    ),
                  ],
                ),
              ],
            ),
            AppProgressBar(
              value: _value,
              color: _paused ? tokens.textMuted : null,
              semanticsLabel: _paused
                  ? 'Download paused'
                  : stage ?? 'Download progress',
            ),
            if (_paused)
              _StatLine(text: task.pausedText)
            else if (stage != null)
              _StageLine(stage: stage, percent: task.stagePercent)
            else
              _Stats(task: task),
          ],
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: _titleGap.h,
      children: [
        Text(
          task.request.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: type.body.copyWith(fontWeight: FontWeight.w600),
        ),
        Text(
          task.metaText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          // Mono sizes and qualities read left to right in any locale.
          textDirection: TextDirection.ltr,
          style: type.monoSmall.copyWith(color: context.tokens.textMuted),
        ),
      ],
    );
  }
}

class _StatLine extends StatelessWidget {
  const _StatLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textDirection: TextDirection.ltr,
    style: context.type.monoSmall.copyWith(color: context.tokens.textMuted),
  );
}

/// What the task is doing, and how far an MP3 conversion has got.
class _StageLine extends StatelessWidget {
  const _StageLine({required this.stage, required this.percent});

  final String stage;
  final String? percent;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final type = context.type;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      spacing: Gap.md.w,
      children: [
        Flexible(
          child: Text(
            stage,
            style: type.caption.copyWith(color: tokens.textMuted),
          ),
        ),
        if (percent case final percent?)
          Text(
            percent,
            textDirection: TextDirection.ltr,
            style: type.monoSmall.copyWith(color: tokens.text),
          ),
      ],
    );
  }
}

/// Percent and bytes on the left, speed and time on the right. Each side may
/// wrap, so a large text size never overflows the card.
class _Stats extends StatelessWidget {
  const _Stats({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final style = context.type.monoSmall.copyWith(color: tokens.textMuted);
    final stats = task.stats;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Gap.md.w,
      children: [
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                if (stats.percent case final percent?)
                  TextSpan(
                    text: percent,
                    style: style.copyWith(color: tokens.text),
                  ),
                TextSpan(text: stats.rest),
              ],
            ),
            textDirection: TextDirection.ltr,
            style: style,
          ),
        ),
        Flexible(
          child: Text(
            stats.right,
            textAlign: TextAlign.end,
            textDirection: TextDirection.ltr,
            style: style,
          ),
        ),
      ],
    );
  }
}

class _CancelledCard extends StatelessWidget {
  const _CancelledCard({
    required this.task,
    required this.onRestart,
    required this.onRemove,
  });

  final DownloadTask task;
  final VoidCallback onRestart;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final radius = BorderRadius.circular(Radii.card.r);
    return DashedBorder(
      radius: Radii.card.r,
      child: DecoratedBox(
        decoration: BoxDecoration(color: tokens.surface, borderRadius: radius),
        child: Padding(
          padding: EdgeInsets.all(_padding.r),
          child: Row(
            spacing: Gap.md.w,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  spacing: _titleGap.h,
                  children: [
                    Text(
                      task.request.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.type.body.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Cancelled · partial file removed',
                      style: context.type.caption.copyWith(
                        color: tokens.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              AppButton(
                label: 'Restart',
                variant: AppButtonVariant.outlined,
                size: AppButtonSize.small,
                expanded: false,
                onPressed: onRestart,
              ),
              AppIconButton(
                icon: Assets.icons.close,
                tooltip: 'Remove',
                onPressed: onRemove,
                bordered: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
