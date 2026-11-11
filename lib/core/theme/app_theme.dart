import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_button_themes.dart';
import 'app_palette.dart';
import 'app_spacing.dart';
import 'app_text_styles.dart';
import 'app_tokens.dart';
import 'app_typography.dart';

abstract final class AppTheme {
  // ThemeData is costly to build and App rebuilds on every accent change.
  static final _cache = <(Brightness, int), ThemeData>{};

  // ThemeData is cached, so a component theme holds raw design values; the
  // widgets that own a layout scale theirs through .w, .h and .r.
  static const _chipHeight = 40.0;
  static const _menuPadding = 6.0;
  static const _menuShadow = Color(0x8C000000);
  static const _sliderThumb = 14.0;
  static const _checkboxRadius = 4.0;

  static ThemeData light([Color accent = AppPalette.defaultAccent]) =>
      _themed(Brightness.light, accent);

  static ThemeData dark([Color accent = AppPalette.defaultAccent]) =>
      _themed(Brightness.dark, accent);

  static ThemeData _themed(Brightness brightness, Color accent) =>
      _cache.putIfAbsent((
        brightness,
        accent.toARGB32(),
      ), () => _build(brightness, accent));

  /// Light has no accent text, so its primary is the ink and the accent only
  /// reaches a primary fill as `primaryIcon`.
  static ColorScheme _scheme(AppTokens t, Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final primary = dark ? t.accent : t.text;
    final onPrimary = dark ? t.onAccent : t.bg;
    return ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      secondary: primary,
      onSecondary: onPrimary,
      primaryContainer: t.accentTint,
      onPrimaryContainer: t.text,
      error: t.error,
      onError: t.onError,
      surface: t.bg,
      onSurface: t.text,
      onSurfaceVariant: t.textMuted,
      surfaceContainerLowest: t.bg,
      surfaceContainerLow: t.surface,
      surfaceContainer: t.surface,
      surfaceContainerHigh: t.surfaceRaised,
      surfaceContainerHighest: t.surfaceSunken,
      outline: t.borderStrong,
      outlineVariant: t.border,
      surfaceTint: Colors.transparent,
      scrim: t.scrim,
      inverseSurface: t.text,
      onInverseSurface: t.bg,
    );
  }

  static ThemeData _build(Brightness brightness, Color accent) {
    final tokens = AppTokens.from(AppPalette.of(brightness), accent);
    final scheme = _scheme(tokens, brightness);
    final type = AppTextStyles.from(tokens.text);

    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: tokens.bg,
      textTheme: AppTypography.textTheme(scheme),
      extensions: [tokens, type],
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.bg,
        foregroundColor: tokens.text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: tokens.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.card),
          side: BorderSide(color: tokens.border),
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: tokens.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        hintStyle: TextStyle(color: tokens.placeholder),
        labelStyle: TextStyle(color: tokens.textMuted),
        border: inputBorder(tokens.border),
        enabledBorder: inputBorder(tokens.border),
        focusedBorder: inputBorder(scheme.primary, 2),
        errorBorder: inputBorder(scheme.error),
        focusedErrorBorder: inputBorder(scheme.error, 2),
      ),
      filledButtonTheme: AppButtonThemes.filled(tokens, scheme, type),
      outlinedButtonTheme: AppButtonThemes.outlined(tokens, type),
      textButtonTheme: AppButtonThemes.text(tokens, scheme, type),
      dividerTheme: DividerThemeData(
        color: tokens.divider,
        thickness: 1,
        space: 1,
      ),
      navigationRailTheme: _navigationRail(tokens, scheme, type),
      chipTheme: _chip(tokens, scheme, type),
      switchTheme: _switch(tokens, scheme),
      checkboxTheme: _checkbox(tokens, scheme),
      radioTheme: _radio(tokens, scheme),
      menuTheme: _menu(tokens),
      menuButtonTheme: _menuButton(tokens, type),
      dialogTheme: _dialog(tokens, type),
      bottomSheetTheme: _bottomSheet(tokens),
      snackBarTheme: _snackBar(tokens, scheme, type),
      sliderTheme: _slider(tokens),
      progressIndicatorTheme: _progress(tokens, scheme),
      tooltipTheme: _tooltip(tokens, type),
      textSelectionTheme: _selection(scheme),
    );
  }

  // The rail from 600 dp: the phone bar's fill, with a pill indicator.
  static NavigationRailThemeData _navigationRail(
    AppTokens t,
    ColorScheme scheme,
    AppTextStyles type,
  ) => NavigationRailThemeData(
    backgroundColor: t.navBar,
    elevation: 0,
    indicatorColor: scheme.primary,
    indicatorShape: const _NavIndicatorShape(),
    useIndicator: true,
    labelType: NavigationRailLabelType.all,
    selectedIconTheme: _navIcon(t, true),
    unselectedIconTheme: _navIcon(t, false),
    selectedLabelTextStyle: _navLabel(t, type, true),
    unselectedLabelTextStyle: _navLabel(t, type, false),
  );

  static IconThemeData _navIcon(AppTokens t, bool selected) => IconThemeData(
    size: AppSizes.iconNav,
    color: selected ? t.primaryIcon : t.textMuted,
  );

  static TextStyle _navLabel(AppTokens t, AppTextStyles type, bool selected) =>
      selected
      ? type.navLabel.copyWith(fontWeight: FontWeight.w600)
      : type.navLabel.copyWith(color: t.textMuted);

  static ChipThemeData _chip(
    AppTokens t,
    ColorScheme scheme,
    AppTextStyles type,
  ) {
    final label = type.body;
    // Padding, not a fixed height, so the chip grows with the text scale. The
    // 1 dp border sits inside the chip's box, so it comes off the padding.
    final vertical = (_chipHeight - label.fontSize! * label.height! - 2) / 2;
    return ChipThemeData(
      backgroundColor: scheme.primary.withValues(alpha: 0),
      selectedColor: scheme.primary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      pressElevation: 0,
      showCheckmark: false,
      shape: const StadiumBorder(),
      // The border matches the fill when selected, so no grey ring shows.
      side: WidgetStateBorderSide.resolveWith(
        (states) => BorderSide(
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : t.borderControl,
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: Gap.lg, vertical: vertical),
      labelPadding: EdgeInsets.zero,
      labelStyle: label.copyWith(
        fontWeight: FontWeight.w500,
        color: WidgetStateColor.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? scheme.onPrimary : t.text,
        ),
      ),
    );
  }

  static SwitchThemeData _switch(AppTokens t, ColorScheme scheme) =>
      SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : t.borderControl,
        ),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : t.textMuted,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        // M3 pads the switch by 4 dp; the spec's box is the 52 x 32 track.
        padding: EdgeInsets.zero,
        // M3 draws a 16 dp knob when off and 24 dp when on, unless it holds an
        // icon, which makes it 24 in both. The spec wants one big knob.
        thumbIcon: const WidgetStatePropertyAll(Icon(null)),
      );

  static CheckboxThemeData _checkbox(AppTokens t, ColorScheme scheme) =>
      CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.primary.withValues(alpha: 0),
        ),
        checkColor: WidgetStatePropertyAll(scheme.onPrimary),
        // The edge matches the fill when ticked, so no grey ring shows.
        side: WidgetStateBorderSide.resolveWith(
          (states) => BorderSide(
            width: 1.5,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : t.borderStrong,
          ),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_checkboxRadius),
        ),
      );

  static RadioThemeData _radio(AppTokens t, ColorScheme scheme) =>
      RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : t.borderStrong,
        ),
      );

  static MenuThemeData _menu(AppTokens t) => MenuThemeData(
    style: MenuStyle(
      backgroundColor: WidgetStatePropertyAll(t.surfaceRaised),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      shadowColor: const WidgetStatePropertyAll(_menuShadow),
      // Skia's shadow has no y/blur knobs; this is the closest to y 18, blur 40.
      elevation: const WidgetStatePropertyAll(12),
      padding: const WidgetStatePropertyAll(EdgeInsets.all(_menuPadding)),
      side: WidgetStatePropertyAll(BorderSide(color: t.borderControl)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.control),
        ),
      ),
    ),
  );

  static MenuButtonThemeData _menuButton(AppTokens t, AppTextStyles type) =>
      MenuButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, AppSizes.touch)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: Gap.md),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.thumb),
            ),
          ),
          foregroundColor: WidgetStatePropertyAll(t.text),
          iconColor: WidgetStatePropertyAll(t.text),
          iconSize: const WidgetStatePropertyAll(AppSizes.iconButton),
          // Padded would stretch every row to 48 and open gaps between them.
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: WidgetStatePropertyAll(type.body),
        ),
      );

  static DialogThemeData _dialog(AppTokens t, AppTextStyles type) =>
      DialogThemeData(
        backgroundColor: t.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        barrierColor: t.scrim,
        insetPadding: const EdgeInsets.all(Gap.xl),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.sheet),
          side: BorderSide(color: t.border),
        ),
        titleTextStyle: type.dialogTitle,
        contentTextStyle: type.bodyRelaxed.copyWith(color: t.errorBody),
      );

  static BottomSheetThemeData _bottomSheet(AppTokens t) => BottomSheetThemeData(
    modalBackgroundColor: t.surface,
    surfaceTintColor: Colors.transparent,
    modalBarrierColor: t.scrim,
    modalElevation: 0,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(Radii.sheet),
      ),
      side: BorderSide(color: t.border),
    ),
  );

  // The action label can only be recoloured here: the bar wraps its action in
  // a TextButtonTheme of its own, so the app's button themes never reach it.
  static SnackBarThemeData _snackBar(
    AppTokens t,
    ColorScheme scheme,
    AppTextStyles type,
  ) => SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    backgroundColor: t.surfaceRaised,
    elevation: 0,
    contentTextStyle: type.body,
    actionTextColor: scheme.primary,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.row),
      side: BorderSide(color: t.border),
    ),
  );

  // The only slider is the player's, which sits on video in both themes, so
  // it takes the accent: in light the primary is ink, invisible on a dark frame.
  static SliderThemeData _slider(AppTokens t) => SliderThemeData(
    trackHeight: 4,
    activeTrackColor: t.accent,
    inactiveTrackColor: t.onMedia.withValues(alpha: .22),
    thumbColor: t.accent,
    overlayColor: t.accent.withValues(alpha: .12),
    thumbShape: const RoundSliderThumbShape(
      enabledThumbRadius: _sliderThumb / 2,
    ),
    overlayShape: const RoundSliderOverlayShape(overlayRadius: Gap.lg),
    trackShape: const RoundedRectSliderTrackShape(),
    showValueIndicator: ShowValueIndicator.never,
  );

  static ProgressIndicatorThemeData _progress(
    AppTokens t,
    ColorScheme scheme,
  ) => ProgressIndicatorThemeData(
    color: scheme.primary,
    refreshBackgroundColor: t.surface,
  );

  static TooltipThemeData _tooltip(AppTokens t, AppTextStyles type) =>
      TooltipThemeData(
        decoration: BoxDecoration(
          color: t.surfaceRaised,
          border: Border.all(color: t.borderControl),
          borderRadius: BorderRadius.circular(Radii.thumbSmall),
        ),
        textStyle: type.caption,
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.md,
          vertical: Gap.sm,
        ),
      );

  static TextSelectionThemeData _selection(ColorScheme scheme) =>
      TextSelectionThemeData(
        cursorColor: scheme.primary,
        selectionColor: scheme.primary.withValues(alpha: .4),
        selectionHandleColor: scheme.primary,
      );
}

/// NavigationRail draws its indicator in a fixed box with no size knob. The
/// spec's pill is 56 x 30, so this shape draws it centred in that box, never
/// larger than it. The ink splash is clipped to the same path.
class _NavIndicatorShape extends ShapeBorder {
  const _NavIndicatorShape();

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    const pill = AppSizes.navIndicator;
    final box = Rect.fromCenter(
      center: rect.center,
      width: math.min(rect.width, pill.width),
      height: math.min(rect.height, pill.height),
    );
    return Path()..addRRect(
      RRect.fromRectAndRadius(box, Radius.circular(box.shortestSide / 2)),
    );
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => this;
}
