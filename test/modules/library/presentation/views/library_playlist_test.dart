import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/modules/library/domain/entities/library_item.dart';
import 'package:grabby/modules/library/domain/extensions/library_item_extensions.dart';
import 'package:grabby/modules/library/presentation/views/library_playlist_view.dart';
import 'package:grabby/modules/library/presentation/views/widgets/library_card.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../support/fixtures.dart';
import 'library_view_harness.dart';

LibraryItem _video(int number, String title) => libraryItem(
  uri: 'content://media/external/video/media/9$number',
  name: '0$number - $title.mp4',
  sizeBytes: 1048576,
  relativePath: 'Movies/Fetchr/Road trip/',
  dateAdded: DateTime(2026, 2, number),
);

// Newest first, as native lists them: the playlist's files arrive backwards.
final _items = [_video(3, 'Fog'), _video(1, 'Dawn'), clipItem];

void main() {
  setUp(() {
    setUpLibraryHarness();
    stubList(() async => Ok(_items));
  });

  test('a file knows its playlist, number and plain name', () {
    final item = _video(3, 'Fog');

    expect(item.playlist, 'Road trip');
    expect(item.playlistNumber, '03');
    expect(item.nameInPlaylist, 'Fog.mp4');
    expect(clipItem.playlist, isNull);
    expect(clipItem.playlistNumber, isNull);
    expect(clipItem.nameInPlaylist, clipItem.name);
    expect(_items.inPlaylist('Road trip').map((i) => i.playlistNumber), [
      '01',
      '03',
    ]);
  });

  testWidgets('a playlist is one tile next to the single files', (
    tester,
  ) async {
    await pumpLibrary(tester);

    expect(find.byType(LibraryPlaylistCard), findsOneWidget);
    expect(find.text('Road trip'), findsOneWidget);
    expect(find.text('2 files · 2.0 MB'), findsOneWidget);
    expect(shown(tester), [clipItem]);
  });

  testWidgets('the tile opens the playlist in order, without the numbers in '
      'the titles', (tester) async {
    await pumpLibrary(tester);

    await tester.tap(find.bySemanticsLabel('Open playlist Road trip'));
    await tester.pumpAndSettle();

    expect(find.byType(LibraryPlaylistView), findsOneWidget);
    expect(find.text('Playlist · 2 files · 2.0 MB'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Dawn.mp4')).dy,
      lessThan(tester.getTopLeft(find.text('Fog.mp4')).dy),
    );
    expect(find.text('01'), findsOneWidget);
    expect(find.text('03'), findsOneWidget);
  });

  group('Delete playlist', () {
    Future<void> confirm(WidgetTester tester) async {
      await openMenu(tester);
      await tester.tap(find.text('Delete playlist'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this playlist?'), findsOneWidget);
      await tester.tap(
        find.descendant(of: find.byType(Dialog), matching: find.text('Delete')),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('deletes every file of it and nothing else', (tester) async {
      when(
        () => repository.delete(any()),
      ).thenAnswer((_) async => const Ok(true));
      await pumpLibrary(tester);

      await confirm(tester);

      verify(() => repository.delete(_video(1, '').uri)).called(1);
      verify(() => repository.delete(_video(3, '').uri)).called(1);
      verifyNever(() => repository.delete(clipItem.uri));
      expect(find.byType(LibraryPlaylistCard), findsNothing);
      expect(shown(tester), [clipItem]);
    });

    testWidgets('a file the user keeps stops it and stays listed', (
      tester,
    ) async {
      when(
        () => repository.delete(_video(1, '').uri),
      ).thenAnswer((_) async => const Ok(true));
      when(
        () => repository.delete(_video(3, '').uri),
      ).thenAnswer((_) async => const Ok(false));
      await pumpLibrary(tester);

      await confirm(tester);

      expect(find.text('1 file · 1.0 MB'), findsOneWidget);
    });

    testWidgets('Cancel deletes nothing', (tester) async {
      await pumpLibrary(tester);

      await openMenu(tester);
      await tester.tap(find.text('Delete playlist'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      verifyNever(() => repository.delete(any()));
      expect(find.byType(LibraryPlaylistCard), findsOneWidget);
    });
  });
}
