import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/widgets/app_pressable.dart';

import 'widget_harness.dart';

Widget _pressable({VoidCallback? onTap, VoidCallback? onLongPress}) => themed(
  Center(
    child: AppPressable(
      onTap: onTap ?? () {},
      onLongPress: onLongPress,
      pressedScale: .9,
      child: const SizedBox(width: 120, height: 80, child: Text('tile')),
    ),
  ),
);

double _scale(WidgetTester tester) =>
    tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

void main() {
  testWidgets('shrinks while held and springs back on release', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_pressable(onTap: () => taps++));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('tile')),
    );
    await tester.pump(kPressTimeout);
    expect(_scale(tester), .9);
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).duration,
      Motion.press,
    );

    await gesture.up();
    await tester.pump();
    expect(taps, 1);
    expect(_scale(tester), 1);
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).duration,
      Motion.fast,
    );
    await tester.pumpAndSettle();
  });

  testWidgets('a long press calls onLongPress, not onTap', (tester) async {
    var taps = 0;
    var longPresses = 0;
    await tester.pumpWidget(
      _pressable(onTap: () => taps++, onLongPress: () => longPresses++),
    );
    await tester.longPress(find.text('tile'));
    await tester.pumpAndSettle();
    expect(longPresses, 1);
    expect(taps, 0);
  });

  testWidgets('the ripple is on: an InkWell with feedback enabled', (
    tester,
  ) async {
    await tester.pumpWidget(_pressable());
    final ink = tester.widget<InkWell>(find.byType(InkWell));
    expect(ink.enableFeedback, isTrue);
  });

  testWidgets('reduce motion: no scale, the tap still lands', (tester) async {
    reduceMotion(tester);
    var taps = 0;
    await tester.pumpWidget(_pressable(onTap: () => taps++));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('tile')),
    );
    await tester.pump(kPressTimeout);
    expect(_scale(tester), 1);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  group('inkAbove', () {
    Widget above({required VoidCallback onTap, required VoidCallback onDots}) =>
        themed(
          Center(
            child: AppPressable(
              onTap: onTap,
              inkAbove: true,
              foreground: Align(
                alignment: Alignment.topRight,
                child: TextButton(onPressed: onDots, child: const Text('dots')),
              ),
              child: const ColoredBox(
                color: Colors.black,
                child: SizedBox(width: 200, height: 120),
              ),
            ),
          ),
        );

    testWidgets('the ink sits over the child, the foreground over the ink', (
      tester,
    ) async {
      await tester.pumpWidget(above(onTap: () {}, onDots: () {}));
      final stack = tester.widget<Stack>(
        find
            .descendant(
              of: find.byType(AppPressable),
              matching: find.byType(Stack),
            )
            .first,
      );
      expect(stack.children, hasLength(3));
      expect(
        find.descendant(
          of: find.byWidget(stack.children[1]),
          matching: find.byType(InkWell),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a tap on the picture goes to onTap, on the dots to them', (
      tester,
    ) async {
      final log = <String>[];
      await tester.pumpWidget(
        above(onTap: () => log.add('tile'), onDots: () => log.add('dots')),
      );
      await tester.tap(find.byType(AppPressable));
      await tester.tap(find.text('dots'));
      await tester.pumpAndSettle();
      expect(log, ['tile', 'dots']);
    });

    testWidgets('the ink layer adds no semantics of its own', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(above(onTap: () {}, onDots: () {}));
      final ink = tester.widget<InkWell>(
        find
            .descendant(
              of: find.byType(AppPressable),
              matching: find.byType(InkWell),
            )
            .first,
      );
      expect(ink.excludeFromSemantics, isTrue);
      semantics.dispose();
    });
  });
}
