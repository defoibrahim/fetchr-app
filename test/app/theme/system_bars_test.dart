import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/theme/system_bars.dart';
import 'package:grabby/core/logging/app_logger.dart';

import '../../core/widgets/widget_harness.dart';

SystemUiOverlayStyle _style(WidgetTester tester) => tester
    .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.descendant(
        of: find.byType(SystemBars),
        matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
      ),
    )
    .value;

void main() {
  tearDown(AppLogger.reset);

  group('SystemBars', () {
    testWidgets('dark: light icons on transparent bars', (tester) async {
      await pumpThemed(tester, const SystemBars(child: Text('page')));
      final style = _style(tester);
      expect(style.statusBarColor, Colors.transparent);
      expect(style.statusBarIconBrightness, Brightness.light);
      expect(style.systemNavigationBarColor, Colors.transparent);
      expect(style.systemNavigationBarIconBrightness, Brightness.light);
    });

    testWidgets('light: dark icons on transparent bars', (tester) async {
      await pumpThemed(
        tester,
        const SystemBars(child: Text('page')),
        brightness: Brightness.light,
      );
      final style = _style(tester);
      expect(style.statusBarColor, Colors.transparent);
      expect(style.statusBarIconBrightness, Brightness.dark);
      expect(style.systemNavigationBarColor, Colors.transparent);
      expect(style.systemNavigationBarIconBrightness, Brightness.dark);
    });

    testWidgets('lets the bars show their own colour, not a system scrim', (
      tester,
    ) async {
      await pumpThemed(tester, const SystemBars(child: Text('page')));

      final style = _style(tester);
      expect(style.systemStatusBarContrastEnforced, isFalse);
      expect(style.systemNavigationBarContrastEnforced, isFalse);
      expect(style.systemNavigationBarDividerColor, Colors.transparent);
    });

    testWidgets('follows the theme when it changes', (tester) async {
      await pumpThemed(tester, const SystemBars(child: Text('page')));
      expect(_style(tester).statusBarIconBrightness, Brightness.light);

      await pumpThemed(
        tester,
        const SystemBars(child: Text('page')),
        brightness: Brightness.light,
      );
      await tester.pumpAndSettle();

      expect(_style(tester).statusBarIconBrightness, Brightness.dark);
    });

    testWidgets('shows its child', (tester) async {
      await pumpThemed(tester, const SystemBars(child: Text('page')));

      expect(find.text('page'), findsOneWidget);
    });
  });

  group('enableEdgeToEdge', () {
    final calls = <MethodCall>[];

    void answer(WidgetTester tester, Future<Object?> Function() reply) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) {
          calls.add(call);
          return reply();
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
    }

    setUp(calls.clear);

    testWidgets('asks the platform for the edge-to-edge UI mode', (
      tester,
    ) async {
      answer(tester, () async => null);

      await enableEdgeToEdge();

      expect(
        calls.map((c) => (c.method, c.arguments)),
        contains((
          'SystemChrome.setEnabledSystemUIMode',
          'SystemUiMode.edgeToEdge',
        )),
      );
    });

    testWidgets('logs a platform failure and does not throw', (tester) async {
      final lines = <String>[];
      AppLogger.overrideForTesting(sink: (_, message, _) => lines.add(message));
      answer(tester, () async => throw PlatformException(code: 'boom'));

      await enableEdgeToEdge();

      expect(lines.single, startsWith('Could not go edge to edge'));
    });
  });
}
