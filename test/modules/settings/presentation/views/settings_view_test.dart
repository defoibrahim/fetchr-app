import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/di/core_providers.dart';
import 'package:grabby/app/shared/domain/entities/quality.dart';
import 'package:grabby/app/shared/domain/entities/yt_dlp_status.dart';
import 'package:grabby/app/shared/download_prefs_provider.dart';
import 'package:grabby/app/shared/yt_dlp_provider.dart';
import 'package:grabby/app/theme/accent_provider.dart';
import 'package:grabby/app/theme/theme_mode_provider.dart';
import 'package:grabby/core/errors/error_messages.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/core/services/storage/app_storage.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/utils/scale.dart';
import 'package:grabby/core/widgets/app_icon.dart';
import 'package:grabby/core/widgets/segmented_pills.dart';
import 'package:grabby/modules/settings/di/settings_providers.dart';
import 'package:grabby/modules/settings/presentation/views/settings_view.dart';
import 'package:grabby/modules/settings/presentation/views/widgets/settings_section.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../core/widgets/widget_harness.dart';
import '../../../../support/fixtures.dart';
import '../../../../support/memory_storage.dart';
import '../../../../support/mocks.dart';

// Tall, so the whole view is on screen: `.h` scales with the height too.
const _tall = Size(375, 2400);

