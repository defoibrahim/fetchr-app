import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/gen/fonts.gen.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/utils/scale.dart';
import 'package:grabby/core/widgets/app_icon.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/url_field.dart';

import '../../../../../core/widgets/widget_harness.dart';

void main() {
  for (final MapEntry(key: mode, value: theme) in themes.entries) {
    final tokens = theme.extension<AppTokens>()!;
    final primary = theme.colorScheme.primary;

    group(mode, () {
      late TextEditingController controller;
      late FocusNode focus;
      var pasted = 0;
      var cleared = 0;

      setUp(() {
        controller = TextEditingController();
        focus = FocusNode();
        pasted = 0;
        cleared = 0;
      });

      tearDown(() {
        controller.dispose();
        focus.dispose();
      });

      Future<void> pump(
        WidgetTester tester, {
        bool hasError = false,
        UrlFieldState? state,
        TextDirection direction = TextDirection.ltr,
      }) async {
        useView(tester);
        await tester.pumpWidget(
          themed(
            Directionality(
              textDirection: direction,
              child: Align(
                alignment: Alignment.topCenter,
                child: UrlField(
                  controller: controller,
                  focusNode: focus,
                  hasError: hasError,
                  state: state,
                  onPaste: () => pasted++,
                  onClear: () => cleared++,
                ),
              ),
            ),
            theme: theme,
          ),
        );
      }

      Border? borderOf(WidgetTester tester) {
        final box = tester.widget<DecoratedBox>(
          find
              .descendant(
                of: find.byType(UrlField),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        return (box.decoration as BoxDecoration).border as Border?;
      }

      testWidgets('empty: the hint, Paste, a 1 dp border, 56 high', (
        tester,
      ) async {
        await pump(tester);

        expect(find.text('https://…'), findsOneWidget);
        expect(find.text('Paste'), findsOneWidget);
        expect(find.byTooltip('Clear URL'), findsNothing);
        expect(borderOf(tester), Border.all(color: tokens.border));
        expect(tester.getSize(find.byType(UrlField)).height, 56.h);
        final box = tester.widget<DecoratedBox>(
          find
              .descendant(
                of: find.byType(UrlField),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        final decoration = box.decoration as BoxDecoration;
        expect(decoration.color, tokens.surface);
        expect(decoration.borderRadius, BorderRadius.circular(16.r));
      });

      testWidgets('empty: Paste is a 44 high surfaceSunken button', (
        tester,
      ) async {
        await pump(tester);

        final paste = find.ancestor(
          of: find.text('Paste'),
          matching: find.byType(TextButton),
        );
        expect(tester.getSize(paste).height, 44.h);
        final style = tester.widget<TextButton>(paste).style!;
        expect(style.backgroundColor!.resolve({}), tokens.surfaceSunken);

        await tester.tap(find.text('Paste'));
        expect(pasted, 1);
      });

      testWidgets('filled: a 44 square Clear button replaces Paste', (
        tester,
      ) async {
        controller.text = 'https://example.com/v';
        await pump(tester);

        expect(find.text('Paste'), findsNothing);
        final clear = find.byTooltip('Clear URL');
        expect(clear, findsOneWidget);
        expect(tester.getSize(clear), Size.square(44.r));
        expect(borderOf(tester), Border.all(color: tokens.border));

        await tester.tap(clear);
        expect(cleared, 1);
      });

      testWidgets('typing swaps Paste for Clear without a rebuild', (
        tester,
      ) async {
        await pump(tester);

        await tester.enterText(find.byType(TextField), 'https://x.test');
        await tester.pump();

        expect(find.text('Paste'), findsNothing);
        expect(find.byTooltip('Clear URL'), findsOneWidget);
      });

      testWidgets('focused: the border is the primary colour', (tester) async {
        await pump(tester);

        focus.requestFocus();
        await tester.pump();

        expect(borderOf(tester), Border.all(color: primary));
        // Empty and focused still offers Paste.
        expect(find.text('Paste'), findsOneWidget);
      });

      testWidgets('error: a 1.5 dp error border, even when focused', (
        tester,
      ) async {
        controller.text = 'https://example.com/v';
        await pump(tester, hasError: true);
        focus.requestFocus();
        await tester.pump();

        expect(borderOf(tester), Border.all(color: tokens.error, width: 1.5));
      });

      testWidgets('a state override wins over the controller and focus', (
        tester,
      ) async {
        await pump(tester, state: UrlFieldState.error);

        expect(borderOf(tester), Border.all(color: tokens.error, width: 1.5));
      });

      testWidgets('the text is one scrolling mono line', (tester) async {
        controller.text = 'https://example.com/${'long/' * 40}video';
        await pump(tester);

        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.maxLines, 1);
        expect(field.keyboardType, TextInputType.url);
        expect(field.style!.fontFamily, FontFamily.jetBrainsMono);
        expect(field.style!.fontSize, 13);
        expect(tester.takeException(), isNull);
      });

      testWidgets('stays left to right under a right to left app', (
        tester,
      ) async {
        await pump(tester, direction: TextDirection.rtl);

        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.textDirection, TextDirection.ltr);
        final link = tester.getCenter(find.byType(AppIcon).first);
        final paste = tester.getCenter(find.text('Paste'));
        expect(paste.dx, greaterThan(link.dx));
      });
    });
  }
}
