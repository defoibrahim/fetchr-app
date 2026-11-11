import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/theme/app_text_styles.dart';
import 'package:grabby/core/theme/theme.dart';

const lime = AppPalette.defaultAccent;

const selected = {WidgetState.selected};
const unselected = <WidgetState>{};

void main() {
  for (final (name, theme) in [
    ('dark', AppTheme.dark(lime)),
    ('light', AppTheme.light(lime)),
  ]) {
    final t = theme.extension<AppTokens>()!;
    final scheme = theme.colorScheme;
    final type = theme.extension<AppTextStyles>()!;

    group(name, () {
      group('navigation rail', () {
        final rail = theme.navigationRailTheme;

        test('sits on the nav bar fill, flat, and shows every label', () {
          expect(rail.backgroundColor, t.navBar);
          expect(rail.elevation, 0);
          expect(rail.labelType, NavigationRailLabelType.all);
          expect(rail.useIndicator, isTrue);
        });

        test('the indicator is primary, in the bar\'s 56 x 30 pill', () {
          expect(rail.indicatorColor, scheme.primary);
          final bounds = rail.indicatorShape!
              .getOuterPath(const Rect.fromLTWH(10, 20, 56, 32))
              .getBounds();
          expect(bounds.size, const Size(56, 30));
          expect(bounds.center, const Offset(38, 36));
        });

        test('the indicator never outgrows a smaller box', () {
          final bounds = rail.indicatorShape!
              .getOuterPath(const Rect.fromLTWH(0, 0, 40, 20))
              .getBounds();
          expect(bounds.size, const Size(40, 20));
        });

        test('icons are 20; selected on primary, others muted', () {
          expect(rail.selectedIconTheme!.size, 20);
          expect(rail.selectedIconTheme!.color, t.primaryIcon);
          expect(rail.unselectedIconTheme!.size, 20);
          expect(rail.unselectedIconTheme!.color, t.textMuted);
        });

        test('labels use navLabel, 600 and text when active', () {
          final on = rail.selectedLabelTextStyle!;
          final off = rail.unselectedLabelTextStyle!;
          expect(on.fontFamily, type.navLabel.fontFamily);
          expect(on.fontSize, 12);
          expect(on.fontWeight, FontWeight.w600);
          expect(on.color, t.text);
          expect(off.fontSize, 12);
          expect(off.fontWeight, FontWeight.w400);
          expect(off.color, t.textMuted);
        });

        testWidgets('renders the pill and the labels in a real rail', (
          tester,
        ) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: Row(
                  children: [
                    NavigationRail(
                      selectedIndex: 0,
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(Icons.home),
                          label: Text('Home'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.download),
                          label: Text('Downloads'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );

          expect(find.text('Home'), findsOneWidget);
          expect(find.text('Downloads'), findsOneWidget);
          final ink = tester
              .widgetList<Ink>(
                find.descendant(
                  of: find.byType(NavigationIndicator),
                  matching: find.byType(Ink),
                ),
              )
              .first;
          final fill = ink.decoration! as ShapeDecoration;
          expect(fill.color, scheme.primary);
          expect(Size(ink.width!, ink.height!), const Size(56, 32));
          expect(
            fill.shape
                .getOuterPath(Offset.zero & Size(ink.width!, ink.height!))
                .getBounds()
                .size,
            const Size(56, 30),
          );
          final selectedIcon = tester.widget<IconTheme>(
            find
                .ancestor(
                  of: find.byIcon(Icons.home),
                  matching: find.byType(IconTheme),
                )
                .first,
          );
          expect(selectedIcon.data.color, t.primaryIcon);
          expect(selectedIcon.data.size, 20);
        });
      });

      group('chip', () {
        final chip = theme.chipTheme;

        BorderSide? sideFor(Set<WidgetState> states) =>
            WidgetStateProperty.resolveAs<BorderSide?>(chip.side, states);

        test(
          'is a pill with a 1 dp border: control grey, primary selected',
          () {
            expect(chip.shape, const StadiumBorder());
            expect(sideFor(unselected)!.width, 1);
            expect(sideFor(unselected)!.color, t.borderControl);
            expect(sideFor(selected)!.width, 1);
            expect(sideFor(selected)!.color, scheme.primary);
            expect(chip.showCheckmark, isFalse);
            expect(chip.surfaceTintColor, Colors.transparent);
          },
        );

        test('selected fills with primary, unselected stays clear', () {
          expect(chip.selectedColor, scheme.primary);
          expect(chip.backgroundColor!.a, 0);
        });

        test(
          'the label is 14/500, onPrimary when selected, text otherwise',
          () {
            final label = chip.labelStyle!;
            expect(label.fontSize, 14);
            expect(label.fontWeight, FontWeight.w500);
            expect(
              WidgetStateProperty.resolveAs<Color?>(label.color, selected),
              scheme.onPrimary,
            );
            expect(
              WidgetStateProperty.resolveAs<Color?>(label.color, unselected),
              t.text,
            );
          },
        );

        testWidgets('is 40 high and 16 dp padded', (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: Center(
                  child: FilterChip(
                    label: const Text('Video'),
                    selected: false,
                    onSelected: (_) {},
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ),
          );

          final size = tester.getSize(find.byType(FilterChip));
          expect(size.height, 40);
          final label = tester.getSize(find.text('Video'));
          // 16 dp each side plus the 1 dp border, which sits inside the box.
          expect(size.width, closeTo(label.width + 34, .5));
        });

        testWidgets('selected paints a primary fill and border', (
          tester,
        ) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilterChip(
                        label: const Text('All'),
                        selected: true,
                        onSelected: (_) {},
                      ),
                      FilterChip(
                        label: const Text('Audio'),
                        selected: false,
                        onSelected: (_) {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );

          ShapeDecoration fillOf(String label) =>
              tester
                      .widget<Ink>(
                        find.descendant(
                          of: find.ancestor(
                            of: find.text(label),
                            matching: find.byType(RawChip),
                          ),
                          matching: find.byType(Ink),
                        ),
                      )
                      .decoration!
                  as ShapeDecoration;
          Color? textOf(String label) =>
              DefaultTextStyle.of(tester.element(find.text(label))).style.color;

          final on = fillOf('All');
          expect(on.color, scheme.primary);
          expect((on.shape as OutlinedBorder).side.color, scheme.primary);
          expect(textOf('All'), scheme.onPrimary);

          final off = fillOf('Audio');
          expect(off.color!.a, 0);
          expect((off.shape as OutlinedBorder).side.color, t.borderControl);
          expect(textOf('Audio'), t.text);
        });
      });

      group('switch', () {
        final sw = theme.switchTheme;

        test('on is a primary track with an onPrimary knob', () {
          expect(sw.trackColor!.resolve(selected), scheme.primary);
          expect(sw.thumbColor!.resolve(selected), scheme.onPrimary);
        });

        test('off is a control-border track with a muted knob', () {
          expect(sw.trackColor!.resolve(unselected), t.borderControl);
          expect(sw.thumbColor!.resolve(unselected), t.textMuted);
        });

        test('has no outline', () {
          expect(sw.trackOutlineColor!.resolve(selected), Colors.transparent);
          expect(sw.trackOutlineColor!.resolve(unselected), Colors.transparent);
        });

        test('keeps the big knob in both states', () {
          expect(sw.thumbIcon!.resolve(selected), isNotNull);
          expect(sw.thumbIcon!.resolve(unselected), isNotNull);
        });

        testWidgets('is 52 wide with no side padding', (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: Center(
                  child: Switch(
                    value: true,
                    onChanged: (_) {},
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ),
          );

          // The 32 dp track is painted in a 40 dp high box.
          expect(tester.getSize(find.byType(Switch)), const Size(52, 40));
        });
      });

      group('checkbox', () {
        final box = theme.checkboxTheme;

        test('fills with primary and checks with onPrimary', () {
          expect(box.fillColor!.resolve(selected), scheme.primary);
          expect(box.fillColor!.resolve(unselected)!.a, 0);
          expect(box.checkColor!.resolve(selected), scheme.onPrimary);
        });

        test('has a 1.5 dp borderStrong edge while clear, radius 4', () {
          final side = box.side! as WidgetStateBorderSide;
          expect(side.resolve(unselected)!.width, 1.5);
          expect(side.resolve(unselected)!.color, t.borderStrong);
          expect(side.resolve(selected)!.color, scheme.primary);
          expect(
            box.shape,
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          );
        });
      });

      test('radio is primary when selected, borderStrong otherwise', () {
        final radio = theme.radioTheme;
        expect(radio.fillColor!.resolve(selected), scheme.primary);
        expect(radio.fillColor!.resolve(unselected), t.borderStrong);
      });

      group('menu', () {
        final menu = theme.menuTheme.style!;

        test('is raised, bordered, round and padded 6', () {
          expect(menu.backgroundColor!.resolve({}), t.surfaceRaised);
          expect(menu.surfaceTintColor!.resolve({}), Colors.transparent);
          expect(menu.padding!.resolve({}), const EdgeInsets.all(6));
          expect(menu.side!.resolve({})!.color, t.borderControl);
          expect(menu.side!.resolve({})!.width, 1);
          expect(
            menu.shape!.resolve({}),
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          );
        });

        test('casts a heavy black shadow', () {
          final shadow = menu.shadowColor!.resolve({})!;
          expect(shadow.toARGB32() & 0x00FFFFFF, 0);
          expect(shadow.a, closeTo(.55, .01));
          expect(menu.elevation!.resolve({}), greaterThan(0));
        });

        test('items are 44 high, radius 10, 14/400 in text', () {
          final item = theme.menuButtonTheme.style!;
          expect(item.minimumSize!.resolve({})!.height, 44);
          expect(
            item.shape!.resolve({}),
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          );
          expect(
            item.padding!.resolve({}),
            const EdgeInsets.symmetric(horizontal: 12),
          );
          expect(item.foregroundColor!.resolve({}), t.text);
          final label = item.textStyle!.resolve({})!;
          expect(label.fontSize, 14);
          expect(label.fontWeight, FontWeight.w400);
          expect(item.iconSize!.resolve({}), 18);
        });
      });

      group('buttons', () {
        const disabled = {WidgetState.disabled};
        const pressed = {WidgetState.pressed};
        const hovered = {WidgetState.hovered};

        Map<String, ButtonStyle> styles() => {
          'filled': theme.filledButtonTheme.style!,
          'outlined': theme.outlinedButtonTheme.style!,
          'text': theme.textButtonTheme.style!,
        };

        test('are 48 high with radius 16, tight to their box and flat', () {
          for (final style in styles().values) {
            expect(style.minimumSize!.resolve({})!.height, 48);
            expect(
              style.shape!.resolve({}),
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            );
            expect(style.tapTargetSize, MaterialTapTargetSize.shrinkWrap);
            expect(style.elevation!.resolve({}), 0);
            expect(
              style.padding!.resolve({}),
              const EdgeInsets.symmetric(horizontal: 16),
            );
          }
        });

        test('label with the body style at 600: 14/600', () {
          for (final style in styles().values) {
            final label = style.textStyle!.resolve({})!;
            expect(label.fontSize, 14);
            expect(label.fontWeight, FontWeight.w600);
            expect(label, type.body.copyWith(fontWeight: FontWeight.w600));
          }
        });

        test('filled is primary on onPrimary, 40% when disabled', () {
          final style = styles()['filled']!;
          expect(style.backgroundColor!.resolve({}), scheme.primary);
          expect(style.foregroundColor!.resolve({}), scheme.onPrimary);
          final fill = style.backgroundColor!.resolve(disabled)!;
          expect(
            fill.toARGB32() & 0x00FFFFFF,
            scheme.primary.toARGB32() & 0x00FFFFFF,
          );
          expect(fill.a, closeTo(.4, .01));
          expect(style.foregroundColor!.resolve(disabled)!.a, closeTo(.4, .01));
        });

        test(
          'outlined is a 1 dp borderStrong side with text, 40% disabled',
          () {
            final style = styles()['outlined']!;
            expect(style.foregroundColor!.resolve({}), t.text);
            expect(style.side!.resolve({})!.color, t.borderStrong);
            expect(style.side!.resolve({})!.width, 1);
            expect(style.side!.resolve(disabled)!.color.a, closeTo(.4, .01));
            expect(
              style.foregroundColor!.resolve(disabled)!.a,
              closeTo(.4, .01),
            );
          },
        );

        test('text is primary on nothing, 40% disabled', () {
          final style = styles()['text']!;
          expect(style.foregroundColor!.resolve({}), scheme.primary);
          expect(style.backgroundColor, isNull);
          expect(style.foregroundColor!.resolve(disabled)!.a, closeTo(.4, .01));
        });

        test('press and hover ink is text at 12% and 8%', () {
          for (final style in styles().values) {
            expect(
              style.overlayColor!.resolve(pressed),
              t.text.withValues(alpha: .12),
            );
            expect(
              style.overlayColor!.resolve({WidgetState.focused}),
              t.text.withValues(alpha: .12),
            );
            expect(
              style.overlayColor!.resolve(hovered),
              t.text.withValues(alpha: .08),
            );
            expect(style.overlayColor!.resolve({}), isNull);
          }
        });

        testWidgets('a stock FilledButton renders 48 high', (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () {},
                    child: const Text('Go'),
                  ),
                ),
              ),
            ),
          );

          expect(tester.getSize(find.byType(FilledButton)).height, 48);
        });
      });

      test('dialog is a bordered surface with radius 28 and the scrim', () {
        final dialog = theme.dialogTheme;
        expect(dialog.backgroundColor, t.surface);
        expect(dialog.surfaceTintColor, Colors.transparent);
        expect(dialog.barrierColor, t.scrim);
        expect(dialog.insetPadding, const EdgeInsets.all(24));
        final shape = dialog.shape! as RoundedRectangleBorder;
        expect(shape.borderRadius, BorderRadius.circular(28));
        expect(shape.side.color, t.border);
        expect(shape.side.width, 1);
        expect(dialog.titleTextStyle, type.dialogTitle);
        expect(dialog.contentTextStyle!.fontSize, 14);
        expect(dialog.contentTextStyle!.height, 1.5);
        expect(
          dialog.contentTextStyle,
          type.bodyRelaxed.copyWith(color: t.errorBody),
        );
      });

      test('bottom sheet is a surface with 28 top corners and the scrim', () {
        final sheet = theme.bottomSheetTheme;
        expect(sheet.modalBackgroundColor, t.surface);
        expect(sheet.surfaceTintColor, Colors.transparent);
        expect(sheet.modalBarrierColor, t.scrim);
        expect(sheet.modalElevation, 0);
        final shape = sheet.shape! as RoundedRectangleBorder;
        expect(
          shape.borderRadius,
          const BorderRadius.vertical(top: Radius.circular(28)),
        );
        expect(shape.side.color, t.border);
        expect(shape.side.width, 1);
      });

      test('snack bar floats raised with a border and radius 14', () {
        final bar = theme.snackBarTheme;
        expect(bar.behavior, SnackBarBehavior.floating);
        expect(bar.backgroundColor, t.surfaceRaised);
        expect(bar.elevation, 0);
        expect(bar.actionTextColor, scheme.primary);
        expect(bar.contentTextStyle!.color, t.text);
        expect(bar.contentTextStyle!.fontSize, 14);
        final shape = bar.shape! as RoundedRectangleBorder;
        expect(shape.borderRadius, BorderRadius.circular(14));
        expect(shape.side.color, t.border);
      });

      group('slider', () {
        final slider = theme.sliderTheme;

        test('has a 4 dp track, a 14 dp thumb and a 22% white remainder', () {
          expect(slider.trackHeight, 4);
          expect(slider.activeTrackColor, t.accent);
          expect(slider.thumbColor, t.accent);
          expect(slider.inactiveTrackColor, t.onMedia.withValues(alpha: .22));
          expect(slider.inactiveTrackColor!.toARGB32() & 0x00FFFFFF, 0xFFFFFF);
          expect(slider.inactiveTrackColor!.a, closeTo(.22, .01));
          expect(slider.showValueIndicator, ShowValueIndicator.never);
        });

        testWidgets('draws a 14 dp thumb', (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: Center(child: Slider(value: .3, onChanged: (_) {})),
              ),
            ),
          );

          final context = tester.element(find.byType(Slider));
          final data = SliderTheme.of(context);
          final thumb = data.thumbShape!.getPreferredSize(true, false);
          expect(thumb, const Size(14, 14));
        });
      });

      // AppProgressBar draws the only linear bar and owns its track and height.
      test('progress indicators are primary and set no linear track', () {
        final progress = theme.progressIndicatorTheme;
        expect(progress.color, scheme.primary);
        expect(progress.linearTrackColor, isNull);
        expect(progress.linearMinHeight, isNull);
      });

      test('tooltip is a small raised bubble', () {
        final tip = theme.tooltipTheme;
        final decoration = tip.decoration! as BoxDecoration;
        expect(decoration.color, t.surfaceRaised);
        expect(decoration.border, Border.all(color: t.borderControl));
        expect(decoration.borderRadius, BorderRadius.circular(8));
        expect(tip.textStyle!.color, t.text);
        expect(tip.textStyle!.fontSize, 12);
      });

      test('text selection follows primary', () {
        final selection = theme.textSelectionTheme;
        expect(selection.cursorColor, scheme.primary);
        expect(selection.selectionHandleColor, scheme.primary);
        expect(selection.selectionColor!.a, closeTo(.4, .01));
        expect(
          selection.selectionColor!.toARGB32() & 0x00FFFFFF,
          scheme.primary.toARGB32() & 0x00FFFFFF,
        );
      });

      test('the card is an 18 radius surface with a hairline', () {
        final card = theme.cardTheme;
        final shape = card.shape! as RoundedRectangleBorder;
        expect(card.color, t.surface);
        expect(shape.borderRadius, BorderRadius.circular(18));
        expect(shape.side.color, t.border);
      });
    });
  }

  test('every accent builds every component theme', () {
    for (final accent in AppPalette.accents.map((o) => o.color)) {
      for (final theme in [AppTheme.dark(accent), AppTheme.light(accent)]) {
        expect(
          theme.navigationRailTheme.indicatorColor,
          theme.colorScheme.primary,
        );
        expect(
          theme.switchTheme.trackColor!.resolve(selected),
          theme.colorScheme.primary,
        );
        expect(theme.sliderTheme.activeTrackColor, accent);
      }
    }
  });

  test('themes still lerp with the component themes in place', () {
    final mid = ThemeData.lerp(AppTheme.dark(lime), AppTheme.light(lime), .5);
    expect(mid.navigationRailTheme.labelType, NavigationRailLabelType.all);
  });
}
