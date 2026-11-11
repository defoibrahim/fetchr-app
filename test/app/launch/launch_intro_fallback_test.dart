import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/launch/launch_intro.dart';
import 'package:grabby/core/logging/app_logger.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/home_header.dart';

import '../../support/fake_app.dart';
import '../../support/launch_intro_harness.dart';

void main() {
  tearDown(AppLogger.reset);

  group('when the native side never answers well', () {
    testWidgets('carries on after the timeout if it never completes', (
      tester,
    ) async {
      await pumpIntro(tester, splashGone: () => Completer<void>().future);

      await tester.pump(
        launchIntroSplashTimeout - const Duration(milliseconds: 1),
      );
      expect(tileRect(tester), introCentre, reason: 'still waiting');

      await tester.pump(const Duration(milliseconds: 2));
      await tester.pump();
      await tester.pump(launchIntroReveal + launchIntroFlight ~/ 2);
      expect(tileRect(tester).left, lessThan(introCentre.left));

      await tester.pumpAndSettle();
      expect(introOverlay, findsNothing);
    });

    testWidgets('carries on if the call fails', (tester) async {
      final lines = <String>[];
      AppLogger.overrideForTesting(sink: (_, message, _) => lines.add(message));
      await pumpIntro(
        tester,
        splashGone: () async => throw PlatformException(code: 'boom'),
      );

      await tester.pump();
      await tester.pump();
      await tester.pump(launchIntroReveal + launchIntroFlight ~/ 2);
      expect(tileRect(tester).left, lessThan(introCentre.left));
      expect(lines, isNotEmpty, reason: 'logged, not swallowed silently');

      await tester.pumpAndSettle();
      expect(introOverlay, findsNothing);
    });
  });

  testWidgets('on the real Home it lands on the header logo tile', (
    tester,
  ) async {
    final gone = Completer<void>();
    await pumpFakeApp(
      tester,
      builder: (context, child) =>
          LaunchIntro(splashGone: () => gone.future, child: child!),
    );

    final header = find.ancestor(
      of: find.descendant(of: find.byType(HomeHeader), matching: logoIcon),
      matching: find.byType(Container),
    );
    expect(tester.widget<Container>(header.first).key, isNotNull);
    final realTile = tester.getRect(header.first);
    expect(tileRect(tester), isNot(realTile));

    await releaseSplash(tester, gone);
    await tester.pump(launchIntroReveal + launchIntroFlight);
    final landed = tileRect(tester);
    expect(landed.left, closeTo(realTile.left, 0.01));
    expect(landed.top, closeTo(realTile.top, 0.01));
    expect(landed.size.width, closeTo(realTile.width, 0.01));

    await tester.pumpAndSettle();
    expect(introOverlay, findsNothing);
  });
}
