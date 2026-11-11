import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:grabby/app/di/core_providers.dart';
import 'package:grabby/app/routes/app_routes.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/core/theme/theme.dart';
import 'package:grabby/core/utils/scale.dart';
import 'package:grabby/modules/downloader/di/downloader_providers.dart';
import 'package:grabby/modules/library/di/library_providers.dart';
import 'package:grabby/modules/library/domain/entities/library_item.dart';
import 'package:grabby/modules/library/presentation/providers/player_factory_provider.dart';
import 'package:grabby/modules/library/presentation/views/player_view.dart';
import 'package:grabby/modules/library/presentation/views/widgets/player_controls.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../core/widgets/widget_harness.dart';
import '../../../../support/fixtures.dart';
import '../../../../support/memory_storage.dart';
import '../../../../support/mocks.dart';

class MockMediaPlayer extends Mock implements Player {}

class MockMediaPlayerStream extends Mock implements PlayerStream {}

const videoKey = Key('video-surface');

final videoItem = libraryItem(
  uri: 'content://media/external/video/media/1',
  name: 'Desert drive at golden hour.mp4',
  sizeBytes: 5452595,
  durationMs: 768000,
  width: 1920,
  height: 1080,
  relativePath: 'Movies/Fetchr/',
  dateAdded: DateTime(2026, 10, 15, 16, 2),
);

final songItem = libraryItem(
  uri: 'content://media/external/audio/media/2',
  name: 'Late-night lo-fi set.mp3',
  mimeType: 'audio/mpeg',
  isAudio: true,
  sizeBytes: 6501171,
  relativePath: 'Music/Fetchr/',
  dateAdded: DateTime(2026, 1, 2, 9, 5),
);

String playerPath(LibraryItem item, [String? title]) =>
    AppRoutes.playerLocation(uri: item.uri, title: title ?? item.name);

late MockMediaPlayer player;
late MockLibraryRepository libraryRepository;
late MockDownloaderRepository downloader;
late List<String> events;
late StreamController<bool> playing;
late StreamController<Duration> position;
late StreamController<Duration> duration;
late StreamController<String> errors;
late GoRouter router;
late List<MethodCall> platformCalls;

void setUpPlayerHarness() {
  registerFallbackValue(Media('content://fallback'));
  registerFallbackValue(Duration.zero);
  events = [];
  playing = StreamController<bool>.broadcast();
  position = StreamController<Duration>.broadcast();
  duration = StreamController<Duration>.broadcast();
  errors = StreamController<String>.broadcast(
    onCancel: () => events.add('cancel errors'),
  );
  addTearDown(playing.close);
  addTearDown(position.close);
  addTearDown(duration.close);
  addTearDown(errors.close);

  final streams = MockMediaPlayerStream();
  when(() => streams.playing).thenAnswer((_) => playing.stream);
  when(() => streams.position).thenAnswer((_) => position.stream);
  when(() => streams.duration).thenAnswer((_) => duration.stream);
  when(() => streams.error).thenAnswer((_) => errors.stream);

  player = MockMediaPlayer();
  when(() => player.stream).thenReturn(streams);
  when(() => player.state).thenReturn(const PlayerState());
  when(() => player.open(any())).thenAnswer((_) async {});
  when(() => player.playOrPause()).thenAnswer((_) async {});
  when(() => player.seek(any())).thenAnswer((_) async {});
  when(() => player.dispose()).thenAnswer((_) async {
    events.add('dispose player');
  });

  libraryRepository = MockLibraryRepository();
  when(
    () => libraryRepository.list(any()),
  ).thenAnswer((_) async => Ok([videoItem, songItem]));
  downloader = MockDownloaderRepository();
  when(downloader.watchTasks).thenAnswer((_) => Stream.value(const []));
  platformCalls = [];
}

/// Opens the player over a stub library tab, as a push from the Library.
Future<void> pumpPlayer(
  WidgetTester tester,
  LibraryItem item, {
  String? title,
  Size size = designSize,
  TextDirection textDirection = TextDirection.ltr,
  Future<Result<List<LibraryItem>>> Function()? list,
}) async {
  useView(tester, size);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      platformCalls.add(call);
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  if (list != null) {
    when(() => libraryRepository.list(any())).thenAnswer((_) => list());
  }
  router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('library')),
      ),
      GoRoute(
        path: AppRoutes.player,
        builder: (_, state) => PlayerView(
          uri: state.uri.queryParameters['uri']!,
          title: state.uri.queryParameters['title'] ?? '',
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        libraryRepositoryProvider.overrideWithValue(libraryRepository),
        downloaderRepositoryProvider.overrideWithValue(downloader),
        appStorageProvider.overrideWithValue(MemoryStorage()),
        playerFactoryProvider.overrideWithValue(() => player),
        videoSurfaceFactoryProvider.overrideWithValue(
          (_) =>
              (_) => const SizedBox.expand(key: videoKey),
        ),
      ],
      child: ScaleScope(
        child: MaterialApp.router(
          theme: AppTheme.dark(),
          routerConfig: router,
          builder: textDirection == TextDirection.ltr
              ? null
              : (_, child) =>
                    Directionality(textDirection: textDirection, child: child!),
        ),
      ),
    ),
  );
  unawaited(router.push(playerPath(item, title)));
  await tester.pumpAndSettle();
}

Future<void> emit<T>(
  WidgetTester tester,
  StreamController<T> controller,
  T value,
) async {
  controller.add(value);
  // The first frame runs before the stream delivers the event.
  await tester.pump();
  await tester.pump();
}

Finder inControls(Finder finder) =>
    find.descendant(of: find.byType(PlayerControls), matching: finder);

double overlayOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(inControls(find.byType(AnimatedOpacity)).first)
    .opacity;

// A single tap waits out the double-tap window before it counts.
Future<void> tapMedia(WidgetTester tester, Offset at) async {
  await tester.tapAt(at);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 250));
}

Offset mediaPoint(WidgetTester tester, {required double xFraction}) {
  final rect = tester.getRect(find.byType(PlayerControls).first);
  // Near the top, clear of the buttons and the time row.
  return Offset(rect.left + rect.width * xFraction, rect.top + 16);
}
