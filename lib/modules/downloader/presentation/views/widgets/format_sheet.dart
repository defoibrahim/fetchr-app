import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../../../app/shared/domain/entities/quality.dart';
import '../../../../../core/gen/assets.gen.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/theme.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../core/utils/scale.dart';
import '../../../../../core/widgets/app_button.dart';
import '../../../../../core/widgets/app_progress_bar.dart';
import '../../../../../core/widgets/media_thumb.dart';
import '../../../../../core/widgets/section_header.dart';
import '../../../domain/entities/format_option.dart';
import '../../../domain/entities/media_info.dart';
import '../../formatters/quality_formatter.dart';
import '../../providers/home_notifier.dart';
import 'quality_option.dart';

const _thumbHeight = 196.0;
const _actionGap = 10.0;
const _optionGap = 6.0;
const _thumbGap = 14.0;
const _metaGap = 6.0;
const _headerGap = 18.0;
const _fetchBarGap = 8.0;
const _fetchBar = 4.0;

// What the skeleton is drawn from while the video is fetched. Text becomes
// bones as long as the words, so these read like a real video.
const _placeholder = MediaInfo(
  url: 'https://example.com/watch',
  title: 'The title of a video on its way, long enough to wrap',
  uploader: 'Channel name',
  isPlaylist: false,
  entries: [],
  options: [
    FormatOption(
      quality: Quality.best,
      width: 3840,
      height: 2160,
      fps: 60,
      sizeBytes: 900000000,
    ),
    FormatOption(
      quality: Quality.p1080,
      width: 1920,
      height: 1080,
      fps: 30,
      sizeBytes: 300000000,
    ),
    FormatOption(
      quality: Quality.p720,
      width: 1280,
      height: 720,
      fps: 30,
      sizeBytes: 150000000,
    ),
    FormatOption(
      quality: Quality.p480,
      width: 854,
      height: 480,
      fps: 30,
      sizeBytes: 80000000,
    ),
    FormatOption(quality: Quality.mp3, sizeBytes: 9000000),
  ],
);

/// The quality picker for the video `homeNotifierProvider` is fetching: the
/// same layout as a skeleton while it loads, then one row per option. Open it with
/// `showAppBottomSheet<Quality>`; it pops the chosen [Quality], or null.
class FormatSheet extends ConsumerStatefulWidget {
  const FormatSheet({super.key, required this.initialQuality, this.preselect});

  /// The Settings default.
  final Quality initialQuality;

  /// Starts on this option instead, when the source offers it.
  final Quality? preselect;

  @override
  ConsumerState<FormatSheet> createState() => _FormatSheetState();
}

class _FormatSheetState extends ConsumerState<FormatSheet> {
  Quality? _picked;

  // Home clears the fetch as the sheet closes; keeping the video stops the
  // exit animation from flashing the skeleton.
  MediaInfo? _info;

  static MediaInfo? _single(AsyncValue<MediaInfo?> state) => switch (state) {
    AsyncData(value: final info?) when !info.isPlaylist => info,
    _ => null,
  };

  Quality _defaultQuality(MediaInfo info) {
    final wanted = widget.preselect;
    final preset = wanted == null ? null : info.optionFor(wanted);
    return (preset ?? info.pick(widget.initialQuality)).quality;
  }

