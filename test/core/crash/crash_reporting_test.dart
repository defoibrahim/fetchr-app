import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/crash/crash_reporter.dart';
import 'package:grabby/core/crash/crash_reporting.dart';
import 'package:grabby/core/logging/app_logger.dart';

typedef _Recorded = (Object error, StackTrace? stack, bool fatal);

class _FakeReporter implements CrashReporter {
  _FakeReporter({required this.capturesUncaught, this.failWith});

  @override
  final bool capturesUncaught;
  final Object? failWith;
  final recorded = <_Recorded>[];
  final userIds = <String?>[];

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
  }) async {
    recorded.add((error, stack, fatal));
    if (failWith != null) throw failWith!;
  }

  @override
  Future<void> setUserId(String? id) async {
    userIds.add(id);
    if (failWith != null) throw failWith!;
  }
}

void main() {
  final logged = <(LogLevel, String)>[];
  final error = StateError('boom');
  final stack = StackTrace.current;

  setUp(() {
    logged.clear();
    AppLogger.overrideForTesting(
      sink: (level, message, _) => logged.add((level, message)),
    );
  });

  tearDown(() {
    CrashReporting.reset();
    AppLogger.reset();
  });

  group('recordUncaught', () {
    test('skips reporters that capture uncaught errors themselves', () async {
      final selfCapturing = _FakeReporter(capturesUncaught: true);
      final forwarded = _FakeReporter(capturesUncaught: false);
      CrashReporting.add(selfCapturing);
      CrashReporting.add(forwarded);
      CrashReporting.recordUncaught(error, stack);
      await pumpEventQueue();

      expect(selfCapturing.recorded, isEmpty);
      expect(forwarded.recorded, [(error, stack, true)]);
    });

    test('logs the error before reporting', () {
      CrashReporting.recordUncaught(error, stack);

      expect(logged.single.$1, LogLevel.error);
      expect(logged.single.$2, contains('Bad state: boom'));
    });

    test('logs even when no reporter is registered', () {
      CrashReporting.recordUncaught(error, null);

      expect(logged, hasLength(1));
    });

    test('a failing reporter does not throw or stop the others', () async {
      final broken = _FakeReporter(
        capturesUncaught: false,
        failWith: StateError('down'),
      );
      final healthy = _FakeReporter(capturesUncaught: false);
      CrashReporting.add(broken);
      CrashReporting.add(healthy);
      CrashReporting.recordUncaught(error, stack);
      await pumpEventQueue();

      expect(healthy.recorded, hasLength(1));
      expect(
        logged.where((l) => l.$1 == LogLevel.warning).single.$2,
        contains('StateError'),
      );
    });
  });

  group('recordError', () {
    test('forwards to every reporter, including self-capturing ones', () async {
      final selfCapturing = _FakeReporter(capturesUncaught: true);
      final forwarded = _FakeReporter(capturesUncaught: false);
      CrashReporting.add(selfCapturing);
      CrashReporting.add(forwarded);

      await CrashReporting.recordError(error, stack);

      expect(selfCapturing.recorded, [(error, stack, false)]);
      expect(forwarded.recorded, [(error, stack, false)]);
    });

    test('passes fatal through', () async {
      final reporter = _FakeReporter(capturesUncaught: false);
      CrashReporting.add(reporter);

      await CrashReporting.recordError(error, stack, fatal: true);

      expect(reporter.recorded.single.$3, isTrue);
    });

    test('logs first, and still completes when a reporter fails', () async {
      CrashReporting.add(
        _FakeReporter(capturesUncaught: false, failWith: Exception('x')),
      );
      CrashReporting.add(_FakeReporter(capturesUncaught: false));

      await CrashReporting.recordError(error, stack);

      expect(logged.first.$1, LogLevel.error);
    });
  });

  group('setUserId', () {
    test('forwards the id, including null, to every reporter', () async {
      final a = _FakeReporter(capturesUncaught: true);
      final b = _FakeReporter(capturesUncaught: false);
      CrashReporting.add(a);
      CrashReporting.add(b);

      await CrashReporting.setUserId('u1');
      await CrashReporting.setUserId(null);

      expect(a.userIds, ['u1', null]);
      expect(b.userIds, ['u1', null]);
    });

    test('a failing reporter does not stop the others', () async {
      final healthy = _FakeReporter(capturesUncaught: false);
      CrashReporting.add(
        _FakeReporter(capturesUncaught: false, failWith: Exception('x')),
      );
      CrashReporting.add(healthy);

      await CrashReporting.setUserId('u1');

      expect(healthy.userIds, ['u1']);
    });
  });

  test('reset drops every reporter', () async {
    final reporter = _FakeReporter(capturesUncaught: false);
    CrashReporting.add(reporter);
    CrashReporting.reset();
    await CrashReporting.recordError(error, stack);

    expect(reporter.recorded, isEmpty);
  });
}
