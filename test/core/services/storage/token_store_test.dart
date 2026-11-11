import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/services/storage/token_store.dart';
import 'package:mocktail/mocktail.dart';

import '../../../support/mocks.dart';

void main() {
  late MockSecureStorage storage;
  late TokenStore store;

  setUp(() {
    storage = MockSecureStorage();
    store = TokenStore(storage);
    when(() => storage.read(key: 'auth_token')).thenAnswer((_) async => 'abc');
    when(
      () => storage.write(
        key: 'auth_token',
        value: any(named: 'value'),
      ),
    ).thenAnswer((_) async {});
    when(() => storage.delete(key: 'auth_token')).thenAnswer((_) async {});
  });

  test('reads the stored token from the auth_token key', () async {
    expect(await store.read(), 'abc');
  });

  test('caches after the first read', () async {
    await store.read();
    await store.read();

    verify(() => storage.read(key: 'auth_token')).called(1);
  });

  test('caches an absent token too', () async {
    when(() => storage.read(key: 'auth_token')).thenAnswer((_) async => null);

    expect(await store.read(), isNull);
    expect(await store.read(), isNull);
    verify(() => storage.read(key: 'auth_token')).called(1);
  });

  test('write stores the token and serves it from memory', () async {
    await store.write('fresh');

    expect(await store.read(), 'fresh');
    verify(() => storage.write(key: 'auth_token', value: 'fresh')).called(1);
    verifyNever(() => storage.read(key: 'auth_token'));
  });

  test('clear deletes the token and reads null afterwards', () async {
    await store.read();
    await store.clear();

    expect(await store.read(), isNull);
    verify(() => storage.delete(key: 'auth_token')).called(1);
    verify(() => storage.read(key: 'auth_token')).called(1);
  });

  test('a failed write leaves the cached token alone', () async {
    await store.read();
    when(
      () => storage.write(
        key: 'auth_token',
        value: any(named: 'value'),
      ),
    ).thenThrow(StateError('keystore'));

    await expectLater(store.write('new'), throwsStateError);

    expect(await store.read(), 'abc');
  });

  test('a clear that lands during the first read wins', () async {
    final pending = Completer<String?>();
    when(
      () => storage.read(key: 'auth_token'),
    ).thenAnswer((_) => pending.future);

    final first = store.read();
    await store.clear();
    pending.complete('old');

    expect(await first, isNull);
    expect(await store.read(), isNull);
  });

  test('a failed read is not cached, so the next read retries', () async {
    when(() => storage.read(key: 'auth_token')).thenThrow(StateError('boom'));
    await expectLater(store.read(), throwsStateError);
    when(() => storage.read(key: 'auth_token')).thenAnswer((_) async => 'abc');

    expect(await store.read(), 'abc');
  });
}
