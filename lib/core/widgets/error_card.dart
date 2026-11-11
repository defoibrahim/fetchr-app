import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../gen/assets.gen.dart';
import '../theme/app_spacing.dart';
import '../theme/theme_extensions.dart';
import '../utils/scale.dart';
import 'app_button.dart';
import 'error_icon_tile.dart';

const _fullPadding = 18.0;
const _compactPadding = 14.0;
const _bodyHeight = 1.45;
const _actionsGap = 14.0;
const _metaGap = 3.0;
const _compactTextMin = 64.0;
const _appear = Duration(milliseconds: 200);

class ErrorCardAction {
  const ErrorCardAction({
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.busy = false,
    this.busyLabel,
  });

  final String label;
  final VoidCallback onPressed;
  final bool primary;

  /// Shows a spinner (and `busyLabel`) and ignores taps.
  final bool busy;
  final String? busyLabel;
}

class ErrorCardData {
  const ErrorCardData({
    required this.icon,
    required this.title,
    required this.body,
    this.actions = const [],
  });

  final SvgGenImage icon;
  final String title;

  /// Plain spans take the card's body style; wrap a figure in
  /// `AppTextStyles.monoSpan` to set it in the mono family.
  final List<InlineSpan> body;
  final List<ErrorCardAction> actions;
}

enum ErrorCardLayout {
  /// The Home card: title, body, then the actions.
  full,

  /// A Downloads row: the title is the media title, the body its failure
  /// reason, and the actions trail.
  compact,
}

class ErrorCard extends StatelessWidget {
  const ErrorCard({
    super.key,
    required this.data,
    this.layout = ErrorCardLayout.full,
  });

  final ErrorCardData data;
  final ErrorCardLayout layout;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final full = layout == ErrorCardLayout.full;
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.errorSurface,
        border: Border.all(color: tokens.errorBorder),
        borderRadius: BorderRadius.circular(Radii.card.r),
      ),
      child: Padding(
        padding: EdgeInsets.all((full ? _fullPadding : _compactPadding).r),
        child: full ? _full(context) : _compact(context),
      ),
    );
    return Semantics(
      liveRegion: true,
      container: true,
      // A compact row lives in a lazy list: replaying the entrance on every
      // scroll-in would make the list flicker.
      child: full ? _Appear(child: card) : card,
    );
  }

  AppButton _button(
    ErrorCardAction action,
    AppButtonSize size, {
    required bool expanded,
  }) => AppButton(
    label: action.label,
    onPressed: action.onPressed,
    variant: action.primary
        ? AppButtonVariant.filled
        : AppButtonVariant.outlined,
    size: size,
    expanded: expanded,
    isLoading: action.busy,
    loadingLabel: action.busyLabel,
  );

  Widget _full(BuildContext context) {
    final tokens = context.tokens;
    final type = context.type;
    final narrow = context.isNarrow;
    final buttons = [
      for (final action in data.actions)
        _button(action, AppButtonSize.compact, expanded: true),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: _actionsGap.h,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Gap.md.w,
          children: [
            ErrorIconTile(icon: data.icon),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Gap.xs.h,
                children: [
                  Text(data.title, style: type.cardTitle),
                  Text.rich(
                    TextSpan(children: data.body),
                    style: type.body.copyWith(
                      color: tokens.errorBody,
                      height: _bodyHeight,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (buttons.isNotEmpty)
          Flex(
            direction: narrow ? Axis.vertical : Axis.horizontal,
            // Stretching a Row needs a bounded height, which a list row lacks.
            crossAxisAlignment: narrow
                ? CrossAxisAlignment.stretch
                : CrossAxisAlignment.center,
            spacing: narrow ? Gap.sm.h : Gap.sm.w,
            children: narrow
                ? buttons
                : [for (final button in buttons) Expanded(child: button)],
          ),
      ],
    );
  }

  Widget _compact(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        _compactRow(context, constraints.maxWidth),
  );

  Widget _compactRow(BuildContext context, double width) {
    final tokens = context.tokens;
    final type = context.type;
    final actions = data.actions.length;
    // The buttons give way before the title does: on a narrow screen with large
    // text a label wraps instead of pushing the icon out of the row.
    final buttonMax = actions == 0
        ? 0.0
        : math.max(
            0.0,
            (width -
                    AppSizes.errorIconTile.r -
                    Gap.md.w -
                    _compactTextMin.w -
                    Gap.sm.w * actions) /
                actions,
          );
    return Row(
      spacing: Gap.sm.w,
      children: [
        Expanded(
          child: Row(
            spacing: Gap.md.w,
            children: [
              ErrorIconTile(icon: data.icon),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  spacing: _metaGap.h,
                  children: [
                    Text(
                      data.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: type.body.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Text.rich(
                      TextSpan(children: data.body),
                      style: type.caption.copyWith(color: tokens.errorText),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        for (final action in data.actions)
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: buttonMax),
            child: _button(action, AppButtonSize.small, expanded: false),
          ),
      ],
    );
  }
}

/// Fades in and grows from nothing, once, when the card first appears.
class _Appear extends StatelessWidget {
  const _Appear({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: _appear,
      curve: Curves.easeOut,
      child: child,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: t,
            child: child,
          ),
        ),
      ),
    );
  }
}
