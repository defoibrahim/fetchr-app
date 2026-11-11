import 'package:flutter/material.dart';

import '../../../../../core/gen/assets.gen.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/theme.dart';
import '../../../../../core/utils/scale.dart';
import '../../../../../core/widgets/app_icon.dart';

const _pad = 14.0;
const _iconTile = 40.0;
const _icon = 20.0;
const _chevron = 18.0;

/// Home's second way in, beside the link: any video on the phone, picked
/// with the system picker, becomes an MP3.
class ConvertVideoTile extends StatelessWidget {
  const ConvertVideoTile({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final type = context.type;
    return Semantics(
      button: true,
      child: Material(
        color: tokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.row.r),
          side: BorderSide(color: tokens.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(_pad.r),
            child: Row(
              spacing: Gap.md.w,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.accentTint,
                    borderRadius: BorderRadius.circular(Radii.thumbSmall.r),
                  ),
                  child: SizedBox.square(
                    dimension: _iconTile.r,
                    child: Center(
                      child: AppIcon(
                        Assets.icons.music,
                        size: _icon.r,
                        color: context.colors.primary,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Convert a video to MP3',
                        style: type.bodyStrong.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Pick any video on your phone',
                        style: type.caption.copyWith(color: tokens.textMuted),
                      ),
                    ],
                  ),
                ),
                AppIcon(
                  Assets.icons.chevronRight,
                  size: _chevron.r,
                  color: tokens.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
