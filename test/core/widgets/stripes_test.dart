import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/widgets/stripes.dart';

import 'widget_harness.dart';

void main() {
  for (final MapEntry(key: mode, value: theme) in themes.entries) {
    final tokens = theme.extension<AppTokens>()!;

    testWidgets('$mode: bands alternate stripeA and stripeB', (tester) async {
      await tester.pumpWidget(
        themed(
          const Center(
            child: SizedBox(width: 84, height: 48, child: Stripes()),
          ),
          theme: theme,
        ),
      );

      final paint = find.descendant(
        of: find.byType(Stripes),
        matching: find.byType(CustomPaint),
      );
      expect(
        tester.renderObject(paint),
        paints
          ..clipRect()
          ..rect(color: tokens.stripeA)
          ..rect(color: tokens.stripeB)
          ..rect(color: tokens.stripeA),
      );
    });
  }

  testWidgets('fills the box it is given', (tester) async {
    await tester.pumpWidget(
      themed(
        const Center(child: SizedBox(width: 120, height: 70, child: Stripes())),
      ),
    );

    expect(tester.getSize(find.byType(Stripes)), const Size(120, 70));
  });
}
