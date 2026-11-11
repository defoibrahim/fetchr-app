import 'package:flutter/material.dart';

import '../gen/assets.gen.dart';
import '../theme/app_button_themes.dart';
import '../theme/app_spacing.dart';
import '../theme/theme_extensions.dart';
import '../utils/scale.dart';
import 'app_icon.dart';

enum AppButtonVariant { filled, outlined, text, destructive }

enum AppButtonSize { large, medium, compact, small }

/// Height and radius are design values, scaled at build time.
({double height, double radius}) _box(AppButtonSize size) => switch (size) {
  AppButtonSize.large => (height: AppSizes.buttonLarge, radius: Radii.control),
  AppButtonSize.medium => (height: AppSizes.buttonMedium, radius: Radii.row),
  AppButtonSize.compact => (
    height: AppSizes.buttonCompact,
    radius: Radii.button,
  ),
  AppButtonSize.small => (height: AppSizes.buttonSmall, radius: Radii.button),
};

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.filled,
    this.size = AppButtonSize.large,
    this.isLoading = false,
    this.loadingLabel,
    this.icon,
    this.iconAfter = false,
    this.expanded = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final bool isLoading;

  /// Shown next to the spinner while loading; without it the spinner replaces
  /// the label and the button keeps the label's width.
  final String? loadingLabel;
  final SvgGenImage? icon;
  final bool iconAfter;
  final bool expanded;

  static void _swallowTap() {}

  @override
  Widget build(BuildContext context) {
    final box = _box(size);
    // Loading swallows taps instead of passing null, which would grey the
    // button out and make the spinner flash.
    final enabled = onPressed != null;
    final handler = !enabled
        ? null
        : isLoading
        ? _swallowTap
        : onPressed;

    final style = _style(context, height: box.height.h, radius: box.radius.r);
    final content = _content();
    final button = switch (variant) {
      AppButtonVariant.filled || AppButtonVariant.destructive => FilledButton(
        onPressed: handler,
        style: style,
        child: content,
      ),
      AppButtonVariant.outlined => OutlinedButton(
        onPressed: handler,
        style: style,
        child: content,
      ),
      AppButtonVariant.text => TextButton(
        onPressed: handler,
        style: style,
        child: content,
      ),
    };
    return expanded ? SizedBox(width: double.infinity, child: button) : button;
  }

  /// The button themes own colour, border, ink and the disabled look. This is
  /// only what varies per size, plus the destructive colours.
  ButtonStyle _style(
    BuildContext context, {
    required double height,
    required double radius,
  }) {
    final tokens = context.tokens;
    final type = context.type;
    final destructive = variant == AppButtonVariant.destructive;
    final solid = destructive || variant == AppButtonVariant.filled;
    final textStyle = switch (size) {
      AppButtonSize.large => type.button,
      AppButtonSize.medium => type.bodyStrong,
      AppButtonSize.compact || AppButtonSize.small => type.body,
    };
    final weight = switch (size) {
      AppButtonSize.large => FontWeight.w600,
      AppButtonSize.medium ||
      AppButtonSize.compact => solid ? FontWeight.w600 : FontWeight.w500,
      AppButtonSize.small => FontWeight.w500,
    };
    return ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(0, height)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
      textStyle: WidgetStatePropertyAll(textStyle.copyWith(fontWeight: weight)),
      backgroundColor: destructive
          ? AppButtonThemes.fading(tokens.error)
          : null,
      foregroundColor: destructive
          ? AppButtonThemes.fading(tokens.onError)
          : null,
      // Every other icon follows the foreground; the filled one is the accent
      // on ink in light.
      iconColor: variant == AppButtonVariant.filled
          ? AppButtonThemes.fading(tokens.primaryIcon)
          : null,
    );
  }

  Widget _content() {
    final glyph = icon;
    final glyphWidget = glyph == null
        ? null
        : AppIcon(glyph, size: AppSizes.iconButton.r);
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: Gap.sm.w,
      children: [
        if (!iconAfter) ?glyphWidget,
        Flexible(child: Text(label, textAlign: TextAlign.center)),
        if (iconAfter) ?glyphWidget,
      ],
    );
    if (!isLoading) return row;

    const spinner = _Spinner();
    final loading = loadingLabel;
    if (loading != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: Gap.sm.w,
        children: [
          spinner,
          Flexible(child: Text(loading, textAlign: TextAlign.center)),
        ],
      );
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        Visibility.maintain(visible: false, child: row),
        spinner,
      ],
    );
  }
}

/// In the button's label colour, which is already faded when it is disabled.
class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: AppSizes.iconButton.r,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        color: DefaultTextStyle.of(context).style.color,
      ),
    );
  }
}
