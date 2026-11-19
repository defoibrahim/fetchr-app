import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/widgets/loading_view.dart';

import 'widget_harness.dart';

double _opacity(WidgetTester tester) => tester
    .widget<FadeTransition>(
      find
          .ancestor(
            of: find.byType(CircularProgressIndicator),
            matching: find.byType(FadeTransition),
          )
          .first,
    )
    .opacity
    .value;

void main() {
  testWidgets('a fast load never shows the spinner', (tester) async {
    await pumpThemed(tester, const LoadingView());
    await tester.pump(const Duration(milliseconds: 150));
    expect(_opacity(tester), 0);
  });

  testWidgets('after 200 ms the spinner fades in over 150 ms', (tester) async {
    await pumpThemed(tester, const LoadingView());
    await tester.pump(Motion.spinnerDelay);
    expect(_opacity(tester), lessThan(.01));
    await tester.pump(const Duration(milliseconds: 75));
    expect(_opacity(tester), inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 80));
    expect(_opacity(tester), 1);
  });

  testWidgets('reduce motion: it still waits, then appears at once', (
    tester,
  ) async {
    reduceMotion(tester);
    await pumpThemed(tester, const LoadingView());
    await tester.pump(const Duration(milliseconds: 190));
    expect(_opacity(tester), 0);
    await tester.pump(const Duration(milliseconds: 20));
    expect(_opacity(tester), 1);
  });
}
