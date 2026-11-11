import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'error_messages.dart';
import 'exceptions.dart';
import 'failure.dart';

Failure failureFrom(Object error) =>
    knownFailure(error) ?? const UnexpectedFailure();

/// The failure for an error the app expects, or null for anything else: a bug
/// worth reporting.
Failure? knownFailure(Object error) => switch (error) {
  DioException() => failureFromDioException(error),
  ServerException(:final message, :final code) => ServerFailure(
    message: message,
    code: code,
  ),
  CacheException(:final message) => CacheFailure(message),
  // Pigeon's own: the host API is not registered or a message did not decode.
  PlatformException(code: 'channel-error') => null,
  PlatformException(:final code) => failureFromCode(code),
  _ => null,
};

String messageOf(Object error) =>
    error is Failure ? error.message : ErrorMessages.unexpected;

Failure failureFromCode(String? code) => switch (code) {
  'unsupported_site' || 'invalid_url' => const UnsupportedSiteFailure(),
  'private_video' => const PrivateVideoFailure(),
  'unavailable' => const MediaUnavailableFailure(),
  'network' => const NetworkFailure(),
  'no_storage' => const StorageFailure(),
  'permission_denied' => const StoragePermissionFailure(),
  'busy' => const YtDlpBusyFailure(),
  'no_folder_app' => const UnexpectedFailure(ErrorMessages.noFolderApp),
  _ => const UnexpectedFailure(ErrorMessages.downloadUnknown),
};

const _networkErrors = {
  DioExceptionType.connectionTimeout,
  DioExceptionType.sendTimeout,
  DioExceptionType.receiveTimeout,
  DioExceptionType.connectionError,
};

@visibleForTesting
Failure failureFromDioException(DioException e) {
  // A connection dropped mid-request arrives as `unknown` wrapping the IO error.
  if (_networkErrors.contains(e.type) ||
      (e.type == DioExceptionType.unknown && e.error is IOException)) {
    return const NetworkFailure();
  }
  final status = e.response?.statusCode;
  if (status == 401) return const UnauthorizedFailure();
  final message = _backendMessage(e.response?.data);
  if (message != null) return ServerFailure(message: message, code: status);
  // Not a backend JSON error: an HTML error page, an empty body, no response.
  // A 3xx here comes from a proxy or captive portal, so it carries no code.
  return ServerFailure(
    message: ErrorMessages.server,
    code: status != null && status >= 400 ? status : null,
  );
}

String? _backendMessage(Object? body) => switch (body) {
  {'message': final String message} => message,
  {'error': {'message': final String message}} => message,
  {'errors': [{'message': final String message}, ...]} => message,
  _ => null,
};
