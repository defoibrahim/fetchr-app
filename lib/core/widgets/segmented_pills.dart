import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/theme_extensions.dart';
import '../utils/scale.dart';

/// A row of equal pills in a padded track, one selected. `height` is the
/// pill's: the track adds its padding around it. A track on a card keeps the
/// default `bg` fill; pass `trackColor` (the surface) for one on the page,
/// which also gets the hairline border.
class SegmentedPills<T> extends StatelessWidget {
  const SegmentedPills({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
    this.height = 40,
    this.trackRadius = Radii.button,
    this.pillRadius = Radii.pillInner,
    this.mono = false,
    this.trackColor,
    this.semanticLabel,
  });

  static const _fade = Duration(milliseconds: 150);

  final List<(T, String)> items;
  final T selected;
  final ValueChanged<T> onChanged;
  final double height;
  final double trackRadius;
  final double pillRadius;
  final bool mono;
  final Color? trackColor;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final type = context.type;
    final fade = context.motion(_fade);
    final label =
        (mono ? (context.isNarrow ? type.monoSmall : type.mono) : type.body)
            .copyWith(fontWeight: FontWeight.w500);

    return Semantics(
      container: true,
      role: SemanticsRole.radioGroup,
      label: semanticLabel,
      // A Container, not a DecoratedBox: it adds the border to its padding,
      // as the spec's box does.
      child: Container(
        padding: EdgeInsets.all(Gap.xs.r),
        decoration: BoxDecoration(
          color: trackColor ?? tokens.bg,
          borderRadius: BorderRadius.circular(trackRadius.r),
          border: trackColor == null ? null : Border.all(color: tokens.border),
        ),
        child: Row(
          spacing: Gap.xs.w,
          children: [
            for (final (value, text) in items)
              Expanded(
                child: _Pill(
                  label: text,
                  textStyle: label,
                  selected: value == selected,
                  height: height.h,
                  radius: pillRadius.r,
                  fade: fade,
                  onTap: () => onChanged(value),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.textStyle,
    required this.selected,
    required this.height,
    required this.radius,
    required this.fade,
    required this.onTap,
  });

  final String label;
  final TextStyle textStyle;
  final bool selected;
  final double height;
  final double radius;
  final Duration fade;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colors;
    final shape = BorderRadius.circular(radius);
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      checked: selected,
      inMutuallyExclusiveGroup: true,
      label: label,
      onTap: onTap,
      child: Material(
        // Clear in the primary's own hue, so the fade does not pass through
        // a dark mix.
        color: selected ? scheme.primary : scheme.primary.withValues(alpha: 0),
        borderRadius: shape,
        animationDuration: fade,
        child: InkWell(
          borderRadius: shape,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            // heightFactor: a bare Center would take the track's whole height.
            child: Center(
              heightFactor: 1,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: Gap.xs.w),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: AnimatedDefaultTextStyle(
                    duration: fade,
                    style: textStyle.copyWith(
                      color: selected
                          ? scheme.onPrimary
                          : context.tokens.textMuted,
                    ),
                    child: Text(label, maxLines: 1, softWrap: false),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