  @override
  Widget build(BuildContext context) {
    final info = _info = _single(ref.watch(homeNotifierProvider)) ?? _info;
    final selected = info == null ? null : _picked ?? _defaultQuality(info);
    final gutter = context.gutter;
    // The dialog hugs its content; the sheet fills its height so Cancel and
    // Download stay pinned to the bottom.
    final hug = context.findAncestorWidgetOfExactType<Dialog>() != null;

    return Padding(
      // The grabber above already leaves 4 of the design's 16.
      padding: EdgeInsets.fromLTRB(gutter, Gap.md.h, gutter, Gap.gutter.h),
      child: Column(
        mainAxisSize: hug ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            fit: hug ? FlexFit.loose : FlexFit.tight,
            child: SingleChildScrollView(
              child: Skeletonizer(
                enabled: info == null,
                effect: _skeletonEffect(context),
                child: _Details(
                  info: info ?? _placeholder,
                  selected: selected,
                  fetching: info == null,
                  onSelect: (q) => setState(() => _picked = q),
                ),
              ),
            ),
          ),
          SizedBox(height: Gap.md.h),
          Row(
            spacing: _actionGap.w,
            children: [
              AppButton(
                label: 'Cancel',
                variant: AppButtonVariant.outlined,
                expanded: false,
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: AppButton(
                  label: selected == null ? 'Download' : selected.downloadLabel,
                  icon: Assets.icons.download,
                  onPressed: selected == null
                      ? null
                      : () => Navigator.of(context).pop(selected),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Still under reduce motion: the package does not read it.
PaintingEffect _skeletonEffect(BuildContext context) {
  final tokens = context.tokens;
  return context.reduceMotion
      ? SolidColorEffect(color: tokens.surfaceSunken)
      : ShimmerEffect(
          baseColor: tokens.surfaceSunken,
          highlightColor: tokens.shimmer,
        );
}

class _Details extends StatelessWidget {
  const _Details({
    required this.info,
    required this.selected,
    required this.onSelect,
    this.fetching = false,
  });

  final MediaInfo info;

  /// Null while fetching: the skeleton picks nothing.
  final Quality? selected;
  final ValueChanged<Quality> onSelect;

  /// Draws the sliding bar under the thumbnail, kept out of the skeleton.
  final bool fetching;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final type = context.type;
    final options = info.options;
    final thumbnail = info.thumbnail;
    final duration = formatDuration(info.durationSec);
    final meta = sourceLine(info.url, info.uploader);
    final estimated = options.any(
      (o) => o.sizeBytes != null && o.sizeIsEstimate,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // One bone: the stripes are a painter, which the shimmer skips.
        Skeleton.replace(
          replacement: Bone(
            width: double.infinity,
            height: _thumbHeight.h,
            borderRadius: BorderRadius.circular(Radii.control.r),
          ),
          child: MediaThumb(
            image: networkThumb(thumbnail),
            width: double.infinity,
            height: _thumbHeight.h,
            radius: Radii.control,
            duration: duration.isEmpty ? null : duration,
            isLive: info.isLive,
          ),
        ),
        if (fetching) ...[
          SizedBox(height: _fetchBarGap.h),
          const Skeleton.keep(
            child: AppProgressBar(
              height: _fetchBar,
              semanticsLabel: 'Getting formats',
            ),
          ),
        ],
        SizedBox(height: _thumbGap.h),
        Text(
          info.title,
          style: type.sheetTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: _metaGap.h),
        Text(
          meta,
          style: type.mono.copyWith(color: tokens.textMuted),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Skeleton.keep(child: _QualityHeader(showEstimateNote: estimated)),
        Column(
          spacing: _optionGap.h,
          children: [
            for (final option in options)
              QualityOption(
                option: option,
                selected: option.quality == selected,
                onTap: () => onSelect(option.quality),
              ),
          ],
        ),
      ],
    );
  }
}

class _QualityHeader extends StatelessWidget {
  const _QualityHeader({required this.showEstimateNote});

  final bool showEstimateNote;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final type = context.type;
    return Padding(
      padding: EdgeInsets.only(top: _headerGap.h, bottom: Gap.sm.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        spacing: Gap.sm.w,
        children: [
          const SectionOverline('Quality'),
          if (showEstimateNote)
            Flexible(
              child: Text(
                'Sizes are estimates',
                style: type.caption.copyWith(color: tokens.textMuted),
                textAlign: TextAlign.end,
              ),
            ),
        ],
      ),
    );
  }
}
