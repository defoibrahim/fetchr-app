import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/gen/assets.gen.dart';
import 'package:grabby/core/gen/fonts.gen.dart';
import 'package:grabby/core/theme/app_text_styles.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/utils/scale.dart';
import 'package:grabby/core/widgets/app_button.dart';
import 'package:grabby/core/widgets/app_icon.dart';
import 'package:grabby/core/widgets/error_card.dart';

import 'widget_harness.dart';

void main() {
  for (final MapEntry(key: mode, value: theme) in themes.entries) {
    final tokens = theme.extension<AppTokens>()!;

    ErrorCardData data({
      List<ErrorCardAction> actions = const [],
      List<InlineSpan>? body,
    }) => ErrorCardData(
      icon: Assets.icons.wifiOff,
      title: 'No internet connection',
      body: body ?? const [TextSpan(text: 'Connect and try again.')],
      actions: actions,
    );

    Future<void> pump(
      WidgetTester tester,
      ErrorCardData card, {
      ErrorCardLayout layout = ErrorCardLayout.full,
    }) async {
      await tester.pumpWidget(
        themed(
          Align(
            alignment: Alignment.topLeft,
            child: ErrorCard(data: card, layout: layout),
          ),
          theme: theme,
        ),
      );
      // Not pumpAndSettle: a busy action spins forever.
      await tester.pump(const Duration(milliseconds: 250));
    }

    group(mode, () {
      testWidgets('full: surface, border, radius and padding', (tester) async {
        await pump(tester, data());

        final box = tester.widget<DecoratedBox>(
          find
              .descendant(
                of: find.byType(ErrorCard),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        final decoration = box.decoration as BoxDecoration;
        expect(decoration.color, tokens.errorSurface);
        expect(decoration.border, Border.all(color: tokens.errorBorder));
        expect(decoration.borderRadius, BorderRadius.circular(18.r));
        final card = tester.getRect(find.byType(ErrorCard));
        final tile = tester.getRect(
          find.ancestor(
            of: find.byType(AppIcon),
            matching: find.byType(Container),
          ),
        );
        expect(tile.left - card.left, closeTo(18.r, 0.01));
        expect(tile.top - card.top, closeTo(18.r, 0.01));
      });

      testWidgets('full: a 40 dp icon tile, the title and the body', (
        tester,
      ) async {
        await pump(tester, data());

        final tile = find.ancestor(
          of: find.byType(AppIcon),
          matching: find.byType(Container),
        );
        expect(tester.getSize(tile), Size.square(40.r));
        final container = tester.widget<Container>(tile);
        expect(
          (container.decoration as BoxDecoration).color,
          tokens.errorIconBg,
        );
        expect(
          (container.decoration as BoxDecoration).borderRadius,
          BorderRadius.circular(12.r),
        );
        final icon = tester.widget<AppIcon>(find.byType(AppIcon));
        expect(icon.icon, Assets.icons.wifiOff);
        expect(icon.size, 20.r);
        expect(icon.color, tokens.error);
        final title = tester.widget<Text>(find.text('No internet connection'));
        expect(title.style!.fontSize, 17);
        expect(title.style!.fontWeight, FontWeight.w600);
        expect(title.style!.color, tokens.text);
        final body = tester.widget<RichText>(
          find.textContaining('Connect and try again.', findRichText: true),
        );
        expect(body.text.style!.fontSize, 14);
        expect(body.text.style!.height, 1.45);
        expect(body.text.style!.color, tokens.errorBody);
      });

      testWidgets('mono spans use the mono family at the body size', (
        tester,
      ) async {
        await pump(
          tester,
          data(
            body: [
              const TextSpan(text: 'It needs about '),
              AppTextStyles.monoSpan('1.2 GB'),
              const TextSpan(text: ' to save.'),
            ],
          ),
        );

        final body = tester.widget<RichText>(
          find.textContaining('about 1.2 GB to save.', findRichText: true),
        );
        final span = body.text.getSpanForPosition(
          const TextPosition(offset: 'It needs about 1'.length),
        )!;
        expect(span, isA<TextSpan>());
        expect((span as TextSpan).style!.fontFamily, FontFamily.jetBrainsMono);
        expect(body.text.style!.fontSize, 14);
      });

      testWidgets('full: actions sit in a row in order, primary filled', (
        tester,
      ) async {
        await pump(
          tester,
          data(
            actions: [
              ErrorCardAction(label: 'Retry', primary: true, onPressed: () {}),
              ErrorCardAction(label: 'Edit link', onPressed: () {}),
            ],
          ),
        );

        expect(find.byType(AppButton), findsNWidgets(2));
        final first = tester.getRect(find.widgetWithText(AppButton, 'Retry'));
        final second = tester.getRect(
          find.widgetWithText(AppButton, 'Edit link'),
        );
        expect(first.top, second.top);
        expect(first.right + 8.w, closeTo(second.left, 0.01));
        expect(first.height, closeTo(46.h, 0.01));
        expect(find.byType(FilledButton), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(FilledButton),
            matching: find.text('Retry'),
          ),
          findsOneWidget,
        );
        expect(find.byType(OutlinedButton), findsOneWidget);
      });

      testWidgets('full: actions stack under 360 dp', (tester) async {
        useView(tester, const Size(320, 800));
        await pump(
          tester,
          data(
            actions: [
              ErrorCardAction(label: 'Retry', primary: true, onPressed: () {}),
              ErrorCardAction(label: 'Edit link', onPressed: () {}),
            ],
          ),
        );

        final first = tester.getRect(find.widgetWithText(AppButton, 'Retry'));
        final second = tester.getRect(
          find.widgetWithText(AppButton, 'Edit link'),
        );
        expect(second.top, greaterThan(first.bottom));
        expect(second.left, first.left);
        expect(second.width, first.width);
      });

      testWidgets('full: actions sit side by side from 360 dp', (tester) async {
        useView(tester, const Size(360, 800));
        await pump(
          tester,
          data(
            actions: [
              ErrorCardAction(label: 'Retry', primary: true, onPressed: () {}),
              ErrorCardAction(label: 'Edit link', onPressed: () {}),
            ],
          ),
        );

        final first = tester.getRect(find.widgetWithText(AppButton, 'Retry'));
        final second = tester.getRect(
          find.widgetWithText(AppButton, 'Edit link'),
        );
        expect(second.top, first.top);
      });

      testWidgets('a busy action shows its busy label and ignores taps', (
        tester,
      ) async {
        var taps = 0;
        await pump(
          tester,
          data(
            actions: [
              ErrorCardAction(
                label: 'Update yt-dlp',
                primary: true,
                busy: true,
                busyLabel: 'Updating…',
                onPressed: () => taps++,
              ),
            ],
          ),
        );

        expect(find.text('Updating…'), findsOneWidget);
        expect(find.text('Update yt-dlp'), findsNothing);
        await tester.tap(find.text('Updating…'));
        expect(taps, 0);
      });

      testWidgets('an idle action calls onPressed', (tester) async {
        var taps = 0;
        await pump(
          tester,
          data(
            actions: [ErrorCardAction(label: 'Retry', onPressed: () => taps++)],
          ),
        );

        await tester.tap(find.text('Retry'));
        expect(taps, 1);
      });

      testWidgets('is a live region', (tester) async {
        await pump(tester, data());

        expect(
          find.descendant(
            of: find.byType(ErrorCard),
            matching: find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.liveRegion == true,
            ),
          ),
          findsOneWidget,
        );
      });

      testWidgets('compact: one title line, the reason, trailing actions', (
        tester,
      ) async {
        await pump(
          tester,
          ErrorCardData(
            icon: Assets.icons.wifiOff,
            title: 'Night drive, no music',
            body: const [TextSpan(text: 'Connection dropped at 41%')],
            actions: [
              ErrorCardAction(label: 'Retry', primary: true, onPressed: () {}),
            ],
          ),
          layout: ErrorCardLayout.compact,
        );

        final title = tester.widget<Text>(find.text('Night drive, no music'));
        expect(title.maxLines, 1);
        expect(title.style!.fontSize, 14);
        expect(title.style!.fontWeight, FontWeight.w600);
        final meta = tester.widget<RichText>(
          find.textContaining('Connection dropped at 41%', findRichText: true),
        );
        expect(meta.text.style!.fontSize, 12);
        expect(meta.text.style!.color, tokens.errorText);
        final card = tester.getRect(find.byType(ErrorCard));
        final tile = tester.getRect(
          find.ancestor(
            of: find.byType(AppIcon),
            matching: find.byType(Container),
          ),
        );
        expect(tile.left - card.left, closeTo(14.r, 0.01));
        final button = tester.getRect(find.byType(FilledButton));
        expect(button.height, closeTo(44.h, 0.01));
        expect(
          button.left,
          greaterThan(tester.getRect(find.text('Night drive, no music')).right),
        );
      });

      testWidgets('compact: a long label wraps before it squeezes the icon', (
        tester,
      ) async {
        useView(tester, const Size(240, 640));
        await pump(
          tester,
          ErrorCardData(
            icon: Assets.icons.alertCircle,
            title: 'Night drive, no music',
            body: const [TextSpan(text: "Fetchr can't save files")],
            actions: [
              ErrorCardAction(
                label: 'Open settings',
                primary: true,
                onPressed: () {},
              ),
            ],
          ),
          layout: ErrorCardLayout.compact,
        );

        expect(tester.takeException(), isNull);
        final text = tester.getRect(find.text('Night drive, no music'));
        expect(text.width, greaterThanOrEqualTo(64.w - 0.01));
      });

      testWidgets('appears with a fade and a size change, then settles', (
        tester,
      ) async {
        await tester.pumpWidget(
          themed(
            Align(
              alignment: Alignment.topLeft,
              child: ErrorCard(data: data()),
            ),
            theme: theme,
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));

        final partial = tester.widget<Opacity>(
          find.descendant(
            of: find.byType(ErrorCard),
            matching: find.byType(Opacity),
          ),
        );
        expect(partial.opacity, lessThan(1));

        await tester.pump(const Duration(milliseconds: 200));
        final settled = tester.widget<Opacity>(
          find.descendant(
            of: find.byType(ErrorCard),
            matching: find.byType(Opacity),
          ),
        );
        expect(settled.opacity, 1);
      });

      testWidgets('compact rows do not replay the entrance', (tester) async {
        await tester.pumpWidget(
          themed(
            Align(
              alignment: Alignment.topLeft,
              child: ErrorCard(data: data(), layout: ErrorCardLayout.compact),
            ),
            theme: theme,
          ),
        );

        expect(
          find.descendant(
            of: find.byType(ErrorCard),
            matching: find.byType(Opacity),
          ),
          findsNothing,
        );
      });

      testWidgets('reduce motion shows it at once', (tester) async {
        reduceMotion(tester);
        await tester.pumpWidget(
          themed(
            Align(
              alignment: Alignment.topLeft,
              child: ErrorCard(data: data()),
            ),
            theme: theme,
          ),
        );

        expect(
          find.descendant(
            of: find.byType(ErrorCard),
            matching: find.byType(Opacity),
          ),
          findsNothing,
        );
        expect(find.text('No internet connection'), findsOneWidget);
      });
    });
  }
}
