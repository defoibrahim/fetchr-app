import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/utils/scale.dart';

final themes = <String, ThemeData>{
  'light': AppTheme.light(),
  'dark': AppTheme.dark(),
};

Widget themed(Widget child, {ThemeData? theme}) {
  return ScaleScope(
    child: MaterialApp(
      theme: theme ?? AppTheme.light(),
      home: Scaffold(body: child),
    ),
  );
}

/// Sizes the test view to [size] at pixel ratio 1 until the test ends. The
/// default is screenutil's design size, which makes every `.w`, `.h` and `.r`
/// factor exactly 1.
void useView(WidgetTester tester, [Size size = designSize]) {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = size;
  addTearDown(tester.view.reset);
}

/// Pumps [child] as the body of a themed app on a [size] view at pixel ratio
/// 1, with the platform text scale at [textScale]. The default size is a
/// phone, so screenutil factors come out close to 1 but not exactly; pass
/// [designSize] to make them 1.
Future<void> pumpThemed(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.dark,
  Color accent = AppPalette.defaultAccent,
  Size size = const Size(390, 844),
  double textScale = 1,
}) {
  useView(tester, size);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  return tester.pumpWidget(
    themed(
      child,
      theme: brightness == Brightness.dark
          ? AppTheme.dark(accent)
          : AppTheme.light(accent),
    ),
  );
}

/// Pumps a themed app and returns a context under its theme, for tests of
/// `showAppBottomSheet`, `AppSnackbar` and the context extensions.
Future<BuildContext> pumpContext(
  WidgetTester tester, {
  ThemeData? theme,
}) async {
  late BuildContext context;
  await tester.pumpWidget(
    themed(
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ),
      theme: theme,
    ),
  );
  return context;
}

/// Turns the platform's "remove animations" setting on until the test ends,
/// which `MediaQuery.disableAnimationsOf` reads. Pump after calling it when
/// the widget is already on screen.
void reduceMotion(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

/// A `MaterialApp.builder` that flips the whole app to right to left.
Widget rtl(BuildContext _, Widget? child) =>
    Directionality(textDirection: TextDirection.rtl, child: child!);

/// The text direction [text] is laid out in: its own, else the one in scope.
TextDirection directionOf(WidgetTester tester, Finder text) =>
    tester.widget<Text>(text).textDirection ??
    Directionality.of(tester.element(text));
