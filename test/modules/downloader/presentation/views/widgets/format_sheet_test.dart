import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/shared/domain/entities/quality.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/utils/scale.dart';
import 'package:grabby/core/utils/widget_utils.dart';
import 'package:grabby/core/widgets/app_progress_bar.dart';
import 'package:grabby/core/widgets/media_thumb.dart';
import 'package:grabby/core/widgets/stripes.dart';
import 'package:grabby/modules/downloader/domain/entities/format_option.dart';
import 'package:grabby/modules/downloader/domain/entities/media_info.dart';
import 'package:grabby/modules/downloader/presentation/providers/home_notifier.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/format_sheet.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/quality_option.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../../../../core/widgets/widget_harness.dart';
import '../../../../../support/fixtures.dart';

const _best = FormatOption(
  quality: Quality.best,
  width: 3840,
  height: 2160,
  sizeBytes: 1200 * mb,
  sizeIsEstimate: true,
);
const _hd = FormatOption(
  quality: Quality.p1080,
  width: 1920,
  height: 1080,
  fps: 60,
  sizeBytes: 184 * mb,
  sizeIsEstimate: true,
);
const _mid = FormatOption(
  quality: Quality.p720,
  width: 1280,
  height: 720,
  fps: 30,
  sizeBytes: 96 * mb,
);
const _sd = FormatOption(quality: Quality.p480);
const _audio = FormatOption(
  quality: Quality.mp3,
  sizeBytes: 11 * mb,
  sizeIsEstimate: true,
);
const _cover = FormatOption(quality: Quality.cover, width: 1280, height: 720);

final _video = mediaInfo(
  url: 'https://www.youtube.com/watch?v=Qx7mT0aK3pE',
  title: 'Desert drive at golden hour',
  uploader: 'Open Road Films',
  durationSec: 768,
  options: const [_best, _hd, _mid, _sd, _audio, _cover],
);

class _FakeHome extends HomeNotifier {
  _FakeHome(this._state);

  final FutureOr<MediaInfo?> _state;

  @override
  FutureOr<MediaInfo?> build() => _state;
}

class _Opener {
  _Opener(this.tester);

  final WidgetTester tester;
  Quality? chosen;
  bool closed = false;

