import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/routes/app_routes.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/modules/downloader/domain/entities/download_request.dart';
import 'package:grabby/modules/downloader/domain/entities/download_task.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/download_card.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/home_header.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/quality_option.dart';
import 'package:grabby/modules/settings/di/settings_providers.dart';
import 'package:mocktail/mocktail.dart';

import '../core/widgets/widget_harness.dart';
import '../modules/downloader/presentation/views/home_view_support.dart';
import '../modules/library/presentation/views/library_view_harness.dart'
    as library_harness;
import '../modules/library/presentation/views/player_view_harness.dart'
    as player_harness;
import '../support/app_fonts.dart';
import '../support/fake_app.dart';
import '../support/fixtures.dart';
import 'responsive_support.dart';

// The app clamps the platform text scale at 1.3 (`MediaQuery.withClampedTextScaling`
// in App), so the worst a screen sees is 1.3 on the smallest phone it supports.
// Real fonts: the test font rounds evenly and hides lines that overflow by a
// pixel with the shipped ones.
const _phone = Size(320, 640);
const _scale = 1.3;

void main() {
  setUpAll(loadAppFonts);

  void scaleText(WidgetTester tester) {
    tester.platformDispatcher.textScaleFactorTestValue = _scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Future<FakeApp> pump(
    WidgetTester tester, {
    FakeApp? app,
    String location = AppRoutes.home,
  }) async {
    scaleText(tester);
    return pumpFakeApp(
      tester,
      app: app ?? homeApp(),
      initialLocation: location,
      theme: AppTheme.dark(),
      size: _phone,
    );
  }

  // Guards the harness: a test that ran at 1.0 would prove nothing.
  void expectScaled(WidgetTester tester) {
    final scaler = MediaQuery.textScalerOf(
      tester.element(find.byType(Scaffold).first),
    );
    expect(scaler.scale(10), closeTo(10 * _scale, 1e-9));
  }

  void expectNoOverflow(WidgetTester tester) =>
      expect(tester.takeException(), isNull);

  void expectFound(Iterable<Finder> finders) {
    for (final finder in finders) {
      expect(finder, findsOneWidget, reason: '$finder');
    }
  }

  // A pinned action must not be pushed off the screen by large text.
  void expectOnScreen(WidgetTester tester, Iterable<Finder> finders) {
    final screen = (Offset.zero & _phone).inflate(.01);
    for (final finder in finders) {
      final rect = tester.getRect(finder);
      expect(
        screen.contains(rect.topLeft) && screen.contains(rect.bottomRight),
        isTrue,
        reason: '$finder is at $rect, off a $_phone screen',
      );
    }
  }

  Finder tab(String label) => navTab(label);

  testWidgets('Home keeps its actions and its recent rows', (tester) async {
    final app = homeApp();
    stubTasks(app, [
      for (final id in ['r1', 'r2', 'r3']) doneTask(id, title: longTitle),
    ]);
    await pump(tester, app: app);
    await typeUrl(tester, '$clipUrl&list=${'x' * 120}');

    expectScaled(tester);
    expectNoOverflow(tester);
    expectFound([
      find.widgetWithText(FilledButton, 'Get formats'),
      find.byTooltip('Clear URL'),
      tab('Home'),
      tab('Downloads'),
      tab('Library'),
      tab('Settings'),
    ]);

    // The recent rows sit below the fold; scrolling builds them.
    final page = find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('See library'),
      200,
      scrollable: page,
    );
    expectNoOverflow(tester);
    expectFound([find.text('Recent'), find.text('See library')]);
  });

  testWidgets('Home with an error card keeps its actions', (tester) async {
    final app = homeApp();
    scaleText(tester);
    await pumpFakeApp(tester, app: app, theme: AppTheme.dark(), size: _phone);
    stubFetch(app, const Err(UnsupportedSiteFailure()));
    await typeUrl(tester, clipUrl);
    await getFormats(tester);

    expectNoOverflow(tester);
    expectFound([
      find.text("This site isn't supported"),
      find.text('Update yt-dlp'),
      find.text('Edit link'),
    ]);
  });

  testWidgets('the format sheet keeps Cancel, Download and every option', (
    tester,
  ) async {
    scaleText(tester);
    await pumpOpenSheet(
      tester,
      _phone,
      info: richVideo(title: longTitle),
      theme: AppTheme.dark(),
    );

    expectScaled(tester);
    expect(formatSheet, findsOneWidget);
    expectNoOverflow(tester);
    expect(find.byType(QualityOption), findsNWidgets(6));
    final actions = [
      find.descendant(of: formatSheet, matching: find.text('Cancel')),
      find.descendant(
        of: formatSheet,
        matching: find.widgetWithText(FilledButton, 'Download best'),
      ),
    ];
    expectFound(actions);
    expectOnScreen(tester, actions);
  });

  testWidgets('a playlist with a long title keeps its actions', (tester) async {
    final app = await pump(tester);
    final info = playlistOf(30, title: longTitle);
    unawaited(app.router.push<int>(AppRoutes.playlist, extra: info));
    await tester.pumpAndSettle();

    expectScaled(tester);
    expectNoOverflow(tester);
    final actions = [
      find.byTooltip('Back'),
      find.text('Select all'),
      find.widgetWithText(FilledButton, 'Download 30 videos'),
    ];
    expectFound([...actions, find.text('30 of 30 selected')]);
    expectOnScreen(tester, actions);
  });

  testWidgets('a downloading card keeps Pause, Cancel and its stats', (
    tester,
  ) async {
    final app = homeApp();
    stubTasks(app, [runningTask(title: longTitle)]);
    await pump(tester, app: app, location: AppRoutes.downloads);

    expectScaled(tester);
    expectNoOverflow(tester);
    expect(find.byType(DownloadCard), findsOneWidget);
    final buttons = [
      find.byTooltip('Pause download'),
      find.byTooltip('Cancel download'),
    ];
    expectFound([...buttons, find.textContaining('64%')]);
    expectOnScreen(tester, buttons);
  });

  testWidgets('Settings keeps every control', (tester) async {
    await pump(tester, location: AppRoutes.settings);

    expectScaled(tester);
    expectNoOverflow(tester);
    expectFound([
      find.text('Default quality'),
      for (final pill in ['Best', '1080p', '720p', '480p', 'MP3'])
        find.text(pill),
      find.text('Save folder'),
      find.text('Faster downloads (aria2c)'),
      find.text('Theme'),
      for (final mode in ['System', 'Dark', 'Light']) find.text(mode),
      find.text('Accent'),
      find.widgetWithText(FilledButton, 'Update yt-dlp'),
      find.text('Check for updates daily'),
    ]);
  });

  // The header alone, 293 dp wide as the page is on the smallest phone.
  group('the Home wordmark', () {
    Future<void> pumpHeader(WidgetTester tester, {double width = 293}) async {
      final app = homeApp();
      when(
        () => app.ytDlp.status(),
      ).thenAnswer((_) async => Ok(ytDlpStatus(version: '2026.10.09')));
      await pumpThemed(
        tester,
        ProviderScope(
          overrides: [ytDlpRepositoryProvider.overrideWithValue(app.ytDlp)],
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, child: const HomeHeader()),
          ),
        ),
        size: _phone,
        textScale: _scale,
      );
      await tester.pump();
      await tester.pump();
      expectScaled(tester);
    }

    bool nameCut(WidgetTester tester) => tester
        .renderObject<RenderParagraph>(find.text('Fetchr'))
        .didExceedMaxLines;

    testWidgets('shows the whole name beside the version', (tester) async {
      await pumpHeader(tester);

      expectNoOverflow(tester);
      expect(nameCut(tester), isFalse);
      expect(find.text('yt-dlp 2026.10.09'), findsOneWidget);
    });

    testWidgets('ellipsises in a row too narrow for it, with no overflow', (
      tester,
    ) async {
      await pumpHeader(tester, width: 100);

      expectNoOverflow(tester);
      expect(nameCut(tester), isTrue);
    });
  });

  // Beyond the plan's five screens: the rows and pages the same rule covers.
  group('the rest of the app', () {
    DownloadRequest titled(String id) =>
        downloadRequest(url: 'https://example.com/$id', title: longTitle);

    testWidgets('Downloads keeps the buttons of every kind of row', (
      tester,
    ) async {
      final app = homeApp();
      stubTasks(app, [
        runningTask(id: 'run', title: longTitle),
        downloadTask(
          id: 'pau',
          status: TaskStatus.paused,
          progress: .4,
          downloadedBytes: 40 * mb,
          totalBytes: 100 * mb,
          request: titled('pau'),
        ),
        downloadTask(
          id: 'can',
          status: TaskStatus.canceled,
          request: titled('can'),
        ),
        downloadTask(
          id: 'que',
          status: TaskStatus.queued,
          request: titled('que'),
        ),
        downloadTask(
          id: 'net',
          status: TaskStatus.failed,
          errorCode: 'network',
          progress: .41,
          request: titled('net'),
        ),
        downloadTask(
          id: 'perm',
          status: TaskStatus.failed,
          errorCode: 'permission_denied',
          request: titled('perm'),
        ),
        doneTask('done', title: longTitle),
      ]);
      await pump(tester, app: app, location: AppRoutes.downloads);
      final list = find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first;

      // Rows build as they scroll in, so each label is reached in order.
      for (final label in [
        find.byTooltip('Pause download'),
        find.byTooltip('Resume download'),
        find.text('Restart'),
        find.text('Retry'),
        find.text('Open settings'),
        find.textContaining('Movies/Fetchr'),
      ]) {
        await tester.scrollUntilVisible(label, 150, scrollable: list);
        expectNoOverflow(tester);
        expect(label, findsAtLeastNWidgets(1), reason: '$label');
      }
    });

    testWidgets('the Library keeps its filters and card menus', (tester) async {
      library_harness.setUpLibraryHarness();
      library_harness.stubList(
        () async => Ok([
          for (var i = 0; i < 6; i++)
            libraryItem(
              uri: 'content://media/external/video/media/$i',
              name: '$longTitle $i.mp4',
              durationMs: 65000,
              width: 1920,
              height: 1080,
              relativePath: 'Movies/Fetchr/',
            ),
        ]),
      );
      scaleText(tester);
      await library_harness.pumpLibrary(tester, size: _phone);

      expectScaled(tester);
      expectNoOverflow(tester);
      expectFound([
        find.widgetWithText(ChoiceChip, 'All'),
        find.widgetWithText(ChoiceChip, 'Video'),
        find.widgetWithText(ChoiceChip, 'Audio'),
      ]);
      expect(find.byTooltip('More actions'), findsAtLeastNWidgets(1));
    });

    testWidgets('the Player keeps its controls and its actions', (
      tester,
    ) async {
      player_harness.setUpPlayerHarness();
      final item = libraryItem(
        uri: 'content://media/external/video/media/1',
        name: '$longTitle.mp4',
        sizeBytes: 5452595,
        durationMs: 768000,
        width: 1920,
        height: 1080,
        relativePath: 'Movies/Fetchr/',
      );
      scaleText(tester);
      await player_harness.pumpPlayer(
        tester,
        item,
        size: _phone,
        list: () async => Ok([item]),
      );

      expectScaled(tester);
      expectNoOverflow(tester);
      expectFound([
        find.byTooltip('Back'),
        find.byTooltip('Fullscreen'),
        find.byTooltip('Play'),
        find.text('Share'),
        find.text('Delete'),
        find.text('Location'),
      ]);
    });
  });
}
