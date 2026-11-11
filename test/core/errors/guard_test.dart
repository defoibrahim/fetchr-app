import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/crash/crash_reporter.dart';
import 'package:grabby/core/crash/crash_reporting.dart';
import 'package:grabby/core/errors/exceptions.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/guard.dart';
import 'package:grabby/core/errors/result.dart';
import 'package:grabby/core/logging/app_logger.dart';

class _Reporter implements CrashReporter {
  final errors = <Object>[];

  @override
  bool get capturesUncaught => true;

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
  }) async => errors.add(error);

  @override
  Future<void> setUserId(String? id) async {}
}

void main() {
  final logged = <(LogLevel, String)>[];
  late _Reporter reporter;

  setUp(() {
    logged.clear();
    AppLogger.overrideForTesting(
      sink: (level, message, stack) => logged.add((level, message)),
    );
    CrashReporting.add(reporter = _Reporter());
  });

  tearDown(() {
    AppLogger.reset();
    CrashReporting.reset();
  });

  test('wraps the value in Ok and logs nothing', () async {
    final result = await guard(() async => 42);

    expect(result, const Ok(42));
    expect(logged, isEmpty);
  });

  test('maps a ServerException and logs it as an error', () async {
    final result = await guard<int>(
      () async => throw const ServerException('nope', code: 409),
    );

    expect(result, const Err<int>(ServerFailure(message: 'nope', code: 409)));
    expect(logged.single.$1, LogLevel.error);
    expect(reporter.errors, isEmpty);
  });

  test('a native error is a known failure and is not reported', () async {
    final result = await guard<int>(
      () async => throw PlatformException(code: 'network'),
    );

    expect(result, const Err<int>(NetworkFailure()));
    expect(reporter.errors, isEmpty);
  });

  test('maps a DioException through failureFromDioException', () async {
    final result = await guard<int>(
      () async => throw DioException(
        requestOptions: RequestOptions(path: 'posts'),
        type: DioExceptionType.connectionTimeout,
      ),
    );

    expect(result, const Err<int>(NetworkFailure()));
  });

  test('maps a CacheException', () async {
    final result = await guard<int>(() async => throw const CacheException());

    expect(result, const Err<int>(CacheFailure()));
  });

  test('maps an Error (not just Exceptions) to UnexpectedFailure', () async {
    final result = await guard<int>(() async => throw StateError('bug'));

    expect(result, const Err<int>(UnexpectedFailure()));
    expect(logged.single.$2, contains('Bad state: bug'));
  });

  test('a pigeon channel error is a bug and goes to crash reporting', () async {
    final error = PlatformException(code: 'channel-error');

    final result = await guard<int>(() async => throw error);
    await pumpEventQueue();

    expect(result, const Err<int>(UnexpectedFailure()));
    expect(reporter.errors, [error]);
  });

  test('an error no arm maps is a bug and goes to crash reporting', () async {
    final bug = StateError('bug');

    await guard<int>(() async => throw bug);
    await pumpEventQueue();

    expect(reporter.errors, [bug]);
  });

  test('catches a synchronous throw from the body', () async {
    final result = await guard<int>(() => throw StateError('sync'));

    expect(result, const Err<int>(UnexpectedFailure()));
  });
}
