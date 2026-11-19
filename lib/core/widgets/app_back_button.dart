import 'package:flutter/material.dart';

import '../gen/assets.gen.dart';
import '../theme/app_spacing.dart';
import '../theme/theme_extensions.dart';
import '../utils/scale.dart';
import 'app_icon.dart';

class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: AppIcon(
        Assets.icons.arrowLeft,
        size: AppSizes.iconBack.r,
        color: context.tokens.text,
      ),
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: onTap ?? () => Navigator.maybePop(context),
    );
  }
}

/// The back arrow and the name of where it leads, at the top of a screen
/// with no app bar.
class AppBackHeader extends StatelessWidget {
  const AppBackHeader(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(Gap.sm.w, Gap.sm.h, context.gutter, Gap.xs.h),
    child: Row(
      spacing: Gap.xs.w,
      children: [
        const AppBackButton(),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.type.button,
          ),
        ),
      ],
    ),
  );
}
