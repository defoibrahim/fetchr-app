import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:grabby/app/di/core_providers.dart';
import 'package:grabby/app/routes/app_routes.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/utils/scale.dart';
import 'package:grabby/modules/library/di/library_providers.dart';
import 'package:grabby/modules/library/domain/entities/library_item.dart';
import 'package:grabby/modules/library/presentation/views/library_view.dart';
import 'package:grabby/modules/library/presentation/views/widgets/library_card.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../core/widgets/widget_harness.dart';
import '../../../../support/fixtures.dart';
import '../../../../support/memory_storage.dart';
import '../../../../support/mocks.dart';

final clipItem = libraryItem(
  uri: 'content://media/external/video/media/1',
  name: 'Clip one & two.mp4',
  sizeBytes: 1572864,
  durationMs: 65000,
  width: 1920,
  height: 1080,
  relativePath: 'Movies/Fetchr/',
  dateAdded: DateTime(2026, 1, 2),
);

final songItem = libraryItem(
  uri: 'content://media/external/audio/media/2',
  name: 'Song.mp3',
  mimeType: 'audio/mpeg',
  isAudio: true,
  sizeBytes: 6501171,
  durationMs: 271000,
  relativePath: 'Music/Fetchr/',
  dateAdded: DateTime(2026, 1, 1),
);

final bothItems = [clipItem, songItem];

late MockLibraryRepository repository;
late List<Uri> pushed;

void setUpLibraryHarness() {
  repository = MockLibraryRepository();
  pushed = [];
  when(
    () => repository.thumbnail(any(), any(), any()),
  ).thenAnswer((_) async => const Ok(null));
}

void stubList(Future<Result<List<LibraryItem>>> Function() answer) {
  when(() => repository.list(any())).thenAnswer((_) => answer());
}

// `ticking` stands in for the shell, which turns TickerMode off for a
// hidden tab.
Future<void> pumpLibrary(
  WidgetTester tester, {
  ValueListenable<bool>? ticking,
  Size size = designSize,
  TextDirection textDirection = TextDirection.ltr,
}) async {
  useView(tester, size);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => ticking == null
            ? const LibraryView()
            : ValueListenableBuilder(
                valueListenable: ticking,
                builder: (_, enabled, child) =>
                    TickerMode(enabled: enabled, child: child!),
                child: const LibraryView(),
              ),
      ),
      GoRoute(
        path: AppRoutes.player,
        builder: (_, state) {
          pushed.add(state.uri);
          return const Scaffold(body: Text('player'));
        },
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (_, _) => const Scaffold(body: Text('home')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        libraryRepositoryProvider.overrideWithValue(repository),
        appStorageProvider.overrideWithValue(MemoryStorage()),
      ],
      child: ScaleScope(
        child: MaterialApp.router(
          theme: AppTheme.light(),
          routerConfig: router,
          builder: textDirection == TextDirection.ltr
              ? null
              : (_, child) =>
                    Directionality(textDirection: textDirection, child: child!),
        ),
      ),
    ),
  );
  // The first frame starts the load; the second shows its result.
  await tester.pump();
  await tester.pump();
}

List<LibraryItem> shown(WidgetTester tester) => [
  for (final card in tester.widgetList<LibraryCard>(find.byType(LibraryCard)))
    card.item,
];

Future<void> openMenu(WidgetTester tester, [int index = 0]) async {
  await tester.tap(find.byTooltip('More actions').at(index));
  await tester.pumpAndSettle();
}

Future<void> pickFilter(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(ChoiceChip, label));
  await tester.pumpAndSettle();
}
