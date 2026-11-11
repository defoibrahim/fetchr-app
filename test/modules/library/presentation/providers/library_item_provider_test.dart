import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/modules/library/di/library_providers.dart';
import 'package:grabby/modules/library/domain/entities/library_item.dart';
import 'package:grabby/modules/library/presentation/providers/library_item_provider.dart';
import 'package:grabby/modules/library/presentation/providers/library_notifier.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../support/fixtures.dart';
import '../../../../support/mocks.dart';

void main() {
  final a = libraryItem(uri: 'content://media/video/1', name: 'A.mp4');
  final b = libraryItem(uri: 'content://media/video/2', name: 'B.mp4');

  late MockGetLibraryUseCase getLibrary;
  late ProviderContainer container;

  setUp(() {
    getLibrary = MockGetLibraryUseCase();
    container = ProviderContainer(
      overrides: [getLibraryUseCaseProvider.overrideWithValue(getLibrary)],
    );
    addTearDown(container.dispose);
  });

  void stubList(Future<Result<List<LibraryItem>>> Function() answer) {
    when(() => getLibrary(any())).thenAnswer((_) => answer());
  }

  // An autoDispose provider lives only while something listens to it.
  void listenToItem(String uri) =>
      container.listen(libraryItemProvider(uri), (_, _) {});

  test('is null while the library loads', () {
    stubList(() => Completer<Result<List<LibraryItem>>>().future);

    listenToItem(a.uri);

    expect(container.read(libraryItemProvider(a.uri)), isNull);
  });

  test('is the item with that uri once the library is loaded', () async {
    stubList(() async => Ok([a, b]));
    listenToItem(b.uri);

    await container.read(libraryNotifierProvider.future);

    expect(container.read(libraryItemProvider(b.uri)), b);
    expect(container.read(libraryItemProvider(a.uri)), a);
  });

  test('is null for a uri the library does not hold', () async {
    stubList(() async => Ok([a]));
    listenToItem('content://media/video/404');

    await container.read(libraryNotifierProvider.future);

    expect(
      container.read(libraryItemProvider('content://media/video/404')),
      isNull,
    );
  });

  test('is null when the library failed to load', () async {
    stubList(() async => throw StateError('boom'));
    listenToItem(a.uri);

    await expectLater(
      container.read(libraryNotifierProvider.future),
      throwsStateError,
    );

    expect(container.read(libraryItemProvider(a.uri)), isNull);
  });

  test('follows a delete in its Undo window and the Undo', () async {
    stubList(() async => Ok([a, b]));
    listenToItem(a.uri);
    await container.read(libraryNotifierProvider.future);
    final notifier = container.read(libraryNotifierProvider.notifier);

    notifier.hide(a);
    expect(container.read(libraryItemProvider(a.uri)), isNull);
    expect(container.read(libraryItemProvider(b.uri)), b);

    notifier.restore(a);
    expect(container.read(libraryItemProvider(a.uri)), a);
  });

  test('does not notify when an unrelated item goes away', () async {
    stubList(() async => Ok([a, b]));
    final seen = <LibraryItem?>[];
    container.listen(libraryItemProvider(a.uri), (_, next) => seen.add(next));
    await container.read(libraryNotifierProvider.future);
    seen.clear();

    container.read(libraryNotifierProvider.notifier).hide(b);

    expect(seen, isEmpty);
    expect(container.read(libraryItemProvider(a.uri)), a);
  });
}
