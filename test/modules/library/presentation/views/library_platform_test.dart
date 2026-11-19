import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/di/core_providers.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/core/platform/platform_traits.dart';
import 'package:grabby/modules/library/domain/entities/library_item.dart';

import '../../../../support/fixtures.dart';
import 'library_view_harness.dart';

void main() {
  setUp(setUpLibraryHarness);

  Future<void> pumpOn(WidgetTester tester, PlatformTraits traits) =>
      pumpLibrary(
        tester,
        overrides: [platformTraitsProvider.overrideWithValue(traits)],
      );

  Future<void> openDeleteDialog(WidgetTester tester) async {
    await openMenu(tester);
    await tester.tap(find.text('Delete file'));
    await tester.pumpAndSettle();
  }

  for (final (name, traits, device, word) in [
    (
      "platform traits keep Android's copy",
      PlatformTraits.android,
      'phone',
      'Gallery',
    ),
    ('iOS traits', PlatformTraits.ios, 'device', 'Files'),
  ]) {
    group(name, () {
      testWidgets('the empty state names $word', (tester) async {
        stubList(() async => const Ok(<LibraryItem>[]));
        await pumpOn(tester, traits);

        expect(
          find.text(
            'Finished videos and audio are saved to Movies/Fetchr and '
            'Music/Fetchr and show up here and in $word.',
          ),
          findsOneWidget,
        );
      });

      testWidgets('the delete dialog names $device and $word', (tester) async {
        stubList(() async => Ok(bothItems));
        await pumpOn(tester, traits);

        await openDeleteDialog(tester);

        expect(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.text(
              '“Clip one & two.mp4” will be removed from your $device and '
              'from $word.',
            ),
          ),
          findsOneWidget,
        );
      });

      testWidgets('the playlist dialog names $device', (tester) async {
        final a = libraryItem(
          uri: 'content://a',
          name: 'A.mp4',
          relativePath: 'Movies/Fetchr/Trip/',
        );
        final b = libraryItem(
          uri: 'content://b',
          name: 'B.mp4',
          relativePath: 'Movies/Fetchr/Trip/',
        );
        stubList(() async => Ok([a, b]));
        await pumpOn(tester, traits);

        await openMenu(tester);
        await tester.tap(find.text('Delete playlist'));
        await tester.pumpAndSettle();

        expect(
          find.text(
            'All 2 files of "Trip" will be removed from your $device. '
            "This can't be undone.",
          ),
          findsOneWidget,
        );
      });
    });
  }
}
