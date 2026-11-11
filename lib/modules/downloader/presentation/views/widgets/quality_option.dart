import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../../../app/shared/domain/entities/quality.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/theme.dart';
import '../../../../../core/utils/scale.dart';
import '../../../domain/entities/format_option.dart';
import '../../formatters/format_option_formatter.dart';
import '../../formatters/quality_formatter.dart';

const _radioSize = 18.0;
const _borderWidth = 1.5;
const _padX = 14.0;
const _padY = 4.0;
const _fade = Duration(milliseconds: 150);

/// One quality row of the format sheet. The whole row is the tap target, so
/// the radio only draws the state.
class QualityOption extends StatelessWidget {
  const QualityOption({
    super.key,
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final FormatOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final type = context.type;
    final scheme = context.colors;
    final label = option.quality.optionLabel;
    final detail = option.detail;
    final size = option.sizeText;
    final shape = BorderRadius.circular(Radii.row.r);

    return Semantics(
      container: true,
      excludeSemantics: true,
      checked: selected,
      inMutuallyExclusiveGroup: true,
      label: '$label, $detail, $size',
      onTap: onTap,
      child: Material(
        // Clear in the tint's own hue, so the fade does not pass through a
        // dark mix.
        color: selected
            ? tokens.accentTint
            : tokens.accentTint.withValues(alpha: 0),
        shape: RoundedRectangleBorder(
          borderRadius: shape,
          side: BorderSide(
            color: selected ? scheme.primary : tokens.border,
            width: _borderWidth,
          ),
        ),
        animationDuration: context.motion(_fade),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: AppSizes.rowOption.h),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: _padX.w,
                vertical: _padY.h,
              ),
              child: Row(
                spacing: Gap.md.w,
                children: [
                  _RadioMark(quality: option.quality, selected: selected),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: type.bodyStrong.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          detail,
                          style: type.caption.copyWith(color: tokens.textMuted),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    size,
                    textDirection: TextDirection.ltr,
                    style: type.mono.copyWith(color: tokens.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A radio that only shows the state; the radio theme owns its colours.
class _RadioMark extends StatelessWidget {
  const _RadioMark({required this.quality, required this.selected});

  final Quality quality;
  final bool selected;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    // A bone in the format sheet's skeleton; the radio is a painter.
    child: Skeleton.replace(
      replacement: Bone.circle(size: _radioSize.r),
      child: SizedBox.square(
        dimension: _radioSize.r,
        child: RadioGroup<Quality>(
          groupValue: selected ? quality : null,
          onChanged: (_) {},
          child: Radio<Quality>(value: quality, enabled: false),
        ),
      ),
    ),
  );
}
