import 'dart:async';

import '../crash/crash_reporting.dart';
import '../logging/app_logger.dart';
import 'failure.dart';
import 'failure_mapper.dart';
import 'result.dart';

Future<Result<T>> guard<T>(Future<T> Function() body) async {
  try {
    return Ok(await body());
  } catch (e, stack) {
    final known = knownFailure(e);
    if (known != null) {
      AppLogger.error('Guarded call failed', e, stack);
      return Err(known);
    }
    // A bug, not a failure the user can retry; AppLogger alone never reaches
    // Sentry. Not awaited: the caller gets its Err while the report sends.
    unawaited(CrashReporting.recordError(e, stack));
    return Err<T>(const UnexpectedFailure());
  }
}
