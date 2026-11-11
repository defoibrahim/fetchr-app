import 'package:flutter/material.dart';

import '../../core/gen/assets.gen.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_extensions.dart';
import '../../core/utils/scale.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_progress_bar.dart';
import '../../core/widgets/empty_view.dart';
import '../../core/widgets/media_thumb.dart';
import 'gallery_section.dart';

const _thumbWidth = 128.0;
const _emptyHeight = 360.0;

class ThumbsSection extends StatelessWidget {
  const ThumbsSection({super.key});

  @override
  Widget build(BuildContext context) {
    Widget thumb(String label, MediaThumb child) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Gap.xs.h,
      children: [child, GalleryCaption(label)],
    );

    final width = _thumbWidth.w;
    return GallerySection(
      title: 'Media thumbnails',
      children: [
        Wrap(
          spacing: Gap.md.w,
          runSpacing: Gap.md.h,
          children: [
            thumb('placeholder', MediaThumb(width: width, aspectRatio: 16 / 9)),
            thumb(
              'duration',
              MediaThumb(width: width, aspectRatio: 16 / 9, duration: '12:34'),
            ),
            thumb(
              'live',
              MediaThumb(width: width, aspectRatio: 16 / 9, isLive: true),
            ),
            thumb(
              'audio',
              MediaThumb(
                width: width,
                aspectRatio: 16 / 9,
                isAudio: true,
                duration: '3:41',
              ),
            ),
            thumb(
              'dimmed',
              MediaThumb(
                width: width,
                aspectRatio: 16 / 9,
                duration: '0:48',
                dimmed: true,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class ProgressSection extends StatelessWidget {
  const ProgressSection({super.key});

  @override
  Widget build(BuildContext context) {
    return GallerySection(
      title: 'Progress bar',
      children: [
        const GalleryExample(label: '0%', child: AppProgressBar(value: 0)),
        const GalleryExample(label: '64%', child: AppProgressBar(value: .64)),
        const GalleryExample(label: '100%', child: AppProgressBar(value: 1)),
        GalleryExample(
          label: 'paused',
          child: AppProgressBar(
            value: .64,
            color: context.tokens.textMuted,
            semanticsLabel: 'Paused download',
          ),
        ),
        const GalleryExample(
          label: 'unknown',
          child: AppProgressBar(semanticsLabel: 'Working'),
        ),
      ],
    );
  }
}

class EmptySection extends StatelessWidget {
  const EmptySection({super.key});

  @override
  Widget build(BuildContext context) {
    return GallerySection(
      title: 'Empty view',
      children: [
        SizedBox(
          height: _emptyHeight.h,
          width: double.infinity,
          child: EmptyView(
            illustration: Assets.icons.emptyDownloads,
            title: 'Nothing downloading',
            message: 'Paste a link on Home and your downloads show up here.',
            action: const AppButton(
              label: 'Paste a link',
              onPressed: noop,
              variant: AppButtonVariant.outlined,
              size: AppButtonSize.medium,
              expanded: false,
            ),
          ),
        ),
        SizedBox(
          height: _emptyHeight.h / 2,
          width: double.infinity,
          child: const EmptyView(message: 'No title, no art, no action.'),
        ),
      ],
    );
  }
}
