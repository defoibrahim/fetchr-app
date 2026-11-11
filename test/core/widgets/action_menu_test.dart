import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/gen/assets.gen.dart';
import 'package:grabby/core/theme/app_spacing.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/widgets/action_menu.dart';

import 'widget_harness.dart';

List<ActionMenuItem> items(List<String> log) => [
  ActionMenuItem(
    icon: Assets.icons.play,
    label: 'Play',
    onSelected: () => log.add('play'),
  ),
  ActionMenuItem(
    icon: Assets.icons.share,
    label: 'Share',
    onSelected: () => log.add('share'),
  ),
  ActionMenuItem(
    icon: Assets.icons.trash,
    label: 'Delete file',
    onSelected: () => log.add('delete'),
    destructive: true,
  ),
];

Future<void> pumpMenu(
  WidgetTester tester,
  ThemeData theme,
  List<String> log, {
  Widget Function(BuildContext, MenuController)? builder,
}) async {
  useView(tester);
  await tester.pumpWidget(
    themed(
      Align(
        alignment: Alignment.topRight,
        child: ActionMenu(
          items: items(log),
          builder:
              builder ??
              (context, controller) => TextButton(
                onPressed: controller.open,
                child: const Text('open'),
              ),
        ),
      ),
      theme: theme,
    ),
  );
}

ColorFilter tint(Color color) => ColorFilter.mode(color, BlendMode.srcIn);

Finder panelOf(AppTokens tokens) => find.ancestor(
  of: find.byType(MenuItemButton).first,
  matching: find.byWidgetPredicate(
    (w) => w is Material && w.color == tokens.surfaceRaised,
  ),
);

