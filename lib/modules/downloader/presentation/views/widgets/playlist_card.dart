import 'package:flutter/material.dart';

import '../../../../../core/gen/assets.gen.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/theme.dart';
import '../../../../../core/utils/scale.dart';
import '../../../../../core/widgets/app_button.dart';
import '../../../../../core/widgets/app_icon.dart';
import '../../../../../core/widgets/media_thumb.dart';
import '../../../domain/entities/playlist_download.dart';
import '../../formatters/playlist_formatter.dart';
import 'playlist_tile_grid.dart';

const _radius = 22.0;
const _padding = 16.0;
const _gap = 14.0;
const _stackWidth = 64.0;
const _stackHeight = 48.0;
const _thumbWidth = 52.0;
const _thumbHeight = 32.0;
const _stackStep = 6.0;
const _titleSize = 15.0;
const _countSize = 40.0;
const _columns = 18;
const _tileHeight = 16.0;
const _legendDot = 8.0;

/// A playlist on the Downloads tab: how far it got, every video as a tile,
/// and the two things the user does with it.
class PlaylistCard extends StatelessWidget {
  const PlaylistCard({
    super.key,
    required this.playlist,
    required this.onOpen,
    required this.onPauseAll,
    required this.onResumeAll,
  });

  final PlaylistDownload playlist;
  final VoidCallback onOpen;
  final VoidCallback onPauseAll;
  final VoidCallback onResumeAll;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final paused = playlist.isPaused;
    // A Material, not a decorated box, so the header's ripple paints on the
    // card rather than under its fill.
    return Material(
      color: tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_radius.r),
        side: BorderSide(color: tokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(_padding.r),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: _gap.h,
          children: [
            _Header(playlist: playlist, onOpen: onOpen),
            _Counts(playlist: playlist),
            PlaylistTileGrid(
              items: playlist.tiles,
              columns: _columns,
              tileSize: _tileHeight.h,
              frozen: paused,
            ),
            _Legend(failed: playlist.failed),
            Row(
              spacing: Gap.sm.w,
              children: [
                Expanded(
                  child: AppButton(
                    label: paused ? 'Resume all' : 'Pause all',
                    size: AppButtonSize.compact,
                    onPressed: paused ? onResumeAll : onPauseAll,
                  ),
                ),
                AppButton(
                  label: 'Open queue',
                  variant: AppButtonVariant.outlined,
                  size: AppButtonSize.compact,
                  expanded: false,
                  onPressed: onOpen,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.playlist, required this.onOpen});

  final PlaylistDownload playlist;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final type = context.type;
    return Semantics(
      button: true,
      label: 'Open playlist ${playlist.title}',
      excludeSemantics: true,
      onTap: onOpen,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(Radii.thumb.r),
        child: Row(
          spacing: Gap.md.w,
          children: [
            _Stack(items: playlist.items),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Gap.xs.h,
                children: [
                  Text(
                    playlist.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.bodyStrong.copyWith(
                      fontSize: _titleSize.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    playlist.metaLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: type.mono.copyWith(color: tokens.textMuted),
                  ),
                ],
              ),
            ),
            AppIcon(
              Assets.icons.chevronRight,
              size: AppSizes.iconButton.r,
              color: tokens.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

/// The first three thumbnails, fanned out back to front.
class _Stack extends StatelessWidget {
  const _Stack({required this.items});

  final List<PlaylistItem> items;

  @override
  Widget build(BuildContext context) {
    final shown = items.take(3).toList();
    return SizedBox(
      width: _stackWidth.w,
      height: _stackHeight.h,
      child: Stack(
        children: [
          for (final (index, item) in shown.indexed.toList().reversed)
            Positioned(
              left: (_stackStep * (shown.length - 1 - index)).w,
              top: (_stackStep * index * 1.33).h,
              child: MediaThumb(
                image: networkThumb(item.thumbnailUrl),
                width: _thumbWidth.w,
                height: _thumbHeight.h,
                radius: Radii.thumbSmall,
                dimmed: index > 0,
              ),
            ),
        ],
      ),
    );
  }
}

class _Counts extends StatelessWidget {
  const _Counts({required this.playlist});

  final PlaylistDownload playlist;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final type = context.type;
    final muted = type.mono.copyWith(color: tokens.textMuted);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text.rich(
          maxLines: 1,
          TextSpan(
            children: [
              TextSpan(
                text: '${playlist.done}',
                style: type.hero.copyWith(fontSize: _countSize.sp, height: 1),
              ),
              TextSpan(
                text: ' / ${playlist.items.length} done',
                style: type.body.copyWith(color: tokens.textMuted),
              ),
            ],
          ),
        ),
        SizedBox(width: Gap.md.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: Gap.xs.h,
            children: [
              Text(
                playlist.statusLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: type.bodyStrong.copyWith(
                  color: playlist.isPaused ? tokens.textMuted : tokens.text,
                ),
              ),
              Text(
                playlist.bytesLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: muted,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.failed});

  final int failed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ExcludeSemantics(
      child: Wrap(
        spacing: Gap.lg.w,
        runSpacing: Gap.xs.h,
        children: [
          _Key(color: tokens.accent, label: 'Done'),
          if (failed > 0) _Key(color: tokens.error, label: '$failed failed'),
          _Key(color: tokens.surfaceSunken, label: 'Waiting'),
        ],
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: Gap.xs.w + 2,
    children: [
      Container(
        width: _legendDot.r,
        height: _legendDot.r,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2.r),
        ),
      ),
      Text(
        label,
        style: context.type.caption.copyWith(color: context.tokens.textMuted),
      ),
    ],
  );
}
