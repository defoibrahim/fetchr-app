import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/launch/launch_intro.dart';
import 'package:grabby/app/shared/launch_logo_target.dart';
import 'package:grabby/app/theme/system_bars.dart';
import 'package:grabby/core/logging/app_logger.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/widgets/app_icon.dart';

import '../../core/widgets/widget_harness.dart' show reduceMotion;
import '../../support/launch_intro_harness.dart';

final _blue = AppPalette.accents[1].color;

BoxDecoration _decoration(WidgetTester tester) =>
    tester.widget<DecoratedBox>(introTile).decoration as BoxDecoration;

double _radius(WidgetTester tester) =>
    (_decoration(tester).borderRadius! as BorderRadius).topLeft.x;

Color _glyph(WidgetTester tester) => tester
    .widget<AppIcon>(find.descendant(of: introOverlay, matching: logoIcon))
    .color!;

Color _background(WidgetTester tester) => tester
    .widget<ColoredBox>(
      find.descendant(of: introOverlay, matching: find.byType(ColoredBox)),
    )
    .color;

SystemUiOverlayStyle _bars(WidgetTester tester) => tester
    .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.descendant(
        of: introOverlay,
        matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
      ),
    )
    .value;

/// An animation ends on the first frame after its duration, not on the one
/// that reaches it.
Future<void> _nextFrame(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 16));

void main() {
  tearDown(AppLogger.reset);

  group('before the native splash is gone', () {
    testWidgets('holds the centred 120 px tile', (tester) async {
      final gone = await pumpIntro(tester);

      expect(tileRect(tester), introCentre);
      expect(_radius(tester), closeTo(36, 0.01), reason: 'the header ratio');
      expect(
        tester.getSize(
          find.descendant(of: introTile, matching: find.byType(AppIcon)),
        ),
        const Size(72, 72),
      );
      expect(tester.getRect(introOverlay), Offset.zero & introWindow);

      await tester.pump(const Duration(milliseconds: 1000));
      expect(tileRect(tester), introCentre, reason: 'no motion while waiting');
      await releaseAndSettle(tester, gone);
    });

    for (final (platform, inApp, icons) in [
      (Brightness.light, AppTheme.dark(), Brightness.dark),
      (Brightness.dark, AppTheme.light(), Brightness.light),
    ]) {
      testWidgets('a ${platform.name} system gets its splash colours and '
          '${icons.name} bar icons, whatever the in-app theme', (tester) async {
        final gone = await pumpIntro(tester, platform: platform, theme: inApp);

        final colors = launchSplashColors(platform);
        expect(_decoration(tester).color, colors.tile);
        expect(_glyph(tester), colors.glyph);
        expect(_background(tester), colors.background);
        expect(_bars(tester), systemBarsStyle(icons));

        await releaseAndSettle(tester, gone);
      });
    }

    testWidgets('asks the native side once, after the first frame', (
      tester,
    ) async {
      final gone = Completer<void>();
      var calls = 0;
      await pumpIntro(
        tester,
        splashGone: () {
          calls++;
          return gone.future;
        },
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(calls, 1);
      await releaseAndSettle(tester, gone);
    });

    testWidgets('absorbs taps and hides itself from semantics', (tester) async {
      final gone = await pumpIntro(tester);

      await tester.tap(find.text('taps 0'), warnIfMissed: false);
      await tester.pump();
      expect(find.text('taps 0'), findsOneWidget);
      expect(
        find.ancestor(of: introTile, matching: find.byType(ExcludeSemantics)),
        findsWidgets,
      );

      await releaseSplash(tester, gone);
      await tester.tap(find.text('taps 0'), warnIfMissed: false);
      await tester.pump();
      expect(find.text('taps 0'), findsOneWidget, reason: 'still running');

      await tester.pumpAndSettle();
      await tester.tap(find.text('taps 0'));
      await tester.pump();
      expect(find.text('taps 1'), findsOneWidget);
    });
  });

  group('after the native splash is gone', () {
    testWidgets('flies the tile onto the target and removes the overlay', (
      tester,
    ) async {
      final gone = await pumpIntro(
        tester,
        platform: Brightness.light,
        theme: AppTheme.dark(_blue),
      );
      final page = tester.element(find.byType(Scaffold));
      final inApp = AppTokens.of(page);
      expect(LaunchLogoTarget.keyOf(page), isNotNull);

      await releaseSplash(tester, gone);
      expect(tileRect(tester), introCentre, reason: 'the flight starts at 0');

      await tester.pump(launchIntroReveal);
      expect(tileRect(tester), introCentre, reason: 'the tagline shows first');

      await tester.pump(launchIntroFlight ~/ 2);
      final mid = tileRect(tester);
      final eased = Curves.easeInOutCubic.transform(0.5);
      final expected = Rect.lerp(introCentre, introTarget, eased)!;
      expect(mid.left, closeTo(expected.left, 0.01));
      expect(mid.top, closeTo(expected.top, 0.01));
      expect(mid.width, closeTo(expected.width, 0.01));
      expect(_radius(tester), closeTo(mid.width * 0.3, 0.01));

      await tester.pump(launchIntroFlight ~/ 2);
      final landed = tileRect(tester);
      expect(landed.left, closeTo(introTarget.left, 0.01));
      expect(landed.top, closeTo(introTarget.top, 0.01));
      expect(landed.width, closeTo(introTarget.width, 0.01));
      expect(landed.height, closeTo(introTarget.height, 0.01));
      // 8-bit channels: the last lerp step can be an ulp off.
      expect(
        _decoration(tester).color!.toARGB32(),
        AppTheme.dark(_blue).colorScheme.primary.toARGB32(),
      );
      expect(_glyph(tester).toARGB32(), inApp.primaryIcon.toARGB32());
      expect(_background(tester).toARGB32(), inApp.bg.toARGB32());

      await tester.pump(launchIntroFade ~/ 2);
      expect(introOverlay, findsOneWidget, reason: 'the background is fading');
      expect(tileRect(tester).left, closeTo(introTarget.left, 0.01));

      await tester.pump(launchIntroFade ~/ 2);
      await _nextFrame(tester);
      expect(introOverlay, findsNothing);
    });

    testWidgets('with reduce motion it ends at once, with no flight', (
      tester,
    ) async {
      reduceMotion(tester);
      final gone = await pumpIntro(tester);

      await releaseSplash(tester, gone);

      expect(introOverlay, findsNothing);
    });

    testWidgets('with no target it fades out where it stands', (tester) async {
      final gone = await pumpIntro(
        tester,
        page: const IntroPage(withTarget: false),
      );

      await releaseSplash(tester, gone);
      await tester.pump(launchIntroReveal + launchIntroFade ~/ 2);
      expect(introOverlay, findsOneWidget);
      expect(tileRect(tester), introCentre, reason: 'nowhere to fly');

      await tester.pump(launchIntroFade ~/ 2);
      await _nextFrame(tester);
      expect(introOverlay, findsNothing);
    });
  });
}
