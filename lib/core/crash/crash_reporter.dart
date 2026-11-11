abstract interface class CrashReporter {
  /// True when the reporter installs its own uncaught-error handlers, so
  /// [CrashReporting.recordUncaught] must not forward to it a second time.
  bool get capturesUncaught;

  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    bool fatal = false,
  });

  Future<void> setUserId(String? id);
}
