import 'package:flutter/material.dart';

import '../../../../../core/gen/assets.gen.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/theme.dart';
import '../../../../../core/utils/formatters.dart';
import '../../../../../core/utils/scale.dart';
import '../../../../../core/widgets/app_button.dart';
import '../../../../../core/widgets/centered_content.dart';
import '../../../../../core/widgets/media_thumb.dart';
import '../../../domain/entities/media_info.dart';
import '../../../domain/entities/playlist_selection.dart';
import 'download_parts.dart';

const _checkSize = 20.0;
const _untickedOpacity = 0.55;
const _barGap = 10.0;
const _barTop = 14.0;
const _barBottom = 22.0;

/// A checkbox that only draws the state; the row around it is the tap target.
class _CheckMark extends StatelessWidget {
  const _CheckMark({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: SizedBox.square(
        dimension: _checkSize.r,
        child: Checkbox(value: checked, onChanged: null),
      ),
    ),
  );
}

class SelectAllRow extends StatelessWidget {
  const SelectAllRow({super.key, required this.selection, required this.onTap});

  final PlaylistSelection selection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final type = context.type;
    final progress = '${selection.count} of ${selection.total} selected';
    return Semantics(
      container: true,
      excludeSemantics: true,
      checked: selection.allSelected,
      label: 'Select all',
      value: progress,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: AppSizes.touch.h),
          child: Row(
            spacing: Gap.md.w,
            children: [
              _CheckMark(checked: selection.allSelected),
              Text(
                'Select all',
                style: type.body.copyWith(fontWeight: FontWeight.w500),
              ),
              Expanded(
                child: Text(
                  progress,
                  style: type.mono.copyWith(color: context.tokens.textMuted),
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlaylistEntryRow extends StatelessWidget {
  const PlaylistEntryRow({
    super.key,
    required this.number,
    required this.numberWidth,
    required this.entry,
    required this.ticked,
    required this.onTap,
  });

  final int number;
  final double numberWidth;
  final PlaylistEntry entry;
  final bool ticked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final type = context.type;
    final thumbnail = entry.thumbnail;
    final duration = formatDuration(entry.durationSec);
    final muted = type.monoSmall.copyWith(color: tokens.textMuted);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.divider)),
      ),
      child: Semantics(
        container: true,
        excludeSemantics: true,
        checked: ticked,
        label: [entry.title, if (duration.isNotEmpty) duration].join(', '),
        onTap: onTap,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: AppSizes.rowPlaylist.h),
            child: Row(
              spacing: Gap.md.w,
              children: [
                _CheckMark(checked: ticked),
                SizedBox(
                  width: numberWidth.w,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text('$number', style: muted),
                  ),
                ),
                MediaThumb(
                  image: networkThumb(thumbnail),
                  width: DownloadThumb.width.w,
                  height: DownloadThumb.height.h,
                  radius: Radii.thumbSmall,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Opacity(
                        opacity: ticked ? 1 : _untickedOpacity,
                        child: Text(
                          entry.title,
                          style: type.body.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (duration.isNotEmpty) Text(duration, style: muted),
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

class PlaylistBottomBar extends StatelessWidget {
  const PlaylistBottomBar({
    super.key,
    required this.gutter,
    required this.caption,
    required this.label,
    required this.onPressed,
  });

  final double gutter;
  final String caption;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.navBar,
        border: Border(top: BorderSide(color: tokens.divider)),
      ),
      child: SafeArea(
        top: false,
        child: CenteredContent(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              gutter,
              _barTop.h,
              gutter,
              _barBottom.h,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: _barGap.h,
              children: [
                Text(
                  caption,
                  style: context.type.caption.copyWith(color: tokens.textMuted),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  // The save path reads left to right in any locale.
                  textDirection: TextDirection.ltr,
                ),
                AppButton(
                  label: label,
                  icon: Assets.icons.download,
                  onPressed: onPressed,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
