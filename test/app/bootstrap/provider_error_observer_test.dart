import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/app/bootstrap/provider_error_observer.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/logging/app_logger.dart';

final _bug = FutureProvider<int>(
  (_) async => throw StateError('boom'),
  retry: (_, _) => null,
);
final _failure = FutureProvider<int>(
  (_) async => throw const NetworkFailure(),
  retry: (_, _) => null,
);

void main() {
  late List<String> lines;

  setUp(() {
    lines = [];
    AppLogger.overrideForTesting(sink: (_, message, _) => lines.add(message));
  });
  tearDown(AppLogger.reset);

  ProviderContainer containerWithObserver() {
    final container = ProviderContainer(
      observers: const [ProviderErrorObserver()],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('an error that is not a Failure is recorded', () async {
    final container = containerWithObserver();

    container.listen(_bug, (_, _) {});
    await pumpEventQueue();

    expect(container.read(_bug).hasError, isTrue);
    expect(lines, ['Recorded error | Bad state: boom']);
  });

  test('a Failure is state, not a report', () async {
    final container = containerWithObserver();

    container.listen(_failure, (_, _) {});
    await pumpEventQueue();

    expect(container.read(_failure).error, const NetworkFailure());
    expect(lines, isEmpty);
  });
}
