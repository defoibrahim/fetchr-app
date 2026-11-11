import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/errors/error_messages.dart';
import 'package:grabby/core/errors/exceptions.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/failure_mapper.dart';

final _request = RequestOptions(path: 'posts');

DioException _error(
  DioExceptionType type, {
  int? status,
  Object? body,
  Object? error,
}) => DioException(
  requestOptions: _request,
  type: type,
  error: error,
  response: status == null
      ? null
      : Response(requestOptions: _request, statusCode: status, data: body),
);

DioException _bad(int status, Object? body) =>
    _error(DioExceptionType.badResponse, status: status, body: body);

const _network = NetworkFailure();

ServerFailure _server([int? code]) =>
    ServerFailure(message: ErrorMessages.server, code: code);

void main() {
  group('failureFromDioException', () {
    final cases = <String, (DioException, Failure)>{
      'connection timeout': (
        _error(DioExceptionType.connectionTimeout),
        _network,
      ),
      'send timeout': (_error(DioExceptionType.sendTimeout), _network),
      'receive timeout': (_error(DioExceptionType.receiveTimeout), _network),
      'connection error': (_error(DioExceptionType.connectionError), _network),
      'connection reset mid-request': (
        _error(
          DioExceptionType.unknown,
          error: const SocketException('Connection reset by peer'),
        ),
        _network,
      ),
      'connection closed before headers': (
        _error(
          DioExceptionType.unknown,
          error: const HttpException('Connection closed'),
        ),
        _network,
      ),
      'TLS handshake cut (captive portal)': (
        _error(
          DioExceptionType.unknown,
          error: const HandshakeException('handshake'),
        ),
        _network,
      ),
      '401 is unauthorized': (
        _bad(401, {'message': 'Token expired'}),
        const UnauthorizedFailure(),
      ),
      '401 without a body is unauthorized': (
        _bad(401, null),
        const UnauthorizedFailure(),
      ),
      'top-level message': (
        _bad(422, {'message': 'Invalid email'}),
        const ServerFailure(message: 'Invalid email', code: 422),
      ),
      'top-level message wins over error.message': (
        _bad(400, {
          'message': 'Top',
          'error': {'message': 'Nested'},
        }),
        const ServerFailure(message: 'Top', code: 400),
      ),
      'error.message': (
        _bad(400, {
          'error': {'message': 'Bad input'},
        }),
        const ServerFailure(message: 'Bad input', code: 400),
      ),
      'errors list takes the first message': (
        _bad(422, {
          'errors': [
            {'message': 'First'},
            {'message': 'Second'},
          ],
        }),
        const ServerFailure(message: 'First', code: 422),
      ),
      'errors list with one entry': (
        _bad(400, {
          'errors': [
            {'message': 'Only', 'field': 'email'},
          ],
        }),
        const ServerFailure(message: 'Only', code: 400),
      ),
      'HTML error page': (_bad(502, '<html>Bad Gateway</html>'), _server(502)),
      'empty body': (_bad(500, ''), _server(500)),
      'null body': (_bad(500, null), _server(500)),
      'errors as a map': (
        _bad(400, {
          'errors': {
            'email': ['taken'],
          },
        }),
        _server(400),
      ),
      'empty errors list': (_bad(400, {'errors': <Object>[]}), _server(400)),
      'non-string message': (_bad(400, {'message': 42}), _server(400)),
      'null message': (_bad(400, {'message': null}), _server(400)),
      'cancelled': (_error(DioExceptionType.cancel), _server()),
      'bad certificate': (_error(DioExceptionType.badCertificate), _server()),
      'unknown without an IO error': (
        _error(DioExceptionType.unknown),
        _server(),
      ),
      'a 3xx has no code': (_bad(302, '<html>Found</html>'), _server()),
    };

    for (final MapEntry(key: name, value: (error, expected)) in cases.entries) {
      test(name, () {
        final failure = failureFromDioException(error);

        expect(failure, expected);
        expect(failure.code, expected.code);
      });
    }
  });

  group('failureFrom', () {
    test('delegates a DioException to failureFromDioException', () {
      final error = _bad(422, {'message': 'Invalid'});

      expect(failureFrom(error), failureFromDioException(error));
    });

    test('maps ServerException, keeping message and code', () {
      expect(
        failureFrom(const ServerException('nope', code: 409)),
        const ServerFailure(message: 'nope', code: 409),
      );
      expect(
        failureFrom(const ServerException('nope')),
        const ServerFailure(message: 'nope'),
      );
    });

    test('maps CacheException to CacheFailure', () {
      expect(failureFrom(const CacheException()), const CacheFailure());
      expect(
        failureFrom(const CacheException('gone')),
        const CacheFailure('gone'),
      );
    });

    test('maps everything else to UnexpectedFailure', () {
      expect(failureFrom(StateError('x')), const UnexpectedFailure());
      expect(failureFrom('plain string'), const UnexpectedFailure());
      expect(failureFrom(const FormatException()), const UnexpectedFailure());
    });
  });

  group('messageOf', () {
    test('a Failure gives its own message', () {
      expect(messageOf(const StorageFailure()), ErrorMessages.storage);
      expect(messageOf(const NetworkFailure('offline')), 'offline');
    });

    test('anything else gives the generic message', () {
      expect(messageOf(StateError('secret')), ErrorMessages.unexpected);
      expect(messageOf('plain string'), ErrorMessages.unexpected);
    });
  });

  group('failureFromCode', () {
    final cases = <String?, Failure>{
      'unsupported_site': const UnsupportedSiteFailure(),
      'invalid_url': const UnsupportedSiteFailure(),
      'private_video': const PrivateVideoFailure(),
      'unavailable': const MediaUnavailableFailure(),
      'network': const NetworkFailure(),
      'no_storage': const StorageFailure(),
      'busy': const YtDlpBusyFailure(),
      'permission_denied': const StoragePermissionFailure(),
      'no_folder_app': const UnexpectedFailure(ErrorMessages.noFolderApp),
      'unknown': const UnexpectedFailure(ErrorMessages.downloadUnknown),
      'something_new': const UnexpectedFailure(ErrorMessages.downloadUnknown),
      '': const UnexpectedFailure(ErrorMessages.downloadUnknown),
      null: const UnexpectedFailure(ErrorMessages.downloadUnknown),
    };

    for (final MapEntry(key: code, value: expected) in cases.entries) {
      test('${code ?? 'null'} maps to ${expected.runtimeType}', () {
        final failure = failureFromCode(code);

        expect(failure, expected);
        expect(failure.runtimeType, expected.runtimeType);
        expect(failure.message, expected.message);
        expect(failure.code, isNull);
      });
    }

    test('each new failure carries its default message', () {
      expect(
        const UnsupportedSiteFailure().message,
        ErrorMessages.unsupportedSite,
      );
      expect(const PrivateVideoFailure().message, ErrorMessages.privateVideo);
      expect(
        const MediaUnavailableFailure().message,
        ErrorMessages.unavailable,
      );
      expect(const StorageFailure().message, ErrorMessages.storage);
      expect(const YtDlpBusyFailure().message, ErrorMessages.ytDlpBusy);
      expect(
        const StoragePermissionFailure().message,
        ErrorMessages.storagePermission,
      );
    });

    test('permission and storage failures differ', () {
      expect(const StoragePermissionFailure(), isNot(const StorageFailure()));
      expect(
        const StoragePermissionFailure('x'),
        isNot(const StorageFailure('x')),
      );
    });

    test('failures of different types with equal messages differ', () {
      expect(
        const UnsupportedSiteFailure('x'),
        isNot(const PrivateVideoFailure('x')),
      );
    });
  });

  group('failureFrom PlatformException', () {
    test('maps by the pigeon error code', () {
      expect(
        failureFrom(PlatformException(code: 'private_video', message: 'raw')),
        const PrivateVideoFailure(),
      );
      expect(
        failureFrom(PlatformException(code: 'no_storage')),
        const StorageFailure(),
      );
      expect(
        failureFrom(PlatformException(code: 'invalid_url')),
        const UnsupportedSiteFailure(),
      );
      expect(
        failureFrom(PlatformException(code: 'permission_denied')),
        const StoragePermissionFailure(),
      );
    });

    test('an unknown or foreign code is a generic download failure', () {
      const expected = UnexpectedFailure(ErrorMessages.downloadUnknown);

      expect(failureFrom(PlatformException(code: 'unknown')), expected);
      expect(failureFrom(PlatformException(code: 'IOException')), expected);
      expect(failureFrom(PlatformException(code: '')), expected);
    });
  });
}
