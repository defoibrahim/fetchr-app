import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/logging/app_logger.dart';

typedef _Entry = (LogLevel, String, StackTrace?);

void main() {
  final captured = <_Entry>[];
  final originalDebugPrint = debugPrint;

  void capture({LogLevel? minimumLevel}) => AppLogger.overrideForTesting(
    minimumLevel: minimumLevel,
    sink: (level, message, stack) => captured.add((level, message, stack)),
  );

  setUp(captured.clear);

  tearDown(() {
    AppLogger.reset();
    debugPrint = originalDebugPrint;
  });

  group('level filtering', () {
    test('passes every level by default outside release', () {
      capture();
      AppLogger.debug('d');
      AppLogger.info('i');
      AppLogger.warning('w');
      AppLogger.error('e');

      expect(captured.map((e) => e.$1), LogLevel.values);
    });

    test('drops messages below the minimum level', () {
      capture(minimumLevel: LogLevel.warning);
      AppLogger.debug('d');
      AppLogger.info('i');
      AppLogger.warning('w');
      AppLogger.error('e');

      expect(captured.map((e) => e.$2), ['w', 'e']);
    });

    test('an error-only minimum keeps just errors, as in release', () {
      capture(minimumLevel: LogLevel.error);
      AppLogger.warning('w');
      AppLogger.error('e');

      expect(captured.map((e) => e.$1), [LogLevel.error]);
    });
  });

  group('redaction', () {
    test('runs before the message reaches the sink', () {
      capture();
      AppLogger.info('login token: abc123');

      expect(captured.single.$2, 'login token: ***');
    });

    test('also covers the error object', () {
      capture();
      AppLogger.error('Failed', Exception('password=hunter2'));

      expect(captured.single.$2, 'Failed | Exception: password: ***');
    });
  });

  group('error formatting', () {
    test('appends the error to the message and forwards the stack', () {
      capture();
      final stack = StackTrace.current;
      AppLogger.error('Failed to save', StateError('boom'), stack);

      final (level, message, forwarded) = captured.single;
      expect(level, LogLevel.error);
      expect(message, 'Failed to save | Bad state: boom');
      expect(forwarded, same(stack));
    });

    test('without an error the message is untouched and the stack is null', () {
      capture();
      AppLogger.error('Directory is null');

      expect(captured.single.$2, 'Directory is null');
      expect(captured.single.$3, isNull);
    });
  });

  group('default sink', () {
    test('prints a level tagged line, then the stack for errors', () {
      final lines = <String?>[];
      debugPrint = (message, {wrapWidth}) => lines.add(message);
      final stack = StackTrace.current;

      AppLogger.error('Failed', StateError('boom'), stack);
      AppLogger.debug('hello');

      expect(lines, [
        '[grabby.error] Failed | Bad state: boom',
        '$stack',
        '[grabby.debug] hello',
      ]);
    });
  });

  test('reset restores the default sink and level', () {
    capture(minimumLevel: LogLevel.error);
    AppLogger.reset();
    final lines = <String?>[];
    debugPrint = (message, {wrapWidth}) => lines.add(message);

    AppLogger.debug('back to default');

    expect(captured, isEmpty);
    expect(lines, ['[grabby.debug] back to default']);
  });
}
