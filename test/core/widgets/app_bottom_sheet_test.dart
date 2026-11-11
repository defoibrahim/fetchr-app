import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/utils/scale.dart';
import 'package:grabby/core/utils/widget_utils.dart';
import 'package:grabby/core/widgets/sheet_drag_handle.dart';

import 'widget_harness.dart';

const phone = Size(390, 844);

final dialogs = find.byType(Dialog);

/// Opens `showAppBottomSheet` on a [size] window and waits for it to settle.
Future<void> openAt(
  WidgetTester tester,
  Size size,
  Widget child, {
  ThemeData? theme,
}) async {
  useView(tester, size);
  final context = await pumpContext(tester, theme: theme);
  unawaited(showAppBottomSheet<void>(context, child: child));
  await tester.pumpAndSettle();
}

void main() {
  for (final MapEntry(key: mode, value: theme) in themes.entries) {
    final tokens = theme.extension<AppTokens>()!;

    Future<void> openSheet(
      WidgetTester tester,
      Widget child, {
      Size size = phone,
    }) => openAt(tester, size, child, theme: theme);

    group(mode, () {
      testWidgets('SheetDragHandle is a 36 x 4 pill in borderStrong', (
        tester,
      ) async {
        await tester.pumpWidget(
          themed(const Center(child: SheetDragHandle()), theme: theme),
        );

        final box = tester.widget<Container>(find.byType(Container).first);
        final decoration = box.decoration! as BoxDecoration;
        expect(decoration.color, tokens.borderStrong);
        expect(decoration.borderRadius, BorderRadius.circular(999));
        expect(tester.getSize(find.byType(SheetDragHandle)), Size(36.w, 4.h));
      });

      testWidgets('shows the grabber and content on a bordered surface', (
        tester,
      ) async {
        await openSheet(tester, const Text('sheet body'));

        expect(find.text('sheet body'), findsOneWidget);
        expect(find.byType(SheetDragHandle), findsOneWidget);
        // The bottom sheet theme owns the surface; read what is painted.
        final surface = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(BottomSheet),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(surface.color, tokens.surface);
        final shape = surface.shape! as RoundedRectangleBorder;
        expect(
          shape.borderRadius,
          const BorderRadius.vertical(top: Radius.circular(28)),
        );
        expect(shape.side.color, tokens.border);
      });

      testWidgets('the grabber sits 10 dp from the top of the sheet', (
        tester,
      ) async {
        await openSheet(tester, const Text('sheet body'));

        final sheet = tester.getRect(find.byType(BottomSheet));
        final grabber = tester.getRect(find.byType(SheetDragHandle));
        expect(grabber.top - sheet.top, closeTo(10.h, 0.01));
      });

      testWidgets('the barrier is the scrim token', (tester) async {
        await openSheet(tester, const Text('sheet body'));

        final barrier = tester.widget<AnimatedModalBarrier>(
          find.byType(AnimatedModalBarrier).last,
        );
        expect(barrier.color.value, tokens.scrim);
      });

      testWidgets('is at most 88% of a portrait screen', (tester) async {
        await openSheet(tester, const SizedBox(height: 3000));

        expect(
          tester.getSize(find.byType(BottomSheet)).height,
          closeTo(844 * 0.88, 0.01),
        );
      });

      testWidgets('is at most 90% of a landscape screen', (tester) async {
        await openSheet(
          tester,
          const SizedBox(height: 3000),
          size: const Size(844, 390),
        );

        expect(
          tester.getSize(find.byType(BottomSheet)).height,
          closeTo(390 * 0.9, 0.01),
        );
      });

      testWidgets('a short sheet hugs its content', (tester) async {
        await openSheet(tester, const SizedBox(height: 100));

        expect(
          tester.getSize(find.byType(BottomSheet)).height,
          lessThan(844 * 0.5),
        );
      });

      testWidgets('from 600 dp it is a dialog on the dialog surface', (
        tester,
      ) async {
        await openSheet(
          tester,
          const Text('sheet body'),
          size: const Size(700, 1000),
        );

        expect(find.text('sheet body'), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.byType(SheetDragHandle), findsNothing);
        final surface = tester.widget<Material>(
          find.descendant(of: dialogs, matching: find.byType(Material)).first,
        );
        expect(surface.color, tokens.surface);
        final shape = surface.shape! as RoundedRectangleBorder;
        expect(shape.borderRadius, BorderRadius.circular(28));
        expect(shape.side.color, tokens.border);
        final barrier = tester.widget<AnimatedModalBarrier>(
          find.byType(AnimatedModalBarrier).last,
        );
        expect(barrier.color.value, tokens.scrim);
      });
    });
  }

  testWidgets('reduce motion opens the sheet in one frame', (tester) async {
    useView(tester, phone);
    reduceMotion(tester);
    final context = await pumpContext(tester);

    unawaited(showAppBottomSheet<void>(context, child: const Text('body')));
    await tester.pump();
    await tester.pump();

    expect(
      tester.getRect(find.byType(BottomSheet)).bottom,
      tester.view.physicalSize.height / tester.view.devicePixelRatio,
    );
  });

  group('the dialog', () {
    Finder surfaceOf(Finder dialog) =>
        find.descendant(of: dialog, matching: find.byType(Material)).first;

    for (final width in [600.0, 700.0, 900.0]) {
      testWidgets('is 480 wide in a ${width.round()} dp window', (
        tester,
      ) async {
        await openAt(tester, Size(width, 1000), const Text('body'));

        expect(dialogs, findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
        expect(tester.getSize(surfaceOf(dialogs)).width, 480);
      });
    }

    testWidgets('keeps the grabber\'s room above the body', (tester) async {
      await openAt(tester, const Size(700, 1000), const Text('body'));

      final gap =
          tester.getTopLeft(find.text('body')).dy -
          tester.getTopLeft(surfaceOf(dialogs)).dy;
      expect(gap, closeTo(18, 0.01));
    });

    testWidgets('is at most 88% of the window and scrolls past it', (
      tester,
    ) async {
      await openAt(
        tester,
        const Size(700, 1000),
        const SingleChildScrollView(child: SizedBox(height: 3000)),
      );

      expect(tester.getSize(surfaceOf(dialogs)).height, closeTo(880, 0.01));
    });

    testWidgets('hugs a short body', (tester) async {
      await openAt(tester, const Size(700, 1000), const SizedBox(height: 100));

      expect(tester.getSize(surfaceOf(dialogs)).height, lessThan(300));
    });

    testWidgets('pops the value its body chooses', (tester) async {
      useView(tester, const Size(700, 1000));
      final context = await pumpContext(tester);
      final result = showAppBottomSheet<String>(
        context,
        child: Builder(
          builder: (c) => TextButton(
            onPressed: () => Navigator.of(c).pop('picked'),
            child: const Text('pick'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('pick'));
      await tester.pumpAndSettle();

      expect(await result, 'picked');
      expect(dialogs, findsNothing);
    });

    testWidgets('a tap on the scrim dismisses it with null', (tester) async {
      useView(tester, const Size(700, 1000));
      final context = await pumpContext(tester);
      final result = showAppBottomSheet<String>(
        context,
        child: const Text('body'),
      );
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(await result, isNull);
      expect(dialogs, findsNothing);
    });

    testWidgets('reduce motion opens it in one frame', (tester) async {
      useView(tester, const Size(700, 1000));
      reduceMotion(tester);
      final context = await pumpContext(tester);

      unawaited(showAppBottomSheet<void>(context, child: const Text('body')));
      await tester.pump();
      await tester.pump();

      expect(tester.hasRunningAnimations, isFalse);
      expect(dialogs, findsOneWidget);
    });
  });

  group('which one opens', () {
    for (final (size, isDialog) in [
      (const Size(599, 1000), false),
      (const Size(600, 479), false),
      (const Size(600, 480), true),
      (const Size(844, 390), false),
      (const Size(390, 844), false),
      (const Size(1024, 768), true),
    ]) {
      final name = isDialog ? 'dialog' : 'sheet';
      testWidgets('${size.width.round()} x ${size.height.round()} is a $name', (
        tester,
      ) async {
        await openAt(tester, size, const Text('body'));

        expect(dialogs, isDialog ? findsOneWidget : findsNothing);
        expect(
          find.byType(BottomSheet),
          isDialog ? findsNothing : findsOneWidget,
        );
      });
    }

    for (final size in [phone, const Size(700, 1000)]) {
      testWidgets('${size.width.round()} wide goes to the root navigator', (
        tester,
      ) async {
        useView(tester, size);
        late BuildContext tab;
        await tester.pumpWidget(
          themed(
            Navigator(
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (c) {
                  tab = c;
                  return const SizedBox();
                },
              ),
            ),
          ),
        );

        unawaited(showAppBottomSheet<void>(tab, child: const Text('body')));
        await tester.pumpAndSettle();

        // A route on the tab's own navigator would sit under two Navigators.
        expect(
          find.ancestor(
            of: find.text('body'),
            matching: find.byType(Navigator),
          ),
          findsOneWidget,
        );
      });
    }
  });
}
