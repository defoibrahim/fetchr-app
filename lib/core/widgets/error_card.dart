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
    this.onTap,
    this.tapHint,
  });

  final ErrorCardData data;
  final ErrorCardLayout layout;

  /// Makes the whole card a tap target with a ripple; its buttons still take
  /// their own taps.
  final VoidCallback? onTap;

  /// What a tap does, for a screen reader ("Show error details").
  final String? tapHint;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final full = layout == ErrorCardLayout.full;
    final body = Padding(
      padding: EdgeInsets.all((full ? _fullPadding : _compactPadding).r),
      child: full ? _full(context) : _compact(context),
    );
    final radius = BorderRadius.circular(Radii.card.r);
    final tap = onTap;
    // A Material, not a DecoratedBox, so the ripple paints on the card's fill
    // instead of under it.
    final card = Material(
      color: tokens.errorSurface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: tokens.errorBorder),
        borderRadius: radius,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: tap, child: body),
    );
    return Semantics(
      liveRegion: true,
      container: true,
      onTapHint: tap == null ? null : tapHint,
      child: card,
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
