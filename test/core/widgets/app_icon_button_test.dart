import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/gen/assets.gen.dart';
import 'package:grabby/core/theme/app_spacing.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/widgets/app_icon_button.dart';

import 'widget_harness.dart';

ColorFilter tint(Color color) => ColorFilter.mode(color, BlendMode.srcIn);

void main() {
  for (final MapEntry(key: mode, value: theme) in themes.entries) {
    final tokens = theme.extension<AppTokens>()!;

    Future<void> pump(
      WidgetTester tester, {
      bool bordered = false,
      VoidCallback? onPressed,
    }) async {
      useView(tester);
      await tester.pumpWidget(
        themed(
          Align(
            alignment: Alignment.topLeft,
            child: AppIconButton(
              icon: Assets.icons.close,
              tooltip: 'Close',
              bordered: bordered,
              onPressed: onPressed,
            ),
          ),
          theme: theme,
        ),
      );
    }

    RoundedRectangleBorder shapeOf(WidgetTester tester) {
      final button = tester.widget<IconButton>(find.byType(IconButton));
      return button.style!.shape!.resolve({}) as RoundedRectangleBorder;
    }

    group(mode, () {
      testWidgets('is a 44 dp square with an 18 dp icon', (tester) async {
        await pump(tester, onPressed: () {});

        expect(tester.getSize(find.byType(IconButton)), const Size.square(44));
        expect(
          tester.getSize(find.byType(SvgPicture)),
          const Size.square(AppSizes.iconButton),
        );
      });

      testWidgets('the tooltip is the screen reader label of a button', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await pump(tester, onPressed: () {});

        expect(find.byTooltip('Close'), findsOneWidget);
        expect(
          tester.getSemantics(find.byType(IconButton)),
          isSemantics(tooltip: 'Close', isButton: true),
        );
        handle.dispose();
      });

      testWidgets('plain: a muted icon and corners 12, with no outline', (
        tester,
      ) async {
        await pump(tester, onPressed: () {});

        expect(
          tester.widget<SvgPicture>(find.byType(SvgPicture)).colorFilter,
          tint(tokens.textMuted),
        );
        final shape = shapeOf(tester);
        expect(shape.borderRadius, BorderRadius.circular(Radii.button));
        expect(shape.side, BorderSide.none);
      });

      testWidgets('bordered: a text icon and a border outline', (tester) async {
        await pump(tester, bordered: true, onPressed: () {});

        expect(
          tester.widget<SvgPicture>(find.byType(SvgPicture)).colorFilter,
          tint(tokens.text),
        );
        final shape = shapeOf(tester);
        expect(shape.borderRadius, BorderRadius.circular(Radii.button));
        expect(shape.side, BorderSide(color: tokens.border));
      });

      testWidgets('a tap runs onPressed', (tester) async {
        var taps = 0;
        await pump(tester, onPressed: () => taps++);

        await tester.tap(find.byType(AppIconButton));

        expect(taps, 1);
      });

      testWidgets('a null onPressed disables the button', (tester) async {
        await pump(tester);

        expect(
          tester.widget<IconButton>(find.byType(IconButton)).onPressed,
          isNull,
        );
      });
    });
  }
}
