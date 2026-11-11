import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/launch/launch_intro.dart';

import '../../support/launch_intro_harness.dart';

final _tagline = find.descendant(of: introOverlay, matching: find.byType(Wrap));

/// The tagline's words in order, and how visible each one is.
List<({String text, double opacity})> _words(WidgetTester tester) => [
  for (final word in tester.widgetList<Opacity>(
    find.descendant(of: _tagline, matching: find.byType(Opacity)),
  ))
    (
      text: ((word.child! as Transform).child! as Text).data!,
      opacity: word.opacity,
    ),
];

void main() {
  testWidgets('reads "Any link. Any format." under the tile', (tester) async {
    final gone = await pumpIntro(tester);

    expect(_words(tester).map((w) => w.text).join(), 'Any link. Any format.');
    expect(tester.getRect(_tagline).top, greaterThan(introCentre.bottom));
    for (final text in tester.widgetList<RichText>(
      find.descendant(of: _tagline, matching: find.byType(RichText)),
    )) {
      expect(
        text.text.style?.decoration,
        anyOf(isNull, TextDecoration.none),
        reason: 'no debug underline: the overlay text needs a Material',
      );
    }

    await releaseAndSettle(tester, gone);
  });

  testWidgets('stays hidden until the native splash is gone', (tester) async {
    final gone = await pumpIntro(tester);
    await tester.pump(const Duration(milliseconds: 500));

    expect(_words(tester).map((w) => w.opacity), everyElement(0));

    await releaseAndSettle(tester, gone);
  });

  testWidgets('rises in word by word, then holds before the tile leaves', (
    tester,
  ) async {
    final gone = await pumpIntro(tester);
    await releaseSplash(tester, gone);

    await tester.pump(const Duration(milliseconds: 120));
    final early = _words(tester).map((w) => w.opacity).toList();
    expect(early.first, greaterThan(0));
    expect(early.last, 0, reason: 'the last word has not started');
    for (var i = 1; i < early.length; i++) {
      expect(early[i], lessThanOrEqualTo(early[i - 1]));
    }

    await tester.pump(launchIntroReveal - const Duration(milliseconds: 120));
    expect(_words(tester).map((w) => w.opacity), everyElement(1));
    expect(tileRect(tester), introCentre, reason: 'read before it flies');

    await tester.pumpAndSettle();
  });

  testWidgets('fades out as the tile flies to the header', (tester) async {
    final gone = await pumpIntro(tester);
    await releaseSplash(tester, gone);

    await tester.pump(launchIntroReveal + launchIntroFlight ~/ 2);
    expect(_words(tester).map((w) => w.opacity), everyElement(0));

    await tester.pumpAndSettle();
  });
}
