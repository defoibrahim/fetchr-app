import 'package:flutter/material.dart';

import '../../../../../core/gen/assets.gen.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/theme.dart';
import '../../../../../core/utils/scale.dart';
import '../../../../../core/widgets/app_icon_button.dart';
import '../../../domain/entities/download_task.dart';
import '../../formatters/download_task_formatter.dart';
import 'download_parts.dart';

const _rowPadY = 6.0;
const _rowPadX = 2.0;
const _textGap = 3.0;

/// The queue as rows: the one that runs next, and under it, when the user taps
/// that row, the rest in order. [tasks] is oldest first and not empty.
class QueuedRows extends StatelessWidget {
  const QueuedRows({
    super.key,
    required this.tasks,
    required this.expanded,
    required this.onToggle,
    required this.onCancel,
  }) : assert(tasks.length > 0);

  final List<DownloadTask> tasks;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<String> onCancel;

  @override
  Widget build(BuildContext context) {
    final more = tasks.length - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          expanded: more > 0 ? expanded : null,
          child: _QueuedRow(
            task: tasks.first,
            text: tasks.first.queuedText(more: more),
            onTap: more > 0 ? onToggle : null,
            onCancel: () => onCancel(tasks.first.id),
          ),
        ),
        if (expanded)
          for (final task in tasks.skip(1))
            _QueuedRow(
              key: ValueKey(task.id),
              task: task,
              text: task.queuedText(),
              onCancel: () => onCancel(task.id),
            ),
      ],
    );
  }
}

class _QueuedRow extends StatelessWidget {
  const _QueuedRow({
    super.key,
    required this.task,
    required this.text,
    required this.onCancel,
    this.onTap,
  });

  final DownloadTask task;
  final String text;
  final VoidCallback onCancel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: _rowPadY.h,
        horizontal: _rowPadX.w,
      ),
      child: Row(
        spacing: Gap.md.w,
        children: [
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(Radii.thumb.r),
              child: Row(
                spacing: Gap.md.w,
                children: [
                  DownloadThumb(task: task, dimmed: true),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      spacing: _textGap.h,
                      children: [
                        Text(
                          task.request.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: type.body.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          text,
                          style: type.caption.copyWith(
                            color: context.tokens.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          AppIconButton(
            icon: Assets.icons.close,
            tooltip: 'Cancel download',
            onPressed: onCancel,
            bordered: true,
          ),
        ],
      ),
    );
  }
}
