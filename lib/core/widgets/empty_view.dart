import 'package:flutter/material.dart';

import '../gen/assets.gen.dart';
import '../theme/app_spacing.dart';
import '../theme/theme_extensions.dart';
import '../utils/scale.dart';
import 'app_icon.dart';

const _illustrationSize = 64.0;
const _illustrationGap = 14.0;
const _titleGap = 6.0;
const _maxTextWidth = 300.0;
const _sideInset = 40.0;

class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    this.illustration,
    this.title,
    required this.message,
    this.action,
  });

  final SvgGenImage? illustration;
  final String? title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final type = context.type;
    final art = illustration;
    final heading = title;
    final cta = action;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: _sideInset.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (art != null) ...[
              AppIcon(
                art,
                size: _illustrationSize.r,
                color: tokens.borderStrong,
              ),
              SizedBox(height: _illustrationGap.h),
            ],
            if (heading != null) ...[
              Text(heading, textAlign: TextAlign.center, style: type.cardTitle),
              SizedBox(height: _titleGap.h),
            ],
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: _maxTextWidth.w),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: type.bodyRelaxed.copyWith(color: tokens.textMuted),
              ),
            ),
            if (cta != null) ...[SizedBox(height: Gap.lg.h), cta],
          ],
        ),
      ),
    );
  }
}