void main() {
  for (final entry in themes.entries) {
    final theme = entry.value;
    final tokens = theme.extension<AppTokens>()!;

    group(entry.key, () {
      testWidgets('is closed until the anchor opens it', (tester) async {
        await pumpMenu(tester, theme, []);

        expect(find.text('Play'), findsNothing);

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(find.byType(MenuItemButton), findsNWidgets(3));
      });

      testWidgets('lists the items in order', (tester) async {
        await pumpMenu(tester, theme, []);
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        final tops = [
          for (final label in ['Play', 'Share', 'Delete file'])
            tester.getTopLeft(find.text(label)).dy,
        ];
        expect(tops[0], lessThan(tops[1]));
        expect(tops[1], lessThan(tops[2]));
      });

      testWidgets('draws the spec panel: 176 wide, raised, bordered, round', (
        tester,
      ) async {
        await pumpMenu(tester, theme, []);
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        final panel = tester.widget<Material>(panelOf(tokens));
        final shape = panel.shape! as RoundedRectangleBorder;
        expect(shape.borderRadius, BorderRadius.circular(16));
        expect(shape.side.color, tokens.borderControl);
        expect(shape.side.width, 1);
        expect(panel.shadowColor!.a, closeTo(.55, .01));
        expect(tester.getSize(panelOf(tokens)).width, 176);
      });

      testWidgets('items are 44 high with a 12 dp padded icon gap', (
        tester,
      ) async {
        await pumpMenu(tester, theme, []);
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        for (final item in tester.widgetList(find.byType(MenuItemButton))) {
          final size = tester.getSize(find.byWidget(item));
          expect(size.height, 44);
        }
        // The menu theme's iconSize, not a size the row sets.
        final icon = tester.getSize(find.byType(SvgPicture).first);
        expect(icon, const Size.square(AppSizes.iconButton));
        final gap =
            tester.getTopLeft(find.text('Play')).dx -
            tester.getTopRight(find.byType(SvgPicture).first).dx;
        expect(gap, 12);
      });

      testWidgets('the menu ends where the anchor ends and sits below it', (
        tester,
      ) async {
        await pumpMenu(tester, theme, []);
        final anchor = tester.getRect(find.text('open'));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        final panel = tester.getRect(panelOf(tokens));
        expect(panel.right, closeTo(375, 1));
        expect(panel.top, greaterThanOrEqualTo(anchor.bottom));
      });

      testWidgets('a destructive item is in the error colour', (tester) async {
        await pumpMenu(tester, theme, []);
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        Color? colorOf(String label) =>
            DefaultTextStyle.of(tester.element(find.text(label))).style.color;
        expect(colorOf('Delete file'), tokens.error);
        expect(colorOf('Share'), tokens.text);
        expect(colorOf('Play'), tokens.text);
      });

      testWidgets('the destructive icon takes the error colour too', (
        tester,
      ) async {
        await pumpMenu(tester, theme, []);
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        final icons = tester
            .widgetList<SvgPicture>(find.byType(SvgPicture))
            .toList();
        expect(icons.last.colorFilter, tint(tokens.error));
        expect(icons.first.colorFilter, tint(tokens.text));
      });

      testWidgets('a tap calls onSelected once and closes the menu', (
        tester,
      ) async {
        final log = <String>[];
        await pumpMenu(tester, theme, log);
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Share'));
        await tester.pumpAndSettle();

        expect(log, ['share']);
        expect(find.byType(MenuItemButton), findsNothing);
      });

      testWidgets('controller.open() from a long press opens it', (
        tester,
      ) async {
        await pumpMenu(
          tester,
          theme,
          [],
          builder: (context, controller) => GestureDetector(
            onLongPress: controller.open,
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: Text('hold'),
            ),
          ),
        );

        await tester.tap(find.text('hold'));
        await tester.pumpAndSettle();
        expect(find.byType(MenuItemButton), findsNothing);

        await tester.longPress(find.text('hold'));
        await tester.pumpAndSettle();
        expect(find.text('Delete file'), findsOneWidget);
      });

      testWidgets('MoreActionsButton is a 44 dp tooltipped button', (
        tester,
      ) async {
        useView(tester);
        await tester.pumpWidget(
          themed(
            Align(
              alignment: Alignment.topRight,
              child: MoreActionsButton(items: items([])),
            ),
            theme: theme,
          ),
        );

        expect(find.byTooltip('More actions'), findsOneWidget);
        expect(tester.getSize(find.byType(IconButton)), const Size.square(44));
        final icon = tester.widget<SvgPicture>(find.byType(SvgPicture));
        expect(icon.width, AppSizes.iconButton);
        expect(icon.colorFilter, tint(tokens.textMuted));
        final button = tester.widget<IconButton>(find.byType(IconButton));
        final shape =
            button.style!.shape!.resolve({}) as RoundedRectangleBorder;
        expect(shape.borderRadius, BorderRadius.circular(12));
      });

      testWidgets('MoreActionsButton opens the menu and runs the item', (
        tester,
      ) async {
        useView(tester);
        final log = <String>[];
        await tester.pumpWidget(
          themed(
            Align(
              alignment: Alignment.topRight,
              child: MoreActionsButton(items: items(log)),
            ),
            theme: theme,
          ),
        );

        await tester.tap(find.byTooltip('More actions'));
        await tester.pumpAndSettle();
        expect(find.text('Play'), findsOneWidget);

        await tester.tap(find.text('Play'));
        await tester.pumpAndSettle();
        expect(log, ['play']);
        expect(find.text('Play'), findsNothing);
      });

      testWidgets('MoreActionsButton toggles: a second tap closes the menu', (
        tester,
      ) async {
        useView(tester);
        await tester.pumpWidget(
          themed(
            Align(
              alignment: Alignment.topRight,
              child: MoreActionsButton(items: items([])),
            ),
            theme: theme,
          ),
        );

        await tester.tap(find.byTooltip('More actions'));
        await tester.pumpAndSettle();
        expect(find.text('Play'), findsOneWidget);

        await tester.tap(find.byTooltip('More actions'));
        await tester.pumpAndSettle();
        expect(find.text('Play'), findsNothing);
      });

      testWidgets('MoreActionsButton announces the label to a screen reader', (
        tester,
      ) async {
        useView(tester);
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          themed(MoreActionsButton(items: items([])), theme: theme),
        );

        expect(
          tester.getSemantics(find.byType(IconButton)),
          isSemantics(tooltip: 'More actions', isButton: true),
        );
        handle.dispose();
      });
    });
  }
}
