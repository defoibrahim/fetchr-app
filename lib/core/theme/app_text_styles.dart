import 'package:flutter/material.dart';

import '../gen/fonts.gen.dart';

/// The spec's 19 text styles plus [bodyRelaxed]. Sizes are raw design values,
/// not run through `.sp`: ThemeData is cached, so a scaled value would go
/// stale on rotation. Every style is coloured with `text`; callers override
/// the colour.
@immutable
class AppTextStyles extends ThemeExtension<AppTextStyles> {
  const AppTextStyles({
    required this.hero,
    required this.screenTitle,
    required this.pageTitle,
    required this.mediaTitle,
    required this.sheetTitle,
    required this.dialogTitle,
    required this.wordmark,
    required this.section,
    required this.button,
    required this.bodyStrong,
    required this.body,
    required this.bodyRelaxed,
    required this.cardTitle,
    required this.caption,
    required this.overline,
    required this.navLabel,
    required this.monoInput,
    required this.mono,
    required this.monoSmall,
    required this.monoBadge,
  });

  factory AppTextStyles.from(Color color) {
    TextStyle title(double size, double lineHeight, double spacing) => style(
      FontFamily.bricolage,
      size,
      lineHeight,
      color,
      weight: FontWeight.w700,
      spacing: spacing,
    );
    TextStyle ui(
      double size,
      double lineHeight,
      FontWeight weight, [
      double spacing = 0,
    ]) => style(
      FontFamily.geist,
      size,
      lineHeight,
      color,
      weight: weight,
      spacing: spacing,
    );
    TextStyle mono(double size, double lineHeight) =>
        style(FontFamily.jetBrainsMono, size, lineHeight, color);

    return AppTextStyles(
      hero: title(34, 36, -1.0),
      screenTitle: title(28, 34, -0.56),
      pageTitle: title(26, 29, -0.52),
      mediaTitle: title(22, 26, -0.2),
      sheetTitle: title(20, 24, -0.2),
      dialogTitle: title(22, 26, -0.2),
      wordmark: title(22, 26, -0.44),
      section: title(18, 22, 0),
      button: ui(16, 20, FontWeight.w600),
      bodyStrong: ui(15, 20, FontWeight.w500),
      body: ui(14, 20, FontWeight.w400),
      bodyRelaxed: ui(14, 21, FontWeight.w400),
      cardTitle: ui(17, 22, FontWeight.w600),
      caption: ui(12, 16, FontWeight.w400),
      overline: ui(12, 16, FontWeight.w500, 0.96),
      navLabel: ui(12, 16, FontWeight.w400),
      monoInput: mono(13, 18),
      mono: mono(12, 16),
      monoSmall: mono(11, 14),
      monoBadge: mono(10, 12),
    );
  }

  /// The one builder for a text style: `lineHeight` is in dp, stored as the
  /// ratio Flutter wants.
  static TextStyle style(
    String family,
    double size,
    double lineHeight,
    Color color, {
    FontWeight weight = FontWeight.w400,
    double spacing = 0,
  }) => TextStyle(
    fontFamily: family,
    fontSize: size,
    height: lineHeight / size,
    fontWeight: weight,
    letterSpacing: spacing,
    color: color,
  );

  /// A span in the mono family that keeps the surrounding size and colour.
  /// Family only, for callers that have no context to read `type.mono` from.
  static TextSpan monoSpan(String text) => TextSpan(
    text: text,
    style: const TextStyle(fontFamily: FontFamily.jetBrainsMono),
  );

  final TextStyle hero;
  final TextStyle screenTitle;
  final TextStyle pageTitle;
  final TextStyle mediaTitle;
  final TextStyle sheetTitle;
  final TextStyle dialogTitle;
  final TextStyle wordmark;
  final TextStyle section;
  final TextStyle button;
  final TextStyle bodyStrong;
  final TextStyle body;

  /// Body with the roomier 1.5 line height of a dialog message.
  final TextStyle bodyRelaxed;
  final TextStyle cardTitle;
  final TextStyle caption;

