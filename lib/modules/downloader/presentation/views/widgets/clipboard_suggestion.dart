import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/theme_extensions.dart';
import '../../../../../core/utils/scale.dart';
import '../../../../../core/widgets/app_button.dart';
import '../../../../../core/widgets/app_reveal.dart';
import '../../../../../core/widgets/dashed_border.dart';

const _marginTop = 16.0;
const _padTop = 12.0;
const _padStart = 14.0;
const _padEnd = 12.0;
const _captionGap = 3.0;

/// "Link found on your clipboard" with a Use button. A null [url] hides it:
/// it fades and collapses, and appears with a fade and an 8 dp rise.
class ClipboardSuggestion extends StatelessWidget {
  const ClipboardSuggestion({
    super.key,
    required this.url,
    required this.onUse,
  });

  final String? url;
  final VoidCallback onUse;

  // AppReveal keeps the last card while it leaves, so a hidden one needs no
  // URL of its own.
  @override
  Widget build(BuildContext context) {
    final url = this.url;
    return AppReveal(
      child: url == null
          ? null
          : Padding(
              padding: EdgeInsets.only(top: _marginTop.h),
              child: _Card(url: url, onUse: onUse),
            ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.url, required this.onUse});

  final String url;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final type = context.type;
    return DashedBorder(
      radius: Radii.row.r,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          _padStart.w,
          _padTop.h,
          _padEnd.w,
          _padTop.h,
        ),
        child: Row(
          spacing: Gap.md.w,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: _captionGap.h,
                children: [
                  Text(
                    'Link found on your clipboard',
                    style: type.caption.copyWith(color: tokens.textMuted),
                  ),
                  Text(
                    url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.ltr,
                    style: type.mono,
                  ),
                ],
              ),
            ),
            AppButton(
              label: 'Use',
              onPressed: onUse,
              variant: AppButtonVariant.outlined,
              size: AppButtonSize.small,
              expanded: false,
            ),
          ],
        ),
      ),
    );
  }
}
