import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/routes/app_routes.dart';
import 'package:grabby/core/errors/error_messages.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/core/widgets/media_thumb.dart';
import 'package:grabby/modules/library/presentation/views/widgets/library_card.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../support/fixtures.dart';

import 'library_view_harness.dart';

void main() {
  setUp(setUpLibraryHarness);

  group('thumbnails', () {
    testWidgets('a cached path is shown through FileImage', (tester) async {
      stubList(() async => Ok([clipItem]));
      when(
        () => repository.thumbnail(clipItem.uri, 480, 300),
      ).thenAnswer((_) async => const Ok('/cache/thumbs/1.jpg'));
      await pumpLibrary(tester);
      await tester.pump();

      final image = tester.widget<Image>(find.byType(Image)).image;
      expect(image, isA<ResizeImage>());
      final source = (image as ResizeImage).imageProvider;
      expect(source, isA<FileImage>());
      expect((source as FileImage).file.path, '/cache/thumbs/1.jpg');
    });

    testWidgets('no thumbnail keeps the stripes', (tester) async {
      stubList(() async => Ok([clipItem]));
      await pumpLibrary(tester);
      await tester.pump();

      expect(find.byType(Image), findsNothing);
      expect(find.byType(MediaThumb), findsOneWidget);
    });

    testWidgets('an audio file gets the audio tile, not a lookup', (
      tester,
    ) async {
      stubList(() async => Ok([songItem]));
      await pumpLibrary(tester);
      await tester.pump();

      expect(
        tester.widget<MediaThumb>(find.byType(MediaThumb)).isAudio,
        isTrue,
      );
      expect(find.byType(Image), findsNothing);
      verifyNever(() => repository.thumbnail(any(), any(), any()));
    });

    testWidgets('the badge shows the duration, and is hidden without one', (
      tester,
    ) async {
      stubList(
        () async =>
            Ok([clipItem, libraryItem(uri: 'content://x', name: 'No.mp4')]),
      );
      await pumpLibrary(tester);

      expect(find.text('1:05'), findsOneWidget);
      final badges = tester
          .widgetList<MediaThumb>(find.byType(MediaThumb))
          .map((thumb) => thumb.duration);
      expect(badges, ['1:05', null]);
    });
  });

  group('a card', () {
    testWidgets('tapping the picture pushes the player with uri and title', (
      tester,
    ) async {
      stubList(() async => Ok(bothItems));
      await pumpLibrary(tester);

      await tester.tap(
        find
            .descendant(
              of: find.byType(LibraryCard).first,
              matching: find.byType(InkWell),
            )
            .first,
      );
      await tester.pumpAndSettle();

      expect(find.text('player'), findsOneWidget);
      expect(pushed.single.path, AppRoutes.player);
      expect(pushed.single.queryParameters, {
        'uri': clipItem.uri,
        'title': clipItem.name,
      });
    });

    testWidgets('the picture is a button named "Play {title}"', (tester) async {
      final semantics = tester.ensureSemantics();
      stubList(() async => Ok(bothItems));
      await pumpLibrary(tester);

      expect(find.bySemanticsLabel('Play Clip one & two.mp4'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Play Song.mp3')),
        isSemantics(label: 'Play Song.mp3', isButton: true, hasTapAction: true),
      );
      semantics.dispose();
    });

    testWidgets('long-pressing it opens the same menu as the dots', (
      tester,
    ) async {
      stubList(() async => Ok(bothItems));
      await pumpLibrary(tester);

      await tester.longPress(find.byType(LibraryCard).first);
      await tester.pumpAndSettle();

      expect(find.byType(MenuItemButton), findsNWidgets(4));
      expect(find.byType(Dialog), findsNothing);
      expect(pushed, isEmpty);
    });

    testWidgets('the dots open Play, Share, Show in folder and Delete file', (
      tester,
    ) async {
      stubList(() async => Ok(bothItems));
      await pumpLibrary(tester);
      expect(find.byType(MenuItemButton), findsNothing);

      await openMenu(tester);

      expect(
        [
          for (final item in tester.widgetList<MenuItemButton>(
            find.byType(MenuItemButton),
          ))
            ((item.child! as Text).data),
        ],
        ['Play', 'Share', 'Show in folder', 'Delete file'],
      );
    });

    testWidgets('the quality and size read left to right', (tester) async {
      stubList(() async => Ok(bothItems));
      await pumpLibrary(tester, textDirection: TextDirection.rtl);

      expect(
        tester.widget<Text>(find.text('MP3 · 6.2 MB')).textDirection,
        TextDirection.ltr,
      );
    });

    testWidgets('the dots are a 44 dp target inside the card', (tester) async {
      stubList(() async => Ok(bothItems));
      await pumpLibrary(tester);

      final dots = tester.getRect(find.byTooltip('More actions').first);
      final card = tester.getRect(find.byType(LibraryCard).first);
      expect(dots.size, const Size(44, 44));
      expect(card.contains(dots.topLeft), isTrue);
      expect(card.contains(dots.bottomRight - const Offset(1, 1)), isTrue);
    });

    testWidgets('Play in the menu opens the player', (tester) async {
      stubList(() async => Ok(bothItems));
      await pumpLibrary(tester);

      await openMenu(tester, 1);
      await tester.tap(find.text('Play'));
      await tester.pumpAndSettle();

      expect(pushed.single.queryParameters['uri'], songItem.uri);
    });

    testWidgets('Share sends that item to the repository', (tester) async {
      stubList(() async => Ok(bothItems));
      when(
        () => repository.share(songItem),
      ).thenAnswer((_) async => const Ok(null));
      await pumpLibrary(tester);

      await openMenu(tester, 1);
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();

      verify(() => repository.share(songItem)).called(1);
      verifyNever(() => repository.share(clipItem));
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a failed Share shows its message', (tester) async {
      stubList(() async => Ok(bothItems));
      when(() => repository.share(clipItem)).thenAnswer(
        (_) async => const Err(UnexpectedFailure('No app to share with')),
      );
      await pumpLibrary(tester);

      await openMenu(tester);
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();

      expect(find.text('No app to share with'), findsOneWidget);
      expect(shown(tester), bothItems);
    });

    testWidgets('Show in folder opens that item folder', (tester) async {
      stubList(() async => Ok(bothItems));
      when(
        () => repository.openFolder(songItem.uri),
      ).thenAnswer((_) async => const Ok<void>(null));
      await pumpLibrary(tester);

      await openMenu(tester, 1);
      await tester.tap(find.text('Show in folder'));
      await tester.pumpAndSettle();

      verify(() => repository.openFolder(songItem.uri)).called(1);
      verifyNever(() => repository.openFolder(clipItem.uri));
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a failed Show in folder shows its message', (tester) async {
      stubList(() async => Ok(bothItems));
      when(() => repository.openFolder(clipItem.uri)).thenAnswer(
        (_) async => const Err(UnexpectedFailure(ErrorMessages.noFolderApp)),
      );
      await pumpLibrary(tester);

      await openMenu(tester);
      await tester.tap(find.text('Show in folder'));
      await tester.pumpAndSettle();

      expect(find.text(ErrorMessages.noFolderApp), findsOneWidget);
    });

    testWidgets('long titles stay in two lines at the largest text', (
      tester,
    ) async {
      stubList(
        () async => Ok([
          libraryItem(
            uri: 'content://x/1',
            name:
                'A very long title that keeps going well past the second line '
                'of a narrow card so it has to be cut short.mp4',
            sizeBytes: 192937984,
            width: 1920,
            height: 1080,
          ),
          songItem,
        ]),
      );
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpLibrary(tester, size: const Size(320, 640));

      expect(tester.takeException(), isNull);
      expect(find.byType(LibraryCard), findsNWidgets(2));
    });
  });
}
