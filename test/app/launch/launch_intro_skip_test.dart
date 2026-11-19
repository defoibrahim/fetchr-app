import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/launch/launch_intro.dart';
import 'package:grabby/app/shared/launch_logo_target.dart';

import '../../core/widgets/widget_harness.dart';
import '../../support/launch_intro_harness.dart';

const _fadeAndAFrame = Duration(milliseconds: 260);

void main() {
  group('a tap', () {
    testWidgets('mid-tagline jumps to the closing fade with the tile home', (
      tester,
    ) async {
      final gone = await pumpIntro(tester);
      await releaseSplash(tester, gone);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tileRect(tester), introCentre);

      await tester.tapAt(const Offset(195, 700));
      await tester.pump();
      expect(introOverlay, findsOneWidget);
      expect(tileRect(tester), introTarget);

      await tester.pump(launchIntroFade ~/ 2);
      expect(introOverlay, findsOneWidget, reason: 'still fading');

      await tester.pump(_fadeAndAFrame);
      expect(introOverlay, findsNothing);
    });

    testWidgets('is absorbed: the page under it gets nothing', (tester) async {
      final gone = await pumpIntro(tester);
      await releaseSplash(tester, gone);

      await tester.tap(find.text('taps 0'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('taps 0'), findsOneWidget);
      expect(introOverlay, findsNothing);

      await tester.tap(find.text('taps 0'));
      await tester.pump();
      expect(find.text('taps 1'), findsOneWidget);
    });

    testWidgets('before the native splash reports still fades, then ignores '
        'the splash', (tester) async {
      final gone = await pumpIntro(tester);
      await tester.tapAt(const Offset(195, 700));
      await tester.pump();
      expect(introOverlay, findsOneWidget);

      await tester.pump(_fadeAndAFrame);
      expect(introOverlay, findsNothing);

      // The splash reporting late does not start the intro over.
      await releaseSplash(tester, gone);
      await tester.pump(const Duration(milliseconds: 100));
      expect(introOverlay, findsNothing);
    });

    testWidgets('during the fade changes nothing', (tester) async {
      final gone = await pumpIntro(tester);
      await releaseSplash(tester, gone);
      await tester.pump(launchIntroReveal + launchIntroFlight);
      await tester.pump(launchIntroFade ~/ 2);

      await tester.tapAt(const Offset(195, 700));
      await tester.pump(
        launchIntroFade ~/ 2 + const Duration(milliseconds: 20),
      );
      expect(introOverlay, findsNothing);
    });

    testWidgets('under reduce motion removes it at once', (tester) async {
      reduceMotion(tester);
      final gone = await pumpIntro(tester);
      await tester.tapAt(const Offset(195, 700));
      await tester.pump();
      expect(introOverlay, findsNothing);
      await releaseSplash(tester, gone);
    });
  });

  group('a shared link', () {
    testWidgets('ends the intro at once, before or after the splash', (
      tester,
    ) async {
      final gone = await pumpIntro(tester);
      final page = tester.element(find.byType(Scaffold));
      LaunchLogoTarget.skipIntroOf(page);
      await tester.pump();
      expect(introOverlay, findsNothing);

      await releaseSplash(tester, gone);
      await tester.pump(const Duration(milliseconds: 100));
      expect(introOverlay, findsNothing);
    });

    testWidgets('mid-flight ends it too', (tester) async {
      final gone = await pumpIntro(tester);
      await releaseSplash(tester, gone);
      await tester.pump(launchIntroReveal + launchIntroFlight ~/ 2);
      expect(introOverlay, findsOneWidget);

      LaunchLogoTarget.skipIntroOf(tester.element(find.byType(Scaffold)));
      await tester.pump();
      expect(introOverlay, findsNothing);
    });

    testWidgets('outside an intro is a no-op', (tester) async {
      final context = await pumpContext(tester);
      LaunchLogoTarget.skipIntroOf(context);
      expect(tester.takeException(), isNull);
    });
  });

  test('a launch on a route of its own skips the intro; Home does not', () {
    expect(launchedOnDeepLink('/'), isFalse);
    expect(launchedOnDeepLink('/downloads'), isTrue);
    expect(launchedOnDeepLink('/player?uri=content%3A%2F%2Fx'), isTrue);
  });
}
