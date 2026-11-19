import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/widgets/app_animated_sliver_list.dart';
import 'package:grabby/core/widgets/app_icon.dart';
import 'package:grabby/core/widgets/app_progress_bar.dart';
import 'package:grabby/modules/downloader/presentation/views/downloads_view.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/attention_row.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/done_row.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/download_card.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../core/widgets/widget_harness.dart';
import '../../../../support/snackbar.dart';
import 'downloads_view_harness.dart';

const _tick = Duration(milliseconds: 1);
final _insert = AppAnimatedSliverList.defaultInsert.duration;
final _remove = AppAnimatedSliverList.defaultRemove.duration;

Finder _card(String id) => find.byKey(ValueKey(id));

/// The row's slot in the list: its height is how far it has grown or folded.
double _slot(WidgetTester tester, Finder row) => tester
    .getSize(find.ancestor(of: row, matching: find.byType(Align)).first)
    .height;

double _check(WidgetTester tester, {int at = 0}) => tester
    .widget<Transform>(
      find
          .ancestor(
            of: find
                .descendant(
                  of: find.byType(DoneRow).at(at),
                  matching: find.byType(AppIcon),
                )
                .first,
            matching: find.byType(Transform),
          )
          .first,
    )
    .transform
    .storage[0];

double? _bar(WidgetTester tester, String id) => tester
    .widget<AppProgressBar>(
      find.descendant(of: _card(id), matching: find.byType(AppProgressBar)),
    )
    .value;

