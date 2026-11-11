import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/errors/error_messages.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/core/widgets/error_card.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/attention_row.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/done_row.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/notification_hint.dart';
import 'package:mocktail/mocktail.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/widgets/widget_harness.dart';
import '../../../../support/snackbar.dart';
import 'downloads_view_harness.dart';

void main() {
  setUp(setUpDownloadsHarness);

  group('needs attention', () {
    testWidgets('shows the title and the short reason', (tester) async {
      await pumpWith(tester, [failed('f')]);

      expect(find.byType(ErrorCard), findsOneWidget);
      expect(find.text('Video f'), findsOneWidget);
      expect(find.text('Connection dropped at 41%'), findsOneWidget);
    });

    testWidgets('Retry retries that task', (tester) async {
      await pumpWith(tester, [failed('f')]);

      await tester.tap(find.text('Retry'));
      await tester.pump();

      verify(() => retry('f')).called(1);
      verifyNever(() => remove(any()));
    });

    testWidgets('a task that could not write offers Open settings', (
      tester,
    ) async {
      // Wider than a phone: the test font is an em wide, so the two-word
      // action would squeeze the title to nothing.
      await pumpWith(tester, [
        failed('f', code: 'permission_denied'),
      ], size: const Size(600, 812));

      expect(find.text("Fetchr can't save files"), findsOneWidget);
      expect(find.text('Retry'), findsNothing);

      await tester.tap(find.text('Open settings'));
      await tester.pump();

      verify(() => permission.openSettings()).called(1);
      verifyNever(() => retry(any()));
    });

    testWidgets('Remove hides the row, then removes the task', (tester) async {
      await pumpWith(tester, [failed('f')]);

      await tester.tap(find.byTooltip('Remove'));
      await tester.pump();

      expect(find.byType(AttentionRow), findsNothing);
      verifyNever(() => remove(any()));

      await pumpSnackbarIn(tester);
      await pumpUndoExpired(tester);

      verify(() => remove('f')).called(1);
      verifyNever(() => retry(any()));
    });

    testWidgets('acts on the tapped row, not the first one', (tester) async {
      await pumpWith(tester, [failed('b'), failed('a')]);

      await tester.tap(find.byTooltip('Remove').last);
      await tester.pump();

      final left = tester.widgetList<AttentionRow>(find.byType(AttentionRow));
      expect(left.map((row) => row.task.id), ['b']);
    });

    group('an unknown failure', () {
      const line = 'ERROR: [generic] Unable to extract uploader id';
      late List<String> clipboard;

      setUp(() => clipboard = []);

      Future<void> pumpUnknown(WidgetTester tester, {String? message}) async {
        await pumpWith(tester, [
          failed('f', code: 'unknown', message: message),
        ]);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboard.add((call.arguments as Map)['text'] as String);
            }
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
      }

      testWidgets('shows the raw yt-dlp line when tapped', (tester) async {
        await pumpUnknown(tester, message: line);

        await tester.tap(find.text('Download failed').first);
        await tester.pumpAndSettle();

        expect(find.text(line), findsOneWidget);
        expect(find.text('Copy'), findsOneWidget);
        expect(find.text('Close'), findsOneWidget);
      });

      testWidgets('Copy copies it and says so', (tester) async {
        await pumpUnknown(tester, message: line);
        await tester.tap(find.text('Download failed').first);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Copy'));
        await tester.pumpAndSettle();

        expect(clipboard, [line]);
        expect(find.text('Copied'), findsOneWidget);
        expect(find.text('Copy'), findsNothing);
      });

      testWidgets('Close copies nothing', (tester) async {
        await pumpUnknown(tester, message: line);
        await tester.tap(find.text('Download failed').first);
        await tester.pumpAndSettle();

        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();

        expect(clipboard, isEmpty);
        expect(find.text('Copied'), findsNothing);
        expect(find.text(line), findsNothing);
      });

      testWidgets('with no line there is nothing to show', (tester) async {
        await pumpUnknown(tester);

        await tester.tap(find.text('Video f'));
        await tester.pumpAndSettle();

        expect(find.text('Copy'), findsNothing);
      });
    });

    testWidgets('a known failure opens no dialog on a tap', (tester) async {
      await pumpWith(tester, [
        failed('f', code: 'unavailable', message: 'ERROR: gone'),
      ]);

      await tester.tap(find.text('Video f'));
      await tester.pumpAndSettle();

      expect(find.text('ERROR: gone'), findsNothing);
      expect(find.text('Copy'), findsNothing);
    });
  });

  group('done today', () {
    testWidgets('shows the title, the folder and the size', (tester) async {
      await pumpWith(tester, [done()]);

      expect(find.text('Video d'), findsOneWidget);
      expect(find.text('Movies/Fetchr · 96 MB'), findsOneWidget);
    });

    testWidgets(
      'the folder and size stay left to right in a right to left app',
      (tester) async {
        useView(tester);
        await tester.pumpWidget(
          themed(
            Directionality(
              textDirection: TextDirection.rtl,
              child: DoneRow(
                task: done(),
                onPlay: () {},
                onShowInFolder: () {},
                onDelete: () {},
              ),
            ),
          ),
        );

        final meta = find.text('Movies/Fetchr · 96 MB');
        expect(
          tester.widget<Text>(meta).textDirection ??
              Directionality.of(tester.element(meta)),
          TextDirection.ltr,
        );
      },
    );

    testWidgets('a tap opens the player on the saved file', (tester) async {
      await pumpWith(tester, [done('d', 'content://media/7')]);

      await tester.tap(find.text('Video d'));
      await tester.pumpAndSettle();

      expect(find.text('player content://media/7 Video d'), findsOneWidget);
    });

    testWidgets('a long press opens Play, Show in folder and Delete file', (
      tester,
    ) async {
      await pumpWith(tester, [done()]);

      await tester.longPress(find.text('Video d'));
      await tester.pump();

      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Show in folder'), findsOneWidget);
      expect(find.text('Delete file'), findsOneWidget);
    });

    testWidgets('the menu plays the file', (tester) async {
      await pumpWith(tester, [done('d', 'content://media/7')]);
      await tester.longPress(find.text('Video d'));
      await tester.pump();

      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      expect(find.text('player content://media/7 Video d'), findsOneWidget);
    });

    testWidgets('the menu shows the file in its folder', (tester) async {
      await pumpWith(tester, [done('d', 'content://media/7')]);
      await tester.longPress(find.text('Video d'));
      await tester.pump();

      await tester.tap(find.text('Show in folder'));
      await tester.pump();

      verify(() => openFolder('content://media/7')).called(1);
    });

    testWidgets('a folder that cannot open shows the failure', (tester) async {
      when(
        () => openFolder(any()),
      ).thenAnswer((_) async => const Err<void>(UnexpectedFailure()));
      await pumpWith(tester, [done()]);
      await tester.longPress(find.text('Video d'));
      await tester.pump();

      await tester.tap(find.text('Show in folder'));
      await tester.pump();
      await tester.pump();

      expect(find.text(ErrorMessages.unexpected), findsOneWidget);
    });

    Future<void> openDeleteDialog(WidgetTester tester) async {
      await tester.longPress(find.text('Video d'));
      await tester.pump();
      await tester.tap(find.text('Delete file'));
      await tester.pumpAndSettle();
    }

    testWidgets('Delete file asks first, with the file in the dialog', (
      tester,
    ) async {
      await pumpWith(tester, [done('d', null, 'Cliffside')]);
      await tester.longPress(find.text('Cliffside'));
      await tester.pump();
      await tester.tap(find.text('Delete file'));
      await tester.pumpAndSettle();

      expect(find.text('Delete this file?'), findsOneWidget);
      expect(
        find.text(
          '“Cliffside” will be removed from your phone and from Gallery.',
        ),
        findsOneWidget,
      );
      expect(find.text('Best · MP4'), findsOneWidget);
      expect(find.text('96 MB'), findsOneWidget);
      verifyNever(() => remove(any()));
    });

    testWidgets('Cancel keeps the file', (tester) async {
      await pumpWith(tester, [done()]);
      await openDeleteDialog(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(DoneRow), findsOneWidget);
      verifyNever(() => remove(any()));
    });

    testWidgets('Delete hides the row, then deletes after the Undo window', (
      tester,
    ) async {
      await pumpWith(tester, [done()]);
      await openDeleteDialog(tester);

      await tester.tap(find.text('Delete'));
      await tester.pump();

      expect(find.byType(DoneRow), findsNothing);
      expect(find.text('Deleted'), findsOneWidget);
      verifyNever(() => remove(any()));

      await pumpSnackbarIn(tester);
      await pumpUndoExpired(tester);

      verify(() => remove('d')).called(1);
    });

    testWidgets('Undo restores the row and deletes nothing', (tester) async {
      await pumpWith(tester, [done()]);
      await openDeleteDialog(tester);
      await tester.tap(find.text('Delete'));
      await tester.pump();
      await pumpSnackbarIn(tester);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(find.byType(DoneRow), findsOneWidget);
      verifyNever(() => remove(any()));
    });

    testWidgets('a declined system dialog brings the row back', (tester) async {
      when(() => remove('d')).thenAnswer((_) async => const Ok(false));
      await pumpWith(tester, [done()]);
      await openDeleteDialog(tester);
      await tester.tap(find.text('Delete'));
      await tester.pump();
      await pumpSnackbarIn(tester);
      await pumpUndoExpired(tester);

      expect(find.byType(DoneRow), findsOneWidget);
    });
  });

  group('notification hint', () {
    testWidgets('is hidden while notifications are allowed', (tester) async {
      await pumpWith(tester, [running()]);

      expect(find.byType(NotificationHint), findsOneWidget);
      expect(find.text('Allow'), findsNothing);
    });

    testWidgets('shows once they are off, even with nothing to list', (
      tester,
    ) async {
      when(
        () => permission.status(),
      ).thenAnswer((_) async => PermissionStatus.denied);
      await pumpWith(tester, const []);

      expect(
        find.text(
          "Notifications are off. Downloads still run, but you won't see "
          'progress outside the app.',
        ),
        findsOneWidget,
      );
      expect(find.text('Allow'), findsOneWidget);
    });

    testWidgets('Allow asks, and the hint goes once they are on', (
      tester,
    ) async {
      var granted = false;
      when(() => permission.status()).thenAnswer(
        (_) async =>
            granted ? PermissionStatus.granted : PermissionStatus.denied,
      );
      when(() => permission.request()).thenAnswer((_) async {
        granted = true;
        return PermissionStatus.granted;
      });
      await pumpWith(tester, const []);

      await tester.tap(find.text('Allow'));
      await tester.pump();
      await tester.pump();

      verify(() => permission.request()).called(1);
      verifyNever(() => permission.openSettings());
      expect(find.text('Allow'), findsNothing);
    });

    testWidgets('a refusal keeps the hint', (tester) async {
      when(
        () => permission.status(),
      ).thenAnswer((_) async => PermissionStatus.denied);
      when(
        () => permission.request(),
      ).thenAnswer((_) async => PermissionStatus.denied);
      await pumpWith(tester, const []);

      await tester.tap(find.text('Allow'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Allow'), findsOneWidget);
      verifyNever(() => permission.openSettings());
    });

    testWidgets('when Android will not ask again it opens the settings', (
      tester,
    ) async {
      when(
        () => permission.status(),
      ).thenAnswer((_) async => PermissionStatus.denied);
      when(
        () => permission.request(),
      ).thenAnswer((_) async => PermissionStatus.permanentlyDenied);
      await pumpWith(tester, const []);

      await tester.tap(find.text('Allow'));
      await tester.pump();
      await tester.pump();

      verify(() => permission.openSettings()).called(1);
      expect(find.text('Allow'), findsOneWidget);
    });

    testWidgets('is checked again when the app resumes', (tester) async {
      var granted = false;
      when(() => permission.status()).thenAnswer(
        (_) async =>
            granted ? PermissionStatus.granted : PermissionStatus.denied,
      );
      await pumpWith(tester, const []);
      expect(find.text('Allow'), findsOneWidget);

      granted = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();

      expect(find.text('Allow'), findsNothing);
    });

    testWidgets('a permission check that throws leaves the hint away', (
      tester,
    ) async {
      when(() => permission.status()).thenThrow(StateError('no plugin'));
      await pumpWith(tester, const []);

      expect(find.text('Allow'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
