import 'package:flutter/material.dart';

import '../../../../../core/gen/assets.gen.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/theme.dart';
import '../../../../../core/utils/scale.dart';
import '../../../../../core/widgets/action_menu.dart';
import '../../../../../core/widgets/app_icon.dart';
import '../../../domain/entities/download_task.dart';
import '../../formatters/download_task_formatter.dart';

const _minHeight = 48.0;
const _circle = 28.0;
const _checkSize = 16.0;
const _padY = 4.0;
const _padX = 2.0;
const _textGap = 2.0;
const _popFrom = .6;

/// A finished download. A tap plays it; a long press opens Play, Show in
/// folder and Delete file.
class DoneRow extends StatelessWidget {
  const DoneRow({
    super.key,
    required this.task,
    required this.onPlay,
    required this.onShowInFolder,
    required this.onDelete,
    this.popCheck = false,
  });

  static const popDuration = Duration(milliseconds: 320);

  final DownloadTask task;
  final VoidCallback onPlay;
  final VoidCallback onShowInFolder;
  final VoidCallback onDelete;

  /// The download has just finished: the check pops in once as the row is
  /// first built. The list passes it only for that frame, so a row that
  /// scrolls in later, or comes back, just shows its check.
  final bool popCheck;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final type = context.type;
    return ActionMenu(
      items: [
        ActionMenuItem.play(onPlay),
        ActionMenuItem.showInFolder(onShowInFolder),
        ActionMenuItem.deleteFile(onDelete),
      ],
      builder: (context, menu) => InkWell(
        onTap: onPlay,
        onLongPress: () => menu.isOpen ? menu.close() : menu.open(),
        borderRadius: BorderRadius.circular(Radii.thumb.r),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: _minHeight.h),
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: _padY.h,
              horizontal: _padX.w,
            ),
            child: Row(
              spacing: Gap.md.w,
              children: [
                _Check(
                  pop: popCheck,
                  child: Container(
                    width: _circle.r,
                    height: _circle.r,
                    decoration: BoxDecoration(
                      color: tokens.accentTint,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    // The accent in dark, the ink in light: never accent on
                    // white.
                    child: AppIcon(
                      Assets.icons.check,
                      size: _checkSize.r,
                      color: context.colors.primary,
                    ),
                  ),
                ),
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
                        style: type.body.copyWith(fontWeight: FontWeight.w500),
                      ),
                      Text(
                        task.doneMeta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.ltr,
                        style: type.monoSmall.copyWith(color: tokens.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The check's one pop, from 60% with an overshoot, when [pop] is set as it
/// is first built (the tween's begin only counts then). Under reduce motion it
/// just shows.
class _Check extends StatelessWidget {
  const _Check({required this.pop, required this.child});

  final bool pop;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final from = pop && !context.reduceMotion ? _popFrom : 1.0;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: from, end: 1),
      duration: DoneRow.popDuration,
      curve: Motion.pop,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: child,
    );
  }
}
