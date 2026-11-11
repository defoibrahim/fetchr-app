import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:grabby/app/shell/app_shell.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/utils/scale.dart';
import 'package:grabby/core/widgets/app_icon.dart';
import 'package:persistent_bottom_nav_bar_v2/persistent_bottom_nav_bar_v2.dart';

import '../../core/widgets/widget_harness.dart';
import '../../support/fake_app.dart';

final _blue = AppPalette.accents[1].color;

// Every real page sits in its own SafeArea.
StatefulShellBranch _branch(String path, {List<RouteBase> routes = const []}) =>
    StatefulShellBranch(
      routes: [
        GoRoute(
          path: path,
          builder: (_, _) => SafeArea(
            child: Align(
              alignment: AlignmentDirectional.topStart,
              child: Text('page $path'),
            ),
          ),
          routes: routes,
        ),
      ],
    );

GoRouter _router({Widget? badge}) => GoRouter(
  initialLocation: '/home',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (_, _, shell) => AppShell(shell: shell, downloadsBadge: badge),
      branches: [
        _branch(
          '/home',
          routes: [
            GoRoute(path: 'detail', builder: (_, _) => const Text('detail')),
          ],
        ),
        _branch('/downloads'),
        _branch('/library'),
        _branch('/settings'),
      ],
    ),
  ],
);

