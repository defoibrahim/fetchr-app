import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/routes/app_routes.dart';
import 'package:grabby/app/shared/domain/entities/quality.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/modules/downloader/domain/entities/download_request.dart';
import 'package:grabby/modules/downloader/domain/entities/download_task.dart';
import 'package:grabby/modules/downloader/domain/entities/media_info.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/format_sheet.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/url_field.dart';
import 'package:mocktail/mocktail.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../../../support/fake_app.dart';
import '../../../../support/fixtures.dart';

const clipUrl = 'https://youtube.com/watch?v=Qx7mT0aK3pE';
const otherUrl = 'https://example.com/other';

final clipInfo = mediaInfo(
  url: clipUrl,
  title: 'A clip',
  uploader: 'Uploader',
  durationSec: 754,
  thumbnail: 'https://example.com/t.jpg',
  options: formatOptions([
    Quality.best,
    Quality.p720,
    Quality.mp3,
    Quality.cover,
  ]),
);

final playlistInfo = mediaInfo(
  url: clipUrl,
  title: 'A list',
  isPlaylist: true,
  options: formatOptions([Quality.best, Quality.mp3]),
  entries: const [
    PlaylistEntry(url: 'https://example.com/a', title: 'A'),
    PlaylistEntry(url: 'https://example.com/b', title: 'B'),
  ],
);

final urlField = find.byType(TextField);
final formatSheet = find.byType(FormatSheet);

String fieldText(WidgetTester tester) =>
    tester.widget<TextField>(urlField).controller!.text;

SharedMediaFile sharedText(String text) =>
    SharedMediaFile(path: text, type: SharedMediaType.text);

/// Where the app is, for `go` navigation; a pushed page leaves it unchanged.
String locationOf(FakeApp app) =>
    app.router.routerDelegate.currentConfiguration.uri.path;

/// The repositories answering what most Home tests need: an enqueue that
/// works and plenty of free space.
FakeApp homeApp() {
  final app = FakeApp();
  when(
    () => app.downloader.enqueue(any()),
  ).thenAnswer((_) async => const Ok<void>(null));
  when(
    () => app.downloader.freeSpaceBytes(),
  ).thenAnswer((_) async => const Ok(8 * gb));
  return app;
}

void stubFetch(FakeApp app, Result<MediaInfo> answer, {String url = clipUrl}) =>
    when(() => app.downloader.fetchInfo(url)).thenAnswer((_) async => answer);

void stubTasks(FakeApp app, List<DownloadTask> tasks) => when(
  () => app.downloader.watchTasks(),
).thenAnswer((_) => Stream.value(tasks));

/// A Home built after the clipboard and the share stream were mocked.
/// `pumpFakeApp` replaces both while it pumps, so the app comes up on
/// Downloads and Home is opened afterwards.
class HomeSession {
  HomeSession(this.app, this.clipboard);

  final FakeApp app;
  String? clipboard;
  final shares = StreamController<List<SharedMediaFile>>();
}

Future<HomeSession> pumpHome(
  WidgetTester tester, {
  required FakeApp app,
  String? clipboard,
  List<SharedMediaFile> initialShare = const [],
  ThemeData? theme,
  Size size = const Size(360, 800),
  TransitionBuilder? builder,
}) async {
  await pumpFakeApp(
    tester,
    app: app,
    initialLocation: AppRoutes.downloads,
    theme: theme,
    size: size,
    builder: builder,
  );
  final home = HomeSession(app, clipboard);
  // Not awaited: a subscriber paused by a hidden tab never takes the done
  // event, so waiting on close() would hang the teardown.
  addTearDown(() => unawaited(home.shares.close()));
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.getData' && home.clipboard != null) {
        return <String, dynamic>{'text': home.clipboard};
      }
      return null;
    },
  );
  ReceiveSharingIntent.setMockValues(
    initialMedia: initialShare,
    mediaStream: home.shares.stream,
  );
  app.router.go(AppRoutes.home);
  // The first frame runs the clipboard check; the next settles its async read.
  await tester.pump();
  await tester.pump();
  return home;
}

Future<void> resumeApp(WidgetTester tester) async {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pump();
  await tester.pump();
  // The card slides in or out.
  await tester.pump(const Duration(milliseconds: 250));
}

/// Taps Get formats and lets a fetch that answers at once finish.
Future<void> getFormats(WidgetTester tester) async {
  await tester.tap(find.text('Get formats'));
  await tester.pump();
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> typeUrl(WidgetTester tester, String text) async {
  await tester.enterText(urlField, text);
  await tester.pump();
}

/// The error card sits below the fold on a short screen.
Future<void> tapCard(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pump();
  await tester.tap(find.text(label));
}

/// The sheet's own pop, without going through its buttons.
void popSheet(WidgetTester tester, [Quality? quality]) =>
    Navigator.of(tester.element(formatSheet)).pop(quality);

Border fieldBorder(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find
        .descendant(
          of: find.byType(UrlField),
          matching: find.byType(DecoratedBox),
        )
        .first,
  );
  return (box.decoration as BoxDecoration).border! as Border;
}

AppTokens lightTokens() => AppTheme.light().extension<AppTokens>()!;

/// Types [clipUrl] and fetches, with the sheet open when the fetch succeeds.
Future<HomeSession> openSheet(
  WidgetTester tester,
  FakeApp app, {
  Result<MediaInfo>? answer,
  Size size = const Size(360, 800),
  TransitionBuilder? builder,
}) async {
  stubFetch(app, answer ?? Ok(clipInfo));
  final home = await pumpHome(tester, app: app, size: size, builder: builder);
  await typeUrl(tester, clipUrl);
  await getFormats(tester);
  return home;
}

/// The requests the last `enqueue` call carried.
List<DownloadRequest> enqueued(FakeApp app) =>
    verify(() => app.downloader.enqueue(captureAny())).captured.single
        as List<DownloadRequest>;
