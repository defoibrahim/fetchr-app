import 'package:equatable/equatable.dart';

import 'failure.dart';

sealed class Result<T> extends Equatable {
  const Result();
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);

  final T value;

  @override
  List<Object?> get props => [value];
}

final class Err<T> extends Result<T> {
  const Err(this.failure);

  final Failure failure;

  @override
  List<Object?> get props => [failure];
}

extension ResultX<T> on Result<T> {
  R fold<R>(R Function(Failure failure) onErr, R Function(T value) onOk) =>
      switch (this) {
        Ok(:final value) => onOk(value),
        Err(:final failure) => onErr(failure),
      };

  bool get isOk => this is Ok<T>;

  T? get valueOrNull => switch (this) {
    Ok(:final value) => value,
    Err() => null,
  };

  Failure? get failureOrNull => switch (this) {
    Ok() => null,
    Err(:final failure) => failure,
  };

  T getOrThrow() => switch (this) {
    Ok(:final value) => value,
    Err(:final failure) => throw failure,
  };

  Result<R> map<R>(R Function(T value) transform) => switch (this) {
    Ok(:final value) => Ok(transform(value)),
    Err(:final failure) => Err(failure),
  };
}
