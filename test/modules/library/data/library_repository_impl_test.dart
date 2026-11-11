import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/errors/error_messages.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/core/platform/fetchr_api.g.dart' as api;
import 'package:grabby/modules/library/data/repositories/library_repository_impl.dart';
import 'package:grabby/modules/library/domain/entities/library_item.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/mocks.dart';

void main() {
  late MockFetchrHostApi hostApi;
  late LibraryRepositoryImpl repository;

  final added = DateTime.fromMillisecondsSinceEpoch(1746100000000);
  final item = LibraryItem(
    uri: 'content://media/external/video/media/7',
    name: 'Clip.mp4',
    mimeType: 'video/mp4',
    isAudio: false,
    sizeBytes: 1024,
    durationMs: 61000,
    dateAdded: added,
    width: 1920,
    height: 1080,
    relativePath: 'Movies/Fetchr/',
  );

  setUp(() {
    hostApi = MockFetchrHostApi();
    repository = LibraryRepositoryImpl(hostApi);
  });

  group('list', () {
    test('maps every field and passes the folder through', () async {
      when(() => hostApi.listLibrary('Fetchr')).thenAnswer(
        (_) async => [
          api.LibraryItem(
            uri: item.uri,
            name: item.name,
            mimeType: item.mimeType,
            isAudio: false,
            sizeBytes: 1024,
            durationMs: 61000,
            dateAddedMs: added.millisecondsSinceEpoch,
            width: 1920,
            height: 1080,
            relativePath: 'Movies/Fetchr/',
          ),
          api.LibraryItem(
            uri: 'content://media/external/audio/media/8',
            name: 'Song.mp3',
            mimeType: 'audio/mpeg',
            isAudio: true,
            sizeBytes: 2,
            dateAddedMs: 0,
          ),
        ],
      );

      final result = await repository.list('Fetchr');

      final items = result.valueOrNull!;
      expect(items.first, item);
      expect(items.last.isAudio, isTrue);
      expect(items.last.durationMs, isNull);
      expect(items.last.width, isNull);
      expect(items.last.height, isNull);
      expect(items.last.relativePath, isNull);
      expect(items.last.dateAdded, DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('an empty library is an empty list, not a failure', () async {
      when(() => hostApi.listLibrary(any())).thenAnswer((_) async => []);

      final result = await repository.list('Fetchr');

      expect(result.valueOrNull, isEmpty);
    });

    test('a storage error from native becomes StorageFailure', () async {
      when(
        () => hostApi.listLibrary(any()),
      ).thenThrow(PlatformException(code: 'no_storage'));

      final result = await repository.list('Fetchr');

      expect(result.failureOrNull, const StorageFailure());
    });

    test('an unknown native error becomes the generic failure', () async {
      when(
        () => hostApi.listLibrary(any()),
      ).thenThrow(PlatformException(code: 'unknown', message: 'ERROR: x'));

      final result = await repository.list('Fetchr');

      expect(
        result.failureOrNull,
        const UnexpectedFailure(ErrorMessages.downloadUnknown),
      );
    });
  });

  group('thumbnail', () {
    test('passes the uri and size and returns the cached path', () async {
      const path = '/cache/thumbs/a.jpg';
      when(
        () => hostApi.thumbnail(item.uri, 480, 300),
      ).thenAnswer((_) async => path);

      final result = await repository.thumbnail(item.uri, 480, 300);

      expect(result.valueOrNull, path);
      verify(() => hostApi.thumbnail(item.uri, 480, 300)).called(1);
    });

    test('a missing thumbnail is Ok(null), not a failure', () async {
      when(
        () => hostApi.thumbnail(any(), any(), any()),
      ).thenAnswer((_) async => null);

      final result = await repository.thumbnail(item.uri, 480, 300);

      expect(result.isOk, isTrue);
      expect(result.valueOrNull, isNull);
    });

    test('a thrown error is a failure', () async {
      when(
        () => hostApi.thumbnail(any(), any(), any()),
      ).thenThrow(PlatformException(code: 'permission_denied'));

      final result = await repository.thumbnail(item.uri, 480, 300);

      expect(result.failureOrNull, const StoragePermissionFailure());
    });
  });

  group('delete', () {
    test('passes the uri and returns true when the file is gone', () async {
      when(() => hostApi.deleteFromLibrary('a')).thenAnswer((_) async => true);

      final result = await repository.delete('a');

      expect(result.valueOrNull, isTrue);
      verify(() => hostApi.deleteFromLibrary('a')).called(1);
    });

    test('returns false when the user declined the dialog', () async {
      when(() => hostApi.deleteFromLibrary('a')).thenAnswer((_) async => false);

      final result = await repository.delete('a');

      expect(result.valueOrNull, isFalse);
    });

    test('a thrown error is a failure, not an exception', () async {
      when(
        () => hostApi.deleteFromLibrary(any()),
      ).thenThrow(PlatformException(code: 'no_storage'));

      final result = await repository.delete('a');

      expect(result.failureOrNull, const StorageFailure());
    });
  });

  group('share', () {
    test('sends the uri and the mime type', () async {
      when(() => hostApi.share(any(), any())).thenAnswer((_) async {});

      final result = await repository.share(item);

      expect(result.isOk, isTrue);
      verify(() => hostApi.share(item.uri, 'video/mp4')).called(1);
    });

    test('a thrown error is a failure', () async {
      when(
        () => hostApi.share(any(), any()),
      ).thenThrow(PlatformException(code: 'unknown'));

      final result = await repository.share(item);

      expect(result.failureOrNull, isA<UnexpectedFailure>());
    });
  });

  group('openFolder', () {
    test('passes the uri to native', () async {
      when(() => hostApi.openFolder(item.uri)).thenAnswer((_) async {});

      final result = await repository.openFolder(item.uri);

      expect(result.isOk, isTrue);
      verify(() => hostApi.openFolder(item.uri)).called(1);
    });

    test('no_folder_app becomes the no folder app failure', () async {
      when(
        () => hostApi.openFolder(any()),
      ).thenThrow(PlatformException(code: 'no_folder_app'));

      final result = await repository.openFolder(item.uri);

      expect(
        result.failureOrNull,
        const UnexpectedFailure(ErrorMessages.noFolderApp),
      );
    });

    test('a thrown error is a failure', () async {
      when(
        () => hostApi.openFolder(any()),
      ).thenThrow(PlatformException(code: 'no_storage'));

      final result = await repository.openFolder(item.uri);

      expect(result.failureOrNull, const StorageFailure());
    });
  });
}
