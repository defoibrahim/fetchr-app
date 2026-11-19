import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/modules/downloader/domain/entities/download_task.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../core/widgets/widget_harness.dart';
import '../../../../support/fixtures.dart';
import '../../../../support/haptics.dart';
import 'downloads_view_harness.dart';

final _pauseButton = find.byTooltip('Pause download');
final _resumeButton = find.byTooltip('Resume download');

void main() {
  setUp(setUpDownloadsHarness);

  testWidgets('Pause swaps to Resume before native answers', (tester) async {
    final reply = Completer<Result<void>>();
    when(() => pause('a')).thenAnswer((_) => reply.future);
    await pumpWith(tester, [running()]);

    await tester.tap(_pauseButton);
    await tester.pumpAndSettle();
    expect(_resumeButton, findsOneWidget);
    expect(_pauseButton, findsNothing);
    expect(find.textContaining('Paused'), findsOneWidget);

    reply.complete(const Ok(null));
    await emit(tester, [running().withStatus(TaskStatus.paused)]);
    await tester.pumpAndSettle();
    expect(_resumeButton, findsOneWidget);
  });

  testWidgets('a second tap before the snapshot is swallowed', (tester) async {
    await pumpWith(tester, [running()]);

    await tester.tap(_pauseButton);
    await tester.pumpAndSettle();
    await tester.tap(_resumeButton);
    await tester.pump();

    verify(() => pause('a')).called(1);
    verifyNever(() => resume(any()));

    // Native confirms; Resume works again.
    await emit(tester, [running().withStatus(TaskStatus.paused)]);
    await tester.tap(_resumeButton);
    await tester.pump();
    verify(() => resume('a')).called(1);
    await tester.pumpAndSettle();
  });

  testWidgets('a failed pause brings Pause back and says why', (tester) async {
    when(
      () => pause('a'),
    ).thenAnswer((_) async => const Err<void>(UnexpectedFailure()));
    await pumpWith(tester, [running()]);

    await tester.tap(_pauseButton);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(_pauseButton, findsOneWidget);
    expect(_resumeButton, findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('the icon cross-fades: both are up mid-way', (tester) async {
    await pumpWith(tester, [running()]);
    await tester.tap(_pauseButton);
    await tester.pump();
    await tester.pump(Motion.fast ~/ 2);
    expect(_pauseButton, findsOneWidget);
    expect(_resumeButton, findsOneWidget);
    await tester.pumpAndSettle();
    expect(_pauseButton, findsNothing);
  });

  testWidgets('reduce motion: the icon swaps on the next frame', (
    tester,
  ) async {
    reduceMotion(tester);
    await pumpWith(tester, [running()]);
    await tester.tap(_pauseButton);
    await tester.pump();
    await tester.pump();
    expect(_pauseButton, findsNothing);
    expect(_resumeButton, findsOneWidget);
  });

  testWidgets('a progress tick does not restart the status line fade', (
    tester,
  ) async {
    await pumpWith(tester, [running()]);
    expect(find.textContaining('64%'), findsOneWidget);
    await emit(tester, [
      downloadTask(
        id: 'a',
        stage: TaskStage.downloading,
        progress: .7,
        downloadedBytes: 129 * mb,
        totalBytes: 184 * mb,
        speed: mb,
        etaSec: 55,
      ),
    ]);
    await tester.pump(Motion.fast ~/ 2);
    // The same line with new numbers, not an old and a new one fading.
    expect(find.textContaining('64%'), findsNothing);
    expect(find.textContaining('70%'), findsOneWidget);
  });

  testWidgets('Cancel shows the cancelled card at once and warns', (
    tester,
  ) async {
    final calls = recordHaptics(tester);
    final reply = Completer<Result<void>>();
    when(() => cancel('a')).thenAnswer((_) => reply.future);
    await pumpWith(tester, [running()]);

    await tester.tap(find.byTooltip('Cancel download'));
    await tester.pump();
    expect(find.text('Cancelled · partial file removed'), findsOneWidget);
    expect(calls, ['HapticFeedbackType.mediumImpact']);

    // Restart waits for native to confirm the cancel.
    await tester.tap(find.text('Restart'));
    await tester.pump();
    verifyNever(() => retry(any()));

    reply.complete(const Ok(null));
    await emit(tester, [running().withStatus(TaskStatus.canceled)]);
    await tester.tap(find.text('Restart'));
    await tester.pump();
    verify(() => retry('a')).called(1);
  });
}
