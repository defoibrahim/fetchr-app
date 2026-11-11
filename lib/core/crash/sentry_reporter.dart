import 'package:sentry_flutter/sentry_flutter.dart';

import 'crash_reporter.dart';

class SentryReporter implements CrashReporter {
  // SentryFlutter.init installs its own error handlers.
  @override
  bool get capturesUncaught => true;

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
  }) async {
    await Sentry.captureException(
      error,
      stackTrace: stack,
      withScope: fatal ? (scope) => scope.level = SentryLevel.fatal : null,
    );
  }

  @override
  Future<void> setUserId(String? id) async {
    await Sentry.configureScope(
      (scope) => scope.setUser(id == null ? null : SentryUser(id: id)),
    );
  }
}
