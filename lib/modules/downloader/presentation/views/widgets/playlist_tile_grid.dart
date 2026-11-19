import 'package:flutter/material.dart';

import '../../../../../core/theme/theme.dart';
import '../../../../../core/widgets/app_pressable.dart';
import '../../../../../core/widgets/stripes.dart';
import '../../../domain/entities/playlist_download.dart';
import '../../formatters/playlist_formatter.dart';

const _fillDuration = Duration(milliseconds: 250);
const _activeBorder = 1.5;
const _selectedBorder = 2.0;
const _stripeBand = 3.0;

/// One tile per video, in playlist order: what is done, on its way, waiting,
/// failed or skipped, at a glance.
class PlaylistTileGrid extends StatelessWidget {
  const PlaylistTileGrid({
    super.key,
    required this.items,
    required this.columns,
    this.tileSize,
    this.gap = 3,
    this.radius = 4,
    this.selectedIndex,
    this.onTap,
    this.frozen = false,
  });

  final List<PlaylistItem> items;
  final int columns;

  /// The tile's height; null makes tiles square.
  final double? tileSize;
  final double gap;
  final double radius;
  final int? selectedIndex;
  final ValueChanged<int>? onTap;

  /// Paused or stopped: the fill stops where it is instead of easing on.
  final bool frozen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final (index, item) in items.indexed)
            _Tile(
              item: item,
              width: width,
              height: tileSize ?? width,
              radius: radius,
              selected: index == selectedIndex,
              animate: !frozen && !context.reduceMotion,
              onTap: onTap == null ? null : () => onTap!(index),
            ),
        ],
      );
    },
  );
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.item,
    required this.width,
    required this.height,
    required this.radius,
    required this.selected,
    required this.animate,
    required this.onTap,
  });

  final PlaylistItem item;
  final double width;
  final double height;
  final double radius;
  final bool selected;
  final bool animate;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final shape = BorderRadius.circular(radius);
    final status = item.status;
    // A card can hold hundreds of tiles: only the patterned faces clip.
    Widget solid(Color color) => DecoratedBox(
      decoration: BoxDecoration(color: color, borderRadius: shape),
    );
    final face = switch (status) {
      PlaylistItemStatus.done => solid(tokens.accent),
      PlaylistItemStatus.failed => solid(tokens.error),
      PlaylistItemStatus.queued => solid(tokens.surfaceSunken),
      PlaylistItemStatus.skipped => ClipRRect(
        borderRadius: shape,
        child: const Stripes(band: _stripeBand),
      ),
      PlaylistItemStatus.downloading => ClipRRect(
        borderRadius: shape,
        child: _Rising(progress: item.progress, animate: animate),
      ),
    };
    final tap = onTap;
    final Widget tile = Container(
      width: width,
      height: height,
      foregroundDecoration: BoxDecoration(
        borderRadius: shape,
        border: selected
            ? Border.all(
                color: tokens.text,
                width: _selectedBorder,
                strokeAlign: BorderSide.strokeAlignOutside,
              )
            : status == PlaylistItemStatus.downloading
            ? Border.all(color: tokens.accent, width: _activeBorder)
            : null,
      ),
      child: face,
    );
    return Semantics(
      label: 'Video ${item.index}, ${status.label}',
      selected: selected,
      button: tap != null,
      onTap: tap,
      excludeSemantics: true,
      child: tap == null
          ? tile
          : AppPressable(
              onTap: tap,
              borderRadius: shape,
              pressedScale: .9,
              // The face is opaque: the ripple goes over it.
              inkAbove: true,
              child: tile,
            ),
    );
  }
}

/// The accent rising from the bottom to the video's progress.
class _Rising extends StatelessWidget {
  const _Rising({required this.progress, required this.animate});

  final double progress;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ColoredBox(
      color: tokens.surfaceSunken,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: progress),
        duration: animate ? _fillDuration : Duration.zero,
        curve: Curves.easeOut,
        builder: (_, value, _) => Align(
          alignment: Alignment.bottomCenter,
          child: FractionallySizedBox(
            heightFactor: value,
            widthFactor: 1,
            child: ColoredBox(color: tokens.accent),
          ),
        ),
      ),
    );
  }
}
