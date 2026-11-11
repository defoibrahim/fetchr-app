import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:grabby/app/di/core_providers.dart';
import 'package:grabby/app/routes/app_router.dart';
import 'package:grabby/app/routes/app_routes.dart';
import 'package:grabby/app/shared/domain/entities/yt_dlp_status.dart';
import 'package:grabby/app/shared/notification_permission_provider.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/utils/scale.dart';
import 'package:grabby/modules/downloader/di/downloader_providers.dart';
import 'package:grabby/modules/downloader/domain/entities/download_task.dart';
import 'package:grabby/modules/library/di/library_providers.dart';
import 'package:grabby/modules/library/domain/entities/library_item.dart';
import 'package:grabby/modules/settings/di/settings_providers.dart';
import 'package:mocktail/mocktail.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:persistent_bottom_nav_bar_v2/persistent_bottom_nav_bar_v2.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'memory_storage.dart';
import 'mocks.dart';

/// The phone nav bar.
final navBar = find.byType(Style8BottomNavBar);

/// The phone nav bar's tabs, in order.
const navLabels = ['Home', 'Downloads', 'Library', 'Settings'];

/// A tab of the phone nav bar. Only the selected tab shows its label, so the
/// tab is found by its place in the bar.
Finder navTab(String label) {
  assert(navLabels.contains(label), label);
  return find
      .descendant(of: navBar, matching: find.byType(GestureDetector))
      .at(navLabels.indexOf(label));
}

int selectedNavTab(WidgetTester tester) =>
    tester.widget<Style8BottomNavBar>(navBar).navBarConfig.selectedIndex;

/// The three repositories behind the screens, answering "nothing yet", and a
/// notification permission that is granted. A test that needs another answer
/// re-stubs a mock before `pumpFakeApp`.
class FakeApp {
  FakeApp() {
    when(
      () => downloader.watchTasks(),
    ).thenAnswer((_) => Stream.value(const <DownloadTask>[]));
    when(
      () => library.list(any()),
    ).thenAnswer((_) async => const Ok(<LibraryItem>[]));
    when(
      () => ytDlp.status(),
    ).thenAnswer((_) async => const Ok(YtDlpStatus(autoUpdate: true)));
    when(
      () => notificationPermission.status(),
    ).thenAnswer((_) async => PermissionStatus.granted);
    when(
      () => notificationPermission.request(),
    ).thenAnswer((_) async => PermissionStatus.granted);
    when(
      () => notificationPermission.openSettings(),
    ).thenAnswer((_) async => true);
  }

  final downloader = MockDownloaderRepository();
  final library = MockLibraryRepository();
  final ytDlp = MockYtDlpRepository();
  final notificationPermission = MockNotificationPermission();
  final storage = MemoryStorage();
  late final GoRouter router;
}

/// Pumps the real [AppRouter] and every real screen over [app]'s mocks.
/// [overrides] add providers the mocks do not cover. A provider can be
/// overridden only once per container, so the ones the mocks already take
/// (the three repositories, the storage and the notification permission)
/// change by re-stubbing the mock on [app] instead. [size] is the logical
/// window (a 360 x 800 phone by default) and [builder] wraps the router the way
/// `MaterialApp.builder` does, for example to set a text direction.
Future<FakeApp> pumpFakeApp(
  WidgetTester tester, {
  FakeApp? app,
  String initialLocation = AppRoutes.home,
  ThemeData? theme,
  Size size = const Size(360, 800),
  TransitionBuilder? builder,
  List<Override> overrides = const [],
}) async {
  final fake = app ?? FakeApp();
  fake.router = AppRouter.create(initialLocation: initialLocation);
  addTearDown(fake.router.dispose);
  tester.view
    ..physicalSize = size * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  // Home reads the clipboard on its first frame.
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (_) async => null,
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  ReceiveSharingIntent.setMockValues(
    initialMedia: [],
    mediaStream: const Stream.empty(),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        downloaderRepositoryProvider.overrideWithValue(fake.downloader),
        libraryRepositoryProvider.overrideWithValue(fake.library),
        ytDlpRepositoryProvider.overrideWithValue(fake.ytDlp),
        appStorageProvider.overrideWithValue(fake.storage),
        notificationPermissionProvider.overrideWithValue(
          fake.notificationPermission,
        ),
        ...overrides,
      ],
      child: ScaleScope(
        child: MaterialApp.router(
          theme: theme ?? AppTheme.light(),
          routerConfig: fake.router,
          builder: builder,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}
