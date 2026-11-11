import 'package:flutter/material.dart';

import '../gen/assets.gen.dart';
import '../theme/app_spacing.dart';
import '../theme/theme_extensions.dart';
import '../utils/scale.dart';
import 'app_icon.dart';

/// The `error` glyph on an `errorIconBg` tile. The defaults are the ErrorCard
/// tile; the confirm dialog passes its bigger one. Sizes are design values,
/// scaled at build time.
class ErrorIconTile extends StatelessWidget {
  const ErrorIconTile({
    super.key,
    required this.icon,
    this.size = AppSizes.errorIconTile,
    this.radius = Radii.button,
    this.iconSize = AppSizes.iconStatus,
  });

  final SvgGenImage icon;
  final double size;
  final double radius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: size.r,
      height: size.r,
      decoration: BoxDecoration(
        color: tokens.errorIconBg,
        borderRadius: BorderRadius.circular(radius.r),
      ),
      alignment: Alignment.center,
      child: AppIcon(icon, size: iconSize.r, color: tokens.error),
    );
  }
}
