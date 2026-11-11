import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../gen/assets.gen.dart';
import '../theme/app_spacing.dart';
import '../theme/theme_extensions.dart';
import '../utils/scale.dart';
import 'app_icon.dart';

/// A 44 dp square icon button with a tooltip, which a screen reader speaks as
/// its label. Plain, the icon is `textMuted`; [bordered] draws a `border`
/// outline and sets the icon in `text`, for a button that sits next to content
/// of its own.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.bordered = false,
  });

  final SvgGenImage icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        foregroundColor: bordered ? tokens.text : tokens.textMuted,
        // Scaled up on a big screen, never down below the touch target.
        fixedSize: Size.square(math.max(AppSizes.touch, AppSizes.touch.r)),
        padding: EdgeInsets.zero,
        // The box is already the touch target.
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.button.r),
          side: bordered ? BorderSide(color: tokens.border) : BorderSide.none,
        ),
      ),
      icon: AppIcon(icon, size: AppSizes.iconButton.r),
    );
  }
}
