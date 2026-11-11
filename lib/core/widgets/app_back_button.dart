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
