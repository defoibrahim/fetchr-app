import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/modules/library/presentation/views/widgets/library_card.dart';

import '../../../../support/app_fonts.dart';
import '../../../../support/fixtures.dart';
import 'library_view_harness.dart';

// The grid gives every card the height LibraryCard.heightFor predicts; with the
// shipped fonts a line can round a pixel taller than its font size times its
// height, so this runs on the real fonts, not the test font.
void main() {
  setUpAll(loadAppFonts);
  setUp(setUpLibraryHarness);

  final twoLines = libraryItem(
    uri: 'content://x/1',
    // yt-dlp writes | as the full-width ｜, which Geist does not have.
    name: 'What is Flutter？ ｜ Explained [I9ceqw5Ny-4].mp4',
    sizeBytes: 48 * 1024 * 1024,
    width: 1920,
    height: 1080,
  );

  for (final size in const [
    Size(320, 640),
    Size(360, 800),
    Size(384, 853),
    Size(393, 873),
    Size(411, 914),
    Size(430, 932),
    // Three columns, then four, on a window that is no longer scaled.
    Size(600, 1000),
    Size(840, 1000),
    Size(900, 1000),
  ]) {
    for (final scale in const [1.0, 1.1, 1.15, 1.2, 1.3]) {
      testWidgets('a card fits its cell at ${size.width.toInt()} dp, x$scale', (
        tester,
      ) async {
        stubList(() async => Ok([twoLines, songItem]));
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await pumpLibrary(tester, size: size);

        expect(tester.takeException(), isNull);
        expect(find.byType(LibraryCard), findsNWidgets(2));
      });
    }
  }

  // The test font stands in for the fallback, so only the strut proves the fit
  // on a device: without it a fallback glyph makes its line taller.
  testWidgets('both lines force the strut height', (tester) async {
    stubList(() async => Ok([twoLines]));
    await pumpLibrary(tester);

    final texts = tester.widgetList<Text>(
      find.descendant(
        of: find.byType(LibraryCard),
        matching: find.byType(Text),
      ),
    );
    final struts = [
      for (final text in texts)
        if (text.data == twoLines.name || text.maxLines == 1) text.strutStyle,
    ];
    expect(struts, hasLength(greaterThanOrEqualTo(2)));
    expect(struts.every((s) => s?.forceStrutHeight ?? false), isTrue);
  });
}
