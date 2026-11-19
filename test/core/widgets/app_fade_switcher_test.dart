import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/widgets/app_fade_switcher.dart';

import 'widget_harness.dart';

class _Switch extends StatefulWidget {
  const _Switch({required this.onOld});

  final VoidCallback onOld;

  @override
  State<_Switch> createState() => _SwitchState();
}

class _SwitchState extends State<_Switch> {
  var _new = false;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextButton(
        onPressed: () => setState(() => _new = !_new),
        child: const Text('flip'),
      ),
      AppFadeSwitcher(
        child: _new
            ? const SizedBox(
                key: ValueKey('new'),
                width: 200,
                height: 48,
                child: Text('new'),
              )
            : SizedBox(
                key: const ValueKey('old'),
                width: 200,
                height: 48,
                child: TextButton(
                  onPressed: widget.onOld,
                  child: const Text('old'),
                ),
              ),
      ),
    ],
  );
}

double _opacityOf(WidgetTester tester, String text) => tester
    .widget<FadeTransition>(
      find
          .ancestor(of: find.text(text), matching: find.byType(FadeTransition))
          .first,
    )
    .opacity
    .value;

void main() {
  testWidgets('cross-fades: both children are up mid-way, then only the new', (
    tester,
  ) async {
    await tester.pumpWidget(themed(_Switch(onOld: () {})));
    await tester.tap(find.text('flip'));
    await tester.pump();
    await tester.pump(Motion.fast ~/ 2);

    expect(find.text('old'), findsOneWidget);
    expect(find.text('new'), findsOneWidget);
    expect(_opacityOf(tester, 'old'), inExclusiveRange(0, 1));
    expect(_opacityOf(tester, 'new'), inExclusiveRange(0, 1));

    await tester.pumpAndSettle();
    expect(find.text('old'), findsNothing);
    expect(_opacityOf(tester, 'new'), 1);
  });

  testWidgets('the outgoing child takes no taps and leaves semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var oldTaps = 0;
    await tester.pumpWidget(themed(_Switch(onOld: () => oldTaps++)));
    await tester.tap(find.text('old'));
    expect(oldTaps, 1);

    await tester.tap(find.text('flip'));
    await tester.pump();
    await tester.pump(Motion.fast ~/ 3);
    expect(find.text('old'), findsOneWidget);

    // A second tap where the old button still fades out.
    await tester.tap(find.text('old'), warnIfMissed: false);
    await tester.pump();
    expect(oldTaps, 1);
    final labels = [
      for (final node in tester.semantics.simulatedAccessibilityTraversal())
        node.label,
    ];
    expect(labels, isNot(contains('old')));
    expect(labels, contains('new'));
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets('the incoming child scales up from scaleFrom', (tester) async {
    await tester.pumpWidget(themed(_Switch(onOld: () {})));
    await tester.tap(find.text('flip'));
    await tester.pump();

    final scale = tester.widget<ScaleTransition>(
      find.ancestor(
        of: find.text('new'),
        matching: find.byType(ScaleTransition),
      ),
    );
    expect(scale.scale.value, closeTo(.98, .001));
    await tester.pumpAndSettle();
    expect(scale.scale.value, 1);
  });

  testWidgets(
    'sizeToIncoming: a Row neighbour resizes on the swap, not after',
    (tester) async {
      var wide = true;
      late StateSetter flip;
      await tester.pumpWidget(
        themed(
          Center(
            child: SizedBox(
              width: 300,
              child: StatefulBuilder(
                builder: (context, setState) {
                  flip = setState;
                  return Row(
                    children: [
                      const Expanded(
                        child: SizedBox(key: ValueKey('field'), height: 44),
                      ),
                      AppFadeSwitcher(
                        spec: Motion.fade,
                        alignment: Alignment.centerRight,
                        sizeToIncoming: true,
                        child: wide
                            ? const SizedBox(
                                key: ValueKey('wide'),
                                width: 88,
                                height: 42,
                              )
                            : const SizedBox(
                                key: ValueKey('narrow'),
                                width: 44,
                                height: 44,
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      double field() =>
          tester.getSize(find.byKey(const ValueKey('field'))).width;
      expect(field(), 300 - 88);

      flip(() => wide = false);
      await tester.pump();
      await tester.pump(Motion.fast ~/ 2);
      // Mid-fade: the wide child still paints, but the field already has room.
      expect(find.byKey(const ValueKey('wide')), findsOneWidget);
      expect(field(), 300 - 44);

      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('wide')), findsNothing);
      expect(field(), 300 - 44);
    },
  );

  testWidgets('reduce motion: the new child is there alone on the next frame', (
    tester,
  ) async {
    reduceMotion(tester);
    await tester.pumpWidget(themed(_Switch(onOld: () {})));
    await tester.tap(find.text('flip'));
    await tester.pump();
    await tester.pump();

    expect(find.text('old'), findsNothing);
    expect(_opacityOf(tester, 'new'), 1);
  });
}
