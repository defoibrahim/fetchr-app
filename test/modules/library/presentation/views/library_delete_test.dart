import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/core/utils/formatters.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../support/snackbar.dart';

import 'library_view_harness.dart';

void main() {
  setUp(setUpLibraryHarness);

  group('delete', () {
    Future<void> tapDelete(WidgetTester tester, [int index = 0]) async {
      await openMenu(tester, index);
      await tester.tap(find.text('Delete file'));
      await tester.pumpAndSettle();
    }

    // Confirms and lets the dialog finish closing, leaving the Undo snackbar
    // up with its five seconds still running.
    Future<void> confirmDelete(WidgetTester tester) async {
      await tapDelete(tester);
      await tester.tap(
        find.descendant(of: find.byType(Dialog), matching: find.text('Delete')),
      );
      await pumpSnackbarIn(tester);
    }

    testWidgets('asks first, with the file and a strip of what it is', (
      tester,
    ) async {
      stubList(() async => Ok(bothItems));
      await pumpLibrary(tester);

      await tapDelete(tester);

      expect(find.text('Delete this file?'), findsOneWidget);
      expect(
        find.text(
          '“Clip one & two.mp4” will be removed from your phone and from '
          'Gallery.',
        ),
        findsOneWidget,
      );
      expect(find.text('1080p · MP4'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text(formatBytes(1572864)),
        ),
        findsOneWidget,
      );
    });

    testWidgets('an audio file says MP3 once in the strip', (tester) async {
      stubList(() async => Ok(bothItems));
      await pumpLibrary(tester);

      await tapDelete(tester, 1);

      expect(
        find.descendant(of: find.byType(Dialog), matching: find.text('MP3')),
        findsOneWidget,
      );
    });

    testWidgets('Cancel keeps the file', (tester) async {
      stubList(() async => Ok(bothItems));
      await pumpLibrary(tester);

      await tapDelete(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 6));

      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(shown(tester), bothItems);
      verifyNever(() => repository.delete(any()));
    });

    testWidgets('Delete hides the card at once and offers Undo', (
      tester,
    ) async {
      stubList(() async => Ok(bothItems));
      await pumpLibrary(tester);

      await confirmDelete(tester);

      expect(shown(tester), [songItem]);
      expect(find.text('Deleted'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      verifyNever(() => repository.delete(any()));
    });

    testWidgets('the file goes once the five seconds run out', (tester) async {
      stubList(() async => Ok(bothItems));
      when(
        () => repository.delete(clipItem.uri),
      ).thenAnswer((_) async => const Ok(true));
      await pumpLibrary(tester);

      await confirmDelete(tester);
      await tester.pump(const Duration(seconds: 3));
      verifyNever(() => repository.delete(any()));

      await pumpUndoExpired(tester);

      verify(() => repository.delete(clipItem.uri)).called(1);
      expect(shown(tester), [songItem]);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('Undo brings the card back and deletes nothing', (
      tester,
    ) async {
      stubList(() async => Ok(bothItems));
      await pumpLibrary(tester);

      await confirmDelete(tester);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 6));

      expect(shown(tester), bothItems);
      expect(find.byType(SnackBar), findsNothing);
      verifyNever(() => repository.delete(any()));
    });

    testWidgets('a hidden card stays hidden through a pull to refresh', (
      tester,
    ) async {
      stubList(() async => Ok(bothItems));
      await pumpLibrary(tester);

      await confirmDelete(tester);
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 300),
        1000,
      );
      await tester.pumpAndSettle();

      verify(() => repository.list('Fetchr')).called(2);
      expect(shown(tester), [songItem]);
    });

    testWidgets('declining the system dialog brings the card back', (
      tester,
    ) async {
      stubList(() async => Ok(bothItems));
      when(
        () => repository.delete(clipItem.uri),
      ).thenAnswer((_) async => const Ok(false));
      await pumpLibrary(tester);

      await confirmDelete(tester);
      await pumpUndoExpired(tester);

      verify(() => repository.delete(clipItem.uri)).called(1);
      expect(shown(tester), bothItems);
    });

    testWidgets('a failure brings the card back and shows its message', (
      tester,
    ) async {
      stubList(() async => Ok(bothItems));
      when(
        () => repository.delete(clipItem.uri),
      ).thenAnswer((_) async => const Err(StorageFailure()));
      await pumpLibrary(tester);

      await confirmDelete(tester);
      await pumpUndoExpired(tester);

      expect(find.text(const StorageFailure().message), findsOneWidget);
      expect(shown(tester), bothItems);
    });

    testWidgets('deleting the last card leaves the empty state', (
      tester,
    ) async {
      stubList(() async => Ok([songItem]));
      await pumpLibrary(tester);

      await confirmDelete(tester);

      expect(find.text('No files yet'), findsOneWidget);
      expect(find.text('Fetchr · 0 files'), findsOneWidget);
    });
  });
}
