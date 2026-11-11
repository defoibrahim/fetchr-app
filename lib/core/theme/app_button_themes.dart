import 'package:flutter/material.dart';

import 'app_spacing.dart';
import 'app_text_styles.dart';
import 'app_tokens.dart';

/// The three stock button themes, compact by default: 48 high, radius 16, a
/// 14/600 label. That is what a bare TextButton or FilledButton gets, such as
/// the folder dialog's; a SnackBarAction does not, since the bar applies its
/// own TextButtonTheme.
/// AppButton sets its own height, radius and label style per size. Values are
/// raw design values: ThemeData is cached, so they are not run through `.w` or
/// `.h`.
abstract final class AppButtonThemes {
  /// A disabled button is its normal colours at 40%.
  static const _disabledAlpha = .4;
  static const _pressedAlpha = .12;
  static const _hoveredAlpha = .08;

  static Color _faded(Color color, Set<WidgetState> states) =>
      states.contains(WidgetState.disabled)
      ? color.withValues(alpha: color.a * _disabledAlpha)
      : color;

  /// `color`, at 40% while disabled. Public so a variant that sets its own
  /// colours (AppButton's destructive) keeps the same disabled look.
  static WidgetStateProperty<Color> fading(Color color) =>
      WidgetStateProperty.resolveWith((states) => _faded(color, states));

  static ButtonStyle _base(AppTokens t, AppTextStyles type) => ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(64, AppSizes.buttonMedium)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: Gap.lg),
    ),
    // Padded would grow the hit box past the button and shift its neighbours.
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    elevation: const WidgetStatePropertyAll(0),
    shape: WidgetStatePropertyAll(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.control),
      ),
    ),
    textStyle: WidgetStatePropertyAll(
      type.body.copyWith(fontWeight: FontWeight.w600),
    ),
    overlayColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed) ||
          states.contains(WidgetState.focused)) {
        return t.text.withValues(alpha: _pressedAlpha);
      }
      if (states.contains(WidgetState.hovered)) {
        return t.text.withValues(alpha: _hoveredAlpha);
      }
      return null;
    }),
  );

  static FilledButtonThemeData filled(
    AppTokens t,
    ColorScheme scheme,
    AppTextStyles type,
  ) => FilledButtonThemeData(
    style: _base(t, type).copyWith(
      backgroundColor: fading(scheme.primary),
      foregroundColor: fading(scheme.onPrimary),
    ),
  );

  static OutlinedButtonThemeData outlined(AppTokens t, AppTextStyles type) =>
      OutlinedButtonThemeData(
        style: _base(t, type).copyWith(
          foregroundColor: fading(t.text),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(color: _faded(t.borderStrong, states)),
          ),
        ),
      );

  static TextButtonThemeData text(
    AppTokens t,
    ColorScheme scheme,
    AppTextStyles type,
  ) => TextButtonThemeData(
    style: _base(t, type).copyWith(foregroundColor: fading(scheme.primary)),
  );
}
