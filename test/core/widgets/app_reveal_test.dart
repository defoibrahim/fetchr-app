import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/widgets/app_reveal.dart';

import 'widget_harness.dart';

const _box = SizedBox(width: 100, height: 40, child: Text('card'));

Widget _reveal(bool visible, {Widget child = _box}) => themed(
  Align(
    alignment: Alignment.topLeft,
    child: AppReveal(child: visible ? child : null),
  ),
);

double _opacity(WidgetTester tester) => tester
    .widget<FadeTransition>(
      find.descendant(
        of: find.byType(AppReveal),
        matching: find.byType(FadeTransition),
      ),
    )
    .opacity
    .value;

double _height(WidgetTester tester) =>
    tester.getSize(find.byType(AppReveal)).height;

void main() {
  testWidgets('a visible child grows and fades in on mount', (tester) async {
    await tester.pumpWidget(_reveal(true));
    expect(_height(tester), 0);

    await tester.pump(Motion.reveal.duration ~/ 2);
    expect(_opacity(tester), inExclusiveRange(0, 1));
    expect(_height(tester), inExclusiveRange(0, 40));

    await tester.pumpAndSettle();
    expect(_opacity(tester), 1);
    expect(_height(tester), 40);
  });

  Future<void> shown(WidgetTester tester) async {
    await tester.pumpWidget(_reveal(true));
    await tester.pumpAndSettle();
  }

  testWidgets('hiding keeps the last child while it leaves, then drops it', (
    tester,
  ) async {
    await shown(tester);
    await tester.pumpWidget(_reveal(false));
    await tester.pump(Motion.reveal.reverseDuration! ~/ 2);

    expect(find.text('card'), findsOneWidget);
    expect(_opacity(tester), inExclusiveRange(0, 1));

    await tester.pumpAndSettle();
    expect(find.text('card'), findsNothing);
    expect(_height(tester), 0);
  });

  testWidgets('the exit is shorter than the entry', (tester) async {
    expect(Motion.reveal.reverseDuration!, lessThan(Motion.reveal.duration));
    await shown(tester);
    await tester.pumpWidget(_reveal(false));
    // The first frame starts the clock.
    await tester.pump();
    // A simulation is done only past its duration.
    await tester.pump(
      Motion.reveal.reverseDuration! + const Duration(milliseconds: 1),
    );
    // The frame after the exit drops the kept child.
    await tester.pump();
    expect(find.text('card'), findsNothing);
  });

  testWidgets('it rises into place from 8 dp below', (tester) async {
    useView(tester);
    await tester.pumpWidget(_reveal(true));
    await tester.pump();
    final start = tester.getTopLeft(find.text('card')).dy;
    await tester.pumpAndSettle();
    final end = tester.getTopLeft(find.text('card')).dy;
    expect(start - end, closeTo(8, .5));
  });

  testWidgets('a hidden child takes no room and builds nothing', (
    tester,
  ) async {
    await tester.pumpWidget(_reveal(false));
    expect(find.text('card'), findsNothing);
    expect(_height(tester), 0);
  });

  testWidgets('reduce motion: shown and hidden on the next frame', (
    tester,
  ) async {
    reduceMotion(tester);
    await tester.pumpWidget(_reveal(true));
    expect(_opacity(tester), 1);
    expect(_height(tester), 40);

    await tester.pumpWidget(_reveal(false));
    await tester.pump();
    expect(find.text('card'), findsNothing);
  });

  group('leaving', () {
    testWidgets('takes no taps and leaves the semantics tree', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_reveal(true));
      await tester.pumpAndSettle();
      expect(find.text('card').hitTestable(), findsOneWidget);
      await tester.pumpWidget(_reveal(false));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('card'), findsOneWidget);
      expect(find.text('card').hitTestable(), findsNothing);
      expect([
        for (final node in tester.semantics.simulatedAccessibilityTraversal())
          node.label,
      ], isNot(contains('card')));
      await tester.pumpAndSettle();
      semantics.dispose();
    });

    testWidgets('gives up focus', (tester) async {
      final focus = FocusNode();
      addTearDown(focus.dispose);
      final button = TextButton(
        focusNode: focus,
        onPressed: () {},
        child: const Text('card'),
      );
      await tester.pumpWidget(_reveal(true, child: button));
      await tester.pumpAndSettle();
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      await tester.pumpWidget(_reveal(false, child: button));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('card'), findsOneWidget);
      expect(focus.hasFocus, isFalse);
      await tester.pumpAndSettle();
    });
  });
}
