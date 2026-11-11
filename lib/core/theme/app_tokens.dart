import 'package:flutter/material.dart';

import 'app_palette.dart';

@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.bg,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.navBar,
    required this.shimmer,
    required this.border,
    required this.borderStrong,
    required this.borderControl,
    required this.divider,
    required this.text,
    required this.textMuted,
    required this.placeholder,
    required this.accent,
    required this.onAccent,
    required this.primaryIcon,
    required this.accentTint,
    required this.audioTile,
    required this.stripeA,
    required this.stripeB,
    required this.error,
    required this.onError,
    required this.errorText,
    required this.errorBody,
    required this.errorSurface,
    required this.errorBorder,
    required this.errorIconBg,
    required this.scrim,
    required this.onMedia,
    required this.mediaScrim,
  });

  /// The one place a palette meets the accent. The light theme never puts the
  /// accent on white as text, so it reaches a primary fill only as the icon.
  factory AppTokens.from(AppPalette p, Color accent) {
    final dark = p.brightness == Brightness.dark;
    final option = AppPalette.optionOf(accent);
    return AppTokens(
      bg: p.bg,
      surface: p.surface,
      surfaceRaised: p.surfaceRaised,
      surfaceSunken: p.surfaceSunken,
      navBar: p.navBar,
      shimmer: p.shimmer,
      border: p.border,
      borderStrong: p.borderStrong,
      borderControl: p.borderControl,
      divider: p.divider,
      text: p.text,
      textMuted: p.textMuted,
      placeholder: p.placeholder,
      accent: accent,
      onAccent: p.onAccent,
      primaryIcon: dark ? p.onAccent : accent,
      accentTint: dark ? option.darkTint : option.lightTint,
      audioTile: p.audioTile,
      stripeA: p.stripeA,
      stripeB: p.stripeB,
      error: p.error,
      onError: p.onError,
      errorText: p.errorText,
      errorBody: p.errorBody,
      errorSurface: p.errorSurface,
      errorBorder: p.errorBorder,
      errorIconBg: p.errorIconBg,
      scrim: p.scrim,
      onMedia: AppPalette.onMedia,
      mediaScrim: AppPalette.mediaScrim,
    );
  }

  final Color bg;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceSunken;
  final Color navBar;
  final Color shimmer;
  final Color border;
  final Color borderStrong;
  final Color borderControl;
  final Color divider;
  final Color text;
  final Color textMuted;
  final Color placeholder;
  final Color accent;
  final Color onAccent;

  /// The icon on a primary fill: `onAccent` on the accent in dark, the accent
  /// on ink in light.
  final Color primaryIcon;
  final Color accentTint;
  final Color audioTile;
  final Color stripeA;
  final Color stripeB;
  final Color error;
  final Color onError;
  final Color errorText;
  final Color errorBody;
  final Color errorSurface;
  final Color errorBorder;
  final Color errorIconBg;
  final Color scrim;

  /// Foreground and scrim over a video frame or thumbnail, the same in both
  /// brightnesses.
  final Color onMedia;
  final Color mediaScrim;

  static AppTokens of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppTokens>() ??
        AppTokens.from(
          AppPalette.of(theme.brightness),
          AppPalette.defaultAccent,
        );
  }

  List<Color> get _values => [
    bg,
    surface,
    surfaceRaised,
    surfaceSunken,
    navBar,
    shimmer,
    border,
    borderStrong,
    borderControl,
    divider,
    text,
    textMuted,
    placeholder,
    accent,
    onAccent,
    primaryIcon,
    accentTint,
    audioTile,
    stripeA,
    stripeB,
    error,
    onError,
    errorText,
    errorBody,
    errorSurface,
    errorBorder,
    errorIconBg,
    scrim,
    onMedia,
    mediaScrim,
  ];

  @override
  AppTokens copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceSunken,
    Color? navBar,
    Color? shimmer,
    Color? border,
    Color? borderStrong,
    Color? borderControl,
    Color? divider,
    Color? text,
    Color? textMuted,
    Color? placeholder,
    Color? accent,
    Color? onAccent,
    Color? primaryIcon,
    Color? accentTint,
    Color? audioTile,
    Color? stripeA,
    Color? stripeB,
    Color? error,
    Color? onError,
    Color? errorText,
    Color? errorBody,
    Color? errorSurface,
    Color? errorBorder,
    Color? errorIconBg,
    Color? scrim,
    Color? onMedia,
    Color? mediaScrim,
  }) {
    return AppTokens(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      navBar: navBar ?? this.navBar,
      shimmer: shimmer ?? this.shimmer,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      borderControl: borderControl ?? this.borderControl,
      divider: divider ?? this.divider,
      text: text ?? this.text,
      textMuted: textMuted ?? this.textMuted,
      placeholder: placeholder ?? this.placeholder,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      primaryIcon: primaryIcon ?? this.primaryIcon,
      accentTint: accentTint ?? this.accentTint,
      audioTile: audioTile ?? this.audioTile,
      stripeA: stripeA ?? this.stripeA,
      stripeB: stripeB ?? this.stripeB,
      error: error ?? this.error,
      onError: onError ?? this.onError,
      errorText: errorText ?? this.errorText,
      errorBody: errorBody ?? this.errorBody,
      errorSurface: errorSurface ?? this.errorSurface,
      errorBorder: errorBorder ?? this.errorBorder,
      errorIconBg: errorIconBg ?? this.errorIconBg,
      scrim: scrim ?? this.scrim,
      onMedia: onMedia ?? this.onMedia,
      mediaScrim: mediaScrim ?? this.mediaScrim,
    );
  }

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppTokens(
      bg: mix(bg, other.bg),
      surface: mix(surface, other.surface),
      surfaceRaised: mix(surfaceRaised, other.surfaceRaised),
      surfaceSunken: mix(surfaceSunken, other.surfaceSunken),
      navBar: mix(navBar, other.navBar),
      shimmer: mix(shimmer, other.shimmer),
      border: mix(border, other.border),
      borderStrong: mix(borderStrong, other.borderStrong),
      borderControl: mix(borderControl, other.borderControl),
      divider: mix(divider, other.divider),
      text: mix(text, other.text),
      textMuted: mix(textMuted, other.textMuted),
      placeholder: mix(placeholder, other.placeholder),
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
      primaryIcon: mix(primaryIcon, other.primaryIcon),
      accentTint: mix(accentTint, other.accentTint),
      audioTile: mix(audioTile, other.audioTile),
      stripeA: mix(stripeA, other.stripeA),
      stripeB: mix(stripeB, other.stripeB),
      error: mix(error, other.error),
      onError: mix(onError, other.onError),
      errorText: mix(errorText, other.errorText),
      errorBody: mix(errorBody, other.errorBody),
      errorSurface: mix(errorSurface, other.errorSurface),
      errorBorder: mix(errorBorder, other.errorBorder),
      errorIconBg: mix(errorIconBg, other.errorIconBg),
      scrim: mix(scrim, other.scrim),
      onMedia: mix(onMedia, other.onMedia),
      mediaScrim: mix(mediaScrim, other.mediaScrim),
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is! AppTokens) return false;
    final mine = _values;
    final theirs = other._values;
    for (var i = 0; i < mine.length; i++) {
      if (mine[i] != theirs[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_values);
}
