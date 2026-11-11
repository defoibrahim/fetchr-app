import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/crash/crash_reporting.dart';
import '../../core/errors/failure.dart';

// Riverpod catches what a provider throws, so the zone hooks in bootstrap()
// never see it. A Failure is state the view shows; anything else is a bug.
final class ProviderErrorObserver extends ProviderObserver {
  const ProviderErrorObserver();

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    if (error is Failure) return;
    CrashReporting.recordError(error, stackTrace).ignore();
  }
}
