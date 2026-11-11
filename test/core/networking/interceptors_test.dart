import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/networking/interceptors.dart';
import 'package:grabby/core/services/storage/token_store.dart';
import 'package:mocktail/mocktail.dart';

import '../../support/fake_http_adapter.dart';
import '../../support/mocks.dart';

Dio _dio(FakeHttpAdapter adapter, TokenStore tokens) => Dio()
  ..interceptors.add(AppInterceptors(tokens))
  ..httpClientAdapter = adapter;

Matcher _dioError(DioExceptionType type, [int? status]) => throwsA(
  isA<DioException>()
      .having((e) => e.type, 'type', type)
      .having((e) => e.response?.statusCode, 'status', status),
);

void main() {
  late TokenStore tokens;
  var unauthorized = 0;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    tokens = TokenStore(const FlutterSecureStorage());
    unauthorized = 0;
    AppInterceptors.onUnauthorized = () => unauthorized++;
  });

  tearDown(() => AppInterceptors.onUnauthorized = null);

  group('request headers', () {
    test('sends Bearer <token> when the store has one', () async {
      await tokens.write('abc123');
      final adapter = FakeHttpAdapter.json('{}');

      await _dio(adapter, tokens).get<Object?>('posts');

      expect(adapter.lastRequest.headers['Authorization'], 'Bearer abc123');
      expect(adapter.lastRequest.headers['Accept'], 'application/json');
    });

    test('sends no Authorization header when there is no token', () async {
      final adapter = FakeHttpAdapter.json('{}');

      await _dio(adapter, tokens).get<Object?>('posts');

      expect(adapter.lastRequest.headers.containsKey('Authorization'), isFalse);
      expect(adapter.lastRequest.headers['Accept'], 'application/json');
    });

    test('reads the token again after it changes', () async {
      final adapter = FakeHttpAdapter.json('{}');
      final dio = _dio(adapter, tokens);

      await tokens.write('first');
      await dio.get<Object?>('posts');
      await tokens.clear();
      await dio.get<Object?>('posts');

      expect(adapter.requests.first.headers['Authorization'], 'Bearer first');
      expect(
        adapter.requests.last.headers.containsKey('Authorization'),
        isFalse,
      );
    });

    test(
      'sends the request without a token when the store cannot be read',
      () async {
        final storage = MockSecureStorage();
        when(
          () => storage.read(key: any(named: 'key')),
        ).thenThrow(StateError('keystore unavailable'));
        final adapter = FakeHttpAdapter.json('{}');

        await _dio(adapter, TokenStore(storage)).get<Object?>('posts');

        expect(adapter.requests, hasLength(1));
        expect(
          adapter.lastRequest.headers.containsKey('Authorization'),
          isFalse,
        );
        expect(unauthorized, 0);
      },
    );

    test('never sends the token to another host', () async {
      await tokens.write('abc123');
      final adapter = FakeHttpAdapter.json('{}');

      await _dio(adapter, tokens).get<Object?>('https://files.example.com/x');

      expect(adapter.lastRequest.headers.containsKey('Authorization'), isFalse);
    });
  });

  group('errors', () {
    test(
      'a 401 calls the hook once and reaches the caller unchanged',
      () async {
        await expectLater(
          _dio(
            FakeHttpAdapter.json('{"message":"x"}', status: 401),
            tokens,
          ).get<Object?>('posts'),
          _dioError(DioExceptionType.badResponse, 401),
        );

        expect(unauthorized, 1);
      },
    );

    test('a 401 without a hook set still reaches the caller', () async {
      AppInterceptors.onUnauthorized = null;

      await expectLater(
        _dio(FakeHttpAdapter.json('{}', status: 401), tokens).get<Object?>('p'),
        _dioError(DioExceptionType.badResponse, 401),
      );
    });

    test('other error statuses never call the hook', () async {
      for (final code in [400, 403, 404, 409, 500, 502]) {
        await expectLater(
          _dio(
            FakeHttpAdapter.json('{}', status: code),
            tokens,
          ).get<Object?>('posts'),
          _dioError(DioExceptionType.badResponse, code),
        );
      }

      expect(unauthorized, 0);
    });

    test('a timeout keeps its type and never calls the hook', () async {
      final adapter = FakeHttpAdapter.failing(
        (options) => DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        ),
      );

      await expectLater(
        _dio(adapter, tokens).get<Object?>('posts'),
        _dioError(DioExceptionType.connectionTimeout),
      );
      expect(unauthorized, 0);
    });
  });
}
