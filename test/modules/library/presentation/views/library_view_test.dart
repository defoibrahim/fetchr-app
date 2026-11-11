import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/shared/download_prefs_provider.dart';
import 'package:grabby/core/errors/error_messages.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/core/utils/formatters.dart';
import 'package:grabby/core/widgets/empty_view.dart';
import 'package:grabby/core/widgets/error_view.dart';
import 'package:grabby/core/widgets/loading_view.dart';
import 'package:grabby/modules/library/domain/entities/library_item.dart';
import 'package:grabby/modules/library/presentation/views/library_view.dart';
import 'package:grabby/modules/library/presentation/views/widgets/library_card.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../support/fixtures.dart';
import 'library_view_harness.dart';

void main() {
  setUp(setUpLibraryHarness);

  group('states', () {
    testWidgets('loading shows the title and a spinner, no count', (
      tester,
    ) async {
      stubList(() => Completer<Result<List<LibraryItem>>>().future);
      await pumpLibrary(tester);

      expect(find.text('Library'), findsOneWidget);
      expect(find.byType(LoadingView), findsOneWidget);
      expect(find.byType(LibraryCard), findsNothing);
      expect(find.textContaining(' file'), findsNothing);
    });

    testWidgets('loaded shows the header count and a card per item', (
      tester,
    ) async {
      stubList(() async => Ok(bothItems));
      await pumpLibrary(tester);

      expect(find.text('Library'), findsOneWidget);
      expect(find.text('Fetchr · 2 files'), findsOneWidget);
      expect(shown(tester), bothItems);
      expect(find.text('Clip one & two.mp4'), findsOneWidget);
      expect(find.text('1080p · ${formatBytes(1572864)}'), findsOneWidget);
      expect(find.text('Song.mp3'), findsOneWidget);
      expect(find.text('MP3 · 6.2 MB'), findsOneWidget);
    });

    testWidgets('one file reads "1 file"', (tester) async {
      stubList(() async => Ok([songItem]));
      await pumpLibrary(tester);

      expect(find.text('Fetchr · 1 file'), findsOneWidget);
    });

    testWidgets('the header and the list follow the save folder', (
      tester,
    ) async {
      stubList(() async => Ok(bothItems));
      await pumpLibrary(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(LibraryView)),
      );

      await container.read(downloadPrefsProvider.notifier).setFolder('Clips');
      await tester.pump();
      await tester.pump();

      verify(() => repository.list('Clips')).called(1);
      expect(find.text('Clips · 2 files'), findsOneWidget);
    });

    testWidgets('the cards are laid out in two columns', (tester) async {
      stubList(() async => Ok(bothItems));
      await pumpLibrary(tester);

      final first = tester.getTopLeft(find.byType(LibraryCard).first);
      final second = tester.getTopLeft(find.byType(LibraryCard).last);
      expect(first.dy, second.dy);
      // 375 wide, 20 gutters and a 12 gap: two columns of 161.5.
      expect(second.dx - first.dx, 173.5);
      expect(tester.getSize(find.byType(LibraryCard).first).width, 161.5);
    });

    testWidgets('failed shows the failure message and Retry loads again', (
      tester,
    ) async {
      stubList(() async => const Err(StorageFailure()));
      await pumpLibrary(tester);

      expect(find.byType(ErrorView), findsOneWidget);
      expect(find.text(const StorageFailure().message), findsOneWidget);

      final retry = Completer<Result<List<LibraryItem>>>();
      stubList(() => retry.future);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();

      expect(find.byType(LoadingView), findsOneWidget);
      expect(find.byType(ErrorView), findsNothing);

      retry.complete(Ok(bothItems));
      await tester.pump();
      await tester.pump();

      expect(shown(tester), bothItems);
      verify(() => repository.list('Fetchr')).called(2);
    });

    testWidgets('an error that is not a Failure shows the generic message', (
      tester,
    ) async {
      stubList(() async => throw StateError('boom'));
      await pumpLibrary(tester);

      expect(find.text(ErrorMessages.unexpected), findsOneWidget);
    });

    testWidgets('a failed refresh replaces the list with the failure', (
      tester,
    ) async {
      stubList(() async => Ok(bothItems));
      await pumpLibrary(tester);

      stubList(() async => const Err(NetworkFailure()));
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 300),
        1000,
      );
      await tester.pumpAndSettle();

      expect(find.byType(ErrorView), findsOneWidget);
      expect(find.byType(LibraryCard), findsNothing);
    });
  });

  group('the columns', () {
    final many = [
      for (var i = 0; i < 8; i++)
        libraryItem(
          uri: 'content://media/external/video/media/$i',
          name: 'Clip $i.mp4',
          durationMs: 65000,
          width: 1920,
          height: 1080,
        ),
    ];

    // The window's width picks the count; the cards follow it, on the grid's
    // whole width.
    for (final (width, columns) in [
      (360.0, 2),
      (599.0, 2),
      (600.0, 3),
      (700.0, 3),
      (839.0, 3),
      (840.0, 4),
      (900.0, 4),
    ]) {
      testWidgets('${width.round()} dp has $columns', (tester) async {
        stubList(() async => Ok(many));
        await pumpLibrary(tester, size: Size(width, 1000));

        final cards = find.byType(LibraryCard);
        final lefts = {
          for (var i = 0; i < cards.evaluate().length; i++)
            tester.getTopLeft(cards.at(i)).dx.round(),
        };
        expect(lefts, hasLength(columns));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the grid is not capped at 560 dp', (tester) async {
      stubList(() async => Ok(many));
      await pumpLibrary(tester, size: const Size(900, 1000));

      final cards = find.byType(LibraryCard);
      final rects = [
        for (var i = 0; i < cards.evaluate().length; i++)
          tester.getRect(cards.at(i)),
      ];
      // The gutters are 20 dp, unscaled from 600 dp.
      final left = rects.map((r) => r.left).reduce((a, b) => a < b ? a : b);
      final right = rects.map((r) => r.right).reduce((a, b) => a > b ? a : b);
      expect(left, closeTo(20, .01));
      expect(right, closeTo(880, .01));
    });
  });

  group('right to left', () {
    testWidgets('the folder and count read left to right', (tester) async {
      stubList(() async => Ok(bothItems));
      await pumpLibrary(tester, textDirection: TextDirection.rtl);

      expect(
        tester.widget<Text>(find.text('Fetchr · 2 files')).textDirection,
        TextDirection.ltr,
      );
    });
  });

  group('filters', () {
    testWidgets('All is selected at first and the chips are in order', (
      tester,
    ) async {
      stubList(() async => Ok(bothItems));
      await pumpLibrary(tester);

      final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip));
      expect([for (final chip in chips) chip.selected], [true, false, false]);
      expect(
        [for (final chip in chips) (chip.label as Text).data],
        ['All', 'Video', 'Audio'],
      );
    });

    testWidgets('Video and Audio narrow the grid, All brings both back', (
      tester,
    ) async {
      stubList(() async => Ok(bothItems));
      await pumpLibrary(tester);

      await pickFilter(tester, 'Video');
      expect(shown(tester), [clipItem]);

      await pickFilter(tester, 'Audio');
      expect(shown(tester), [songItem]);

      await pickFilter(tester, 'All');
      expect(shown(tester), bothItems);
    });

    testWidgets('the header still counts every file', (tester) async {
      stubList(() async => Ok(bothItems));
      await pumpLibrary(tester);

      await pickFilter(tester, 'Audio');

      expect(find.text('Fetchr · 2 files'), findsOneWidget);
    });

    testWidgets('an empty filter says so, and still pulls to refresh', (
      tester,
    ) async {
      stubList(() async => Ok([clipItem]));
      await pumpLibrary(tester);

      await pickFilter(tester, 'Audio');
      expect(find.text('No audio files'), findsOneWidget);
      expect(find.byType(LibraryCard), findsNothing);

      final reload = Completer<Result<List<LibraryItem>>>();
      stubList(() => reload.future);
      await tester.fling(
        find.text('No audio files'),
        const Offset(0, 300),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      verify(() => repository.list('Fetchr')).called(2);

      reload.complete(Ok(bothItems));
      await tester.pumpAndSettle();
      expect(shown(tester), [songItem]);

      await pickFilter(tester, 'Video');
      expect(shown(tester), [clipItem]);
    });

    testWidgets('Video with only audio files reads "No video files"', (
      tester,
    ) async {
      stubList(() async => Ok([songItem]));
      await pumpLibrary(tester);

      await pickFilter(tester, 'Video');

      expect(find.text('No video files'), findsOneWidget);
    });

    testWidgets('changing the filter closes an open menu', (tester) async {
      stubList(() async => Ok(bothItems));
      await pumpLibrary(tester);
      await openMenu(tester);
      expect(find.text('Delete file'), findsOneWidget);

      await pickFilter(tester, 'Audio');

      expect(find.text('Delete file'), findsNothing);
      expect(shown(tester), [songItem]);
    });
  });

  group('empty', () {
    testWidgets('says where files are saved and offers Paste a link', (
      tester,
    ) async {
      stubList(() async => const Ok(<LibraryItem>[]));
      await pumpLibrary(tester);

      expect(find.byType(EmptyView), findsOneWidget);
      expect(find.text('Fetchr · 0 files'), findsOneWidget);
      expect(find.text('No files yet'), findsOneWidget);
      expect(
        find.text(
          'Finished videos and audio are saved to Movies/Fetchr and '
          'Music/Fetchr and show up here and in Gallery.',
        ),
        findsOneWidget,
      );
      expect(find.byType(LibraryCard), findsNothing);
    });

    testWidgets('the paths follow the save folder', (tester) async {
      stubList(() async => const Ok(<LibraryItem>[]));
      await pumpLibrary(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(LibraryView)),
      );

      await container.read(downloadPrefsProvider.notifier).setFolder('Clips');
      await tester.pump();
      await tester.pump();

      expect(
        find.textContaining('Movies/Clips and Music/Clips'),
        findsOneWidget,
      );
    });

    testWidgets('Paste a link goes Home', (tester) async {
      stubList(() async => const Ok(<LibraryItem>[]));
      await pumpLibrary(tester);

      await tester.tap(find.text('Paste a link'));
      await tester.pumpAndSettle();

      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('pulling down reloads, and the new files appear', (
      tester,
    ) async {
      stubList(() async => const Ok(<LibraryItem>[]));
      await pumpLibrary(tester);

      stubList(() async => Ok(bothItems));
      await tester.fling(find.byType(EmptyView), const Offset(0, 300), 1000);
      await tester.pumpAndSettle();

      verify(() => repository.list('Fetchr')).called(2);
      expect(shown(tester), bothItems);
      expect(find.byType(EmptyView), findsNothing);
    });
  });

  group('the tab', () {
    testWidgets('pulling the list down reloads and keeps the list visible', (
      tester,
    ) async {
      stubList(() async => Ok(bothItems));
      await pumpLibrary(tester);

      final reload = Completer<Result<List<LibraryItem>>>();
      stubList(() => reload.future);
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 300),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      verify(() => repository.list('Fetchr')).called(2);
      expect(shown(tester), bothItems);
      expect(find.byType(LoadingView), findsNothing);

      reload.complete(Ok([songItem]));
      await tester.pumpAndSettle();

      expect(shown(tester), [songItem]);
    });

    testWidgets('showing the tab again reloads once and keeps the list', (
      tester,
    ) async {
      stubList(() async => Ok(bothItems));
      final ticking = ValueNotifier(true);
      addTearDown(ticking.dispose);
      await pumpLibrary(tester, ticking: ticking);
      verify(() => repository.list('Fetchr')).called(1);

      ticking.value = false;
      await tester.pump();
      await tester.pump();
      verifyNever(() => repository.list(any()));

      final reload = Completer<Result<List<LibraryItem>>>();
      stubList(() => reload.future);
      ticking.value = true;
      await tester.pump();
      await tester.pump();

      verify(() => repository.list('Fetchr')).called(1);
      expect(shown(tester), bothItems);
      expect(find.byType(LoadingView), findsNothing);

      reload.complete(Ok([songItem]));
      await tester.pump();
      await tester.pump();

      expect(shown(tester), [songItem]);
      verifyNever(() => repository.list(any()));
    });

    testWidgets('the first build and unrelated rebuilds do not reload', (
      tester,
    ) async {
      stubList(() async => Ok(bothItems));
      final ticking = ValueNotifier(true);
      addTearDown(ticking.dispose);
      await pumpLibrary(tester, ticking: ticking);
      verify(() => repository.list('Fetchr')).called(1);

      ticking.value = true;
      await tester.pump();
      await tester.pump();

      verifyNever(() => repository.list(any()));
    });
  });
}
