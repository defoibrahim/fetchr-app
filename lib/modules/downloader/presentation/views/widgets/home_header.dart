import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/shared/domain/entities/yt_dlp_status.dart';
import '../../../../../app/shared/formatters/yt_dlp_formatter.dart';
import '../../../../../app/shared/launch_logo_target.dart';
import '../../../../../app/shared/yt_dlp_provider.dart';
import '../../../../../core/config/environment.dart';
import '../../../../../core/gen/assets.gen.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/theme_extensions.dart';
import '../../../../../core/utils/scale.dart';
import '../../../../../core/widgets/app_icon.dart';

const _logoGap = 10.0;
const _chipPadX = 10.0;
const _chipPadY = 5.0;
const _wordmarkShare = 0.5;

/// The logo tile and wordmark, and the yt-dlp version on the right.
class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // No chip while the status loads, after it failed, or while an update
    // runs after a failed read: there is no version to show.
    final status = ref.watch(
      ytDlpProvider.select((state) => state.value?.status),
    );
    return LayoutBuilder(
      builder: (_, constraints) => Row(
        children: [
          const _LogoTile(),
          SizedBox(width: _logoGap.w),
          // A cap, not a Flexible: next to the chip's Expanded a Flexible
          // would split the free width in half and cut a version that fits.
          // The name keeps what it needs up to the cap, so a longer
          // Environment.appName ellipsises instead of overflowing the row.
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: constraints.maxWidth * _wordmarkShare,
            ),
            child: Text(
              Environment.current.appName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.type.wordmark,
            ),
          ),
          // The chip takes what is left.
          if (status != null)
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: _VersionChip(status: status),
              ),
            ),
        ],
      ),
    );
  }
}

class _LogoTile extends StatelessWidget {
  const _LogoTile();

  @override
  Widget build(BuildContext context) {
    // The primary fill and its glyph: the accent on dark, the ink with an
    // accent glyph on light.
    return Container(
      key: LaunchLogoTarget.keyOf(context),
      width: AppSizes.logoTile.r,
      height: AppSizes.logoTile.r,
      decoration: BoxDecoration(
        color: context.colors.primary,
        borderRadius: BorderRadius.circular(Radii.logo.r),
      ),
      alignment: Alignment.center,
      child: AppIcon(
        Assets.icons.logo,
        size: AppSizes.logoGlyph.r,
        color: context.tokens.primaryIcon,
      ),
    );
  }
}

class _VersionChip extends StatelessWidget {
  const _VersionChip({required this.status});

  final YtDlpStatus status;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: context.tokens.border),
        borderRadius: BorderRadius.circular(Radii.pill.r),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: _chipPadX.w,
          vertical: _chipPadY.h,
        ),
        child: Text(
          status.versionLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.type.monoSmall.copyWith(
            color: context.tokens.textMuted,
          ),
        ),
      ),
    );
  }
}
