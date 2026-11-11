import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/routes/app_routes.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/core/gen/fonts.gen.dart';
import 'package:grabby/core/theme/app_spacing.dart';
import 'package:grabby/core/utils/scale.dart';
import 'package:grabby/core/widgets/app_button.dart';
import 'package:grabby/core/widgets/app_progress_bar.dart';
import 'package:grabby/modules/downloader/domain/entities/download_task.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/download_card.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/url_field.dart';
import 'package:grabby/modules/library/presentation/views/widgets/library_card.dart';
import 'package:grabby/modules/settings/presentation/views/widgets/settings_section.dart';
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

const _phone = Size(390, 844);
const _hero = 'Paste a link.\nGet the file.';

// A `Size(width, 800)` phone or a `Size(width, 1000)` tablet.
Size _at(double width) => Size(width, width < 600 ? 800 : 1000);

Future<FakeApp> _pumpAt(
  WidgetTester tester,
  Size size, {
  FakeApp? app,
  String location = AppRoutes.home,
  TransitionBuilder? builder,
}) => pumpFakeApp(
  tester,
  app: app ?? homeApp(),
  initialLocation: location,
  size: size,
  builder: builder,
);

void main() {
  setUpAll(loadAppFonts);

  group('the shell', () {
    for (final (width, rail) in [
      (390.0, false),
      (599.0, false),
      (600.0, true),
      (839.0, true),
      (900.0, true),
    ]) {
      testWidgets('${width.round()} dp shows a ${rail ? 'rail' : 'bar'}', (
        tester,
      ) async {
        await _pumpAt(tester, _at(width));

        expect(
          find.byType(NavigationRail),
          rail ? findsOneWidget : findsNothing,
        );
        expect(navBar, rail ? findsNothing : findsOneWidget);
      });
    }

    testWidgets('the rail holds the four tabs and switches between them', (
      tester,
    ) async {
      await _pumpAt(tester, _at(700));
      NavigationRail rail() =>
          tester.widget<NavigationRail>(find.byType(NavigationRail));

      expect(rail().destinations, hasLength(4));
      expect(rail().selectedIndex, 0);

      rail().onDestinationSelected!(3);
      await tester.pumpAndSettle();

      expect(rail().selectedIndex, 3);
      expect(find.text('DOWNLOAD ENGINE'), findsOneWidget);
    });

    // One column pages; the Library grid has its own column counts below.
    final pages = <(String, String, Finder)>[
      ('Home', AppRoutes.home, find.byType(UrlField)),
      ('Downloads', AppRoutes.downloads, find.byType(DownloadCard)),
      ('Settings', AppRoutes.settings, find.byType(SettingsSection)),
    ];
    for (final width in [700.0, 900.0]) {
      for (final (name, location, anchor) in pages) {
        testWidgets(
          '$name at ${width.round()} dp is at most 560 wide and centred',
          (tester) async {
            final app = homeApp();
            stubTasks(app, [runningTask()]);
            await _pumpAt(tester, _at(width), app: app, location: location);

            expect(find.byType(NavigationRail), findsOneWidget);
            final rail = tester.getRect(find.byType(NavigationRail));
            final content = spanOf(tester, anchor);
            expect(content.width, lessThanOrEqualTo(560));
            // Equal room between the rail and the content, and the content
            // and the window's edge.
            expect(
              content.left - rail.right,
              closeTo(width - content.right, 2),
            );
          },
        );
      }
    }
  });

  group('the format picker', () {
    for (final width in [600.0, 700.0, 900.0]) {
      testWidgets('${width.round()} dp opens as a 480 wide dialog', (
        tester,
      ) async {
        await pumpOpenSheet(tester, _at(width));

        expect(formatSheet, findsOneWidget);
        final dialog = find.ancestor(
          of: formatSheet,
          matching: find.byType(Dialog),
        );
        expect(dialog, findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
        // The dialog's own surface is the 480; the picker may pad inside it.
        final surface = find
            .descendant(of: dialog, matching: find.byType(Material))
            .first;
        expect(tester.getSize(surface).width, closeTo(480, 1));
        expect(tester.getSize(formatSheet).width, lessThanOrEqualTo(481));
      });
    }

    for (final width in [390.0, 599.0]) {
      testWidgets('${width.round()} dp opens as a bottom sheet', (
        tester,
      ) async {
        await pumpOpenSheet(tester, _at(width));

        expect(formatSheet, findsOneWidget);
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(find.byType(Dialog), findsNothing);
      });
    }
  });

  // In the routed app, so the shell's own width limit is part of what is
  // measured: a grid sized from its parent's width would never see 840.
  group('the Library grid', () {
    for (final (width, columns) in [
      (360.0, 2),
      (599.0, 2),
      (600.0, 3),
      (700.0, 3),
      (839.0, 3),
      (840.0, 4),
      (900.0, 4),
    ]) {
      testWidgets('${width.round()} dp has $columns columns', (tester) async {
        final app = homeApp();
        when(() => app.library.list(any())).thenAnswer(
          (_) async => Ok([
            for (var i = 0; i < 16; i++)
              libraryItem(
                uri: 'content://media/external/video/media/$i',
                name: 'Clip $i.mp4',
                durationMs: 65000,
                width: 1920,
                height: 1080,
                relativePath: 'Movies/Fetchr/',
              ),
          ]),
        );
        when(
          () => app.library.thumbnail(any(), any(), any()),
        ).thenAnswer((_) async => const Ok(null));
        await _pumpAt(
          tester,
          _at(width),
          app: app,
          location: AppRoutes.library,
        );

        final cards = find.byType(LibraryCard);
        expect(cards, findsAtLeastNWidgets(columns));
        final lefts = {
          for (var i = 0; i < cards.evaluate().length; i++)
            tester.getTopLeft(cards.at(i)).dx.round(),
        };
        expect(lefts, hasLength(columns));
      });
    }
  });

  group('the Player', () {
    setUp(player_harness.setUpPlayerHarness);

    Future<(Rect, Rect)> pumpPlayerAt(WidgetTester tester, Size size) async {
      await player_harness.pumpPlayer(
        tester,
        player_harness.videoItem,
        size: size,
      );
      return (
        tester.getRect(find.byKey(player_harness.videoKey)),
        tester.getRect(find.text(player_harness.videoItem.name)),
      );
    }

    testWidgets('900 dp splits: video left, details right', (tester) async {
      final (video, title) = await pumpPlayerAt(tester, _at(900));

      expect(video.right, lessThanOrEqualTo(title.left));
      expect(title.top, lessThan(video.bottom));
      expect(tester.getCenter(find.text('Share')).dx, greaterThan(video.right));
      expect(
        tester.getCenter(find.text('Location')).dx,
        greaterThan(video.right),
      );
    });

    testWidgets('700 dp keeps the details under the video', (tester) async {
      final (video, title) = await pumpPlayerAt(tester, _at(700));

      expect(title.top, greaterThanOrEqualTo(video.bottom - .5));
    });
  });

  group('under 360 dp', () {
    for (final (width, narrow) in [
      (340.0, true),
      (359.0, true),
      (360.0, false),
    ]) {
      final label = '${width.round()} dp';

      testWidgets('$label: the gutter is ${narrow ? 16 : 20}, the hero '
          '${narrow ? 30 : 34}', (tester) async {
        await _pumpAt(tester, _at(width));

        final gutter = narrow ? Gap.gutterNarrow : Gap.gutter;
        expect(
          tester.getTopLeft(find.byType(UrlField)).dx,
          closeTo(gutter.w, .01),
        );
        expect(
          tester.widget<Text>(find.text(_hero)).style!.fontSize,
          narrow ? 30 : 34,
        );
      });

      testWidgets('$label: the quality pills are mono ${narrow ? 11 : 12}', (
        tester,
      ) async {
        await _pumpAt(tester, _at(width), location: AppRoutes.settings);

        final style = tester
            .widget<AnimatedDefaultTextStyle>(
              find
                  .ancestor(
                    of: find.text('1080p'),
                    matching: find.byType(AnimatedDefaultTextStyle),
                  )
                  .first,
            )
            .style;
        expect(style.fontFamily, FontFamily.jetBrainsMono);
        expect(style.fontSize, narrow ? 11 : 12);
      });

      testWidgets(
        '$label: the error actions ${narrow ? 'stack' : 'sit side by side'}',
        (tester) async {
          final app = homeApp();
          stubFetch(app, const Err(UnsupportedSiteFailure()));
          await _pumpAt(tester, _at(width), app: app);
          await typeUrl(tester, clipUrl);
          await getFormats(tester);

          final first = tester.getRect(
            find.widgetWithText(AppButton, 'Update yt-dlp'),
          );
          final second = tester.getRect(
            find.widgetWithText(AppButton, 'Edit link'),
          );
          if (narrow) {
            expect(second.top, greaterThanOrEqualTo(first.bottom));
            expect(second.left, first.left);
            expect(second.width, first.width);
          } else {
            expect(second.top, first.top);
          }
        },
      );
    }
  });

  group('right to left', () {
    testWidgets('the URL field keeps its direction and its layout', (
      tester,
    ) async {
      await _pumpAt(tester, _phone, builder: rtl);
      final field = tester.getRect(find.byType(UrlField));

      // Paste ends the row on the right, as in the left to right app.
      expect(
        tester.getCenter(find.text('Paste')).dx,
        greaterThan(field.center.dx),
      );

      await typeUrl(tester, clipUrl);

      expect(
        tester.widget<TextField>(urlField).textDirection,
        TextDirection.ltr,
      );
      expect(
        tester.getCenter(find.byTooltip('Clear URL')).dx,
        greaterThan(field.center.dx),
      );
    });

    testWidgets('the save folders in Settings stay left to right', (
      tester,
    ) async {
      await _pumpAt(tester, _phone, location: AppRoutes.settings, builder: rtl);

      expect(
        directionOf(tester, find.textContaining('Movies/Fetchr')),
        TextDirection.ltr,
      );
    });

    testWidgets('the save path on the playlist page stays left to right', (
      tester,
    ) async {
      final app = await _pumpAt(tester, _phone, builder: rtl);
      unawaited(app.router.push<int>(AppRoutes.playlist, extra: playlistOf(5)));
      await tester.pumpAndSettle();

      expect(
        directionOf(tester, find.textContaining('Saves to Movies/Fetchr')),
        TextDirection.ltr,
      );
    });

    testWidgets('the path of a finished download stays left to right', (
      tester,
    ) async {
      final app = homeApp();
      stubTasks(app, [doneTask('d')]);
      await _pumpAt(
        tester,
        _phone,
        app: app,
        location: AppRoutes.downloads,
        builder: rtl,
      );

      expect(
        directionOf(tester, find.textContaining('Movies/Fetchr')),
        TextDirection.ltr,
      );
    });
  });

  group('semantics', () {
    // A screen reader speaks the tooltip of an icon-only button.
    void expectNamed(WidgetTester tester, Iterable<String> names) {
      for (final name in names) {
        final tooltip = find.byTooltip(name);
        expect(tooltip, findsAtLeastNWidgets(1), reason: 'no "$name" button');
        final button = find.ancestor(
          of: tooltip.first,
          matching: find.byType(IconButton),
        );
        expect(
          tester.getSemantics(button.first),
          isSemantics(tooltip: name, isButton: true),
          reason: name,
        );
      }
    }

    semanticsTest('Home names Clear URL', (tester) async {
      await _pumpAt(tester, _phone);
      await typeUrl(tester, clipUrl);

      expectNamed(tester, ['Clear URL']);
    });

    semanticsTest('download cards name Pause, Resume, Cancel and Remove', (
      tester,
    ) async {
      final app = homeApp();
      stubTasks(app, [
        runningTask(),
        downloadTask(
          id: 'p',
          status: TaskStatus.paused,
          progress: .4,
          downloadedBytes: 40 * mb,
          totalBytes: 100 * mb,
        ),
        downloadTask(id: 'c', status: TaskStatus.canceled),
      ]);
      await _pumpAt(
        tester,
        const Size(390, 1000),
        app: app,
        location: AppRoutes.downloads,
      );

      expectNamed(tester, [
        'Pause download',
        'Cancel download',
        'Resume download',
        'Remove',
      ]);
    });

    semanticsTest('the download progress exposes 64%', (tester) async {
      final app = homeApp();
      stubTasks(app, [runningTask()]);
      await _pumpAt(tester, _phone, app: app, location: AppRoutes.downloads);

      final bar = tester.getSemantics(find.byType(AppProgressBar));
      expect(bar.value, '64%');
      expect(bar.label, 'Download progress');
    });

    semanticsTest('Library cards name More actions', (tester) async {
      library_harness.setUpLibraryHarness();
      library_harness.stubList(
        () async => Ok([library_harness.clipItem, library_harness.songItem]),
      );
      await library_harness.pumpLibrary(tester);

      expectNamed(tester, ['More actions']);
    });

    semanticsTest('the player names Back, Fullscreen, the skips and Play', (
      tester,
    ) async {
      player_harness.setUpPlayerHarness();
      await player_harness.pumpPlayer(tester, player_harness.videoItem);

      expectNamed(tester, [
        'Back',
        'Fullscreen',
        'Back 10 seconds',
        'Forward 10 seconds',
        'Play',
      ]);

      await player_harness.emit(tester, player_harness.playing, true);

      expectNamed(tester, ['Pause']);
    });
  });
}
