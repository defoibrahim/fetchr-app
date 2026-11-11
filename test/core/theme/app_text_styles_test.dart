import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/theme/app_text_styles.dart';
import 'package:grabby/core/theme/theme.dart';

import '../widgets/widget_harness.dart';

typedef _Spec = (
  String name,
  TextStyle Function(AppTextStyles) pick,
  String family,
  double size,
  double lineHeight,
  FontWeight weight,
  double spacing,
);

const _bricolage = 'Bricolage';
const _geist = 'Geist';
// Not Colors.red: a MaterialColor never equals a plain Color.
const _red = Color(0xFFF44336);
const _mono = 'JetBrainsMono';

final _specs = <_Spec>[
  ('hero', (t) => t.hero, _bricolage, 34, 36, FontWeight.w700, -1.0),
  (
    'screenTitle',
    (t) => t.screenTitle,
    _bricolage,
    28,
    34,
    FontWeight.w700,
    -0.56,
  ),
  ('pageTitle', (t) => t.pageTitle, _bricolage, 26, 29, FontWeight.w700, -0.52),
  (
    'mediaTitle',
    (t) => t.mediaTitle,
    _bricolage,
    22,
    26,
    FontWeight.w700,
    -0.2,
  ),
  (
    'sheetTitle',
    (t) => t.sheetTitle,
    _bricolage,
    20,
    24,
    FontWeight.w700,
    -0.2,
  ),
  (
    'dialogTitle',
    (t) => t.dialogTitle,
    _bricolage,
    22,
    26,
    FontWeight.w700,
    -0.2,
  ),
  ('wordmark', (t) => t.wordmark, _bricolage, 22, 26, FontWeight.w700, -0.44),
  ('section', (t) => t.section, _bricolage, 18, 22, FontWeight.w700, 0),
  ('button', (t) => t.button, _geist, 16, 20, FontWeight.w600, 0),
  ('bodyStrong', (t) => t.bodyStrong, _geist, 15, 20, FontWeight.w500, 0),
  ('body', (t) => t.body, _geist, 14, 20, FontWeight.w400, 0),
  ('bodyRelaxed', (t) => t.bodyRelaxed, _geist, 14, 21, FontWeight.w400, 0),
  ('cardTitle', (t) => t.cardTitle, _geist, 17, 22, FontWeight.w600, 0),
  ('caption', (t) => t.caption, _geist, 12, 16, FontWeight.w400, 0),
  ('overline', (t) => t.overline, _geist, 12, 16, FontWeight.w500, 0.96),
  ('navLabel', (t) => t.navLabel, _geist, 12, 16, FontWeight.w400, 0),
  ('monoInput', (t) => t.monoInput, _mono, 13, 18, FontWeight.w400, 0),
  ('mono', (t) => t.mono, _mono, 12, 16, FontWeight.w400, 0),
  ('monoSmall', (t) => t.monoSmall, _mono, 11, 14, FontWeight.w400, 0),
  ('monoBadge', (t) => t.monoBadge, _mono, 10, 12, FontWeight.w400, 0),
];

void main() {
  final dark = AppTheme.dark();
  final light = AppTheme.light();
  final darkType = dark.extension<AppTextStyles>()!;

  test('the table has the 19 spec styles and bodyRelaxed', () {
    expect(_specs, hasLength(20));
  });

  for (final (name, pick, family, size, lineHeight, weight, spacing)
      in _specs) {
    test('$name is $family $size/$lineHeight $weight', () {
      final style = pick(darkType);
      expect(style.fontFamily, family);
      expect(style.fontSize, size);
      expect(style.height, lineHeight / size);
      expect(style.fontWeight, weight);
      expect(style.letterSpacing, spacing);
    });
  }

  test('every style is coloured with the text token', () {
    final tokens = dark.extension<AppTokens>()!;
    for (final (_, pick, _, _, _, _, _) in _specs) {
      expect(pick(darkType).color, tokens.text);
    }
    final lightTokens = light.extension<AppTokens>()!;
    expect(light.extension<AppTextStyles>()!.body.color, lightTokens.text);
  });

  test('every M3 text slot is set in Geist', () {
    for (final theme in [dark, light]) {
      final t = theme.textTheme;
      final slots = [
        t.displayLarge,
        t.displayMedium,
        t.displaySmall,
        t.headlineLarge,
        t.headlineMedium,
        t.headlineSmall,
        t.titleLarge,
        t.titleMedium,
        t.titleSmall,
        t.bodyLarge,
        t.bodyMedium,
        t.bodySmall,
        t.labelLarge,
        t.labelMedium,
        t.labelSmall,
      ];
      for (final slot in slots) {
        expect(slot!.fontFamily, _geist);
      }
    }
    expect(dark.textTheme.bodyMedium!.fontFamily, 'Geist');
  });

  test('the extension copies and lerps', () {
    final other = AppTextStyles.from(_red);
    expect(darkType.copyWith(), darkType);
    expect(darkType.copyWith().hashCode, darkType.hashCode);
    expect(darkType.copyWith(hero: other.hero).hero, other.hero);
    expect(darkType.copyWith(hero: other.hero), isNot(darkType));
    expect(darkType.lerp(other, 0), darkType);
    expect(darkType.lerp(other, 1), other);
    expect(darkType.lerp(null, 0.5), darkType);
    final mid = darkType.lerp(other, 0.5);
    expect(mid.body.color, Color.lerp(darkType.body.color, _red, 0.5));
  });

  test('bodyRelaxed is body with a 1.5 line height', () {
    expect(darkType.bodyRelaxed.height, 1.5);
    expect(
      darkType.bodyRelaxed,
      darkType.body.copyWith(height: darkType.bodyRelaxed.height),
    );
  });

  test('monoSpan sets only the mono family', () {
    final span = AppTextStyles.monoSpan('1.2 GB');
    expect(span.text, '1.2 GB');
    expect(span.style, const TextStyle(fontFamily: _mono));
  });

  testWidgets('context.type reads the theme extension', (tester) async {
    final seen = (await pumpContext(tester, theme: light)).type;
    expect(seen, light.extension<AppTextStyles>());
    expect(seen.mono.fontFamily, _mono);
  });

  testWidgets('context.type falls back when the theme has no extension', (
    tester,
  ) async {
    final seen = (await pumpContext(tester, theme: ThemeData())).type;
    expect(seen.hero.fontFamily, _bricolage);
  });
}
