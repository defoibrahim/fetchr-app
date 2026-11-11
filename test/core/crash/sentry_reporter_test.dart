import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/crash/sentry_reporter.dart';

void main() {
  group('SentryReporter', () {
    test('lets SentryFlutter.init own the uncaught handlers', () {
      expect(SentryReporter().capturesUncaught, isTrue);
    });

    // Sentry's hub is a no-op until SentryFlutter.init runs, so these only
    // prove the calls are safe before it does.
    test('records without throwing when Sentry is not initialised', () async {
      await SentryReporter().recordError(
        StateError('boom'),
        StackTrace.current,
      );
      await SentryReporter().recordError(StateError('boom'), null, fatal: true);
    });

    test('sets and clears the user without throwing', () async {
      await SentryReporter().setUserId('u1');
      await SentryReporter().setUserId(null);
    });
  });
}
