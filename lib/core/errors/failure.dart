import 'package:equatable/equatable.dart';

import 'error_messages.dart';

abstract class Failure extends Equatable {
  const Failure({required this.message, this.code});

  final String message;
  final int? code;

  @override
  List<Object?> get props => [message, code];
}

class ServerFailure extends Failure {
  const ServerFailure({required super.message, super.code});
}

class NetworkFailure extends Failure {
  const NetworkFailure([String message = ErrorMessages.network])
    : super(message: message);
}

class CacheFailure extends Failure {
  const CacheFailure([String message = ErrorMessages.cache])
    : super(message: message);
}

class UnexpectedFailure extends Failure {
  const UnexpectedFailure([String message = ErrorMessages.unexpected])
    : super(message: message);
}

class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure([String message = ErrorMessages.unauthorized])
    : super(message: message, code: 401);
}

class UnsupportedSiteFailure extends Failure {
  const UnsupportedSiteFailure([String message = ErrorMessages.unsupportedSite])
    : super(message: message);
}

class PrivateVideoFailure extends Failure {
  const PrivateVideoFailure([String message = ErrorMessages.privateVideo])
    : super(message: message);
}

class MediaUnavailableFailure extends Failure {
  const MediaUnavailableFailure([String message = ErrorMessages.unavailable])
    : super(message: message);
}

class StorageFailure extends Failure {
  const StorageFailure([String message = ErrorMessages.storage])
    : super(message: message);
}

class StoragePermissionFailure extends Failure {
  const StoragePermissionFailure([
    String message = ErrorMessages.storagePermission,
  ]) : super(message: message);
}

class YtDlpBusyFailure extends Failure {
  const YtDlpBusyFailure([String message = ErrorMessages.ytDlpBusy])
    : super(message: message);
}
