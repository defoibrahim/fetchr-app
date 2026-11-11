import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/utils/scale.dart';

import '../widgets/widget_harness.dart';

void main() {
  Future<void> pumpAt(WidgetTester tester, Size size) async {
    useView(tester, size);
    await pumpContext(tester);
  }

  testWidgets('a phone scales by its width and height', (tester) async {
    await pumpAt(tester, const Size(390, 844));

    expect(100.w, closeTo(100 * 390 / 375, 1e-9));
    expect(100.h, closeTo(100 * 844 / 812, 1e-9));
    // The smaller of the two ratios.
    expect(100.r, closeTo(100 * 844 / 812, 1e-9));
    expect(100.sp, closeTo(100 * 390 / 375, 1e-9));
  });

  testWidgets('599 dp still scales', (tester) async {
    await pumpAt(tester, const Size(599, 1000));

    expect(100.w, closeTo(100 * 599 / 375, 1e-9));
  });

  for (final width in [600.0, 700.0, 900.0, 1280.0]) {
    testWidgets('${width.round()} dp is the design values', (tester) async {
      await pumpAt(tester, Size(width, 1000));

      expect(100.w, 100);
      expect(100.h, 100);
      expect(100.r, 100);
      expect(100.sp, 100);
    });
  }

  testWidgets('a resize across 600 dp flips it', (tester) async {
    await pumpAt(tester, const Size(700, 1000));
    expect(100.w, 100);

    useView(tester, const Size(390, 844));
    await tester.pump();
    expect(100.w, closeTo(100 * 390 / 375, 1e-9));

    useView(tester, const Size(900, 1000));
    await tester.pump();
    expect(100.w, 100);
  });

  testWidgets('a landscape phone follows its width, not its height', (
    tester,
  ) async {
    await pumpAt(tester, const Size(844, 390));

    expect(100.w, 100);
    expect(100.h, 100);
  });
}
