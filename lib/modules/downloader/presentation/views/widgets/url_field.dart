import 'package:flutter/material.dart';

import '../../../../../core/gen/assets.gen.dart';
import '../../../../../core/theme/app_spacing.dart';
import '../../../../../core/theme/theme_extensions.dart';
import '../../../../../core/utils/scale.dart';
import '../../../../../core/widgets/app_icon.dart';
import '../../../../../core/widgets/app_icon_button.dart';

enum UrlFieldState { empty, filled, focused, error }

const _borderWidth = 1.0;
const _errorBorderWidth = 1.5;
const _linkIconSize = 20.0;
const _pasteIconSize = 16.0;
const _pasteIconGap = 6.0;
const _pastePadding = 14.0;
const _pad = 4.0;
const _leadingPad = 14.0;

/// The link input: 56 high, the link icon, the URL as one scrolling mono line,
/// and Paste while it is empty or a clear button once it is not. The border
/// follows [UrlFieldState]; pass [state] to pin it (the gallery does), or leave
/// it null to derive it from the controller, the focus and [hasError].
class UrlField extends StatelessWidget {
  const UrlField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onPaste,
    required this.onClear,
    this.hasError = false,
    this.state,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onPaste;
  final VoidCallback onClear;
  final bool hasError;
  final UrlFieldState? state;

  @override
  Widget build(BuildContext context) {
    // A URL reads left to right whatever the app's direction is.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ListenableBuilder(
        listenable: Listenable.merge([controller, focusNode]),
        builder: (context, _) {
          final filled = controller.text.isNotEmpty;
          final shown = state ?? _derive(filled);
          return DecoratedBox(
            decoration: BoxDecoration(
              color: context.tokens.surface,
              border: _border(context, shown),
              borderRadius: BorderRadius.circular(Radii.control.r),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: AppSizes.input.h),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  _leadingPad.w,
                  _pad.h,
                  _pad.w,
                  _pad.h,
                ),
                child: Row(
                  spacing: Gap.sm.w,
                  children: [
                    AppIcon(
                      Assets.icons.link,
                      size: _linkIconSize.r,
                      color: context.tokens.textMuted,
                    ),
                    Expanded(child: _input(context)),
                    filled
                        ? AppIconButton(
                            icon: Assets.icons.close,
                            tooltip: 'Clear URL',
                            onPressed: onClear,
                          )
                        : _pasteButton(context),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  UrlFieldState _derive(bool filled) {
    if (hasError) return UrlFieldState.error;
    if (focusNode.hasFocus) return UrlFieldState.focused;
    return filled ? UrlFieldState.filled : UrlFieldState.empty;
  }

  Border _border(BuildContext context, UrlFieldState shown) => switch (shown) {
    UrlFieldState.error => Border.all(
      color: context.tokens.error,
      width: _errorBorderWidth,
    ),
    UrlFieldState.focused => Border.all(
      color: context.colors.primary,
      width: _borderWidth,
    ),
    _ => Border.all(color: context.tokens.border, width: _borderWidth),
  };

  Widget _input(BuildContext context) {
    final style = context.type.monoInput;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: TextInputType.url,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      style: style,
      decoration: InputDecoration(
        hintText: 'https://…',
        hintStyle: style.copyWith(color: context.tokens.placeholder),
        // The theme's filled, bordered field is the box around this one.
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        isCollapsed: true,
      ),
    );
  }

  Widget _pasteButton(BuildContext context) {
    final tokens = context.tokens;
    return TextButton(
      onPressed: onPaste,
      style: TextButton.styleFrom(
        backgroundColor: tokens.surfaceSunken,
        foregroundColor: tokens.text,
        minimumSize: Size(0, AppSizes.touch.h),
        padding: EdgeInsets.symmetric(horizontal: _pastePadding.w),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.button.r),
        ),
        textStyle: context.type.body.copyWith(fontWeight: FontWeight.w500),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: _pasteIconGap.w,
        children: [
          AppIcon(Assets.icons.clipboard, size: _pasteIconSize.r),
          const Text('Paste'),
        ],
      ),
    );
  }
}
