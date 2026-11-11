import 'error_messages.dart';

class ServerException implements Exception {
  const ServerException(this.message, {this.code});

  final String message;
  final int? code;

  @override
  String toString() => 'ServerException($code): $message';
}

class CacheException implements Exception {
  const CacheException([this.message = ErrorMessages.cache]);

  final String message;

  @override
  String toString() => 'CacheException: $message';
}
