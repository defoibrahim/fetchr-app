import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/theme/app_spacing.dart';
import 'package:grabby/core/theme/theme.dart';

import '../widgets/widget_harness.dart';
import 'contrast.dart';

const lime = AppPalette.defaultAccent;

void main() {
  final dark = AppTheme.dark(lime).extension<AppTokens>()!;
  final light = AppTheme.light(lime).extension<AppTokens>()!;

  group('AppPalette', () {
    test('offers lime first, then blue, amber and pink', () {
      expect(AppPalette.accents.map((o) => o.color), const [
        Color(0xFFC8F03C),
        Color(0xFF7CC4FF),
        Color(0xFFFFB547),
        Color(0xFFF59BE8),
      ]);
      expect(AppPalette.accents.first.color, AppPalette.defaultAccent);
    });

    test('optionOf finds the option, and lime stands in for a stranger', () {
      expect(
        AppPalette.optionOf(AppPalette.accents[2].color),
        AppPalette.accents[2],
      );
      expect(AppPalette.optionOf(Colors.teal), AppPalette.accents.first);
    });
  });

  group('tokens', () {
    test('dark and light carry the spec values', () {
      expect(dark.bg, const Color(0xFF121210));
      expect(light.bg, const Color(0xFFF6F5F0));
      expect(dark.surfaceRaised, const Color(0xFF24231F));
      expect(dark.surfaceSunken, const Color(0xFF2A2925));
      expect(light.surfaceSunken, const Color(0xFFECEAE2));
      expect(dark.borderStrong, const Color(0xFF4A4840));
      expect(dark.text, const Color(0xFFF3F1EA));
      expect(light.textMuted, const Color(0xFF5F5C54));
      expect(dark.error, const Color(0xFFFF9147));
      expect(light.errorSurface, const Color(0xFFFFF4ED));
      expect(dark.onAccent, const Color(0xFF121210));
      expect(light.onAccent, const Color(0xFF121210));
    });

    test('scrim is #060605 at 72%', () {
      for (final t in [dark, light]) {
        expect(t.scrim.toARGB32() & 0x00FFFFFF, 0x060605);
        expect(t.scrim.a, closeTo(.72, .01));
      }
    });

    test('the accent is a setting, so it follows the argument', () {
      final pink = AppPalette.accents.last.color;
      expect(AppTheme.dark(pink).extension<AppTokens>()!.accent, pink);
      expect(AppTheme.light(pink).extension<AppTokens>()!.accent, pink);
    });

    test('primaryIcon is onAccent in dark and the accent in light', () {
      expect(dark.primaryIcon, dark.onAccent);
      expect(light.primaryIcon, lime);
    });

    test('each accent owns its tint: the spec values for lime', () {
      expect(dark.accentTint, const Color(0xFF23241C));
      expect(light.accentTint, const Color(0xFFF1F5DC));
      for (final option in AppPalette.accents) {
        final darkTokens = AppTheme.dark(option.color).extension<AppTokens>()!;
        final lightTokens = AppTheme.light(
          option.color,
        ).extension<AppTokens>()!;
        expect(darkTokens.accentTint, option.darkTint);
        expect(lightTokens.accentTint, option.lightTint);
        expect(
          contrast(darkTokens.text, darkTokens.accentTint),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(lightTokens.text, lightTokens.accentTint),
          greaterThanOrEqualTo(4.5),
        );
      }
    });

    test('onMedia is white and mediaScrim is black at 72%', () {
      for (final t in [dark, light]) {
        expect(t.onMedia, const Color(0xFFFFFFFF));
        expect(t.mediaScrim.toARGB32() & 0x00FFFFFF, 0);
        expect(t.mediaScrim.a, closeTo(.72, .001));
      }
    });

    test('tokens lerp to the other end and compare by value', () {
      expect(dark.lerp(light, 0), dark);
      expect(dark.lerp(light, 1), light);
      expect(dark.lerp(null, .5), dark);
      expect(dark.copyWith(), dark);
      expect(dark.copyWith().hashCode, dark.hashCode);
      expect(dark.copyWith(text: Colors.pink).text, Colors.pink);
      expect(dark.copyWith(text: Colors.pink), isNot(dark));
    });

    test('lerp blends at the midpoint', () {
      expect(
        dark.lerp(light, .5).surface,
        Color.lerp(dark.surface, light.surface, .5),
      );
    });
  });

  group('scheme', () {
    for (final accent in AppPalette.accents.map((o) => o.color)) {
      test('dark primary is the accent ${accent.toARGB32()}', () {
        final scheme = AppTheme.dark(accent).colorScheme;
        expect(scheme.primary, accent);
        expect(scheme.onPrimary, const Color(0xFF121210));
        expect(contrast(scheme.onPrimary, scheme.primary), greaterThan(4.5));
      });
    }

    test('light primary is ink, never the accent', () {
      for (final accent in AppPalette.accents.map((o) => o.color)) {
        final theme = AppTheme.light(accent);
        expect(theme.colorScheme.primary, const Color(0xFF171714));
        expect(theme.colorScheme.onPrimary, const Color(0xFFF6F5F0));
        expect(theme.extension<AppTokens>()!.primaryIcon, accent);
      }
    });

    test('maps the tokens onto the Material roles in both themes', () {
      for (final (theme, t) in [
        (AppTheme.dark(lime), dark),
        (AppTheme.light(lime), light),
      ]) {
        final s = theme.colorScheme;
        expect(s.surface, t.bg);
        expect(s.surfaceContainerLowest, t.bg);
        expect(s.surfaceContainerLow, t.surface);
        expect(s.surfaceContainer, t.surface);
        expect(s.surfaceContainerHigh, t.surfaceRaised);
        expect(s.surfaceContainerHighest, t.surfaceSunken);
        expect(s.onSurface, t.text);
        expect(s.onSurfaceVariant, t.textMuted);
        expect(s.outline, t.borderStrong);
        expect(s.outlineVariant, t.border);
        expect(s.error, t.error);
        expect(s.onError, t.onError);
        expect(s.primaryContainer, t.accentTint);
        expect(s.onPrimaryContainer, t.text);
        expect(s.secondary, s.primary);
        expect(s.onSecondary, s.onPrimary);
        expect(s.surfaceTint, Colors.transparent);
        expect(s.scrim, t.scrim);
        expect(s.inverseSurface, t.text);
        expect(s.onInverseSurface, t.bg);
      }
    });

    test('brightness matches the theme', () {
      expect(AppTheme.dark(lime).brightness, Brightness.dark);
      expect(AppTheme.light(lime).brightness, Brightness.light);
    });
  });

  group('contrast', () {
    for (final theme in [AppTheme.dark(lime), AppTheme.light(lime)]) {
      test('text tokens reach 4.5:1 (${theme.brightness})', () {
        final t = theme.extension<AppTokens>()!;
        for (final fg in [t.text, t.textMuted, t.placeholder]) {
          expect(contrast(fg, t.bg), greaterThanOrEqualTo(4.5));
          expect(contrast(fg, t.surface), greaterThanOrEqualTo(4.5));
        }
        expect(
          contrast(t.errorText, t.errorSurface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(t.errorBody, t.errorSurface),
          greaterThanOrEqualTo(4.5),
        );
        expect(contrast(t.onError, t.error), greaterThanOrEqualTo(4.5));
      });
    }
  });

  group('AppTheme', () {
    test('a theme is built once per accent', () {
      expect(identical(AppTheme.dark(lime), AppTheme.dark(lime)), isTrue);
      expect(identical(AppTheme.light(lime), AppTheme.light(lime)), isTrue);
      expect(
        identical(
          AppTheme.dark(lime),
          AppTheme.dark(AppPalette.accents[1].color),
        ),
        isFalse,
      );
    });

    test('the accent defaults to lime', () {
      expect(identical(AppTheme.dark(), AppTheme.dark(lime)), isTrue);
      expect(identical(AppTheme.light(), AppTheme.light(lime)), isTrue);
    });

    test('wires the page, app bar and divider to the tokens', () {
      for (final (theme, t) in [
        (AppTheme.dark(lime), dark),
        (AppTheme.light(lime), light),
      ]) {
        expect(theme.useMaterial3, isTrue);
        expect(theme.scaffoldBackgroundColor, t.bg);
        expect(theme.appBarTheme.backgroundColor, t.bg);
        expect(theme.appBarTheme.foregroundColor, t.text);
        expect(theme.appBarTheme.surfaceTintColor, Colors.transparent);
        expect(theme.dividerTheme.color, t.divider);
      }
    });

    test('text theme is coloured from the scheme', () {
      expect(AppTheme.dark(lime).textTheme.bodyMedium?.color, dark.text);
    });
  });

  group('ThemeContextX', () {
    testWidgets('reads the registered tokens and scheme', (tester) async {
      final context = await pumpContext(tester, theme: AppTheme.dark());
      expect(context.tokens, dark);
      expect(context.isDark, isTrue);
      expect(context.colors, AppTheme.dark().colorScheme);
    });

    testWidgets('isNarrow, reduceMotion and motion follow the media query', (
      tester,
    ) async {
      final context = await pumpContext(tester);
      const d = Duration(milliseconds: 200);

      useView(tester, const Size(359, 800));
      await tester.pump();
      expect(context.isNarrow, isTrue);
      expect(context.reduceMotion, isFalse);
      expect(context.motion(d), d);

      useView(tester, const Size(Breakpoints.narrow, 800));
      reduceMotion(tester);
      await tester.pump();
      expect(context.isNarrow, isFalse);
      expect(context.reduceMotion, isTrue);
      expect(context.motion(d), Duration.zero);
    });

    testWidgets('windowClass follows the window width', (tester) async {
      final context = await pumpContext(tester);

      for (final (width, expected) in [
        (340.0, WindowClass.narrow),
        (390.0, WindowClass.compact),
        (700.0, WindowClass.medium),
        (900.0, WindowClass.expanded),
      ]) {
        useView(tester, Size(width, 1000));
        await tester.pump();
        expect(context.windowClass, expected, reason: '$width dp');
      }
    });

    testWidgets('falls back to the palette when the extension is missing', (
      tester,
    ) async {
      final context = await pumpContext(tester, theme: ThemeData.light());
      expect(context.tokens, light);
    });
  });
}
