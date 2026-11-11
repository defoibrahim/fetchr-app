import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/gen/assets.gen.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/utils/scale.dart';
import 'package:grabby/core/widgets/app_button.dart';
import 'package:grabby/core/widgets/app_icon.dart';
import 'package:grabby/core/widgets/confirm_dialog.dart';

import 'widget_harness.dart';

void main() {
  for (final MapEntry(key: mode, value: theme) in themes.entries) {
    final tokens = theme.extension<AppTokens>()!;
    bool? answer;

    Future<void> openDialog(
      WidgetTester tester, {
      (String, String)? meta = ('720p · MP4', '96 MB'),
      SvgGenImage? icon,
    }) async {
      answer = null;
      await tester.pumpWidget(
        themed(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(
                showConfirmDialog(
                  context,
                  title: 'Delete this file?',
                  message: '“Clip” will be removed from your phone.',
                  confirmLabel: 'Delete',
                  icon: icon ?? Assets.icons.trash,
                  meta: meta,
                ).then((v) => answer = v),
              ),
              child: const Text('Open'),
            ),
          ),
          theme: theme,
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
    }

    group(mode, () {
      testWidgets('shows the title, message, meta strip and both buttons', (
        tester,
      ) async {
        await openDialog(tester);

        expect(find.text('Delete this file?'), findsOneWidget);
        expect(
          find.text('“Clip” will be removed from your phone.'),
          findsOneWidget,
        );
        expect(find.text('720p · MP4'), findsOneWidget);
        expect(find.text('96 MB'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('Delete'), findsOneWidget);
      });

      testWidgets('the surface, border and radius follow the spec', (
        tester,
      ) async {
        await openDialog(tester);

        // The dialog theme owns the surface; read what is painted.
        final surface = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(Dialog),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(surface.color, tokens.surface);
        final shape = surface.shape! as RoundedRectangleBorder;
        expect(shape.side.color, tokens.border);
        expect(shape.borderRadius, BorderRadius.circular(28));
        final title = tester.widget<Text>(find.text('Delete this file?'));
        expect(title.style!.fontSize, 22);
        expect(title.style!.color, tokens.text);
        final body = tester.widget<Text>(
          find.text('“Clip” will be removed from your phone.'),
        );
        expect(body.style!.color, tokens.errorBody);
        expect(body.style!.height, 1.5);
      });

      testWidgets('the icon sits in a 44 dp errorIconBg tile', (tester) async {
        await openDialog(tester);

        final tile = find.ancestor(
          of: find.byType(AppIcon),
          matching: find.byType(Container),
        );
        expect(tester.getSize(tile), Size.square(44.r));
        expect(
          (tester.widget<Container>(tile).decoration! as BoxDecoration).color,
          tokens.errorIconBg,
        );
        final icon = tester.widget<AppIcon>(find.byType(AppIcon));
        expect(icon.icon, Assets.icons.trash);
        expect(icon.color, tokens.error);
      });

      testWidgets('the meta strip is a bg strip with a string at each end', (
        tester,
      ) async {
        await openDialog(tester);

        final strip = find.ancestor(
          of: find.text('96 MB'),
          matching: find.byType(Container),
        );
        final decoration =
            tester.widget<Container>(strip).decoration! as BoxDecoration;
        expect(decoration.color, tokens.bg);
        expect(decoration.borderRadius, BorderRadius.circular(12.r));
        expect(
          tester.widget<Text>(find.text('96 MB')).style!.color,
          tokens.textMuted,
        );
        final box = tester.getRect(strip);
        expect(
          tester.getRect(find.text('720p · MP4')).left - box.left,
          closeTo(12.w, 0.01),
        );
        expect(
          box.right - tester.getRect(find.text('96 MB')).right,
          closeTo(12.w, 0.01),
        );
      });

      testWidgets('without meta or icon those parts are left out', (
        tester,
      ) async {
        answer = null;
        await tester.pumpWidget(
          themed(
            Builder(
              builder: (context) => TextButton(
                onPressed: () => unawaited(
                  showConfirmDialog(
                    context,
                    title: 'Sure?',
                    message: 'Really.',
                    confirmLabel: 'Yes',
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
            theme: theme,
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        expect(find.byType(AppIcon), findsNothing);
        expect(find.text('Sure?'), findsOneWidget);
      });

      testWidgets('Cancel is outlined and Delete is destructive, both 48', (
        tester,
      ) async {
        await openDialog(tester);

        final cancel = tester.widget<AppButton>(
          find.widgetWithText(AppButton, 'Cancel'),
        );
        final confirm = tester.widget<AppButton>(
          find.widgetWithText(AppButton, 'Delete'),
        );
        expect(cancel.variant, AppButtonVariant.outlined);
        expect(cancel.size, AppButtonSize.medium);
        expect(confirm.variant, AppButtonVariant.destructive);
        expect(confirm.size, AppButtonSize.medium);
        final left = tester.getRect(find.widgetWithText(AppButton, 'Cancel'));
        final right = tester.getRect(find.widgetWithText(AppButton, 'Delete'));
        expect(left.width, closeTo(right.width, 0.01));
        expect(right.left - left.right, closeTo(10.w, 0.01));
      });

      testWidgets('Delete gives true', (tester) async {
        await openDialog(tester);

        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();

        expect(answer, isTrue);
        expect(find.byType(Dialog), findsNothing);
      });

      testWidgets('Cancel gives false', (tester) async {
        await openDialog(tester);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(answer, isFalse);
        expect(find.byType(Dialog), findsNothing);
      });

      testWidgets('a tap on the barrier gives false', (tester) async {
        await openDialog(tester);

        await tester.tapAt(const Offset(4, 4));
        await tester.pumpAndSettle();

        expect(answer, isFalse);
        expect(find.byType(Dialog), findsNothing);
      });

      testWidgets('the barrier is the scrim token', (tester) async {
        await openDialog(tester);

        final barrier = tester.widget<AnimatedModalBarrier>(
          find.byType(AnimatedModalBarrier).last,
        );
        expect(barrier.color.value, tokens.scrim);
      });
    });
  }

  testWidgets('confirmDeleteFile asks about the file and resolves on Delete', (
    tester,
  ) async {
    bool? answer;
    await tester.pumpWidget(
      themed(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
              confirmDeleteFile(
                context,
                'Clip',
                meta: ('720p · MP4', '96 MB'),
              ).then((v) => answer = v),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Delete this file?'), findsOneWidget);
    expect(
      find.text('“Clip” will be removed from your phone and from Gallery.'),
      findsOneWidget,
    );
    expect(find.text('96 MB'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(answer, isTrue);
  });
}
