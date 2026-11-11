import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/errors/error_messages.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/core/logging/app_logger.dart';
import 'package:grabby/core/networking/api_constants.dart';
import 'package:grabby/core/networking/dio_client.dart';
import 'package:grabby/core/networking/http_method.dart';
import 'package:grabby/core/networking/interceptors.dart';
import 'package:grabby/core/services/storage/token_store.dart';

import '../../support/fake_http_adapter.dart';

// compute() needs a top-level function it can send to another isolate.
int _lengthOf(Object? data) => (data! as List<Object?>).length;

DioClient _client(FakeHttpAdapter adapter) {
  final dio = buildDio(
    baseUrl: 'https://api.example.test/',
    tokenStore: TokenStore(const FlutterSecureStorage()),
  )..httpClientAdapter = adapter;
  return DioClient(dio);
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('makeRequest', () {
    test('200 hands the decoded JSON to the converter', () async {
      final result = await _client(FakeHttpAdapter.json('{"id":7}'))
          .makeRequest(
            path: 'posts/7',
            converter: (data) => (data! as Map<String, Object?>)['id']! as int,
          );

      expect(result, const Ok(7));
    });

    test('201 counts as success', () async {
      final result =
          await _client(
            FakeHttpAdapter.json('{"id":1}', status: 201),
          ).makeRequest(
            path: 'posts',
            method: HttpMethod.post,
            converter: (d) => d,
          );

      expect(result.isOk, isTrue);
    });

    test('204 reaches the converter as null', () async {
      Object? seen = 'untouched';

      final result = await _client(FakeHttpAdapter.empty()).makeRequest<bool>(
        path: 'posts/1',
        method: HttpMethod.delete,
        converter: (data) {
          seen = data;
          return true;
        },
      );

      expect(result, const Ok(true));
      expect(seen, isNull);
    });

    test(
      '500 with a JSON message becomes ServerFailure with the status',
      () async {
        final result = await _client(
          FakeHttpAdapter.json('{"message":"Database down"}', status: 500),
        ).makeRequest<Object?>(path: 'posts', converter: (d) => d);

        expect(
          result,
          const Err<Object?>(
            ServerFailure(message: 'Database down', code: 500),
          ),
        );
      },
    );

    test(
      '500 with a non-JSON body falls back to the generic message',
      () async {
        final result = await _client(
          FakeHttpAdapter((_) async => ResponseBody.fromString('<html/>', 502)),
        ).makeRequest<Object?>(path: 'posts', converter: (d) => d);

        expect(
          result.failureOrNull,
          const ServerFailure(message: ErrorMessages.server, code: 502),
        );
      },
    );

    test('401 becomes UnauthorizedFailure and calls the hook', () async {
      var hooked = 0;
      AppInterceptors.onUnauthorized = () => hooked++;
      addTearDown(() => AppInterceptors.onUnauthorized = null);

      final result = await _client(
        FakeHttpAdapter.json('{"message":"nope"}', status: 401),
      ).makeRequest<Object?>(path: 'me', converter: (d) => d);

      expect(result.failureOrNull, const UnauthorizedFailure());
      expect(hooked, 1);
    });

    test('a timeout becomes NetworkFailure', () async {
      final adapter = FakeHttpAdapter.failing(
        (options) => DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
        ),
      );

      final result = await _client(
        adapter,
      ).makeRequest<Object?>(path: 'posts', converter: (d) => d);

      expect(result, const Err<Object?>(NetworkFailure()));
    });

    test('a dropped connection becomes NetworkFailure', () async {
      final adapter = FakeHttpAdapter.failing(
        (_) => const SocketException('Connection reset by peer'),
      );

      final result = await _client(
        adapter,
      ).makeRequest<Object?>(path: 'posts', converter: (d) => d);

      expect(result.failureOrNull, const NetworkFailure());
    });

    test('a converter throw becomes UnexpectedFailure and is logged', () async {
      final logged = <String>[];
      AppLogger.overrideForTesting(
        sink: (level, message, stack) => logged.add(message),
      );
      addTearDown(AppLogger.reset);

      final result = await _client(FakeHttpAdapter.json('{}')).makeRequest<int>(
        path: 'posts',
        converter: (_) => throw const FormatException('bad shape'),
      );

      expect(result, const Err<int>(UnexpectedFailure()));
      expect(
        logged.any((m) => m.contains('posts') && m.contains('bad shape')),
        isTrue,
      );
    });

    test('sends the method, body and query parameters', () async {
      final adapter = FakeHttpAdapter.json('{}');

      await _client(adapter).makeRequest<Object?>(
        path: 'posts',
        method: HttpMethod.patch,
        data: {'title': 'new'},
        queryParams: {'draft': true},
        converter: (d) => d,
      );

      final sent = adapter.lastRequest;
      expect(sent.method, 'PATCH');
      expect(sent.path, 'posts');
      expect(sent.data, {'title': 'new'});
      expect(sent.queryParameters, {'draft': true});
    });

    test('defaults to GET', () async {
      final adapter = FakeHttpAdapter.json('[]');

      await _client(
        adapter,
      ).makeRequest<Object?>(path: 'posts', converter: (d) => d);

      expect(adapter.lastRequest.method, 'GET');
    });

    test('maps every HttpMethod to its verb', () async {
      final adapter = FakeHttpAdapter.json('{}');
      final client = _client(adapter);

      for (final method in HttpMethod.values) {
        await client.makeRequest<Object?>(
          path: 'x',
          method: method,
          converter: (d) => d,
        );
      }

      expect(adapter.requests.map((r) => r.method), [
        'GET',
        'POST',
        'PUT',
        'PATCH',
        'DELETE',
      ]);
    });

    test('isIsolate runs the converter in compute()', () async {
      final result = await _client(
        FakeHttpAdapter.json('[1,2,3]'),
      ).makeRequest<int>(path: 'posts', converter: _lengthOf, isIsolate: true);

      expect(result, const Ok(3));
    });

    test(
      'isIsolate still maps a converter throw to UnexpectedFailure',
      () async {
        AppLogger.overrideForTesting(sink: (level, message, stack) {});
        addTearDown(AppLogger.reset);

        final result = await _client(FakeHttpAdapter.json('{}'))
            .makeRequest<int>(
              path: 'posts',
              converter: _lengthOf,
              isIsolate: true,
            );

        expect(result, const Err<int>(UnexpectedFailure()));
      },
    );
  });

  group('buildDio', () {
    test('applies the base url and ApiConstants timeouts', () {
      final dio = buildDio(
        baseUrl: 'https://api.example.test/',
        tokenStore: TokenStore(const FlutterSecureStorage()),
      );

      expect(dio.options.baseUrl, 'https://api.example.test/');
      expect(dio.options.connectTimeout, ApiConstants.connectTimeout);
      expect(dio.options.receiveTimeout, ApiConstants.receiveTimeout);
      expect(dio.options.sendTimeout, ApiConstants.sendTimeout);
      expect(ApiConstants.connectTimeout, const Duration(seconds: 20));
      expect(ApiConstants.receiveTimeout, const Duration(seconds: 30));
      expect(ApiConstants.sendTimeout, const Duration(seconds: 30));
    });

    test('installs AppInterceptors that attach the stored token', () async {
      final tokens = TokenStore(const FlutterSecureStorage());
      await tokens.write('abc123');
      final adapter = FakeHttpAdapter.json('{}');
      final dio = buildDio(
        baseUrl: 'https://api.example.test/',
        tokenStore: tokens,
      )..httpClientAdapter = adapter;

      await DioClient(
        dio,
      ).makeRequest<Object?>(path: 'me', converter: (d) => d);

      expect(dio.interceptors.whereType<AppInterceptors>(), hasLength(1));
      expect(adapter.lastRequest.uri.toString(), 'https://api.example.test/me');
      expect(adapter.lastRequest.headers['Authorization'], 'Bearer abc123');
    });

    test('logs method, path, status and duration, never the query', () async {
      final logged = <String>[];
      AppLogger.overrideForTesting(
        sink: (level, message, stack) => logged.add(message),
      );
      addTearDown(AppLogger.reset);

      await _client(FakeHttpAdapter.json('{}')).makeRequest<Object?>(
        path: 'posts',
        queryParams: {'api_key': 'secret-value'},
        converter: (d) => d,
      );

      expect(logged, hasLength(1));
      expect(logged.single, matches(RegExp(r'^GET posts -> 200 \(\d+ms\)$')));
    });

    test('logs the failure type when there is no response', () async {
      final logged = <String>[];
      AppLogger.overrideForTesting(
        sink: (level, message, stack) => logged.add(message),
      );
      addTearDown(AppLogger.reset);
      final adapter = FakeHttpAdapter.failing(
        (options) => DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        ),
      );

      await _client(
        adapter,
      ).makeRequest<Object?>(path: 'posts', converter: (d) => d);

      expect(
        logged.single,
        matches(RegExp(r'^GET posts -> connectionTimeout \(\d+ms\)$')),
      );
    });
  });
}
