import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/shared/domain/entities/quality.dart';
import 'package:grabby/app/shared/download_prefs_provider.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/core/theme/app_spacing.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/utils/scale.dart';
import 'package:grabby/core/widgets/media_thumb.dart';
import 'package:grabby/core/widgets/segmented_pills.dart';
import 'package:grabby/modules/downloader/domain/entities/media_info.dart';
import 'package:grabby/modules/downloader/presentation/providers/home_notifier.dart';
import 'package:grabby/modules/downloader/presentation/views/playlist_view.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/playlist_rows.dart';

import '../../../../core/widgets/widget_harness.dart';
import '../../../../support/app_fonts.dart';
import '../../../../support/fixtures.dart';
import '../../../../support/mocks.dart';

typedef _Download =
    Future<Result<int>> Function(MediaInfo, Quality, List<int> picked);

class _FakeHome extends HomeNotifier {
  _FakeHome(this._download);

  final _Download _download;

  @override
  Future<Result<int>> downloadPlaylist(
    MediaInfo info,
    Quality quality,
    List<int> picked,
  ) => _download(info, quality, picked);
}

List<PlaylistEntry> _entries(int n) => [
  for (var i = 1; i <= n; i++)
    PlaylistEntry(
      url: 'https://example.com/v/$i',
      title: 'Entry $i',
      durationSec: i * 60,
    ),
];

MediaInfo _playlist({
  int entries = 24,
  String title = 'Coastal road trips',
  List<Quality> qualities = const [
    Quality.best,
    Quality.p1080,
    Quality.p720,
    Quality.p480,
    Quality.mp3,
  ],
}) => mediaInfo(
  url: 'https://www.youtube.com/playlist?list=PL1',
  title: title,
  isPlaylist: true,
  uploader: 'Open Road Films',
  options: formatOptions(qualities),
  entries: _entries(entries),
);

class _Page {
  _Page(this.tester);

  final WidgetTester tester;
  final calls = <(Quality, List<int>)>[];
  int? popped;
  bool closed = false;

  Future<void> open(
    MediaInfo info, {
    _Download? onDownload,
    DownloadPrefs prefs = const DownloadPrefs(),
    ThemeData? theme,
    Size size = designSize,
    TextDirection direction = TextDirection.ltr,
  }) async {
    useView(tester, size);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          homeNotifierProvider.overrideWith(
            () => _FakeHome((info, quality, picked) {
              calls.add((quality, picked));
              return onDownload?.call(info, quality, picked) ??
                  Future.value(Ok(picked.length));
            }),
          ),
          downloadPrefsProvider.overrideWith(() => FixedPrefs(prefs)),
        ],
        child: themed(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                popped = await Navigator.of(context).push<int>(
                  MaterialPageRoute(
                    builder: (_) => Directionality(
                      textDirection: direction,
                      child: PlaylistView(info: info),
                    ),
                  ),
                );
                closed = true;
              },
              child: const Text('open'),
            ),
          ),
          theme: theme,
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> tapText(String text) async {
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }
}

Finder get _downloadButton => find.byType(FilledButton);

bool _downloadEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(_downloadButton).onPressed != null;

Finder get _selectAll =>
    find.ancestor(of: find.text('Select all'), matching: find.byType(InkWell));

bool _selectAllChecked(WidgetTester tester) => tester
    .widget<Checkbox>(
      find.descendant(of: _selectAll, matching: find.byType(Checkbox)),
    )
    .value!;

Finder _row(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(InkWell));

bool _ticked(WidgetTester tester, String title) => tester
    .widget<Checkbox>(
      find.descendant(of: _row(title), matching: find.byType(Checkbox)),
    )
    .value!;

double _titleOpacity(WidgetTester tester, String title) => tester
    .widget<Opacity>(
      find.ancestor(of: find.text(title), matching: find.byType(Opacity)).first,
    )
    .opacity;

