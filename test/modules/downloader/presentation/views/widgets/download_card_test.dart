import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/shared/domain/entities/quality.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/widgets/app_progress_bar.dart';
import 'package:grabby/core/widgets/media_thumb.dart';
import 'package:grabby/modules/downloader/domain/entities/download_task.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/download_card.dart';

import '../../../../../core/widgets/widget_harness.dart';
import '../../../../../support/fixtures.dart';

class _Calls {
  final taps = <String>[];

  DownloadCard card(DownloadTask task) => DownloadCard(
    task: task,
    onPause: () => taps.add('pause'),
    onResume: () => taps.add('resume'),
    onCancel: () => taps.add('cancel'),
    onRestart: () => taps.add('restart'),
    onRemove: () => taps.add('remove'),
  );
}

DownloadTask _downloading({
  double progress = .64,
  bool stalled = false,
  int? totalBytes = 184 * mb,
}) => downloadTask(
  id: 'a',
  stage: TaskStage.downloading,
  progress: progress,
  downloadedBytes: 118 * mb,
  totalBytes: totalBytes,
  speed: (4.2 * mb).round(),
  etaSec: 16,
  stalled: stalled,
  request: downloadRequest(title: 'Desert drive at golden hour'),
);

void main() {
  for (final MapEntry(key: mode, value: theme) in themes.entries) {
    final tokens = theme.extension<AppTokens>()!;

    group(mode, () {
      late _Calls calls;

      Future<void> pump(WidgetTester tester, DownloadTask task) async {
        calls = _Calls();
        useView(tester);
        await tester.pumpWidget(
          themed(
            Align(alignment: Alignment.topCenter, child: calls.card(task)),
            theme: theme,
          ),
        );
        // Not pumpAndSettle: a starting or merging bar slides forever.
        await tester.pump(const Duration(milliseconds: 300));
      }

      AppProgressBar bar(WidgetTester tester) =>
          tester.widget<AppProgressBar>(find.byType(AppProgressBar));

      group('downloading', () {
        testWidgets('shows the title, the meta line and the stats', (
          tester,
        ) async {
          await pump(tester, _downloading());

          expect(find.text('Desert drive at golden hour'), findsOneWidget);
          expect(find.text('Best · MP4'), findsOneWidget);
          expect(find.text('64% · 118 / 184 MB'), findsOneWidget);
          expect(find.text('4.2 MB/s · 0:16 left'), findsOneWidget);
          expect(bar(tester).value, .64);
          expect(bar(tester).color, isNull);
        });

        testWidgets('the percent is in the text colour, the rest muted', (
          tester,
        ) async {
          await pump(tester, _downloading());

          final text = tester.widget<Text>(find.text('64% · 118 / 184 MB'));
          final spans = text.textSpan!.toStringDeep();
          expect(spans, contains('64%'));
          final root = text.textSpan! as TextSpan;
          final percent = root.children!.first as TextSpan;
          expect(percent.style!.color, tokens.text);
          expect(text.style!.color, tokens.textMuted);
        });

        testWidgets('offers Pause and Cancel, not Resume', (tester) async {
          await pump(tester, _downloading());

          expect(find.byTooltip('Pause download'), findsOneWidget);
          expect(find.byTooltip('Cancel download'), findsOneWidget);
          expect(find.byTooltip('Resume download'), findsNothing);
          expect(find.byType(Card), findsOneWidget);
        });

        testWidgets('Pause and Cancel call back', (tester) async {
          await pump(tester, _downloading());

          await tester.tap(find.byTooltip('Pause download'));
          await tester.tap(find.byTooltip('Cancel download'));

          expect(calls.taps, ['pause', 'cancel']);
        });

        testWidgets('the buttons are 44 dp squares', (tester) async {
          await pump(tester, _downloading());

          for (final label in ['Pause download', 'Cancel download']) {
            final size = tester.getSize(find.byTooltip(label));
            expect(size.width, greaterThanOrEqualTo(44));
            expect(size.height, greaterThanOrEqualTo(44));
          }
        });

        testWidgets('an unknown total shows bytes so far on a sliding bar', (
          tester,
        ) async {
          await pump(tester, _downloading(progress: -1, totalBytes: null));

          expect(find.text('118 MB'), findsOneWidget);
          expect(bar(tester).value, isNull);
        });

        testWidgets('a stalled download says it is waiting', (tester) async {
          await pump(tester, _downloading(stalled: true));

          expect(find.text('Waiting for network…'), findsOneWidget);
          expect(find.textContaining('MB/s'), findsNothing);
        });

        testWidgets('a playlist entry says where it is', (tester) async {
          await pump(
            tester,
            downloadTask(
              stage: TaskStage.downloading,
              progress: .2,
              request: downloadRequest(
                quality: Quality.p720,
                playlistIndex: 3,
                playlistCount: 18,
              ),
            ),
          );

          expect(find.text('720p · 3 of 18 in playlist'), findsOneWidget);
        });

        testWidgets('an audio download has the audio tile', (tester) async {
          await pump(
            tester,
            downloadTask(
              stage: TaskStage.downloading,
              progress: .2,
              request: downloadRequest(quality: Quality.mp3),
            ),
          );

          expect(
            tester.widget<MediaThumb>(find.byType(MediaThumb)).isAudio,
            isTrue,
          );
        });

        testWidgets('a video download has the video thumb', (tester) async {
          await pump(tester, _downloading());

          final thumb = tester.widget<MediaThumb>(find.byType(MediaThumb));
          expect(thumb.isAudio, isFalse);
          expect(thumb.image, isNull);
          expect(tester.getSize(find.byType(MediaThumb)), const Size(64, 38));
        });

        testWidgets('a thumbnail URL is loaded', (tester) async {
          await pump(
            tester,
            downloadTask(
              stage: TaskStage.downloading,
              progress: .2,
              request: downloadRequest(thumbnail: 'https://example.com/t.jpg'),
            ),
          );

          expect(
            tester.widget<MediaThumb>(find.byType(MediaThumb)).image,
            const NetworkImage('https://example.com/t.jpg'),
          );
        });

        testWidgets('a long title takes one line', (tester) async {
          await pump(
            tester,
            downloadTask(
              stage: TaskStage.downloading,
              progress: .2,
              request: downloadRequest(title: 'Very long title ' * 20),
            ),
          );

          final title = tester.widget<Text>(
            find.textContaining('Very long title'),
          );
          expect(title.maxLines, 1);
          expect(title.overflow, TextOverflow.ellipsis);
        });
      });

      group('starting', () {
        testWidgets('says Starting… on a sliding bar', (tester) async {
          await pump(tester, downloadTask(stage: TaskStage.preparing));

          expect(find.text('Starting…'), findsOneWidget);
          expect(bar(tester).value, isNull);
          expect(find.byTooltip('Pause download'), findsOneWidget);
          expect(find.byTooltip('Cancel download'), findsOneWidget);
        });
      });

      group('merging', () {
        Future<void> pumpMerging(WidgetTester tester, Quality quality) => pump(
          tester,
          downloadTask(
            stage: TaskStage.postProcessing,
            progress: -1,
            request: downloadRequest(quality: quality),
          ),
        );

        testWidgets('video and audio are merged on a sliding bar', (
          tester,
        ) async {
          await pumpMerging(tester, Quality.p720);

          expect(find.text('Merging video and audio…'), findsOneWidget);
          expect(bar(tester).value, isNull);
          expect(find.byTooltip('Pause download'), findsOneWidget);
        });

        testWidgets('audio is converted', (tester) async {
          await pumpMerging(tester, Quality.mp3);

          expect(find.text('Converting to MP3…'), findsOneWidget);
          expect(bar(tester).value, isNull, reason: 'before ffmpeg reports');
        });

        testWidgets('a reported conversion fills the bar with its percent', (
          tester,
        ) async {
          await pump(
            tester,
            downloadTask(
              stage: TaskStage.postProcessing,
              progress: .42,
              request: downloadRequest(quality: Quality.mp3),
            ),
          );

          expect(find.text('Converting to MP3…'), findsOneWidget);
          expect(find.text('42%'), findsOneWidget);
          expect(bar(tester).value, .42);
        });

        testWidgets('a cover is saved', (tester) async {
          await pumpMerging(tester, Quality.cover);

          expect(find.text('Saving cover…'), findsOneWidget);
        });
      });

      group('paused', () {
        final paused = downloadTask(
          status: TaskStatus.paused,
          progress: .64,
          downloadedBytes: 118 * mb,
          totalBytes: 184 * mb,
          request: downloadRequest(title: 'Desert drive at golden hour'),
        );

        testWidgets('says where it stopped, on a muted bar', (tester) async {
          await pump(tester, paused);

          expect(find.text('Paused at 64% · 118 / 184 MB'), findsOneWidget);
          expect(bar(tester).value, .64);
          expect(bar(tester).color, tokens.textMuted);
        });

        testWidgets('offers Resume and Cancel, not Pause', (tester) async {
          await pump(tester, paused);

          expect(find.byTooltip('Resume download'), findsOneWidget);
          expect(find.byTooltip('Cancel download'), findsOneWidget);
          expect(find.byTooltip('Pause download'), findsNothing);
        });

        testWidgets('Resume and Cancel call back', (tester) async {
          await pump(tester, paused);

          await tester.tap(find.byTooltip('Resume download'));
          await tester.tap(find.byTooltip('Cancel download'));

          expect(calls.taps, ['resume', 'cancel']);
        });

        testWidgets('a paused task with no progress keeps an empty bar', (
          tester,
        ) async {
          await pump(
            tester,
            downloadTask(status: TaskStatus.paused, progress: -1),
          );

          expect(find.text('Paused'), findsOneWidget);
          expect(bar(tester).value, 0);
        });
      });

      group('cancelled', () {
        final cancelled = downloadTask(
          status: TaskStatus.canceled,
          request: downloadRequest(title: 'Desert drive at golden hour'),
        );

        testWidgets('is a dashed card with Restart and Remove', (tester) async {
          await pump(tester, cancelled);

          expect(find.text('Desert drive at golden hour'), findsOneWidget);
          expect(find.text('Cancelled · partial file removed'), findsOneWidget);
          expect(find.text('Restart'), findsOneWidget);
          expect(find.byTooltip('Remove'), findsOneWidget);
          expect(find.byType(AppProgressBar), findsNothing);
          expect(find.byTooltip('Pause download'), findsNothing);
          // Not the solid Card: the border is drawn in dashes.
          expect(find.byType(Card), findsNothing);
        });

        testWidgets('draws its border in borderStrong', (tester) async {
          await pump(tester, cancelled);

          // The card's own paint is the outermost one; the buttons have more.
          final dashed = find
              .descendant(
                of: find.byType(DownloadCard),
                matching: find.byType(CustomPaint),
              )
              .first;
          final painter = tester.widget<CustomPaint>(dashed).foregroundPainter!;

          final canvas = TestRecordingCanvas();
          painter.paint(canvas, const Size(300, 80));
          final dashes = [
            for (final call in canvas.invocations)
              if (call.invocation.memberName == #drawPath)
                call.invocation.positionalArguments[1] as Paint,
          ];
          // 4 on, 3 off along about 730 dp of outline.
          expect(dashes.length, inInclusiveRange(90, 120));
          for (final dash in dashes) {
            // Paint keeps 8-bit channels.
            expect(dash.color.toARGB32(), tokens.borderStrong.toARGB32());
            expect(dash.style, PaintingStyle.stroke);
            expect(dash.strokeWidth, 1);
          }
        });

        testWidgets('Restart and Remove call back', (tester) async {
          await pump(tester, cancelled);

          await tester.tap(find.text('Restart'));
          await tester.tap(find.byTooltip('Remove'));

          expect(calls.taps, ['restart', 'remove']);
        });
      });

      testWidgets('is not for queued, failed or finished tasks', (
        tester,
      ) async {
        for (final status in [
          TaskStatus.queued,
          TaskStatus.failed,
          TaskStatus.completed,
        ]) {
          expect(
            () => _Calls().card(downloadTask(status: status)),
            throwsAssertionError,
          );
        }
      });
    });
  }

  group('at the narrowest phone with the largest text', () {
    final tasks = {
      'downloading': _downloading(),
      'unknown size': _downloading(progress: -1, totalBytes: null),
      'stalled': _downloading(stalled: true),
      'starting': downloadTask(
        stage: TaskStage.preparing,
        request: downloadRequest(title: 'A long title ' * 12),
      ),
      'paused': downloadTask(
        status: TaskStatus.paused,
        progress: .64,
        downloadedBytes: 118 * mb,
        totalBytes: 184 * mb,
        request: downloadRequest(title: 'A long title ' * 12),
      ),
      'cancelled': downloadTask(
        status: TaskStatus.canceled,
        request: downloadRequest(title: 'A long title ' * 12),
      ),
    };

    for (final MapEntry(key: name, value: task) in tasks.entries) {
      testWidgets('$name does not overflow', (tester) async {
        await pumpThemed(
          tester,
          _Calls().card(task),
          size: const Size(320, 640),
          textScale: 1.3,
        );
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull);
        expect(find.byType(DownloadCard), findsOneWidget);
      });
    }

    testWidgets('a downloading card keeps Pause, Cancel and its progress', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      try {
        await pumpThemed(
          tester,
          _Calls().card(_downloading()),
          size: const Size(320, 640),
          textScale: 1.3,
        );
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull);
        const screen = Rect.fromLTWH(0, 0, 320, 640);
        for (final label in ['Pause download', 'Cancel download']) {
          final button = tester.getRect(find.byTooltip(label));
          expect(screen.expandToInclude(button), screen, reason: label);
        }
        final progress = tester.getSemantics(find.byType(AppProgressBar));
        expect(progress.value, '64%');
        expect(progress.label, 'Download progress');
      } finally {
        handle.dispose();
      }
    });
  });

  group('in a right to left app', () {
    Future<void> pumpRtl(WidgetTester tester, DownloadTask task) async {
      useView(tester);
      await tester.pumpWidget(
        themed(
          Directionality(
            textDirection: TextDirection.rtl,
            child: Align(
              alignment: Alignment.topCenter,
              child: _Calls().card(task),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('the meta line and the stats stay left to right', (
      tester,
    ) async {
      await pumpRtl(tester, _downloading());

      for (final text in [
        'Best · MP4',
        '64% · 118 / 184 MB',
        '4.2 MB/s · 0:16 left',
      ]) {
        expect(
          directionOf(tester, find.text(text)),
          TextDirection.ltr,
          reason: text,
        );
      }
    });

    testWidgets('where a paused download stopped stays left to right', (
      tester,
    ) async {
      await pumpRtl(
        tester,
        downloadTask(
          status: TaskStatus.paused,
          progress: .64,
          downloadedBytes: 118 * mb,
          totalBytes: 184 * mb,
        ),
      );

      expect(
        directionOf(tester, find.text('Paused at 64% · 118 / 184 MB')),
        TextDirection.ltr,
      );
    });
  });
}