  /// Uppercase at the call site.
  final TextStyle overline;

  /// Weight 600 when active comes from the nav theme.
  final TextStyle navLabel;
  final TextStyle monoInput;
  final TextStyle mono;
  final TextStyle monoSmall;
  final TextStyle monoBadge;

  List<TextStyle> get _values => [
    hero,
    screenTitle,
    pageTitle,
    mediaTitle,
    sheetTitle,
    dialogTitle,
    wordmark,
    section,
    button,
    bodyStrong,
    body,
    bodyRelaxed,
    cardTitle,
    caption,
    overline,
    navLabel,
    monoInput,
    mono,
    monoSmall,
    monoBadge,
  ];

  @override
  AppTextStyles copyWith({
    TextStyle? hero,
    TextStyle? screenTitle,
    TextStyle? pageTitle,
    TextStyle? mediaTitle,
    TextStyle? sheetTitle,
    TextStyle? dialogTitle,
    TextStyle? wordmark,
    TextStyle? section,
    TextStyle? button,
    TextStyle? bodyStrong,
    TextStyle? body,
    TextStyle? bodyRelaxed,
    TextStyle? cardTitle,
    TextStyle? caption,
    TextStyle? overline,
    TextStyle? navLabel,
    TextStyle? monoInput,
    TextStyle? mono,
    TextStyle? monoSmall,
    TextStyle? monoBadge,
  }) {
    return AppTextStyles(
      hero: hero ?? this.hero,
      screenTitle: screenTitle ?? this.screenTitle,
      pageTitle: pageTitle ?? this.pageTitle,
      mediaTitle: mediaTitle ?? this.mediaTitle,
      sheetTitle: sheetTitle ?? this.sheetTitle,
      dialogTitle: dialogTitle ?? this.dialogTitle,
      wordmark: wordmark ?? this.wordmark,
      section: section ?? this.section,
      button: button ?? this.button,
      bodyStrong: bodyStrong ?? this.bodyStrong,
      body: body ?? this.body,
      bodyRelaxed: bodyRelaxed ?? this.bodyRelaxed,
      cardTitle: cardTitle ?? this.cardTitle,
      caption: caption ?? this.caption,
      overline: overline ?? this.overline,
      navLabel: navLabel ?? this.navLabel,
      monoInput: monoInput ?? this.monoInput,
      mono: mono ?? this.mono,
      monoSmall: monoSmall ?? this.monoSmall,
      monoBadge: monoBadge ?? this.monoBadge,
    );
  }

  @override
  AppTextStyles lerp(ThemeExtension<AppTextStyles>? other, double t) {
    if (other is! AppTextStyles) return this;
    TextStyle mix(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    return AppTextStyles(
      hero: mix(hero, other.hero),
      screenTitle: mix(screenTitle, other.screenTitle),
      pageTitle: mix(pageTitle, other.pageTitle),
      mediaTitle: mix(mediaTitle, other.mediaTitle),
      sheetTitle: mix(sheetTitle, other.sheetTitle),
      dialogTitle: mix(dialogTitle, other.dialogTitle),
      wordmark: mix(wordmark, other.wordmark),
      section: mix(section, other.section),
      button: mix(button, other.button),
      bodyStrong: mix(bodyStrong, other.bodyStrong),
      body: mix(body, other.body),
      bodyRelaxed: mix(bodyRelaxed, other.bodyRelaxed),
      cardTitle: mix(cardTitle, other.cardTitle),
      caption: mix(caption, other.caption),
      overline: mix(overline, other.overline),
      navLabel: mix(navLabel, other.navLabel),
      monoInput: mix(monoInput, other.monoInput),
      mono: mix(mono, other.mono),
      monoSmall: mix(monoSmall, other.monoSmall),
      monoBadge: mix(monoBadge, other.monoBadge),
    );
  }

  @override
  bool operator ==(Object other) {
    if (other is! AppTextStyles) return false;
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
