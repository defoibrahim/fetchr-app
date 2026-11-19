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

  // A filled button's fill is the ink in light, so ink at 12% on it would not
  // show; its own label colour does.
  static const _filledPressedAlpha = .16;
  static const _filledHoveredAlpha = .10;

  static Color _faded(Color color, Set<WidgetState> states) =>
      states.contains(WidgetState.disabled)
      ? color.withValues(alpha: color.a * _disabledAlpha)
      : color;

  /// `color`, at 40% while disabled. Public so a variant that sets its own
  /// colours (AppButton's destructive) keeps the same disabled look.
  static WidgetStateProperty<Color> fading(Color color) =>
      WidgetStateProperty.resolveWith((states) => _faded(color, states));

  /// The pressed and focused overlay, and a lighter one on hover: [ink] at
  /// [pressed] and [hovered] alpha.
  static WidgetStateProperty<Color?> overlay(
    Color ink, {
    double pressed = _pressedAlpha,
    double hovered = _hoveredAlpha,
  }) => WidgetStateProperty.resolveWith((states) {
    if (states.contains(WidgetState.pressed) ||
        states.contains(WidgetState.focused)) {
      return ink.withValues(alpha: pressed);
    }
    if (states.contains(WidgetState.hovered)) {
      return ink.withValues(alpha: hovered);
    }
    return null;
  });

  /// [overlay] for a button filled with a solid colour, in its label's
  /// colour [onFill].
  static WidgetStateProperty<Color?> filledOverlay(Color onFill) => overlay(
    onFill,
    pressed: _filledPressedAlpha,
    hovered: _filledHoveredAlpha,
  );

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
    overlayColor: overlay(t.text),
  );

  static FilledButtonThemeData filled(
    AppTokens t,
    ColorScheme scheme,
    AppTextStyles type,
  ) => FilledButtonThemeData(
    style: _base(t, type).copyWith(
      backgroundColor: fading(scheme.primary),
      foregroundColor: fading(scheme.onPrimary),
      overlayColor: filledOverlay(scheme.onPrimary),
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
