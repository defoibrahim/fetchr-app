import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/routes/app_routes.dart';
import 'package:grabby/app/shell/app_branch_switcher.dart';
import 'package:grabby/app/shell/tab_scroll.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/modules/downloader/domain/entities/download_task.dart';
import 'package:grabby/modules/downloader/presentation/views/downloads_view.dart';
import 'package:grabby/modules/library/domain/entities/library_item.dart';
import 'package:mocktail/mocktail.dart';
import 'package:persistent_bottom_nav_bar_v2/persistent_bottom_nav_bar_v2.dart';

import '../../core/widgets/widget_harness.dart';
import '../../support/fake_app.dart';
import '../../support/fixtures.dart';
import '../../support/haptics.dart';

const _tick = Duration(milliseconds: 1);

// From 600 dp the shell has a rail, not a bar.
const _wide = Size(700, 1000);

FakeApp _withDone(int count) {
  final app = FakeApp();
  final now = DateTime.now();
  when(() => app.downloader.watchTasks()).thenAnswer(
    (_) => Stream.value([
      for (var i = 0; i < count; i++)
        downloadTask(
          id: 'd$i',
          status: TaskStatus.completed,
          savedUri: 'content://media/$i',
          finishedAt: now,
        ),
    ]),
  );
  return app;
}

ScrollPosition _downloadsList(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(DownloadsView),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

Future<ScrollPosition> _scrolledDownloads(
  WidgetTester tester, {
  required double by,
  Size size = const Size(360, 800),
}) async {
  await pumpFakeApp(
    tester,
    app: _withDone(60),
    initialLocation: AppRoutes.downloads,
    size: size,
  );
  final list = _downloadsList(tester);
  list.jumpTo(by);
  await tester.pump();
  expect(list.pixels, by);
  return list;
}

Finder _railTab(String label) => find.descendant(
  of: find.byType(NavigationRail),
  matching: find.text(label),
);

void main() {
  testWidgets('the router shows its tabs through the fade-through switcher', (
    tester,
  ) async {
    await pumpFakeApp(tester);

    expect(find.byType(AppBranchSwitcher), findsOneWidget);
    expect(find.byType(TabScroll), findsOneWidget);
  });

  testWidgets('the bar pill moves with the pages: 250 ms, standard', (
    tester,
  ) async {
    await pumpFakeApp(tester);

    final motion = tester
        .widget<Style8BottomNavBar>(navBar)
        .itemAnimationProperties;
    expect(motion.duration, AppBranchSwitcher.duration);
    expect(motion.curve, Motion.standard);
  });

  testWidgets('a tab switch, or a tap on the open tab, plays no haptic', (
    tester,
  ) async {
    await pumpFakeApp(tester);
    final haptics = recordHaptics(tester);

    await tester.tap(navTab('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(navTab('Settings'));
    await tester.pumpAndSettle();

    expect(selectedNavTab(tester), 3);
    expect(haptics, isEmpty);
  });

  group('a tap on the open tab', () {
    testWidgets('scrolls its list back to the top over 300 ms', (tester) async {
      final list = await _scrolledDownloads(tester, by: 600);

      await tester.tap(navTab('Downloads'));
      await tester.pump();
      await tester.pump(TabScroll.duration ~/ 2);
      expect(list.pixels, inExclusiveRange(0, 600));

      await tester.pump(TabScroll.duration ~/ 2 + _tick);
      expect(list.pixels, 0);
      expect(selectedNavTab(tester), 1);
    });

    testWidgets('far down, first jumps a screen and a half from the top', (
      tester,
    ) async {
      final list = await _scrolledDownloads(tester, by: 3000);
      final near = list.viewportDimension * TabScroll.jumpScreens;

      await tester.tap(navTab('Downloads'));
      await tester.pump();

      expect(list.pixels, lessThanOrEqualTo(near));
      await tester.pumpAndSettle();
      expect(list.pixels, 0);
    });

    testWidgets('jumps to the top at once under reduce motion', (tester) async {
      reduceMotion(tester);
      final list = await _scrolledDownloads(tester, by: 600);

      await tester.tap(navTab('Downloads'));
      await tester.pump();

      expect(list.pixels, 0);
    });

    testWidgets('does the same from the rail', (tester) async {
      final list = await _scrolledDownloads(tester, by: 600, size: _wide);

      await tester.tap(_railTab('Downloads'));
      await tester.pumpAndSettle();

      expect(list.pixels, 0);
    });

    testWidgets('a tap on another tab leaves the list where it was', (
      tester,
    ) async {
      final list = await _scrolledDownloads(tester, by: 600);

      await tester.tap(navTab('Home'));
      await tester.pumpAndSettle();
      await tester.tap(navTab('Downloads'));
      await tester.pumpAndSettle();

      expect(list.pixels, 600);
    });
  });

  testWidgets('Library still reloads when its tab is shown again', (
    tester,
  ) async {
    final app = FakeApp();
    when(
      () => app.library.list(any()),
    ).thenAnswer((_) async => const Ok(<LibraryItem>[]));
    await pumpFakeApp(tester, app: app);

    await tester.tap(navTab('Library'));
    await tester.pumpAndSettle();
    verify(() => app.library.list(any())).called(1);

    await tester.tap(navTab('Home'));
    await tester.pumpAndSettle();
    verifyNever(() => app.library.list(any()));

    await tester.tap(navTab('Library'));
    // At once, not at the end of the fade.
    await tester.pump();
    await tester.pump();
    verify(() => app.library.list(any())).called(1);
    await tester.pumpAndSettle();
  });
}
