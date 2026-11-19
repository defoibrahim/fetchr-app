import 'package:flutter/material.dart';

import '../../../../../core/gen/assets.gen.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/theme.dart';
import '../../../../../core/utils/scale.dart';
import '../../../../../core/widgets/app_button.dart';
import '../../../../../core/widgets/app_icon_button.dart';
import '../../../../../core/widgets/app_progress_bar.dart';
import '../../../../../core/widgets/media_thumb.dart';
import '../../../domain/entities/playlist_download.dart';
import '../../formatters/download_task_formatter.dart';
import '../../formatters/playlist_formatter.dart';
import 'playlist_tile_grid.dart';

const _currentWidth = 148.0;
const _currentHeight = 84.0;
const _currentBar = 4.0;
const _currentTitleSize = 18.0;
const _panelRadius = 22.0;
const _panelPadding = 16.0;
const _gridColumns = 12;
const _gridGap = 4.0;
const _gridRadius = 6.0;
const _rowThumbWidth = 56.0;
const _rowThumbHeight = 34.0;
const _rowPadY = 8.0;
const _textGap = 3.0;
const _chipPad = 6.0;
const _barHeight = 52.0;

/// What the selected tile's row offers: by its status, or nothing for the
/// video on its way.
enum TileAction {
  play('Play'),
  retry('Retry'),
  skip('Skip'),
  addBack('Add back');

  const TileAction(this.label);

  final String label;

  static TileAction? of(PlaylistItemStatus status) => switch (status) {
    PlaylistItemStatus.done => TileAction.play,
    PlaylistItemStatus.failed => TileAction.retry,
    PlaylistItemStatus.queued => TileAction.skip,
    PlaylistItemStatus.skipped => TileAction.addBack,
    PlaylistItemStatus.downloading => null,
  };
}

/// The video on its way: a large thumbnail with its bar, then its status,
/// title and numbers.
class CurrentItem extends StatelessWidget {
  const CurrentItem({super.key, required this.item});

  final PlaylistItem item;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final type = context.type;
    final task = item.task;
    final paused = task.isPaused;
    final stats = task.stats;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Gap.md.w,
      children: [
        SizedBox(
          width: _currentWidth.w,
          child: Column(
            spacing: Gap.sm.h,
            children: [
              Stack(
                children: [
                  MediaThumb(
                    image: networkThumb(item.thumbnailUrl),
                    width: _currentWidth.w,
                    height: _currentHeight.h,
                  ),
                  Positioned(
                    left: _chipPad.r,
                    top: _chipPad.r,
                    child: _Chip(text: item.place),
                  ),
                ],
              ),
              AppProgressBar(
                value: task.progress >= 0 ? item.progress : null,
                height: _currentBar.h,
                color: paused ? tokens.textMuted : null,
                semanticsLabel: 'Video ${item.index} progress',
              ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: _textGap.h,
            children: [
              Text(
                item.currentLabel,
                style: type.overline.copyWith(
                  color: paused ? tokens.textMuted : tokens.text,
                ),
              ),
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: type.section.copyWith(fontSize: _currentTitleSize.sp),
              ),
              Text(
                paused
                    ? task.pausedText
                    : '${stats.percent ?? ''}${stats.rest}',
                style: type.mono.copyWith(color: tokens.textMuted),
              ),
              if (!paused)
                Text(
                  stats.right,
                  style: type.mono.copyWith(color: tokens.textMuted),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.mediaScrim,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: _chipPad.w, vertical: 2.h),
        child: Text(
          text,
          style: context.type.monoBadge.copyWith(color: tokens.onMedia),
        ),
      ),
    );
  }
}

/// The summary line, the grid of every video and the selected one's row.
class TilePanel extends StatelessWidget {
  const TilePanel({
    super.key,
    required this.playlist,
    required this.selected,
    required this.onSelect,
    required this.onAction,
  });

  final PlaylistDownload playlist;
  final PlaylistItem? selected;
  final ValueChanged<PlaylistItem> onSelect;
  final void Function(PlaylistItem item, TileAction action) onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final type = context.type;
    final tiles = playlist.tiles;
    final eta = playlist.etaShort;
    final chosen = selected;
    return Container(
      padding: EdgeInsets.all(_panelPadding.r),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(_panelRadius.r),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Gap.md.h,
        children: [
          Row(
            children: [
              Expanded(child: Text(playlist.summary, style: type.bodyStrong)),
              if (eta != null)
                Text(eta, style: type.mono.copyWith(color: tokens.textMuted)),
            ],
          ),
          PlaylistTileGrid(
            items: tiles,
            columns: _gridColumns,
            gap: _gridGap.r,
            radius: _gridRadius.r,
            selectedIndex: chosen == null ? null : tiles.indexOf(chosen),
            frozen: playlist.isPaused,
            onTap: (index) => onSelect(tiles[index]),
          ),
          if (chosen != null)
            _SelectedRow(
              playlist: playlist,
              item: chosen,
              onAction: (action) => onAction(chosen, action),
            ),
        ],
      ),
    );
  }
}