  Future<void> open(
    FutureOr<MediaInfo?> state, {
    Quality initial = Quality.p1080,
    Quality? preselect,
    ThemeData? theme,
    Size size = designSize,
    bool settle = true,
  }) async {
    useView(tester, size);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [homeNotifierProvider.overrideWith(() => _FakeHome(state))],
        child: themed(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                chosen = await showAppBottomSheet<Quality>(
                  context,
                  child: FormatSheet(
                    initialQuality: initial,
                    preselect: preselect,
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
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      // The shimmer never settles: wait out the sheet's entrance instead.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }
  }

  Future<void> tapRow(String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> tapDownload() async {
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
  }
}

Finder _row(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(QualityOption));

Finder _inRow(String label, Finder matching) =>
    find.descendant(of: _row(label), matching: matching);

bool _selected(WidgetTester tester, String label) =>
    tester
        .widget<RadioGroup<Quality>>(
          _inRow(label, find.byType(RadioGroup<Quality>)),
        )
        .groupValue !=
    null;

Material _material(WidgetTester tester, String label) =>
    tester.widget<Material>(_inRow(label, find.byType(Material)).first);

FilledButton _download(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byType(FilledButton));

// `Skeletonizer()` builds a private subclass, which `find.byType` misses.
Skeletonizer _skeleton(WidgetTester tester) => tester.widget<Skeletonizer>(
  find.byWidgetPredicate((w) => w is Skeletonizer),
);

void main() {
  // The shimmer and the sliding bar never settle; reduced motion holds both.
  group('loading', () {
    testWidgets('draws the sheet as a skeleton under a sliding bar, with '
        'Download disabled', (tester) async {
      reduceMotion(tester);
      await _Opener(tester).open(Completer<MediaInfo?>().future);

      expect(_skeleton(tester).enabled, isTrue);
      final rows = tester.widgetList<QualityOption>(find.byType(QualityOption));
      expect(rows, hasLength(5), reason: 'placeholder rows under bones');
      expect(rows.where((r) => r.selected), isEmpty);
      expect(
        tester.widget<AppProgressBar>(find.byType(AppProgressBar)).value,
        isNull,
      );
      expect(find.text('QUALITY'), findsOneWidget);
      expect(find.text('Sizes are estimates'), findsNothing);
      expect(find.text('Download'), findsOneWidget);
      expect(_download(tester).onPressed, isNull);
    });

    testWidgets('shimmers, and holds still when motion is reduced', (
      tester,
    ) async {
      await _Opener(tester).open(Completer<MediaInfo?>().future, settle: false);
      expect(_skeleton(tester).effect, isA<ShimmerEffect>());

      reduceMotion(tester);
      await tester.pumpAndSettle();
      expect(_skeleton(tester).effect, isA<SolidColorEffect>());
    });

    testWidgets('Cancel still closes it', (tester) async {
      reduceMotion(tester);
      final opener = _Opener(tester);
      await opener.open(Completer<MediaInfo?>().future);

      await opener.tapRow('Cancel');

      expect(opener.closed, isTrue);
      expect(opener.chosen, isNull);
    });

    testWidgets('swaps in the rows when the video arrives', (tester) async {
      reduceMotion(tester);
      final fetched = Completer<MediaInfo?>();
      await _Opener(tester).open(fetched.future);
      expect(_skeleton(tester).enabled, isTrue);

      fetched.complete(_video);
      await tester.pumpAndSettle();

      expect(_skeleton(tester).enabled, isFalse);
      expect(find.byType(AppProgressBar), findsNothing);
      expect(find.byType(QualityOption), findsNWidgets(6));
      expect(find.byType(Stripes), findsOneWidget);
      expect(_download(tester).onPressed, isNotNull);
    });

    testWidgets('a playlist is not this sheet\'s to show', (tester) async {
      reduceMotion(tester);
      await _Opener(
        tester,
      ).open(mediaInfo(isPlaylist: true, options: const [_best]));

      expect(_skeleton(tester).enabled, isTrue);
      expect(_download(tester).onPressed, isNull);
    });
  });

  group('loaded', () {
    testWidgets('lists one row per option, in order', (tester) async {
      await _Opener(tester).open(_video);

      expect(find.byType(QualityOption), findsNWidgets(6));
      final labels = [
        for (final row in tester.widgetList<QualityOption>(
          find.byType(QualityOption),
        ))
          row.option.quality,
      ];
      expect(labels, Quality.values);
      for (final label in [
        'Best available',
        '1080p',
        '720p',
        '480p',
        'Audio only',
        'Cover photo',
      ]) {
        expect(_row(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('shows the title, the site and uploader, and the duration', (
      tester,
    ) async {
      await _Opener(tester).open(_video);

      expect(find.text('Desert drive at golden hour'), findsOneWidget);
      expect(find.text('youtube.com · Open Road Films'), findsOneWidget);
      expect(find.text('12:48'), findsOneWidget);
    });

    testWidgets('leaves the uploader out when there is none', (tester) async {
      await _Opener(
        tester,
      ).open(mediaInfo(url: 'https://example.com/v', options: const [_hd]));

      expect(find.text('example.com'), findsOneWidget);
    });

    testWidgets('shows a LIVE badge for a live stream', (tester) async {
      await _Opener(tester).open(mediaInfo(isLive: true, options: const [_hd]));

      expect(find.text('LIVE'), findsOneWidget);
    });

    testWidgets('has no LIVE badge for a video', (tester) async {
      await _Opener(tester).open(_video);

      expect(find.text('LIVE'), findsNothing);
    });

    testWidgets('puts the thumbnail in the full-width media thumb', (
      tester,
    ) async {
      await _Opener(tester).open(
        mediaInfo(thumbnail: 'https://example.com/t.jpg', options: const [_hd]),
      );

      final thumb = tester.widget<MediaThumb>(find.byType(MediaThumb));
      expect(thumb.image, const NetworkImage('https://example.com/t.jpg'));
      expect(thumb.width, double.infinity);
      expect(tester.getSize(find.byType(MediaThumb)).height, 196);
    });

    testWidgets('shows each row\'s detail and size', (tester) async {
      await _Opener(tester).open(_video);

      expect(
        _inRow('Best available', find.text('2160p · 3840×2160')),
        findsOne,
      );
      expect(_inRow('Best available', find.text('~1.2 GB')), findsOneWidget);
      expect(
        _inRow('1080p', find.text('MP4 · 1920×1080 · 60 fps')),
        findsOneWidget,
      );
      expect(_inRow('720p', find.text('MP4 · 1280×720 · 30 fps')), findsOne);
      expect(_inRow('480p', find.text('MP4 · data saver')), findsOneWidget);
      expect(_inRow('480p', find.text('size unknown')), findsOneWidget);
      expect(
        _inRow('Audio only', find.text('MP3 · best quality (VBR)')),
        findsOneWidget,
      );
      expect(_inRow('Cover photo', find.text('JPEG · 1280×720')), findsOne);
    });

    testWidgets('notes that sizes are estimates when one is', (tester) async {
      await _Opener(tester).open(_video);

      expect(find.text('Sizes are estimates'), findsOneWidget);
    });

    testWidgets('leaves the note out when every size is exact', (tester) async {
      await _Opener(tester).open(mediaInfo(options: const [_mid, _sd]));

      expect(find.text('Sizes are estimates'), findsNothing);
    });

    testWidgets('keeps the video while Home clears the fetch', (tester) async {
      await _Opener(tester).open(_video);

      ProviderScope.containerOf(
        tester.element(find.byType(FormatSheet)),
      ).read(homeNotifierProvider.notifier).clear();
      await tester.pump();

      expect(find.byType(QualityOption), findsNWidgets(6));
      expect(find.text('Desert drive at golden hour'), findsOneWidget);
    });
  });

  group('selection', () {
    testWidgets('preselects the Settings default', (tester) async {
      await _Opener(tester).open(_video, initial: Quality.p720);

      expect(_selected(tester, '720p'), isTrue);
      expect(_selected(tester, '1080p'), isFalse);
      expect(find.text('Download 720p'), findsOneWidget);
    });

    testWidgets('a 720p-only source preselects its first option', (
      tester,
    ) async {
      await _Opener(
        tester,
      ).open(mediaInfo(options: const [_mid, _audio]), initial: Quality.p1080);

      expect(_selected(tester, '720p'), isTrue);
      expect(_selected(tester, 'Audio only'), isFalse);
      expect(find.text('Download 720p'), findsOneWidget);
    });

    testWidgets('preselect wins over the default when the source has it', (
      tester,
    ) async {
      await _Opener(
        tester,
      ).open(_video, initial: Quality.p1080, preselect: Quality.p480);

      expect(_selected(tester, '480p'), isTrue);
      expect(_selected(tester, '1080p'), isFalse);
      expect(find.text('Download 480p'), findsOneWidget);
    });

    testWidgets('a preselect the source lacks falls back to the default', (
      tester,
    ) async {
      await _Opener(tester).open(
        mediaInfo(options: const [_hd, _mid]),
        initial: Quality.p720,
        preselect: Quality.p480,
      );

      expect(_selected(tester, '720p'), isTrue);
    });

    testWidgets('a row tap selects it and relabels the button', (tester) async {
      final opener = _Opener(tester);
      await opener.open(_video);
      expect(find.text('Download 1080p'), findsOneWidget);

      await opener.tapRow('720p');

      expect(_selected(tester, '720p'), isTrue);
      expect(_selected(tester, '1080p'), isFalse);
      expect(find.text('Download 720p'), findsOneWidget);
      expect(find.text('Download 1080p'), findsNothing);
    });

    testWidgets('tapping the detail text selects the row too', (tester) async {
      final opener = _Opener(tester);
      await opener.open(_video);

      await opener.tapRow('MP4 · 1280×720 · 30 fps');

      expect(_selected(tester, '720p'), isTrue);
    });

    testWidgets('names best, MP3 and cover the way the design does', (
      tester,
    ) async {
      final opener = _Opener(tester);
      await opener.open(_video);

      await opener.tapRow('Best available');
      expect(find.text('Download best'), findsOneWidget);
      await opener.tapRow('Audio only');
      expect(find.text('Download MP3'), findsOneWidget);
      await opener.tapRow('Cover photo');
      expect(find.text('Download cover'), findsOneWidget);
    });

    testWidgets('exposes each row as one radio of a group', (tester) async {
      final handle = tester.ensureSemantics();
      await _Opener(tester).open(_video);

      expect(
        tester.getSemantics(_row('1080p')),
        matchesSemantics(
          label: '1080p, MP4 · 1920×1080 · 60 fps, ~184 MB',
          hasCheckedState: true,
          isChecked: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(_row('720p')),
        matchesSemantics(
          label: '720p, MP4 · 1280×720 · 30 fps, 96 MB',
          hasCheckedState: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });
  });

  group('closing', () {
    testWidgets('Cancel pops null', (tester) async {
      final opener = _Opener(tester);
      await opener.open(_video);

      await opener.tapRow('Cancel');

      expect(opener.closed, isTrue);
      expect(opener.chosen, isNull);
    });

    testWidgets('a tap on the scrim pops null', (tester) async {
      final opener = _Opener(tester);
      await opener.open(_video);

      await tester.tapAt(const Offset(187, 20));
      await tester.pumpAndSettle();

      expect(opener.closed, isTrue);
      expect(opener.chosen, isNull);
      expect(find.byType(FormatSheet), findsNothing);
    });

    testWidgets('Download pops the preselected quality', (tester) async {
      final opener = _Opener(tester);
      await opener.open(_video);

      await opener.tapDownload();

      expect(opener.chosen, Quality.p1080);
    });

    testWidgets('Download pops the quality that was tapped', (tester) async {
      final opener = _Opener(tester);
      await opener.open(_video);

      await opener.tapRow('Audio only');
      await opener.tapDownload();

      expect(opener.chosen, Quality.mp3);
    });

    testWidgets('a row tap alone does not close the sheet', (tester) async {
      final opener = _Opener(tester);
      await opener.open(_video);

      await opener.tapRow('480p');

      expect(opener.closed, isFalse);
      expect(find.byType(FormatSheet), findsOneWidget);
    });

    testWidgets('the cover row downloads the cover', (tester) async {
      final opener = _Opener(tester);
      await opener.open(_video);

      await opener.tapRow('Cover photo');
      await opener.tapDownload();

      expect(opener.chosen, Quality.cover);
    });
  });

  for (final MapEntry(key: mode, value: theme) in themes.entries) {
    group('the rows in $mode', () {
      final tokens = theme.extension<AppTokens>()!;
      final scheme = theme.colorScheme;

      testWidgets('a selected row has a primary border and the accent tint', (
        tester,
      ) async {
        await _Opener(tester).open(_video, theme: theme);

        final material = _material(tester, '1080p');
        final side = (material.shape! as RoundedRectangleBorder).side;
        expect(material.color, tokens.accentTint);
        expect(side.color, scheme.primary);
        expect(side.width, 1.5);
      });

      testWidgets('an unselected row has a plain border and no fill', (
        tester,
      ) async {
        await _Opener(tester).open(_video, theme: theme);

        final material = _material(tester, '720p');
        final side = (material.shape! as RoundedRectangleBorder).side;
        expect(material.color!.a, 0);
        expect(side.color, tokens.border);
        expect(side.width, 1.5);
      });

      testWidgets('a row is at least 50 high and fills the width', (
        tester,
      ) async {
        await _Opener(tester).open(_video, theme: theme);

        final size = tester.getSize(_row('1080p'));
        expect(size.height, greaterThanOrEqualTo(50));
        expect(size.width, 375 - 2 * 20);
      });
    });
  }

  group('in a dialog', () {
    const window = Size(700, 1000);
    final surface = find
        .descendant(of: find.byType(Dialog), matching: find.byType(Material))
        .first;

    testWidgets('hugs the content instead of standing 88% tall', (
      tester,
    ) async {
      await _Opener(
        tester,
      ).open(mediaInfo(options: const [_hd, _mid]), size: window);

      expect(find.byType(Dialog), findsOneWidget);
      expect(tester.getSize(surface).width, closeTo(480, 1));
      expect(tester.getSize(surface).height, lessThan(window.height * .6));
      expect(find.text('Download 1080p'), findsOneWidget);
    });

    testWidgets('scrolls the body and keeps Cancel and Download in view', (
      tester,
    ) async {
      // 480 high is the shortest window that still opens a dialog.
      await _Opener(tester).open(_video, size: const Size(700, 480));

      expect(find.byType(Dialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (final label in ['Cancel', 'Download 1080p']) {
        final rect = tester.getRect(find.text(label));
        expect(rect.bottom, lessThanOrEqualTo(480), reason: label);
      }
      expect(tester.getSize(surface).height, lessThanOrEqualTo(480 * .88));
    });
  });

  group('in a bottom sheet', () {
    testWidgets('is as tall with the video as it was while loading', (
      tester,
    ) async {
      reduceMotion(tester);
      final fetched = Completer<MediaInfo?>();
      await _Opener(tester).open(fetched.future);
      final loading = tester.getSize(find.byType(FormatSheet)).height;

      fetched.complete(mediaInfo(options: const [_hd, _mid]));
      await tester.pumpAndSettle();

      expect(tester.getSize(find.byType(FormatSheet)).height, loading);
    });
  });

  testWidgets('the text scale grows a row instead of clipping it', (
    tester,
  ) async {
    final opener = _Opener(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await opener.open(_video);

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(_row('1080p')).height,
      greaterThan(50),
      reason: 'two text lines no longer fit in 50',
    );
  });
}
