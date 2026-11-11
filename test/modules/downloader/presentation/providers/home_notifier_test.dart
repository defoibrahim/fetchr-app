import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/shared/domain/entities/quality.dart';
import 'package:grabby/app/shared/download_prefs_provider.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/core/usecase/base_use_case.dart';
import 'package:grabby/modules/downloader/di/downloader_providers.dart';
import 'package:grabby/modules/downloader/domain/entities/download_request.dart';
import 'package:grabby/modules/downloader/domain/entities/format_option.dart';
import 'package:grabby/modules/downloader/domain/entities/media_info.dart';
import 'package:grabby/modules/downloader/presentation/providers/home_notifier.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../support/mocks.dart';

void main() {
  const video = MediaInfo(
    url: 'https://example.com/v/1',
    title: 'One',
    thumbnail: 'https://example.com/v/1.jpg',
    uploader: 'Uploader',
    durationSec: 754,
    isPlaylist: false,
    options: [
      FormatOption(quality: Quality.best),
      FormatOption(quality: Quality.mp3),
    ],
    entries: [],
  );
  const entryA = PlaylistEntry(
    url: 'https://example.com/v/a',
    title: 'A',
    thumbnail: 'https://example.com/v/a.jpg',
    durationSec: 61,
  );
  const entryB = PlaylistEntry(url: 'https://example.com/v/b', title: 'B');
  const entryC = PlaylistEntry(url: 'https://example.com/v/c', title: 'C');
  const playlist = MediaInfo(
    url: 'https://example.com/list',
    title: 'List',
    uploader: 'Curator',
    isPlaylist: true,
    options: [
      FormatOption(quality: Quality.best),
      FormatOption(quality: Quality.mp3),
    ],
    entries: [entryA, entryB, entryC],
  );
  const failure = UnsupportedSiteFailure();
  const prefs = DownloadPrefs(
    quality: Quality.p720,
    folder: 'Music',
    useAria2c: true,
  );

  late MockFetchMediaInfoUseCase fetchInfo;
  late MockEnqueueDownloadsUseCase enqueue;
  late MockGetFreeSpaceUseCase freeSpace;
  late ProviderContainer container;

  AsyncValue<MediaInfo?> state() => container.read(homeNotifierProvider);

  HomeNotifier notifier() => container.read(homeNotifierProvider.notifier);

  setUpAll(() {
    registerFallbackValue(<DownloadRequest>[]);
    registerFallbackValue(const NoParams());
  });

  setUp(() {
    fetchInfo = MockFetchMediaInfoUseCase();
    enqueue = MockEnqueueDownloadsUseCase();
    freeSpace = MockGetFreeSpaceUseCase();
    container = ProviderContainer(
      overrides: [
        fetchMediaInfoUseCaseProvider.overrideWithValue(fetchInfo),
        enqueueDownloadsUseCaseProvider.overrideWithValue(enqueue),
        getFreeSpaceUseCaseProvider.overrideWithValue(freeSpace),
        downloadPrefsProvider.overrideWith(() => FixedPrefs(prefs)),
      ],
    );
    when(() => enqueue(any())).thenAnswer((_) async => const Ok<void>(null));
    when(
      () => freeSpace(const NoParams()),
    ).thenAnswer((_) async => const Ok(1000));
    // An autoDispose provider lives only while something listens to it.
    container.listen(homeNotifierProvider, (_, _) {});
  });

  tearDown(() => container.dispose());

  group('fetch', () {
    test('starts empty', () {
      expect(state().value, isNull);
      expect(state().isLoading, isFalse);
    });

    test('goes loading -> data', () async {
      final pending = Completer<Result<MediaInfo>>();
      when(() => fetchInfo('u')).thenAnswer((_) => pending.future);

      final fetching = notifier().fetch('u');
      expect(state().isLoading, isTrue);

      pending.complete(const Ok(video));
      await fetching;

      expect(state().requireValue, video);
      expect(state().isLoading, isFalse);
    });

    test('a failure lands in state and a second fetch recovers', () async {
      when(() => fetchInfo('u')).thenAnswer((_) async => const Err(failure));
      await notifier().fetch('u');

      expect(state().hasError, isTrue);
      expect(state().error, failure);

      when(() => fetchInfo('u')).thenAnswer((_) async => const Ok(video));
      await notifier().fetch('u');

      expect(state().requireValue, video);
    });

    test('an older fetch that lands last is dropped', () async {
      final first = Completer<Result<MediaInfo>>();
      final second = Completer<Result<MediaInfo>>();
      when(() => fetchInfo('a')).thenAnswer((_) => first.future);
      when(() => fetchInfo('b')).thenAnswer((_) => second.future);

      final a = notifier().fetch('a');
      final b = notifier().fetch('b');
      second.complete(const Ok(playlist));
      await b;
      first.complete(const Ok(video));
      await a;

      expect(state().requireValue, playlist);
    });

    test('an older failure cannot overwrite a newer result', () async {
      final first = Completer<Result<MediaInfo>>();
      when(() => fetchInfo('a')).thenAnswer((_) => first.future);
      when(() => fetchInfo('b')).thenAnswer((_) async => const Ok(video));

      final a = notifier().fetch('a');
      await notifier().fetch('b');
      first.complete(const Err(failure));
      await a;

      expect(state().requireValue, video);
    });

    test('a result that lands after dispose is dropped', () async {
      final pending = Completer<Result<MediaInfo>>();
      when(() => fetchInfo('u')).thenAnswer((_) => pending.future);
      final disposed = ProviderContainer(
        overrides: [fetchMediaInfoUseCaseProvider.overrideWithValue(fetchInfo)],
      );
      final seen = <AsyncValue<MediaInfo?>>[];
      disposed.listen(homeNotifierProvider, (_, next) => seen.add(next));
      final fetching = disposed.read(homeNotifierProvider.notifier).fetch('u');

      disposed.dispose();
      pending.complete(const Ok(video));
      await fetching;

      expect(seen.last.isLoading, isTrue);
    });
  });

  group('clear', () {
    test('resets the state', () async {
      when(() => fetchInfo('u')).thenAnswer((_) async => const Ok(video));
      await notifier().fetch('u');

      notifier().clear();

      expect(state().value, isNull);
    });

    test('clears an error', () async {
      when(() => fetchInfo('u')).thenAnswer((_) async => const Err(failure));
      await notifier().fetch('u');
      expect(state().hasError, isTrue);

      notifier().clear();

      expect(state().hasError, isFalse);
      expect(state().value, isNull);
    });

    test('drops a fetch still in flight', () async {
      final pending = Completer<Result<MediaInfo>>();
      when(() => fetchInfo('u')).thenAnswer((_) => pending.future);

      final fetching = notifier().fetch('u');
      notifier().clear();
      pending.complete(const Ok(video));
      await fetching;

      expect(state().value, isNull);
      expect(state().isLoading, isFalse);
    });
  });

  group('download', () {
    List<DownloadRequest> enqueued() =>
        verify(() => enqueue(captureAny())).captured.single
            as List<DownloadRequest>;

    test(
      'a video becomes one request using the saved prefs and the info',
      () async {
        final result = await notifier().download(video, Quality.p1080);

        expect(result, const Ok<void>(null));
        expect(enqueued(), [
          DownloadRequest(
            url: video.url,
            title: video.title,
            thumbnail: video.thumbnail,
            quality: Quality.p1080,
            folder: prefs.folder,
            useAria2c: prefs.useAria2c,
            uploader: 'Uploader',
            durationSec: 754,
          ),
        ]);
      },
    );

    test('hands back the use case failure', () async {
      when(() => enqueue(any())).thenAnswer((_) async => const Err(failure));

      final result = await notifier().download(video, Quality.best);

      expect(result, const Err<void>(failure));
    });
  });

  group('storageShortfall', () {
    MediaInfo sized(int? bytes) => MediaInfo(
      url: 'https://example.com/v/1',
      title: 'One',
      isPlaylist: false,
      options: [FormatOption(quality: Quality.p720, sizeBytes: bytes)],
      entries: const [],
    );

    test('null when the pick fits, even to the last byte', () async {
      expect(
        await notifier().storageShortfall(sized(999), Quality.p720),
        isNull,
      );
      expect(
        await notifier().storageShortfall(sized(1000), Quality.p720),
        isNull,
      );
    });

    test('the needed and free bytes when it does not fit', () async {
      expect(await notifier().storageShortfall(sized(1001), Quality.p720), (
        needed: 1001,
        free: 1000,
      ));
    });

    test('an unknown size is not checked and free space is not read', () async {
      expect(
        await notifier().storageShortfall(sized(null), Quality.p720),
        isNull,
      );
      expect(
        await notifier().storageShortfall(sized(5000), Quality.best),
        isNull,
      );
      verifyNever(() => freeSpace(any()));
    });

    test('a failed free space read never blocks the download', () async {
      when(
        () => freeSpace(const NoParams()),
      ).thenAnswer((_) async => const Err(failure));

      expect(
        await notifier().storageShortfall(sized(5000), Quality.p720),
        isNull,
      );
    });
  });

  group('downloadPlaylist', () {
    List<DownloadRequest> enqueued() =>
        verify(() => enqueue(captureAny())).captured.single
            as List<DownloadRequest>;

    test('one request per picked index with the playlist fields', () async {
      final result = await notifier().downloadPlaylist(playlist, Quality.mp3, [
        0,
        2,
      ]);

      expect(result, const Ok(2));
      expect(enqueued(), [
        DownloadRequest(
          url: entryA.url,
          title: entryA.title,
          thumbnail: entryA.thumbnail,
          quality: Quality.mp3,
          folder: prefs.folder,
          useAria2c: prefs.useAria2c,
          uploader: 'Curator',
          durationSec: 61,
          playlistTitle: 'List',
          playlistIndex: 1,
          playlistCount: 3,
        ),
        DownloadRequest(
          url: entryC.url,
          title: entryC.title,
          quality: Quality.mp3,
          folder: prefs.folder,
          useAria2c: prefs.useAria2c,
          uploader: 'Curator',
          playlistTitle: 'List',
          playlistIndex: 3,
          playlistCount: 3,
        ),
      ]);
    });

    test('keeps the order it is given', () async {
      await notifier().downloadPlaylist(playlist, Quality.best, [1, 0]);

      expect(enqueued().map((r) => r.playlistIndex), [2, 1]);
    });

    test('nothing picked starts nothing and counts none', () async {
      final result = await notifier().downloadPlaylist(
        playlist,
        Quality.best,
        const [],
      );

      expect(result, const Ok(0));
      verifyNever(() => enqueue(any()));
    });

    test('hands back the use case failure', () async {
      when(() => enqueue(any())).thenAnswer((_) async => const Err(failure));

      final result = await notifier().downloadPlaylist(playlist, Quality.best, [
        0,
      ]);

      expect(result, const Err<int>(failure));
    });
  });
}
