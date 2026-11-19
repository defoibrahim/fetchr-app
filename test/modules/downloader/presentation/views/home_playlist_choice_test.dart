import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/modules/downloader/presentation/views/playlist_view.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../support/fake_app.dart';
import 'home_view_support.dart';

const _inPlaylist = '$clipUrl&list=PL1';

void main() {
  late FakeApp app;

  setUp(() => app = homeApp());

  Future<void> askFor(WidgetTester tester) async {
    await pumpHome(tester, app: app);
    await typeUrl(tester, _inPlaylist);
    await tester.tap(find.text('Get formats'));
    await tester.pumpAndSettle();
  }

  testWidgets('a video in a playlist asks first, and This video drops the '
      'playlist from the link', (tester) async {
    stubFetch(app, Ok(clipInfo));
    await askFor(tester);

    expect(find.text('This video is in a playlist'), findsOneWidget);
    verifyNever(() => app.downloader.fetchInfo(any()));

    await tester.tap(find.text('This video'));
    await tester.pumpAndSettle();

    verify(() => app.downloader.fetchInfo(clipUrl)).called(1);
    expect(fieldText(tester), clipUrl);
    expect(formatSheet, findsOneWidget);
  });

  testWidgets('Playlist fetches the link as pasted', (tester) async {
    stubFetch(app, Ok(playlistInfo), url: _inPlaylist);
    await askFor(tester);

    await tester.tap(find.text('Playlist'));
    await tester.pumpAndSettle();

    verify(() => app.downloader.fetchInfo(_inPlaylist)).called(1);
    expect(find.byType(PlaylistView), findsOneWidget);
  });

  testWidgets('dismissing the question fetches nothing', (tester) async {
    await askFor(tester);

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(find.text('This video is in a playlist'), findsNothing);
    verifyNever(() => app.downloader.fetchInfo(any()));
    expect(fieldText(tester), _inPlaylist);
  });
}
