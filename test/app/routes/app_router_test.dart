import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/gallery/gallery_view.dart';
import 'package:grabby/app/routes/app_router.dart';
import 'package:grabby/app/routes/app_routes.dart';
import 'package:grabby/app/shared/domain/entities/quality.dart';
import 'package:grabby/app/shell/app_shell.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/core/widgets/not_found_view.dart';
import 'package:grabby/modules/downloader/presentation/views/downloads_view.dart';
import 'package:grabby/modules/downloader/presentation/views/home_view.dart';
import 'package:grabby/modules/downloader/presentation/views/playlist_view.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/downloads_badge.dart';
import 'package:grabby/modules/downloader/presentation/views/widgets/format_sheet.dart';
import 'package:grabby/modules/library/presentation/views/library_view.dart';
import 'package:grabby/modules/settings/presentation/views/settings_view.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fake_app.dart';
import '../../support/fixtures.dart';

Finder _tab(String label) => navTab(label);

int _selectedTab(WidgetTester tester) => selectedNavTab(tester);

String _location(FakeApp app) =>
    app.router.routeInformationProvider.value.uri.toString();

void main() {
  setUpAll(() => registerFallbackValue(''));

  group('shell', () {
    testWidgets('opens on Home with four tabs', (tester) async {
      await pumpFakeApp(tester);

      expect(find.byType(HomeView), findsOneWidget);
      expect(_selectedTab(tester), 0);
      for (final label in navLabels) {
        expect(_tab(label), findsOneWidget);
      }
    });

    testWidgets('hands the shell the downloads badge', (tester) async {
      await pumpFakeApp(tester);

      final shell = tester.widget<AppShell>(find.byType(AppShell));
      expect(shell.downloadsBadge, isA<DownloadsBadge>());
    });

    testWidgets('each tab shows its own screen and location', (tester) async {
      final app = await pumpFakeApp(tester);

      for (final (label, view, path) in [
        ('Downloads', DownloadsView, AppRoutes.downloads),
        ('Library', LibraryView, AppRoutes.library),
        ('Settings', SettingsView, AppRoutes.settings),
        ('Home', HomeView, AppRoutes.home),
      ]) {
        await tester.tap(_tab(label));
        await tester.pumpAndSettle();

        expect(find.byType(view), findsOneWidget, reason: label);
        expect(_location(app), path, reason: label);
      }
    });

    testWidgets('a deep link selects its tab', (tester) async {
      await pumpFakeApp(tester, initialLocation: AppRoutes.settings);

      expect(find.byType(SettingsView), findsOneWidget);
      expect(_selectedTab(tester), 3);
    });

    testWidgets('a sheet opened from a tab covers the bottom bar', (
      tester,
    ) async {
      final app = FakeApp();
      when(() => app.downloader.fetchInfo(any())).thenAnswer(
        (_) async => Ok(
          mediaInfo(
            title: 'A clip',
            options: formatOptions(const [Quality.best, Quality.mp3]),
          ),
        ),
      );
      await pumpFakeApp(tester, app: app);
      expect(_tab('Settings').hitTestable(), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'https://example.com/v');
      await tester.pump();
      await tester.tap(find.text('Get formats'));
      await tester.pumpAndSettle();

      expect(find.byType(FormatSheet), findsOneWidget);
      expect(_tab('Settings').hitTestable(), findsNothing);
    });

    testWidgets('selecting Library reloads it, other tabs do not', (
      tester,
    ) async {
      final app = await pumpFakeApp(tester, initialLocation: AppRoutes.library);
      verify(() => app.library.list(any())).called(1);

      await tester.tap(_tab('Home'));
      await tester.pumpAndSettle();
      await tester.tap(_tab('Settings'));
      await tester.pumpAndSettle();
      verifyNever(() => app.library.list(any()));

      await tester.tap(_tab('Library'));
      await tester.pumpAndSettle();
      verify(() => app.library.list(any())).called(1);
    });
  });

  group('playlist', () {
    testWidgets('with a MediaInfo extra shows PlaylistView over the shell', (
      tester,
    ) async {
      final app = await pumpFakeApp(tester);
      final info = mediaInfo(title: 'Road trip mix', isPlaylist: true);

      unawaited(app.router.push(AppRoutes.playlist, extra: info));
      await tester.pumpAndSettle();

      final view = tester.widget<PlaylistView>(find.byType(PlaylistView));
      expect(view.info, info);
      expect(find.text('Road trip mix'), findsOneWidget);
      expect(navBar, findsNothing);
    });

    testWidgets('without one shows NotFoundView', (tester) async {
      final app = await pumpFakeApp(tester);

      unawaited(app.router.push(AppRoutes.playlist));
      await tester.pumpAndSettle();

      expect(find.byType(PlaylistView), findsNothing);
      expect(find.byType(NotFoundView), findsOneWidget);
    });

    testWidgets('with an extra of another type shows NotFoundView', (
      tester,
    ) async {
      final app = await pumpFakeApp(tester);

      unawaited(app.router.push(AppRoutes.playlist, extra: 'nope'));
      await tester.pumpAndSettle();

      expect(find.byType(NotFoundView), findsOneWidget);
    });
  });

  group('gallery', () {
    testWidgets('is a route in debug builds', (tester) async {
      expect(kDebugMode, isTrue);
      final app = await pumpFakeApp(tester);

      app.router.go(AppRoutes.gallery);
      // Not pumpAndSettle: the gallery's spinners never stop.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(GalleryView), findsOneWidget);
      expect(navBar, findsNothing);
    });
  });

  group('player', () {
    testWidgets('without a uri shows NotFoundView and Go home returns', (
      tester,
    ) async {
      final app = await pumpFakeApp(
        tester,
        initialLocation: '${AppRoutes.player}?title=Clip',
      );

      expect(find.byType(NotFoundView), findsOneWidget);
      expect(navBar, findsNothing);

      await tester.tap(find.text('Go home'));
      await tester.pumpAndSettle();

      expect(find.byType(NotFoundView), findsNothing);
      expect(find.byType(HomeView), findsOneWidget);
      expect(_location(app), AppRoutes.home);
    });

    testWidgets('an empty uri is missing too', (tester) async {
      await pumpFakeApp(tester, initialLocation: '${AppRoutes.player}?uri=');

      expect(find.byType(NotFoundView), findsOneWidget);
    });
  });

  testWidgets('an unknown path shows NotFoundView and Go home returns home', (
    tester,
  ) async {
    final app = await pumpFakeApp(tester, initialLocation: '/missing');
    expect(find.byType(NotFoundView), findsOneWidget);
    verifyNever(() => app.library.list(any()));

    await tester.tap(find.text('Go home'));
    await tester.pumpAndSettle();

    expect(find.byType(NotFoundView), findsNothing);
    expect(find.byType(HomeView), findsOneWidget);
    expect(_selectedTab(tester), 0);
  });

  test('routerProvider builds the router at home and is a single instance', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final router = container.read(routerProvider);

    expect(router.routeInformationProvider.value.uri.path, AppRoutes.home);
    expect(container.read(routerProvider), same(router));
  });
}
