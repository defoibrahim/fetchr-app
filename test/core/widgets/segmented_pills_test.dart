import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/utils/scale.dart';
import 'package:grabby/core/widgets/segmented_pills.dart';

import 'widget_harness.dart';

const qualities = [
  ('best', 'Best'),
  ('1080', '1080p'),
  ('720', '720p'),
  ('480', '480p'),
  ('mp3', 'MP3'),
];

Future<void> pumpPills(
  WidgetTester tester,
  ThemeData theme, {
  String selected = '1080',
  ValueChanged<String>? onChanged,
  double height = 40,
  double trackRadius = 12,
  double pillRadius = 9,
  bool mono = false,
  Color? trackColor,
  String? semanticLabel,
  Size size = designSize,
}) async {
  useView(tester, size);
  await tester.pumpWidget(
    themed(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: SegmentedPills<String>(
          items: qualities,
          selected: selected,
          onChanged: onChanged ?? (_) {},
          height: height,
          trackRadius: trackRadius,
          pillRadius: pillRadius,
          mono: mono,
          trackColor: trackColor,
          semanticLabel: semanticLabel,
        ),
      ),
      theme: theme,
    ),
  );
}

Material pillOf(WidgetTester tester, String label) => tester.widget<Material>(
  find.ancestor(of: find.text(label), matching: find.byType(Material)).first,
);

TextStyle labelStyle(WidgetTester tester, String label) => tester
    .widget<AnimatedDefaultTextStyle>(
      find
          .ancestor(
            of: find.text(label),
            matching: find.byType(AnimatedDefaultTextStyle),
          )
          .first,
    )
    .style;

