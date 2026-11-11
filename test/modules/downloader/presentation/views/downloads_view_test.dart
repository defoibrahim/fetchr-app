import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/shared/domain/entities/quality.dart';
import 'package:grabby/core/errors/error_messages.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/core/widgets/app_progress_bar.dart';
import 'package:grabby/core/widgets/empty_view.dart';
import 'package:grabby/core/widgets/error_view.dart';
import 'package:grabby/core/widgets/loading_view.dart';
import 'package:grabby/modules/downloader/domain/entities/download_task.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/done_row.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/download_card.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../support/fixtures.dart';
import '../../../../support/snackbar.dart';
import 'downloads_view_harness.dart';

void main() {
  setUp(setUpDownloadsHarness);

  group('states', () {
    testWidgets('shows loading until the first snapshot', (tester) async {
      await pumpView(tester);

      expect(find.text('Downloads'), findsOneWidget);
      expect(find.byType(LoadingView), findsOneWidget);
      expect(find.text('Keeps running when you close the app'), findsNothing);
    });

    testWidgets('an empty snapshot shows the empty state', (tester) async {
      await pumpWith(tester, const []);

      expect(find.byType(EmptyView), findsOneWidget);
      expect(find.byType(LoadingView), findsNothing);
      expect(find.text('Nothing downloading'), findsOneWidget);
      expect(
        find.text(
          'Active, queued and failed downloads appear here, even after you '
          'close the app.',
        ),
        findsOneWidget,
      );
      expect(find.text('Keeps running when you close the app'), findsNothing);
    });

    testWidgets('Paste a link goes Home', (tester) async {
      await pumpWith(tester, const []);

      await tester.tap(find.text('Paste a link'));
      await tester.pumpAndSettle();

      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('yesterday\'s downloads leave the screen empty', (
      tester,
    ) async {
      await pumpWith(tester, [
        downloadTask(
          id: 'old',
          status: TaskStatus.completed,
          finishedAt: DateTime.now().subtract(const Duration(days: 2)),
        ),
      ]);

      expect(find.byType(EmptyView), findsOneWidget);
      expect(find.byType(DoneRow), findsNothing);
    });

    testWidgets('with work to show, the header says it keeps running', (
      tester,
    ) async {
      await pumpWith(tester, [running()]);

      expect(find.text('Keeps running when you close the app'), findsOneWidget);
      expect(find.byType(EmptyView), findsNothing);
    });

    testWidgets('a Failure error shows its message and Retry reloads', (
      tester,
    ) async {
      await pumpView(tester);
      events.addError(const StorageFailure());
      await tester.pump();
      await tester.pump();

      expect(find.byType(ErrorView), findsOneWidget);
      expect(find.text(const StorageFailure().message), findsOneWidget);

      final reloaded = StreamController<List<DownloadTask>>();
      addTearDown(reloaded.close);
      when(() => watch()).thenAnswer((_) => reloaded.stream);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();

      expect(find.byType(LoadingView), findsOneWidget);
      expect(find.byType(ErrorView), findsNothing);

      reloaded.add([done()]);
      await tester.pump();
      await tester.pump();

      expect(find.byType(DoneRow), findsOneWidget);
      verify(() => watch()).called(2);
    });

    testWidgets('any other error shows the generic message', (tester) async {
      await pumpView(tester);
      events.addError(StateError('boom'));
      await tester.pump();
      await tester.pump();

      expect(find.text(ErrorMessages.unexpected), findsOneWidget);
      expect(find.textContaining('boom'), findsNothing);
    });
  });

  group('groups', () {
    testWidgets('are Active, then the queue, Needs attention, Done today', (
      tester,
    ) async {
      await pumpWith(tester, [
        done('d'),
        failed('f'),
        downloadTask(
          id: 'q',
          status: TaskStatus.queued,
          request: downloadRequest(title: 'Queued title'),
        ),
        running('r'),
      ]);

      double top(Finder finder) => tester.getTopLeft(finder).dy;
      final order = [
        top(find.text('ACTIVE')),
        top(find.text('Video r')),
        top(find.text('Queued title')),
        top(find.text('NEEDS ATTENTION')),
        top(find.text('Video f')),
        top(find.text('DONE TODAY')),
        top(find.text('Video d')),
      ];
      expect(order, [...order]..sort());
      expect(order.toSet(), hasLength(order.length));
    });

    testWidgets('an empty group is hidden', (tester) async {
      await pumpWith(tester, [done()]);

      expect(find.text('DONE TODAY'), findsOneWidget);
      expect(find.text('ACTIVE'), findsNothing);
      expect(find.text('NEEDS ATTENTION'), findsNothing);
    });

    testWidgets('a queue alone is still under Active', (tester) async {
      await pumpWith(tester, [
        downloadTask(id: 'q', status: TaskStatus.queued),
      ]);

      expect(find.text('ACTIVE'), findsOneWidget);
      expect(find.text('Queued'), findsOneWidget);
    });

    testWidgets('a new snapshot replaces the list', (tester) async {
      await pumpWith(tester, [running()]);
      expect(find.byType(DownloadCard), findsOneWidget);
      expect(find.byType(DoneRow), findsNothing);

      await emit(tester, [done('a')]);

      expect(find.byType(DownloadCard), findsNothing);
      expect(find.byType(DoneRow), findsOneWidget);
    });

    testWidgets('builds only the rows on screen', (tester) async {
      await pumpWith(tester, [for (var i = 0; i < 500; i++) done('d$i')]);

      expect(find.byType(DoneRow).evaluate().length, lessThan(30));
    });
  });

  group('download cards', () {
    testWidgets('Pause pauses that task', (tester) async {
      await pumpWith(tester, [running('a'), running('b')]);

      await tester.tap(find.byTooltip('Pause download').last);
      await tester.pump();

      verify(() => pause('b')).called(1);
      verifyNever(() => pause('a'));
    });

    testWidgets('Resume resumes a paused task', (tester) async {
      await pumpWith(tester, [
        downloadTask(id: 'p', status: TaskStatus.paused, progress: .3),
      ]);

      await tester.tap(find.byTooltip('Resume download'));
      await tester.pump();

      verify(() => resume('p')).called(1);
      verifyNever(() => pause(any()));
    });

    testWidgets('Cancel cancels, and the next snapshot shows Restart', (
      tester,
    ) async {
      await pumpWith(tester, [running()]);

      await tester.tap(find.byTooltip('Cancel download'));
      await tester.pump();
      verify(() => cancel('a')).called(1);

      await emit(tester, [downloadTask(id: 'a', status: TaskStatus.canceled)]);

      expect(find.text('Cancelled · partial file removed'), findsOneWidget);
      expect(find.text('Restart'), findsOneWidget);
    });

    testWidgets('Restart retries that task', (tester) async {
      await pumpWith(tester, [
        downloadTask(id: 'a', status: TaskStatus.canceled),
      ]);

      await tester.tap(find.text('Restart'));
      await tester.pump();

      verify(() => retry('a')).called(1);
    });

    testWidgets('Remove on a cancelled card hides it, then removes it', (
      tester,
    ) async {
      await pumpWith(tester, [
        downloadTask(id: 'a', status: TaskStatus.canceled),
      ]);

      await tester.tap(find.byTooltip('Remove'));
      await tester.pump();

      expect(find.byType(DownloadCard), findsNothing);
      expect(find.text('Removed'), findsOneWidget);
      verifyNever(() => remove(any()));

      await pumpSnackbarIn(tester);
      await pumpUndoExpired(tester);

      verify(() => remove('a')).called(1);
    });

    testWidgets('Undo brings a removed card back and removes nothing', (
      tester,
    ) async {
      await pumpWith(tester, [
        downloadTask(id: 'a', status: TaskStatus.canceled),
      ]);

      await tester.tap(find.byTooltip('Remove'));
      await tester.pump();
      await pumpSnackbarIn(tester);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(find.byType(DownloadCard), findsOneWidget);
      verifyNever(() => remove(any()));
    });

    testWidgets('a snapshot during the Undo window keeps the card hidden', (
      tester,
    ) async {
      final cancelled = downloadTask(id: 'a', status: TaskStatus.canceled);
      await pumpWith(tester, [cancelled]);
      await tester.tap(find.byTooltip('Remove'));
      await tester.pump();

      await emit(tester, [cancelled, running('b')]);

      final shown = tester.widgetList<DownloadCard>(find.byType(DownloadCard));
      expect(shown.map((card) => card.task.id), ['b']);
    });

    testWidgets('a failed action shows the failure in a snackbar', (
      tester,
    ) async {
      when(
        () => pause('a'),
      ).thenAnswer((_) async => const Err<void>(UnexpectedFailure()));
      await pumpWith(tester, [running()]);

      await tester.tap(find.byTooltip('Pause download'));
      await tester.pump();
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(ErrorMessages.unexpected), findsOneWidget);
    });

    testWidgets('a successful action shows no snackbar', (tester) async {
      await pumpWith(tester, [running()]);

      await tester.tap(find.byTooltip('Pause download'));
      await tester.pump();
      await tester.pump();

      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a bar follows the progress of its task', (tester) async {
      await pumpWith(tester, [running()]);

      expect(
        tester.widget<AppProgressBar>(find.byType(AppProgressBar)).value,
        .64,
      );
    });
  });

  group('queue', () {
    DownloadTask queued(String id, int minutesAgo, {double progress = 0}) =>
        downloadTask(
          id: id,
          status: TaskStatus.queued,
          progress: progress,
          createdAt: DateTime.now().subtract(Duration(minutes: minutesAgo)),
        );

    testWidgets('leads with the task that runs next and counts the rest', (
      tester,
    ) async {
      await pumpWith(tester, [queued('c', 1), queued('b', 2), queued('a', 3)]);

      expect(find.text('Video a'), findsOneWidget);
      expect(find.text('Queued · 2 more after this'), findsOneWidget);
      expect(find.text('Video b'), findsNothing);
      expect(find.text('Video c'), findsNothing);
    });

    testWidgets('a tap expands the rest in order, and again collapses', (
      tester,
    ) async {
      await pumpWith(tester, [queued('c', 1), queued('b', 2), queued('a', 3)]);

      await tester.tap(find.text('Video a'));
      await tester.pump();

      expect(find.text('Video b'), findsOneWidget);
      expect(find.text('Video c'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Video b')).dy,
        lessThan(tester.getTopLeft(find.text('Video c')).dy),
      );

      await tester.tap(find.text('Video a'));
      await tester.pump();

      expect(find.text('Video b'), findsNothing);
      expect(find.text('Video c'), findsNothing);
    });

    testWidgets('stays expanded when the snapshot changes', (tester) async {
      await pumpWith(tester, [queued('b', 1), queued('a', 2)]);
      await tester.tap(find.text('Video a'));
      await tester.pump();

      await emit(tester, [running('r'), queued('b', 1), queued('a', 2)]);

      expect(find.text('Video b'), findsOneWidget);
    });

    testWidgets('a lone task has nothing to expand', (tester) async {
      await pumpWith(tester, [queued('a', 1)]);

      await tester.tap(find.text('Video a'));
      await tester.pump();

      expect(find.text('Queued'), findsOneWidget);
      expect(find.text('Queued · 0 more after this'), findsNothing);
    });

    testWidgets('Cancel on the first row cancels it', (tester) async {
      await pumpWith(tester, [queued('b', 1), queued('a', 2)]);

      await tester.tap(find.byTooltip('Cancel download'));
      await tester.pump();

      verify(() => cancel('a')).called(1);
      verifyNever(() => cancel('b'));
    });

    testWidgets('Cancel on an expanded row cancels that one', (tester) async {
      await pumpWith(tester, [queued('b', 1), queued('a', 2)]);
      await tester.tap(find.text('Video a'));
      await tester.pump();

      await tester.tap(find.byTooltip('Cancel download').last);
      await tester.pump();

      verify(() => cancel('b')).called(1);
      verifyNever(() => cancel('a'));
    });

    testWidgets('a retried task says where it resumes from', (tester) async {
      await pumpWith(tester, [queued('a', 1, progress: .41)]);

      expect(find.text('Queued again · resumes from 41%'), findsOneWidget);
    });
  });

  group('on a wide window', () {
    testWidgets('keeps the cards at most 560 wide and centred', (tester) async {
      await pumpWith(tester, [running()], size: const Size(700, 1000));

      final card = tester.getRect(find.byType(DownloadCard));
      expect(card.width, lessThanOrEqualTo(560));
      expect(card.left, closeTo(700 - card.right, 1));
    });

    testWidgets('centres the empty state in the same column', (tester) async {
      await pumpWith(tester, const [], size: const Size(700, 1000));

      final empty = tester.getRect(find.byType(EmptyView));
      expect(empty.width, lessThanOrEqualTo(560));
      expect(empty.left, closeTo(700 - empty.right, 1));
    });
  });

  testWidgets('a quality tag shows on an audio card', (tester) async {
    await pumpWith(tester, [
      downloadTask(
        id: 'a',
        stage: TaskStage.downloading,
        progress: .5,
        request: downloadRequest(quality: Quality.mp3),
      ),
    ]);

    expect(find.text('MP3'), findsOneWidget);
  });
}
