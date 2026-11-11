import 'package:flutter/material.dart';

import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/theme_extensions.dart';
import '../../../../../core/utils/scale.dart';
import '../../../../../core/widgets/app_button.dart';
import '../../../../../core/widgets/dashed_border.dart';

const _appear = Duration(milliseconds: 200);
const _slide = 8.0;
const _marginTop = 16.0;
const _padTop = 12.0;
const _padStart = 14.0;
const _padEnd = 12.0;
const _captionGap = 3.0;

/// "Link found on your clipboard" with a Use button. A null [url] hides it:
/// it fades and collapses, and appears with a fade and an 8 dp rise.
class ClipboardSuggestion extends StatefulWidget {
  const ClipboardSuggestion({
    super.key,
    required this.url,
    required this.onUse,
  });

  final String? url;
  final VoidCallback onUse;

  @override
  State<ClipboardSuggestion> createState() => _ClipboardSuggestionState();
}

class _ClipboardSuggestionState extends State<ClipboardSuggestion> {
  // Kept after the URL goes so the card has something to fade out.
  String? _shown;

  @override
  void initState() {
    super.initState();
    _shown = widget.url;
  }

  @override
  void didUpdateWidget(ClipboardSuggestion oldWidget) {
    super.didUpdateWidget(oldWidget);
    _shown = widget.url ?? _shown;
  }

  @override
  Widget build(BuildContext context) {
    final url = _shown;
    if (url == null) return const SizedBox.shrink();
    return TweenAnimationBuilder<double>(
      // Begins at 0 so a card that is just built still rises and fades in.
      tween: Tween<double>(begin: 0, end: widget.url == null ? 0 : 1),
      duration: context.motion(_appear),
      curve: Curves.easeOut,
      builder: (context, t, child) {
        if (t == 0 && widget.url == null) return const SizedBox.shrink();
        return Opacity(
          opacity: t,
          child: ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: t,
              child: Transform.translate(
                offset: Offset(0, (1 - t) * _slide.h),
                child: child,
              ),
            ),
          ),
        );
      },
      child: Padding(
        padding: EdgeInsets.only(top: _marginTop.h),
        child: _Card(url: url, onUse: widget.onUse),
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
