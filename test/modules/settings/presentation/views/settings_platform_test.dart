import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/di/core_providers.dart';
import 'package:grabby/app/shared/domain/entities/yt_dlp_status.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/core/platform/platform_traits.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/utils/scale.dart';
import 'package:grabby/modules/settings/di/settings_providers.dart';
import 'package:grabby/modules/settings/presentation/views/settings_view.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../core/widgets/widget_harness.dart';
import '../../../../support/fixtures.dart';
import '../../../../support/memory_storage.dart';
import '../../../../support/mocks.dart';

// Tall, so the whole view is on screen: `.h` scales with the height too.
const _tall = Size(375, 2400);
const _running = '2026.10.01';
const _aria2c = 'Faster downloads (aria2c)';

void main() {
  late MockYtDlpRepository repository;

  YtDlpStatus status(String version) =>
      ytDlpStatus(version: version, checkedAt: DateTime(2026, 11, 14));

  setUp(() {
    repository = MockYtDlpRepository();
    when(
      () => repository.status(),
    ).thenAnswer((_) async => Ok(status(_running)));
  });

  Future<void> pumpOn(WidgetTester tester, PlatformTraits traits) async {
    useView(tester, _tall);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ytDlpRepositoryProvider.overrideWithValue(repository),
          appStorageProvider.overrideWithValue(MemoryStorage()),
          platformTraitsProvider.overrideWithValue(traits),
        ],
        child: ScaleScope(
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const SettingsView(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> updateTo(WidgetTester tester, String version) async {
    when(
      () => repository.update(),
    ).thenAnswer((_) async => Ok(status(version)));
    await tester.tap(find.text('Update yt-dlp'));
    await tester.pumpAndSettle();
  }

  Finder restartLine(String version) =>
      find.text('Updated to $version — restart Fetchr to use it');

  // The fonts' OFL and, on iOS, the bundled Python, FFmpeg and packages
  // (registerNativeLicenses) need a way in on both platforms.
  for (final traits in [PlatformTraits.android, PlatformTraits.ios]) {
    testWidgets('Open-source licences opens the licence page '
        '(${traits.galleryWord})', (tester) async {
      await pumpOn(tester, traits);

      await tester.tap(find.text('Open-source licences'));
      await tester.pumpAndSettle();

      expect(find.byType(LicensePage), findsOneWidget);
    });
  }

  group("platform traits keep Android's copy", () {
    testWidgets('the aria2c row is shown', (tester) async {
      await pumpOn(tester, PlatformTraits.android);

      expect(find.text(_aria2c), findsOneWidget);
      expect(
        find.text('Splits large files into parallel parts'),
        findsOneWidget,
      );
    });

    testWidgets('an update to a new version is in use at once', (tester) async {
      await pumpOn(tester, PlatformTraits.android);

      await updateTo(tester, '2026.10.26');

      expect(find.text('yt-dlp 2026.10.26'), findsOneWidget);
      expect(find.text('Updated just now'), findsOneWidget);
      expect(find.text('Up to date'), findsOneWidget);
      expect(find.textContaining('restart'), findsNothing);
    });
  });

  group('iOS traits', () {
    testWidgets('there is no aria2c row', (tester) async {
      await pumpOn(tester, PlatformTraits.ios);

      expect(find.text(_aria2c), findsNothing);
      expect(find.text('Splits large files into parallel parts'), findsNothing);
      expect(find.text('Save folder'), findsOneWidget);
    });

    testWidgets('a new version waits for a restart: the running one shows', (
      tester,
    ) async {
      await pumpOn(tester, PlatformTraits.ios);

      await updateTo(tester, '2026.10.26');

      expect(restartLine('2026.10.26'), findsOneWidget);
      expect(find.text('yt-dlp $_running'), findsOneWidget);
      expect(find.text('yt-dlp 2026.10.26'), findsNothing);
      expect(find.text('Updated just now'), findsNothing);
      expect(find.text('Up to date'), findsNothing);
      expect(find.text('Check again'), findsOneWidget);
    });

    testWidgets('checking again still says the restart is pending', (
      tester,
    ) async {
      await pumpOn(tester, PlatformTraits.ios);
      await updateTo(tester, '2026.10.26');

      await tester.tap(find.text('Check again'));
      await tester.pumpAndSettle();

      verify(() => repository.update()).called(2);
      expect(restartLine('2026.10.26'), findsOneWidget);
      expect(find.text('yt-dlp $_running'), findsOneWidget);
    });

    testWidgets('a failed Check again keeps the restart line', (tester) async {
      await pumpOn(tester, PlatformTraits.ios);
      await updateTo(tester, '2026.10.26');
      when(
        () => repository.update(),
      ).thenAnswer((_) async => const Err(NetworkFailure()));

      await tester.tap(find.text('Check again'));
      await tester.pumpAndSettle();

      expect(restartLine('2026.10.26'), findsOneWidget);
      expect(find.text('Update yt-dlp'), findsOneWidget);
      expect(find.text('Up to date'), findsNothing);
    });

    testWidgets('the running version back from an update is up to date', (
      tester,
    ) async {
      await pumpOn(tester, PlatformTraits.ios);

      await updateTo(tester, _running);

      expect(find.text('yt-dlp $_running'), findsOneWidget);
      expect(find.text('Updated just now'), findsOneWidget);
      expect(find.text('Up to date'), findsOneWidget);
      expect(find.textContaining('restart'), findsNothing);
    });
  });
}