void main() {
  group('header', () {
    testWidgets('shows the title, the site and the real count', (tester) async {
      await _Page(tester).open(_playlist());

      expect(find.text('Playlist'), findsOneWidget);
      expect(find.text('youtube.com · 24 videos'), findsOneWidget);
      expect(find.text('Coastal road trips'), findsOneWidget);
    });

    testWidgets(
      'reads the site and count left to right in a right-to-left app',
      (tester) async {
        await _Page(tester).open(_playlist(), direction: TextDirection.rtl);

        final line = find.text('youtube.com · 24 videos');
        expect(Directionality.of(tester.element(line)), TextDirection.rtl);
        expect(directionOf(tester, line), TextDirection.ltr);
      },
    );

    testWidgets('says "1 video" for a one-entry playlist', (tester) async {
      await _Page(tester).open(_playlist(entries: 1));

      expect(find.text('youtube.com · 1 video'), findsOneWidget);
      expect(find.text('1 of 1 selected'), findsOneWidget);
      expect(find.text('Download 1 video'), findsOneWidget);
    });

    testWidgets('clips a long title at two lines', (tester) async {
      await _Page(tester).open(_playlist(title: 'A very long title ' * 20));

      final title = tester.widget<Text>(
        find.textContaining('A very long title').first,
      );
      expect(title.maxLines, 2);
      expect(title.overflow, TextOverflow.ellipsis);
    });

    testWidgets('the back button leaves with no result', (tester) async {
      final page = _Page(tester);
      await page.open(_playlist());

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(page.closed, isTrue);
      expect(page.popped, isNull);
      expect(find.byType(PlaylistView), findsNothing);
    });
  });

  group('quality pills', () {
    SegmentedPills<Quality> pills(WidgetTester tester) => tester
        .widget<SegmentedPills<Quality>>(find.byType(SegmentedPills<Quality>));

    testWidgets('offer every quality the playlist lists', (tester) async {
      await _Page(tester).open(_playlist());

      expect(
        [for (final (_, label) in pills(tester).items) label],
        ['Best', '1080p', '720p', '480p', 'MP3'],
      );
    });

    testWidgets('follow the design for the track', (tester) async {
      await _Page(tester).open(_playlist(), theme: AppTheme.dark());

      final widget = pills(tester);
      expect(widget.height, 44);
      expect(widget.trackRadius, Radii.row);
      expect(widget.pillRadius, Radii.thumb);
      expect(widget.mono, isTrue);
      expect(
        widget.trackColor,
        AppTheme.dark().extension<AppTokens>()!.surface,
      );
    });

    testWidgets('start on the Settings default when the source offers it', (
      tester,
    ) async {
      await _Page(
        tester,
      ).open(_playlist(), prefs: const DownloadPrefs(quality: Quality.p480));

      expect(pills(tester).selected, Quality.p480);
    });

    testWidgets('start on the first one when it does not', (tester) async {
      await _Page(tester).open(
        _playlist(qualities: const [Quality.p720, Quality.mp3]),
        prefs: const DownloadPrefs(quality: Quality.p1080),
      );

      expect(pills(tester).selected, Quality.p720);
    });

    testWidgets('a tap changes the quality that is enqueued', (tester) async {
      final page = _Page(tester);
      await page.open(_playlist());

      await page.tapText('720p');
      await page.tapText('Download 24 videos');

      expect(page.calls.single.$1, Quality.p720);
      expect(page.calls.single.$2, List.generate(24, (i) => i));
    });
  });

  group('selection', () {
    testWidgets('starts with every entry ticked', (tester) async {
      await _Page(tester).open(_playlist());

      expect(find.text('24 of 24 selected'), findsOneWidget);
      expect(find.text('Download 24 videos'), findsOneWidget);
      expect(_selectAllChecked(tester), isTrue);
      expect(_ticked(tester, 'Entry 1'), isTrue);
      expect(_titleOpacity(tester, 'Entry 1'), 1);
    });

    testWidgets('unticking an entry dims its title and updates the counts', (
      tester,
    ) async {
      final page = _Page(tester);
      await page.open(_playlist());

      await page.tapText('Entry 2');

      expect(_ticked(tester, 'Entry 2'), isFalse);
      expect(_titleOpacity(tester, 'Entry 2'), 0.55);
      expect(_titleOpacity(tester, 'Entry 1'), 1);
      expect(find.text('23 of 24 selected'), findsOneWidget);
      expect(find.text('Download 23 videos'), findsOneWidget);
      expect(
        _selectAllChecked(tester),
        isFalse,
        reason: 'only checked when all are',
      );
    });

    testWidgets('a second tap ticks the entry again', (tester) async {
      final page = _Page(tester);
      await page.open(_playlist());

      await page.tapText('Entry 2');
      await page.tapText('Entry 2');

      expect(_ticked(tester, 'Entry 2'), isTrue);
      expect(find.text('24 of 24 selected'), findsOneWidget);
    });

    testWidgets('Select all unticks everything, then ticks everything', (
      tester,
    ) async {
      final page = _Page(tester);
      await page.open(_playlist());

      await page.tapText('Select all');

      expect(find.text('0 of 24 selected'), findsOneWidget);
      expect(_selectAllChecked(tester), isFalse);
      expect(_ticked(tester, 'Entry 1'), isFalse);

      await page.tapText('Select all');

      expect(find.text('24 of 24 selected'), findsOneWidget);
      expect(_selectAllChecked(tester), isTrue);
      expect(_ticked(tester, 'Entry 1'), isTrue);
    });

    testWidgets('Select all from a partial selection ticks everything', (
      tester,
    ) async {
      final page = _Page(tester);
      await page.open(_playlist());

      await page.tapText('Entry 3');
      await page.tapText('Select all');

      expect(find.text('24 of 24 selected'), findsOneWidget);
    });

    testWidgets('the whole Select all row is the tap target', (tester) async {
      final page = _Page(tester);
      await page.open(_playlist());

      await page.tapText('24 of 24 selected');

      expect(find.text('0 of 24 selected'), findsOneWidget);
    });

    testWidgets('the whole entry row is the tap target', (tester) async {
      final page = _Page(tester);
      await page.open(_playlist());

      await page.tapText('1:00');

      expect(_ticked(tester, 'Entry 1'), isFalse);
    });

    testWidgets('each row exposes a checkbox with its title and duration', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _Page(tester).open(_playlist());

      expect(
        tester.getSemantics(_row('Entry 1')),
        matchesSemantics(
          label: 'Entry 1, 1:00',
          hasCheckedState: true,
          isChecked: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(_selectAll),
        matchesSemantics(
          label: 'Select all',
          value: '24 of 24 selected',
          hasCheckedState: true,
          isChecked: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });
  });

  group('download bar', () {
    testWidgets('says where the videos go', (tester) async {
      await _Page(
        tester,
      ).open(_playlist(), prefs: const DownloadPrefs(folder: 'Trips'));

      expect(find.text('Saves to Movies/Trips'), findsOneWidget);
    });

    testWidgets('forces the save path to read left to right', (tester) async {
      await _Page(tester).open(_playlist());

      expect(
        tester.widget<Text>(find.text('Saves to Movies/Fetchr')).textDirection,
        TextDirection.ltr,
      );
    });

    testWidgets('says Music for MP3', (tester) async {
      final page = _Page(tester);
      await page.open(_playlist(), prefs: const DownloadPrefs(folder: 'Trips'));

      await page.tapText('MP3');

      expect(find.text('Saves to Music/Trips'), findsOneWidget);
    });

    for (final MapEntry(key: mode, value: theme) in themes.entries) {
      testWidgets('sits on the nav bar colour with a divider on top in $mode', (
        tester,
      ) async {
        await _Page(tester).open(_playlist(), theme: theme);
        final tokens = theme.extension<AppTokens>()!;

        final bar = tester.widget<DecoratedBox>(
          find
              .ancestor(
                of: find.text('Saves to Movies/Fetchr'),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        final decoration = bar.decoration as BoxDecoration;
        expect(decoration.color, tokens.navBar);
        expect((decoration.border! as Border).top.color, tokens.divider);
      });
    }

    testWidgets('0 selected disables Download', (tester) async {
      final page = _Page(tester);
      await page.open(_playlist());
      expect(_downloadEnabled(tester), isTrue);

      await page.tapText('Select all');

      expect(find.text('Download 0 videos'), findsOneWidget);
      expect(_downloadEnabled(tester), isFalse);

      await tester.tap(_downloadButton, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(page.calls, isEmpty);
    });
  });

  group('downloading', () {
    testWidgets('sends the ticked entries, ascending and 0-based', (
      tester,
    ) async {
      final page = _Page(tester);
      await page.open(_playlist(entries: 18));

      await page.tapText('Select all');
      await page.tapText('Entry 1');
      await page.tapText('Entry 3');
      await page.tapText('Download 2 videos');

      expect(page.calls.single.$1, Quality.best);
      expect(page.calls.single.$2, [0, 2]);
    });

    testWidgets('an Ok pops the number that was started', (tester) async {
      final page = _Page(tester);
      await page.open(_playlist(entries: 18));

      await page.tapText('Select all');
      await page.tapText('Entry 1');
      await page.tapText('Entry 3');
      await page.tapText('Download 2 videos');

      expect(page.closed, isTrue);
      expect(page.popped, 2);
      expect(find.byType(PlaylistView), findsNothing);
    });

    testWidgets('an Err shows the failure and stays on the page', (
      tester,
    ) async {
      final page = _Page(tester);
      await page.open(
        _playlist(),
        onDownload: (_, _, _) async => const Err(StorageFailure()),
      );

      await page.tapText('Download 24 videos');

      expect(find.text(const StorageFailure().message), findsOneWidget);
      expect(find.byType(PlaylistView), findsOneWidget);
      expect(page.closed, isFalse);
      expect(_downloadEnabled(tester), isTrue, reason: 'it can be retried');
    });

    testWidgets('a retry after an Err can still succeed', (tester) async {
      final page = _Page(tester);
      var attempts = 0;
      await page.open(
        _playlist(),
        onDownload: (_, _, picked) async =>
            ++attempts == 1 ? const Err(StorageFailure()) : Ok(picked.length),
      );

      await page.tapText('Download 24 videos');
      await page.tapText('Download 24 videos');

      expect(page.popped, 24);
    });

    testWidgets('is disabled while the enqueue runs', (tester) async {
      final page = _Page(tester);
      final pending = Completer<Result<int>>();
      await page.open(_playlist(), onDownload: (_, _, _) => pending.future);

      await tester.tap(_downloadButton);
      await tester.pump();

      expect(_downloadEnabled(tester), isFalse);
      expect(page.closed, isFalse);

      pending.complete(const Ok(24));
      await tester.pumpAndSettle();

      expect(page.popped, 24);
    });

    testWidgets('a double tap enqueues once', (tester) async {
      final page = _Page(tester);
      final pending = Completer<Result<int>>();
      await page.open(_playlist(), onDownload: (_, _, _) => pending.future);

      await tester.tap(_downloadButton);
      await tester.tap(_downloadButton);
      await tester.pump();

      expect(page.calls, hasLength(1));

      pending.complete(const Ok(24));
      await tester.pumpAndSettle();
    });
  });

  group('a long playlist', () {
    testWidgets('builds its rows lazily', (tester) async {
      await _Page(tester).open(_playlist(entries: 500));

      expect(find.text('500 of 500 selected'), findsOneWidget);
      expect(find.text('youtube.com · 500 videos'), findsOneWidget);
      final built = tester.widgetList(find.byType(MediaThumb)).length;
      expect(built, lessThan(30));
      expect(find.text('Entry 500'), findsNothing);
    });

    testWidgets('Select all covers entries that were never built', (
      tester,
    ) async {
      final page = _Page(tester);
      await page.open(_playlist(entries: 500));

      await page.tapText('Entry 1');
      await page.tapText('Select all');
      await page.tapText('Download 500 videos');

      expect(page.calls.single.$2, hasLength(500));
      expect(page.popped, 500);
    });

    testWidgets('scrolls to the last entry', (tester) async {
      await _Page(tester).open(_playlist(entries: 500));

      await tester.dragUntilVisible(
        find.text('Entry 500'),
        find.byType(CustomScrollView),
        const Offset(0, -400),
        maxIteration: 200,
      );

      expect(find.text('Entry 500'), findsOneWidget);
      expect(find.text('500'), findsOneWidget);
    });

    testWidgets('keeps the numbers in a column wide enough for three digits', (
      tester,
    ) async {
      await _Page(tester).open(_playlist(entries: 120));

      final one = tester.getRect(find.text('1').first);
      final two = tester.getRect(find.text('2').first);
      expect(one.right, two.right);
      expect(tester.takeException(), isNull);
    });
  });

  group('rows', () {
    testWidgets('number each entry and show its duration', (tester) async {
      await _Page(tester).open(_playlist(entries: 3));

      expect(find.text('1'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('1:00'), findsOneWidget);
      expect(find.text('3:00'), findsOneWidget);
    });

    testWidgets('hide the duration when it is unknown', (tester) async {
      await _Page(tester).open(
        mediaInfo(
          url: 'https://example.com/list',
          title: 'No times',
          isPlaylist: true,
          options: formatOptions(const [Quality.best]),
          entries: const [
            PlaylistEntry(url: 'https://example.com/1', title: 'Untimed'),
          ],
        ),
      );

      expect(find.text('Untimed'), findsOneWidget);
      expect(find.text('0:00'), findsNothing);
    });

    testWidgets('use a 64 by 38 thumbnail', (tester) async {
      await _Page(tester).open(_playlist(entries: 2));

      final size = tester.getSize(find.byType(MediaThumb).first);
      expect(size.width, 64);
      expect(size.height, 38);
    });

    testWidgets('are at least 62 high and clip a long title', (tester) async {
      await _Page(tester).open(
        mediaInfo(
          url: 'https://example.com/list',
          title: 'Long',
          isPlaylist: true,
          options: formatOptions(const [Quality.best]),
          entries: [
            PlaylistEntry(
              url: 'https://example.com/1',
              title: 'A very long entry title ' * 10,
              durationSec: 5,
            ),
          ],
        ),
      );

      final row = find.ancestor(
        of: find.textContaining('A very long entry title'),
        matching: find.byType(InkWell),
      );
      expect(tester.getSize(row).height, greaterThanOrEqualTo(62));
      final title = tester.widget<Text>(
        find.textContaining('A very long entry title'),
      );
      expect(title.maxLines, 1);
    });
  });

  // Real fonts, loaded here so the groups above keep the test font.
  group('on a small or short window at the largest text', () {
    setUpAll(loadAppFonts);

    for (final (name, size) in [
      ('320x640', const Size(320, 640)),
      ('844x390', const Size(844, 390)),
    ]) {
      testWidgets('a long title does not overflow at $name', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _Page(tester).open(
          _playlist(entries: 30, title: 'A very long title ' * 20),
          size: size,
        );

        expect(tester.takeException(), isNull);
        expect(find.byTooltip('Back'), findsOneWidget);
        expect(find.text('Select all'), findsOneWidget);
        expect(_downloadButton, findsOneWidget);
        // The header scrolls with the list, so every entry stays reachable.
        await tester.dragUntilVisible(
          find.text('Entry 30'),
          find.byType(CustomScrollView),
          const Offset(0, -150),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('on a wide window', () {
    testWidgets('caps the rows and the Download button at 560, centred', (
      tester,
    ) async {
      await _Page(tester).open(_playlist(), size: const Size(700, 1000));

      for (final finder in [
        find.byType(PlaylistEntryRow).first,
        _downloadButton,
      ]) {
        final rect = tester.getRect(finder);
        expect(rect.width, lessThanOrEqualTo(560));
        expect(rect.left, closeTo(700 - rect.right, 1));
      }
    });

    testWidgets('keeps the bar as tall as its content, edge to edge', (
      tester,
    ) async {
      await _Page(tester).open(_playlist(), size: const Size(700, 1000));

      final bar = tester.getSize(find.byType(PlaylistBottomBar));
      expect(bar.width, 700);
      expect(bar.height, lessThan(300));
    });
  });

  testWidgets('an empty playlist has nothing to download', (tester) async {
    await _Page(tester).open(_playlist(entries: 0));

    expect(find.text('0 of 0 selected'), findsOneWidget);
    expect(find.text('Download 0 videos'), findsOneWidget);
    expect(_downloadEnabled(tester), isFalse);
    expect(_selectAllChecked(tester), isFalse);
  });
}
