import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/gen/assets.gen.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/utils/scale.dart';
import 'package:grabby/core/widgets/app_button.dart';
import 'package:grabby/core/widgets/app_icon.dart';

import 'widget_harness.dart';

/// What the button paints: the Material under it holds the resolved fill,
/// label style and shape, whether the theme or AppButton set them.
Material _materialOf(WidgetTester tester, Finder button) =>
    tester.widget<Material>(
      find.descendant(of: button, matching: find.byType(Material)).first,
    );

double _radiusOf(Material material) {
  final shape = material.shape! as RoundedRectangleBorder;
  return (shape.borderRadius as BorderRadius).topLeft.x;
}

Color? _iconColor(WidgetTester tester) =>
    IconTheme.of(tester.element(find.byType(AppIcon))).color;

bool _sameRgb(Color a, Color b) =>
    a.toARGB32() & 0x00FFFFFF == b.toARGB32() & 0x00FFFFFF;

void main() {
  for (final MapEntry(key: mode, value: theme) in themes.entries) {
    final tokens = theme.extension<AppTokens>()!;
    final scheme = theme.colorScheme;

    Future<void> pump(WidgetTester tester, Widget button) => tester.pumpWidget(
      themed(
        Align(alignment: Alignment.topLeft, child: button),
        theme: theme,
      ),
    );

    group(mode, () {
      testWidgets('each variant renders its Material button and taps', (
        tester,
      ) async {
        final expected = {
          AppButtonVariant.filled: find.byType(FilledButton),
          AppButtonVariant.destructive: find.byType(FilledButton),
          AppButtonVariant.outlined: find.byType(OutlinedButton),
          AppButtonVariant.text: find.byType(TextButton),
        };
        for (final entry in expected.entries) {
          var taps = 0;
          await pump(
            tester,
            AppButton(label: 'Go', variant: entry.key, onPressed: () => taps++),
          );

          expect(entry.value, findsOneWidget);
          await tester.tap(find.text('Go'));
          expect(taps, 1, reason: entry.key.name);
        }
      });

      testWidgets('filled is primary on onPrimary', (tester) async {
        await pump(tester, AppButton(label: 'Go', onPressed: () {}));

        final material = _materialOf(tester, find.byType(FilledButton));
        expect(material.color, scheme.primary);
        expect(material.textStyle!.color, scheme.onPrimary);
      });

      testWidgets('destructive is an error fill with onError', (tester) async {
        await pump(
          tester,
          AppButton(
            label: 'Go',
            variant: AppButtonVariant.destructive,
            onPressed: () {},
          ),
        );

        final material = _materialOf(tester, find.byType(FilledButton));
        expect(material.color, tokens.error);
        expect(material.textStyle!.color, tokens.onError);
      });

      testWidgets('destructive fades to 40% when disabled', (tester) async {
        await pump(
          tester,
          const AppButton(
            label: 'Go',
            variant: AppButtonVariant.destructive,
            onPressed: null,
          ),
        );

        final material = _materialOf(tester, find.byType(FilledButton));
        expect(_sameRgb(material.color!, tokens.error), isTrue);
        expect(material.color!.a, closeTo(.4, .01));
        expect(material.textStyle!.color!.a, closeTo(.4, .01));
      });

      testWidgets('outlined has a 1 dp borderStrong side and text colour', (
        tester,
      ) async {
        await pump(
          tester,
          AppButton(
            label: 'Go',
            variant: AppButtonVariant.outlined,
            onPressed: () {},
          ),
        );

        final material = _materialOf(tester, find.byType(OutlinedButton));
        final shape = material.shape! as RoundedRectangleBorder;
        expect(shape.side.color, tokens.borderStrong);
        expect(shape.side.width, 1);
        expect(material.textStyle!.color, tokens.text);
        expect(material.color, anyOf(isNull, Colors.transparent));
      });

      // (size, height, radius, label size, filled weight, outlined weight)
      for (final (size, height, radius, fontSize, filled, outlined) in [
        (
          AppButtonSize.large,
          54.0,
          16.0,
          16.0,
          FontWeight.w600,
          FontWeight.w600,
        ),
        (
          AppButtonSize.medium,
          48.0,
          14.0,
          15.0,
          FontWeight.w600,
          FontWeight.w500,
        ),
        (
          AppButtonSize.compact,
          46.0,
          12.0,
          14.0,
          FontWeight.w600,
          FontWeight.w500,
        ),
        (
          AppButtonSize.small,
          44.0,
          12.0,
          14.0,
          FontWeight.w500,
          FontWeight.w500,
        ),
      ]) {
        testWidgets('${size.name} is $height high, radius $radius', (
          tester,
        ) async {
          await pump(
            tester,
            Column(
              children: [
                AppButton(label: 'F', size: size, onPressed: () {}),
                AppButton(
                  label: 'O',
                  size: size,
                  variant: AppButtonVariant.outlined,
                  onPressed: () {},
                ),
              ],
            ),
          );

          final filledFinder = find.byType(FilledButton);
          final outlinedFinder = find.byType(OutlinedButton);
          expect(tester.getSize(filledFinder).height, height.h);
          expect(tester.getSize(outlinedFinder).height, height.h);
          final filledMaterial = _materialOf(tester, filledFinder);
          expect(_radiusOf(filledMaterial), radius.r);
          expect(filledMaterial.textStyle!.fontSize, fontSize);
          expect(filledMaterial.textStyle!.fontWeight, filled);
          final outlinedMaterial = _materialOf(tester, outlinedFinder);
          expect(_radiusOf(outlinedMaterial), radius.r);
          expect(outlinedMaterial.textStyle!.fontWeight, outlined);
        });
      }

      testWidgets('a null onPressed disables the button at 40%', (
        tester,
      ) async {
        await pump(tester, const AppButton(label: 'Go', onPressed: null));

        final button = tester.widget<FilledButton>(find.byType(FilledButton));
        expect(button.enabled, isFalse);
        // The theme fades the same colours once; there is no Opacity on top.
        expect(find.byType(Opacity), findsNothing);
        final material = _materialOf(tester, find.byType(FilledButton));
        expect(_sameRgb(material.color!, scheme.primary), isTrue);
        expect(material.color!.a, closeTo(.4, .01));
        expect(material.textStyle!.color!.a, closeTo(.4, .01));
      });

      testWidgets('an enabled button is fully opaque', (tester) async {
        await pump(tester, AppButton(label: 'Go', onPressed: () {}));

        expect(find.byType(Opacity), findsNothing);
        expect(_materialOf(tester, find.byType(FilledButton)).color!.a, 1);
      });

      testWidgets('isLoading swallows taps and keeps the label width', (
        tester,
      ) async {
        var taps = 0;
        Widget button({required bool loading}) => AppButton(
          label: 'Update yt-dlp',
          expanded: false,
          isLoading: loading,
          onPressed: () => taps++,
        );
        await pump(tester, button(loading: false));
        final idle = tester.getSize(find.byType(FilledButton)).width;

        await pump(tester, button(loading: true));

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(tester.getSize(find.byType(FilledButton)).width, idle);
        await tester.tap(find.byType(FilledButton));
        expect(taps, 0);
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
          isTrue,
        );
      });

      testWidgets('the spinner is 18 dp', (tester) async {
        await pump(
          tester,
          AppButton(label: 'Go', isLoading: true, onPressed: () {}),
        );

        final box = tester.getSize(
          find
              .ancestor(
                of: find.byType(CircularProgressIndicator),
                matching: find.byType(SizedBox),
              )
              .first,
        );
        expect(box, Size.square(18.r));
      });

      testWidgets('the spinner takes the label colour', (tester) async {
        await pump(
          tester,
          AppButton(label: 'Go', isLoading: true, onPressed: () {}),
        );

        final spinner = tester.widget<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator),
        );
        expect(spinner.color, scheme.onPrimary);
      });

      testWidgets('loadingLabel replaces the label next to the spinner', (
        tester,
      ) async {
        await pump(
          tester,
          AppButton(
            label: 'Get formats',
            loadingLabel: 'Fetching…',
            isLoading: true,
            onPressed: () {},
          ),
        );

        expect(find.text('Fetching…'), findsOneWidget);
        expect(find.text('Get formats'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      });

      testWidgets('a null onPressed while loading stays disabled', (
        tester,
      ) async {
        await pump(
          tester,
          const AppButton(label: 'Go', isLoading: true, onPressed: null),
        );

        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).enabled,
          isFalse,
        );
      });

      testWidgets(
        'a leading icon is 18 dp, left of the label, on primaryIcon',
        (tester) async {
          await pump(
            tester,
            AppButton(
              label: 'Go',
              icon: Assets.icons.download,
              onPressed: () {},
            ),
          );

          expect(tester.widget<AppIcon>(find.byType(AppIcon)).size, 18.r);
          expect(_iconColor(tester), tokens.primaryIcon);
          final iconX = tester.getCenter(find.byType(AppIcon)).dx;
          final labelBox = tester.getRect(find.text('Go'));
          expect(iconX, lessThan(labelBox.left));
          expect(
            labelBox.left - tester.getRect(find.byType(AppIcon)).right,
            closeTo(8.w, 0.01),
          );
        },
      );

      testWidgets('iconAfter puts the icon after the label', (tester) async {
        await pump(
          tester,
          AppButton(
            label: 'Get formats',
            icon: Assets.icons.arrowRight,
            iconAfter: true,
            variant: AppButtonVariant.outlined,
            onPressed: () {},
          ),
        );

        expect(
          tester.getCenter(find.byType(AppIcon)).dx,
          greaterThan(tester.getRect(find.text('Get formats')).right),
        );
        expect(_iconColor(tester), tokens.text);
      });

      testWidgets('a disabled icon fades with the label', (tester) async {
        await pump(
          tester,
          AppButton(label: 'Go', icon: Assets.icons.download, onPressed: null),
        );

        expect(_sameRgb(_iconColor(tester)!, tokens.primaryIcon), isTrue);
        expect(_iconColor(tester)!.a, closeTo(.4, .01));
      });

      testWidgets('expanded fills the width; otherwise it hugs the label', (
        tester,
      ) async {
        await pump(tester, AppButton(label: 'Go', onPressed: () {}));
        final wide = tester.getSize(find.byType(FilledButton)).width;

        await pump(
          tester,
          AppButton(label: 'Go', expanded: false, onPressed: () {}),
        );
        final narrow = tester.getSize(find.byType(FilledButton)).width;

        expect(
          wide,
          tester.view.physicalSize.width / tester.view.devicePixelRatio,
        );
        expect(narrow, lessThan(wide));
      });
    });
  }
}
