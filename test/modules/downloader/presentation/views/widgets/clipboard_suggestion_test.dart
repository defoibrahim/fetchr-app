import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/utils/scale.dart';
import 'package:grabby/core/widgets/dashed_border.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/clipboard_suggestion.dart';

import '../../../../../core/widgets/widget_harness.dart';

const _url = 'https://youtube.com/watch?v=Qx7mT0aK3pE';
const _caption = 'Link found on your clipboard';

void main() {
  for (final MapEntry(key: mode, value: theme) in themes.entries) {
    final tokens = theme.extension<AppTokens>()!;

    Future<void> pump(
      WidgetTester tester,
      String? url, {
      VoidCallback? onUse,
    }) async {
      useView(tester);
      await tester.pumpWidget(
        themed(
          Align(
            alignment: Alignment.topCenter,
            child: ClipboardSuggestion(url: url, onUse: onUse ?? () {}),
          ),
          theme: theme,
        ),
      );
      await tester.pumpAndSettle();
    }

    group(mode, () {
      testWidgets('shows the caption, the URL and Use', (tester) async {
        await pump(tester, _url);

        expect(find.text(_caption), findsOneWidget);
        expect(find.text(_url), findsOneWidget);
        expect(find.text('Use'), findsOneWidget);
      });

      testWidgets('the URL is one mono line that ellipsizes at the end', (
        tester,
      ) async {
        await pump(tester, '$_url&list=${'x' * 200}');

        final text = tester.widget<Text>(find.textContaining('youtube.com'));
        expect(text.maxLines, 1);
        expect(text.overflow, TextOverflow.ellipsis);
        expect(text.textDirection, TextDirection.ltr);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a dashed 1 dp borderStrong border, radius 14', (
        tester,
      ) async {
        await pump(tester, _url);

        final painter = tester
            .widgetList<CustomPaint>(
              find.descendant(
                of: find.byType(ClipboardSuggestion),
                matching: find.byType(CustomPaint),
              ),
            )
            .map((p) => p.foregroundPainter)
            .whereType<DashedBorderPainter>()
            .single;
        expect(painter.color, tokens.borderStrong);
        expect(painter.width, 1);
        expect(painter.radius, 14.r);
        expect(painter.dash, 4.r);
        expect(painter.gap, 3.r);
      });

      testWidgets('Use calls onUse and the button is 44 high', (tester) async {
        var used = 0;
        await pump(tester, _url, onUse: () => used++);

        expect(tester.getSize(find.byType(OutlinedButton)).height, 44.h);
        await tester.tap(find.text('Use'));
        expect(used, 1);
      });

      testWidgets('nothing takes space without a URL', (tester) async {
        await pump(tester, null);

        expect(find.text(_caption), findsNothing);
        expect(tester.getSize(find.byType(ClipboardSuggestion)).height, 0);
      });

      testWidgets('fades in, then fades out and collapses in 200 ms', (
        tester,
      ) async {
        await pump(tester, null);
        await tester.pumpWidget(
          themed(
            const Align(
              alignment: Alignment.topCenter,
              child: ClipboardSuggestion(url: _url, onUse: _noop),
            ),
            theme: theme,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        final half = tester.getSize(find.byType(ClipboardSuggestion)).height;
        expect(half, greaterThan(0));
        await tester.pumpAndSettle();
        final full = tester.getSize(find.byType(ClipboardSuggestion)).height;
        expect(half, lessThan(full));

        await tester.pumpWidget(
          themed(
            const Align(
              alignment: Alignment.topCenter,
              child: ClipboardSuggestion(url: null, onUse: _noop),
            ),
            theme: theme,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        // Still fading out: the caption is there and the height is shrinking.
        expect(find.text(_caption), findsOneWidget);
        expect(
          tester.getSize(find.byType(ClipboardSuggestion)).height,
          lessThan(full),
        );

        await tester.pumpAndSettle();
        expect(find.text(_caption), findsNothing);
        expect(tester.getSize(find.byType(ClipboardSuggestion)).height, 0);
      });

      testWidgets('under reduced motion it appears and goes at once', (
        tester,
      ) async {
        reduceMotion(tester);
        await pump(tester, null);
        await tester.pumpWidget(
          themed(
            const Align(
              alignment: Alignment.topCenter,
              child: ClipboardSuggestion(url: _url, onUse: _noop),
            ),
            theme: theme,
          ),
        );
        await tester.pump();
        await tester.pump();

        expect(find.text(_caption), findsOneWidget);
        final full = tester.getSize(find.byType(ClipboardSuggestion)).height;
        expect(full, greaterThan(0));
      });
    });
  }
}

void _noop() {}
