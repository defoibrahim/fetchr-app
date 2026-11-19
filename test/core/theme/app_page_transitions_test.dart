import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/theme/app_page_transitions.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/utils/scale.dart';

import '../widgets/widget_harness.dart';

final _navigator = GlobalKey<NavigatorState>();

Future<void> _pump(WidgetTester tester) => tester.pumpWidget(
  ScaleScope(
    child: MaterialApp(
      navigatorKey: _navigator,
      theme: AppTheme.light(),
      home: const Text('first'),
    ),
  ),
);

void _push() => _navigator.currentState!.push(
  MaterialPageRoute<void>(builder: (_) => const Text('second')),
);

void main() {
  test('Android and iOS keep their own transition, wrapped', () {
    final builders = AppTheme.light().pageTransitionsTheme.builders;
    final android =
        builders[TargetPlatform.android]! as ReduceMotionPageTransitionsBuilder;
    final ios =
        builders[TargetPlatform.iOS]! as ReduceMotionPageTransitionsBuilder;
    expect(android.builder, isA<PredictiveBackPageTransitionsBuilder>());
    expect(ios.builder, isA<CupertinoPageTransitionsBuilder>());
    expect(AppTheme.dark().pageTransitionsTheme, AppPageTransitions.theme);
  });

  testWidgets('a push animates over the platform transition', (tester) async {
    await _pump(tester);
    _push();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Both pages are up mid-transition.
    expect(find.text('first'), findsOneWidget);
    expect(find.text('second'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('first'), findsNothing);
  });

  testWidgets('reduce motion: a push and a pop land on the next frame', (
    tester,
  ) async {
    reduceMotion(tester);
    await _pump(tester);
    _push();
    await tester.pump();
    await tester.pump();
    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsOneWidget);

    _navigator.currentState!.pop();
    await tester.pump();
    await tester.pump();
    expect(find.text('second'), findsNothing);
    expect(find.text('first'), findsOneWidget);
  });

  test('reduce motion zeroes the durations the route reads', () {
    const builder = ReduceMotionPageTransitionsBuilder(
      PredictiveBackPageTransitionsBuilder(),
    );
    expect(builder.transitionDuration, greaterThan(Duration.zero));
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(binding.platformDispatcher.clearAccessibilityFeaturesTestValue);
    expect(builder.transitionDuration, Duration.zero);
    expect(builder.reverseTransitionDuration, Duration.zero);
  });

  test('Android 13 to 15 send back swipes as predictive back events', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    expect(manifest, contains('android:enableOnBackInvokedCallback="true"'));
  });

  testWidgets('reduce motion keeps the platform back swipe (iOS edge drag)', (
    tester,
  ) async {
    reduceMotion(tester);
    await tester.pumpWidget(
      ScaleScope(
        child: MaterialApp(
          navigatorKey: _navigator,
          theme: AppTheme.light().copyWith(platform: TargetPlatform.iOS),
          home: const Scaffold(body: Text('first')),
        ),
      ),
    );
    _navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Center(child: Text('second'))),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('second'), findsOneWidget);

    final gesture = await tester.startGesture(const Offset(5, 300));
    // Past half the 800 dp test window, so the swipe commits.
    await gesture.moveBy(const Offset(200, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(400, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('second'), findsNothing);
    expect(find.text('first'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
