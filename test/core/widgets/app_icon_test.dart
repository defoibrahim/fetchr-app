import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/gen/assets.gen.dart';
import 'package:grabby/core/widgets/app_icon.dart';

import 'widget_harness.dart';

SvgPicture _picture(WidgetTester tester) =>
    tester.widget<SvgPicture>(find.byType(SvgPicture));

ColorFilter _tint(Color color) => ColorFilter.mode(color, BlendMode.srcIn);

void main() {
  testWidgets('renders an SvgPicture at the given size and colour', (
    tester,
  ) async {
    await tester.pumpWidget(
      themed(
        AppIcon(
          Assets.icons.download,
          size: 18,
          color: const Color(0xFFC8F03C),
        ),
      ),
    );

    final picture = _picture(tester);
    expect(picture.width, 18);
    expect(picture.height, 18);
    expect(picture.colorFilter, _tint(const Color(0xFFC8F03C)));
    expect((picture.bytesLoader as SvgAssetLoader).theme, isNull);
  });

  testWidgets('takes the IconTheme size and colour by default', (tester) async {
    await tester.pumpWidget(
      themed(
        IconTheme(
          data: const IconThemeData(size: 31, color: Color(0xFFFF0000)),
          child: AppIcon(Assets.icons.home),
        ),
      ),
    );

    final picture = _picture(tester);
    expect(picture.width, 31);
    expect(picture.height, 31);
    expect(picture.colorFilter, _tint(const Color(0xFFFF0000)));
  });

  testWidgets('paints strokes and fills in the tint, nothing else', (
    tester,
  ) async {
    const tint = Color(0xFFFF0000);
    final boundary = GlobalKey();
    await tester.pumpWidget(
      themed(
        Align(
          alignment: Alignment.topLeft,
          child: RepaintBoundary(
            key: boundary,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(Assets.icons.home, size: 48, color: tint),
                AppIcon(Assets.icons.play, size: 48, color: tint),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();

    final pixels = await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return data!.buffer.asUint8List();
    });

    var solid = 0;
    for (var i = 0; i < pixels!.length; i += 4) {
      if (pixels[i + 3] != 255) continue;
      solid++;
      expect([pixels[i], pixels[i + 1], pixels[i + 2]], [255, 0, 0]);
    }
    expect(solid, greaterThan(0));
  });

  testWidgets('is excluded from semantics without a label', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(themed(AppIcon(Assets.icons.close)));

    expect(_picture(tester).excludeFromSemantics, isTrue);
    expect(find.bySemanticsLabel('Clear URL'), findsNothing);
    handle.dispose();
  });

  testWidgets('carries the semantic label when given', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      themed(AppIcon(Assets.icons.close, semanticLabel: 'Clear URL')),
    );

    expect(_picture(tester).excludeFromSemantics, isFalse);
    expect(find.bySemanticsLabel('Clear URL'), findsOneWidget);
    handle.dispose();
  });

  test('every icon asset parses', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final icon in Assets.icons.values) {
      await SvgAssetLoader(icon.path).loadBytes(null);
    }
  });
}