void main() {
  setUp(setUpDownloadsHarness);

  testWidgets('the first list is in place, with nothing to animate', (
    tester,
  ) async {
    await pumpWith(tester, [done('d1'), done('d2'), failed('f')]);

    expect(await tester.pumpAndSettle(), 1);
    expect(_check(tester), 1);
    expect(_check(tester, at: 1), 1);
  });

  testWidgets('a new download grows in above the others, which keep their '
      'state', (tester) async {
    await pumpWith(tester, [running('a')]);
    final bar = tester.state(
      find.descendant(of: _card('a'), matching: find.byType(AppProgressBar)),
    );
    final full = _slot(tester, _card('a'));

    await emit(tester, [running('b'), running('a')]);
    await tester.pump(_insert ~/ 2);
    expect(_slot(tester, _card('b')), inExclusiveRange(0, full));
    expect(
      tester.getTopLeft(_card('b')).dy,
      lessThan(tester.getTopLeft(_card('a')).dy),
    );

    await tester.pump(_insert ~/ 2 + _tick);
    expect(_slot(tester, _card('b')), full);
    expect(
      tester.state(
        find.descendant(of: _card('a'), matching: find.byType(AppProgressBar)),
      ),
      same(bar),
    );
  });

  testWidgets('a removed row folds away, takes no taps, and Undo grows it '
      'back', (tester) async {
    await pumpWith(tester, [failed('a'), failed('b')]);
    final full = _slot(tester, find.byType(AttentionRow).at(1));

    await tester.tap(find.byTooltip('Remove').last);
    await tester.pump();
    await tester.pump();
    await tester.pump(_remove ~/ 4);
    final leaving = find.byType(AttentionRow).at(1);
    expect(_slot(tester, leaving), inExclusiveRange(0, full));
    await tester.tap(
      find.descendant(of: leaving, matching: find.text('Retry')),
      warnIfMissed: false,
    );
    verifyNever(() => retry(any()));

    await pumpSnackbarIn(tester);
    expect(find.byType(AttentionRow), findsOneWidget);
    await tester.tap(find.text('Undo'));
    // Undo restores the row once the snackbar has gone.
    for (
      var i = 0;
      i < 20 && find.byType(AttentionRow).evaluate().length < 2;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(_insert ~/ 3);
    expect(
      _slot(tester, find.byType(AttentionRow).at(1)),
      inExclusiveRange(0, full),
    );

    await tester.pumpAndSettle();
    expect(find.byType(AttentionRow), findsNWidgets(2));
    expect(_slot(tester, find.byType(AttentionRow).at(1)), full);
    verifyNever(() => remove(any()));
  });

  testWidgets('a group heading leaves with its last row', (tester) async {
    await pumpWith(tester, [running('a'), failed('f')]);
    expect(find.text('NEEDS ATTENTION'), findsOneWidget);

    await emit(tester, [running('a')]);
    await tester.pump(_remove ~/ 2);
    expect(find.text('NEEDS ATTENTION'), findsOneWidget);
    expect(find.byType(AttentionRow), findsOneWidget);

    await tester.pump(_remove ~/ 2 + _tick);
    expect(find.text('NEEDS ATTENTION'), findsNothing);
    expect(find.byType(AttentionRow), findsNothing);
  });

  group('a download that finishes', () {
    testWidgets('holds its full card, "Saved", before its Done row arrives', (
      tester,
    ) async {
      await pumpWith(tester, [running('a'), failed('f')]);

      await emit(tester, [done('a'), failed('f')]);
      expect(find.byType(DownloadCard), findsOneWidget);
      expect(_bar(tester, 'a'), 1);
      expect(find.text('Saved'), findsOneWidget);
      expect(find.text('DONE TODAY'), findsNothing);
      expect(find.byType(DoneRow), findsNothing);

      await tester.pump(savedHold ~/ 2);
      expect(find.byType(DownloadCard), findsOneWidget);
      expect(find.byType(DoneRow), findsNothing);

      await tester.pump(savedHold ~/ 2 + _tick);
      // The card folds out of Active while the Done row grows in, its check
      // popping from 60%.
      expect(find.byType(DownloadCard), findsOneWidget);
      expect(find.byType(DoneRow), findsOneWidget);
      expect(find.text('DONE TODAY'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 40));
      expect(_check(tester), inExclusiveRange(.6, 1));

      await tester.pumpAndSettle();
      expect(find.byType(DownloadCard), findsNothing);
      expect(find.text('ACTIVE'), findsNothing);
      expect(find.byType(DoneRow), findsOneWidget);
      expect(_check(tester), 1);
    });

    testWidgets('the held card takes no taps', (tester) async {
      await pumpWith(tester, [running('a')]);

      await emit(tester, [done('a')]);
      await tester.tap(find.byTooltip('Pause download'));
      await tester.tap(find.byTooltip('Cancel download'));
      await tester.pumpAndSettle();

      verifyNever(() => pause(any()));
      verifyNever(() => cancel(any()));
    });

    testWidgets('under reduce motion goes straight to Done', (tester) async {
      reduceMotion(tester);
      await pumpWith(tester, [running('a')]);

      await emit(tester, [done('a')]);
      await tester.pump();

      expect(find.byType(DownloadCard), findsNothing);
      expect(find.text('Saved'), findsNothing);
      expect(find.byType(DoneRow), findsOneWidget);
      expect(_check(tester), 1);
      expect(await tester.pumpAndSettle(), 1);
    });

    testWidgets('a pause that loses the race to the finish does not hold', (
      tester,
    ) async {
      await pumpWith(tester, [running('a')]);
      await tester.tap(find.byTooltip('Pause download'));
      await tester.pump();
      expect(find.byTooltip('Resume download'), findsOneWidget);

      // Native finished before the pause took effect.
      await emit(tester, [done('a')]);

      expect(find.text('Saved'), findsNothing);
      expect(find.byType(DoneRow), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(DownloadCard), findsNothing);
      expect(find.byType(DoneRow), findsOneWidget);
    });

    testWidgets(
      'finishing while the tab is hidden: no hold, no pop on return',
      (tester) async {
        await pumpWith(tester, [running('a'), failed('f')]);
        tabShown.value = false;
        await tester.pump();

        await emit(tester, [done('a'), failed('f')]);
        tabShown.value = true;
        // The first build back can still show the old Active snapshot; the
        // finished task arrives a frame or two later.
        await tester.pump();
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));

        expect(find.text('Saved'), findsNothing);
        expect(find.byType(DoneRow), findsOneWidget);
        expect(_check(tester), 1);
        await tester.pumpAndSettle();
        expect(find.byType(DownloadCard), findsNothing);
        expect(find.byType(DoneRow), findsOneWidget);
        expect(_check(tester), 1);
      },
    );

    testWidgets('a hold cut short by leaving the tab does not replay later', (
      tester,
    ) async {
      await pumpWith(tester, [running('a'), failed('f')]);
      await emit(tester, [done('a'), failed('f')]);
      await tester.pump(savedHold ~/ 2);
      expect(find.text('Saved'), findsOneWidget);

      tabShown.value = false;
      await tester.pump();
      await tester.pump(const Duration(minutes: 1));
      tabShown.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      await tester.pump(_remove);

      expect(find.text('Saved'), findsNothing);
      expect(find.byType(DownloadCard), findsNothing);
      expect(find.byType(DoneRow), findsOneWidget);
      expect(_check(tester), 1);
    });
  });

  group('the Done check', () {
    testWidgets('pops for a download finished while the list is open', (
      tester,
    ) async {
      await pumpWith(tester, [done('old')]);

      // Finished from the queue: no card to hold, the row arrives at once.
      await emit(tester, [done('new'), done('old')]);
      await tester.pump(DoneRow.popDuration ~/ 8);

      expect(_check(tester), lessThan(1));
      expect(_check(tester, at: 1), 1);
      await tester.pumpAndSettle();
      expect(_check(tester), 1);
    });

    testWidgets('does not pop for a row that comes back (Undo)', (
      tester,
    ) async {
      await pumpWith(tester, [done('a'), failed('f')]);

      // Hidden, then shown again, as a delete and its Undo do.
      await emit(tester, [failed('f')]);
      await tester.pumpAndSettle();
      await emit(tester, [done('a'), failed('f')]);
      await tester.pump(DoneRow.popDuration ~/ 8);

      expect(_slot(tester, find.byType(DoneRow)), greaterThan(0));
      expect(_check(tester), 1);
      await tester.pumpAndSettle();
    });

    testWidgets('does not pop for a row that scrolls in later', (tester) async {
      await pumpWith(tester, [for (var i = 0; i < 30; i++) failed('f$i')]);

      await emit(tester, [
        for (var i = 0; i < 30; i++) failed('f$i'),
        done('new'),
      ]);
      await tester.pumpAndSettle();
      expect(find.byType(DoneRow), findsNothing);

      await tester.scrollUntilVisible(find.byType(DoneRow), 300);
      await tester.pump(DoneRow.popDuration ~/ 8);
      expect(_check(tester), 1);
    });
  });
}
