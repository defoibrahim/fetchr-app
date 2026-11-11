import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/utils/scale.dart';

import 'widget_harness.dart';

void main() {
  testWidgets('useView defaults to the design size, so screenutil is 1', (
    tester,
  ) async {
    useView(tester);
    await pumpContext(tester);

    expect(100.w, 100);
    expect(100.h, 100);
    expect(100.r, 100);
  });

  testWidgets('pumpThemed takes brightness, accent, size and text scale', (
    tester,
  ) async {
    await pumpThemed(
      tester,
      const SizedBox(),
      brightness: Brightness.light,
      accent: AppPalette.accents[1].color,
      size: const Size(320, 640),
      textScale: 1.3,
    );
    final context = tester.element(find.byType(Scaffold));

    expect(Theme.of(context).brightness, Brightness.light);
    expect(context.tokens.accent, AppPalette.accents[1].color);
    expect(MediaQuery.sizeOf(context), const Size(320, 640));
    expect(MediaQuery.textScalerOf(context).scale(10), closeTo(13, 1e-9));
  });

  testWidgets('reduceMotion turns on disableAnimations for the test', (
    tester,
  ) async {
    final context = await pumpContext(tester);
    expect(MediaQuery.disableAnimationsOf(context), isFalse);

    reduceMotion(tester);
    await tester.pump();

    expect(MediaQuery.disableAnimationsOf(context), isTrue);
  });
}
