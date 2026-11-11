import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/di/core_providers.dart';
import 'package:grabby/app/shared/download_prefs_provider.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/modules/library/di/library_providers.dart';
import 'package:grabby/modules/library/domain/entities/library_item.dart';
import 'package:grabby/modules/library/presentation/providers/library_notifier.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../support/fixtures.dart';
import '../../../../support/memory_storage.dart';
import '../../../../support/mocks.dart';

void main() {
  // The list is newest first by dateAdded.
  LibraryItem item(String id, int day) => libraryItem(
    uri: 'content://media/external/video/media/$id',
    name: 'Clip $id.mp4',
    dateAdded: DateTime.utc(2026, 1, day),
  );

  final a = item('1', 3);
  final b = item('2', 2);
  final c = item('3', 1);
  const failure = StorageFailure();

  late MockGetLibraryUseCase getLibrary;
  late MockDeleteLibraryItemsUseCase deleteItems;
  late MockShareLibraryItemUseCase shareItem;
  late MockOpenLibraryFolderUseCase openFolder;
  late ProviderContainer container;

  void stubList(String folder, Future<Result<List<LibraryItem>>> Function() f) {
    when(() => getLibrary(folder)).thenAnswer((_) => f());
  }

  void stubDelete(Result<bool> result) {
    when(() => deleteItems(any())).thenAnswer((_) async => result);
  }

  // An autoDispose provider lives only while something listens to it.
  void start() => container.listen(libraryNotifierProvider, (_, _) {});

  AsyncValue<List<LibraryItem>> state() =>
      container.read(libraryNotifierProvider);

  LibraryNotifier notifier() =>
      container.read(libraryNotifierProvider.notifier);

  ProviderContainer newContainer() => ProviderContainer(
    overrides: [
      appStorageProvider.overrideWithValue(MemoryStorage()),
      getLibraryUseCaseProvider.overrideWithValue(getLibrary),
      deleteLibraryItemsUseCaseProvider.overrideWithValue(deleteItems),
      shareLibraryItemUseCaseProvider.overrideWithValue(shareItem),
      openLibraryFolderUseCaseProvider.overrideWithValue(openFolder),
    ],
  );

  setUp(() {
    getLibrary = MockGetLibraryUseCase();
    deleteItems = MockDeleteLibraryItemsUseCase();
    shareItem = MockShareLibraryItemUseCase();
    openFolder = MockOpenLibraryFolderUseCase();
    container = newContainer();
  });

  tearDown(() => container.dispose());

  test('starts loading, then holds the items of the default folder', () async {
    final pending = Completer<Result<List<LibraryItem>>>();
    stubList('Fetchr', () => pending.future);
    start();
    expect(state().isLoading, isTrue);

    pending.complete(Ok([a, b]));
    await container.read(libraryNotifierProvider.future);

    expect(state().requireValue, [a, b]);
  });

  test('a failure is in state and a retry recovers', () async {
    stubList('Fetchr', () async => const Err(failure));
    start();
    await pumpEventQueue();

    expect(state().error, failure);

    stubList('Fetchr', () async => Ok([a]));
    container.invalidate(libraryNotifierProvider);
    await container.read(libraryNotifierProvider.future);

    expect(state().requireValue, [a]);
  });

  test('a folder change refetches for the new folder', () async {
    stubList('Fetchr', () async => Ok([a]));
    stubList('Music', () async => Ok([b, c]));
    start();
    await container.read(libraryNotifierProvider.future);

    await container.read(downloadPrefsProvider.notifier).setFolder('Music');
    await container.read(libraryNotifierProvider.future);

    expect(state().requireValue, [b, c]);
    verify(() => getLibrary('Fetchr')).called(1);
    verify(() => getLibrary('Music')).called(1);
  });

  test('changing something other than the folder does not refetch', () async {
    stubList('Fetchr', () async => Ok([a]));
    start();
    await container.read(libraryNotifierProvider.future);

    await container.read(downloadPrefsProvider.notifier).setUseAria2c(true);
    await pumpEventQueue();

    verify(() => getLibrary('Fetchr')).called(1);
  });

  test('refresh keeps the list visible until the reload lands', () async {
    stubList('Fetchr', () async => Ok([a]));
    start();
    await container.read(libraryNotifierProvider.future);

    final pending = Completer<Result<List<LibraryItem>>>();
    stubList('Fetchr', () => pending.future);
    final refreshing = notifier().refresh();

    expect(state().value, [a]);
    expect(state().isLoading, isTrue);

    pending.complete(Ok([a, b]));
    await refreshing;

    expect(state().requireValue, [a, b]);
    expect(state().isLoading, isFalse);
  });

  test('a failed refresh surfaces the failure without throwing', () async {
    stubList('Fetchr', () async => Ok([a]));
    start();
    await container.read(libraryNotifierProvider.future);

    stubList('Fetchr', () async => const Err(failure));
    await notifier().refresh();

    expect(state().error, failure);
    expect(state().isLoading, isFalse);
  });

  group('delete', () {
    setUp(() async {
      stubList('Fetchr', () async => Ok([a, b, c]));
      start();
      await container.read(libraryNotifierProvider.future);
    });

    test('deletes that file and returns true, leaving state to hide', () async {
      stubDelete(const Ok(true));

      final result = await notifier().delete(b);

      expect(result, const Ok(true));
      expect(state().requireValue, [a, b, c]);
      verify(() => deleteItems(b.uri)).called(1);
      verify(() => getLibrary('Fetchr')).called(1);
    });

    test('returns false when the user declined the dialog', () async {
      stubDelete(const Ok(false));

      expect(await notifier().delete(b), const Ok(false));
      expect(state().requireValue, [a, b, c]);
    });

    test('returns the failure when it fails', () async {
      stubDelete(const Err(failure));

      final result = await notifier().delete(b);

      expect(result.failureOrNull, failure);
      expect(state().requireValue, [a, b, c]);
    });

    test('a result that lands after dispose is still returned', () async {
      final pending = Completer<Result<bool>>();
      when(() => deleteItems(any())).thenAnswer((_) => pending.future);
      final disposed = newContainer();
      disposed.listen(libraryNotifierProvider, (_, _) {});
      await disposed.read(libraryNotifierProvider.future);
      final deleting = disposed
          .read(libraryNotifierProvider.notifier)
          .delete(b);

      disposed.dispose();
      pending.complete(const Ok(true));

      expect(await deleting, const Ok(true));
    });

    test('a delete after dispose does nothing and returns false', () async {
      final disposed = newContainer();
      disposed.listen(libraryNotifierProvider, (_, _) {});
      await disposed.read(libraryNotifierProvider.future);
      final disposedNotifier = disposed.read(libraryNotifierProvider.notifier);

      disposed.dispose();

      expect(await disposedNotifier.delete(b), const Ok(false));
      verifyNever(() => deleteItems(any()));
    });
  });

  group('hide and restore', () {
    setUp(() async {
      stubList('Fetchr', () async => Ok([a, b, c]));
      start();
      await container.read(libraryNotifierProvider.future);
    });

    test('hide drops only that item without touching the use cases', () {
      notifier().hide(b);

      expect(state().requireValue, [a, c]);
      verify(() => getLibrary('Fetchr')).called(1);
      verifyNever(() => deleteItems(any()));
    });

    test('restore puts each item back in its place', () {
      for (final hidden in [a, b, c]) {
        notifier().hide(hidden);
        notifier().restore(hidden);

        expect(state().requireValue, [a, b, c]);
      }
    });

    test('restore brings back several items in order', () {
      notifier()
        ..hide(a)
        ..hide(c)
        ..restore(c)
        ..restore(a);

      expect(state().requireValue, [a, b, c]);
    });

    test('a hidden item stays hidden across a refresh', () async {
      notifier().hide(b);

      await notifier().refresh();

      expect(state().requireValue, [a, c]);
      verify(() => getLibrary('Fetchr')).called(2);
    });

    test('an item hidden while a reload is in flight stays hidden', () async {
      final pending = Completer<Result<List<LibraryItem>>>();
      stubList('Fetchr', () => pending.future);
      final refreshing = notifier().refresh();

      notifier().hide(b);
      pending.complete(Ok([a, b, c]));
      await refreshing;

      expect(state().requireValue, [a, c]);
    });

    test('a restored item shows again after a refresh', () async {
      notifier().hide(b);
      notifier().restore(b);

      await notifier().refresh();

      expect(state().requireValue, [a, b, c]);
    });

    test('a deleted item stays hidden across a refresh', () async {
      stubDelete(const Ok(true));
      notifier().hide(b);

      await notifier().delete(b);
      await notifier().refresh();

      expect(state().requireValue, [a, c]);
    });

    test(
      'a declined delete followed by restore brings the item back',
      () async {
        stubDelete(const Ok(false));
        notifier().hide(b);

        expect(await notifier().delete(b), const Ok(false));
        notifier().restore(b);

        expect(state().requireValue, [a, b, c]);
      },
    );

    test('restore leaves a failed reload showing its error', () async {
      notifier().hide(b);
      stubList('Fetchr', () async => const Err(failure));
      await notifier().refresh();

      notifier().restore(b);

      expect(state().error, failure);
    });

    test('hide and restore after dispose are ignored', () async {
      final disposed = newContainer();
      disposed.listen(libraryNotifierProvider, (_, _) {});
      await disposed.read(libraryNotifierProvider.future);
      final disposedNotifier = disposed.read(libraryNotifierProvider.notifier);
      disposedNotifier.hide(b);

      disposed.dispose();

      expect(() => disposedNotifier.restore(b), returnsNormally);
    });
  });

  group('openFolder', () {
    setUp(() async {
      stubList('Fetchr', () async => Ok([a]));
      start();
      await container.read(libraryNotifierProvider.future);
    });

    test('passes the item uri and returns what the use case says', () async {
      when(
        () => openFolder(a.uri),
      ).thenAnswer((_) async => const Ok<void>(null));

      expect(await notifier().openFolder(a), const Ok<void>(null));
      verify(() => openFolder(a.uri)).called(1);
      expect(state().requireValue, [a]);
    });

    test('returns the failure', () async {
      when(
        () => openFolder(a.uri),
      ).thenAnswer((_) async => const Err<void>(failure));

      expect((await notifier().openFolder(a)).failureOrNull, failure);
    });
  });

  group('share', () {
    setUp(() async {
      stubList('Fetchr', () async => Ok([a]));
      start();
      await container.read(libraryNotifierProvider.future);
    });

    test('delegates to the use case and leaves the list alone', () async {
      when(() => shareItem(a)).thenAnswer((_) async => const Ok<void>(null));

      final result = await notifier().share(a);

      expect(result.isOk, isTrue);
      expect(state().requireValue, [a]);
    });

    test('returns the failure', () async {
      when(
        () => shareItem(a),
      ).thenAnswer((_) async => const Err<void>(failure));

      final result = await notifier().share(a);

      expect(result.failureOrNull, failure);
    });
  });
}