Future<GoRouter> _pump(
  WidgetTester tester, {
  Brightness brightness = Brightness.dark,
  Widget? badge,
  Size size = designSize,
  TransitionBuilder? builder,
}) async {
  useView(tester, size);
  final router = _router(badge: badge);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ScaleScope(
      child: MaterialApp.router(
        theme: brightness == Brightness.dark
            ? AppTheme.dark(_blue)
            : AppTheme.light(_blue),
        routerConfig: router,
        builder: builder,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

Finder _tabIcon(String label) =>
    find.descendant(of: navTab(label), matching: find.byType(AppIcon));

// Only the selected tab shows its title.
Finder _title(String label) =>
    find.descendant(of: navTab(label), matching: find.text(label));

Color? _pill(WidgetTester tester, String label) =>
    (tester
                .widget<AnimatedContainer>(
                  find.descendant(
                    of: navTab(label),
                    matching: find.byType(AnimatedContainer),
                  ),
                )
                .decoration!
            as BoxDecoration)
        .color;

String _location(GoRouter router) =>
    router.routeInformationProvider.value.uri.toString();

ColorFilter? _iconTint(WidgetTester tester, String label) => tester
    .widget<SvgPicture>(
      find.descendant(of: _tabIcon(label), matching: find.byType(SvgPicture)),
    )
    .colorFilter;

ColorFilter _tint(Color color) => ColorFilter.mode(color, BlendMode.srcIn);

// From 600 dp the shell has a rail, not a bar.
const _wide = Size(700, 1000);

NavigationRail _rail(WidgetTester tester) =>
    tester.widget<NavigationRail>(find.byType(NavigationRail));

Finder _railTab(String label) => find.descendant(
  of: find.byType(NavigationRail),
  matching: find.text(label),
);

Finder _railIcon(int index) => find
    .descendant(of: find.byType(NavigationRail), matching: find.byType(AppIcon))
    .at(index);

ColorFilter? _railTint(WidgetTester tester, int index) => tester
    .widget<SvgPicture>(
      find.descendant(of: _railIcon(index), matching: find.byType(SvgPicture)),
    )
    .colorFilter;

void main() {
  group('destinations', () {
    testWidgets('are Home, Downloads, Library and Settings in order', (
      tester,
    ) async {
      await _pump(tester);

      final bar = tester.widget<Style8BottomNavBar>(navBar);
      expect(bar.navBarConfig.items.map((i) => i.title), navLabels);
      expect(_title('Home'), findsOneWidget, reason: 'the selected one');
      for (final label in navLabels.skip(1)) {
        expect(_title(label), findsNothing, reason: label);
      }
      expect(selectedNavTab(tester), 0);
    });

    testWidgets('draw an AppIcon at 20 dp, left decorative', (tester) async {
      await _pump(tester);

      for (final label in navLabels) {
        final picture = tester.widget<SvgPicture>(
          find.descendant(
            of: _tabIcon(label),
            matching: find.byType(SvgPicture),
          ),
        );
        expect(picture.width, 20, reason: label);
        expect(picture.height, 20, reason: label);
        expect(picture.excludeFromSemantics, isTrue, reason: label);
      }
    });
  });

  testWidgets('each tab reads its label and whether it is selected', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);

    for (final (i, label) in navLabels.indexed) {
      expect(
        tester.getSemantics(navTab(label)),
        isSemantics(
          label: label,
          isButton: true,
          isSelected: i == 0,
          hasSelectedState: true,
          hasTapAction: true,
        ),
        reason: '$label, read once',
      );
    }
    semantics.dispose();
  });

  group('navigation', () {
    testWidgets('tapping a destination selects its branch', (tester) async {
      final router = await _pump(tester);

      for (final (i, label) in navLabels.indexed.skip(1)) {
        await tester.tap(navTab(label));
        await tester.pumpAndSettle();

        expect(selectedNavTab(tester), i, reason: label);
        expect(_location(router), '/${label.toLowerCase()}', reason: label);
        expect(find.text('page /${label.toLowerCase()}'), findsOneWidget);
      }
    });

    testWidgets('re-tapping the current tab goes to its initial location', (
      tester,
    ) async {
      final router = await _pump(tester);
      router.go('/home/detail');
      await tester.pumpAndSettle();
      expect(find.text('detail'), findsOneWidget);

      await tester.tap(navTab('Home'));
      await tester.pumpAndSettle();

      expect(_location(router), '/home');
      expect(find.text('detail'), findsNothing);
      expect(find.text('page /home'), findsOneWidget);
    });

    testWidgets('tapping another tab keeps the first one where it was', (
      tester,
    ) async {
      final router = await _pump(tester);
      router.go('/home/detail');
      await tester.pumpAndSettle();

      await tester.tap(navTab('Library'));
      await tester.pumpAndSettle();
      await tester.tap(navTab('Home'));
      await tester.pumpAndSettle();

      expect(_location(router), '/home/detail');
    });
  });

  group('bar', () {
    testWidgets('sits on the nav bar fill under a 1 dp divider line', (
      tester,
    ) async {
      await _pump(tester);
      final tokens = AppTokens.of(tester.element(navBar));

      final box = tester.widget<DecoratedBox>(
        find.descendant(of: navBar, matching: find.byType(DecoratedBox)).first,
      );
      final decoration = box.decoration as BoxDecoration;
      expect(decoration.color, tokens.navBar);
      expect(decoration.border, Border(top: BorderSide(color: tokens.divider)));
    });

    testWidgets('each tab is a 48 dp tap target', (tester) async {
      await _pump(tester);

      for (final label in navLabels) {
        final size = tester.getSize(navTab(label));
        expect(size.height, 48, reason: label);
        expect(size.width, greaterThanOrEqualTo(48), reason: label);
      }
    });
  });

  group('colours come from the theme', () {
    testWidgets('dark: accent indicator, onAccent on the selected icon', (
      tester,
    ) async {
      await _pump(tester);
      final tokens = AppTokens.of(tester.element(navBar));

      expect(_pill(tester, 'Home'), _blue);
      expect(_pill(tester, 'Library'), Colors.transparent);
      expect(_iconTint(tester, 'Home'), _tint(tokens.onAccent));
      for (final label in ['Downloads', 'Library', 'Settings']) {
        expect(
          _iconTint(tester, label),
          _tint(tokens.textMuted),
          reason: label,
        );
      }
    });

    testWidgets('light: ink indicator, accent on the selected icon', (
      tester,
    ) async {
      await _pump(tester, brightness: Brightness.light);
      final tokens = AppTokens.of(tester.element(navBar));

      expect(_pill(tester, 'Home'), tokens.text);
      expect(_iconTint(tester, 'Home'), _tint(_blue));
      expect(_iconTint(tester, 'Library'), _tint(tokens.textMuted));
    });

    testWidgets('the selected icon follows the selected tab', (tester) async {
      await _pump(tester);
      final tokens = AppTokens.of(tester.element(navBar));

      await tester.tap(navTab('Settings'));
      await tester.pumpAndSettle();

      expect(_iconTint(tester, 'Settings'), _tint(tokens.onAccent));
      expect(_iconTint(tester, 'Home'), _tint(tokens.textMuted));
    });

    testWidgets('the icon colour eases with the pill instead of snapping', (
      tester,
    ) async {
      await _pump(tester);
      final tokens = AppTokens.of(tester.element(navBar));

      await tester.tap(navTab('Settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      for (final end in [tokens.textMuted, tokens.onAccent]) {
        expect(_iconTint(tester, 'Settings'), isNot(_tint(end)));
        expect(_iconTint(tester, 'Home'), isNot(_tint(end)));
      }
      await tester.pumpAndSettle();
    });
  });

  group('downloads badge', () {
    testWidgets('sits on the Downloads icon and on no other', (tester) async {
      await _pump(tester, badge: const Text('7', key: Key('badge')));

      final badge = find.byKey(const Key('badge'));
      for (final label in navLabels) {
        expect(
          find.descendant(of: navTab(label), matching: badge),
          label == 'Downloads' ? findsOneWidget : findsNothing,
          reason: label,
        );
      }

      final icon = _tabIcon('Downloads');
      expect(
        tester.getCenter(badge).dx,
        greaterThan(tester.getCenter(icon).dx),
      );
      expect(tester.getCenter(badge).dy, lessThan(tester.getCenter(icon).dy));
    });

    testWidgets('does not move the icon or change the bar height', (
      tester,
    ) async {
      await _pump(tester);
      final bare = tester.getCenter(_tabIcon('Downloads'));
      final height = tester.getSize(navBar).height;

      await _pump(tester, badge: const Text('7'));

      expect(tester.getCenter(_tabIcon('Downloads')), bare);
      expect(tester.getSize(navBar).height, height);
    });

    testWidgets('mirrors under right-to-left text', (tester) async {
      useView(tester);
      final router = _router(badge: const Text('7', key: Key('badge')));
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ScaleScope(
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            routerConfig: router,
            builder: rtl,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getCenter(find.byKey(const Key('badge'))).dx,
        lessThan(tester.getCenter(_tabIcon('Downloads')).dx),
      );
    });
  });

  group('rail', () {
    for (final (width, rail) in [(599.0, false), (600.0, true)]) {
      testWidgets('${width.round()} dp shows a ${rail ? 'rail' : 'bar'}', (
        tester,
      ) async {
        await _pump(tester, size: Size(width, 1000));

        expect(
          find.byType(NavigationRail),
          rail ? findsOneWidget : findsNothing,
        );
        expect(navBar, rail ? findsNothing : findsOneWidget);
      });
    }

    testWidgets('holds the four destinations in order, beside the page', (
      tester,
    ) async {
      await _pump(tester, size: _wide);

      final rail = _rail(tester);
      expect(rail.destinations, hasLength(4));
      for (final (i, label) in navLabels.indexed) {
        expect((rail.destinations[i].label as Text).data, label);
        expect(_railTab(label), findsOneWidget);
      }
      expect(rail.selectedIndex, 0);
      expect(
        tester.getRect(find.byType(NavigationRail)).right,
        lessThanOrEqualTo(tester.getTopLeft(find.text('page /home')).dx),
      );
    });

    testWidgets('a 1 dp divider separates the rail from the page', (
      tester,
    ) async {
      await _pump(tester, size: _wide);

      final divider = find.byType(VerticalDivider);
      expect(divider, findsOneWidget);
      expect(tester.getSize(divider).width, 1);
      expect(
        tester.getTopLeft(divider).dx,
        tester.getRect(find.byType(NavigationRail)).right,
      );
    });

    testWidgets('tapping a destination selects its branch', (tester) async {
      final router = await _pump(tester, size: _wide);

      for (final (i, label) in navLabels.indexed.skip(1)) {
        await tester.tap(_railTab(label));
        await tester.pumpAndSettle();

        expect(_rail(tester).selectedIndex, i, reason: label);
        expect(_location(router), '/${label.toLowerCase()}', reason: label);
        expect(find.text('page /${label.toLowerCase()}'), findsOneWidget);
      }
    });

    testWidgets('re-tapping the current destination goes to its initial '
        'location', (tester) async {
      final router = await _pump(tester, size: _wide);
      router.go('/home/detail');
      await tester.pumpAndSettle();
      expect(find.text('detail'), findsOneWidget);

      await tester.tap(_railTab('Home'));
      await tester.pumpAndSettle();

      expect(_location(router), '/home');
      expect(find.text('detail'), findsNothing);
    });

    testWidgets('dark: accent indicator, onAccent on the selected icon', (
      tester,
    ) async {
      await _pump(tester, size: _wide);
      final context = tester.element(find.byType(NavigationRail));
      final tokens = AppTokens.of(context);

      expect(Theme.of(context).navigationRailTheme.indicatorColor, _blue);
      expect(_railTint(tester, 0), _tint(tokens.onAccent));
      for (final i in [1, 2, 3]) {
        expect(_railTint(tester, i), _tint(tokens.textMuted), reason: '$i');
      }
    });

    testWidgets('light: ink indicator, accent on the selected icon', (
      tester,
    ) async {
      await _pump(tester, brightness: Brightness.light, size: _wide);
      final context = tester.element(find.byType(NavigationRail));
      final tokens = AppTokens.of(context);

      expect(Theme.of(context).navigationRailTheme.indicatorColor, tokens.text);
      expect(_railTint(tester, 0), _tint(_blue));
      expect(_railTint(tester, 2), _tint(tokens.textMuted));
    });

    testWidgets('the selected icon follows the selected destination', (
      tester,
    ) async {
      await _pump(tester, size: _wide);
      final tokens = AppTokens.of(tester.element(find.byType(NavigationRail)));

      await tester.tap(_railTab('Settings'));
      await tester.pumpAndSettle();

      expect(_railTint(tester, 3), _tint(tokens.onAccent));
      expect(_railTint(tester, 0), _tint(tokens.textMuted));
    });

    testWidgets('the rail leaves its own colours to the theme', (tester) async {
      await _pump(tester, size: _wide);

      final rail = _rail(tester);
      expect(rail.backgroundColor, isNull);
      expect(rail.indicatorColor, isNull);
      expect(rail.labelType, isNull);
    });

    testWidgets('the badge sits on the Downloads icon and on no other', (
      tester,
    ) async {
      await _pump(
        tester,
        size: _wide,
        badge: const Text('7', key: Key('badge')),
      );

      final badge = find.byKey(const Key('badge'));
      expect(badge, findsOneWidget);
      expect(
        find.descendant(of: find.byType(NavigationRail), matching: badge),
        findsOneWidget,
      );
      final icon = _railIcon(1);
      expect(
        tester.getCenter(badge).dx,
        greaterThan(tester.getCenter(icon).dx),
      );
      expect(tester.getCenter(badge).dy, lessThan(tester.getCenter(icon).dy));
    });

    testWidgets('moves to the right edge under right-to-left text', (
      tester,
    ) async {
      await _pump(tester, size: _wide, builder: rtl);

      expect(tester.getRect(find.byType(NavigationRail)).right, _wide.width);
      expect(
        tester.getTopLeft(find.text('page /home')).dx,
        lessThan(tester.getRect(find.byType(NavigationRail)).left),
      );
    });

    // A camera cutout on the rail's side: the rail pads it, and the page,
    // which sits beside the rail, must not pad it a second time.
    const cutout = 48.0;

    testWidgets('a left cutout is padded by the rail only, in left-to-right', (
      tester,
    ) async {
      tester.view
        ..padding = const FakeViewPadding(left: cutout)
        ..viewPadding = const FakeViewPadding(left: cutout);
      await _pump(tester, size: _wide);

      expect(
        tester.getRect(_railIcon(0)).left,
        greaterThanOrEqualTo(cutout),
        reason: 'the rail keeps clear of the cutout',
      );
      expect(
        tester.getRect(find.text('page /home')).left,
        tester.getRect(find.byType(VerticalDivider)).right,
      );
    });

    testWidgets('a right cutout is padded by the rail only, in right-to-left', (
      tester,
    ) async {
      tester.view
        ..padding = const FakeViewPadding(right: cutout)
        ..viewPadding = const FakeViewPadding(right: cutout);
      await _pump(tester, size: _wide, builder: rtl);

      expect(
        tester.getRect(_railIcon(0)).right,
        lessThanOrEqualTo(_wide.width - cutout),
        reason: 'the rail keeps clear of the cutout',
      );
      expect(
        tester.getRect(find.text('page /home')).right,
        tester.getRect(find.byType(VerticalDivider)).left,
      );
    });

    testWidgets('a landscape phone at the largest text scale fits all four', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await _pump(tester, size: const Size(844, 390));

      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(
        tester.getBottomLeft(_railTab('Settings')).dy,
        lessThanOrEqualTo(390),
      );
    });
  });
}
