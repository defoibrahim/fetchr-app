import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/di/core_providers.dart';
import 'package:grabby/core/platform/platform_traits.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/notification_hint.dart';
import 'package:mocktail/mocktail.dart';
import 'package:permission_handler/permission_handler.dart';

import 'downloads_view_harness.dart';

void main() {
  setUp(setUpDownloadsHarness);

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
      // iOS shows its notification prompt once; nothing posts before M6, so the
      // hint must not spend it.
      testWidgets('the notification hint follows asksNotificationPermission', (
        tester,
      ) async {
        when(
          () => permission.status(),
        ).thenAnswer((_) async => PermissionStatus.denied);
        await pumpWith(
          tester,
          const [],
          overrides: [platformTraitsProvider.overrideWithValue(traits)],
        );

        final shown = traits.asksNotificationPermission;
        expect(
          find.byType(NotificationHint),
          shown ? findsOneWidget : findsNothing,
        );
        expect(find.text('Allow'), shown ? findsOneWidget : findsNothing);
      });

      testWidgets('Delete file names $device and $word', (tester) async {
        await pumpWith(
          tester,
          [done('d', null, 'Cliffside')],
          overrides: [platformTraitsProvider.overrideWithValue(traits)],
        );
        await tester.longPress(find.text('Cliffside'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete file'));
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.text(
              '“Cliffside” will be removed from your $device and from $word.',
            ),
          ),
          findsOneWidget,
        );
      });
    });
  }
}
