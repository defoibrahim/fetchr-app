import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/core/utils/formatters.dart';
import 'package:grabby/core/utils/scale.dart';
import 'package:grabby/modules/downloader/domain/entities/download_task.dart';
import 'package:grabby/modules/library/domain/entities/library_item.dart';
import 'package:grabby/modules/library/presentation/formatters/library_item_formatter.dart';
import 'package:grabby/modules/library/presentation/views/player_view.dart';
import 'package:grabby/modules/library/presentation/views/widgets/player_controls.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../core/widgets/widget_harness.dart';
import '../../../../support/fixtures.dart';
import '../../../../support/snackbar.dart';
import 'player_view_harness.dart';

void stubSavedTask() => when(downloader.watchTasks).thenAnswer(
  (_) => Stream.value([
    downloadTask(
      status: TaskStatus.completed,
      savedUri: videoItem.uri,
      request: downloadRequest(
        url: 'https://www.youtube.com/watch?v=1',
        uploader: 'Open Road Films',
      ),
    ),
  ]),
);

void main() {
  setUp(setUpPlayerHarness);

  group('the picture', () {
    testWidgets('opens the file it was given', (tester) async {
      await pumpPlayer(tester, videoItem);

      final media =
          verify(() => player.open(captureAny())).captured.single as Media;
      expect(media.uri, Media(videoItem.uri).uri);
    });

    testWidgets('a video shows the video surface', (tester) async {
      await pumpPlayer(tester, videoItem);

      expect(find.byKey(videoKey), findsOneWidget);
    });

    testWidgets('an audio file shows the audio tile instead', (tester) async {
      await pumpPlayer(tester, songItem);

      expect(find.byKey(videoKey), findsNothing);
      expect(inControls(find.byType(ColoredBox)), findsWidgets);
    });

    testWidgets('is 16:9 across the width', (tester) async {
      await pumpPlayer(tester, videoItem);

      final size = tester.getSize(find.byType(PlayerControls).first);
      expect(size.width, designSize.width);
      expect(size.height, closeTo(designSize.width * 9 / 16, .01));
    });

    testWidgets('an unknown file still plays, as a video', (tester) async {
      await pumpPlayer(
        tester,
        libraryItem(uri: 'content://elsewhere/9', name: 'Elsewhere.mp4'),
      );

      verify(() => player.open(any())).called(1);
      expect(find.byKey(videoKey), findsOneWidget);
    });
  });

  group('the page', () {
    testWidgets('has a Back row that goes back', (tester) async {
      await pumpPlayer(tester, videoItem);

      expect(find.text('Back'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('library'), findsOneWidget);
    });

    testWidgets('shows the title, in up to three lines', (tester) async {
      await pumpPlayer(tester, videoItem);

      final title = tester.widget<Text>(find.text(videoItem.name));
      expect(title.maxLines, 3);
    });

    testWidgets('while the library loads it shows the route title only', (
      tester,
    ) async {
      final pending = Completer<Result<List<LibraryItem>>>();
      await pumpPlayer(
        tester,
        videoItem,
        title: 'From the route',
        list: () => pending.future,
      );

      expect(find.text('From the route'), findsOneWidget);
      expect(find.text('Quality'), findsNothing);
      expect(find.text('Share'), findsNothing);
      verify(() => player.open(any())).called(1);

      pending.complete(Ok([videoItem]));
      await tester.pumpAndSettle();

      expect(find.text(videoItem.name), findsOneWidget);
      expect(find.text('Quality'), findsOneWidget);
    });

    testWidgets('an unknown file has no info list and no Share or Delete', (
      tester,
    ) async {
      await pumpPlayer(
        tester,
        libraryItem(uri: 'content://elsewhere/9', name: 'Elsewhere.mp4'),
      );

      expect(find.text('Elsewhere.mp4'), findsOneWidget);
      expect(find.text('Quality'), findsNothing);
      expect(find.text('Share'), findsNothing);
      expect(find.text('Delete'), findsNothing);
    });

    testWidgets('lists the quality, size, date and location of a video', (
      tester,
    ) async {
      await pumpPlayer(tester, videoItem);

      for (final label in ['Quality', 'Size', 'Saved', 'Location']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('1080p · MP4'), findsOneWidget);
      expect(find.text(formatBytes(5452595)), findsOneWidget);
      expect(find.text('15 Oct 2026, 16:02'), findsOneWidget);
      expect(
        find.text('Movies/Fetchr/Desert drive at golden hour.mp4'),
        findsOneWidget,
      );
    });

    testWidgets('lists an audio file as MP3', (tester) async {
      await pumpPlayer(tester, songItem);

      expect(find.text('MP3'), findsOneWidget);
      expect(find.text('6.2 MB'), findsOneWidget);
      expect(find.text(songItem.location), findsOneWidget);
    });

    testWidgets('the location reads left to right and wraps without overflow', (
      tester,
    ) async {
      final long = libraryItem(
        uri: 'content://long/1',
        name: '${'A_very_long_name_without_breaks_' * 4}.mp4',
        relativePath: 'Movies/Fetchr/',
      );
      when(
        () => libraryRepository.list(any()),
      ).thenAnswer((_) async => Ok([long]));
      await pumpPlayer(tester, long, size: const Size(320, 640));

      final text = tester.widget<Text>(find.text(long.location));
      expect(text.textDirection, TextDirection.ltr);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows where it came from only for a task that saved it', (
      tester,
    ) async {
      stubSavedTask();
      await pumpPlayer(tester, videoItem);

      expect(find.text('youtube.com · Open Road Films'), findsOneWidget);
    });

    testWidgets('hides the source line without a matching task', (
      tester,
    ) async {
      await pumpPlayer(tester, videoItem);

      expect(find.textContaining(' · Open Road'), findsNothing);
      expect(find.textContaining('youtube'), findsNothing);
    });

    testWidgets('the page scrolls when it does not fit', (tester) async {
      await pumpPlayer(tester, videoItem, size: const Size(640, 360));

      expect(find.byType(SingleChildScrollView), findsOneWidget);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -300),
      );
      await tester.pump();
      expect(find.text('Quality'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // The drag opened a double-tap window.
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('fits the largest text on a small screen', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpPlayer(tester, videoItem, size: const Size(320, 640));

      expect(tester.takeException(), isNull);
      expect(find.text('Quality'), findsOneWidget);
    });
  });

  group('the layout', () {
    Rect video(WidgetTester tester) => tester.getRect(find.byKey(videoKey));
    Rect title(WidgetTester tester) =>
        tester.getRect(find.text(videoItem.name));

    for (final width in [840.0, 900.0]) {
      testWidgets('${width.round()} dp splits: video left, details right', (
        tester,
      ) async {
        await pumpPlayer(tester, videoItem, size: Size(width, 1000));

        expect(video(tester).right, lessThanOrEqualTo(title(tester).left));
        expect(title(tester).top, lessThan(video(tester).bottom));
        // Three parts of the window in five, from its left edge.
        expect(video(tester).left, 0);
        expect(video(tester).width, closeTo(width * 3 / 5, .01));
        expect(
          tester.getCenter(find.text('Location')).dx,
          greaterThan(video(tester).right),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the details of the split scroll on their own', (tester) async {
      await pumpPlayer(tester, videoItem, size: const Size(900, 340));
      final videoTop = video(tester).top;
      final titleTop = title(tester).top;

      await tester.drag(
        find.ancestor(
          of: find.text('Location'),
          matching: find.byType(SingleChildScrollView),
        ),
        const Offset(0, -150),
      );
      await tester.pump();

      expect(title(tester).top, lessThan(titleTop));
      expect(video(tester).top, videoTop);
      expect(tester.takeException(), isNull);
    });

    for (final width in [600.0, 700.0, 839.0]) {
      testWidgets('${width.round()} dp stacks it in a 560 wide centre', (
        tester,
      ) async {
        await pumpPlayer(tester, videoItem, size: Size(width, 1000));

        expect(video(tester).width, 560);
        expect(video(tester).center.dx, closeTo(width / 2, .01));
        expect(title(tester).top, greaterThanOrEqualTo(video(tester).bottom));
      });
    }

    testWidgets('599 dp is still across the whole width', (tester) async {
      await pumpPlayer(tester, videoItem, size: const Size(599, 1000));

      expect(video(tester).width, 599);
    });

    testWidgets('the sizes and the quality read left to right', (tester) async {
      await pumpPlayer(tester, videoItem, textDirection: TextDirection.rtl);

      for (final value in ['1080p · MP4', formatBytes(5452595)]) {
        expect(
          tester.widget<Text>(find.text(value)).textDirection,
          TextDirection.ltr,
          reason: value,
        );
      }
    });

    testWidgets('the source line reads left to right', (tester) async {
      stubSavedTask();
      await pumpPlayer(tester, videoItem, textDirection: TextDirection.rtl);

      final line = find.text('youtube.com · Open Road Films');
      expect(Directionality.of(tester.element(line)), TextDirection.rtl);
      expect(directionOf(tester, line), TextDirection.ltr);
    });
  });

  group('errors', () {
    testWidgets('an error event tells the user once', (tester) async {
      await pumpPlayer(tester, videoItem);

      await emit(tester, errors, 'decoder hiccup');
      expect(find.text("Couldn't play this file properly."), findsOneWidget);

      await emit(tester, errors, 'another one');
      expect(find.text("Couldn't play this file properly."), findsOneWidget);

      await pumpSnackbarIn(tester);
      await pumpUndoExpired(tester);
      expect(find.byType(SnackBar), findsNothing);
      await emit(tester, errors, 'and a third');
      expect(find.text("Couldn't play this file properly."), findsNothing);
    });

    testWidgets('a file that fails to open tells the user', (tester) async {
      when(() => player.open(any())).thenAnswer((_) async => throw 'bad file');
      await pumpPlayer(tester, videoItem);

      expect(find.text("Couldn't play this file properly."), findsOneWidget);
    });
  });

  group('share', () {
    testWidgets('sends the file to the share sheet', (tester) async {
      when(
        () => libraryRepository.share(videoItem),
      ).thenAnswer((_) async => const Ok(null));
      await pumpPlayer(tester, videoItem);

      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();

      verify(() => libraryRepository.share(videoItem)).called(1);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a failure shows its message', (tester) async {
      when(() => libraryRepository.share(videoItem)).thenAnswer(
        (_) async => const Err(UnexpectedFailure('No app to share with')),
      );
      await pumpPlayer(tester, videoItem);

      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();

      expect(find.text('No app to share with'), findsOneWidget);
    });
  });

  group('delete', () {
    Future<void> tapDelete(WidgetTester tester) async {
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
    }

    Future<void> confirm(WidgetTester tester) async {
      await tapDelete(tester);
      await tester.tap(
        find.descendant(of: find.byType(Dialog), matching: find.text('Delete')),
      );
      await pumpSnackbarIn(tester);
    }

    testWidgets('asks first, with the same dialog as the Library', (
      tester,
    ) async {
      await pumpPlayer(tester, videoItem);

      await tapDelete(tester);

      expect(find.text('Delete this file?'), findsOneWidget);
      expect(
        find.text(
          '“Desert drive at golden hour.mp4” will be removed from your '
          'phone and from Gallery.',
        ),
        findsOneWidget,
      );
      expect(find.text('1080p · MP4'), findsWidgets);
    });

    testWidgets('Cancel stays on the player and deletes nothing', (
      tester,
    ) async {
      await pumpPlayer(tester, videoItem);

      await tapDelete(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 6));

      expect(find.byType(PlayerView), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      verifyNever(() => libraryRepository.delete(any()));
    });

    testWidgets('Delete leaves the player and offers Undo', (tester) async {
      await pumpPlayer(tester, videoItem);

      await confirm(tester);

      expect(find.byType(PlayerView), findsNothing);
      expect(find.text('library'), findsOneWidget);
      expect(find.text('Deleted'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      verifyNever(() => libraryRepository.delete(any()));
    });

    testWidgets('the file goes once the five seconds run out', (tester) async {
      when(
        () => libraryRepository.delete(videoItem.uri),
      ).thenAnswer((_) async => const Ok(true));
      await pumpPlayer(tester, videoItem);

      await confirm(tester);
      await pumpUndoExpired(tester);

      verify(() => libraryRepository.delete(videoItem.uri)).called(1);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('Undo deletes nothing', (tester) async {
      await pumpPlayer(tester, videoItem);

      await confirm(tester);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 6));

      verifyNever(() => libraryRepository.delete(any()));
    });

    testWidgets('a failure shows its message after leaving', (tester) async {
      when(
        () => libraryRepository.delete(videoItem.uri),
      ).thenAnswer((_) async => const Err(StorageFailure()));
      await pumpPlayer(tester, videoItem);

      await confirm(tester);
      await pumpUndoExpired(tester);

      expect(find.text(const StorageFailure().message), findsOneWidget);
    });

    testWidgets('with nothing to go back to, it lands on the Library', (
      tester,
    ) async {
      await pumpPlayer(tester, videoItem);
      router.go(playerPath(videoItem));
      await tester.pumpAndSettle();
      expect(router.canPop(), isFalse);

      await confirm(tester);

      expect(find.byType(PlayerView), findsNothing);
    });
  });

  group('dispose', () {
    testWidgets('cancels the error subscription before the player', (
      tester,
    ) async {
      await pumpPlayer(tester, videoItem);

      router.pop();
      await tester.pumpAndSettle();

      expect(events, ['cancel errors', 'dispose player']);
    });
  });
}
