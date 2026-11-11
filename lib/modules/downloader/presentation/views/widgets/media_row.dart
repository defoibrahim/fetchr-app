import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/theme_extensions.dart';
import '../../../../../core/utils/scale.dart';
import '../../../../../core/widgets/media_thumb.dart';

const _thumbWidth = 84.0;
const _thumbHeight = 48.0;
const _thumbGap = 14.0;
const _textGap = 4.0;

/// A 64 high row: an 84 x 48 thumbnail, the title on one line and a mono meta
/// line. The whole row is the tap target.
class MediaRow extends StatelessWidget {
  const MediaRow({
    super.key,
    required this.title,
    required this.meta,
    required this.onTap,
    this.thumbnailUrl,
    this.duration,
    this.isAudio = false,
  });

  final String title;
  final String meta;
  final VoidCallback onTap;
  final String? thumbnailUrl;
  final String? duration;
  final bool isAudio;

  @override
  Widget build(BuildContext context) {
    final url = thumbnailUrl;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.thumb.r),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: AppSizes.rowRecent.h),
        child: Row(
          spacing: _thumbGap.w,
          children: [
            MediaThumb(
              image: networkThumb(url),
              width: _thumbWidth.w,
              height: _thumbHeight.h,
              duration: duration,
              isAudio: isAudio,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                spacing: _textGap.h,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.type.bodyStrong,
                  ),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.ltr,
                    style: context.type.monoSmall.copyWith(
                      color: context.tokens.textMuted,
                    ),
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