void main() {
  for (final entry in themes.entries) {
    final theme = entry.value;
    final tokens = theme.extension<AppTokens>()!;
    final scheme = theme.colorScheme;

    group(entry.key, () {
      testWidgets('shows one pill per item and reports the tapped value', (
        tester,
      ) async {
        final taps = <String>[];
        await pumpPills(tester, theme, onChanged: taps.add);

        for (final (_, label) in qualities) {
          expect(find.text(label), findsOneWidget);
        }
        await tester.tap(find.text('720p'));
        await tester.tap(find.text('MP3'));

        expect(taps, ['720', 'mp3']);
      });

      testWidgets('the selected pill is a primary fill with onPrimary text', (
        tester,
      ) async {
        await pumpPills(tester, theme);

        expect(pillOf(tester, '1080p').color, scheme.primary);
        expect(labelStyle(tester, '1080p').color, scheme.onPrimary);
      });

      testWidgets('unselected pills are clear with muted text', (tester) async {
        await pumpPills(tester, theme);

        for (final label in ['Best', '720p', '480p', 'MP3']) {
          expect(pillOf(tester, label).color!.a, 0);
          expect(labelStyle(tester, label).color, tokens.textMuted);
        }
      });

      testWidgets('selection cross-fades over 150 ms', (tester) async {
        await pumpPills(tester, theme);

        expect(
          pillOf(tester, '720p').animationDuration,
          const Duration(milliseconds: 150),
        );
        expect(
          tester
              .widget<AnimatedDefaultTextStyle>(
                find
                    .ancestor(
                      of: find.text('720p'),
                      matching: find.byType(AnimatedDefaultTextStyle),
                    )
                    .first,
              )
              .duration,
          const Duration(milliseconds: 150),
        );
      });

      testWidgets('reduce motion drops the cross-fade', (tester) async {
        reduceMotion(tester);
        await pumpPills(tester, theme);

        expect(pillOf(tester, '720p').animationDuration, Duration.zero);
      });

      testWidgets('the track is 4 dp padded on bg with no border by default', (
        tester,
      ) async {
        await pumpPills(tester, theme);

        final track = tester.widget<DecoratedBox>(
          find
              .ancestor(
                of: find.text('Best'),
                matching: find.byType(DecoratedBox),
              )
              .last,
        );
        final decoration = track.decoration as BoxDecoration;
        expect(decoration.color, tokens.bg);
        expect(decoration.border, isNull);
        expect(decoration.borderRadius, BorderRadius.circular(12));
        final trackBox = tester.getRect(
          find
              .ancestor(
                of: find.text('Best'),
                matching: find.byType(DecoratedBox),
              )
              .last,
        );
        expect(trackBox.height, 48);
        expect(trackBox.width, 335);
        expect(tester.getTopLeft(find.text('Best')).dx, greaterThan(24));
      });

      testWidgets('a page track takes the given colour and a hairline border', (
        tester,
      ) async {
        await pumpPills(
          tester,
          theme,
          trackColor: tokens.surface,
          height: 44,
          trackRadius: 14,
          pillRadius: 10,
        );

        final finder = find
            .ancestor(
              of: find.text('Best'),
              matching: find.byType(DecoratedBox),
            )
            .last;
        final decoration =
            tester.widget<DecoratedBox>(finder).decoration as BoxDecoration;
        expect(decoration.color, tokens.surface);
        expect(decoration.border, Border.all(color: tokens.border));
        expect(decoration.borderRadius, BorderRadius.circular(14));
        expect(tester.getSize(finder).height, 54);
        final pill = tester.widget<Material>(
          find
              .ancestor(of: find.text('Best'), matching: find.byType(Material))
              .first,
        );
        expect(pill.borderRadius, BorderRadius.circular(10));
      });

      testWidgets('pills are equal width and at least the given height', (
        tester,
      ) async {
        await pumpPills(tester, theme);

        final sizes = [
          for (final (_, label) in qualities)
            tester.getSize(
              find
                  .ancestor(
                    of: find.text(label),
                    matching: find.byType(InkWell),
                  )
                  .first,
            ),
        ];
        for (final size in sizes) {
          expect(size.width, closeTo((335 - 8 - 16) / 5, .01));
          expect(size.height, 40);
        }
      });

      testWidgets('body labels are 14/500, mono labels 12/500 JetBrains Mono', (
        tester,
      ) async {
        await pumpPills(tester, theme);
        expect(labelStyle(tester, 'Best').fontSize, 14);
        expect(labelStyle(tester, 'Best').fontWeight, FontWeight.w500);
        expect(labelStyle(tester, 'Best').fontFamily, 'Geist');

        await pumpPills(tester, theme, mono: true);
        expect(labelStyle(tester, 'Best').fontSize, 12);
        expect(labelStyle(tester, 'Best').fontWeight, FontWeight.w500);
        expect(labelStyle(tester, 'Best').fontFamily, 'JetBrainsMono');
      });

      testWidgets('mono labels drop to 11 under 360 dp', (tester) async {
        await pumpPills(tester, theme, mono: true, size: const Size(320, 640));

        expect(labelStyle(tester, 'Best').fontSize, 11);
      });

      testWidgets('five pills fit 320 dp at the 1.3 text clamp', (
        tester,
      ) async {
        await pumpPills(tester, theme, mono: true, size: const Size(320, 640));
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearAllTestValues);
        await tester.pump();

        expect(tester.takeException(), isNull);
        for (final (_, label) in qualities) {
          final text = tester.getRect(find.text(label));
          final pill = tester.getRect(
            find
                .ancestor(of: find.text(label), matching: find.byType(InkWell))
                .first,
          );
          expect(text.width, lessThanOrEqualTo(pill.width));
        }
      });

      testWidgets('each pill is a checked button in one exclusive group', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await pumpPills(tester, theme, semanticLabel: 'Default quality');

        expect(
          tester.getSemantics(find.text('1080p')),
          isSemantics(
            label: '1080p',
            isButton: true,
            hasCheckedState: true,
            isChecked: true,
            isInMutuallyExclusiveGroup: true,
          ),
        );
        expect(
          tester.getSemantics(find.text('720p')),
          isSemantics(
            label: '720p',
            isButton: true,
            hasCheckedState: true,
            isChecked: false,
            isInMutuallyExclusiveGroup: true,
          ),
        );
        handle.dispose();
      });

      testWidgets('the group carries the semantic label as a radio group', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await pumpPills(tester, theme, semanticLabel: 'Default quality');

        expect(
          tester.getSemantics(find.bySemanticsLabel('Default quality')),
          isSemantics(label: 'Default quality', role: SemanticsRole.radioGroup),
        );
        handle.dispose();
      });

      testWidgets('a tap through semantics reports the value', (tester) async {
        final handle = tester.ensureSemantics();
        final taps = <String>[];
        await pumpPills(tester, theme, onChanged: taps.add);

        tester.semantics.tap(find.semantics.byLabel('480p'));
        await tester.pump();

        expect(taps, ['480']);
        handle.dispose();
      });
    });
  }
}
