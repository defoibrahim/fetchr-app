import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/utils/scale.dart';
import 'package:grabby/core/widgets/media_thumb.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/media_row.dart';

import '../../../../../core/widgets/widget_harness.dart';

void main() {
  group('MediaRow', () {
    for (final MapEntry(key: mode, value: theme) in themes.entries) {
      final tokens = theme.extension<AppTokens>()!;

      Future<void> pump(WidgetTester tester, Widget row) async {
        useView(tester);
        await tester.pumpWidget(
          themed(
            Align(alignment: Alignment.topLeft, child: row),
            theme: theme,
          ),
        );
      }

      testWidgets('$mode: 64 high, an 84 x 48 thumb, the title and meta', (
        tester,
      ) async {
        await pump(
          tester,
          MediaRow(
            title: 'Desert drive at golden hour',
            meta: '1080p · MP4 · 184 MB',
            duration: '12:48',
            onTap: () {},
          ),
        );

        expect(tester.getSize(find.byType(MediaRow)).height, 64.h);
        expect(tester.getSize(find.byType(MediaThumb)), Size(84.w, 48.h));
        expect(find.text('Desert drive at golden hour'), findsOneWidget);
        expect(find.text('1080p · MP4 · 184 MB'), findsOneWidget);
        expect(find.text('12:48'), findsOneWidget);
        final meta = tester.widget<Text>(find.text('1080p · MP4 · 184 MB'));
        expect(meta.style!.color, tokens.textMuted);
        expect(meta.style!.fontSize, 11);
      });

      testWidgets('$mode: the title keeps to one line with an ellipsis', (
        tester,
      ) async {
        await pump(
          tester,
          SizedBox(
            width: 320,
            child: MediaRow(
              title: 'A very long title ' * 12,
              meta: '720p · MP4',
              onTap: () {},
            ),
          ),
        );

        final title = tester.widget<Text>(find.textContaining('A very long'));
        expect(title.maxLines, 1);
        expect(title.overflow, TextOverflow.ellipsis);
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(MediaRow)).height, 64.h);
      });

      testWidgets('$mode: right to left mirrors the row, not the meta', (
        tester,
      ) async {
        await pump(
          tester,
          Directionality(
            textDirection: TextDirection.rtl,
            child: SizedBox(
              width: 320,
              child: MediaRow(
                title: 'Clip',
                meta: '1080p · MP4 · 184 MB',
                onTap: () {},
              ),
            ),
          ),
        );

        expect(
          tester.getCenter(find.byType(MediaThumb)).dx,
          greaterThan(tester.getCenter(find.text('Clip')).dx),
        );
        expect(
          tester.widget<Text>(find.text('1080p · MP4 · 184 MB')).textDirection,
          TextDirection.ltr,
        );
      });

      testWidgets('$mode: audio draws the audio tile with no duration badge', (
        tester,
      ) async {
        await pump(
          tester,
          MediaRow(
            title: 'Late-night lo-fi set, part 3',
            meta: 'Audio · MP3 · 6.2 MB',
            isAudio: true,
            onTap: () {},
          ),
        );

        expect(
          tester.widget<MediaThumb>(find.byType(MediaThumb)).isAudio,
          true,
        );
      });

      testWidgets('$mode: a tap anywhere on the row calls onTap', (
        tester,
      ) async {
        var taps = 0;
        await pump(
          tester,
          MediaRow(title: 'Clip', meta: '720p', onTap: () => taps++),
        );

        await tester.tap(find.text('Clip'));
        await tester.tap(find.byType(MediaThumb));
        expect(taps, 2);
      });
    }
  });
}
