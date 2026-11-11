import 'package:flutter/foundation.dart';

import '../logging/app_logger.dart';
import 'crash_reporter.dart';

abstract final class CrashReporting {
  static final List<CrashReporter> _reporters = [];

  static void add(CrashReporter reporter) => _reporters.add(reporter);

  static void recordUncaught(Object error, StackTrace? stack) {
    AppLogger.error('Unhandled error', error, stack);
    for (final reporter in _reporters) {
      if (reporter.capturesUncaught) continue;
      // ignore(): a failed report must not come back here as a new error.
      _send(reporter, error, stack, fatal: true).ignore();
    }
  }

  static Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
  }) async {
    AppLogger.error('Recorded error', error, stack);
    await Future.wait([
      for (final reporter in _reporters)
        _send(reporter, error, stack, fatal: fatal),
    ]);
  }

  static Future<void> setUserId(String? id) async {
    await Future.wait([
      for (final reporter in _reporters) _guarded(() => reporter.setUserId(id)),
    ]);
  }

  @visibleForTesting
  static void reset() => _reporters.clear();

  static Future<void> _send(
    CrashReporter reporter,
    Object error,
    StackTrace? stack, {
    required bool fatal,
  }) => _guarded(() => reporter.recordError(error, stack, fatal: fatal));

  static Future<void> _guarded(Future<void> Function() call) async {
    try {
      await call();
    } catch (e) {
      AppLogger.warning('Crash reporter failed: ${e.runtimeType}');
    }
  }
}
