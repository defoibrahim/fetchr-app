import 'dart:ui';

/// An accent the user can pick, with the tint behind a selected row in each
/// brightness. Lime's tints are the spec's. The others are the accent at 4.5%
/// (dark) and 19% (light) over `surface`: the alphas that land closest to lime's.
class AccentOption {
  const AccentOption(
    this.name,
    this.color, {
    required this.darkTint,
    required this.lightTint,
  });

  /// What a screen reader calls the swatch.
  final String name;
  final Color color;
  final Color darkTint;
  final Color lightTint;
}

/// Every colour the spec fixes, per brightness. The accent is a setting, so it
/// is not here beyond the default and the options.
class AppPalette {
  const AppPalette._({
    required this.brightness,
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
    required this.onAccent,
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
  });

  static const defaultAccent = Color(0xFFC8F03C);

  /// Lime, blue, amber, pink; each passes 4.5:1 with `onAccent`.
  static const accents = [
    AccentOption(
      'Lime',
      defaultAccent,
      darkTint: Color(0xFF23241C),
      lightTint: Color(0xFFF1F5DC),
    ),
    AccentOption(
      'Blue',
      Color(0xFF7CC4FF),
      darkTint: Color(0xFF1F2322),
      lightTint: Color(0xFFE6F4FF),
    ),
    AccentOption(
      'Amber',
      Color(0xFFFFB547),
      darkTint: Color(0xFF25221A),
      lightTint: Color(0xFFFFF1DC),
    ),
    AccentOption(
      'Pink',
      Color(0xFFF59BE8),
      darkTint: Color(0xFF252121),
      lightTint: Color(0xFFFDECFB),
    ),
  ];

  /// An accent outside the options, such as a stale saved one, borrows lime's
  /// tints.
  static AccentOption optionOf(Color color) =>
      accents.firstWhere((o) => o.color == color, orElse: () => accents.first);

  /// Foreground and scrim for anything drawn over a video frame or thumbnail;
  /// the same in both brightnesses.
  static const onMedia = Color(0xFFFFFFFF);
  static final mediaScrim = const Color(0xFF000000).withValues(alpha: .72);

  static const dark = AppPalette._(
    brightness: Brightness.dark,
    bg: Color(0xFF121210),
    surface: Color(0xFF1B1B18),
    surfaceRaised: Color(0xFF24231F),
    surfaceSunken: Color(0xFF2A2925),
    navBar: Color(0xFF161614),
    shimmer: Color(0xFF3A3933),
    border: Color(0xFF33322D),
    borderStrong: Color(0xFF4A4840),
    borderControl: Color(0xFF3D3C36),
    divider: Color(0xFF262521),
    text: Color(0xFFF3F1EA),
    textMuted: Color(0xFFA8A59B),
    placeholder: Color(0xFF8F8C82),
    onAccent: Color(0xFF121210),
    audioTile: Color(0xFF1F2A1A),
    stripeA: Color(0xFF2B2A24),
    stripeB: Color(0xFF25241F),
    error: Color(0xFFFF9147),
    onError: Color(0xFF121210),
    errorText: Color(0xFFFFB585),
    errorBody: Color(0xFFC9C5BA),
    errorSurface: Color(0xFF1E1915),
    errorBorder: Color(0xFF4A3626),
    errorIconBg: Color(0xFF3A2618),
    scrim: Color(0xB8060605),
  );

  static const light = AppPalette._(
    brightness: Brightness.light,
    bg: Color(0xFFF6F5F0),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFECEAE2),
    navBar: Color(0xFFFFFFFF),
    shimmer: Color(0xFFF7F6F1),
    border: Color(0xFFDEDCD3),
    borderStrong: Color(0xFFBDBAAF),
    borderControl: Color(0xFFD3D0C5),
    divider: Color(0xFFE4E2DA),
    text: Color(0xFF171714),
    textMuted: Color(0xFF5F5C54),
    placeholder: Color(0xFF6E6B62),
    onAccent: Color(0xFF121210),
    audioTile: Color(0xFF171714),
    stripeA: Color(0xFFE6E3D8),
    stripeB: Color(0xFFDEDBCF),
    error: Color(0xFFC2410C),
    onError: Color(0xFFFFFFFF),
    errorText: Color(0xFFC2410C),
    errorBody: Color(0xFF5F5C54),
    errorSurface: Color(0xFFFFF4ED),
    errorBorder: Color(0xFFF3C9AE),
    errorIconBg: Color(0xFFFDE3D2),
    scrim: Color(0xB8060605),
  );

  final Brightness brightness;
  final Color bg;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceSunken;
  final Color navBar;

  // The highlight a loading skeleton's shimmer sweeps across its bones, which
  // are surfaceSunken.
  final Color shimmer;
  final Color border;
  final Color borderStrong;
  final Color borderControl;
  final Color divider;
  final Color text;
  final Color textMuted;
  final Color placeholder;
  final Color onAccent;
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

  static AppPalette of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}
