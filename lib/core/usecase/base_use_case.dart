import 'package:equatable/equatable.dart';

import '../errors/result.dart';

abstract interface class BaseUseCase<T, P> {
  Future<Result<T>> call(P params);
}

final class NoParams extends Equatable {
  const NoParams();

  @override
  List<Object?> get props => const [];
}
