// Shared by the launch intro tests: a window, a stand-in for the Home
// header's tile, and finders for the overlay's parts.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/launch/launch_intro.dart';
import 'package:grabby/app/shared/launch_logo_target.dart';
import 'package:grabby/core/gen/assets.gen.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/utils/scale.dart';
import 'package:grabby/core/widgets/app_icon.dart';

import '../core/widgets/widget_harness.dart';

const introWindow = Size(390, 844);
final introCentre = Rect.fromCenter(
  center: const Offset(195, 422),
  width: 120,
  height: 120,
);
const introTarget = Rect.fromLTWH(20, 60, 30, 30);

final introOverlay = find.byKey(launchIntroOverlayKey);
final introTile = find.descendant(
  of: introOverlay,
  matching: find.byType(DecoratedBox),
);
final logoIcon = find.byWidgetPredicate(
  (w) => w is AppIcon && w.icon == Assets.icons.logo,
);

Rect tileRect(WidgetTester tester) => tester.getRect(introTile);

/// A stand-in for the Home header's tile.
class IntroTargetTile extends StatelessWidget {
  const IntroTargetTile({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    key: LaunchLogoTarget.keyOf(context),
    width: introTarget.width,
    height: introTarget.height,
  );
}

class IntroPage extends StatefulWidget {
  const IntroPage({super.key, this.withTarget = true});

  final bool withTarget;

  @override
  State<IntroPage> createState() => _IntroPageState();
}

class _IntroPageState extends State<IntroPage> {
  int taps = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Stack(
      children: [
        if (widget.withTarget)
          Positioned(
            left: introTarget.left,
            top: introTarget.top,
            child: const IntroTargetTile(),
          ),
        Align(
          alignment: Alignment.bottomCenter,
          child: TextButton(
            onPressed: () => setState(() => taps++),
            child: Text('taps $taps'),
          ),
        ),
      ],
    ),
  );
}

/// Pumps a [LaunchIntro] over [page] on a window of [introWindow]. The page's
/// theme is [theme] and the system's brightness is [platform], so a test can
/// tell which of the two the intro follows. Without [splashGone] the intro
/// waits on the returned completer.
Future<Completer<void>> pumpIntro(
  WidgetTester tester, {
  Future<void> Function()? splashGone,
  Widget page = const IntroPage(),
  Brightness platform = Brightness.light,
  ThemeData? theme,
}) async {
  final gone = Completer<void>();
  useView(tester, introWindow);
  tester.platformDispatcher.platformBrightnessTestValue = platform;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  await tester.pumpWidget(
    ScaleScope(
      child: MaterialApp(
        theme: theme ?? AppTheme.dark(),
        builder: (context, child) => LaunchIntro(
          splashGone: splashGone ?? () => gone.future,
          child: child!,
        ),
        home: page,
      ),
    ),
  );
  return gone;
}

/// Lets a completed future reach the intro, then draws the frame that starts
/// its animation.
Future<void> releaseSplash(WidgetTester tester, Completer<void> gone) async {
  gone.complete();
  await tester.pump();
  await tester.pump();
}

Future<void> releaseAndSettle(WidgetTester tester, Completer<void> gone) async {
  await releaseSplash(tester, gone);
  await tester.pumpAndSettle();
}
