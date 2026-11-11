import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/core/gen/assets.gen.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/widgets/app_icon.dart';
import 'package:grabby/core/widgets/app_snackbar.dart';

import '../../support/snackbar.dart';
import 'widget_harness.dart';

void main() {
  const failure = StorageFailure();

  group('showUndo', () {
    testWidgets('shows the message with an Undo action', (tester) async {
      final context = await pumpContext(tester);

      unawaited(AppSnackbar.showUndo(context, 'File deleted'));
      await pumpSnackbarIn(tester);

      expect(find.text('File deleted'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      expect(
        tester.widget<AppIcon>(find.byType(AppIcon)).icon,
        Assets.icons.alertCircle,
      );
    });

    testWidgets('resolves true when Undo is tapped', (tester) async {
      final context = await pumpContext(tester);
      bool? undone;
      unawaited(AppSnackbar.showUndo(context, 'x').then((v) => undone = v));
      await pumpSnackbarIn(tester);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(undone, isTrue);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('resolves false and closes after 5 s', (tester) async {
      final context = await pumpContext(tester);
      bool? undone;
      unawaited(AppSnackbar.showUndo(context, 'x').then((v) => undone = v));
      await pumpSnackbarIn(tester);

      await tester.pump(const Duration(seconds: 4));
      expect(find.byType(SnackBar), findsOneWidget);
      expect(undone, isNull);

      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(undone, isFalse);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('resolves false when another snackbar replaces it', (
      tester,
    ) async {
      final context = await pumpContext(tester);
      bool? undone;
      unawaited(AppSnackbar.showUndo(context, 'x').then((v) => undone = v));
      await pumpSnackbarIn(tester);

      AppSnackbar.show(context, 'Other');
      await tester.pumpAndSettle();

      expect(undone, isFalse);
      expect(find.text('Other'), findsOneWidget);
    });

    testWidgets('resolves false when swiped away', (tester) async {
      final context = await pumpContext(tester);
      bool? undone;
      unawaited(AppSnackbar.showUndo(context, 'x').then((v) => undone = v));
      await pumpSnackbarIn(tester);

      await tester.fling(find.text('x'), const Offset(0, 200), 1000);
      await tester.pumpAndSettle();

      expect(undone, isFalse);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('show', () {
    for (final MapEntry(key: mode, value: theme) in themes.entries) {
      final tokens = theme.extension<AppTokens>()!;

      testWidgets('$mode: a floating raised card with a bordered radius', (
        tester,
      ) async {
        final context = await pumpContext(tester, theme: theme);

        AppSnackbar.show(context, 'Copied');
        await tester.pumpAndSettle();

        // The theme owns all of it; read what is painted.
        final bar = find
            .descendant(
              of: find.byType(SnackBar),
              matching: find.byType(Material),
            )
            .first;
        final material = tester.widget<Material>(bar);
        expect(material.color, tokens.surfaceRaised);
        expect(material.elevation, 0);
        final shape = material.shape! as RoundedRectangleBorder;
        expect(shape.side.color, tokens.border);
        expect(shape.borderRadius, BorderRadius.circular(14));
        expect(
          tester.getSize(bar).width,
          lessThan(
            tester.view.physicalSize.width / tester.view.devicePixelRatio,
          ),
        );
        final text = DefaultTextStyle.of(tester.element(find.text('Copied')));
        expect(text.style.color, tokens.text);
        expect(text.style.fontSize, 14);
      });

      testWidgets('$mode: each type has its icon and colour', (tester) async {
        final context = await pumpContext(tester, theme: theme);
        final expected = {
          SnackType.info: (Assets.icons.alertCircle, tokens.textMuted),
          SnackType.success: (Assets.icons.check, tokens.accent),
          SnackType.error: (Assets.icons.alertCircle, tokens.error),
        };

        for (final MapEntry(key: type, value: (icon, tint))
            in expected.entries) {
          AppSnackbar.show(context, 'msg ${type.name}', type: type);
          await tester.pumpAndSettle();

          expect(find.text('msg ${type.name}'), findsOneWidget);
          final shown = tester.widget<AppIcon>(find.byType(AppIcon));
          expect(shown.icon, icon, reason: type.name);
          expect(shown.color, tint, reason: type.name);
        }
      });

      testWidgets('$mode: an action runs its callback and closes the bar', (
        tester,
      ) async {
        final context = await pumpContext(tester, theme: theme);
        var views = 0;

        AppSnackbar.show(
          context,
          'Added to Downloads',
          action: ('View', () => views++),
        );
        await tester.pumpAndSettle();
        final label = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(SnackBarAction),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(label.textStyle!.color, theme.colorScheme.primary);
        // The bar gives its action a TextButtonTheme of its own, so the app's
        // stock button theme (and its 54 dp, 16 dp-radius shape) never reaches it.
        expect(label.textStyle!.fontSize, 14);
        expect(
          tester
              .getSize(
                find.descendant(
                  of: find.byType(SnackBarAction),
                  matching: find.byType(TextButton),
                ),
              )
              .height,
          48,
        );

        await tester.tap(find.text('View'));
        await tester.pumpAndSettle();

        expect(views, 1);
        expect(find.byType(SnackBar), findsNothing);
      });
    }

    testWidgets('a custom duration closes the bar sooner', (tester) async {
      final context = await pumpContext(tester);

      AppSnackbar.show(context, 'Quick', duration: const Duration(seconds: 1));
      await pumpSnackbarIn(tester);
      // The timer, then a frame to start the exit, then the exit. A default
      // 4 s bar would still be up.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('an action does not keep the bar up for ever', (tester) async {
      final context = await pumpContext(tester);

      AppSnackbar.show(context, 'Added', action: ('View', () {}));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('showFailure', () {
    testWidgets('shows an Err as an error snackbar', (tester) async {
      final context = await pumpContext(tester);

      unawaited(AppSnackbar.showFailure(context, const Err<int>(failure)));
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(failure.message), findsOneWidget);
      expect(
        tester.widget<AppIcon>(find.byType(AppIcon)).icon,
        Assets.icons.alertCircle,
      );
    });

    testWidgets('shows nothing for an Ok', (tester) async {
      final context = await pumpContext(tester);

      unawaited(AppSnackbar.showFailure(context, const Ok<int>(1)));
      await tester.pump();

      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('waits for a future result', (tester) async {
      final context = await pumpContext(tester);
      final pending = Completer<Result<void>>();

      unawaited(AppSnackbar.showFailure(context, pending.future));
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);

      pending.complete(const Err<void>(failure));
      await tester.pump();
      await tester.pump();

      expect(find.text(failure.message), findsOneWidget);
    });

    testWidgets('does not touch a context that unmounted while waiting', (
      tester,
    ) async {
      final context = await pumpContext(tester);
      final pending = Completer<Result<void>>();
      final shown = AppSnackbar.showFailure(context, pending.future);

      await tester.pumpWidget(const SizedBox());
      pending.complete(const Err<void>(failure));

      await expectLater(shown, completes);
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
