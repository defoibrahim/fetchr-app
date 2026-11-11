import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/widgets/error_view.dart';

import 'widget_harness.dart';

void main() {
  testWidgets('shows the message and calls onRetry when Retry is tapped', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      themed(ErrorView(message: 'Boom', onRetry: () => retries++)),
    );

    expect(find.text('Boom'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    expect(retries, 1);
  });

  testWidgets('hides Retry when there is no handler', (tester) async {
    await tester.pumpWidget(themed(const ErrorView(message: 'Boom')));

    expect(find.text('Boom'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
  });

  for (final entry in themes.entries) {
    testWidgets('tints the icon with the ${entry.key} error token', (
      tester,
    ) async {
      await tester.pumpWidget(
        themed(const ErrorView(message: 'Boom'), theme: entry.value),
      );

      final icon = tester.widget<Icon>(
        find.byIcon(Icons.error_outline_rounded),
      );
      expect(icon.color, entry.value.extension<AppTokens>()!.error);
    });
  }
}
