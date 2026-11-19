import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/widgets/app_pressable.dart';
import 'package:grabby/core/widgets/stripes.dart';
import 'package:grabby/modules/downloader/domain/entities/download_task.dart';
import 'package:grabby/modules/downloader/domain/entities/playlist_download.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/playlist_tile_grid.dart';

import '../../../../../core/widgets/widget_harness.dart';
import '../../../../../support/fixtures.dart';

final _items = [
  PlaylistItem(playlistTask(1, status: TaskStatus.completed)),
  PlaylistItem(playlistTask(2, status: TaskStatus.running, progress: .5)),
  PlaylistItem(playlistTask(3)),
  PlaylistItem(playlistTask(4, status: TaskStatus.failed)),
  PlaylistItem(playlistTask(5, status: TaskStatus.canceled)),
];

Future<void> _pump(
  WidgetTester tester, {
  List<PlaylistItem>? items,
  int? selectedIndex,
  ValueChanged<int>? onTap,
  bool frozen = false,
}) => pumpThemed(
  tester,
  SizedBox(
    width: 300,
    child: PlaylistTileGrid(
      items: items ?? _items,
      columns: 5,
      selectedIndex: selectedIndex,
      onTap: onTap,
      frozen: frozen,
    ),
  ),
);

Color? _fill(WidgetTester tester, int index) {
  final tile = find.bySemanticsLabel(RegExp('^Video ${index + 1},'));
  return tester
      .widgetList<DecoratedBox>(
        find.descendant(of: tile, matching: find.byType(DecoratedBox)),
      )
      .map((box) => (box.decoration as BoxDecoration).color)
      .nonNulls
      .lastOrNull;
}

void main() {
  testWidgets('each status has its own face', (tester) async {
    await _pump(tester);
    await tester.pumpAndSettle();
    final tokens = AppTokens.of(tester.element(find.byType(PlaylistTileGrid)));

    expect(_fill(tester, 0), tokens.accent);
    expect(_fill(tester, 2), tokens.surfaceSunken);
    expect(_fill(tester, 3), tokens.error);
    expect(
      find.descendant(
        of: find.bySemanticsLabel('Video 5, skipped'),
        matching: find.byType(Stripes),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the one downloading fills with the accent to its progress', (
    tester,
  ) async {
    await _pump(tester);
    await tester.pumpAndSettle();
    final tile = find.bySemanticsLabel('Video 2, downloading');

    final fill = tester.widget<FractionallySizedBox>(
      find.descendant(of: tile, matching: find.byType(FractionallySizedBox)),
    );
    expect(fill.heightFactor, .5);
  });

  testWidgets('the fill eases to new progress, unless frozen', (tester) async {
    double factor() => tester
        .widget<FractionallySizedBox>(find.byType(FractionallySizedBox))
        .heightFactor!;
    List<PlaylistItem> at(double progress) => [
      PlaylistItem(
        playlistTask(2, status: TaskStatus.running, progress: progress),
      ),
    ];

    await _pump(tester, items: at(.2));
    await _pump(tester, items: at(.6));
    await tester.pump(const Duration(milliseconds: 100));
    expect(factor(), inExclusiveRange(.2, .6));
    await tester.pumpAndSettle();
    expect(factor(), .6);

    await _pump(tester, items: at(.8), frozen: true);
    await tester.pump();
    expect(factor(), .8);
  });

  testWidgets('every tile is labelled with its place and status', (
    tester,
  ) async {
    await _pump(tester);

    for (final label in [
      'Video 1, done',
      'Video 2, downloading',
      'Video 3, waiting',
      'Video 4, failed',
      'Video 5, skipped',
    ]) {
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }
  });

  testWidgets('a tap reports the tile and the selection is marked', (
    tester,
  ) async {
    final taps = <int>[];
    await _pump(tester, selectedIndex: 2, onTap: taps.add);

    await tester.tap(find.bySemanticsLabel('Video 4, failed'));

    expect(taps, [3]);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Video 3, waiting')),
      isSemantics(isSelected: true, isButton: true, hasTapAction: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Video 4, failed')),
      isSemantics(isSelected: false),
    );
  });

  testWidgets('a pressed tile shrinks to 0.9 and ripples over its face', (
    tester,
  ) async {
    await _pump(tester, onTap: (_) {});
    final tile = find.bySemanticsLabel('Video 4, failed');
    final pressable = find.descendant(
      of: tile,
      matching: find.byType(AppPressable),
    );
    expect(tester.widget<AppPressable>(pressable).pressedScale, .9);
    expect(tester.widget<AppPressable>(pressable).inkAbove, isTrue);

    final gesture = await tester.startGesture(tester.getCenter(tile));
    await tester.pump(kPressTimeout);
    expect(
      tester
          .widget<AnimatedScale>(
            find.descendant(
              of: pressable,
              matching: find.byType(AnimatedScale),
            ),
          )
          .scale,
      .9,
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a grid nobody taps has no pressables', (tester) async {
    await _pump(tester);
    expect(find.byType(AppPressable), findsNothing);
  });
}
