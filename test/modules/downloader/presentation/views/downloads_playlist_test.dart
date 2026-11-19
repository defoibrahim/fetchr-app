import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/modules/downloader/domain/entities/download_task.dart';
import 'package:grabby/modules/downloader/presentation/views/playlist_detail_view.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/playlist_card.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../support/fixtures.dart';
import 'downloads_view_harness.dart';

const _mb = 1024 * 1024;

// 1 done, 2 on its way, 3 to 5 waiting, and a plain download beside them.
final _tasks = [
  playlistTask(1, status: TaskStatus.completed, totalBytes: 20 * _mb),
  playlistTask(
    2,
    status: TaskStatus.running,
    progress: .5,
    downloadedBytes: 10 * _mb,
    totalBytes: 20 * _mb,
    speed: _mb,
  ),
  playlistTask(3),
  playlistTask(4),
  playlistTask(5),
  downloadTask(id: 'single', status: TaskStatus.queued),
];

Future<void> _open(WidgetTester tester) async {
  await pumpWith(tester, _tasks);
  await tester.tap(find.text('Open queue'));
  await tester.pumpAndSettle();
  expect(find.byType(PlaylistDetailView), findsOneWidget);
}

void main() {
  setUp(setUpDownloadsHarness);

  testWidgets('a playlist is one card with its counts, not a row per '
      'video', (tester) async {
    await pumpWith(tester, _tasks);

    expect(find.byType(PlaylistCard), findsOneWidget);
    expect(find.text('Road trip'), findsOneWidget);
    expect(find.text('Playlist · Best · 5 videos'), findsOneWidget);
    expect(find.textContaining('/ 5 done'), findsOneWidget);
    expect(find.text('Video 3'), findsNothing);
    expect(find.text('Video single'), findsOneWidget);
  });

  testWidgets('the header ripple paints on the card, not under its fill', (
    tester,
  ) async {
    await pumpWith(tester, _tasks);
    final header = find.ancestor(
      of: find.text('Road trip'),
      matching: find.byType(InkWell),
    );
    // The nearest Material is the card itself: the ink lands on its surface.
    final material = tester.widget<Material>(
      find.ancestor(of: header, matching: find.byType(Material)).first,
    );
    expect(material.color, AppTokens.of(tester.element(header)).surface);
    expect(material.clipBehavior, Clip.antiAlias);
    expect(
      find.ancestor(of: header, matching: find.byType(DecoratedBox)),
      findsNothing,
    );
  });

  testWidgets('Pause all holds the waiting videos first, then the running '
      'one', (tester) async {
    await pumpWith(tester, _tasks);

    await tester.tap(find.text('Pause all'));
    await tester.pumpAndSettle();

    verifyInOrder([
      () => pause('v3'),
      () => pause('v4'),
      () => pause('v5'),
      () => pause('v2'),
    ]);
    verifyNever(() => pause('single'));
  });

  testWidgets('a paused playlist offers Resume all', (tester) async {
    await pumpWith(tester, [
      for (final task in _tasks.take(5))
        task.status == TaskStatus.completed
            ? task
            : playlistTask(
                task.request.playlistIndex!,
                status: TaskStatus.paused,
                progress: task.progress,
              ),
    ]);

    expect(find.text('Paused'), findsOneWidget);
    await tester.tap(find.text('Resume all'));
    await tester.pumpAndSettle();

    verify(() => resume('v2')).called(1);
  });

  testWidgets('a finished playlist leaves no card', (tester) async {
    await pumpWith(tester, [
      playlistTask(1, status: TaskStatus.completed, finishedAt: DateTime.now()),
    ]);

    expect(find.byType(PlaylistCard), findsNothing);
    expect(find.text('Video 1'), findsOneWidget);
  });

  group('detail', () {
    testWidgets('shows the video on its way, selected, and the queue', (
      tester,
    ) async {
      await _open(tester);

      expect(find.text('Downloading now'), findsOneWidget);
      expect(find.text('2 of 36'), findsOneWidget);
      expect(find.text('1 done · 4 to go'), findsOneWidget);
      expect(find.text('Downloading · 50%'), findsOneWidget);
      expect(find.text('Up next'), findsOneWidget);
      expect(find.text('#3'), findsOneWidget);
    });

    testWidgets('a tile selects its video and its action', (tester) async {
      await _open(tester);

      await tester.tap(find.bySemanticsLabel('Video 1, done'));
      await tester.pumpAndSettle();

      expect(find.text('Saved · 20 MB'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Play'), findsOneWidget);
    });

    testWidgets('skip applies at once; Undo queues it back in its place', (
      tester,
    ) async {
      await _open(tester);

      await tester.ensureVisible(find.byTooltip('Skip').at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Skip').at(1));
      await tester.pumpAndSettle();
      verify(() => cancel('v4')).called(1);
      expect(find.text('Skipped “Video 4”'), findsWidgets);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      verify(() => retry('v4')).called(1);
      verify(() => reorder(['v3', 'v4', 'v5'])).called(1);
    });

    testWidgets('stop pauses at once, leaves, and Undo resumes', (
      tester,
    ) async {
      await _open(tester);

      await tester.tap(find.text('Stop playlist'));
      await tester.pumpAndSettle();

      verify(() => pause('v2')).called(1);
      expect(find.byType(PlaylistDetailView), findsNothing);
      expect(find.byType(PlaylistCard), findsNothing);
      expect(find.text('Playlist stopped · 1 video kept'), findsWidgets);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      verifyNever(() => remove(any()));
      expect(find.byType(PlaylistCard), findsOneWidget);
    });

    testWidgets('stop drops the videos left once the snackbar closes', (
      tester,
    ) async {
      await _open(tester);

      await tester.tap(find.text('Stop playlist'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();

      for (final id in ['v2', 'v3', 'v4', 'v5']) {
        verify(() => remove(id)).called(1);
      }
      verifyNever(() => remove('v1'));
    });
  });
}
