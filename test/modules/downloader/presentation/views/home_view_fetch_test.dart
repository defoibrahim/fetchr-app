import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/routes/app_routes.dart';
import 'package:grabby/app/shared/domain/entities/quality.dart';
import 'package:grabby/app/shared/domain/entities/yt_dlp_status.dart';
import 'package:grabby/core/errors/error_messages.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/core/utils/formatters.dart';
import 'package:grabby/modules/downloader/domain/entities/download_request.dart';
import 'package:grabby/modules/downloader/domain/entities/format_option.dart';
import 'package:grabby/modules/downloader/domain/entities/media_info.dart';
import 'package:grabby/modules/downloader/presentation/views/playlist_view.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/format_sheet.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../core/widgets/widget_harness.dart';
import '../../../../support/fake_app.dart';
import '../../../../support/fixtures.dart';
import 'home_view_support.dart';

void main() {
  late FakeApp app;

  setUpAll(() => registerFallbackValue(<DownloadRequest>[]));

  setUp(() => app = homeApp());

  group('fetching', () {
    testWidgets('shows Fetching… behind the open sheet', (tester) async {
      final pending = Completer<Result<MediaInfo>>();
      when(
        () => app.downloader.fetchInfo(clipUrl),
      ).thenAnswer((_) => pending.future);
      await pumpHome(tester, app: app);
      await typeUrl(tester, 'watch $clipUrl now');

      await tester.tap(find.text('Get formats'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Fetching…'), findsOneWidget);
      expect(formatSheet, findsOneWidget);
      verify(() => app.downloader.fetchInfo(clipUrl)).called(1);

      pending.complete(Ok(clipInfo));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Get formats'), findsOneWidget);
    });

    testWidgets('a single video loads into the sheet', (tester) async {
      await openSheet(tester, app);

      expect(formatSheet, findsOneWidget);
      expect(find.text('A clip'), findsOneWidget);
    });

    final failures = <(String, Failure, String, List<String>)>[
      (
        'unsupported site',
        const UnsupportedSiteFailure(),
        "This site isn't supported",
        ['Update yt-dlp', 'Edit link'],
      ),
      (
        'private video',
        const PrivateVideoFailure(),
        'This video is private',
        ['Try another link'],
      ),
      ('network', const NetworkFailure(), 'No internet connection', ['Retry']),
      (
        'unavailable',
        const MediaUnavailableFailure(),
        "This video isn't available",
        ['Try another link'],
      ),
      ('busy', const YtDlpBusyFailure(), 'yt-dlp is updating', ['Retry']),
      (
        'unknown',
        const UnexpectedFailure(),
        "Couldn't get this video",
        ['Update yt-dlp', 'Edit link'],
      ),
    ];
    for (final (name, failure, title, actions) in failures) {
      testWidgets('$name closes the sheet and shows its card', (tester) async {
        await openSheet(tester, app, answer: Err(failure));

        expect(formatSheet, findsNothing);
        expect(find.text(title), findsOneWidget);
        for (final label in actions) {
          expect(find.text(label), findsOneWidget);
        }
        expect(
          fieldBorder(tester),
          Border.all(color: lightTokens().error, width: 1.5),
        );
        expect(fieldText(tester), clipUrl);
      });
    }

    testWidgets('typing clears the card and the error border', (tester) async {
      await openSheet(tester, app, answer: const Err(PrivateVideoFailure()));
      expect(find.text('This video is private'), findsOneWidget);

      await typeUrl(tester, '${clipUrl}x');
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('This video is private'), findsNothing);
      // The field has focus now: its border is the primary colour, not the
      // error one.
      expect(fieldBorder(tester).top.color, isNot(lightTokens().error));
      expect(fieldBorder(tester).top.width, 1);
    });

    testWidgets('Retry fetches again', (tester) async {
      await openSheet(tester, app, answer: const Err(NetworkFailure()));
      stubFetch(app, Ok(clipInfo));

      await tapCard(tester, 'Retry');
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      verify(() => app.downloader.fetchInfo(clipUrl)).called(2);
      expect(formatSheet, findsOneWidget);
      expect(find.text('No internet connection'), findsNothing);
    });

    testWidgets('Edit link focuses the field and selects the link', (
      tester,
    ) async {
      await openSheet(tester, app, answer: const Err(UnsupportedSiteFailure()));

      await tapCard(tester, 'Edit link');
      await tester.pump();

      final field = tester.widget<TextField>(urlField);
      expect(field.focusNode!.hasFocus, isTrue);
      expect(
        field.controller!.selection,
        const TextSelection(baseOffset: 0, extentOffset: clipUrl.length),
      );
      // Selecting is not editing: the card stays.
      expect(find.text("This site isn't supported"), findsOneWidget);
    });

    testWidgets('Try another link clears the field and focuses it', (
      tester,
    ) async {
      await openSheet(tester, app, answer: const Err(PrivateVideoFailure()));

      await tapCard(tester, 'Try another link');
      await tester.pump(const Duration(milliseconds: 250));

      final field = tester.widget<TextField>(urlField);
      expect(field.controller!.text, isEmpty);
      expect(field.focusNode!.hasFocus, isTrue);
      expect(find.text('This video is private'), findsNothing);
    });
  });

  group('updating yt-dlp from the card', () {
    Future<Completer<Result<YtDlpStatus>>> unsupportedWithPendingUpdate(
      WidgetTester tester,
    ) async {
      final update = Completer<Result<YtDlpStatus>>();
      when(() => app.ytDlp.update()).thenAnswer((_) => update.future);
      await openSheet(tester, app, answer: const Err(UnsupportedSiteFailure()));
      return update;
    }

    testWidgets(
      'is busy and ignores taps, then refetches and reads Check again',
      (tester) async {
        final update = await unsupportedWithPendingUpdate(tester);

        await tapCard(tester, 'Update yt-dlp');
        await tester.pump();

        expect(find.text('Updating…'), findsOneWidget);
        await tapCard(tester, 'Updating…');
        await tester.pump();
        verify(() => app.ytDlp.update()).called(1);

        update.complete(Ok(ytDlpStatus(version: '2026.10.10')));
        await tester.pump();
        await tester.pump();
        await tester.pumpAndSettle();

        verify(() => app.downloader.fetchInfo(clipUrl)).called(2);
        expect(find.text("This site isn't supported"), findsOneWidget);
        expect(find.text('Check again'), findsOneWidget);
        expect(find.text('yt-dlp 2026.10.10'), findsOneWidget);

        await tapCard(tester, 'Check again');
        await tester.pump();
        verify(() => app.ytDlp.update()).called(1);
      },
    );

    testWidgets('a network failure says the update could not run', (
      tester,
    ) async {
      await openSheet(tester, app, answer: const Err(UnsupportedSiteFailure()));
      when(() => app.ytDlp.update()).thenAnswer(
        (_) async =>
            const Err(NetworkFailure(ErrorMessages.ytDlpUpdateOffline)),
      );

      await tapCard(tester, 'Update yt-dlp');
      await tester.pump();
      await tester.pump();

      expect(
        find.text("Couldn't update yt-dlp. Check your connection."),
        findsOneWidget,
      );
      expect(find.text('Update yt-dlp'), findsOneWidget);
      verify(() => app.downloader.fetchInfo(clipUrl)).called(1);
    });

    testWidgets('a busy yt-dlp says so', (tester) async {
      await openSheet(tester, app, answer: const Err(UnsupportedSiteFailure()));
      when(
        () => app.ytDlp.update(),
      ).thenAnswer((_) async => const Err(YtDlpBusyFailure()));

      await tapCard(tester, 'Update yt-dlp');
      await tester.pump();
      await tester.pump();

      expect(find.text(const YtDlpBusyFailure().message), findsOneWidget);
    });

    testWidgets('Settings is busy while an update started here runs', (
      tester,
    ) async {
      await unsupportedWithPendingUpdate(tester);
      await tapCard(tester, 'Update yt-dlp');
      await tester.pump();

      app.router.go(AppRoutes.settings);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Updating…'), findsOneWidget);
    });
  });

  group('a playlist', () {
    testWidgets('pushes /playlist; back keeps the link and clears the state', (
      tester,
    ) async {
      await openSheet(tester, app, answer: Ok(playlistInfo));

      expect(formatSheet, findsNothing);
      expect(find.byType(PlaylistView), findsOneWidget);

      app.router.pop();
      await tester.pumpAndSettle();

      expect(find.byType(PlaylistView), findsNothing);
      expect(fieldText(tester), clipUrl);

      // The state was cleared, so the link can be fetched again.
      await getFormats(tester);
      verify(() => app.downloader.fetchInfo(clipUrl)).called(2);
    });

    testWidgets('3 added clears the field and says so, with View', (
      tester,
    ) async {
      await openSheet(tester, app, answer: Ok(playlistInfo));

      app.router.pop(3);
      await tester.pumpAndSettle();

      expect(fieldText(tester), isEmpty);
      expect(find.text('3 videos added to Downloads'), findsOneWidget);

      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      expect(locationOf(app), AppRoutes.downloads);
    });

    testWidgets('1 added reads "1 video"', (tester) async {
      await openSheet(tester, app, answer: Ok(playlistInfo));

      app.router.pop(1);
      await tester.pumpAndSettle();

      expect(find.text('1 video added to Downloads'), findsOneWidget);
    });
  });

  group('choosing a quality', () {
    testWidgets('queues it with the saved folder and says so, with View', (
      tester,
    ) async {
      await openSheet(tester, app);

      popSheet(tester, Quality.p720);
      await tester.pumpAndSettle();

      expect(enqueued(app), [
        const DownloadRequest(
          url: clipUrl,
          title: 'A clip',
          thumbnail: 'https://example.com/t.jpg',
          quality: Quality.p720,
          folder: 'Fetchr',
          useAria2c: false,
          uploader: 'Uploader',
          durationSec: 754,
        ),
      ]);
      expect(find.text('Added to Downloads'), findsOneWidget);
      expect(fieldText(tester), isEmpty);

      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      expect(locationOf(app), AppRoutes.downloads);
    });

    testWidgets('the sheet button queues the picked row', (tester) async {
      await openSheet(tester, app);

      await tester.tap(find.text('720p'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Download 720p'));
      await tester.pumpAndSettle();

      expect(enqueued(app).single.quality, Quality.p720);
      expect(find.text('Added to Downloads'), findsOneWidget);
    });

    testWidgets('the cover row queues the cover photo with its thumbnail', (
      tester,
    ) async {
      await openSheet(tester, app);

      popSheet(tester, Quality.cover);
      await tester.pumpAndSettle();

      final request = enqueued(app).single;
      expect(request.quality, Quality.cover);
      expect(request.thumbnail, 'https://example.com/t.jpg');
    });

    testWidgets('dismissing starts nothing, keeps the link, allows a refetch', (
      tester,
    ) async {
      await openSheet(tester, app);

      popSheet(tester);
      await tester.pumpAndSettle();

      verifyNever(() => app.downloader.enqueue(any()));
      expect(fieldText(tester), clipUrl);

      await getFormats(tester);
      expect(formatSheet, findsOneWidget);
      verify(() => app.downloader.fetchInfo(clipUrl)).called(2);
    });

    testWidgets('dismissing while it still loads drops the fetch', (
      tester,
    ) async {
      final pending = Completer<Result<MediaInfo>>();
      when(
        () => app.downloader.fetchInfo(clipUrl),
      ).thenAnswer((_) => pending.future);
      await pumpHome(tester, app: app);
      await typeUrl(tester, clipUrl);
      await tester.tap(find.text('Get formats'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      popSheet(tester);
      await tester.pump(const Duration(milliseconds: 400));
      pending.complete(Ok(clipInfo));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(formatSheet, findsNothing);
      expect(find.text('Get formats'), findsOneWidget);
      expect(fieldText(tester), clipUrl);
    });

    testWidgets('a failed enqueue shows its message and keeps the link', (
      tester,
    ) async {
      await openSheet(tester, app);
      when(
        () => app.downloader.enqueue(any()),
      ).thenAnswer((_) async => const Err<void>(StorageFailure()));

      popSheet(tester, Quality.best);
      await tester.pumpAndSettle();

      expect(find.text(const StorageFailure().message), findsOneWidget);
      expect(find.text('Added to Downloads'), findsNothing);
      expect(fieldText(tester), clipUrl);
    });
  });

  group('the storage check', () {
    final big = mediaInfo(
      url: clipUrl,
      title: 'A clip',
      options: const [
        FormatOption(quality: Quality.best, sizeBytes: 1288 * mb),
        FormatOption(quality: Quality.p1080, sizeBytes: 900 * mb),
        FormatOption(quality: Quality.p720, sizeBytes: 300 * mb),
      ],
    );

    Future<void> openAndChoose(WidgetTester tester, Quality quality) async {
      when(
        () => app.downloader.freeSpaceBytes(),
      ).thenAnswer((_) async => const Ok(640 * mb));
      await openSheet(tester, app, answer: Ok(big));
      popSheet(tester, quality);
      await tester.pumpAndSettle();
    }

    testWidgets('a pick that does not fit shows the card, enqueues nothing', (
      tester,
    ) async {
      await openAndChoose(tester, Quality.best);

      expect(find.text('Not enough storage'), findsOneWidget);
      expect(
        find.textContaining(formatBytes(1288 * mb), findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining(formatBytes(640 * mb), findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Lower quality'), findsOneWidget);
      expect(find.text('Open Library'), findsOneWidget);
      verifyNever(() => app.downloader.enqueue(any()));
      expect(fieldText(tester), clipUrl);
      expect(fieldBorder(tester).top.color, lightTokens().error);
    });

    testWidgets('Lower quality reopens the sheet on the next option down', (
      tester,
    ) async {
      await openAndChoose(tester, Quality.best);

      await tapCard(tester, 'Lower quality');
      await tester.pumpAndSettle();

      expect(formatSheet, findsOneWidget);
      expect(tester.widget<FormatSheet>(formatSheet).preselect, Quality.p1080);
      expect(find.text('Not enough storage'), findsNothing);
      verify(() => app.downloader.fetchInfo(clipUrl)).called(1);

      popSheet(tester, Quality.p720);
      await tester.pumpAndSettle();

      expect(enqueued(app).single.quality, Quality.p720);
      expect(find.text('Added to Downloads'), findsOneWidget);
    });

    testWidgets('Open Library goes to the Library', (tester) async {
      await openAndChoose(tester, Quality.best);

      await tapCard(tester, 'Open Library');
      await tester.pumpAndSettle();

      expect(locationOf(app), AppRoutes.library);
    });

    testWidgets('editing the link clears the card', (tester) async {
      await openAndChoose(tester, Quality.best);

      await typeUrl(tester, '${clipUrl}x');
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Not enough storage'), findsNothing);
    });

    testWidgets('a pick that fits is enqueued', (tester) async {
      await openAndChoose(tester, Quality.p720);

      expect(find.text('Not enough storage'), findsNothing);
      verify(() => app.downloader.enqueue(any())).called(1);
    });
  });

  group('shared links', () {
    testWidgets('a link the app was launched with is filled and fetched', (
      tester,
    ) async {
      stubFetch(app, Ok(clipInfo));
      await pumpHome(
        tester,
        app: app,
        initialShare: [sharedText('Video $clipUrl')],
      );
      await tester.pumpAndSettle();

      expect(fieldText(tester), clipUrl);
      verify(() => app.downloader.fetchInfo(clipUrl)).called(1);
      expect(formatSheet, findsOneWidget);
    });

    testWidgets('shared text without a link is ignored', (tester) async {
      await pumpHome(tester, app: app, initialShare: [sharedText('hello')]);

      expect(fieldText(tester), isEmpty);
      verifyNever(() => app.downloader.fetchInfo(any()));
    });

    testWidgets('a link shared while the app runs is filled and fetched', (
      tester,
    ) async {
      stubFetch(app, Ok(clipInfo));
      final home = await pumpHome(tester, app: app);

      home.shares.add([sharedText(clipUrl)]);
      await tester.pumpAndSettle();

      expect(fieldText(tester), clipUrl);
      verify(() => app.downloader.fetchInfo(clipUrl)).called(1);
      expect(formatSheet, findsOneWidget);
    });

    testWidgets('a link shared while another tab shows opens the sheet', (
      tester,
    ) async {
      stubFetch(app, Ok(clipInfo));
      final home = await pumpHome(tester, app: app);
      app.router.go(AppRoutes.downloads);
      await tester.pumpAndSettle();
      expect(locationOf(app), AppRoutes.downloads);

      home.shares.add([sharedText(clipUrl)]);
      await tester.pumpAndSettle();

      expect(locationOf(app), AppRoutes.home);
      expect(formatSheet, findsOneWidget);
      expect(fieldText(tester), clipUrl);
    });

    testWidgets('a link shared behind an open sheet is filled, not fetched', (
      tester,
    ) async {
      final home = await openSheet(tester, app);

      home.shares.add([sharedText(otherUrl)]);
      await tester.pump();
      await tester.pump();

      expect(fieldText(tester), otherUrl);
      verifyNever(() => app.downloader.fetchInfo(otherUrl));
      expect(formatSheet, findsOneWidget);
    });

    testWidgets('a link shared behind the sheet survives its download', (
      tester,
    ) async {
      final home = await openSheet(tester, app);
      home.shares.add([sharedText(otherUrl)]);
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('720p'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Download 720p'));
      await tester.pumpAndSettle();

      expect(enqueued(app).single.url, clipUrl);
      expect(find.text('Added to Downloads'), findsOneWidget);
      expect(fieldText(tester), otherUrl);
    });
  });

  group('the picker by window', () {
    final dialog = find.ancestor(
      of: formatSheet,
      matching: find.byType(Dialog),
    );

    testWidgets('700 dp: a 480 wide dialog that picks like the sheet', (
      tester,
    ) async {
      await openSheet(tester, app, size: const Size(700, 1000));

      expect(dialog, findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      final surface = find
          .descendant(of: dialog, matching: find.byType(Material))
          .first;
      expect(tester.getSize(surface).width, closeTo(480, 1));

      await tester.tap(find.text('720p'));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Download 720p'));
      await tester.pumpAndSettle();

      expect(enqueued(app).single.url, clipUrl);
      expect(dialog, findsNothing);
    });

    testWidgets('360 dp: still a bottom sheet', (tester) async {
      await openSheet(tester, app);

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('right to left: the sizes stay left to right', (tester) async {
      await openSheet(tester, app, builder: rtl);

      final sizes = find.text('size unknown');
      expect(sizes, findsNWidgets(clipInfo.options.length));
      for (final size in tester.widgetList<Text>(sizes)) {
        expect(size.textDirection, TextDirection.ltr);
      }
    });
  });
}
