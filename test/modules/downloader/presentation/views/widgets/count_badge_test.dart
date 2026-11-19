import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/downloads_badge.dart';

import '../../../../../core/widgets/widget_harness.dart';

Future<void> _pump(WidgetTester tester, int count) =>
    pumpThemed(tester, Center(child: CountBadge(count: count)));

// The outer scale is presence (pop in, shrink out); the inner one the bump.
double _presence(WidgetTester tester) => tester
    .widgetList<ScaleTransition>(find.byType(ScaleTransition))
    .first
    .scale
    .value;

double _bump(WidgetTester tester) => tester
    .widgetList<ScaleTransition>(find.byType(ScaleTransition))
    .elementAt(1)
    .scale
    .value;

void main() {
  testWidgets('a count there from the start shows without a pop', (
    tester,
  ) async {
    await _pump(tester, 3);
    expect(find.text('3'), findsOneWidget);
    expect(_presence(tester), 1);
  });

  testWidgets('the first task pops the badge in over 250 ms', (tester) async {
    await _pump(tester, 0);
    expect(find.byType(Text), findsNothing);
    await _pump(tester, 1);
    await tester.pump(const Duration(milliseconds: 50));
    expect(_presence(tester), inExclusiveRange(0, 1));
    // The pop overshoots before it settles.
    var peak = 0.0;
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      peak = peak > _presence(tester) ? peak : _presence(tester);
    }
    expect(peak, greaterThan(1));
    await tester.pumpAndSettle();
    expect(_presence(tester), 1);
  });

  testWidgets('a rise bumps it to 1.2 and back; the number cross-fades', (
    tester,
  ) async {
    await _pump(tester, 1);
    await _pump(tester, 2);
    var peak = 1.0;
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      peak = peak > _bump(tester) ? peak : _bump(tester);
      if (i == 5) {
        expect(find.text('1'), findsOneWidget);
        expect(find.text('2'), findsOneWidget);
      }
    }
    expect(peak, closeTo(1.2, .03));
    await tester.pumpAndSettle();
    expect(_bump(tester), 1);
    expect(find.text('1'), findsNothing);
  });

  testWidgets('a fall cross-fades without a bump', (tester) async {
    await _pump(tester, 3);
    await _pump(tester, 2);
    await tester.pump(const Duration(milliseconds: 60));
    expect(_bump(tester), 1);
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('at zero it shrinks away with its last number, then is gone', (
    tester,
  ) async {
    await _pump(tester, 2);
    await _pump(tester, 0);
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('2'), findsOneWidget);
    expect(_presence(tester), inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('shows 9+ above nine', (tester) async {
    await _pump(tester, 12);
    expect(find.text('9+'), findsOneWidget);
  });

  testWidgets('reduce motion: no pop, no bump, gone at once', (tester) async {
    reduceMotion(tester);
    await _pump(tester, 0);
    await _pump(tester, 1);
    await tester.pump();
    expect(_presence(tester), 1);
    await _pump(tester, 2);
    await tester.pump();
    expect(_bump(tester), 1);
    await _pump(tester, 0);
    await tester.pump();
    await tester.pump();
    expect(find.byType(Text), findsNothing);
  });

  test('the bump lasts 220 ms', () {
    expect(CountBadge.bump, const Duration(milliseconds: 220));
    expect(Motion.medium, const Duration(milliseconds: 250));
  });
}
