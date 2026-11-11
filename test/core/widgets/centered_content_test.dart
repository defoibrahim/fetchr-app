import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/widgets/centered_content.dart';

import 'widget_harness.dart';

void main() {
  const body = Key('body');

  Future<void> pumpBody(WidgetTester tester, Size size) async {
    useView(tester, size);
    await tester.pumpWidget(
      themed(
        const CenteredContent(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [SizedBox(key: body, height: 40)],
          ),
        ),
      ),
    );
  }

  testWidgets('caps the page at 560 and centres it from 600 dp', (
    tester,
  ) async {
    await pumpBody(tester, const Size(700, 1000));

    final rect = tester.getRect(find.byKey(body));
    expect(rect.width, 560);
    expect(rect.center.dx, 350);
    expect(rect.top, 0);
  });

  testWidgets('leaves a window of 840 dp and more at 560 too', (tester) async {
    await pumpBody(tester, const Size(900, 1000));

    final rect = tester.getRect(find.byKey(body));
    expect(rect.width, 560);
    expect(rect.center.dx, 450);
  });

  for (final width in [599.0, 390.0]) {
    testWidgets(
      '${width.round()} dp: adds no inset, the page fills the window',
      (tester) async {
        await pumpBody(tester, Size(width, 800));

        final rect = tester.getRect(find.byKey(body));
        expect(rect.left, 0);
        expect(rect.width, width);
      },
    );
  }

  testWidgets('centres in the room beside a rail, not in the window', (
    tester,
  ) async {
    useView(tester, const Size(700, 1000));
    await tester.pumpWidget(
      themed(
        const Row(
          children: [
            SizedBox(width: 100),
            Expanded(
              child: CenteredContent(child: SizedBox(key: body, height: 40)),
            ),
          ],
        ),
      ),
    );

    final rect = tester.getRect(find.byKey(body));
    expect(rect.left, 100 + 20);
    expect(rect.width, 560);
  });

  testWidgets('adds no inset when the width is unbounded', (tester) async {
    useView(tester, const Size(700, 1000));
    await tester.pumpWidget(
      themed(
        const SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: CenteredContent(
            child: SizedBox(key: body, width: 300, height: 40),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.byKey(body)).left, 0);
  });

  testWidgets('keeps the child State when the window crosses 600 dp', (
    tester,
  ) async {
    useView(tester, const Size(599, 800));
    await tester.pumpWidget(
      themed(
        CenteredContent(
          child: StatefulBuilder(
            key: body,
            builder: (_, _) => const SizedBox(width: double.infinity),
          ),
        ),
      ),
    );
    final state = tester.state(find.byKey(body));

    for (final width in [700.0, 599.0]) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pump();

      expect(tester.state(find.byKey(body)), same(state), reason: '$width dp');
    }
  });
}
