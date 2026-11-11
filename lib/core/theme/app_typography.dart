import 'package:flutter/material.dart';

import '../gen/fonts.gen.dart';
import 'app_text_styles.dart';

/// The M3 slots, all in Geist, so a stock widget (ListTile, Chip, Tooltip)
/// matches the spec's UI text. Sizes are not run through `.sp`: ThemeData is
/// cached, so a scaled value would go stale on rotation. Use AppText for
/// scaled text.
abstract final class AppTypography {
  static TextTheme textTheme(ColorScheme scheme) {
    TextStyle style(
      double size,
      double lineHeight, {
      FontWeight weight = FontWeight.w400,
      double spacing = 0,
    }) => AppTextStyles.style(
      FontFamily.geist,
      size,
      lineHeight,
      scheme.onSurface,
      weight: weight,
      spacing: spacing,
    );

    return TextTheme(
      displayLarge: style(57, 64, spacing: -0.25),
      displayMedium: style(45, 52),
      displaySmall: style(36, 44),
      headlineLarge: style(32, 40),
      headlineMedium: style(28, 36),
      headlineSmall: style(24, 32),
      titleLarge: style(22, 28),
      titleMedium: style(16, 24, weight: FontWeight.w500, spacing: 0.15),
      titleSmall: style(14, 20, weight: FontWeight.w500, spacing: 0.1),
      bodyLarge: style(16, 24, spacing: 0.5),
      bodyMedium: style(14, 20, spacing: 0.25),
      bodySmall: style(12, 16, spacing: 0.4),
      labelLarge: style(14, 20, weight: FontWeight.w500, spacing: 0.1),
      labelMedium: style(12, 16, weight: FontWeight.w500, spacing: 0.5),
      labelSmall: style(11, 16, weight: FontWeight.w500, spacing: 0.5),
    );
  }
}
