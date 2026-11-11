import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:grabby/app/routes/app_routes.dart';
import 'package:grabby/app/shared/domain/entities/quality.dart';
import 'package:grabby/app/shared/domain/entities/yt_dlp_status.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/core/gen/assets.gen.dart';
import 'package:grabby/core/theme/app_spacing.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/utils/formatters.dart';
import 'package:grabby/core/utils/scale.dart';
import 'package:grabby/core/widgets/app_icon.dart';
import 'package:grabby/modules/downloader/di/downloader_providers.dart';
import 'package:grabby/modules/downloader/domain/entities/download_request.dart';
import 'package:grabby/modules/downloader/domain/entities/download_task.dart';
import 'package:grabby/modules/downloader/presentation/views/home_view.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/clipboard_suggestion.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/home_header.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/home_recent.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/media_row.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/url_field.dart';
import 'package:grabby/modules/settings/di/settings_providers.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../core/widgets/widget_harness.dart';
import '../../../../support/fake_app.dart';
import '../../../../support/fixtures.dart';
import 'home_view_support.dart';

const _caption = 'Link found on your clipboard';
const _hero = 'Paste a link.\nGet the file.';

void main() {
  late FakeApp app;

  setUpAll(() => registerFallbackValue(<DownloadRequest>[]));

  setUp(() => app = homeApp());

  group('the page', () {
    testWidgets('the header, hero, subline and the input block', (
      tester,
    ) async {
      await pumpHome(tester, app: app);

      expect(find.text('Fetchr'), findsOneWidget);
      expect(find.text(_hero), findsOneWidget);
      expect(
        find.text('Or share any video to Fetchr from another app.'),
        findsOneWidget,
      );
      expect(find.text('VIDEO OR PLAYLIST URL'), findsOneWidget);
      expect(find.text('https://…'), findsOneWidget);
    });

    testWidgets('empty: Paste shows, Get formats is off, nothing is recent', (
      tester,
    ) async {
      await pumpHome(tester, app: app);

      expect(find.text('Paste'), findsOneWidget);
      expect(find.byTooltip('Clear URL'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Get formats'),
            )
            .onPressed,
        isNull,
      );
      expect(find.text('Your downloads will show up here.'), findsOneWidget);
      expect(find.text('Recent'), findsNothing);
      expect(find.byType(MediaRow), findsNothing);
      expect(fieldBorder(tester), Border.all(color: lightTokens().border));
    });

    testWidgets('under 360 dp the hero is 30 and the gutter 16', (
      tester,
    ) async {
      await pumpHome(tester, app: app);
      double heroSize() =>
          tester.widget<Text>(find.text(_hero)).style!.fontSize!;
      double gutter() => tester.getTopLeft(find.byType(UrlField)).dx;
      expect(heroSize(), 34);
      expect(gutter(), Gap.gutter.w);

      tester.view.physicalSize = const Size(1020, 2400);
      await tester.pump();

      expect(heroSize(), 30);
      expect(gutter(), Gap.gutterNarrow.w);
    });

    for (final MapEntry(key: mode, value: theme) in themes.entries) {
      testWidgets('$mode: the logo tile is the primary fill with its glyph', (
        tester,
      ) async {
        await pumpHome(tester, app: app, theme: theme);
        final tokens = theme.extension<AppTokens>()!;

        final glyph = find.byWidgetPredicate(
          (w) => w is AppIcon && w.icon == Assets.icons.logo,
        );
        final tile = tester.widget<Container>(
          find.ancestor(of: glyph, matching: find.byType(Container)).first,
        );
        final decoration = tile.decoration! as BoxDecoration;
        // Dark is the accent with an onAccent glyph, light is the ink with an
        // accent glyph.
        expect(decoration.color, theme.colorScheme.primary);
        expect(tester.widget<AppIcon>(glyph).color, tokens.primaryIcon);
        expect(decoration.borderRadius, BorderRadius.circular(9.r));
        expect(tester.getSize(find.byWidget(tile)), Size.square(30.r));
      });
    }
  });

  group('the yt-dlp chip', () {
    testWidgets('shows the version', (tester) async {
      when(
        () => app.ytDlp.status(),
      ).thenAnswer((_) async => Ok(ytDlpStatus(version: '2026.10.09')));
      await pumpHome(tester, app: app);

      expect(find.text('yt-dlp 2026.10.09'), findsOneWidget);
    });

    testWidgets('says bundled when native has no version', (tester) async {
      await pumpHome(tester, app: app);

      expect(find.text('yt-dlp bundled'), findsOneWidget);
    });

    testWidgets('is hidden while the status loads', (tester) async {
      final pending = Completer<Result<YtDlpStatus>>();
      when(() => app.ytDlp.status()).thenAnswer((_) => pending.future);
      await pumpHome(tester, app: app);

      expect(find.textContaining('yt-dlp'), findsNothing);

      pending.complete(Ok(ytDlpStatus(version: '1.0')));
      await tester.pump();
      expect(find.text('yt-dlp 1.0'), findsOneWidget);
    });

    testWidgets('is hidden when the status could not be read', (tester) async {
      when(
        () => app.ytDlp.status(),
      ).thenAnswer((_) async => const Err(UnexpectedFailure()));
      await pumpHome(tester, app: app);

      expect(find.textContaining('yt-dlp'), findsNothing);
    });

    Finder chipBox() => find
        .ancestor(
          of: find.text('yt-dlp bundled'),
          matching: find.byType(DecoratedBox),
        )
        .first;

    testWidgets('ends the row', (tester) async {
      await pumpHome(tester, app: app);

      expect(
        tester.getRect(chipBox()).right,
        closeTo(tester.getRect(find.byType(HomeHeader)).right, .5),
      );
    });

    testWidgets('ends the row on the left when the app is right to left', (
      tester,
    ) async {
      await pumpHome(tester, app: app, builder: rtl);

      expect(
        tester.getRect(chipBox()).left,
        closeTo(tester.getRect(find.byType(HomeHeader)).left, .5),
      );
    });

    testWidgets('keeps to one line when the version is long, at 1.3 text', (
      tester,
    ) async {
      when(() => app.ytDlp.status()).thenAnswer(
        (_) async => Ok(ytDlpStatus(version: '2026.10.09.nightly.20261009.ab')),
      );
      // The header alone, at the page's width on the smallest phone.
      await pumpThemed(
        tester,
        ProviderScope(
          overrides: [ytDlpRepositoryProvider.overrideWithValue(app.ytDlp)],
          child: const Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 293, child: HomeHeader()),
          ),
        ),
        size: const Size(320, 640),
        textScale: 1.3,
      );
      await tester.pump();
      await tester.pump();

      final chip = find.textContaining('yt-dlp 2026');
      expect(chip, findsOneWidget);
      expect(tester.takeException(), isNull);
      final text = tester.widget<Text>(chip);
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(
        tester.getRect(chip).right,
        lessThanOrEqualTo(tester.getRect(find.byType(HomeHeader)).right),
      );
    });
  });

  group('in a wide window', () {
    Finder page() => find.descendant(
      of: find.byType(HomeView),
      matching: find.byType(CustomScrollView),
    );

    // 700 is the narrowest window that leaves 560 beside the rail.
    for (final width in [700.0, 900.0]) {
      testWidgets('${width.round()} dp: a 560 column in the middle', (
        tester,
      ) async {
        await pumpHome(tester, app: app, size: Size(width, 1000));

        final room = tester.getRect(find.byType(HomeView));
        final column = tester.getRect(page());
        expect(column.width, Breakpoints.contentMax);
        expect(column.left - room.left, closeTo(room.right - column.right, .5));
        expect(
          tester.getTopLeft(find.byType(UrlField)).dx,
          closeTo(column.left + Gap.gutter.w, .01),
        );
      });
    }

    testWidgets('599 dp: the page fills the window', (tester) async {
      await pumpHome(tester, app: app, size: const Size(599, 900));

      expect(
        tester.getSize(page()).width,
        tester.getSize(find.byType(HomeView)).width,
      );
    });
  });

  group('the field', () {
    testWidgets('typing swaps Paste for Clear, and Clear empties it', (
      tester,
    ) async {
      await pumpHome(tester, app: app);

      await typeUrl(tester, clipUrl);
      expect(find.text('Paste'), findsNothing);
      expect(find.byTooltip('Clear URL'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear URL'));
      await tester.pump();

      expect(fieldText(tester), isEmpty);
      expect(find.text('Paste'), findsOneWidget);
    });

    testWidgets('Get formats needs a link, even one inside other text', (
      tester,
    ) async {
      await pumpHome(tester, app: app);
      FilledButton button() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Get formats'),
      );

      await typeUrl(tester, 'not a link');
      expect(button().onPressed, isNull);

      await typeUrl(tester, 'watch this $clipUrl now');
      expect(button().onPressed, isNotNull);
    });

    testWidgets('Paste fills the field with the link in the clipboard', (
      tester,
    ) async {
      final home = await pumpHome(tester, app: app);
      home.clipboard = 'copied $clipUrl';

      await tester.tap(find.text('Paste'));
      await tester.pump();
      await tester.pump();

      expect(fieldText(tester), clipUrl);
    });

    testWidgets('Paste keeps text that has no link', (tester) async {
      final home = await pumpHome(tester, app: app);
      home.clipboard = 'just words';

      await tester.tap(find.text('Paste'));
      await tester.pump();
      await tester.pump();

      expect(fieldText(tester), 'just words');
    });
  });

  group('the clipboard', () {
    testWidgets('a link on start shows the card and leaves the field empty', (
      tester,
    ) async {
      await pumpHome(tester, app: app, clipboard: 'look: $clipUrl');
      await tester.pumpAndSettle();

      expect(find.text(_caption), findsOneWidget);
      expect(find.text(clipUrl), findsOneWidget);
      expect(fieldText(tester), isEmpty);
      verifyNever(() => app.downloader.fetchInfo(any()));
    });

    testWidgets('text with no link shows nothing', (tester) async {
      await pumpHome(tester, app: app, clipboard: 'just some words');
      await tester.pumpAndSettle();

      expect(find.text(_caption), findsNothing);
    });

    testWidgets('Use fills the field and hides the card', (tester) async {
      await pumpHome(tester, app: app, clipboard: clipUrl);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Use'));
      await tester.pumpAndSettle();

      expect(fieldText(tester), clipUrl);
      expect(find.text(_caption), findsNothing);
      expect(find.byTooltip('Clear URL'), findsOneWidget);
    });

    testWidgets('a resume with the same clipboard does not offer it again', (
      tester,
    ) async {
      final home = await pumpHome(tester, app: app, clipboard: clipUrl);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use'));
      await tester.pumpAndSettle();

      // The field holds it: not offered.
      await resumeApp(tester);
      expect(find.text(_caption), findsNothing);

      // The field is cleared: it was offered before, so still not offered.
      await tester.tap(find.byTooltip('Clear URL'));
      await tester.pump();
      await resumeApp(tester);
      expect(find.text(_caption), findsNothing);
      expect(fieldText(tester), isEmpty);

      // A new link is.
      home.clipboard = otherUrl;
      await resumeApp(tester);
      expect(find.text(_caption), findsOneWidget);
      expect(find.text(otherUrl), findsOneWidget);
      expect(fieldText(tester), isEmpty);
    });

    testWidgets('a card nobody used stays, and is not offered again', (
      tester,
    ) async {
      await pumpHome(tester, app: app, clipboard: clipUrl);
      await tester.pumpAndSettle();

      await resumeApp(tester);

      expect(find.text(_caption), findsOneWidget);
    });

    testWidgets('never when the field already holds the link', (tester) async {
      final home = await pumpHome(tester, app: app);
      await typeUrl(tester, clipUrl);
      home.clipboard = clipUrl;

      await resumeApp(tester);

      expect(find.text(_caption), findsNothing);
    });

    testWidgets('typing the offered link hides the card', (tester) async {
      await pumpHome(tester, app: app, clipboard: clipUrl);
      await tester.pumpAndSettle();

      await typeUrl(tester, clipUrl);
      await tester.pumpAndSettle();

      expect(find.text(_caption), findsNothing);
    });

    testWidgets('is hidden while an error card shows', (tester) async {
      stubFetch(app, const Err(NetworkFailure()));
      await pumpHome(tester, app: app, clipboard: otherUrl);
      await tester.pumpAndSettle();
      expect(find.text(_caption), findsOneWidget);

      await typeUrl(tester, clipUrl);
      await getFormats(tester);

      expect(find.text('No internet connection'), findsOneWidget);
      expect(find.text(_caption), findsNothing);
      expect(find.byType(ClipboardSuggestion), findsOneWidget);
    });
  });

  group('recent downloads', () {
    DownloadTask done(
      String id, {
      Quality quality = Quality.p720,
      int? totalBytes,
      required int finished,
      String? savedUri = 'content://media/external/video/media/1',
      TaskStatus status = TaskStatus.completed,
    }) => downloadTask(
      id: id,
      status: status,
      request: downloadRequest(
        title: 'Clip $id',
        quality: quality,
        durationSec: 61,
      ),
      totalBytes: totalBytes,
      savedUri: savedUri,
      finishedAt: DateTime.utc(2026, 1, finished),
    );

    // Downloads would be the first screen under pumpHome, and a running task
    // keeps it animating.
    Future<void> pumpOnHome(WidgetTester tester) =>
        pumpFakeApp(tester, app: app);

    testWidgets('the three newest finished downloads, newest first', (
      tester,
    ) async {
      stubTasks(app, [
        done('old', finished: 1),
        done('c', finished: 4),
        done('running', finished: 9, status: TaskStatus.running),
        done('gone', finished: 9, savedUri: null),
        done('a', finished: 6, quality: Quality.mp3, totalBytes: 6500000),
        done('b', finished: 5, totalBytes: 22 * mb),
      ]);
      await pumpOnHome(tester);

      expect(find.byType(MediaRow), findsNWidgets(3));
      double top(String title) => tester.getTopLeft(find.text(title)).dy;
      expect(top('Clip a'), lessThan(top('Clip b')));
      expect(top('Clip b'), lessThan(top('Clip c')));
      expect(find.text('Clip old'), findsNothing);
      expect(find.text('Clip running'), findsNothing);
      expect(find.text('Clip gone'), findsNothing);
      expect(find.text('Recent'), findsOneWidget);
      expect(find.text('See library'), findsOneWidget);
      expect(find.text('Your downloads will show up here.'), findsNothing);
      expect(
        find.text('Audio · MP3 · ${formatBytes(6500000)}'),
        findsOneWidget,
      );
      expect(find.text('720p · MP4 · ${formatBytes(22 * mb)}'), findsOneWidget);
      expect(find.text('720p · MP4'), findsOneWidget);
    });

    testWidgets('See library opens the Library', (tester) async {
      stubTasks(app, [done('a', finished: 1)]);
      await pumpOnHome(tester);

      await tester.tap(find.text('See library'));
      await tester.pumpAndSettle();

      expect(locationOf(app), AppRoutes.library);
    });

    testWidgets('downloads still running leave the empty state', (
      tester,
    ) async {
      stubTasks(app, [done('a', finished: 1, status: TaskStatus.running)]);
      await pumpOnHome(tester);

      expect(find.text('Your downloads will show up here.'), findsOneWidget);
      expect(find.text('Recent'), findsNothing);
    });

    testWidgets('stays quiet until the first snapshot', (tester) async {
      when(
        () => app.downloader.watchTasks(),
      ).thenAnswer((_) => const Stream<List<DownloadTask>>.empty());
      await pumpOnHome(tester);

      expect(find.byType(MediaRow), findsNothing);
      expect(find.text('Your downloads will show up here.'), findsNothing);
      expect(find.text('Recent'), findsNothing);
    });

    testWidgets('a tap opens the player on the saved file', (tester) async {
      useView(tester, const Size(390, 844));
      stubTasks(app, [
        done('a', finished: 1, savedUri: 'content://media/external/video/7'),
      ]);
      // The real player needs a native video backend, so the route is a stub.
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(
              body: CustomScrollView(slivers: [HomeRecent(gutter: 20)]),
            ),
          ),
          GoRoute(
            path: AppRoutes.player,
            builder: (_, state) => Text(
              'player ${state.uri.queryParameters['uri']} '
              '${state.uri.queryParameters['title']}',
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            downloaderRepositoryProvider.overrideWithValue(app.downloader),
          ],
          child: ScaleScope(
            child: MaterialApp.router(
              theme: AppTheme.light(),
              routerConfig: router,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Clip a'));
      await tester.pumpAndSettle();

      expect(
        find.text('player content://media/external/video/7 Clip a'),
        findsOneWidget,
      );
    });
  });
}
