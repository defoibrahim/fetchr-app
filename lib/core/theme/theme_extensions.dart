import 'package:flutter/material.dart';

import '../utils/scale.dart';
import 'app_spacing.dart';
import 'app_text_styles.dart';
import 'app_tokens.dart';

extension ThemeContextX on BuildContext {
  AppTokens get tokens => AppTokens.of(this);
  AppTextStyles get type =>
      Theme.of(this).extension<AppTextStyles>() ??
      AppTextStyles.from(tokens.text);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get text => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  bool get isNarrow => MediaQuery.sizeOf(this).width < Breakpoints.narrow;
  bool get reduceMotion => MediaQuery.disableAnimationsOf(this);

  /// By the window's width, not the width a parent leaves: beside the rail a
  /// 900 dp window has about 820 dp, which is still `expanded`.
  WindowClass get windowClass => WindowClass.of(MediaQuery.sizeOf(this).width);

  /// The page's side padding: 20, or 16 under [Breakpoints.narrow].
  double get gutter => (isNarrow ? Gap.gutterNarrow : Gap.gutter).w;

  /// `d`, or zero when the user asked for less motion.
  Duration motion(Duration d) => reduceMotion ? Duration.zero : d;
}