class _SelectedRow extends StatelessWidget {
  const _SelectedRow({
    required this.playlist,
    required this.item,
    required this.onAction,
  });

  final PlaylistDownload playlist;
  final PlaylistItem item;
  final ValueChanged<TileAction> onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final type = context.type;
    final action = TileAction.of(item.status);
    return Row(
      spacing: Gap.md.w,
      children: [
        Text('#${item.index}', style: type.mono),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: _textGap.h,
            children: [
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: type.bodyStrong,
              ),
              Text(
                playlist.metaOf(item),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: type.mono.copyWith(color: tokens.textMuted),
              ),
            ],
          ),
        ),
        if (action != null)
          AppButton(
            label: action.label,
            variant: AppButtonVariant.outlined,
            size: AppButtonSize.small,
            expanded: false,
            onPressed: () => onAction(action),
          ),
      ],
    );
  }
}

/// A video waiting to start: drag it by the handle, or skip it.
class UpNextRow extends StatelessWidget {
  const UpNextRow({
    super.key,
    required this.item,
    required this.index,
    required this.draggable,
    required this.onSkip,
  });

  final PlaylistItem item;
  final int index;
  final bool draggable;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final type = context.type;
    final handle = Icon(
      Icons.drag_indicator_rounded,
      size: AppSizes.iconButton.r,
      color: draggable ? tokens.textMuted : tokens.border,
      semanticLabel: draggable ? 'Drag to reorder' : null,
    );
    return ColoredBox(
      color: tokens.bg,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: _rowPadY.h),
        child: Row(
          spacing: Gap.md.w,
          children: [
            if (draggable)
              ReorderableDragStartListener(index: index, child: handle)
            else
              handle,
            MediaThumb(
              image: networkThumb(item.thumbnailUrl),
              width: _rowThumbWidth.w,
              height: _rowThumbHeight.h,
              radius: Radii.thumbSmall,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: _textGap.h,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.bodyStrong,
                  ),
                  Text(
                    item.queueMeta,
                    style: type.mono.copyWith(color: tokens.textMuted),
                  ),
                ],
              ),
            ),
            AppIconButton(
              icon: Assets.icons.close,
              tooltip: 'Skip',
              onPressed: onSkip,
            ),
          ],
        ),
      ),
    );
  }
}

/// Stop and Pause all, pinned under the list.
class PlaylistBar extends StatelessWidget {
  const PlaylistBar({
    super.key,
    required this.paused,
    required this.onStop,
    required this.onPauseAll,
    required this.onResumeAll,
  });

  final bool paused;
  final VoidCallback onStop;
  final VoidCallback onPauseAll;
  final VoidCallback onResumeAll;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final gutter = context.gutter;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.bg,
        border: Border(top: BorderSide(color: tokens.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(gutter, Gap.md.h, gutter, Gap.md.h),
          child: Row(
            spacing: Gap.sm.w,
            children: [
              Expanded(
                child: SizedBox(
                  height: _barHeight.h,
                  child: AppButton(
                    label: 'Stop playlist',
                    variant: AppButtonVariant.destructiveOutline,
                    onPressed: onStop,
                  ),
                ),
              ),
              Expanded(
                child: SizedBox(
                  height: _barHeight.h,
                  child: AppButton(
                    label: paused ? 'Resume' : 'Pause all',
                    onPressed: paused ? onResumeAll : onPauseAll,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
