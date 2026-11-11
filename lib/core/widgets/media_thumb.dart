import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../gen/assets.gen.dart';
import '../theme/app_spacing.dart';
import '../theme/theme_extensions.dart';
import '../utils/scale.dart';
import 'app_icon.dart';
import 'stripes.dart';

const _audioIconSize = 22.0;
const _badgeInset = 4.0;
const _badgeRadius = 4.0;
const _badgePadX = 4.0;
const _badgePadY = 1.0;
const _dimmedOpacity = 0.6;
const _fade = Duration(milliseconds: 150);

/// The image for a thumbnail URL from yt-dlp, which may be missing or empty.
ImageProvider? networkThumb(String? url) =>
    url == null || url.isEmpty ? null : NetworkImage(url);

/// A video or audio thumbnail: the image over a stripe placeholder, an audio
/// tile with a music note, and the duration and live badges.
///
/// `width` and `height` are final logical sizes, so callers scale them; an
/// infinite `width` takes the parent's, and a null `height` follows
/// `aspectRatio`. `radius` is a design value and is scaled here.
class MediaThumb extends StatelessWidget {
  const MediaThumb({
    super.key,
    this.image,
    required this.width,
    this.height,
    this.aspectRatio,
    this.radius = Radii.thumb,
    this.duration,
    this.isAudio = false,
    this.isLive = false,
    this.dimmed = false,
  }) : assert(height != null || aspectRatio != null);

  final ImageProvider? image;
  final double width;
  final double? height;
  final double? aspectRatio;
  final double radius;
  final String? duration;
  final bool isAudio;
  final bool isLive;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final thumb = LayoutBuilder(
      builder: (context, constraints) {
        final boxWidth = width.isFinite ? width : constraints.maxWidth;
        final boxHeight = height ?? boxWidth / aspectRatio!;
        return SizedBox(
          width: boxWidth,
          height: boxHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius.r),
            child: _layers(context, boxWidth, boxHeight),
          ),
        );
      },
    );
    return dimmed ? Opacity(opacity: _dimmedOpacity, child: thumb) : thumb;
  }

  Widget _layers(BuildContext context, double boxWidth, double boxHeight) {
    final tokens = context.tokens;
    final type = context.type;
    final stripes = Stripes(band: (boxHeight / 6).clamp(7, 10));
    final source = image;
    final badge = duration;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (isAudio)
          const AudioTile()
        else ...[
          stripes,
          if (source != null)
            Image(
              image: ResizeImage.resizeIfNeeded(
                _decodeWidth(context, boxWidth, boxHeight),
                null,
                source,
              ),
              fit: BoxFit.cover,
              frameBuilder: _fadeIn,
              errorBuilder: (_, _, _) => stripes,
            ),
        ],
        if (badge != null && badge.isNotEmpty)
          Positioned(
            right: _badgeInset.r,
            bottom: _badgeInset.r,
            child: _Badge(
              fill: tokens.mediaScrim,
              child: Text(
                badge,
                style: type.monoBadge.copyWith(color: tokens.onMedia),
              ),
            ),
          ),
        if (isLive)
          Positioned(
            left: _badgeInset.r,
            top: _badgeInset.r,
            child: _Badge(
              fill: tokens.error,
              child: Text(
                'LIVE',
                style: type.monoBadge.copyWith(
                  color: tokens.onError,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // Decode near the box size, not the source size. One side only: both would
  // stretch the image. Width, wide enough that a 16:9 source still covers the
  // box height; a 9:16 source then covers the width with room to spare.
  int _decodeWidth(BuildContext context, double boxWidth, double boxHeight) =>
      (math.max(boxWidth, boxHeight * 16 / 9) *
              MediaQuery.devicePixelRatioOf(context))
          .ceil();

  Widget _fadeIn(
    BuildContext context,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    if (wasSynchronouslyLoaded) return child;
    return AnimatedOpacity(
      opacity: frame == null ? 0 : 1,
      duration: context.motion(_fade),
      child: child,
    );
  }
}

/// The audio surface: the `audioTile` fill with a centred music note in the
/// accent. `iconSize` is a design value and is scaled here.
class AudioTile extends StatelessWidget {
  const AudioTile({super.key, this.iconSize = _audioIconSize});

  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ColoredBox(
      color: tokens.audioTile,
      child: Center(
        child: AppIcon(
          Assets.icons.music,
          size: iconSize.r,
          color: tokens.accent,
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.fill, required this.child});

  final Color fill;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(_badgeRadius.r),
    ),
    child: Padding(
      padding: EdgeInsets.symmetric(
        horizontal: _badgePadX.w,
        vertical: _badgePadY.h,
      ),
      child: child,
    ),
  );
}
