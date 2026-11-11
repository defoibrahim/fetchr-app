import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../../core/theme/theme_extensions.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../core/utils/scale.dart';
import '../../../../../core/widgets/action_menu.dart';
import '../../../../../core/widgets/media_thumb.dart';
import '../../../domain/entities/library_item.dart';
import '../../formatters/library_item_formatter.dart';
import '../../providers/library_thumbnail_provider.dart';

const _thumbAspect = 16 / 10;
const _titleLines = 2;
const _titleLineHeight = 1.25;
const _titleGap = 3.0;

TextStyle _titleStyle(AppTextStyles type) =>
    type.body.copyWith(fontWeight: FontWeight.w500, height: _titleLineHeight);

// Every line is exactly the strut's height. A glyph Geist lacks, such as the
// full-width ｜ yt-dlp puts in file names, is drawn in a taller system font and
// would make its line a pixel taller than heightFor allows.
StrutStyle _strut(TextStyle style) =>
    StrutStyle.fromTextStyle(style, forceStrutHeight: true);

// The dots are 44 dp wide and sit flush right; the text stops where their
// 18 dp glyph begins, as in the mockup where the box overhangs the card.
const _dotsReserve = 34.0;

/// One file in the Library grid: a 16:10 picture that plays it, the title in two
/// lines, the quality and size, and a menu on the dots or a long press.
class LibraryCard extends StatelessWidget {
  const LibraryCard({
    super.key,
    required this.item,
    required this.onPlay,
    required this.onShare,
    required this.onOpenFolder,
    required this.onDelete,
  });

  final LibraryItem item;
  final VoidCallback onPlay;
  final VoidCallback onShare;
  final VoidCallback onOpenFolder;
  final VoidCallback onDelete;

  /// The height a grid row must give a card [width] wide: the picture plus the
  /// text block at two title lines, which follows the user's text scale.
  static double heightFor(BuildContext context, double width) {
    final scaler = MediaQuery.textScalerOf(context);
    final type = context.type;
    final text =
        Gap.sm.h +
        _linesHeight(_titleStyle(type), _titleLines, scaler) +
        _titleGap.h +
        _linesHeight(type.monoSmall, 1, scaler);
    return width / _thumbAspect + math.max(text, AppSizes.touch.r);
  }

  // Laid out, not computed: the engine rounds a line's ascent and descent on
  // their own, which a font size times a height cannot predict.
  static double _linesHeight(TextStyle style, int lines, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: List.filled(lines, ' ').join('\n'), style: style),
      strutStyle: _strut(style),
      textScaler: scaler,
      textDirection: TextDirection.ltr,
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }

  @override
  Widget build(BuildContext context) {
    return ActionMenu(
      items: [
        ActionMenuItem.play(onPlay),
        ActionMenuItem.share(onShare),
        ActionMenuItem.showInFolder(onOpenFolder),
        ActionMenuItem.deleteFile(onDelete),
      ],
      builder: (context, controller) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: controller.open,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Picture(item: item, onPlay: onPlay),
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: AppSizes.touch.r),
              child: Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.only(
                      top: Gap.sm.h,
                      right: _dotsReserve.w,
                    ),
                    child: _Text(item: item),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: MoreActionsDots(controller: controller),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Picture extends ConsumerWidget {
  const _Picture({required this.item, required this.onPlay});

  final LibraryItem item;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // An audio file has no frame to ask for: the tile stands in.
    final path = item.isAudio
        ? null
        : ref.watch(libraryThumbnailProvider(item.uri)).value;
    final seconds = (item.durationMs ?? 0) ~/ 1000;
    return Semantics(
      container: true,
      button: true,
      label: 'Play ${item.name}',
      onTap: onPlay,
      excludeSemantics: true,
      child: Stack(
        children: [
          MediaThumb(
            image: path == null ? null : FileImage(File(path)),
            width: double.infinity,
            aspectRatio: _thumbAspect,
            radius: Radii.row,
            duration: seconds > 0 ? formatDuration(seconds) : null,
            isAudio: item.isAudio,
          ),
          // The ink goes above the picture, which would hide it underneath.
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onPlay,
                borderRadius: BorderRadius.circular(Radii.row.r),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Text extends StatelessWidget {
  const _Text({required this.item});

  final LibraryItem item;

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    final title = _titleStyle(type);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: _titleGap.h,
      children: [
        Text(
          item.name,
          maxLines: _titleLines,
          overflow: TextOverflow.ellipsis,
          style: title,
          strutStyle: _strut(title),
        ),
        Text(
          item.metaText,
          textDirection: TextDirection.ltr,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: type.monoSmall.copyWith(color: context.tokens.textMuted),
          strutStyle: _strut(type.monoSmall),
        ),
      ],
    );
  }
}
