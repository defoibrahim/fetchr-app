import 'package:flutter_test/flutter_test.dart';
import 'package:grabby/core/errors/failure.dart';
import 'package:grabby/core/errors/result.dart';

void main() {
  const failure = ServerFailure(message: 'boom', code: 500);

  group('fold', () {
    test('calls onOk with the value', () {
      const Result<int> result = Ok(2);

      expect(result.fold((f) => -1, (v) => v * 10), 20);
    });

    test('calls onErr with the failure', () {
      const Result<int> result = Err(failure);

      expect(result.fold((f) => f.message, (v) => 'ok'), 'boom');
    });
  });

  group('accessors', () {
    test('Ok exposes its value and no failure', () {
      const Result<int> result = Ok(2);

      expect(result.isOk, isTrue);
      expect(result.valueOrNull, 2);
      expect(result.failureOrNull, isNull);
    });

    test('Err exposes its failure and no value', () {
      const Result<int> result = Err(failure);

      expect(result.isOk, isFalse);
      expect(result.valueOrNull, isNull);
      expect(result.failureOrNull, failure);
    });

    test('an Ok holding null still reads as Ok', () {
      const Result<int?> result = Ok(null);

      expect(result.isOk, isTrue);
      expect(result.valueOrNull, isNull);
    });
  });

  group('getOrThrow', () {
    test('returns the value of an Ok', () {
      const Result<int> result = Ok(2);

      expect(result.getOrThrow(), 2);
    });

    test('returns a null value of an Ok', () {
      const Result<int?> result = Ok(null);

      expect(result.getOrThrow(), isNull);
    });

    test('throws the failure of an Err', () {
      const Result<int> result = Err(failure);

      expect(result.getOrThrow, throwsA(same(failure)));
    });
  });

  group('map', () {
    test('transforms an Ok value', () {
      const Result<int> result = Ok(2);

      expect(result.map((v) => 'v$v'), const Ok('v2'));
    });

    test('leaves an Err untouched and never runs the transform', () {
      const Result<int> result = Err(failure);
      var called = false;

      final mapped = result.map((v) {
        called = true;
        return v;
      });

      expect(mapped, const Err<int>(failure));
      expect(called, isFalse);
    });
  });

  group('equality', () {
    test('Ok compares by value', () {
      expect(const Ok(1), const Ok(1));
      expect(const Ok(1), isNot(const Ok(2)));
      expect(const Ok([1, 2]), const Ok([1, 2]));
    });

    test('Err compares by failure', () {
      expect(const Err<int>(failure), const Err<int>(failure));
      expect(
        const Err<int>(failure),
        isNot(const Err<int>(ServerFailure(message: 'other'))),
      );
    });

    test('Ok and Err never equal each other', () {
      expect(const Ok<int>(1), isNot(const Err<int>(failure)));
    });
  });

  group('Failure', () {
    test('equality includes message, code and type', () {
      expect(const NetworkFailure(), const NetworkFailure());
      expect(const NetworkFailure('a'), isNot(const NetworkFailure('b')));
      expect(
        const ServerFailure(message: 'x', code: 400),
        isNot(const ServerFailure(message: 'x', code: 500)),
      );
      expect(const CacheFailure('x'), isNot(const UnexpectedFailure('x')));
    });

    test('UnauthorizedFailure carries 401', () {
      expect(const UnauthorizedFailure().code, 401);
    });
  });
}
