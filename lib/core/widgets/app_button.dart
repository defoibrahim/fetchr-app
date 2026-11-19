import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../gen/assets.gen.dart';
import '../theme/app_button_themes.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import '../theme/theme_extensions.dart';
import '../utils/scale.dart';
import 'app_fade_switcher.dart';
import 'app_icon.dart';
import 'press_scale.dart';

/// `destructiveOutline` is the error-tinted outline for a strong action that
/// can be undone, such as stopping a playlist.
enum AppButtonVariant {
  filled,
  outlined,
  text,
  destructive,
  destructiveOutline,
}

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
    // Keyed by the kind of content, so the label and the spinner cross-fade
    // and a label change alone does not.
    final content = AppFadeSwitcher(
      spec: Motion.fade,
      alignment: Alignment.center,
      child: KeyedSubtree(key: ValueKey(isLoading), child: _content()),
    );
    Widget button([WidgetStatesController? states]) => switch (variant) {
      AppButtonVariant.filled || AppButtonVariant.destructive => FilledButton(
        onPressed: handler,
        style: style,
        statesController: states,
        child: content,
      ),
      AppButtonVariant.outlined ||
      AppButtonVariant.destructiveOutline => OutlinedButton(
        onPressed: handler,
        style: style,
        statesController: states,
        child: content,
      ),
      AppButtonVariant.text => TextButton(
        onPressed: handler,
        style: style,
        statesController: states,
        child: content,
      ),
    };
    // The small sizes sit in rows of content, where a shrinking button would
    // jostle its neighbours; the ripple is enough there.
    final scaled = switch (size) {
      AppButtonSize.large ||
      AppButtonSize.medium => _PressScale(builder: button),
      AppButtonSize.compact || AppButtonSize.small => button(),
    };
    return expanded ? SizedBox(width: double.infinity, child: scaled) : scaled;
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
      foregroundColor: switch (variant) {
        AppButtonVariant.destructive => AppButtonThemes.fading(tokens.onError),
        AppButtonVariant.destructiveOutline => AppButtonThemes.fading(
          tokens.errorText,
        ),
        _ => null,
      },
      overlayColor: destructive
          ? AppButtonThemes.filledOverlay(tokens.onError)
          : null,
      side: variant == AppButtonVariant.destructiveOutline
          ? WidgetStatePropertyAll(BorderSide(color: tokens.errorBorder))
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

/// Shrinks the button a little while it is held, and not at all under
/// reduce motion. It reads the press from the button's own states, so it
/// follows the same tap the ripple does.
class _PressScale extends StatefulWidget {
  const _PressScale({required this.builder});

  final Widget Function(WidgetStatesController states) builder;

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  final _states = WidgetStatesController();
  var _pressed = false;

  @override
  void initState() {
    super.initState();
    _states.addListener(_onStates);
  }

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  // A button that turns disabled mid-press drops `pressed` while it builds,
  // when this ancestor cannot rebuild; it catches up after the frame.
  void _onStates() {
    final pressed = _states.value.contains(WidgetState.pressed);
    if (pressed == _pressed) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onStates();
      });
      return;
    }
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) =>
      PressScale(pressed: _pressed, child: widget.builder(_states));
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
