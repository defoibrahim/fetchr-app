import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/gen/assets.gen.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/utils/scale.dart';
import 'package:grabby/core/widgets/app_icon.dart';
import 'package:grabby/core/widgets/empty_view.dart';

import 'widget_harness.dart';

void main() {
  for (final MapEntry(key: mode, value: theme) in themes.entries) {
    final tokens = theme.extension<AppTokens>()!;

    group(mode, () {
      testWidgets('a message alone is muted body text, centred', (
        tester,
      ) async {
        await tester.pumpWidget(
          themed(const EmptyView(message: 'Nothing here'), theme: theme),
        );

        final text = tester.widget<Text>(find.text('Nothing here'));
        expect(text.style!.color, tokens.textMuted);
        expect(text.style!.fontSize, 14);
        expect(text.style!.height, 1.5);
        expect(text.textAlign, TextAlign.center);
        expect(find.byType(AppIcon), findsNothing);
      });

      testWidgets('shows the illustration, title, message and action', (
        tester,
      ) async {
        await tester.pumpWidget(
          themed(
            EmptyView(
              illustration: Assets.icons.emptyDownloads,
              title: 'Nothing downloading',
              message: 'Active downloads appear here.',
              action: TextButton(onPressed: () {}, child: const Text('Paste')),
            ),
            theme: theme,
          ),
        );

        final icon = tester.widget<AppIcon>(find.byType(AppIcon));
        expect(icon.icon, Assets.icons.emptyDownloads);
        expect(icon.size, 64.r);
        expect(icon.color, tokens.borderStrong);
        final title = tester.widget<Text>(find.text('Nothing downloading'));
        expect(title.style!.fontSize, 17);
        expect(title.style!.color, tokens.text);
        expect(find.text('Active downloads appear here.'), findsOneWidget);
        // Top to bottom: illustration, title, message, action.
        final ys = [
          tester.getCenter(find.byType(AppIcon)).dy,
          tester.getCenter(find.text('Nothing downloading')).dy,
          tester.getCenter(find.text('Active downloads appear here.')).dy,
          tester.getCenter(find.text('Paste')).dy,
        ];
        expect(ys, [...ys]..sort());
      });

      testWidgets('the message is at most 300 wide', (tester) async {
        await tester.pumpWidget(
          themed(EmptyView(message: 'word ' * 80), theme: theme),
        );

        final box = tester.getSize(find.byType(Text));
        expect(box.width, lessThanOrEqualTo(300.w));
      });
    });
  }
}
