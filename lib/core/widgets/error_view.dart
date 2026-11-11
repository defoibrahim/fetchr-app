import 'package:flutter/material.dart';

import '../gen/assets.gen.dart';
import '../theme/theme_extensions.dart';
import '../utils/scale.dart';
import 'app_button.dart';
import 'app_text.dart';

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.r),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 48.r, color: tokens.error),
            SizedBox(height: 12.h),
            AppText(
              message,
              align: TextAlign.center,
              color: tokens.textMuted,
              maxLines: 4,
            ),
            if (onRetry != null) ...[
              SizedBox(height: 16.h),
              AppButton(
                label: 'Retry',
                icon: Assets.icons.refresh,
                expanded: false,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