void main() {
  late MockYtDlpRepository repository;
  late MemoryStorage storage;
  late ProviderContainer container;

  YtDlpStatus status({
    String? version = '2026.10.01',
    DateTime? checkedAt,
    bool autoUpdate = true,
  }) => ytDlpStatus(
    version: version,
    checkedAt: checkedAt,
    autoUpdate: autoUpdate,
  );

  setUp(() {
    repository = MockYtDlpRepository();
    storage = MemoryStorage();
    when(() => repository.status()).thenAnswer((_) async => Ok(status()));
    when(
      () => repository.setAutoUpdate(any()),
    ).thenAnswer((_) async => const Ok<void>(null));
  });

  Future<void> pumpSettings(
    WidgetTester tester, {
    ThemeData? theme,
    Size size = _tall,
    TransitionBuilder? builder,
  }) async {
    useView(tester, size);
    container = ProviderContainer(
      overrides: [
        ytDlpRepositoryProvider.overrideWithValue(repository),
        appStorageProvider.overrideWithValue(storage),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: ScaleScope(
          child: MaterialApp(
            theme: theme ?? AppTheme.light(),
            builder: builder,
            home: const SettingsView(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  DownloadPrefs prefs() => container.read(downloadPrefsProvider);

  Finder switchOf(String title) => find.descendant(
    of: find.widgetWithText(SettingsSwitchRow, title),
    matching: find.byType(Switch),
  );

  bool switchValue(WidgetTester tester, String title) =>
      tester.widget<Switch>(switchOf(title)).value;

  SegmentedPills<T> pills<T>(WidgetTester tester) =>
      tester.widget<SegmentedPills<T>>(find.byType(SegmentedPills<T>));

  testWidgets('shows the title and the three sections', (tester) async {
    await pumpSettings(tester);

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('DOWNLOADS'), findsOneWidget);
    expect(find.text('APPEARANCE'), findsOneWidget);
    expect(find.text('DOWNLOAD ENGINE'), findsOneWidget);
  });

  testWidgets('renders in the dark theme at phone size', (tester) async {
    await pumpSettings(
      tester,
      theme: AppTheme.dark(),
      size: const Size(390, 844),
    );

    expect(find.text('Settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('width', () {
    testWidgets('from 600 dp the page is a centred column of at most 560', (
      tester,
    ) async {
      await pumpSettings(tester, size: const Size(700, 2400));

      final page = tester.getRect(find.byType(SingleChildScrollView));
      expect(page.width, 560);
      expect(page.center.dx, 350);
    });

    testWidgets('under 600 dp the page fills the window', (tester) async {
      await pumpSettings(tester, size: const Size(599, 2400));

      expect(tester.getSize(find.byType(SingleChildScrollView)).width, 599);
    });
  });

  group('default quality', () {
    testWidgets('offers every quality but the cover photo', (tester) async {
      await pumpSettings(tester);

      for (final quality in Quality.values.where((q) => q != Quality.cover)) {
        expect(
          find.text(quality.shortLabel),
          findsOneWidget,
          reason: quality.name,
        );
      }
      expect(find.text(Quality.cover.shortLabel), findsNothing);
      expect(
        pills<Quality>(tester).items.map((i) => i.$1),
        isNot(contains(Quality.cover)),
      );
    });

    testWidgets('selects the current choice', (tester) async {
      await pumpSettings(tester);
      expect(pills<Quality>(tester).selected, Quality.best);

      await container
          .read(downloadPrefsProvider.notifier)
          .setQuality(Quality.p480);
      await tester.pump();

      expect(pills<Quality>(tester).selected, Quality.p480);
    });

    testWidgets('tapping one updates the prefs and saves it', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text('720p'));
      await tester.pumpAndSettle();

      expect(prefs().quality, Quality.p720);
      expect(storage.values[StorageKeys.defaultQuality], 'p720');
      expect(pills<Quality>(tester).selected, Quality.p720);
    });
  });

  group('save folder', () {
    Future<void> openDialog(WidgetTester tester) async {
      await tester.tap(find.text('Save folder'));
      await tester.pumpAndSettle();
    }

    Future<void> submit(WidgetTester tester, String name) async {
      await tester.enterText(find.byType(TextFormField), name);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows where videos and audio go', (tester) async {
      await pumpSettings(tester);

      expect(find.text('Movies/Fetchr · Music/Fetchr'), findsOneWidget);
    });

    testWidgets('the paths read left to right under right-to-left text', (
      tester,
    ) async {
      await pumpSettings(tester, builder: rtl);

      final paths = find.text('Movies/Fetchr · Music/Fetchr');
      expect(Directionality.of(tester.element(paths)), TextDirection.rtl);
      expect(tester.widget<Text>(paths).textDirection, TextDirection.ltr);
    });

    testWidgets('the row ripples on the card, not under it', (tester) async {
      await pumpSettings(tester);

      final nearest = tester.widget<Material>(
        find
            .ancestor(
              of: find.widgetWithText(InkWell, 'Save folder'),
              matching: find.byType(Material),
            )
            .first,
      );

      expect(nearest.color, AppTheme.light().extension<AppTokens>()!.surface);
    });

    testWidgets('the dialog starts with the current name', (tester) async {
      await pumpSettings(tester);

      await openDialog(tester);

      final field = tester.widget<TextFormField>(find.byType(TextFormField));
      expect(field.controller?.text, 'Fetchr');
    });

    testWidgets('a valid name is saved trimmed and shown', (tester) async {
      await pumpSettings(tester);

      await openDialog(tester);
      await submit(tester, ' Clips ');

      expect(prefs().folder, 'Clips');
      expect(storage.values[StorageKeys.saveFolder], 'Clips');
      expect(find.text('Movies/Clips · Music/Clips'), findsOneWidget);
    });

    for (final (name, why) in [
      ('a/b', 'a slash'),
      ('.x', 'a leading dot'),
      ('   ', 'a blank name'),
      ('', 'an empty name'),
    ]) {
      testWidgets('rejects $why and saves nothing', (tester) async {
        await pumpSettings(tester);

        await openDialog(tester);
        await submit(tester, name);

        expect(find.byType(Dialog), findsOneWidget);
        expect(prefs().folder, DownloadPrefs.defaultFolder);
        expect(storage.values, isNot(contains(StorageKeys.saveFolder)));
      });
    }

    testWidgets('Cancel leaves the folder alone', (tester) async {
      await pumpSettings(tester);

      await openDialog(tester);
      await tester.enterText(find.byType(TextFormField), 'Other');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      expect(prefs().folder, DownloadPrefs.defaultFolder);
      expect(storage.values, isNot(contains(StorageKeys.saveFolder)));
    });

    testWidgets('saving the same name writes nothing', (tester) async {
      await pumpSettings(tester);

      await openDialog(tester);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(storage.values, isNot(contains(StorageKeys.saveFolder)));
    });
  });

  group('aria2c', () {
    const title = 'Faster downloads (aria2c)';

    testWidgets('is off by default and the switch turns it on', (tester) async {
      await pumpSettings(tester);
      expect(
        find.text('Splits large files into parallel parts'),
        findsOneWidget,
      );
      expect(switchValue(tester, title), isFalse);

      await tester.tap(switchOf(title));
      await tester.pumpAndSettle();

      expect(prefs().useAria2c, isTrue);
      expect(storage.values[StorageKeys.useAria2c], 'true');
      expect(switchValue(tester, title), isTrue);
    });

    testWidgets('shows a saved choice', (tester) async {
      storage = MemoryStorage({StorageKeys.useAria2c: 'true'});
      await pumpSettings(tester);
      await container.read(downloadPrefsProvider.notifier).load();
      await tester.pumpAndSettle();

      expect(switchValue(tester, title), isTrue);
    });
  });

  group('theme', () {
    testWidgets('has System, Dark and Light with the mode selected', (
      tester,
    ) async {
      await pumpSettings(tester);

      expect(find.text('System'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(pills<ThemeMode>(tester).selected, ThemeMode.system);
    });

    testWidgets('tapping a pill sets and saves the mode', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(container.read(themeModeProvider), ThemeMode.dark);
      expect(storage.values[StorageKeys.themeMode], 'dark');
      expect(pills<ThemeMode>(tester).selected, ThemeMode.dark);

      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      expect(container.read(themeModeProvider), ThemeMode.light);

      await tester.tap(find.text('System'));
      await tester.pumpAndSettle();
      expect(container.read(themeModeProvider), ThemeMode.system);
    });
  });

  group('accent', () {
    const names = ['Lime', 'Blue', 'Amber', 'Pink'];

    testWidgets('offers the four palette accents by name', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpSettings(tester);

      for (final name in names) {
        expect(find.bySemanticsLabel('$name accent'), findsOneWidget);
      }
      expect(AppPalette.accents, hasLength(names.length));
      handle.dispose();
    });

    testWidgets('the current accent is the selected button', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpSettings(tester);

      expect(
        tester.getSemantics(find.bySemanticsLabel('Lime accent')),
        isSemantics(
          label: 'Lime accent',
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          isInMutuallyExclusiveGroup: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Blue accent')),
        isSemantics(
          label: 'Blue accent',
          isButton: true,
          hasSelectedState: true,
          isSelected: false,
          isInMutuallyExclusiveGroup: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('tapping one sets, saves and selects it', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpSettings(tester);

      await tester.tap(find.bySemanticsLabel('Blue accent'));
      await tester.pumpAndSettle();

      final blue = AppPalette.accents[1].color;
      expect(container.read(accentProvider), blue);
      expect(storage.values[StorageKeys.accent], '${blue.toARGB32()}');
      expect(
        tester.getSemantics(find.bySemanticsLabel('Blue accent')),
        isSemantics(
          label: 'Blue accent',
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          isInMutuallyExclusiveGroup: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Lime accent')),
        isSemantics(
          label: 'Lime accent',
          isButton: true,
          hasSelectedState: true,
          isSelected: false,
          isInMutuallyExclusiveGroup: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('only the selected swatch has a check', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpSettings(tester);
      Finder checkIn(String name) => find.descendant(
        of: find.bySemanticsLabel('$name accent'),
        matching: find.byType(AppIcon),
      );
      expect(checkIn('Lime'), findsOneWidget);
      expect(checkIn('Blue'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Blue accent'));
      await tester.pumpAndSettle();

      expect(checkIn('Lime'), findsNothing);
      expect(checkIn('Blue'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('every swatch is at least a 44 dp target', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpSettings(tester, size: const Size(375, 812 * 3));

      for (final name in names) {
        final box = tester.getSize(find.bySemanticsLabel('$name accent'));
        expect(box.width, greaterThanOrEqualTo(44), reason: name);
        expect(box.height, greaterThanOrEqualTo(44), reason: name);
      }
      handle.dispose();
    });
  });

  group('yt-dlp version', () {
    testWidgets('shows the native version', (tester) async {
      await pumpSettings(tester);

      expect(find.text('yt-dlp 2026.10.01'), findsOneWidget);
    });

    testWidgets('shows "bundled" when native reports none', (tester) async {
      when(
        () => repository.status(),
      ).thenAnswer((_) async => Ok(status(version: null)));

      await pumpSettings(tester);

      expect(find.text('yt-dlp bundled'), findsOneWidget);
    });

    testWidgets('shows a placeholder while it loads', (tester) async {
      final gate = Completer<Result<YtDlpStatus>>();
      when(() => repository.status()).thenAnswer((_) => gate.future);
      useView(tester, _tall);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ytDlpRepositoryProvider.overrideWithValue(repository),
            appStorageProvider.overrideWithValue(storage),
          ],
          child: ScaleScope(
            child: MaterialApp(
              theme: AppTheme.light(),
              home: const SettingsView(),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Checking…'), findsOneWidget);
      expect(find.text('Never checked'), findsNothing);
      gate.complete(Ok(status()));
      await tester.pumpAndSettle();
      expect(find.text('yt-dlp 2026.10.01'), findsOneWidget);
      expect(find.text('Checking…'), findsNothing);
    });

    testWidgets('a failed read says so and leaves Update usable', (
      tester,
    ) async {
      when(
        () => repository.status(),
      ).thenAnswer((_) async => const Err<YtDlpStatus>(UnexpectedFailure()));
      when(
        () => repository.update(),
      ).thenAnswer((_) async => Ok(status(version: '2026.10.14')));
      await pumpSettings(tester);

      expect(find.text('Version unavailable'), findsOneWidget);
      expect(find.text('Update yt-dlp').hitTestable(), findsOneWidget);

      await tester.tap(find.text('Update yt-dlp'));
      await tester.pumpAndSettle();

      verify(() => repository.update()).called(1);
      expect(find.text('yt-dlp 2026.10.14'), findsOneWidget);
      expect(find.text('Version unavailable'), findsNothing);
    });

    testWidgets('shows when it was last checked', (tester) async {
      when(() => repository.status()).thenAnswer(
        (_) async => Ok(status(checkedAt: DateTime(2020, 3, 5, 9, 12))),
      );

      await pumpSettings(tester);

      expect(find.text('Last checked 5 Mar'), findsOneWidget);
    });

    testWidgets('says never checked without a timestamp', (tester) async {
      await pumpSettings(tester);

      expect(find.text('Never checked'), findsOneWidget);
      expect(find.text('Up to date'), findsNothing);
    });
  });

  group('update', () {
    testWidgets('goes idle, busy, then done with Up to date', (tester) async {
      final gate = Completer<Result<YtDlpStatus>>();
      when(() => repository.update()).thenAnswer((_) => gate.future);
      await pumpSettings(tester);
      expect(find.text('Update yt-dlp').hitTestable(), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.tap(find.text('Update yt-dlp'));
      await tester.pump();

      expect(find.text('Updating…').hitTestable(), findsOneWidget);
      expect(find.text('Update yt-dlp'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Downloading the latest release…'), findsOneWidget);
      expect(find.text('Up to date'), findsNothing);

      gate.complete(Ok(status(version: '2026.10.14')));
      await tester.pumpAndSettle();

      expect(find.text('Check again').hitTestable(), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Up to date'), findsOneWidget);
      expect(find.text('Updated just now'), findsOneWidget);
      expect(find.text('yt-dlp 2026.10.14'), findsOneWidget);
      expect(find.text('yt-dlp 2026.10.01'), findsNothing);
    });

    testWidgets('Check again runs another update', (tester) async {
      when(
        () => repository.update(),
      ).thenAnswer((_) async => Ok(status(version: '2026.10.14')));
      await pumpSettings(tester);

      await tester.tap(find.text('Update yt-dlp'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check again'));
      await tester.pumpAndSettle();

      verify(() => repository.update()).called(2);
      expect(find.text('Up to date'), findsOneWidget);
    });

    testWidgets('a second tap while updating is ignored', (tester) async {
      final gate = Completer<Result<YtDlpStatus>>();
      when(() => repository.update()).thenAnswer((_) => gate.future);
      await pumpSettings(tester);

      await tester.tap(find.text('Update yt-dlp'));
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      verify(() => repository.update()).called(1);
      gate.complete(Ok(status(version: '2026.10.14')));
      await tester.pumpAndSettle();
    });

    testWidgets('a network failure shows the connection copy and goes idle', (
      tester,
    ) async {
      when(() => repository.update()).thenAnswer(
        (_) async => const Err<YtDlpStatus>(
          NetworkFailure(ErrorMessages.ytDlpUpdateOffline),
        ),
      );
      await pumpSettings(tester);

      await tester.tap(find.text('Update yt-dlp'));
      await tester.pumpAndSettle();

      expect(
        find.text("Couldn't update yt-dlp. Check your connection."),
        findsOneWidget,
      );
      expect(find.text('Update yt-dlp').hitTestable(), findsOneWidget);
      expect(find.text('Up to date'), findsNothing);
      expect(find.text('yt-dlp 2026.10.01'), findsOneWidget);
      expect(find.text('Never checked'), findsOneWidget);
    });

    testWidgets('a busy failure shows its message', (tester) async {
      when(
        () => repository.update(),
      ).thenAnswer((_) async => const Err<YtDlpStatus>(YtDlpBusyFailure()));
      await pumpSettings(tester);

      await tester.tap(find.text('Update yt-dlp'));
      await tester.pumpAndSettle();

      expect(find.text(ErrorMessages.ytDlpBusy), findsOneWidget);
    });

    testWidgets('the button works again after a failure', (tester) async {
      var calls = 0;
      when(() => repository.update()).thenAnswer((_) async {
        calls++;
        return calls == 1
            ? const Err<YtDlpStatus>(NetworkFailure())
            : Ok(status(version: '2026.10.14'));
      });
      await pumpSettings(tester);

      await tester.tap(find.text('Update yt-dlp'));
      await tester.pumpAndSettle();
      // The failure snackbar can sit over the button until it times out.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Update yt-dlp'));
      await tester.pumpAndSettle();

      expect(calls, 2);
      expect(find.text('Up to date'), findsOneWidget);
    });

    testWidgets('an update started elsewhere shows busy and ignores taps', (
      tester,
    ) async {
      final gate = Completer<Result<YtDlpStatus>>();
      when(() => repository.update()).thenAnswer((_) => gate.future);
      await pumpSettings(tester);

      unawaited(container.read(ytDlpProvider.notifier).updateYtDlp());
      await tester.pump();

      expect(find.text('Updating…').hitTestable(), findsOneWidget);
      expect(find.text('Downloading the latest release…'), findsOneWidget);
      await tester.tap(find.text('Updating…'));
      await tester.pump();
      verify(() => repository.update()).called(1);

      gate.complete(Ok(status(version: '2026.10.14')));
      await tester.pumpAndSettle();
      expect(find.text('Check again').hitTestable(), findsOneWidget);
      expect(find.text('Up to date'), findsOneWidget);
    });

    testWidgets('a done phase set elsewhere shows Up to date here', (
      tester,
    ) async {
      when(
        () => repository.update(),
      ).thenAnswer((_) async => Ok(status(version: '2026.10.14')));
      await pumpSettings(tester);

      await container.read(ytDlpProvider.notifier).updateYtDlp();
      await tester.pumpAndSettle();

      expect(find.text('Check again').hitTestable(), findsOneWidget);
      expect(find.text('Up to date'), findsOneWidget);
    });
  });

  group('daily updates', () {
    const title = 'Check for updates daily';

    testWidgets('shows the native setting', (tester) async {
      await pumpSettings(tester);
      expect(find.text('On app start, at most once a day'), findsOneWidget);
      expect(switchValue(tester, title), isTrue);
    });

    testWidgets('shows it off', (tester) async {
      when(
        () => repository.status(),
      ).thenAnswer((_) async => Ok(status(autoUpdate: false)));

      await pumpSettings(tester);

      expect(switchValue(tester, title), isFalse);
    });

    testWidgets('the switch calls setAutoUpdate', (tester) async {
      await pumpSettings(tester);

      await tester.tap(switchOf(title));
      await tester.pumpAndSettle();

      verify(() => repository.setAutoUpdate(false)).called(1);
      expect(switchValue(tester, title), isFalse);

      await tester.tap(switchOf(title));
      await tester.pumpAndSettle();

      verify(() => repository.setAutoUpdate(true)).called(1);
      expect(switchValue(tester, title), isTrue);
    });

    testWidgets('a failure flips the switch back and says why', (tester) async {
      when(
        () => repository.setAutoUpdate(any()),
      ).thenAnswer((_) async => const Err<void>(UnexpectedFailure()));
      await pumpSettings(tester);

      await tester.tap(switchOf(title));
      await tester.pumpAndSettle();

      expect(switchValue(tester, title), isTrue);
      expect(find.text(ErrorMessages.unexpected), findsOneWidget);
    });

    testWidgets('is off limits while the status is unknown', (tester) async {
      when(
        () => repository.status(),
      ).thenAnswer((_) async => const Err<YtDlpStatus>(UnexpectedFailure()));

      await pumpSettings(tester);

      expect(tester.widget<Switch>(switchOf(title)).onChanged, isNull);
    });
  });
}
