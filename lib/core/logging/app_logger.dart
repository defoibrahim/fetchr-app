import 'package:flutter/foundation.dart';

import 'log_filters.dart';

/// Severity, ordered. Comparisons use [index], so do not reorder.
enum LogLevel { debug, info, warning, error }

typedef LogSink =
    void Function(LogLevel level, String message, StackTrace? stackTrace);

/// The app's only logging sink. Every message goes through
/// [LogFilters.redact]; release builds log errors only.
abstract final class AppLogger {
  static LogLevel? _minimumOverride;
  static LogSink? _sinkOverride;

  static LogLevel get _minimum =>
      _minimumOverride ?? (kReleaseMode ? LogLevel.error : LogLevel.debug);

  @visibleForTesting
  static void overrideForTesting({LogLevel? minimumLevel, LogSink? sink}) {
    _minimumOverride = minimumLevel;
    _sinkOverride = sink;
  }

  @visibleForTesting
  static void reset() => overrideForTesting();

  static void debug(String message) => _write(LogLevel.debug, message);

  static void info(String message) => _write(LogLevel.info, message);

  static void warning(String message) => _write(LogLevel.warning, message);

  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    _write(
      LogLevel.error,
      error == null ? message : '$message | $error',
      stackTrace,
    );
  }

  static void _write(LogLevel level, String message, [StackTrace? stack]) {
    if (level.index < _minimum.index) return;
    // Frames are code locations, not user data, so only the message is redacted.
    final safe = LogFilters.redact(message);
    (_sinkOverride ?? _defaultSink)(level, safe, stack);
  }

  // debugPrint, not dart:developer log: `flutter run` and logcat never show developer.log.
  static void _defaultSink(LogLevel level, String message, StackTrace? stack) {
    debugPrint('[grabby.${level.name}] $message');
    if (stack != null) debugPrint('$stack');
  }
}
