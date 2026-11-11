import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/widgets/app_progress_bar.dart';

import 'widget_harness.dart';

const trackWidth = 200.0;

Future<void> pumpBar(
  WidgetTester tester,
  ThemeData theme,
  AppProgressBar bar,
) async {
  useView(tester);
  await tester.pumpWidget(
    themed(
      Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: trackWidth, child: bar),
      ),
      theme: theme,
    ),
  );
}

final segmentPill = find.descendant(
  of: find.byType(FractionallySizedBox),
  matching: find.byType(DecoratedBox),
);

double fillFactor(WidgetTester tester) => tester
    .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
    .widthFactor!;

Color? fillColor(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find
        .descendant(
          of: find.byType(FractionallySizedBox),
          matching: find.byType(DecoratedBox),
        )
        .first,
  );
  return (box.decoration as BoxDecoration).color;
}

void main() {
  for (final entry in themes.entries) {
    final theme = entry.value;
    final tokens = theme.extension<AppTokens>()!;
    final scheme = theme.colorScheme;

    group(entry.key, () {
      testWidgets('is a 6 dp pill on the sunken track by default', (
        tester,
      ) async {
        await pumpBar(tester, theme, const AppProgressBar(value: .4));

        expect(tester.getSize(find.byType(AppProgressBar)).height, 6);
        final track = tester.widget<DecoratedBox>(
          find
              .descendant(
                of: find.byType(AppProgressBar),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        final decoration = track.decoration as BoxDecoration;
        expect(decoration.color, tokens.surfaceSunken);
        expect(decoration.borderRadius, BorderRadius.circular(999));
      });

      testWidgets('height is configurable', (tester) async {
        await pumpBar(
          tester,
          theme,
          const AppProgressBar(value: .4, height: 10),
        );

        expect(tester.getSize(find.byType(AppProgressBar)).height, 10);
      });

      testWidgets('the fill is a pill in the primary colour', (tester) async {
        await pumpBar(tester, theme, const AppProgressBar(value: .4));

        expect(fillColor(tester), scheme.primary);
        expect(fillFactor(tester), .4);
        final fill =
            tester
                    .widget<DecoratedBox>(
                      find.descendant(
                        of: find.byType(FractionallySizedBox),
                        matching: find.byType(DecoratedBox),
                      ),
                    )
                    .decoration
                as BoxDecoration;
        expect(fill.borderRadius, BorderRadius.circular(999));
      });

      testWidgets('colour overrides the fill', (tester) async {
        await pumpBar(
          tester,
          theme,
          AppProgressBar(value: .4, color: tokens.error),
        );

        expect(fillColor(tester), tokens.error);
      });

      testWidgets('the fill is as wide as the value', (tester) async {
        await pumpBar(tester, theme, const AppProgressBar(value: .64));

        final fill = find.descendant(
          of: find.byType(FractionallySizedBox),
          matching: find.byType(DecoratedBox),
        );
        expect(tester.getSize(fill).width, closeTo(.64 * trackWidth, .01));
      });

      testWidgets('values outside 0 to 1 are clamped', (tester) async {
        await pumpBar(tester, theme, const AppProgressBar(value: 1.7));
        expect(fillFactor(tester), 1);

        await pumpBar(tester, theme, const AppProgressBar(value: -.2));
        await tester.pumpAndSettle();
        expect(fillFactor(tester), 0);
      });

      testWidgets('the width tweens linearly over 250 ms', (tester) async {
        await pumpBar(tester, theme, const AppProgressBar(value: .2));
        await pumpBar(tester, theme, const AppProgressBar(value: .8));

        expect(fillFactor(tester), closeTo(.2, .001));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 125));
        expect(fillFactor(tester), closeTo(.5, .02));
        await tester.pump(const Duration(milliseconds: 125));
        expect(fillFactor(tester), closeTo(.8, .001));
      });

      testWidgets('reduce motion jumps straight to the value', (tester) async {
        reduceMotion(tester);
        await pumpBar(tester, theme, const AppProgressBar(value: .2));
        await pumpBar(tester, theme, const AppProgressBar(value: .8));
        await tester.pump();

        expect(fillFactor(tester), .8);
      });

      testWidgets('exposes the percentage and the label', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpBar(tester, theme, const AppProgressBar(value: .64));

        final node = tester.getSemantics(find.byType(AppProgressBar));
        expect(node.label, 'Download progress');
        expect(node.value, '64%');
        handle.dispose();
      });

      testWidgets('rounds the percentage', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpBar(tester, theme, const AppProgressBar(value: .3349));

        expect(tester.getSemantics(find.byType(AppProgressBar)).value, '33%');
        handle.dispose();
      });

      testWidgets('takes a custom semantics label', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpBar(
          tester,
          theme,
          const AppProgressBar(
            value: .5,
            semanticsLabel: 'Merging video and audio',
          ),
        );

        expect(
          tester.getSemantics(find.byType(AppProgressBar)).label,
          'Merging video and audio',
        );
        handle.dispose();
      });

      group('indeterminate', () {
        testWidgets('is a 40% segment with no percentage', (tester) async {
          final handle = tester.ensureSemantics();
          await pumpBar(tester, theme, const AppProgressBar());

          expect(fillFactor(tester), .4);
          expect(fillColor(tester), scheme.primary);
          final node = tester.getSemantics(find.byType(AppProgressBar));
          expect(node.label, 'Download progress');
          expect(node.value, isEmpty);
          handle.dispose();
        });

        testWidgets('is a segment 40% of the track wide', (tester) async {
          await pumpBar(tester, theme, const AppProgressBar());

          expect(
            tester.getSize(segmentPill).width,
            closeTo(.4 * trackWidth, .01),
          );
          await tester.pump(const Duration(milliseconds: 700));
          expect(
            tester.getSize(segmentPill).width,
            closeTo(.4 * trackWidth, .01),
          );
        });

        testWidgets('travels from off the left edge to off the right edge', (
          tester,
        ) async {
          await pumpBar(tester, theme, const AppProgressBar());
          Rect pill() => tester.getRect(segmentPill);

          // t = 0: the segment's right edge is on the track's left edge.
          expect(pill().right, closeTo(0, .01));
          // t = .5 (easeInOut is symmetric): centred on the track.
          await tester.pump(const Duration(milliseconds: 700));
          expect(pill().center.dx, closeTo(trackWidth / 2, .01));
          // t = 1: its left edge is on the track's right edge.
          await tester.pump(const Duration(milliseconds: 699));
          expect(pill().left, closeTo(trackWidth, 1));
        });

        testWidgets('slides left to right and loops every 1400 ms', (
          tester,
        ) async {
          await pumpBar(tester, theme, const AppProgressBar());
          double left() => tester.getTopLeft(segmentPill).dx;

          final start = left();
          expect(start, lessThan(0));

          await tester.pump(const Duration(milliseconds: 700));
          final middle = left();
          expect(middle, greaterThan(start));

          await tester.pump(const Duration(milliseconds: 600));
          expect(left(), greaterThan(middle));
          expect(left(), greaterThan(trackWidth * .9));

          // 100 ms into the next pass it is back off the left edge.
          await tester.pump(const Duration(milliseconds: 200));
          expect(left(), lessThan(0));
        });

        testWidgets('never leaves the track', (tester) async {
          await pumpBar(tester, theme, const AppProgressBar());

          expect(
            find.descendant(
              of: find.byType(AppProgressBar),
              matching: find.byType(ClipRRect),
            ),
            findsOneWidget,
          );
        });

        testWidgets('stays at the left under reduce motion', (tester) async {
          reduceMotion(tester);
          await pumpBar(tester, theme, const AppProgressBar());
          final start = tester.getTopLeft(segmentPill).dx;

          await tester.pump(const Duration(milliseconds: 700));

          expect(tester.hasRunningAnimations, isFalse);
          expect(tester.getTopLeft(segmentPill).dx, start);
          expect(start, greaterThanOrEqualTo(0));
        });

        testWidgets('holds at the left when reduce motion comes on', (
          tester,
        ) async {
          await pumpBar(tester, theme, const AppProgressBar());
          await tester.pump(const Duration(milliseconds: 700));
          expect(tester.hasRunningAnimations, isTrue);

          reduceMotion(tester);
          await tester.pump();

          expect(tester.hasRunningAnimations, isFalse);
          expect(tester.getTopLeft(segmentPill).dx, greaterThanOrEqualTo(0));
        });

        testWidgets('stops animating once a value arrives', (tester) async {
          await pumpBar(tester, theme, const AppProgressBar());
          await pumpBar(tester, theme, const AppProgressBar(value: .5));
          await tester.pumpAndSettle();

          expect(fillFactor(tester), .5);
          expect(tester.hasRunningAnimations, isFalse);
        });
      });
    });
  }
}
