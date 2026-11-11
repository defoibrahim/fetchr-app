import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:grabby/app/app.dart';
import 'package:grabby/app/di/core_providers.dart';
import 'package:grabby/app/launch/launch_intro.dart';
import 'package:grabby/app/routes/app_router.dart';
import 'package:grabby/app/theme/accent_provider.dart';
import 'package:grabby/app/theme/system_bars.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:mocktail/mocktail.dart';

import '../core/widgets/widget_harness.dart';
import '../support/memory_storage.dart';
import '../support/mocks.dart';

final _blue = AppPalette.accents[1].color;

/// Pumps [App] over a one-page router, so no screen or repository is needed.
/// Returns a context taken from that page, which sits under the app's theme.
Future<BuildContext> _pumpApp(
  WidgetTester tester, {
  Brightness brightness = Brightness.dark,
  App app = const App(),
}) async {
  useView(tester);
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
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
  late BuildContext page;
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) {
          page = context;
          return const SizedBox();
        },
      ),
    ],
  );
  addTearDown(router.dispose);
  final host = MockFetchrHostApi();
  when(() => host.setAccentColor(any())).thenAnswer((_) async {});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        routerProvider.overrideWithValue(router),
        appStorageProvider.overrideWithValue(MemoryStorage()),
        fetchrHostApiProvider.overrideWithValue(host),
      ],
      child: app,
    ),
  );
  await tester.pumpAndSettle();
  return page;
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(App)));

void main() {
  setUpAll(() => registerFallbackValue(0));

  group('launch intro', () {
    testWidgets('is off without splashGone', (tester) async {
      await _pumpApp(tester);

      expect(find.byType(LaunchIntro), findsNothing);
    });

    testWidgets('covers the first screen until the splash is gone', (
      tester,
    ) async {
      final gone = Completer<void>();
      await _pumpApp(tester, app: App(splashGone: () => gone.future));
      expect(find.byKey(launchIntroOverlayKey), findsOneWidget);

      gone.complete();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byKey(launchIntroOverlayKey), findsNothing);
    });
  });

  group('theme', () {
    testWidgets('dark takes its primary from the accent', (tester) async {
      final page = await _pumpApp(tester);
      expect(
        Theme.of(page).colorScheme.primary,
        AppPalette.defaultAccent,
        reason: 'lime until the user picks another',
      );

      await _container(tester).read(accentProvider.notifier).setAccent(_blue);
      await tester.pumpAndSettle();

      expect(Theme.of(page).colorScheme.primary, _blue);
      expect(AppTokens.of(page).accent, _blue);
    });

    testWidgets('light keeps ink as the primary and shows the accent as '
        'primaryIcon', (tester) async {
      final page = await _pumpApp(tester, brightness: Brightness.light);
      await _container(tester).read(accentProvider.notifier).setAccent(_blue);
      await tester.pumpAndSettle();

      final tokens = AppTokens.of(page);
      expect(Theme.of(page).brightness, Brightness.light);
      expect(Theme.of(page).colorScheme.primary, tokens.text);
      expect(tokens.primaryIcon, _blue);
    });
  });

  group('system bars', () {
    for (final brightness in Brightness.values) {
      testWidgets('are styled from the active theme (${brightness.name})', (
        tester,
      ) async {
        await _pumpApp(tester, brightness: brightness);

        final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
          find.descendant(
            of: find.byType(SystemBars),
            matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
          ),
        );
        expect(region.value.systemNavigationBarColor, Colors.transparent);
        expect(
          region.value.statusBarIconBrightness,
          brightness == Brightness.dark ? Brightness.light : Brightness.dark,
        );
      });
    }
  });

  testWidgets('clamps the text scale at 1.3', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final page = await _pumpApp(tester);

    expect(MediaQuery.textScalerOf(page).scale(10), closeTo(13, 0.001));
  });
}
